require_relative "../../support/elten_array_shuffle"
require_relative "../../support/mille_bornes"
include MilleBornesTest

test("safety definitions default to enabled while canonical defaults preserve legacy serialized options") do
  game = Fixture.new.game
  legacy = JSON.parse(File.read(File.join(__dir__, "../../fixtures/contracts/v1/mille_bornes.json"), encoding: "UTF-8"))["options"]
  equal(legacy, game.normalize_options(legacy), "explicit historical zero delay remains unchanged")
  legacy["bot_delay"] = 1
  labels = {
    "accumulate_hazards" => "Accumulate problems",
    "recycle_discard" => "Use discarded cards as a new deck when the current deck runs out",
    "counterflow" => "Add counterflow cards",
    "include_safeties" => "Add safety cards"
  }
  labels.each do |key, label|
    definition = game.option_definitions.find { |item| item.key == key }
    assert(definition, "missing option #{key}")
    equal(label, definition.label, "exact option label")
    equal(:boolean, definition.kind, "boolean editor")
    equal(key == "include_safeties", definition.default, "standard and optional defaults")
  end
  assert(!game.default_options.key?("include_safeties"), "canonical default omits the implicit enabled flag")
  equal(game.default_options, game.normalize_options({}), "default options are already canonical")
  equal(JSON.generate(legacy), JSON.generate(game.normalize_options(game.default_options)), "legacy default values and order")
  equal(JSON.generate(legacy), JSON.generate(game.normalize_options({})), "missing safety flag preserves legacy shape")
  assert(game.rules_options_text(legacy).include?("Add safety cards"), "effective rules include default safeties")
  assert(game.table_options_announcement(legacy).include?("Add safety cards"), "table announcement includes default safeties")
  ["include_safeties", :include_safeties].each do |key|
    [true, 1, "1", "true", "TRUE"].each do |enabled|
      normalized = game.normalize_options(key => enabled)
      equal(JSON.generate(legacy), JSON.generate(normalized), "enabled flag has no serialized footprint")
      equal(normalized, game.normalize_options(normalized), "enabled normalization is idempotent")
    end
    [false, 0, "0", "false", "FALSE", nil].each do |disabled|
      normalized = game.normalize_options(key => disabled)
      equal(false, normalized["include_safeties"], "disabled flag retained")
      equal(normalized, game.normalize_options(normalized), "disabled normalization is idempotent")
      equal(normalized, game.options_from_json(JSON.generate(normalized)), "disabled flag survives serialization")
      equal(nil, game.options_error(normalized, player_count: 3), "disabled safeties are valid")
      assert(!game.rules_options_text(normalized).include?("Add safety cards"), "disabled safety rule omitted")
      assert(game.options_summary(normalized).include?("Add safety cards: No"), "lobby identifies disabled safeties")
    end
  end
  assert(game.notification_option_keys(legacy).include?("include_safeties"), "safety option declared public")
end

test("disabled safeties remove exactly four physical cards before dealing without changing standard order") do
  game = Fixture.new.game
  standard = game.send(:deck_for, {})
  safeties = game.class::SAFETIES.map { |type| "#{type}:1" }
  equal(106, standard.length, "legacy deck size")
  [nil, [1, 1], [3, 4], [20, 1]].each do |counts|
    options = { "include_safeties" => false }
    options.merge!("counterflow" => true, "counterflow_cards" => counts[0], "end_counterflow_cards" => counts[1]) if counts
    enabled = game.send(:deck_for, options.merge("include_safeties" => true))
    disabled = game.send(:deck_for, options)
    equal(enabled - safeties, disabled, "only four physical safeties removed; other order and counts preserved")
    equal(102 + counts.to_a.sum, disabled.length, "disabled deck size with explicit variant counts")
    equal(disabled.length, disabled.uniq.length, "no duplicate physical card")
    (2..8).each do |count|
      fixture = Fixture.new(players: Array.new(count) { |seat| "Player#{seat + 1}" }, options: options)
      current = fixture.start
      equal(Array.new(count, 6), current.state[:hands].values.map(&:length), "six cards per player")
      cards = current.state[:hands].values.flatten + current.state[:draw_pile] + current.state[:discard] + current.state[:spent]
      equal(disabled.sort, cards.sort, "actual deal conserves the configured physical deck")
      equal(current.state, fixture.replay.state, "disabled replay is deterministic")
      equal(false, current.state[:options]["include_safeties"], "actual session retains disabled flag")
    end
  end
  equal(standard, game.send(:deck_for, {}), "disabled deck creation never mutates standard counts")
  equal(standard, game.send(:deck_for, { include_safeties: true }), "explicit enabled deck unchanged")
  equal(102, game.send(:deck_for, { include_safeties: false }).length, "symbol-keyed option filters actual deck")
