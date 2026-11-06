require_relative "../support/ui"

class Program
  def self.server_app(**options); @server_app_uuid = options.fetch(:uuid); end
  def self.server_app_uuid; @server_app_uuid; end
  def self.app_runtime; nil; end
end
module Session
  def self.name; "Alice"; end
end
require_relative "../../__app"

def assert(condition, message)
  raise message unless condition
end

repository = Object.new
repository.define_singleton_method(:load) { |_user| [] }
EltenGameRoom.define_singleton_method(:table_watch_repository) { repository }
EltenGameRoom.define_singleton_method(:table_watch_set_games) { |_games| nil }
EltenGameRoom.define_singleton_method(:contacts_settings_changed) { |_values| nil }
response = nil
GameRoomScreens::Settings.define_singleton_method(:new) do |*_arguments, **_options|
  Struct.new(:result) do
    def wait; result; end
    def table_watch_baseline; []; end
  end.new(response)
end
stored = { "interface_language" => "en", "known_languages" => ["en"], "table_presets" => ["keep"], "unrelated" => "keep" }
writes = 0
messages = []
program = EltenGameRoom.allocate
program.define_singleton_method(:game_room_settings) { |**_options| stored.dup }
program.define_singleton_method(:run_network_task) { |*_arguments, &operation| operation.call }
program.define_singleton_method(:alert) { |message| messages << message }
program.define_singleton_method(:update_json) do |path, default:, &operation|
  raise "unexpected settings destination" unless path == "settings.json"
  writes += 1
  stored = operation.call(stored.dup)
end
program.send(:show_settings)
assert(writes == 0 && messages.empty?, "cancelling language settings wrote preferences")
response = stored.merge("interface_language" => "pl", "known_languages" => %w[pl en], "table_watch_games" => [])
program.send(:show_settings)
assert(writes == 1 && stored["interface_language"] == "pl" && stored["known_languages"] == %w[en pl], "language choices did not reach local settings.json")
assert(stored["table_presets"] == ["keep"] && stored["unrelated"] == "keep", "language saving erased unrelated settings")
assert(GameRoomLocalization.primary_language == "en", "saving switched only part of the running interface")
assert(messages.last == "Settings saved. Close ELTEN completely and start it again to apply the interface language preferences. Restarting with F12 does not reload Power Games.", "language changes did not distinguish a full restart from F12")
response = stored.merge("table_watch_games" => [])
program.send(:show_settings)
assert(messages.last == "Settings saved.", "unchanged languages requested another restart")
puts "Local language save, cancellation, retained preferences and restart notice passed"
