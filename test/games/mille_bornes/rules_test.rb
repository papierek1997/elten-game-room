require_relative "../../support/elten_array_shuffle"
require_relative "../../support/mille_bornes"
include MilleBornesTest

test("standard deck, explicit draw, determinism and rejected events") do
  fixture = Fixture.new
  game = fixture.game
  deck = game.send(:deck_for, game.default_options)
  equal(106, deck.length, "deck count")
  equal(106, deck.uniq.length, "physical card uniqueness")
  equal(GameRoomGames::MilleBornes::DECK_COUNTS, deck.group_by { |card| card.split(":").first }.transform_values(&:length), "card distribution")
  dealt = fixture.start
  equal([6, 6, 6], dealt.state[:hands].values.map(&:length), "initial hands")
  equal(:awaiting_draw, dealt.state[:phase], "draw is explicit")
  before = Marshal.dump(dealt.state)
  equal(:invalid, game.action_for({ "kind" => "card", "action" => "discard", "card" => dealt.state[:hands]["Alice"].first }, dealt, "Alice").first, "no play before draw")
  fixture.events.concat([
    event(2, "Bob", "draw"), event(3, "Alice", "draw", "extra"),
    event(4, "Mallory", "deal", "2|#{'f' * 32}"), event(5, "Alice", "unknown")
  ])
  equal(before, Marshal.dump(fixture.replay.state), "illegal events changed state")
  fixture.events.slice!(1..-1)
  drawn = fixture.act("Alice", { "kind" => "command", "action" => "draw" })
  equal(7, drawn.state[:hands]["Alice"].length, "draw to seven")
  card = drawn.state[:hands]["Alice"].last
  after = fixture.act("Alice", { "kind" => "card", "action" => "discard", "card" => card })
  equal(6, after.state[:hands]["Alice"].length, "discard to six")
  equal("Bob", after.current_player, "next player")
  equal(after.state, fixture.replay.state, "deterministic replay")
  repeated = game.replay(fixture.session, fixture.events + [fixture.events.last], fixture.repository)
  equal(after.state, repeated.state, "event deduplication")
end

test("exact finish, two 200 cards, stopped driving and speed limit") do
  fixture = Fixture.new
  state = fixture.scenario
  state[:hands]["Alice"] = %w[200:1 200:2 200:3 100:1 50:1 25:1]
  equal(:invalid, fixture.play(state, "Alice", "play", "200:1"), "must start driving")
  track = state[:tracks][0]
  track[:moving] = true
  track[:miles] = 850
  equal(:invalid, fixture.play(state, "Alice", "play", "200:1"), "cannot exceed 1000")
  track[:miles] = 0
  track[:speed_limit] = true
  equal(:invalid, fixture.play(state, "Alice", "play", "100:1"), "limit blocks 100")
  equal(:ok, fixture.play(state, "Alice", "play", "50:1"), "limit permits 50")
  state[:current_player] = "Alice"
  state[:phase] = :playing
  track[:speed_limit] = false
  track[:two_hundreds] = 2
  equal(:invalid, fixture.play(state, "Alice", "play", "200:1"), "third 200 blocked")
  track[:miles] = 975
  equal(:ok, fixture.play(state, "Alice", "play", "25:1"), "exact finish")
  equal(:round_complete, state[:phase], "finish immediately")
  equal(0, state[:round_winner], "winner unit")
  equal(1800, state[:scores][0], "1000 plus victory and shutout")
end