end

test("disabled safeties naturally reject fabricated safety plays and reactions in actual replay") do
  fixture = Fixture.new(options: { "include_safeties" => false })
  seed = (1..200).find do |number|
    fixture.events.replace([event(1, "Alice", "deal", "1|#{number.to_s(16).rjust(32, '0')}"), event(2, "Alice", "draw")])
    fixture.replay.state[:hands]["Alice"].include?("speed_limit:1")
  end
  assert(seed, "deterministic attack fixture found")
  pending = fixture.act("Alice", { "kind" => "card", "action" => "play", "card" => "speed_limit:1", "target" => "2" })
  equal(["Bob"], fixture.game.active_actors(pending), "no impossible responder activated")
  equal([], fixture.game.legal_actions(pending, "Carol"), "no safety reaction without a physical card")
  token = pending.state[:reaction][:token]
  fixture.game.class::SAFETIES.product(%w[play discard dirty_trick]).each do |safety, action|
    selection = { "kind" => "card", "action" => action, "card" => "#{safety}:1" }
    selection["reaction"] = token if action == "dirty_trick"
    equal(:invalid, fixture.game.action_for(selection, pending, "Carol").first, "forged safety action rejected")
    value = action == "discard" ? "#{safety}:1" : "#{safety}:1|#{action == 'dirty_trick' ? token : ''}"
    rejected = fixture.game.replay(fixture.session, fixture.events + [event(4, "Carol", action, value)], fixture.repository)
    equal(pending.state, rejected.state, "rejected imported action has no effect")
    equal(pending.accepted_events, rejected.accepted_events, "forged event not accepted")
    equal(pending.history.map(&:to_h), rejected.history.map(&:to_h), "forged event not announced")
  end
  after = fixture.act("Bob", { "kind" => "command", "action" => "draw" })
  equal(nil, after.state[:reaction], "ordinary draw still closes attack window")
  equal(0, fixture.game.participant_scores(after)["Carol"], "no invented safety or dirty-trick points")
end

test("dirty tricks restore stopped cars and unrelated problems rather than granting green lights") do
  GameRoomGames::MilleBornes::PROTECTION.reject { |hazard, _safety| hazard == "counterflow" }.each do |hazard, safety|
    unrelated = safety == "extra_tank" ? "flat_tire" : "out_of_gas"
    [[], [unrelated]].each do |problems|
      fixture = Fixture.new(options: { "accumulate_hazards" => true })
      state = fixture.scenario
      state[:hands]["Alice"] = ["#{hazard}:1", "25:1"]
      state[:hands]["Carol"] = ["#{safety}:1", "50:1"]
      state[:tracks][2].merge!(miles: 425, two_hundreds: 1, moving: false, hazards: problems.dup)
      prior = Marshal.load(Marshal.dump(state[:tracks][2]))
      if hazard == "stop"
        equal(:invalid, fixture.play(state, "Alice", "play", "stop:1", target: "2"), "red light cannot stop a car that is already stopped")
        equal(prior, state[:tracks][2], "invalid red light cannot change a stopped car")
        equal(nil, state[:reaction], "invalid red light cannot open a dirty-trick window")
        next
      end
      equal(:ok, fixture.play(state, "Alice", "play", "#{hazard}:1", target: "2"), "attack stopped car with accumulation")
      equal(:ok, fixture.play(state, "Carol", "dirty_trick", "#{safety}:1", reaction: state[:reaction][:token]), "immediate matching reaction")
      expected = prior.merge(safeties: [safety], dirty_tricks: 1, moving: safety == "right_of_way" && problems.empty?)
      equal(expected, state[:tracks][2], "previous track restored except actual safety effects and bonus")
      equal(825, fixture.game.participant_scores(fixture.snapshot(state))["Carol"], "mileage plus 100 safety and 300 bonus")
    end
  end
