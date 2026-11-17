require_relative "../../support/ui"
require_relative "../../../lib/game_surfaces"
require_relative "bots_helpers"
require_relative "../../support/session_runner"

# In-memory native LiveSessions contract, real repository, codec, game replay
# and active GameRoomSessionRunner. No live account, network or worker thread.
module DuckBotRunnerFixture
  include GameRoomTest::Assertions
  LOGIC = GameRoomDuckRacing

  Clock = Struct.new(:value) do
    def now(_session); value.to_i; end
    def now_f(_session); value; end
  end

  # Worker backoff, turn scheduling and game time must advance together. A
  # virtual game deadline must not outrun the real monotonic retry clock.
  module MonotonicClock
    def clock_gettime(clock_id, *arguments)
      clock = Thread.current[:duck_bot_runner_clock]
      return clock.value if clock && clock_id == Process::CLOCK_MONOTONIC && arguments.empty?
      super
    end
  end
  Process.singleton_class.prepend(MonotonicClock)

  class Seed
    def initialize(value); @value = value; end
    def roll(count:, sides:)
      raise ArgumentError unless count == 16 && sides == 256
      bytes = Array.new(count) { |index| ((@value >> (8 * (count - index - 1))) & 255) + 1 }
      GameRoomRandom::Roll.new(values: bytes, sides: sides, source: "controlled test fixture")
    end
  end

  class Fixture
    include GameRoomTest::Assertions
    include DuckBotFixture
    attr_reader :harness, :runner, :clock, :plans, :game, :users

    def initialize(kind, bot_count: 2, bot_delay: 0, blackjack_opening: :decisions)
      @clock = Clock.new(1_000.0)
      @previous_clock = Thread.current[:duck_bot_runner_clock]
      Thread.current[:duck_bot_runner_clock] = clock
      @game = DuckBotFixture.game
      @users = %w[Host Observer]
      @options = game.default_options.merge("bot_delay" => bot_delay, "word_language" => "en",
        "question_language" => "en", "challenges" => [kind])
      @harness = NativeRoomHarness.new(game: game, users: users, options: @options, bots: bot_count)
      users.each { |user| harness.as(user) { harness.transports[user].set_observer(harness.table, true, actor: user) } }
      bots = harness.transports[users.first].room_snapshot(harness.table)[:bots]
      session = harness.as(users.first) do
        harness.repositories[users.first].start_session(table: harness.table, game: game.id,
          players: bots, options: JSON.generate(@options), recipients: users)
      end
      harness.instance_variable_set(:@session, session)
      seed = (0...10_000).find do |value|
        race = LOGIC::Race.start(player_count: bot_count, laps: 3, seed: value, enabled_challenges: [kind])
        race[:racers][0][:hand].any? { |card| card.type == "super_challenge" }
      end
      assert(seed, "No fixture seed contains the real challenge card")
      @plans = []
      @runner = runner_for(harness, users.first)
      runner.instance_variable_set(:@clock, clock)
      runner.instance_variable_get(:@turn).instance_variable_set(:@clock, -> { clock.value })
      template = runner.instance_variable_get(:@context_template)
      template.local_data = {"duck_host" => true,
        "duck_stack_entry_bytes" => harness.transports[users.first].game_action_limits(harness.table)['max_stack_entry_bytes']}
      # The ordinary executor now receives its start seed from the native
      # server draw, not from the context's local entropy source.
      harness.view(users.first).next_random_values = Seed.new(seed).roll(count:16,sides:256).values
      runner.send(:register_execution_group)
      virtual_clock = clock
      runner.instance_variable_get(:@game).define_singleton_method(:duck_automatic_now_ms) do |_replay|
        (virtual_clock.value * 1_000).round
      end
      planning = runner.instance_variable_get(:@planning_game)
      original, plans, lock = planning.method(:plan_duck_bot), @plans, runner.instance_variable_get(:@execution_group).operation
      planning.define_singleton_method(:plan_duck_bot) do |replay, actor, context: nil|
        raise "Planning under the executor write lock" if lock.mon_owned?
        value = original.call(replay, actor, context: context)
        if value
          plans << {actor: actor, challenge: replay.state[:round][:challenge][:id],
            started_at: replay.state[:round][:started_at], ready_ms: value[:ready_ms],
            trace: value[:trace], input: value[:input]}
        end
        value
      end
      tick(0)
      assert(replay.state[:race], "Observer host did not start the race")
      card = replay.state[:race][:racers][0][:hand].find { |copy| copy.type == "super_challenge" }
      assert(card)
      if kind == 'blackjack'
        # Race actions receive their own native random receipt, independently
        # of the initial deal. An all-natural opening resolves without input;
        # delay/timeout tests explicitly need unfinished player decisions.
        opening_seed = (0...10_000).find do |candidate|
          race = Marshal.load(Marshal.dump(replay.state[:race]))
          race[:random] = Random.new(candidate)
          accepted = LOGIC::Race.new(race).apply(seat:0, revision:race[:revision],
            action:{kind: :play, card:card.id})
          next false unless accepted && race[:challenge]
          engine = LOGIC::ChallengeEngine.start(race[:challenge], resources:DuckBotFixture.resources)
          players = engine[:model][:players].values
          blackjack_opening == :all_natural ? players.all? { |player| player[:done] } :
            players.none? { |player| player[:done] }
        end
        assert(opening_seed, "No controlled blackjack opening for #{blackjack_opening}")
        harness.view(users.first).next_random_values = Seed.new(opening_seed).roll(count:16,sides:256).values
      end
      # The real dealt physical card opens the challenge. No state injection.
      status, = harness.as(users.first) do
        runner.submit(session: harness.session, replay: replay,
          selection: {"kind" => "duck", "action" => "race", "input" => {"kind" => "play", "card" => card.id}},
          actor: replay.players[0], controller: true)
      end
      assert_equal(:ok, status)
      @challenge_id = replay.state.fetch(:round).fetch(:challenge).fetch(:id)
      20.times do
        break if replay.state.dig(:round, :phase) == :playing || replay.state[:last_resolution]
        tick(0.01)
      end
      immediately_resolved = blackjack_opening == :all_natural && kind == 'blackjack' &&
        replay.state.dig(:last_resolution, :id) == @challenge_id
      assert(immediately_resolved || replay.state.dig(:round, :phase) == :playing,
        "Readiness stalled: #{replay.state.dig(:round, :ready).inspect}; players=#{replay.players.inspect}; " \
        "controllers=#{replay.state[:controllers].inspect}; local=#{runner.send(:context).local_data.inspect}; " \
        "actions=#{wire.map { |data| data.slice('action', 'actor') }.inspect}")
      if kind == "simon"
        # Table IDs are intentionally random in the native broker. Select an
        # explicit bot skill/reaction seed for this one boundary scenario;
        # the resulting full trace still uses the real planner and verifier.
        challenge = replay.state[:round][:challenge]
        long_seed = (0...100).find do |candidate|
          LOGIC::ChallengeBot.plan(challenge, seat: 0, seed: candidate,
            resources: DuckBotFixture.resources)["finished_at"] > 90_000
        end
        assert(long_seed, "No controlled bot seed crosses the idle boundary")
        ordinary_hash = planning.method(:duck_bot_hash)
        planning.define_singleton_method(:duck_bot_hash) do |value|
          value.is_a?(Array) && value.length == 4 && value[2] == 0 && value[3].is_a?(String) ? long_seed : ordinary_hash.call(value)
        end
      end
    rescue Exception
      close
      raise
    end

    def replay; harness.replay(users.first); end

    def tick(delta = 0.25)
      clock.value += delta
      # This fixture exercises verified bot actions, not speech timing. Model
      # the screen's completed presentation acknowledgement on every revision;
      # pacing_client_runner_test covers the real busy/pause boundary.
      runner.publish_view(session: harness.session, replay: replay, busy: false,
        context: runner.instance_variable_get(:@context_template))
      step(harness, runner, users.first)
      current = replay
      assert_equal(harness.events(users.first).length, current.accepted_events.length,
        "The runner wrote an action rejected by the actual replay")
      current
    end

    def wire
      repository = harness.repositories.fetch(users.first)
      decoded = []
      GameRoomActionPayload.each(harness.events(users.first), game.id, repository, harness.session) do |data, actor, _|
        decoded << data.merge("actor" => actor)
      end
      decoded
    end

    def finish(limit: 4_000)
      return replay if replay.state.dig(:last_resolution, :id) == @challenge_id
      limit.times do
        current = tick
        if current.state[:last_resolution]
          assert_equal(@challenge_id, current.state[:last_resolution][:id])
          return current
        end
      end
      raise "Bot challenge stalled after #{limit} executor ticks: #{replay.state[:round].inspect}"
    end

    def assert_converged(label)
      events = users.map { |user| harness.events(user) }
      assert(events.all? { |value| value == events.first }, "#{label}: ordered stacks differ")
      states = users.map { |user| semantic(GameRoomTest::ReplaySnapshot.capture(harness.replay(user))) }
      assert(states.all? { |value| value == states.first }, "#{label}: complete replays differ")
    end

    def close
      runner&.close
      runner&.send(:unregister_execution_group)
      harness&.as(users.first) { harness.view(users.first)&.close }
    ensure
      Thread.current[:duck_bot_runner_clock] = @previous_clock if Thread.current[:duck_bot_runner_clock].equal?(clock)
    end
  end
