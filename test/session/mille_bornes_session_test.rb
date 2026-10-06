require_relative "../support/session_runner"
require_relative "../support/sequence_random"
require_relative "../support/elten_array_shuffle"
require_relative "../../games/mille_bornes"

game = GameRoomGames::MilleBornes.new
settings = game.default_options.merge("bot_delay" => 0, "target_score" => 100)
harness = NativeRoomHarness.new(game: game, users: %w[Alice Bob], bots: 1, options: settings)
harness.start
runners = harness.users.to_h { |user| [user, runner_for(harness, user)] }
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
    harness.assert_converged("1000 miles synchronized turn")
    break if harness.replay("Alice").finished?

    runners.each do |user, runner|
      replay = harness.replay(user)
      next if replay.finished?
      actions = game.legal_actions(replay, user)
      next if actions.empty?
      action = actions.max_by { |candidate| game.bot_action_score(replay, user, candidate) }
      harness.as(user) do
        status, = runner.submit(session: harness.session, replay: replay, selection: action, actor: user)
        assert(status == :ok, "legal 1000 miles action rejected by runner: #{status}")
      end
    end
  end
  final = harness.replay("Alice")
  events = harness.events("Alice")
  assert(final.finished?, "1000 miles did not finish through its production runner")
  assert(events.any? { |event| GameRoomParticipants.bot?(event["actor"]) }, "no bot submitted a normal event")
  assert(final.accepted_events.length == events.length, "runner persisted a rejected 1000 miles event")
  before = events.length
  10.times do
    clock += 2
    runners.each { |user, runner| step(harness, runner, user) }
    harness.broker.deliver(duplicate: true)
  end
  assert(harness.events("Alice").length == before, "finished race kept writing events")
  harness.assert_converged("1000 miles final result", expected_count: before)
  puts "1000 miles: native transport, duplicate delivery, two humans, bot runner, covered game and final convergence passed"
ensure
  runners.each_value(&:close)
end