end

test("every safety protects the whole team but only its card owner can react and take the extra turn") do
  GameRoomGames::MilleBornes::PROTECTION.each do |hazard, safety|
    options = { "team_count" => 2, "counterflow" => true, "counterflow_cards" => 1, "end_counterflow_cards" => 1 }
    fixture = Fixture.new(players: %w[Alice Bob Carol Dave], options: options)
    state = fixture.scenario
    state[:hands]["Alice"] = ["#{hazard}:1", "25:1"]
    state[:hands]["Dave"] = ["#{safety}:1", "50:1"]
    state[:tracks][1][:moving] = true
    other_hand = state[:hands]["Bob"].dup
    equal(:ok, fixture.play(state, "Alice", "play", "#{hazard}:1", target: "1"), "attack shared track")
    token = state[:reaction][:token]
    equal(:invalid, fixture.play(state, "Bob", "dirty_trick", "#{safety}:1", reaction: token), "no borrowing teammate's safety")
    equal(:ok, fixture.play(state, "Dave", "dirty_trick", "#{safety}:1", reaction: token), "card owner protects team")
    equal([safety], state[:tracks][1][:safeties], "team immunity installed")
    equal(other_hand, state[:hands]["Bob"], "other teammate's hand unchanged")
    equal("Dave", state[:current_player], "card owner takes extra turn")
    %w[Bob Dave].each do |player|
      equal(400, fixture.game.participant_scores(fixture.snapshot(state))[player], "safety and dirty-trick points shared")
    end
    equal(0, fixture.game.participant_scores(fixture.snapshot(state))["Alice"], "opponents receive no safety points")
  end
end

test("replacement and extra-turn draws conserve cards with zero, one, two or recycled cards available") do
  [0, 1, 2, :recycled].each do |available|
    fixture = Fixture.new(options: { "recycle_discard" => available == :recycled })
    state = fixture.scenario
    state[:draw_pile] = available == :recycled ? [] : %w[25:8 25:9].first(available)
    state[:discard] = available == :recycled ? %w[25:8 25:9] : []
    state[:hands]["Alice"] = %w[stop:1 25:1]
    state[:hands]["Carol"] = %w[right_of_way:1 100:2 100:3 100:4 100:5 100:6]
    state[:tracks][2][:moving] = true
    original = (state[:hands].values.flatten + state[:draw_pile] + state[:discard] + state[:spent]).sort
    equal(:ok, fixture.play(state, "Alice", "play", "stop:1", target: "2"), "attack")
    equal(:ok, fixture.play(state, "Carol", "dirty_trick", "right_of_way:1", reaction: state[:reaction][:token]), "reaction")
    equal(available == 0 ? 5 : 6, state[:hands]["Carol"].length, "only available replacement drawn")
    extra_draw = available == 2 || available == :recycled
    equal(extra_draw ? :awaiting_draw : :playing, state[:phase], "extra turn draws only from an available stock")
    equal("Carol", state[:current_player], "reactor owns extra turn")
    if extra_draw
      equal(:ok, fixture.play(state, "Carol", "draw"), "explicit extra-turn draw")
      equal(7, state[:hands]["Carol"].length, "replacement plus ordinary draw yields seven cards")
    end
    equal(:ok, fixture.play(state, "Carol", "play", "100:2"), "drive immediately without a green light")
    equal("Alice", state[:current_player], "continue after reactor, skipping intermediate player")
    equal(500, fixture.game.participant_scores(fixture.snapshot(state))["Carol"], "dirty-trick points plus new mileage")
    cards = state[:hands].values.flatten + state[:draw_pile] + state[:discard] + state[:spent]
    equal(original, cards.sort, "reaction and extra turn neither duplicate nor lose cards")
  end
end

