require_relative "../../support/elten_array_shuffle"
require_relative "../../support/mille_bornes"
include MilleBornesTest

REPAIR_OPTIONS = { "include_instant_repairs" => true, "counterflow" => true,
  "counterflow_cards" => 4, "end_counterflow_cards" => 6, "accumulate_hazards" => true }.freeze

test("instant repair consumes one card and one turn for each ordinary problem") do
  %w[stop out_of_gas flat_tire accident speed_limit counterflow go].each do |problem|
    fixture = Fixture.new(options: REPAIR_OPTIONS)
    state = fixture.scenario
    state[:hands]["Alice"] = %w[instant_repair:1 100:1]
    track = state[:tracks][0]
    case problem
    when "speed_limit", "counterflow"
      track.merge!(moving: true, problem.to_sym => true)
    when "go"
      track[:moving] = false
    else
      track[:hazards] = [problem]
    end
    before_pile = state[:draw_pile].dup
    selection = { "kind" => "card", "action" => "play", "card" => "instant_repair:1", "problem" => problem }
    equal(selection, fixture.game.send(:normalize_selection, { "kind" => "card", "action" => "select",
      "card" => fixture.game.send(:surface_value, selection) }), "surface selection round trip")
    equal(selection, fixture.game.send(:selection_from_event, event(90, "Alice", "play", "instant_repair:1|#{problem}")), "event problem round trip")
    equal(:ok, fixture.play(state, "Alice", "play", "instant_repair:1", problem: problem), "valid repair #{problem}")
    equal([], track[:hazards], "single hazard removed")
    assert(!track[:speed_limit] && !track[:counterflow], "independent flags cleared when chosen")
    equal(%w[100:1], state[:hands]["Alice"], "one physical card consumed")
    equal(["instant_repair:1"], state[:spent], "joker spent, not recycled as discard")
    equal(before_pile, state[:draw_pile], "no bonus draw")
    equal("Bob", state[:current_player], "normal next turn")
    equal([], track[:safeties], "no permanent protection")
    equal(0, track[:dirty_tricks], "no dirty trick bonus")
    equal(0, fixture.game.send(:round_points, track), "no points for the joker")
    expected_moving = %w[stop speed_limit counterflow go].include?(problem)
    equal(expected_moving, track[:moving], "ordinary green-light requirement preserved")
  end
end

test("one repair never clears the other accumulated problems") do
  %w[stop out_of_gas flat_tire accident speed_limit counterflow].each do |problem|
    fixture = Fixture.new(options: REPAIR_OPTIONS)
    state = fixture.scenario
    state[:hands]["Alice"] = %w[instant_repair:1 100:1]
    track = state[:tracks][0]
    original_hazards = %w[stop out_of_gas flat_tire accident]
    track.merge!(hazards: original_hazards.dup, speed_limit: true, counterflow: true)
    opponents = Marshal.dump(state[:tracks].drop(1))
    equal(:ok, fixture.play(state, "Alice", "play", "instant_repair:1", problem: problem), "stacked repair")
    equal(original_hazards - [problem], track[:hazards], "other main hazards remain")
    equal(problem != "speed_limit", track[:speed_limit], "speed limit independent")
    equal(problem != "counterflow", track[:counterflow], "counterflow independent")
    assert(!track[:moving], "remaining hazards still stop driving")
    equal(opponents, Marshal.dump(state[:tracks].drop(1)), "opponents unaffected")
  end
end

test("instant repair is not a safety or a free out-of-turn response") do
  fixture = Fixture.new(options: REPAIR_OPTIONS)
  state = fixture.scenario
  state[:hands]["Alice"] = %w[instant_repair:1 100:1]
  state[:tracks][0].merge!(moving: true)
  equal(["discard"], fixture.game.legal_actions(fixture.snapshot(state), "Alice").select { |entry| entry["card"] == "instant_repair:1" }.map { |entry| entry["action"] }, "no action on a healthy moving car")
  state[:tracks][0][:hazards] = ["accident"]
  state[:tracks][0][:moving] = false
  state[:current_player] = "Bob"
  state[:reaction] = { unit: 0, hazard: "accident", token: "1:7", before: fixture.game.send(:fresh_track) }
  equal([], fixture.game.legal_actions(fixture.snapshot(state), "Alice"), "joker cannot dirty-trick an attack")
  state[:current_player] = "Alice"
  state[:phase] = :awaiting_draw
  equal(:invalid, fixture.play(state, "Alice", "play", "instant_repair:1", problem: "accident"), "draw still required")
  state[:phase] = :playing
  state[:options]["include_instant_repairs"] = false
  equal(:invalid, fixture.play(state, "Alice", "play", "instant_repair:1", problem: "accident"), "disabled variant rejects fabricated joker")