test("hazards, remedies and right of way") do
  fixture = Fixture.new
  %w[out_of_gas flat_tire accident].zip(%w[fuel spare_tire repairs]).each do |hazard, remedy|
    state = fixture.scenario
    state[:hands]["Alice"] = ["#{hazard}:1", "25:1"]
    state[:hands]["Bob"] = ["#{remedy}:1", "go:1", "25:2"]
    state[:tracks][1][:moving] = true
    equal(:ok, fixture.play(state, "Alice", "play", "#{hazard}:1", target: "1"), "hazard legal")
    equal(false, state[:tracks][1][:moving], "hazard stops")
    state[:phase] = :playing
    equal(:ok, fixture.play(state, "Bob", "play", "#{remedy}:1"), "matching remedy")
    equal(false, state[:tracks][1][:moving], "still needs green light")
    state[:phase] = :playing
    state[:current_player] = "Bob"
    equal(:ok, fixture.play(state, "Bob", "play", "go:1"), "green light restarts")
    assert(state[:tracks][1][:moving], "not moving after green light")
  end
  state = fixture.scenario
  state[:hands]["Alice"] = %w[right_of_way:1 25:1]
  state[:tracks][0][:hazards] = %w[stop flat_tire]
  state[:tracks][0][:speed_limit] = true
  equal(:ok, fixture.play(state, "Alice", "play", "right_of_way:1"), "safety legal")
  equal(%w[flat_tire], state[:tracks][0][:hazards], "right of way only removes stop")
  equal(false, state[:tracks][0][:moving], "other hazard still blocks")
  equal(false, state[:tracks][0][:speed_limit], "limit removed")
  state[:hands]["Alice"] << "spare_tire:1"
  state[:phase] = :playing
  equal(:ok, fixture.play(state, "Alice", "play", "spare_tire:1"), "fix remaining problem")
  assert(state[:tracks][0][:moving], "right of way removes need for green light")
  equal(100, fixture.game.participant_scores(fixture.snapshot(state))["Alice"], "immediate safety points")
end

test("attack accumulation and independent limit") do
  fixture = Fixture.new
  state = fixture.scenario
  state[:hands]["Alice"] = %w[stop:1 out_of_gas:1 speed_limit:1 25:1]
  equal(:invalid, fixture.play(state, "Alice", "play", "out_of_gas:1", target: "1"), "no attack on stopped car")
  equal(:ok, fixture.play(state, "Alice", "play", "speed_limit:1", target: "1"), "limit on stopped car")
  state[:current_player] = "Alice"
  state[:phase] = :playing
  state[:options]["accumulate_hazards"] = true
  equal(:ok, fixture.play(state, "Alice", "play", "out_of_gas:1", target: "1"), "accumulated gas")
  state[:current_player] = "Alice"
  state[:phase] = :playing
  equal(:ok, fixture.play(state, "Alice", "play", "stop:1", target: "1"), "accumulated red light")
  equal(%w[out_of_gas stop], state[:tracks][1][:hazards], "both blockers retained")
  state[:hands]["Alice"] << "out_of_gas:2"
  state[:current_player] = "Alice"
  state[:phase] = :playing
  equal(:invalid, fixture.play(state, "Alice", "play", "out_of_gas:2", target: "1"), "no duplicate hazard")
end

test("dirty trick restores movement, draws replacement and takes extra turn") do
  fixture = Fixture.new
  state = fixture.scenario
  state[:hands]["Alice"] = %w[stop:1 25:1]
  state[:hands]["Carol"] = %w[right_of_way:1 100:2 100:3 100:4 100:5 100:6]
  state[:tracks][2][:moving] = true
  state[:tracks][2][:miles] = 400
  equal(:ok, fixture.play(state, "Alice", "play", "stop:1", target: "2"), "attack Carol")
  before = fixture.snapshot(Marshal.load(Marshal.dump(state)))
  token = state[:reaction][:token]
  reaction = { "kind" => "card", "action" => "dirty_trick", "card" => "right_of_way:1", "reaction" => token }
  equal(["Carol", "Bob"], fixture.game.active_actors(before), "reacting bot considered before next draw")
  assert(fixture.game.concurrent_session_input?(before, before, reaction), "same pending attack allows concurrency")
  equal(:ok, fixture.play(state, "Carol", "dirty_trick", "right_of_way:1", reaction: token), "out of turn safety")
  assert(state[:tracks][2][:moving], "dirty trick restores prior movement")
  equal(400, state[:tracks][2][:miles], "distance preserved")
  equal(6, state[:hands]["Carol"].length, "safety replacement drawn")
  equal("Carol", state[:current_player], "reactor gets extra turn")
  equal(:awaiting_draw, state[:phase], "extra turn explicitly draws")
  equal(800, fixture.game.participant_scores(fixture.snapshot(state))["Carol"], "100 safety plus 300 dirty trick")
  equal(:ok, fixture.play(state, "Carol", "draw"), "extra turn draw")
  equal(7, state[:hands]["Carol"].length, "seven cards on extra turn")
  equal(:ok, fixture.play(state, "Carol", "play", "100:2"), "no green light required")
  equal("Alice", state[:current_player], "continues after reactor")
  assert(!fixture.game.concurrent_session_input?(before, fixture.snapshot(state), reaction), "expired reaction not concurrent")
