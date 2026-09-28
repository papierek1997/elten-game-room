require_relative "support/settings_widget"

current_ids = EltenGameRoom::GAME_REGISTRY.ids
new_2_0 = %w[rummy domino mexican_train scrabble taboo biblios]
old_ids = GameRoomPreferences::LEGACY_WIDGET_GAME_IDS
new_since_legacy = current_ids - old_ids
raise "Release migration fixture must cover six new games" unless new_2_0.all? { |id| current_ids.include?(id) } && old_ids.length == 17

legacy = {
  "widget_games" => %w[uno makao], "widget_enabled" => false,
  "widget_show_unavailable" => true, "lobby_games" => %w[uno],
  "lobby_known_games" => current_ids,
  "table_watch_games" => [], "invitation_notifications" => "contacts",
  "custom_setting" => "preserve me"
}
original = Marshal.load(Marshal.dump(legacy))
migrated = GameRoomPreferences.normalize(legacy, current_ids)
expected = current_ids.select { |id| (%w[uno makao] + new_since_legacy).include?(id) }
assert(migrated["widget_games"] == expected, "legacy widget selection did not enable the six games added in 2.0")
assert(legacy == original, "normalizing preferences mutated the saved input")
%w[widget_enabled widget_show_unavailable lobby_games table_watch_games invitation_notifications custom_setting].each do |key|
  assert(migrated[key] == legacy[key], "widget migration changed #{key}")
end
assert((current_ids - migrated["widget_known_games"]).empty?, "migration did not remember existing games")
assert(GameRoomPreferences.normalize(migrated, current_ids) == migrated, "migration is not idempotent")

# The user explicitly approved this one-off upgrade even when the old
# selection was empty; old games remain off, and a disabled widget stays off.
empty = GameRoomPreferences.normalize(legacy.merge("widget_games" => []), current_ids)
assert(empty["widget_games"].sort == new_since_legacy.sort && empty["widget_enabled"] == false, "empty legacy selection lost the agreed upgrade")
assert(GameRoomPreferences.defaults(current_ids)["widget_games"] == current_ids, "new installation lost default games")
fresh_old = GameRoomPreferences.defaults(old_ids)
assert(GameRoomPreferences.normalize(fresh_old, current_ids)["widget_games"] == current_ids, "a fresh older installation missed newly registered games")

before_new_boards = current_ids - %w[battleship mancala]
existing_229 = GameRoomPreferences.defaults(before_new_boards).merge("widget_games" => %w[uno])
assert(GameRoomPreferences.normalize(existing_229, current_ids)["widget_games"].sort == %w[uno battleship mancala].sort,
  "new board games did not migrate independently of build number or old opt-outs")

# Subsequent releases need no per-game allowlist edit. Explicit deselection
# is honoured even for one of the six games enabled by the legacy migration.
saved = JSON.parse(JSON.generate(migrated.merge("widget_games" => migrated["widget_games"] - %w[domino uno])))
assert(!GameRoomPreferences.normalize(saved, current_ids)["widget_games"].include?("domino"), "migration re-enabled a manually unchecked game")
future_ids = current_ids + %w[future_game_a future_game_b]
all_unchecked = migrated.merge("widget_games" => [])
assert(GameRoomPreferences.normalize(all_unchecked, future_ids)["widget_games"] == %w[future_game_a future_game_b], "new games were confused with a previously cleared selection")
future = GameRoomPreferences.normalize(saved, future_ids)
assert(future["widget_games"] == saved["widget_games"] + %w[future_game_a future_game_b], "future games were not enabled by default")
future["widget_games"].delete("future_game_a")
after_restart = GameRoomPreferences.normalize(JSON.parse(JSON.generate(future)), future_ids)
assert(!after_restart["widget_games"].include?("future_game_a"), "restart re-enabled a manually unchecked new game")
following = GameRoomPreferences.normalize(after_restart, future_ids + ["future_game_c"])
assert(following["widget_games"] == after_restart["widget_games"] + ["future_game_c"], "a second update reset previous choices")
reordered = GameRoomPreferences.normalize(following, (future_ids + ["future_game_c"]).reverse)
assert(reordered["widget_games"].sort == following["widget_games"].sort, "game list ordering changed selections")

# The opposite choice on another local profile remains independent.
other = GameRoomPreferences.defaults(current_ids).merge("widget_games" => ["domino"])
assert(GameRoomPreferences.normalize(other, future_ids)["widget_games"] == %w[domino future_game_a future_game_b], "profile choices were replaced by another profile's selection")
assert(saved["widget_games"] == migrated["widget_games"] - %w[domino uno], "another migration mutated a profile")

class Form
  class << self
    attr_accessor :widget_settings_driver
  end
  alias_method :wait_without_widget_settings_driver, :wait
  def wait
    wait_without_widget_settings_driver
    Form.widget_settings_driver.call(self)
  end
end

class WidgetPreferenceApp < EltenGameRoom
  attr_reader :stored, :writes, :notices
  def initialize(values)
    @stored = Marshal.load(Marshal.dump(values))
    @writes, @notices = 0, []
  end
  def read_json(_path, default:); Marshal.load(Marshal.dump(@stored || default)); end
  def update_json(_path, default:)
    @writes += 1
    @stored = yield(Marshal.load(Marshal.dump(@stored || default)))
  end
  def run_network_task(*); yield; end
  def alert(message); @notices << message; end
  def self.table_watch_repository
    Object.new.tap do |repository|
      repository.define_singleton_method(:load) { |_| [] }
      repository.define_singleton_method(:save) { |*| raise "widget change wrote notification subscriptions" }
    end
  end
  def self.table_watch_set_games(_); end
end

app = WidgetPreferenceApp.new(legacy)
20.times do
  assert(app.send(:game_room_settings, reload: true)["widget_games"] == expected, "widget reads missed migrated games")
end
assert(app.writes.zero? && app.stored == legacy, "widget refresh caused disk writes")

Form.widget_settings_driver = lambda do |form|
  list = form.fields.find { |field| field.is_a?(ListBox) && field.header == "Games shown on the main screen" }
  assert(list != nil, "widget game list is missing")
  assert(list.game_indices.map { |index| current_ids[index] } == expected, "Settings displayed stale game selections")
  # FakeControl's test helper only selects entries; clear the fake mask to
  # simulate unchecking a row without adding an API to the real control.
  list.instance_variable_get(:@selected)[current_ids.index("domino") + GameRoomScreens::GameList::ACTION_ROWS] = false
  form.accept_button.trigger(:press)
end
app.send(:show_settings)
assert(app.writes == 1, "Save did not perform one settings write")
assert(!app.stored["widget_games"].include?("domino"), "Save ignored manual deselection")
assert((current_ids - app.stored["widget_known_games"]).empty?, "Save lost known game IDs")
new_instance = WidgetPreferenceApp.new(app.stored)
assert(!new_instance.send(:game_room_settings, reload: true)["widget_games"].include?("domino"), "new application instance undid saved deselection")

cancelled = WidgetPreferenceApp.new(legacy)
Form.widget_settings_driver = ->(form) { form.cancel_button.trigger(:press) }
cancelled.send(:show_settings)
assert(cancelled.writes.zero? && cancelled.stored == legacy, "Cancel persisted migration or selections")
puts "PASS widget defaults: six-game legacy upgrade, future additions, saved opt-outs, separate profiles, settings form, no read-time writes and Cancel"