end

test("invalid, missing, stale and foreign problem choices cannot mutate the game") do
  fixture = Fixture.new(options: REPAIR_OPTIONS)
  state = fixture.scenario
  state[:hands]["Alice"] = %w[instant_repair:1 100:1]
  state[:tracks][0][:hazards] = ["flat_tire"]
  original = Marshal.dump(state)
  [nil, "accident", "driving_ace", "", "flat_tire|extra", "0"].each do |problem|
    details = problem == nil ? {} : { problem: problem }
    equal(:invalid, fixture.play(state, "Alice", "play", "instant_repair:1", **details), "invalid problem #{problem.inspect}")
    equal(original, Marshal.dump(state), "rejected choice is read-only")
  end
  equal(:invalid, fixture.play(state, "Alice", "play", "instant_repair:1", problem: "flat_tire", target: "1"), "cannot target an opponent")
  equal(:invalid, fixture.play(state, "Bob", "play", "instant_repair:1", problem: "flat_tire"), "cannot use another hand")
  assert(!fixture.game.send(:apply_event, state, event(91, "Alice", "play", "instant_repair:1|flat_tire|extra"), "Alice", 91, []), "malformed persisted choice rejected")
  state[:tracks][0].merge!(moving: true, hazards: [])
  equal(:invalid, fixture.play(state, "Alice", "play", "instant_repair:1", problem: "flat_tire"), "stale choice rejected after recovery")
end

test("teams share the repaired track and right of way keeps its normal effect") do
  fixture = Fixture.new(players: %w[Alice Bob Carol David], options: REPAIR_OPTIONS.merge("team_count" => 2))
  state = fixture.scenario
  state[:hands]["Alice"] = %w[instant_repair:1 100:1]
  own_unit = fixture.game.send(:unit_for, state, "Alice")
  track = state[:tracks][own_unit]
  track.merge!(hazards: ["out_of_gas"], safeties: ["right_of_way"])
  equal(:ok, fixture.play(state, "Alice", "play", "instant_repair:1", problem: "out_of_gas"), "team repair")
  assert(track[:moving], "right of way restarts after last mechanical problem")
  teammate = state[:players].find { |player| player != "Alice" && fixture.game.send(:unit_for, state, player) == own_unit }
  assert(fixture.game.legal_actions(fixture.snapshot(state), teammate).none? { |entry| entry["card"] == "instant_repair:1" }, "teammate cannot replay the consumed physical card")
end

test("bots retain a useful joker but prefer a matching ordinary remedy") do
  fixture = Fixture.new(options: REPAIR_OPTIONS)
  state = fixture.scenario
  state[:hands]["Alice"] = %w[instant_repair:1 spare_tire:1 100:1]
  state[:tracks][0][:hazards] = ["flat_tire"]
  replay = fixture.snapshot(state)
  actions = fixture.game.legal_actions(replay, "Alice")
  chosen = actions.max_by { |entry| fixture.game.bot_action_score(replay, "Alice", entry) }
  equal("spare_tire:1", chosen["card"], "ordinary remedy preserves the joker")
  state[:hands]["Alice"].delete("spare_tire:1")
  replay = fixture.snapshot(state)
  chosen = fixture.game.legal_actions(replay, "Alice").max_by { |entry| fixture.game.bot_action_score(replay, "Alice", entry) }
  equal("flat_tire", chosen["problem"], "joker chosen when ordinary remedy unavailable")
  alternative = Marshal.load(Marshal.dump(state))
  alternative[:hands]["Bob"] = %w[right_of_way:1 driving_ace:1]
  alternative[:draw_pile].reverse!
  other = fixture.snapshot(alternative)
  actions = fixture.game.legal_actions(replay, "Alice")
  equal(actions.map { |entry| fixture.game.bot_action_score(replay, "Alice", entry) },
    actions.map { |entry| fixture.game.bot_action_score(other, "Alice", entry) }, "joker heuristic never peeks at hidden cards")
end
