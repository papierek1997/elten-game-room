require_relative "support/settings_widget"

ids = EltenGameRoom::GAME_REGISTRY.ids
legacy_ids = GameRoomPreferences::LEGACY_WIDGET_GAME_IDS
added = ids - legacy_ids
raise "Migration must include the newer games" unless %w[rummy domino mexican_train scrabble taboo biblios battleship mancala krowa axel_pong].all? { |id| added.include?(id) }
copy = ->(value) { JSON.parse(JSON.generate(value)) }
legacy = {
  "lobby_games" => %w[uno], "announce_table_created" => true,
  "announce_player_joined" => false, "announce_player_left" => false,
  "announce_computer_changes" => false, "widget_games" => %w[makao],
  "widget_known_games" => ids, "widget_enabled" => false,
  "table_watch_games" => %w[uno], "table_watch_contacts_only" => true,
  "invitation_notifications" => "contacts", "sentinel" => "keep"
}
untouched = copy.call(legacy)
expected = ids.select { |id| (["uno"] + added).include?(id) }
migrated = GameRoomPreferences.normalize(legacy, ids)
assert(migrated["lobby_games"] == expected, "legacy lobby selection did not enable newly added games")
assert(migrated["lobby_known_games"].sort == ids.sort, "lobby migration did not record the catalogue")
assert(legacy == untouched, "migration changed its input")
(legacy.keys - ["lobby_games"]).each { |key| assert(migrated[key] == legacy[key], "lobby migration changed #{key}") }
assert(GameRoomPreferences.normalize(migrated, ids) == migrated, "lobby migration is not idempotent")
assert(GameRoomPreferences.defaults(ids)["lobby_games"] == ids, "fresh install missed default lobby games")
assert(GameRoomPreferences.defaults(ids)["lobby_known_games"] == ids, "fresh install did not remember lobby catalogue")
assert(GameRoomPreferences.normalize({}, ids)["lobby_games"] == ids, "missing selection did not enable all games")
assert(GameRoomPreferences.normalize(legacy.merge("lobby_games" => []), ids)["lobby_games"] == added,
  "legacy empty list should add only post-legacy games")

# Each channel has its own catalogue: an up-to-date widget must not suppress
# the one-time lobby upgrade or overwrite its independent choices.
assert(migrated["widget_games"] == ["makao"], "lobby changes reset widget opt-outs")
muted = GameRoomPreferences.normalize({"lobby_games" => [], "announce_lobby_changes" => false}, ids)
%w[created joined left bot_added bot_removed].each do |kind|
  assert(!GameRoomPreferences.lobby_announcement_enabled?(muted, kind, "axel_pong", ids), "migration unmuted #{kind}")
end
assert(GameRoomPreferences.lobby_announcement_enabled?(migrated, :created, "axel_pong", ids), "new game not announced")
assert(!GameRoomPreferences.lobby_announcement_enabled?(migrated, :joined, "axel_pong", ids), "join switch ignored")
assert(!GameRoomPreferences.lobby_announcement_enabled?(migrated, :created, "chess", ids), "old opt-out ignored")

# Remember manual choices, including an empty list, through restarts and two
# upgrades. Merely reordering or temporarily removing games is not an upgrade.
saved = copy.call(migrated)
saved["lobby_games"] -= %w[domino uno]
future_ids = ids + %w[future_game_a future_game_b]
future = GameRoomPreferences.normalize(saved, future_ids)
assert(future["lobby_games"] == saved["lobby_games"] + %w[future_game_a future_game_b], "future games not selected")
future["lobby_games"].delete("future_game_a")
restarted = GameRoomPreferences.normalize(copy.call(future), future_ids)
assert(!restarted["lobby_games"].include?("future_game_a"), "restart re-enabled manual opt-out")
following = GameRoomPreferences.normalize(restarted, future_ids + ["future_game_c"])
assert(following["lobby_games"] == restarted["lobby_games"] + ["future_game_c"], "second update reset choices")
assert(GameRoomPreferences.normalize(saved.merge("lobby_games" => []), future_ids)["lobby_games"] == %w[future_game_a future_game_b], "empty saved list treated as fresh defaults")
assert(GameRoomPreferences.normalize(following, (future_ids + ["future_game_c"]).reverse)["lobby_games"].sort == following["lobby_games"].sort, "sorting changed checks")
removed = GameRoomPreferences.normalize(saved, ids - ["domino"])
assert(!GameRoomPreferences.normalize(removed, ids)["lobby_games"].include?("domino"), "returning game lost its opt-out")
other = GameRoomPreferences.defaults(ids).merge("lobby_games" => ["domino"])
assert(GameRoomPreferences.normalize(other, future_ids)["lobby_games"] == %w[domino future_game_a future_game_b], "profiles are not independent")