end

test("dirty trick expires on draw or play and rejects wrong immunity") do
  [true, false].each do |with_draw|
    fixture = Fixture.new
    state = fixture.scenario
    state[:draw_pile] = [] unless with_draw
    state[:hands]["Alice"] = %w[stop:1 25:1]
    state[:hands]["Carol"] = %w[right_of_way:1 driving_ace:1]
    state[:tracks][2][:moving] = true
    fixture.play(state, "Alice", "play", "stop:1", target: "2")
    token = state[:reaction][:token]
    equal(:invalid, fixture.play(state, "Carol", "dirty_trick", "driving_ace:1", reaction: token), "wrong safety")
    equal(:invalid, fixture.play(state, "Carol", "dirty_trick", "right_of_way:1", reaction: "0:0"), "wrong reaction token")
    if with_draw
      fixture.play(state, "Bob", "draw")
    else
      fixture.play(state, "Bob", "discard", "75:1")
    end
    equal(:invalid, fixture.play(state, "Carol", "dirty_trick", "right_of_way:1", reaction: token), "window closes")
  end
end

test("empty deck continues without recycling; empty hand ends the round") do
  fixture = Fixture.new
  state = fixture.scenario
  state[:draw_pile] = []
  state[:discard] = %w[200:1]
  state[:hands]["Alice"] = %w[25:1 50:1]
  equal(:ok, fixture.play(state, "Alice", "discard", "25:1"), "discard without deck")
  equal(:playing, state[:phase], "no draw when pile empty")
  equal([], state[:draw_pile], "standard deck not recycled")
  state[:current_player] = "Alice"
  equal(:ok, fixture.play(state, "Alice", "discard", "50:1"), "last card")
  equal(:round_complete, state[:phase], "any empty hand ends round")
  equal(nil, state[:round_winner], "no distance winner")
  equal([0, 0, 0], state[:scores], "no bonuses on empty hand")
end

test("recycling is deterministic and uses only discarded cards") do
  fixture = Fixture.new(options: { "recycle_discard" => true })
  state = fixture.scenario
  state[:draw_pile] = []
  state[:discard] = %w[50:2 50:3 50:4]
  state[:spent] = %w[stop:1]
  state[:phase] = :awaiting_draw
  duplicate = Marshal.load(Marshal.dump(state))
  equal(:ok, fixture.play(state, "Alice", "draw"), "recycle draw")
  fixture.play(duplicate, "Alice", "draw")
  equal(state, duplicate, "deterministic recycling")
  equal(1, state[:recycle_count], "one recycle")
  equal([], state[:discard], "discard consumed")
  equal(%w[stop:1], state[:spent], "played cards remain out")
end

test("coronation, shutout, four safeties, match end and tie continuation") do
  fixture = Fixture.new(options: { "target_score" => 2000 })
  state = fixture.scenario
  state[:draw_pile] = []
  state[:hands]["Alice"] = %w[100:1 50:1]
  track = state[:tracks][0]
  track[:miles] = 900
  track[:moving] = true
  track[:safeties] = GameRoomGames::MilleBornes::SAFETIES.dup
  track[:dirty_tricks] = 1
  equal(:ok, fixture.play(state, "Alice", "play", "100:1"), "win")
  equal(3100, state[:scores][0], "all bonuses")
  equal("Alice", state[:winner], "match winner")
  equal(:finished, state[:phase], "match finished")
  tied = fixture.scenario
  tied[:hands]["Alice"] = %w[25:1]
  tied[:scores] = [2000, 2000, 0]
  fixture.play(tied, "Alice", "discard", "25:1")
  equal(nil, tied[:winner], "equal leaders continue")