end

include GameRoomTest::Assertions
cases = []
case_filter = Regexp.new(ENV.fetch("DUCK_BOT_CASE")) if ENV.key?("DUCK_BOT_CASE")
check = lambda do |name, &block|
  next if case_filter && !case_filter.match?(name)

  block.call
  cases << {name: name, status: "PASS"}
rescue StandardError => error
  cases << {name: name, status: "FAIL", error: "#{error.class}: #{error.message}", backtrace: error.backtrace.first(8)}
end

check.call('blackjack all-natural opening: immediate settlement, no artificial bot decision') do
  h = DuckBotRunnerFixture::Fixture.new('blackjack', blackjack_opening: :all_natural)
  begin
    finished = h.finish
    assert(finished.state[:round].nil?, 'natural 21s still require an input round')
    assert(finished.state[:last_resolution][:settlement], 'natural opening has no settlement')
    assert(h.wire.none? { |data| data['action'] == 'input' }, 'an already complete hand submitted a bot move')
    h.assert_converged('immediate blackjack settlement')
  ensure
    h.close
  end
end

(["simon"] + GameRoomDuckRacing::ChallengeEngine::FIRST_ANSWER).each do |kind|
  check.call("observer host: #{kind}, real bot executor, complete verified attempt, continued race") do
    h = DuckBotRunnerFixture::Fixture.new(kind)
    begin
      finished = h.finish
      assert_equal(:turn, finished.state[:race][:phase])
      assert(finished.state[:last_resolution][:settlement])
      messages = h.wire
      assert(messages.none? { |data| data["action"] == "cancel" })
      commits = messages.select { |data| data["action"] == "commit" }
      reveals = messages.select { |data| data["action"] == "reveal" }
      if kind == "simon"
        assert_equal([], commits)
        assert_equal([], reveals)
        submissions = messages.select { |data| data['action'] == 'result' }
        assert_equal(2, submissions.length)
        assert_equal(2, submissions.map { |data| data['actor'] }.uniq.length)
        assert(submissions.all? { |data| data['answer'].keys == ['score'] })
      else
        assert_equal([], commits)
        assert_equal([], reveals)
        submissions = messages.select { |data| data["action"] == "attempt" }
        assert(submissions.length.between?(1, 2))
        settlement = finished.state[:last_resolution][:settlement]
        assert(settlement.transfers.all? { |transfer| transfer.amount == 4 })
      end
      submissions.each do |data|
        plan = h.plans.find { |entry| entry[:actor] == data["actor"] }
        assert(plan)
        assert(data["at"] >= plan[:ready_ms], "A bot submitted before its simulated completion")
        preparation = GameRoomDuckRacing::ChallengeEngine::SPEED_TYPES.include?(kind) ?
          GameRoomDuckRacing::ChallengeEngine::PREPARATION_MS : 0
        preparation = GameRoomDuckRacing::ChallengeEngine::COUNT_DUCKS_PREPARATION_MS if kind == 'count_ducks'
        unless kind == 'simon'
          assert_equal(plan[:ready_ms] - plan[:started_at] - preparation, plan[:trace]["finished_at"])
        end
      end
      if kind == "simon"
        assert(h.plans.any? { |entry| entry[:ready_ms] - entry[:started_at] > 90_000 }, "Fixture did not cross the idle boundary")
        alive = messages.select { |data| data["action"] == "alive" }
        assert_equal(2, alive.map { |data| data["actor"] }.uniq.length)
        assert(alive.length >= 6)
      end
      h.assert_converged("#{kind} observer-host bot challenge")
      count = h.harness.events(h.users.first).length
      12.times do
        break if h.harness.events(h.users.first).length > count
        h.tick
      end
      assert(h.harness.events(h.users.first).length > count, "Race did not continue after the challenge")
    ensure
      h.close
    end
  end