class LobbyPreferenceApp < EltenGameRoom
  attr_reader :stored, :writes
  def initialize(values)
    @stored = JSON.parse(JSON.generate(values))
    @writes = 0
  end
  def read_json(path, default:)
    raise "unexpected read" unless path == "settings.json"
    JSON.parse(JSON.generate(@stored))
  end
  def update_json(path, default:)
    raise "unexpected write" unless path == "settings.json"
    @writes += 1
    @stored = yield(JSON.parse(JSON.generate(@stored)))
  end
  def run_network_task(*); yield; end
  def alert(*); end
  def self.contacts_settings_changed(*); end
  def self.table_watch_set_games(*); end
  def self.table_watch_repository
    Object.new.tap do |repo|
      def repo.load(*); ["uno"]; end
      def repo.save(*); raise "lobby changes must not change server subscriptions"; end
    end
  end
end

app = LobbyPreferenceApp.new(legacy)
20.times { assert(app.send(:game_room_settings, reload: true)["lobby_games"] == expected, "read missed lobby upgrade") }
assert(app.writes.zero? && app.stored == legacy, "lobby read wrote settings")
previous_wait = Form.instance_method(:wait)
driver = nil
Form.define_method(:wait) { driver.call(self) }
begin
  driver = lambda do |form|
    form.fields.first.index = form.fields.first.options.index('Lobby messages')
    form.fields.first.trigger(:move)
    list = form.fields.find { |field| field.is_a?(ListBox) && field.header == "Games covered by lobby messages" }
    assert(list && !form.hidden_controls.include?(list), "lobby list missing from Lobby messages")
    assert(list.game_indices.map { |index| ids[index] } == expected, "Settings displays stale lobby choices")
    list.instance_variable_get(:@selected)[ids.index("domino") + GameRoomScreens::GameList::ACTION_ROWS] = false
    form.accept_button.trigger(:press)
  end
  app.send(:show_settings)
  assert(app.writes == 1, "Settings did not save once")
  assert(!app.stored["lobby_games"].include?("domino"), "Save ignored deselection")
  assert((ids - app.stored["lobby_known_games"]).empty?, "Save lost lobby catalogue")
  assert(app.stored["widget_games"] == ["makao"] && app.stored["table_watch_games"] == ["uno"], "Save affected another channel")
  fresh_app = LobbyPreferenceApp.new(app.stored)
  assert(!fresh_app.send(:game_room_settings)["lobby_games"].include?("domino"), "restart undid saved choice")
  driver = ->(form) { form.cancel_button.trigger(:press) }
  cancelled = LobbyPreferenceApp.new(legacy)
  cancelled.send(:show_settings)
  assert(cancelled.writes.zero? && cancelled.stored == legacy, "Cancel persisted migration")

  # The form records every displayed game, even when opened with a legacy
  # value object. Otherwise normalization after Save rechecks manual opt-outs.
  driver = lambda do |form|
    list = form.fields.find { |field| field.is_a?(ListBox) && field.header == "Games covered by lobby messages" }
    list.instance_variable_get(:@selected)[ids.index("domino") + GameRoomScreens::GameList::ACTION_ROWS] = false
    form.accept_button.trigger(:press)
  end
  direct = GameRoomScreens::Settings.new(migrated.reject { |key, _| key == "lobby_known_games" },
    games: ids.map { |id| {id: id, name: id} }).wait
  assert(direct["lobby_known_games"].sort == ids.sort, "form did not record displayed lobby games")
  assert(!GameRoomPreferences.normalize(direct, ids)["lobby_games"].include?("domino"), "post-save normalization undid deselection")
ensure
  Form.define_method(:wait, previous_wait)
end
puts "PASS lobby defaults: legacy additions, future games, opt-outs, mute switches, UI Save/Cancel, independent channels/profiles and no read-time writes"
