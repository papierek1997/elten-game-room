if ARGV.first
  require_relative "../../support/binary_rules_load"
  GameRoomTestLocalization.use_language("en")
end
require_relative "../../support/session_runner"
require_relative "../../support/elten_array_shuffle"
require_relative "../../support/mille_bornes"
include MilleBornesTest

module MilleBornesBotRegression
  module_function

  def choose(fixture, state, discards_only: false, random: GameRoomRandom::SeededSource.new(42))
    replay = fixture.snapshot(state)
    actions = fixture.game.legal_actions(replay, "Alice")
    actions = actions.select { |action| action["action"] == "discard" } if discards_only
    chosen = fixture.game.bot_strategy.choose(actions: actions, game: fixture.game, replay: replay,
      actor: "Alice", random_source: random)
    equal(:ok, fixture.game.action_for(chosen, replay, "Alice").first, "Chosen bot action follows standard validation")
    chosen
  end

  def with_runner(seed, covered:)
    game = GameRoomGames::MilleBornes.new
    options = game.default_options.merge("bot_delay" => 0, "target_score" => 5000,
      "accumulate_hazards" => true, "counterflow" => true,
      "counterflow_cards" => 3, "end_counterflow_cards" => 4)
    harness = NativeRoomHarness.new(game: game, users: %w[Alice Bob], bots: 1, options: options)
    runners = {}
    harness.start
    clock = 0.0
    harness.users.each do |user|
      runner = runner_for(harness, user, covered: -> { covered })
      runners[user] = runner
      seed_bytes = seed.to_s(16).rjust(32, "0").scan(/../).map { |byte| byte.to_i(16) + 1 }
      runner.instance_variable_get(:@context_template).random_source =
        GameRoomRandom::SequenceSource.new(seed_bytes + Array.new(200, 1))
      runner.instance_variable_get(:@turn).instance_variable_set(:@clock, -> { clock })
    end
    advance = lambda do
      clock += 2
      runners.each do |user, runner|
        harness.as(user) do
          unless covered
            runner.publish_view(session: harness.session, replay: harness.replay(user), busy: false,
              context: runner.instance_variable_get(:@context_template))
          end
          step(harness, runner, user)
        end
      end
      harness.broker.deliver(duplicate: true)
      harness.assert_converged("Safety bot covered=#{covered}")
      harness.users.each do |user|
        replay = harness.replay(user)
        equal(harness.events(user).length, replay.accepted_events.length, "Runner only persists accepted actions")
      end
    end
    await(advance) { harness.replay("Alice").state[:round] == 1 }
    bot = harness.replay("Alice").players.find { |player| GameRoomParticipants.bot?(player) }
    assert(bot, "Native room has a real bot seat")
    yield harness, runners, advance, bot
    verify_history(harness)
  ensure
    runners&.each_value(&:close)
  end

  def await(advance)
    30.times do
      advance.call
      return if yield
    end
    raise "Active session runner did not complete the expected bot action"
  end

  def human_action(harness, runners, user, &selection)
    assert(!GameRoomParticipants.bot?(user), "Regression must not submit a bot action itself")
    replay = harness.replay(user)
    action = harness.game.legal_actions(replay, user).find(&selection)
    assert(action, "Missing scripted legal human action for #{user}")
    harness.as(user) do
      status, = runners.fetch(user).submit(session: harness.session, replay: replay, selection: action, actor: user)
      equal(:ok, status, "Human action goes through the active runner")
    end
    harness.broker.deliver(duplicate: true)
    harness.assert_converged("Human setup for safety bot")
  end

  def replay_at(harness, count)
    harness.game.replay(harness.session, harness.events("Alice").take(count), harness.repositories.fetch("Alice"))
  end

  def verify_history(harness)
    events = harness.events("Alice")
    events.each_with_index do |event, index|
      replay = replay_at(harness, index + 1)
      equal(index + 1, replay.accepted_events.length, "Every safety history prefix is accepted")
      state = replay.state
      cards = state[:hands].values.flatten + state[:draw_pile] + state[:discard] + state[:spent]
      equal(harness.game.send(:deck_for, state[:options]).sort, cards.sort, "Safety events conserve physical cards")
      next unless GameRoomParticipants.bot?(event["actor"])

      before = replay_at(harness, index)
      selection = harness.game.send(:selection_from_event, event)
      equal(:ok, harness.game.action_for(selection, before, event["actor"]).first,
        "Persisted bot move passes standard action_for from its real previous replay")
      if before.state[:phase] == :awaiting_draw
        assert(%w[draw dirty_trick].include?(event["action"]), "Bot cannot discard or ordinarily play before drawing")
      end
    end
    equal(GameRoomTest::ReplaySnapshot.capture(harness.replay("Alice")),
      GameRoomTest::ReplaySnapshot.capture(replay_at(harness, events.length)), "Fresh replay preserves the bot history")
  end
