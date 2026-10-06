require_relative "../../support/elten_array_shuffle"
require_relative "../../support/mille_bornes"
include MilleBornesTest

COUNTERFLOW_OPTIONS = { "counterflow" => true, "counterflow_cards" => 3, "end_counterflow_cards" => 4 }.freeze

test("counterflow counts preserve legacy options and are edited only in custom decks") do
  game = Fixture.new.game
  defaults = game.normalize_options(game.default_options)
  equal(false, defaults["counterflow"], "variant disabled by default")
  %w[counterflow_cards end_counterflow_cards].each do |key|
    assert(!defaults.key?(key), "disabled normalization excludes #{key}")
    definition = game.option_definitions.find { |item| item.key == key }
    equal(:integer, definition.kind, "integer count editor")
    equal(key == "counterflow_cards" ? 4 : 6, definition.default, "authorized fallback follows speed limit and its remedy")
    assert(!game.option_visible?(definition, defaults), "count hidden while disabled")
    assert(!game.option_visible?(definition, COUNTERFLOW_OPTIONS), "normal counterflow remains a checkbox")
    assert(game.option_visible?(definition, COUNTERFLOW_OPTIONS.merge("custom_deck" => true)), "count visible in enabled custom variant")
  end
  [false, 0, "0", "false", "FALSE", nil].each do |disabled|
    options = COUNTERFLOW_OPTIONS.merge("counterflow" => disabled)
    equal(JSON.generate(defaults), JSON.generate(game.normalize_options(options)), "baseline option values and order unchanged")
    equal(nil, game.options_error(options), "disabled counts ignored")
  end
  [1, 20].product([1, 20]).each do |attacks, remedies|
    options = { counterflow: true, counterflow_cards: attacks.to_s, end_counterflow_cards: remedies.to_s }
    equal(nil, game.options_error(options), "both inclusive bounds accepted")
    normalized = game.normalize_options(options)
    equal(attacks, normalized["counterflow_cards"], "attack count normalized")
    equal(remedies, normalized["end_counterflow_cards"], "remedy count normalized")
    equal(normalized, game.normalize_options(normalized), "normalization idempotent")
    equal(normalized, game.options_from_json(JSON.generate(normalized)), "counts survive option serialization")
  end
  errors = {
    "counterflow_cards" => "Enter the number of counterflow cards (an integer from 1 to 20) to enable counterflow.",
    "end_counterflow_cards" => "Enter the number of end of counterflow cards (an integer from 1 to 20) to enable counterflow."
  }
  errors.each do |key, message|
    [nil, false, true, -1, 0, 21, 1.5, "1.5", "", "bad", "NaN", "Infinity", "1e1", "0x10", "1\0",
      "9" * 256, [], [1], {}, { "count" => 1 }].each do |invalid|
      options = COUNTERFLOW_OPTIONS.merge(key => invalid)
      equal(message, game.options_error(options), "specific validation for #{key}=#{invalid.inspect}")
      equal(message, game.options_error(game.normalize_options(options)), "invalid count survives normalization as an error")
      fixture = Fixture.new(options: options)
      status, = game.action_for({ "kind" => "command", "action" => "deal" }, fixture.replay, "Alice", context: fixture.context)
      equal(:invalid, status, "invalid count cannot create a deal")
      fixture.events << event(1, "Alice", "deal", "1|#{'0' * 32}")
      equal([], fixture.replay.accepted_events, "invalid imported deal rejected")
    end
  end
  assert(game.options_summary(COUNTERFLOW_OPTIONS).include?("Counterflow: 3 attack cards and 4 remedy cards"), "explicit counts announced")
  assert(!game.options_summary(defaults).include?("Counterflow"), "baseline summary unchanged")
  %w[counterflow counterflow_cards end_counterflow_cards].each do |key|
    assert(game.notification_option_keys(COUNTERFLOW_OPTIONS).include?(key), "variant announced to joining players")
  end
end