end

GameRoomDuckRacing::ChallengeEngine::SEQUENTIAL.each do |kind|
  check.call("observer host: #{kind}, actual replay history and finite sequential bot actions") do
    h = DuckBotRunnerFixture::Fixture.new(kind)
    begin
      first = h.replay
      decision_count = if kind == "blackjack"
        first.state[:round][:engine][:model][:players].count { |_seat, player| !player[:done] }
      else
        2
      end
      finished = h.finish
      messages = h.wire
      assert(messages.none? { |data| %w[cancel commit reveal].include?(data["action"]) })
      inputs = messages.select { |data| data["action"] == "input" }
      minimum_inputs = {"dice_duel" => 2, "blackjack" => decision_count,
        "risky_dice" => 2, "numbered_balls" => 4, "sound_memory" => 10}.fetch(kind)
      assert(inputs.length >= minimum_inputs, "#{kind} completed without the required bot decisions")
      assert_equal(decision_count, inputs.map { |data| data["actor"] }.uniq.length)
      if kind == 'blackjack'
        initial_model = first.state[:round][:engine][:model]
        expected_order = initial_model[:participants].rotate(initial_model[:turn_index]).reject do |seat|
          initial_model[:players].fetch(seat)[:done]
        end.map { |seat| first.players.fetch(seat) }
        assert_equal(expected_order, inputs.map { |data| data['actor'] }.chunk(&:itself).map(&:first),
          'Blackjack bot attempts interleaved before a player finished drawing')
      end
      if %w[dice_duel blackjack risky_dice].include?(kind)
        notices = finished.history.select { |entry| [:challenge_roll, :challenge_draw, :challenge_stand].include?(entry.kind) }
        assert_equal(inputs.length, notices.length, "Accepted bot inputs must appear exactly once in public history")
        assert(notices.all? { |entry| !entry.text.empty? })
      end
      assert_equal([], h.replay.state[:duck_challenge_events], "Finished challenge retained public memory")
      h.assert_converged("#{kind} sequential bots")
    ensure
      h.close
    end
  end