end

test("counterflow uses the authorized four and six defaults and rejects invalid explicit counts") do
  fixture = Fixture.new
  assert(fixture.game.option_definitions.any? { |definition| definition.key == "counterflow" && definition.default == false }, "variant is opt-in")
  equal(nil, fixture.game.options_error({ "counterflow" => true }), "unspecified counts use authorized defaults")
  equal(nil, fixture.game.options_error({ counterflow: "true" }), "symbol-keyed variant uses defaults")
  enabled = Fixture.new(options: { "counterflow" => true })
  equal(:ok, enabled.game.action_for({ "kind" => "command", "action" => "deal" }, enabled.replay,
    enabled.players.first, context: enabled.context).first, "default variant can start")
  [true, 1, 2, "true", "1", "unknown", "", [], {}].each do |value|
    options = { "counterflow" => value }
    equal(nil, fixture.game.options_error(options), "raw enabled setting uses defaults")
    normalized = fixture.game.normalize_options(options)
    assert(normalized["counterflow"], "enabled marker must survive normalization")
    equal([4, 6], normalized.values_at("counterflow_cards", "end_counterflow_cards"), "canonical variant counts")
    equal(nil, fixture.game.options_error(normalized), "normalized setting validates")
    imported = fixture.game.options_from_json(JSON.generate(options))
    equal(normalized, imported, "imported setting keeps the same defaults")
  end
  [false, 0, "0", "false", "FALSE", nil].each do |value|
    equal(nil, fixture.game.options_error({ "counterflow" => value }), "explicitly disabled setting is safe")
  end
  assert(fixture.game.normalize_options({ "counterflow" => false, counterflow: true })["counterflow"], "conflicting keys cannot hide an enabled variant")
  [0, 21, "bad", 1.5].each do |count|
    assert(fixture.game.options_error({ "counterflow" => true, "counterflow_cards" => count }), "invalid explicit count is rejected")
  end
end

test("team layouts, shared tracks, independent hands and nine-player roster") do
  { 4 => [2], 6 => [2, 3], 8 => [2, 4], 9 => [3] }.each do |count, teams|
    teams.each do |team_count|
      players = Array.new(count) { |index| "Player#{index + 1}" }
      fixture = Fixture.new(players: players, options: { "team_count" => team_count })
      state = fixture.start.state
      equal(team_count, state[:tracks].length, "shared team tracks")
      equal(count, state[:hands].length, "separate hands")
      equal(count / team_count, fixture.game.team_size(state[:options], player_count: count), "team size")
      options = fixture.game.with_team_assignment(state[:options], players: players, seats: state[:seats])
      assert(fixture.game.prepared_team_assignment(options, players: players), "prepared roster retained")
    end
  end
  fixture = Fixture.new(players: %w[Alice Bob Carol Dave], options: { "team_count" => 2 })
  state = fixture.scenario
  state[:hands]["Alice"] = %w[stop:1 25:1]
  state[:tracks][0][:moving] = true
  equal(:invalid, fixture.play(state, "Alice", "play", "stop:1", target: "2"), "cannot attack teammate")
  equal(:ok, fixture.play(state, "Alice", "play", "25:1"), "team mileage")
  equal(25, fixture.game.participant_scores(fixture.snapshot(state))["Carol"], "teammate shares score")
end