end

{
  "stop" => ["right_of_way", 97, 129], "speed_limit" => ["right_of_way", 16, 16],
  "out_of_gas" => ["extra_tank", 60, 156], "flat_tire" => ["puncture_proof", 145, 1],
  "accident" => ["driving_ace", 75, 156], "counterflow" => ["driving_ace", 61, 317]
}.each do |hazard, (safety, outside_turn_seed, own_turn_seed)|
  [false, true].product([["Alice", false], ["Alice", true], ["Bob", false]]).each do |covered, (attacker, following_draw)|
    seed = attacker == "Alice" ? outside_turn_seed : own_turn_seed
    test("active runner dirty trick #{hazard}/#{safety}, covered=#{covered}, attacker=#{attacker}, following_draw=#{following_draw}") do
      MilleBornesBotRegression.with_runner(seed, covered: covered) do |harness, runners, advance, bot|
        initial = harness.replay("Alice")
        card = "#{safety}:1"
        assert(initial.state[:hands].fetch(bot).include?(card), "Fixed deal must give the bot its safety")
        if attacker == "Bob"
          MilleBornesBotRegression.human_action(harness, runners, "Alice") { |action| action["action"] == "draw" }
          MilleBornesBotRegression.human_action(harness, runners, "Alice") { |action| action["action"] == "discard" }
        end
        MilleBornesBotRegression.human_action(harness, runners, attacker) { |action| action["action"] == "draw" }
        MilleBornesBotRegression.human_action(harness, runners, attacker) do |action|
          action["action"] == "play" && action["card"].start_with?("#{hazard}:") && action["target"] == "2"
        end
        attacked = harness.replay("Alice")
        equal(attacker == "Alice" ? "Bob" : bot, attacked.state[:current_player], "Reaction covers both ordinary and out-of-turn bot input")
        equal(bot, harness.game.active_actors(attacked).first, "Pending reaction advertises the bot to the runner")
        token = attacked.state[:reaction][:token]
        if following_draw
          MilleBornesBotRegression.human_action(harness, runners, "Bob") { |action| action["action"] == "draw" }
          expired = harness.replay("Alice")
          equal(nil, expired.state[:reaction], "Following player's draw closes the existing reaction window")
          equal([], harness.game.legal_actions(expired, bot), "Expired reaction cannot wake the bot out of turn")
          stale = { "kind" => "card", "action" => "dirty_trick", "card" => card, "reaction" => token }
          equal(:invalid, harness.game.action_for(stale, expired, bot).first, "Expired safety reaction is rejected")
          count = harness.events("Alice").length
          3.times { advance.call }
          equal(count, harness.events("Alice").length, "Runner never persists an expired reaction or an out-of-turn discard")
          next
        end
        before = harness.events("Alice").length
        MilleBornesBotRegression.await(advance) { harness.events("Alice").length > before }
        written = harness.events("Alice").drop(before)
        equal([[bot, "dirty_trick", "#{card}|#{token}"]],
          written.map { |event| event.values_at("actor", "action", "value") }, "Runner itself writes exactly one safety reaction")
        reacted = harness.replay("Alice")
        track = reacted.state[:tracks][2]
        equal([safety], track[:safeties], "Bot safety takes effect")
        equal(1, track[:dirty_tricks], "Dirty trick grants exactly one bonus")
        equal(400, harness.game.participant_scores(reacted).fetch(bot), "Safety and dirty-trick points are actually awarded")
        equal([], track[:hazards], "The attacked track is restored")
        assert(!track[:speed_limit] && !track[:counterflow], "Safety removes the corresponding independent problem")
        equal(nil, reacted.state[:reaction], "Reaction is consumed")
        equal(bot, reacted.state[:current_player], "Bot receives the extra turn")
        equal(:awaiting_draw, reacted.state[:phase], "Extra turn still requires its normal draw")
        equal(initial.state[:hands].fetch(bot).length, reacted.state[:hands].fetch(bot).length, "Reaction replaces the safety card")
        assert(reacted.state[:spent].include?(card), "Safety is physically consumed")
        3.times { advance.call }
        equal(1, harness.events("Alice").count { |event| event["action"] == "dirty_trick" }, "Duplicate delivery cannot repeat the reaction")
      end
    end
  end
