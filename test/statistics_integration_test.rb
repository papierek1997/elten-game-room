require_relative "support/settings_widget"
require_relative "support/host_source"
require File.join(EltenTestHost.root, "src/eapi/tasks")

module EltenAPI
  module Controls
    module WaitForItem; end
    class SpeechSequence; end
    class FormField < FakeControl
      def text_utf8(value); GameRoomContent.utf8(value); end
      def on(event, &handler)
        @handlers ||= {}
        super
      end
    end
  end
end
class ListBox
  def item_states; @item_states ||= {}; end
  def clear_item_audio; end
end
load File.join(EltenTestHost.root, "src/ui/controls/table_box.rb")
TableBox = EltenAPI::Controls.const_get(:TableBox)

class Form
  class << self
    attr_accessor :statistics_driver
  end
  def wait
    Form.statistics_driver.call(self)
  end
end

def loop_update; end

original_run = EltenAPI::Tasks.method(:run)
original_service = EltenGameRoom.method(:statistics_service)
original_today = GameRoomStatistics::Periods.method(:today)
today = Date.new(2026, 9, 25)
GameRoomStatistics::Periods.define_singleton_method(:today) { today }
tasks = []
tokens = []
EltenAPI::Tasks.define_singleton_method(:run) do |**options, &operation|
  tasks << options
  original_run.call(**options.merge(ui: :none)) do |progress, token|
    tokens << token
    operation.call(progress, token)
  end
end
ui_thread = Thread.current
reads = []
read_error = nil
cancel_read = nil
data = {"visitors" => 12, "players" => 8, "started" => 6, "completed" => 4,
  "first_day" => 20260920, "partial" => false, "games" => []}
store = Object.new
store.define_singleton_method(:years) do |today:, cancellation_token:|
  assert(Thread.current != ui_thread, "Statistics years were read on the UI thread")
  assert(cancellation_token.equal?(tokens.last), "Year discovery lost the task cancellation token")
  reads << [:years, today]
  raise read_error if read_error
  cancellation_token.cancel if cancel_read == :years
  [2025, 2026]
end
store.define_singleton_method(:report) do |period, cancellation_token:|
  assert(Thread.current != ui_thread, "Statistics report was read on the UI thread")
  assert(cancellation_token.equal?(tokens.last), "Report lost the task cancellation token")
  reads << [:report, period.key]
  raise read_error if read_error
  cancellation_token.cancel if cancel_read == :report
  data
end
service = Struct.new(:store).new(store)
service_reads = 0
EltenGameRoom.define_singleton_method(:statistics_service) { service_reads += 1; service }
app = EltenGameRoom.new
app.define_singleton_method(:run_network_task) { |*_args, **_options| raise "Statistics used the shared lobby task" }
app.define_singleton_method(:announce_server_table_access) { raise "Statistics changed the lobby access status" }
lobby_error = IOError.new("existing lobby error")
server_tables = Struct.new(:last_error).new(lobby_error)
app.instance_variable_set(:@server_tables, server_tables)
forms = []
Form.statistics_driver = lambda do |form|
  forms << form
  assert(form.is_a?(GameRoomUI::Form) && form.game_room_program.equal?(app), "Statistics menu lost its application form")
  assert(form.fields.first.text.include?("Visitors: 12"), "Statistics menu did not run the actual screen reader")
  table = form.fields.find { |field| field.is_a?(TableBox) }
  assert(table.rows.length == EltenGameRoom::GAME_REGISTRY.ids.length, "Statistics did not receive the full game registry")
  periods = form.fields.find { |field| field.instance_of?(ListBox) }
  assert(periods.options.include?("2025"), "Statistics did not use discovered calendar years")
  periods.index = 1
  periods.trigger(:move)
  refresh = form.fields.find { |field| field.is_a?(Button) && field.label == "Refresh" }
  refresh.trigger(:press)
  form.cancel_button.trigger(:press)
end
begin
  assert(app.respond_to?(:show_statistics, true), "Statistics menu has no screen implementation")
  app.send(:open_main_option, EltenGameRoom::MAIN_OPTIONS.index("Statistics"))
  assert(forms.length == 1, "Statistics menu did not open exactly one screen")
  assert(reads == [[:years, today], [:report, "today"], [:report, "last_7"], [:years, today], [:report, "last_7"]],
    "Statistics menu callbacks do not follow explicit screen reads")
  assert(tasks.length == reads.length && tasks.all? { |options| options[:cancellable] == true && !options[:title].to_s.empty? },
    "Statistics reads do not use cancellable host tasks")
  assert(service_reads == 1, "Statistics screen did not pin its account service")
  assert(server_tables.last_error.equal?(lobby_error), "Statistics changed the shared lobby error")
  [IOError.new("statistics offline"), EltenLink::Error.new("statistics denied")].each do |failure|
    read_error = failure
    Form.statistics_driver = lambda do |form|
      assert(form.fields.first.text.include?("Statistics are unavailable. Try Refresh."), "Read failures were presented as counts")
      assert(form.fields.first.text.include?("Calendar years are unavailable."), "Year read failure was hidden")
      assert(form.fields.find { |field| field.is_a?(TableBox) }.rows.empty?, "Read failure retained stale rows")
      form.cancel_button.trigger(:press)
    end
    app.send(:show_statistics)
    assert(server_tables.last_error.equal?(lobby_error), "A statistics failure poisoned the shared lobby error")
  end
  read_error = nil
  [:years, :report].each do |kind|
    cancel_read = kind
    before_tokens = tokens.length
    Form.statistics_driver = lambda do |form|
      summary = form.fields.first.text
      assert(summary.include?("Calendar years are unavailable.") == (kind == :years), "Cancelled year discovery was accepted")
      assert(summary.include?("Statistics are unavailable.") == (kind == :report), "Cancelled report was accepted")
      form.cancel_button.trigger(:press)
    end
    app.send(:show_statistics)
    assert(tokens.drop(before_tokens).any?(&:cancelled?), "The cancellation fixture did not cancel its native task")
    assert(server_tables.last_error.equal?(lobby_error), "Statistics cancellation changed the lobby error")
  end
  cancel_read = nil
  service = nil
  previous_reads = reads.dup
  Form.statistics_driver = lambda do |form|
    assert(form.fields.first.text.include?("Statistics are unavailable."), "Unavailable statistics service aborted the menu")
    form.cancel_button.trigger(:press)
  end
  app.send(:show_statistics)
  assert(reads == previous_reads, "An unavailable service made a statistics request")
ensure
  EltenAPI::Tasks.define_singleton_method(:run, original_run)
  EltenGameRoom.define_singleton_method(:statistics_service, original_service)
  GameRoomStatistics::Periods.define_singleton_method(:today, original_today)
end
puts "PASS statistics menu, actual screen and native task readers"