end

%w[dice_duel blackjack risky_dice].each do |kind|
  check.call("observer host: #{kind}, real executor advances the current player's timeout") do
    h = DuckBotRunnerFixture::Fixture.new(kind)
    begin
      before = h.replay
      initial_model = before.state[:round][:engine]
      turn = GameRoomDuckRacing::ChallengeEngine.current_turn(initial_model)
      actor = before.players.fetch(turn)
      deadline = before.state[:round][:started_at] + initial_model[:model][:deadline_ms]
      after = h.tick(deadline / 1_000.0 - h.clock.value)
      # At thirty seconds the ordinary executor may first publish the two
      # due presence pulses. Keep the exact clock boundary and let those
      # accepted operations drain; do not submit the timeout by hand.
      initial_model[:participants].length.times do
        break if h.wire.any? { |data| data["action"] == "advance" }
        after = h.tick(0)
      end
      advances = h.wire.select { |data| data["action"] == "advance" }
      assert_equal(1, advances.length, "A due decision must be finished by the normal automatic executor")
      assert_equal(deadline, advances.first.fetch("at"))
      notices = after.history.drop(before.history.length).select do |entry|
        [:challenge_roll, :challenge_draw, :challenge_stand].include?(entry.kind)
      end
      expected = {"dice_duel" => [:challenge_roll], "blackjack" => [:challenge_stand],
        "risky_dice" => [:challenge_roll, :challenge_stand]}.fetch(kind)
      assert_equal(expected, notices.map(&:kind))
      if after.state[:round]
        assert(after.state[:round][:engine][:model][:players].fetch(turn)[:done])
        assert(GameRoomDuckRacing::ChallengeEngine.current_turn(after.state[:round][:engine]) != turn)
      end
      finished = h.finish
      assert(finished.state[:last_resolution][:settlement])
      assert(h.wire.none? { |data| %w[cancel commit reveal].include?(data["action"]) })
      assert(h.wire.none? { |data| data["action"] == "input" && data["actor"] == actor },
        "The timed-out bot must not later submit a stale planned action")
      h.assert_converged("#{kind} executor timeout")
    ensure
      h.close
    end
  end