end

{ "right_of_way" => 97, "extra_tank" => 60, "puncture_proof" => 145, "driving_ace" => 75 }.each do |safety, seed|
  [false, true].each do |covered|
    test("active runner ordinary safety #{safety}, covered=#{covered}") do
      MilleBornesBotRegression.with_runner(seed, covered: covered) do |harness, runners, advance, bot|
        harness.users.each do |user|
          MilleBornesBotRegression.human_action(harness, runners, user) { |action| action["action"] == "draw" }
          MilleBornesBotRegression.human_action(harness, runners, user) { |action| action["action"] == "discard" }
        end
        match = lambda do |event|
          event["actor"] == bot && event["action"] == "play" && event["value"] == "#{safety}:1|"
        end
        MilleBornesBotRegression.await(advance) { harness.events("Alice").any?(&match) }
        index = harness.events("Alice").index(&match)
        before = MilleBornesBotRegression.replay_at(harness, index)
        after = MilleBornesBotRegression.replay_at(harness, index + 1)
        equal(nil, before.state[:reaction], "Ordinary safety does not require an attack")
        assert(after.state[:tracks][2][:safeties].include?(safety), "Ordinary safety takes effect")
        equal(0, after.state[:tracks][2][:dirty_tricks], "Ordinary play does not invent a dirty trick")
        equal(100, harness.game.participant_scores(after).fetch(bot) - harness.game.participant_scores(before).fetch(bot),
          "Ordinary safety awards only its normal points")
        equal(bot, after.state[:current_player], "Ordinary safety also retains the bot's turn")
        equal(:awaiting_draw, after.state[:phase], "Ordinary safety's extra turn requires drawing")
        equal(before.state[:hands].fetch(bot).length - 1, after.state[:hands].fetch(bot).length, "Ordinary safety consumes one card")
      end
    end
  end
end

test("useful distance discards precede useful defenses and attacks without duplicate-count inversion") do
  defenses = %w[go fuel spare_tire repairs end_limit end_counterflow instant_repair]
  alternatives = defenses + GameRoomGames::MilleBornes::HAZARDS
  [false, true].product(GameRoomGames::MilleBornes::DISTANCES, alternatives, [[1, 1], [6, 1], [1, 6]]).each do |recycling, distance, other, copies|
    fixture = Fixture.new(options: { "recycle_discard" => recycling, "counterflow" => true,
      "counterflow_cards" => 3, "end_counterflow_cards" => 4, "include_instant_repairs" => true })
    state = fixture.scenario
    counts = fixture.game.deck_counts_for(state[:options])
    distance_copies = [copies[0], counts.fetch(distance)].min
    other_copies = [copies[1], counts.fetch(other)].min
    state[:hands]["Alice"] = Array.new(distance_copies) { |index| "#{distance}:#{index + 1}" } +
      Array.new(other_copies) { |index| "#{other}:#{index + 1}" }
    chosen = MilleBornesBotRegression.choose(fixture, state, discards_only: true)
    redundant = recycling && other_copies > 1 && (other == "go" || fixture.game.class::REMEDIES.key?(other))
    equal(redundant ? other : distance, chosen["card"].split(":").first,
      "Discard preference: recycle=#{recycling}, distance=#{distance}, alternative=#{other}, copies=#{copies}")
  end
end

test("obsolete remedies after every relevant safety precede even repeated useful distances") do
  {
    "fuel" => ["extra_tank"], "spare_tire" => ["puncture_proof"],
    "repairs" => ["driving_ace"], "end_counterflow" => ["driving_ace"],
    "go" => ["right_of_way"], "end_limit" => ["right_of_way"],
    "instant_repair" => GameRoomGames::MilleBornes::SAFETIES
  }.each do |remedy, safeties|
    [false, true].product(GameRoomGames::MilleBornes::DISTANCES, [1, 6]).each do |recycling, distance, copies|
      fixture = Fixture.new(options: { "recycle_discard" => recycling, "counterflow" => true,
        "counterflow_cards" => 3, "end_counterflow_cards" => 4, "include_instant_repairs" => true })
      state = fixture.scenario
      state[:tracks][0][:safeties] = safeties.dup
      distance_copies = [copies, fixture.game.deck_counts_for(state[:options]).fetch(distance)].min
      state[:hands]["Alice"] = ["#{remedy}:1"] + Array.new(distance_copies) { |index| "#{distance}:#{index + 1}" }
      chosen = MilleBornesBotRegression.choose(fixture, state, discards_only: true)
      equal("#{remedy}:1", chosen["card"], "Immunity makes #{remedy} obsolete before useful #{distance} cards")
    end
  end