test("configured cards extend the unchanged standard deterministic deck") do
  game = Fixture.new.game
  standard = game.send(:deck_for, game.default_options)
  equal(106, standard.length, "standard size unchanged")
  [1, 20].product([1, 20]).each do |attacks, remedies|
    options = COUNTERFLOW_OPTIONS.merge("counterflow_cards" => attacks, "end_counterflow_cards" => remedies)
    fixture = Fixture.new(options: options)
    deck = game.send(:deck_for, options)
    equal(standard, deck.first(106), "standard distribution and pre-shuffle order unchanged")
    equal(106 + attacks + remedies, deck.length, "configured counts added")
    equal(deck.length, deck.uniq.length, "physical cards remain unique")
    equal(Array.new(attacks) { |index| "counterflow:#{index + 1}" } +
      Array.new(remedies) { |index| "end_counterflow:#{index + 1}" }, deck.drop(106), "stable variant card IDs")
    replay = fixture.start
    shuffled = GameRoomRandom.shuffle(deck, random: Random.new(replay.state[:seed].to_i(16)))
    equal(shuffled.drop(fixture.players.length * 6), replay.state[:draw_pile], "one deterministic shuffle including new cards")
    equal(replay.state, fixture.replay.state, "deterministic enabled replay")
    equal(standard, game.send(:deck_for, options.merge("counterflow" => false)), "disabled variant does not add cards")
  end
  equal(116, game.send(:deck_for, { "counterflow" => true }).length, "normal counterflow uses authorized 4/6 fallback")
  state = Fixture.new.scenario
  game.send(:apply_safety, state[:tracks][0], "driving_ace")
  assert(state[:tracks].none? { |track| track.key?(:counterflow) }, "standard tracks have no new field, even after a safety")
end

test("counterflow attacks moving and stopped opponents without touching other conditions") do
  [false, true].product([false, true]).each do |moving, accumulate|
    fixture = Fixture.new(options: COUNTERFLOW_OPTIONS.merge("accumulate_hazards" => accumulate))
    state = fixture.scenario
    state[:hands]["Alice"] = %w[counterflow:1 counterflow:2 25:1]
    track = state[:tracks][1]
    track[:moving] = moving
    track[:hazards] = moving ? [] : %w[stop flat_tire]
    track[:speed_limit] = true
    track[:miles] = 325
    before = Marshal.load(Marshal.dump(track))
    equal(:invalid, fixture.play(state, "Alice", "play", "counterflow:1", target: "0"), "cannot attack own track")
    equal(:ok, fixture.play(state, "Alice", "play", "counterflow:1", target: "1"), "attack irrespective of movement or accumulation")
    equal(before.merge(counterflow: true), track, "effect separate from movement, limit and main hazards")
    equal(before, state[:reaction][:before], "reaction preserves complete previous track")
    state[:current_player] = "Alice"
    state[:phase] = :playing
    equal(:invalid, fixture.play(state, "Alice", "play", "counterflow:2", target: "1"), "duplicate counterflow rejected")
  end
  GameRoomGames::MilleBornes::SAFETIES.each do |safety|
    fixture = Fixture.new(options: COUNTERFLOW_OPTIONS)
    state = fixture.scenario
    state[:hands]["Alice"] = %w[counterflow:1 25:1]
    state[:tracks][1][:safeties] = [safety]
    expected = safety == "driving_ace" ? :invalid : :ok
    equal(expected, fixture.play(state, "Alice", "play", "counterflow:1", target: "1"), "only driving ace blocks counterflow")
  end
  fixture = Fixture.new
  state = fixture.scenario
  state[:hands]["Alice"] = %w[counterflow:1 end_counterflow:1 25:1]
  state[:tracks][0][:counterflow] = true
  equal(:invalid, fixture.play(state, "Alice", "play", "counterflow:1", target: "1"), "disabled variant rejects forged attack")
  equal(:invalid, fixture.play(state, "Alice", "play", "end_counterflow:1"), "disabled variant rejects forged remedy")
end

test("all mileage subtracts with a zero floor including playable zero-mile tracks") do
  fixture = Fixture.new(options: COUNTERFLOW_OPTIONS)
  GameRoomGames::MilleBornes::DISTANCES.each do |distance|
    [0, 10, distance.to_i, 750, 975].each do |miles|
      state = fixture.scenario
      state[:hands]["Alice"] = ["#{distance}:1", "go:1"]
      track = state[:tracks][0]
      track[:moving] = true
      track[:counterflow] = true
      track[:miles] = miles
      equal(:ok, fixture.play(state, "Alice", "play", "#{distance}:1"), "#{distance} playable from #{miles}")
      equal([miles - distance.to_i, 0].max, track[:miles], "backward mileage clamped")
      equal(distance == "200" ? 1 : 0, track[:two_hundreds], "200-card use counted even at zero")
      equal(nil, state[:round_winner], "backwards never wins by reaching 1000")
      assert(state[:spent].include?("#{distance}:1"), "zero-floor play consumes physical card")
      equal(track[:miles], fixture.game.participant_scores(fixture.snapshot(state))["Alice"], "score uses actual reduced mileage")
    end
  end