module MilleBornesSessionRegression
  module_function

  def custom_options(counts)
    types = GameRoomGames::MilleBornes::DECK_COUNTS.keys + %w[counterflow end_counterflow instant_repair]
    types.to_h { |type| ["#{type}_cards", counts.fetch(type, 0)] }.merge(
      "custom_deck" => true, "include_instant_repairs" => true,
      "include_safeties" => false, "accumulate_hazards" => true
    )
  end

  def assert_inventory(replay, counts)
    state = replay.state
    expected = counts.flat_map { |type, count| Array.new(count) { |copy| "#{type}:#{copy + 1}" } }
    inventory = state[:hands].values.flatten + state[:draw_pile] + state[:discard] + state[:spent]
    assert(inventory.sort == expected.sort, "Custom/optional deck lost, duplicated or invented physical cards")
    assert(inventory.uniq.length == inventory.length, "A physical card exists in more than one location")
  end

  def with_session(options:, counts:, seed: 83, covered: true)
    game = GameRoomGames::MilleBornes.new
    settings = game.default_options.merge(options).merge("bot_delay" => 0, "target_score" => 5000)
    harness = NativeRoomHarness.new(game: game, users: %w[Alice Bob], bots: 1, options: settings)
    runners = {}
    harness.start
    clock = 0.0
    harness.users.each do |user|
      runner = runner_for(harness, user, covered: -> { covered })
      runners[user] = runner
      seed_bytes = seed.to_s(16).rjust(32, "0").scan(/../).map { |byte| byte.to_i(16) + 1 }
      runner.instance_variable_get(:@context_template).random_source = GameRoomRandom::SequenceSource.new(seed_bytes + Array.new(200, 1))
      runner.instance_variable_get(:@turn).instance_variable_set(:@clock, -> { clock })
    end
    advance = lambda do
      clock += 2
      runners.each do |user, runner|
        unless covered
          harness.as(user) do
            runner.publish_view(session: harness.session, replay: harness.replay(user), busy: false,
              context: runner.instance_variable_get(:@context_template))
          end
        end
        step(harness, runner, user)
      end
      harness.broker.deliver(duplicate: true)
      harness.assert_converged("instant repair runner covered=#{covered}")
      harness.users.each do |user|
        replay = harness.replay(user)
        assert(replay.accepted_events.length == harness.events(user).length, "Runner persisted a rejected repair/custom-deck event")
        assert_inventory(replay, counts) if replay.state[:round].positive?
      end
    end
    await(harness, advance, "initial custom/optional deal") { |replay| replay.state[:round] == 1 }
    assert(harness.replay("Alice").state[:hands].values.all? { |hand| hand.length == 6 }, "Custom deck did not deal six cards per seat")
    yield harness, runners, advance
  ensure
    runners&.each_value(&:close)
  end

  def await(harness, advance, label)
    30.times do
      advance.call
      return if yield harness.replay("Alice")
    end
    raise "Production runner did not reach #{label}"
  end

  def submit(harness, runners, user, counts, &selection)
    replay = harness.replay(user)
    action = harness.game.legal_actions(replay, user).find(&selection)
    assert(action != nil, "Missing scripted legal human action for #{user}")
    assert(!GameRoomParticipants.bot?(user), "Test must not submit the bot's repair itself")
    harness.as(user) do
      status, = runners.fetch(user).submit(session: harness.session, replay: replay, selection: action, actor: user)
      assert(status == :ok, "Human action rejected before bot repair: #{status}, #{action.inspect}")
    end
    harness.broker.deliver(duplicate: true)
    harness.assert_converged("human action before bot repair")
    assert_inventory(harness.replay(user), counts)
  end

  def human_turn(harness, runners, user, counts, attack: nil)
    submit(harness, runners, user, counts) { |action| action["action"] == "draw" }
    submit(harness, runners, user, counts) do |action|
      if attack
        action["action"] == "play" && action["card"].start_with?("#{attack}:") && action["target"] == "2"
      else
        action["action"] == "discard" && action["card"].start_with?("25:")
      end
    end
  end

  def bot_repair(harness, advance, bot, problem)
    before = harness.events("Alice").length
    before_hand = harness.replay("Alice").state[:hands].fetch(bot).dup
    await(harness, advance, "bot repair of #{problem}") do |replay|
      replay.state[:current_player] == "Alice" && replay.state[:phase] == :awaiting_draw
    end
    events = harness.events("Alice").drop(before)
    assert(events.map { |event| event["action"] } == %w[draw play], "Bot did not draw and repair through normal runner events")
    assert(events.all? { |event| event["actor"] == bot }, "A human submitted the bot's repair")
    event = events.last
    card, repaired = event.fetch("value").split("|", -1)
    assert(card.start_with?("instant_repair:") && repaired == problem, "Bot repaired the wrong problem: #{event.inspect}")
    state = harness.replay("Alice").state
    assert(state[:spent].include?(card) && !state[:hands].fetch(bot).include?(card), "Bot repair did not consume its physical card")
    assert((before_hand - [card] - state[:hands].fetch(bot)).empty?, "Bot repair consumed another card from its hand")
    assert(state[:tracks][2][:safeties].empty? && state[:tracks][2][:dirty_tricks].zero?, "Bot repair granted immunity or dirty-trick bonus")
    assert(harness.game.participant_scores(harness.replay("Alice")).fetch(bot).zero?, "Bot repair granted unearned points")
    assert(state[:reaction] == nil, "Bot repair opened a dirty-trick window")
    history = harness.replay("Alice").history.last.text
    problem_label = problem == "go" ? "No green light" : harness.game.send(:card_label, problem)
    assert(history.include?("used Instant repair to remove #{problem_label}."), "Replay lost the selected repair problem in history")
    count = harness.events("Alice").length
    3.times { advance.call }
    assert(harness.events("Alice").length == count, "Bot received an extra turn or repeated a repaired event")
    event
  end

  def replay_prefixes(harness, counts)
    events = harness.events("Alice")
    repository = harness.repositories.fetch("Alice")
    events.each_index do |index|
      prefix = events.take(index + 1)
      replay = harness.game.replay(harness.session, prefix, repository)
      assert(replay.accepted_events.length == prefix.length, "A repair history prefix could not be replayed")
      assert_inventory(replay, counts)
    end
    before = GameRoomTest::ReplaySnapshot.capture(harness.replay("Alice"))
    rebuilt = harness.game.replay(harness.session, events, repository)
    assert(before == GameRoomTest::ReplaySnapshot.capture(rebuilt), "Fresh replay changed the accepted custom-deck game")
  end

  def run
    standard = GameRoomGames::MilleBornes::DECK_COUNTS
    with_session(options: { "include_instant_repairs" => true }, counts: standard.merge("instant_repair" => 2)) do |harness, _runners, _advance|
      replay_prefixes(harness, standard.merge("instant_repair" => 2))
    end
    puts "PASS optional deck contains exactly two physical instant repairs through the native runner"

    counts = { "25" => 20, "instant_repair" => 6, "flat_tire" => 6, "speed_limit" => 2 }
    [true, false].each do |covered|
      with_session(options: custom_options(counts), counts: counts, covered: covered) do |harness, runners, advance|
        bot = harness.replay("Alice").players.find { |player| GameRoomParticipants.bot?(player) }
        assert(bot != nil && harness.replay("Alice").state[:hands].fetch(bot).grep(/^instant_repair:/).length >= 3, "Deterministic fixture did not deal the bot enough repairs")
        human_turn(harness, runners, "Alice", counts, attack: "flat_tire")
        human_turn(harness, runners, "Bob", counts, attack: "speed_limit")
        bot_repair(harness, advance, bot, "flat_tire")
        track = harness.replay("Alice").state[:tracks][2]
        assert(track[:hazards].empty? && track[:speed_limit] && !track[:moving], "Mechanical repair also removed the speed limit or supplied a green light")
        human_turn(harness, runners, "Alice", counts)
        human_turn(harness, runners, "Bob", counts)
        bot_repair(harness, advance, bot, "go")
        track = harness.replay("Alice").state[:tracks][2]
        assert(track[:moving] && track[:speed_limit], "Green-light repair removed a separate speed limit")
        human_turn(harness, runners, "Alice", counts)
        human_turn(harness, runners, "Bob", counts)
        bot_repair(harness, advance, bot, "speed_limit")
        track = harness.replay("Alice").state[:tracks][2]
        assert(track[:moving] && !track[:speed_limit], "Speed-limit repair stopped the bot or retained the restriction")
        human_turn(harness, runners, "Alice", counts, attack: "flat_tire")
        assert(harness.replay("Alice").state[:tracks][2][:hazards] == ["flat_tire"], "Instant repair made the bot immune to a later puncture")
        human_turn(harness, runners, "Bob", counts)
        bot_repair(harness, advance, bot, "flat_tire")
        assert(!harness.replay("Alice").state[:tracks][2][:moving], "Repeated mechanical repair supplied a green light")
        replay_prefixes(harness, counts)
      end
      puts "PASS instant repair bot via real runner, covered=#{covered}, two clients, duplicate delivery, custom counts and every replay prefix"
    end

    disabled = custom_options(counts).merge("include_instant_repairs" => false, "go_cards" => 2,
      "right_of_way_cards" => 9, "counterflow_cards" => 7, "end_counterflow_cards" => 8)
    effective = counts.merge("instant_repair" => 0, "go" => 2)
    with_session(options: disabled, counts: effective) do |harness, _runners, _advance|
      replay_prefixes(harness, effective)
    end
    puts "PASS custom counts respect disabled instant repairs, safeties and counterflow in persisted replay"

    standard_counterflow = standard.merge("instant_repair" => 2, "counterflow" => 4, "end_counterflow" => 6)
    reset = custom_options(counts).merge("custom_deck" => false, "include_safeties" => true,
      "counterflow" => true, "counterflow_cards" => 7, "end_counterflow_cards" => 8)
    with_session(options: reset, counts: standard_counterflow) do |harness, _runners, _advance|
      replay_prefixes(harness, standard_counterflow)
    end
    legacy = { "counterflow" => true, "counterflow_cards" => 2, "end_counterflow_cards" => 9 }
    legacy_counts = standard.merge("counterflow" => 2, "end_counterflow" => 9)
    with_session(options: legacy, counts: legacy_counts) do |harness, _runners, _advance|
      replay_prefixes(harness, legacy_counts)
    end
    puts "PASS explicit standard-deck reset and legacy counterflow counts survive native session serialization"

    exact = { "25" => 16, "go" => 2, "instant_repair" => 0 }
    with_session(options: custom_options(exact), counts: exact) do |harness, _runners, _advance|
      replay = harness.replay("Alice")
      assert(replay.state[:draw_pile].empty? && replay.state[:phase] == :playing, "Exact six-card-per-player deck invented a draw step")
      assert(harness.game.legal_actions(replay, "Alice").none? { |action| action["action"] == "draw" }, "Empty custom deck offered a phantom draw")
      replay_prefixes(harness, exact)
    end
    puts "PASS minimum custom deck deals six cards per seat with zero enabled repair copies and no phantom draw"
  end
end

MilleBornesSessionRegression.run
