require_relative "../../support/mille_bornes"
include MilleBornesTest

test("only enabled custom card counts block creation, without losing hidden edits") do
  game = Fixture.new.game
  groups = { "counterflow" => %w[counterflow end_counterflow],
    "include_safeties" => GameRoomGames::MilleBornes::SAFETIES,
    "include_instant_repairs" => %w[instant_repair] }
  groups.each do |flag, cards|
    cards.each do |type|
      [-1, 101, "invalid"].each do |invalid|
        key = "#{type}_cards"
        options = game.normalize_options("custom_deck" => true, flag => false, key => invalid)
        definition = game.option_definitions.find { |item| item.key == key }
        equal(false, game.option_visible?(definition, options), "inactive count hidden")
        equal(nil, game.options_error(options, player_count: 2), "hidden count must not block start")
        equal(0, game.deck_counts_for(options).fetch(type), "disabled cards absent")
        assert(game.options_error(options.merge(flag => true), player_count: 2), "re-enabled invalid count rejected")
        assert(options.key?(key), "hidden edit retained")
      end
    end
  end
  assert(game.options_error({"custom_deck" => true, "25_cards" => 101}), "active count still validated")
end

test("scores rank current totals, keep ties stable and announce each team once") do
  fixture = Fixture.new
  state = fixture.scenario
  state[:scores] = [100, 900, 500]
  state[:tracks][0][:miles] = 900
  replay = fixture.snapshot(state)
  text = fixture.game.shortcut_feature_data(:scores, replay, "Alice").fetch(:message)
  equal("Alice: 1000 points; Bob: 900 points; Carol: 500 points", text, "current round included")
  state[:tracks][0][:miles] = 400
  text = fixture.game.shortcut_feature_data(:scores, fixture.snapshot(state), "Alice").fetch(:message)
  equal("Bob: 900 points; Alice: 500 points; Carol: 500 points", text, "ties preserve seat order")
  team = Fixture.new(players: %w[Alice Bob Carol Dave], options: { "team_count" => 2 })
  state = team.scenario
  state[:scores] = [100, 900]
  text = team.game.shortcut_feature_data(:scores, team.snapshot(state), "Alice").fetch(:message)
  equal("Team 2: Bob, Dave: 900 points; Team 1: Alice, Carol: 100 points", text, "teams sorted once each")
end

test("disconnected status preserves game information and observer semantics") do
  fixture = Fixture.new
  replay = fixture.snapshot(fixture.scenario)
  status = fixture.game.participant_status(replay, "Alice", connected: true)
  equal("disconnected; #{status}", fixture.game.participant_status(replay, "Alice", connected: false), "connection included")
  equal(nil, fixture.game.participant_status(replay, "Observer", connected: true), "connected observer has no player status")
  equal("disconnected", fixture.game.participant_status(replay, "Observer", connected: false), "disconnected observer")
end

test("eight-player limit and one-second default are specific to Mille Bornes") do
  game = Fixture.new.game
  equal(8, game.maximum_players, "native capacity")
  equal(nil, game.options_error({}, player_count: 8), "eighth player supported")
  assert(game.options_error({}, player_count: 9), "ninth player rejected")
  equal(1, game.default_options.fetch("bot_delay"), "bot delay default")
  equal(0, game.normalize_options("bot_delay" => 0).fetch("bot_delay"), "explicit zero retained")
  equal(0, GameRoomGames::Base.new.default_bot_move_delay, "shared default unchanged")
end