end

test("counterflow keeps stop, mechanical hazards, speed limits and two-200 restriction") do
  fixture = Fixture.new(options: COUNTERFLOW_OPTIONS)
  [[], %w[stop], %w[out_of_gas], %w[flat_tire], %w[accident]].each do |hazards|
    state = fixture.scenario
    state[:hands]["Alice"] = %w[25:1 50:1 75:1 100:1 200:1]
    track = state[:tracks][0]
    track[:counterflow] = true
    track[:moving] = !hazards.empty?
    track[:hazards] = hazards
    state[:hands]["Alice"].dup.each do |card|
      equal(:invalid, fixture.play(state, "Alice", "play", card), "no backward mileage while stopped or under a main hazard")
    end
  end
  GameRoomGames::MilleBornes::DISTANCES.each do |distance|
    state = fixture.scenario
    state[:hands]["Alice"] = ["#{distance}:1", "go:1"]
    state[:tracks][0].merge!(moving: true, counterflow: true, speed_limit: true, miles: 400)
    expected = distance.to_i <= 50 ? :ok : :invalid
    equal(expected, fixture.play(state, "Alice", "play", "#{distance}:1"), "speed limit applies backwards")
  end
  state = fixture.scenario
  state[:hands]["Alice"] = %w[200:1 200:2 200:3 end_counterflow:1 go:1]
  track = state[:tracks][0]
  track.merge!(moving: true, counterflow: true)
  %w[200:1 200:2].each do |card|
    state[:current_player] = "Alice"
    state[:phase] = :playing
    equal(:ok, fixture.play(state, "Alice", "play", card), "first two 200-mile cards legal at zero")
  end
  state[:current_player] = "Alice"
  state[:phase] = :playing
  equal(:invalid, fixture.play(state, "Alice", "play", "200:3"), "third 200 rejected while backwards")
  equal(:ok, fixture.play(state, "Alice", "play", "end_counterflow:1"), "end counterflow")
  state[:current_player] = "Alice"
  state[:phase] = :playing
  equal(:invalid, fixture.play(state, "Alice", "play", "200:3"), "remedy does not refund 200-mile use")
end

test("end of counterflow is independent and adds no green-light requirement") do
  fixture = Fixture.new(options: COUNTERFLOW_OPTIONS)
  [false, true].each do |moving|
    state = fixture.scenario
    state[:hands]["Alice"] = %w[end_counterflow:1 end_counterflow:2 25:1]
    track = state[:tracks][0]
    track.merge!(moving: moving, counterflow: true, miles: 500, speed_limit: true)
    track[:hazards] = moving ? [] : %w[stop flat_tire out_of_gas]
    before = Marshal.load(Marshal.dump(track))
    equal(:ok, fixture.play(state, "Alice", "play", "end_counterflow:1"), "remedy legal independently of main hazards")
    equal(before.merge(counterflow: false), track, "remedy only changes counterflow flag")
    state[:current_player] = "Alice"
    state[:phase] = :playing
    equal(:invalid, fixture.play(state, "Alice", "play", "end_counterflow:2"), "cannot remedy absent effect")
    equal(moving ? :ok : :invalid, fixture.play(state, "Alice", "play", "25:1"), "no extra GO requirement or bypass of hazards")
    equal(moving ? 525 : 500, track[:miles], "forward mileage restored only when moving")
  end
  %w[go end_limit fuel spare_tire repairs].each do |remedy|
    state = fixture.scenario
    state[:hands]["Alice"] = ["#{remedy}:1", "25:1"]
    track = state[:tracks][0]
    track.merge!(counterflow: true, speed_limit: true)
    hazard = fixture.game.class::REMEDIES[remedy]
    track[:hazards] = [hazard] if hazard && hazard != "speed_limit"
    equal(:ok, fixture.play(state, "Alice", "play", "#{remedy}:1"), "ordinary remedy legal")
    assert(track[:counterflow], "#{remedy} must not cure counterflow")
  end
end

