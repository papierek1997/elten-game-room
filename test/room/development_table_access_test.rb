require_relative "../support/ui"

def assert(condition, message)
  raise message if !condition
end

module Session
  class << self
    attr_accessor :name
  end
end

class Program
  def self.server_app(**options)
    @server_app_uuid = options.fetch(:uuid)
  end

  def self.server_app_uuid
    @server_app_uuid
  end

  def server_app_uuid
    self.class.server_app_uuid
  end

  def developer_mode?
    raise "Access detection must not inspect developer_mode"
  end

  def author
    raise "Access detection must not special-case the author"
  end
end

module Log
  def self.warning(_message); end
  def self.debug(_message); end
end

module EltenLink
  class Error < StandardError
    attr_reader :code, :status

    def initialize(code, status: 403)
      @code = code
      @status = status
      super(code)
    end
  end

  class Client
    attr_accessor :error, :write_error
    attr_reader :calls

    def initialize
      @calls = []
      @rows = Hash.new { |hash, key| hash[key] = [] }
    end

    def request(table, operation, options)
      @calls << [table, operation, options]
      raise @error if @error
      raise @write_error if @write_error && operation != :select

      case operation
      when :select
        rows = @rows[table]
        rows = rows.select { |row| options[:where].all? { |key, value| row[key] == value } } if options[:where]
        rows.first(options.fetch(:limit, rows.length))
      when :insert
        row = options.merge("__id" => @rows[table].length + 1, "__insertion_user" => Session.name)
        @rows[table] << row
        row
      when :update
        @rows[table].find { |row| row["__id"] == options[:id] }.merge!(options[:values])
      end
    end
  end

  module Apps
    def self.table(client, _uuid, name)
      Object.new.tap do |table|
        table.define_singleton_method(:select) { |**options| client.request(name, :select, options) }
        table.define_singleton_method(:insert) { |values| client.request(name, :insert, values) }
        table.define_singleton_method(:update) { |id, values| client.request(name, :update, { id: id, values: values }) }
      end
    end
  end

  module Notifications; end
  module Contacts
    def self.list(_client)
      raise "Disabled invitation sending queried contacts"
    end
  end
  module Users
    def self.online(_client)
      raise "Disabled invitation sending queried online users"
    end
  end
end

module EltenAPI
  module Tasks
    class Cancelled < StandardError; end
    class Token
      def raise_if_cancelled!; end
    end
    class << self
      attr_accessor :cancel_next

      def run(**_options, &operation)
        if @cancel_next
          @cancel_next = false
          raise Cancelled
        end
        Thread.new { operation.call(nil, Token.new) }.value
      end
    end
  end
end

require_relative "../../__app"

# This headless host has no program runtime; publish the normal startup snapshot.
EltenGameRoom.remember_settings(EltenGameRoom::DEFAULT_SETTINGS)

class EmptyLiveEndpoint
  attr_reader :user
  def initialize(user)
    @user = user.to_s.dup.freeze
  end
  def sessions; []; end
  def on_invitation(&block); end
end

Session.name = "papierek"
client = EltenLink::Client.new
app = EltenGameRoom.new
# This headless access fixture has no storage Runtime. Native directory
# preparation is covered by host/local_directories_test, not the SDK probe.
app.define_singleton_method(:prepare_local_directories) { nil }
tables = GameRoomServerTables.new(app, client: client)
app.instance_variable_set(:@server_tables, tables)
GameRoomStartupUpdate.define_singleton_method(:check) { |_program| nil } # This test covers table access, not catalogue updates.
endpoint = EmptyLiveEndpoint.new(Session.name)
app.define_singleton_method(:live_sessions) { endpoint }
entries = []
app.define_singleton_method(:run_program_interface) { |current| entries << current }
alerts = []
ui_thread = Thread.current
app.define_singleton_method(:alert) do |message|
  assert(Thread.current == ui_thread, "A table access notice was shown from a worker")
  alerts << message
end
app.define_singleton_method(:confirm) { |_message| true }

# Even the author must use the server's answer, with no local identity exception.
client.error = EltenLink::Error.new("apps.tables.stamp_required")
app.program_main
assert(entries.length == 1, "Protected tables prevented reaching the interface")
assert(client.calls == [["game_room_users", :select, { where: { "username" => "papierek" }, limit: 1 }]], "Startup made more than the probe request")
assert(alerts.length == 1 && alerts.last.start_with?("The server requires an official launcher stamp"), "The restriction was not announced once")

menu_options = []
menu_actions = [:exit]
GameRoomScreens::MainMenu.define_singleton_method(:new) do |**options|
  menu_options << options
  result = GameRoomScreens::MenuResult.new(action: menu_actions.shift || :exit, index: 0)
  Object.new.tap { |menu| menu.define_singleton_method(:wait) { result } }