test("every safety counters its hazard without clearing unrelated problems") do
  GameRoomGames::MilleBornes::PROTECTION.each do |hazard, safety|
    options = hazard == "counterflow" ? { "counterflow" => true, "counterflow_cards" => 1, "end_counterflow_cards" => 1 } : {}
    fixture = Fixture.new(options: options)
    state = fixture.scenario
    state[:options]["accumulate_hazards"] = true
    state[:hands]["Alice"] = ["#{hazard}:1", "25:1"]
    state[:hands]["Carol"] = ["#{safety}:1", "50:1"]
    track = state[:tracks][2]
    track[:moving] = true
    fixture.play(state, "Alice", "play", "#{hazard}:1", target: "2")
    token = state[:reaction][:token]
    equal(:ok, fixture.play(state, "Carol", "dirty_trick", "#{safety}:1", reaction: token), "#{hazard} dirty trick")
    restored = state[:tracks][2]
    assert(restored[:moving] && restored[:hazards].empty?, "#{hazard}: driving not restored")
    assert(!restored[:speed_limit], "#{hazard}: speed-limit track restored")
    assert(!restored[:counterflow], "#{hazard}: counterflow track restored")
    state[:hands]["Alice"] << "#{hazard}:2"
    state[:phase] = :playing
    state[:current_player] = "Alice"
    equal(:invalid, fixture.play(state, "Alice", "play", "#{hazard}:2", target: "2"), "#{safety} immunity")
  end
  fixture = Fixture.new(options: { "accumulate_hazards" => true })
  state = fixture.scenario
  state[:hands]["Alice"] = %w[accident:1 25:1]
  state[:hands]["Carol"] = %w[driving_ace:1 50:1]
  state[:tracks][2][:hazards] = %w[out_of_gas]
  fixture.play(state, "Alice", "play", "accident:1", target: "2")
  fixture.play(state, "Carol", "dirty_trick", "driving_ace:1", reaction: state[:reaction][:token])
  equal(%w[out_of_gas], state[:tracks][2][:hazards], "unrelated older hazard retained")
  equal(false, state[:tracks][2][:moving], "older hazard still blocks")
end

test("teammate can react using their own hand and owns the extra turn") do
  fixture = Fixture.new(players: %w[Alice Bob Carol Dave], options: { "team_count" => 2 })
  state = fixture.scenario
  state[:hands]["Alice"] = %w[speed_limit:1 25:1]
  state[:hands]["Dave"] = %w[right_of_way:1 50:1]
  fixture.play(state, "Alice", "play", "speed_limit:1", target: "1")
  token = state[:reaction][:token]
  equal(:invalid, fixture.play(state, "Bob", "dirty_trick", "right_of_way:1", reaction: token), "cannot borrow teammate's card")
  equal(:ok, fixture.play(state, "Dave", "dirty_trick", "right_of_way:1", reaction: token), "teammate reacts")
  equal("Dave", state[:current_player], "card owner gets turn")
  equal(400, fixture.game.participant_scores(fixture.snapshot(state))["Bob"], "team shares reaction points")
end

test("empty-pile dirty trick and all safety extra turns respect hand size") do
  fixture = Fixture.new
  state = fixture.scenario
  state[:draw_pile] = []
  state[:hands]["Alice"] = %w[stop:1 25:1]
  state[:hands]["Carol"] = %w[right_of_way:1 50:1]
  state[:tracks][2][:moving] = true
  fixture.play(state, "Alice", "play", "stop:1", target: "2")
  equal(:ok, fixture.play(state, "Carol", "dirty_trick", "right_of_way:1", reaction: state[:reaction][:token]), "empty deck reaction")
  equal(["50:1"], state[:hands]["Carol"], "no invented replacement")
  equal(:playing, state[:phase], "extra play without draw")
  GameRoomGames::MilleBornes::SAFETIES.each do |safety|
    normal = fixture.scenario
    normal[:hands]["Alice"] = ["#{safety}:1"] + Array.new(6) { |index| "100:#{index + 1}" }
    fixture.play(normal, "Alice", "play", "#{safety}:1")
    equal(6, normal[:hands]["Alice"].length, "normal safety leaves six")
    equal("Alice", normal[:current_player], "extra turn belongs to safety player")
    fixture.play(normal, "Alice", "draw")
    equal(7, normal[:hands]["Alice"].length, "normal extra turn draws to seven")
  end
end