test("the next accepted draw, discard, ordinary play, safety or attack closes the previous reaction") do
  %w[draw discard go extra_tank out_of_gas].each do |next_action|
    fixture = Fixture.new
    state = fixture.scenario
    state[:draw_pile] = next_action == "draw" ? ["50:9"] : []
    state[:hands]["Alice"] = %w[speed_limit:1 25:1]
    state[:hands]["Bob"] = %w[go:1 extra_tank:1 out_of_gas:1 25:2]
    state[:hands]["Carol"] = %w[right_of_way:1 50:1]
    state[:tracks][2][:moving] = true
    equal(:ok, fixture.play(state, "Alice", "play", "speed_limit:1", target: "2"), "initial attack")
    pending = fixture.snapshot(Marshal.load(Marshal.dump(state)))
    token = state[:reaction][:token]
    reaction = { "kind" => "card", "action" => "dirty_trick", "card" => "right_of_way:1", "reaction" => token }
    equal(:invalid, fixture.play(state, "Carol", "dirty_trick", "right_of_way:1", reaction: "stale"), "invalid attempt rejected")
    equal(:invalid, fixture.play(state, "Alice", "draw"), "wrong actor rejected")
    equal(pending.state, state, "invalid attempts do not close the window or mutate state")
    equal(:ok, fixture.game.action_for(reaction, fixture.snapshot(state), "Carol").first, "reaction still immediately legal")
    status = case next_action
    when "draw"
      fixture.play(state, "Bob", "draw")
    when "discard"
      fixture.play(state, "Bob", "discard", "25:2")
    when "out_of_gas"
      fixture.play(state, "Bob", "play", "out_of_gas:1", target: "2")
    else
      fixture.play(state, "Bob", "play", "#{next_action}:1")
    end
    equal(:ok, status, "next accepted action")
    equal(:invalid, fixture.play(state, "Carol", "dirty_trick", "right_of_way:1", reaction: token), "too late for previous attack")
    assert(!fixture.game.concurrent_session_input?(pending, fixture.snapshot(state), reaction), "expired attack cannot bypass stale-view checks")
  end
end

require_relative "../../support/session_runner"

test("runner rejects human reactions after a zero-delay bot draw and accepts them during configured bot delay") do
  [false, true].product([0, 3]).each do |covered, delay|
    game = GameRoomGames::MilleBornes.new
    settings = game.normalize_options("bot_delay" => delay)
    harness = NativeRoomHarness.new(game: game, users: %w[Alice Bob], bots: 1, options: settings)
    harness.start
    players = harness.repositories["Alice"].players_for(harness.session)
    bot = players.find { |player| GameRoomParticipants.bot?(player) }
    fixture = Fixture.new(players: players, options: settings)
    seed = (1..2000).find do |number|
      fixture.events.replace([event(1, "Alice", "deal", "1|#{number.to_s(16).rjust(32, '0')}"), event(2, "Alice", "draw")])
      hands = fixture.replay.state[:hands]
      hands["Alice"].include?("right_of_way:1") && hands["Bob"].include?("speed_limit:1")
    end
    assert(seed, "deterministic human-response fixture found")
    discard = fixture.replay.state[:hands]["Alice"].find { |card| card != "right_of_way:1" }
    fixture.act("Alice", { "kind" => "card", "action" => "discard", "card" => discard })
    fixture.act("Bob", { "kind" => "command", "action" => "draw" })
    fixture.act("Bob", { "kind" => "card", "action" => "play", "card" => "speed_limit:1", "target" => "0" })
    fixture.events.each do |entry|
      command = GameRoomGames::EventCommand.new(action: entry["action"], value: entry["value"])
      harness.write(entry["actor"], [command])
    end
    runner = runner_for(harness, "Alice", covered: -> { covered })
    clock = 0.0
    runner.instance_variable_get(:@turn).instance_variable_set(:@clock, -> { clock })
    begin
      pending = harness.replay("Alice")
      equal(["Alice", bot], game.active_actors(pending), "human responder is listed before the next bot")
      equal(bot, GameRoomBots::Coordinator.new.pending_bot(game, pending), "bot coordinator skips human actors instead of waiting")
      reaction = game.legal_actions(pending, "Alice").find { |action| action["action"] == "dirty_trick" }
      assert(reaction, "human initially has a legal dirty trick")
      before_count = harness.events("Alice").length
      unless covered
        step(harness, runner)
        equal(before_count, harness.events("Alice").length, "visible game waits for presentation acknowledgement")
        runner.publish_view(session: harness.session, replay: pending, busy: false,
          context: runner.instance_variable_get(:@context_template))
      end
      step(harness, runner)
      if delay == 0
        equal(before_count + 1, harness.events("Alice").length, "bot draws in the first eligible runner step without advancing clock")
        equal(bot, harness.events("Alice").last["actor"], "draw belongs to the next bot")
        equal("draw", harness.events("Alice").last["action"], "draw is the cutoff event")
        equal(nil, harness.replay("Alice").state[:reaction], "human reaction window is gone")
        equal(:invalid, game.action_for(reaction, harness.replay("Alice"), "Alice").first, "late response cannot be treated as a dirty trick")
        rejected = false
        begin
          harness.as("Alice") { runner.submit(session: harness.session, replay: pending, selection: reaction, actor: "Alice") }
        rescue GameRoomSessionRunner::StaleView
          rejected = true
        end
        assert(rejected, "stale UI cannot resurrect the expired reaction")
      else
        equal(before_count, harness.events("Alice").length, "existing configured bot delay leaves the reaction pending")
        status, = harness.as("Alice") do
          runner.submit(session: harness.session, replay: pending, selection: reaction, actor: "Alice")
        end
        equal(:ok, status, "human can submit a valid dirty trick during configured delay")
        after = harness.replay("Alice")
        equal("Alice", after.current_player, "human takes the extra turn")
        equal(400, game.participant_scores(after)["Alice"], "runner awards safety and dirty-trick points")
        clock = 4.0
        runner.publish_view(session: harness.session, replay: after, busy: false,
          context: runner.instance_variable_get(:@context_template)) unless covered
        step(harness, runner)
        equal(before_count + 1, harness.events("Alice").length, "obsolete delayed bot draw is not committed after human reaction")
      end
      harness.assert_converged("human dirty-trick runner boundary")
      puts "Human reaction: covered #{covered}, bot delay #{delay}, #{delay == 0 ? 'no reserved response window' : 'accepted before bot draw'}"
    ensure
      runner.close
    end
  end