end
app.send(:show_main_menu)
assert(menu_options.last[:refresh] == nil, "The disabled lobby installed a polling callback")
3.times { app.send(:poll_lobby_activity, Object.new, Object.new) }
app.send(:load_lobby_history)
app.send(:register_game_room_user)
app.instance_variable_get(:@game_room_users).registered(["Bob"])
activity = app.instance_variable_get(:@table_activity)
activity.global_entries
activity.latest_global_id
assert(client.calls.length == 1, "A disabled optional feature queried a table")
assert(alerts.length == 1, "Maintenance repeated the development notice")

[:contacts, :online].each { |source| app.send(:show_invite_users, Object.new, source: source) }
assert(alerts.last(2).all? { |message| message.start_with?("Sending invitations is unavailable because the server requires an official launcher stamp") }, "Invitation sending did not explain the restriction")
menu_actions.replace([:invite_contacts, :exit])
app.send(:show_main_menu)
assert(alerts.last.start_with?("Sending invitations is unavailable because the server requires an official launcher stamp"), "The main menu did not explain the invitation restriction")
assert(client.calls.length == 1, "An invitation shortcut queried a protected table")

# Reusing the same instance must probe again and recover cached repository handles.
client.error = nil
Session.name = "Alice"
endpoint = EmptyLiveEndpoint.new(Session.name)
app.program_main
assert(entries.length == 2 && tables.available?, "The second main invocation did not recover access")
assert(client.calls.count { |table, operation, options| table == "game_room_users" && operation == :select && options[:limit] == 1 } == 2, "Main did not probe on every invocation")
assert(client.calls.any? { |table, operation, values| table == "game_room_users" && operation == :insert && values["username"] == "Alice" }, "Registration did not resume after recovery")
assert(app.send(:invitation_sending_available?), "Invitation sending remained disabled after recovery")
app.send(:show_main_menu)
assert(menu_options.last[:refresh].respond_to?(:call), "The available lobby did not enable history refresh")

# A later denial is shared with already-cached handles and announced from the UI.
client.write_error = EltenLink::Error.new("apps.tables.stamp_required")
app.send(:run_network_task, "Saving activity", silent: true) do
  activity.send(:persist_global_activity, { "__id" => 9, "owner" => "Alice", "game" => "spades" }, "created", "Alice")
end
assert(tables.stamp_required?, "A later ordinary write did not disable table access")
count = client.calls.length
notice_count = alerts.length
app.send(:register_game_room_user)
activity.global_entries
activity.latest_global_id
app.send(:poll_lobby_activity, Object.new, Object.new)
app.send(:run_network_task, "No table operation") { true }
assert(client.calls.length == count, "A cached repository sent requests after a late denial")
assert(alerts.length == notice_count, "A late denial was announced repeatedly")

# Other errors, including an unrelated 403, must not become a development diagnosis.
client.write_error = nil
%w[network_error timeout auth.unauthorized apps.tables.forbidden apps.tables.not_found api_error].each do |code|
  client.error = EltenLink::Error.new(code)
  before = client.calls.length
  app.program_main
  assert(client.calls.length == before + 1, "A failed probe was retried during the same launch")
  assert(!tables.available? && !tables.stamp_required?, "#{code} was mistaken for a development restriction")
  assert(alerts.last.start_with?("Server table access could not be checked."), "An unresolved access check was not explained")
  app.send(:show_invite_users, Object.new, source: :online)
  assert(alerts.last.start_with?("Sending invitations is unavailable because"), "An unrelated error was described as development mode")
end

# Notification entry cannot bypass the access check, even on an existing instance.
client.error = EltenLink::Error.new("apps.tables.stamp_required")
app.define_singleton_method(:load_pending_invitations) { nil }
notification = Struct.new(:sender, :metadata).new("Bob", { "invitation_id" => 1 })
2.times do
  before = client.calls.length
  assert(app.notification_action(:open_invitation, notification), "Notification entry did not complete")
  assert(client.calls.length == before + 1 && tables.stamp_required?, "Notification entry reused an earlier access decision")
end

# Cancelling before the worker starts must not retain the previous success.
client.error = nil
app.program_main
assert(tables.available?, "Access did not recover before cancellation test")
before = client.calls.length
EltenAPI::Tasks.cancel_next = true
app.program_main
assert(client.calls.length == before && !tables.available?, "Cancelling detection reused previous access")
assert(!tables.stamp_required?, "Cancellation was classified as development mode")

puts "Development table access tests passed: entry points, rechecks, notices, skipped queries and invitations"