test("driving ace clears counterflow and accident without changing unrelated conditions") do
  fixture = Fixture.new(options: COUNTERFLOW_OPTIONS)
  [false, true].each do |moving|
    state = fixture.scenario
    state[:hands]["Alice"] = %w[driving_ace:1 25:1]
    track = state[:tracks][0]
    track.merge!(moving: moving, counterflow: true, miles: 500, speed_limit: true)
    track[:hazards] = moving ? [] : %w[stop accident out_of_gas]
    equal(:ok, fixture.play(state, "Alice", "play", "driving_ace:1"), "normal safety clears effect")
    equal(false, track[:counterflow], "counterflow removed")
    equal(moving, track[:moving], "prior movement retained without adding or bypassing GO")
    equal(moving ? [] : %w[stop out_of_gas], track[:hazards], "only accident removed from main hazards")
    assert(track[:speed_limit], "driving ace does not remove speed limit")
    equal(500, track[:miles], "safety does not restore lost distance")
    equal("Alice", state[:current_player], "normal safety grants own extra turn")
  end
end

test("counterflow dirty trick restores prior movement and unrelated hazards") do
  fixture = Fixture.new(options: COUNTERFLOW_OPTIONS)
  [false, true].each do |moving|
    state = fixture.scenario
    state[:hands]["Alice"] = %w[counterflow:1 25:1]
    state[:hands]["Carol"] = %w[driving_ace:1 right_of_way:1 50:1]
    track = state[:tracks][2]
    track.merge!(moving: moving, miles: 425, two_hundreds: 1, speed_limit: true)
    track[:hazards] = moving ? [] : %w[stop flat_tire out_of_gas]
    before = Marshal.load(Marshal.dump(track))
    equal(:ok, fixture.play(state, "Alice", "play", "counterflow:1", target: "2"), "counterflow attack accepted")
    token = state[:reaction][:token]
    equal(:invalid, fixture.play(state, "Carol", "dirty_trick", "right_of_way:1", reaction: token), "wrong safety cannot counter counterflow")
    equal(:invalid, fixture.play(state, "Carol", "dirty_trick", "driving_ace:1", reaction: "0:0"), "stale token rejected")
    equal(:ok, fixture.play(state, "Carol", "dirty_trick", "driving_ace:1", reaction: token), "ace counters attack")
    equal(before.merge(safeties: ["driving_ace"], dirty_tricks: 1), state[:tracks][2], "exact prior track plus safety and bonus restored")
    equal("Carol", state[:current_player], "reactor gets extra turn")
    equal(3, state[:hands]["Carol"].length, "replacement drawn for safety")
  end
  %w[speed_limit accident].each do |hazard|
    state = fixture.scenario
    state[:hands]["Alice"] = ["#{hazard}:1", "25:1"]
    safety = fixture.game.class::PROTECTION[hazard]
    state[:hands]["Carol"] = ["#{safety}:1", "50:1"]
    state[:tracks][2].merge!(moving: true, counterflow: true)
    equal(:ok, fixture.play(state, "Alice", "play", "#{hazard}:1", target: "2"), "main attack while counterflow active")
    equal(:ok, fixture.play(state, "Carol", "dirty_trick", "#{safety}:1", reaction: state[:reaction][:token]), "ordinary dirty trick")
    equal(hazard != "accident", state[:tracks][2][:counterflow], "only ace clears prior counterflow during another dirty trick")
    assert(state[:tracks][2][:moving], "dirty trick restores movement with counterflow handled independently")
  end
end

test("team remedies and dirty tricks use the acting teammate's own hand") do
  fixture = Fixture.new(players: %w[Alice Bob Carol Dave], options: COUNTERFLOW_OPTIONS.merge("team_count" => 2))
  state = fixture.scenario
  state[:hands]["Alice"] = %w[counterflow:1 25:1]
  state[:hands]["Dave"] = %w[driving_ace:1 end_counterflow:1 50:1]
  equal(:invalid, fixture.play(state, "Alice", "play", "counterflow:1", target: "2"), "cannot attack a teammate")
  equal(:ok, fixture.play(state, "Alice", "play", "counterflow:1", target: "1"), "attack enemy shared track")
  token = state[:reaction][:token]
  equal(:invalid, fixture.play(state, "Bob", "dirty_trick", "driving_ace:1", reaction: token), "cannot borrow teammate safety")
  equal(:ok, fixture.play(state, "Dave", "dirty_trick", "driving_ace:1", reaction: token), "teammate safety protects entire track")
  equal(400, fixture.game.participant_scores(fixture.snapshot(state))["Bob"], "shared dirty trick score")
  state = fixture.scenario
  state[:tracks][1].merge!(moving: true, counterflow: true, miles: 400)
  state[:hands]["Dave"] = %w[end_counterflow:1 50:1]
  state[:current_player] = "Dave"
  equal(:ok, fixture.play(state, "Dave", "play", "end_counterflow:1"), "teammate remedies shared track")
  equal(false, state[:tracks][1][:counterflow], "remedy applies to team")
end