end

test("disabled-safety match completes through the production runner with humans, a bot and duplicate delivery") do
  game = GameRoomGames::MilleBornes.new
  settings = game.normalize_options("include_safeties" => false, "bot_delay" => 0, "target_score" => 100)
  harness = NativeRoomHarness.new(game: game, users: %w[Alice Bob], bots: 1, options: settings)
  harness.start
  runners = harness.users.to_h { |user| [user, runner_for(harness, user)] }
  expected_cards = game.send(:deck_for, settings).sort
  clock = 0.0
  runners.each_value do |runner|
    runner.instance_variable_get(:@context_template).random_source = GameRoomRandom::SeededSource.new(137)
    runner.instance_variable_get(:@turn).instance_variable_set(:@clock, -> { clock })
  end
  begin
    600.times do
      clock += 2
      runners.each { |user, runner| step(harness, runner, user) }
      harness.broker.deliver(duplicate: true)
      harness.assert_converged("disabled-safety match")
      current = harness.replay("Alice")
      cards = current.state[:hands].values.flatten + current.state[:draw_pile] + current.state[:discard] + current.state[:spent]
      equal(expected_cards, cards.sort, "runner conserves the 102-card deck")
      break if current.finished?

      runners.each do |user, runner|
        replay = harness.replay(user)
        next if replay.finished?
        selection = game.legal_actions(replay, user).max_by { |action| game.bot_action_score(replay, user, action) }
        next unless selection
        status, = harness.as(user) { runner.submit(session: harness.session, replay: replay, selection: selection, actor: user) }
        equal(:ok, status, "human uses the same runner commit boundary")
      end
    end
    final = harness.replay("Alice")
    events = harness.events("Alice")
    assert(final.finished?, "disabled-safety match did not finish through its production runner")
    equal(events.length, final.accepted_events.length, "all runner events replay")
    assert(events.any? { |entry| GameRoomParticipants.bot?(entry["actor"]) }, "bot must commit actual moves")
    assert(events.none? { |entry| entry["action"] == "dirty_trick" }, "no impossible dirty trick committed")
    assert(final.state[:tracks].all? { |track| track[:safeties].empty? && track[:dirty_tricks] == 0 }, "no impossible safety or score")
    harness.assert_converged("finished disabled-safety match", expected_count: events.length)
  ensure
    runners.each_value(&:close)
  end
end