end

test("counterflow, overshooting and the two-200 limit discard unusable mileage in either deck mode") do
  scenarios = GameRoomGames::MilleBornes::DISTANCES.product([0, 975]).map do |distance, miles|
    [distance, { moving: true, counterflow: true, miles: miles }]
  end
  scenarios += [["100", { moving: true, miles: 925 }], ["200", { moving: true, miles: 850 }],
    ["200", { moving: true, miles: 400, two_hundreds: 2 }]]
  [false, true].product(scenarios).each do |recycling, (distance, track)|
    fixture = Fixture.new(options: { "recycle_discard" => recycling, "counterflow" => true,
      "counterflow_cards" => 3, "end_counterflow_cards" => 4 })
    state = fixture.scenario
    state[:tracks][0].merge!(track)
    state[:hands]["Alice"] = ["#{distance}:1", "fuel:1"]
    chosen = MilleBornesBotRegression.choose(fixture, state)
    equal(["discard", "#{distance}:1"], chosen.values_at("action", "card"), "Bot does not waste a useful remedy or drive backwards")
    equal(:ok, fixture.play(state, "Alice", "discard", chosen["card"]), "Chosen discard executes through action_for and replay")
  end
end

test("discard preference never overrides legal progress, exact finish, repair or the mandatory draw") do
  [false, true].each do |recycling|
    fixture = Fixture.new(options: { "recycle_discard" => recycling })
    state = fixture.scenario
    state[:hands]["Alice"] = %w[100:1 fuel:1]
    state[:tracks][0].merge!(moving: true, safeties: ["extra_tank"])
    chosen = MilleBornesBotRegression.choose(fixture, state)
    equal(["play", "100:1"], chosen.values_at("action", "card"), "Useful progress beats any discard")
    state[:tracks][0][:miles] = 900
    equal(chosen, MilleBornesBotRegression.choose(fixture, state), "Exact finish beats discarding")
    state[:tracks][0].merge!(moving: false, safeties: [], hazards: ["out_of_gas"])
    equal(["play", "fuel:1"], MilleBornesBotRegression.choose(fixture, state).values_at("action", "card"),
      "An immediately useful remedy is played")
    state[:tracks][0].merge!(safeties: ["extra_tank"], hazards: [])
    state[:phase] = :awaiting_draw
    state[:hands]["Alice"] = %w[fuel:1 fuel:2]
    equal({ "kind" => "command", "action" => "draw" }, MilleBornesBotRegression.choose(fixture, state), "Raw draw phase cannot discard")
    equal(:invalid, fixture.play(state, "Alice", "discard", "fuel:1"), "Validator rejects premature discard")
    equal(:ok, fixture.play(state, "Alice", "draw"), "Required draw executes normally")
    equal(:ok, fixture.play(state, "Alice", "discard", "fuel:1"), "Discard becomes legal only after the draw")
  end
end

test("discard ties preserve hidden information, immutable observations and deterministic RNG") do
  [false, true].each do |recycling|
    fixture = Fixture.new(options: { "recycle_discard" => recycling })
    state = fixture.scenario
    state[:hands]["Alice"] = %w[100:1 100:2 fuel:1]
    alternative = Marshal.load(Marshal.dump(state))
    alternative[:hands]["Bob"] = %w[extra_tank:1 right_of_way:1]
    alternative[:hands]["Carol"] = %w[driving_ace:1 puncture_proof:1]
    alternative[:draw_pile].reverse!
    before = Marshal.dump(state)
    random = GameRoomRandom::SeededSource.new(42)
    alternate_random = random.dup
    expected_random = random.dup
    expected_card = state[:hands]["Alice"].take(2)[expected_random.roll(count: 1, sides: 2).values.first - 1]
    chosen = MilleBornesBotRegression.choose(fixture, state, random: random)
    equal(expected_card, chosen["card"], "Exactly one normal tie-break selects among the two distance cards")
    equal(chosen, MilleBornesBotRegression.choose(fixture, alternative, random: alternate_random), "No hidden hand or deck-order advantage")
    expected_tail = expected_random.roll(count: 8, sides: 1000).values
    equal(expected_tail, random.roll(count: 8, sides: 1000).values, "No additional RNG consumption")
    equal(expected_tail, alternate_random.roll(count: 8, sides: 1000).values, "Hidden changes preserve subsequent RNG")
    equal(before, Marshal.dump(state), "Bot scoring and choice do not mutate the replay")
  end
end