end

%w[dice_duel blackjack risky_dice numbered_balls sound_memory sound_order copy_number guess_number quiz rhythm hit_duck].each do |kind|
  check.call("configured delay: #{kind}, real executor, no early or duplicate writes") do
    h = DuckBotRunnerFixture::Fixture.new(kind, bot_delay: 3)
    begin
      start = h.replay.state[:round][:started_at]
      10.times { h.tick(0.25) }
      assert(h.wire.none? { |data| %w[input attempt commit result].include?(data['action']) },
        "#{kind}: bot moved before its configured pause")
      h.finish
      messages = h.wire.select { |data| %w[input attempt commit result].include?(data['action']) }
      assert(!messages.empty?, "#{kind}: no bot decisions were submitted")
      messages.each do |data|
        plan = h.plans.find { |entry| entry[:actor] == data['actor'] &&
          (data['action'] != 'input' || entry[:input] == data['input']) }
        assert(plan, "No cached plan for #{data.inspect}")
        assert(data['at'] >= plan[:ready_ms] && data['at'] >= start + 3_000)
      end
      inputs = messages.select { |data| data['action'] == 'input' }
      assert_equal(inputs.length, inputs.map { |data| [data['actor'], data['input']['press_id']] }.uniq.length)
      assert(h.wire.none? { |data| data['action'] == 'cancel' })
      h.assert_converged("#{kind} configured delay")
    ensure
      h.close
    end
  end
end

report_dir = File.expand_path("../../../tmp/duck-racing", __dir__)
FileUtils.mkdir_p(report_dir)
path = File.join(report_dir, "bot-runner-local.json")
report = File.file?(path) ? JSON.parse(File.read(path)) : {"runs" => []}
run = {scope: "Actual active executor and codec/repository over an in-memory native LiveSessions broker, virtual time, no live accounts",
  filter: case_filter&.source, cases: cases, failures: cases.count { |entry| entry[:status] == "FAIL" }}
report["runs"] << run
File.write(path, JSON.pretty_generate(report) + "\n")
cases.select { |entry| entry[:status] == "FAIL" }.each { |entry| warn "FAIL #{entry[:name]}: #{entry[:error]}" }
raise "#{run[:failures]} Duck bot runner checks failed" unless run[:failures].zero?
raise "No bot runner cases matched #{case_filter.inspect}" if cases.empty?
puts "PASS #{cases.length} Duck Racing native-contract bot runner scenarios"
