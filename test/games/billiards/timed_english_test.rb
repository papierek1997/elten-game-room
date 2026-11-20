require_relative '../../support/billiards'
require_relative '../../support/session_runner'

module BilliardsTimedEnglishTest
  extend GameRoomTest::Assertions
  def self.run
    game = GameRoomGames::Billiards.new
    options = {'discipline'=>'english', 'english_limit'=>'time', 'time_limit_minutes'=>1, 'race_to'=>2}
    match = BilliardsFixture::Match.new(players: %w[Alice Bob], options: options)
    assert_equal([], game.legal_actions(match.replay, 'Alice'), 'Timed play started without an accepted clock boundary')
    start = game.automatic_action(match.replay, 'Alice', context: GameRoomGames::ActionContext.new(now: 1000))
    assert_equal('clock_start', start['action'])
    assert_equal(nil, game.automatic_action(match.replay, 'Bob', context: GameRoomGames::ActionContext.new(now: 1000)))
    status, plan = game.action_for(start, match.replay, 'Alice')
    assert_equal(:ok, status)
    oversized = match.replay
    oversized.state[:revision] = 10**80
    assert_equal(:invalid, game.action_for(start.merge('revision'=>10**80), oversized, 'Alice').first)
    match.events << {'id'=>1, 'actor'=>'Alice', 'action'=>'clock_start', 'value'=>plan.events.first.value, 'created_at'=>1000}
    assert_equal(1000, match.replay.state[:english_started_at])
    early = game.automatic_action(match.replay, 'Alice', context: GameRoomGames::ActionContext.new(now: 1059))
    assert_equal(nil, early)
    time = game.automatic_action(match.replay, 'Alice', context: GameRoomGames::ActionContext.new(now: 1060))
    assert_equal('time', time['action'])
    assert_equal(:invalid, game.action_for(time, match.replay, 'Bob', context: GameRoomGames::ActionContext.new(now: 1060)).first)
    assert_equal(:invalid, game.action_for(time, match.replay, 'Alice', context: GameRoomGames::ActionContext.new(now: 1059)).first)
    status, plan = game.action_for(time, match.replay, 'Alice', context: GameRoomGames::ActionContext.new(now: 1060))
    assert_equal(:ok, status)
    match.events << {'id'=>2, 'actor'=>'Alice', 'action'=>'time', 'value'=>plan.events.first.value, 'created_at'=>1060}
    after = match.replay
    assert_equal(:rack_end, after.state[:phase])
    assert_equal(nil, after.state[:rack_winner])
    assert_equal([0, 0], after.state[:racks])
    next_move = match.selection('choice', 'choice'=>0)
    status, plan = game.action_for(next_move, after, after.current_player, context: GameRoomGames::ActionContext.new(now: 1061))
    assert_equal(:ok, status)
    match.events << {'id'=>3, 'actor'=>after.current_player, 'action'=>'choice', 'value'=>plan.events.first.value, 'created_at'=>1061}
    assert_equal(nil, match.replay.state[:english_started_at], 'The next frame reused an expired clock')
    assert_equal(match.replay, GameRoomGames::Billiards.new.replay(match.session, match.events, match.repository))
    check_inflight(options)
    check_executor
    puts 'Timed English billiards: authenticated start/expiry, early and foreign refusal, next-frame clock, late-shot refusal, complete in-flight simulation, cold replay and active executor passed.'
  end

  def self.check_inflight(options)
    match = BilliardsFixture::Match.new(players: %w[Alice Bob], options: options.merge('race_to'=>1))
    match.events << {'id'=>1, 'actor'=>'Alice', 'action'=>'clock_start', 'value'=>'[1,0]', 'created_at'=>1000}
    move = match.game.legal_actions(match.replay, 'Alice').first
    move['shot']['power'] = 1000
    status, plan = match.game.action_for(move, match.replay, 'Alice', context: GameRoomGames::ActionContext.new(now: 1059))
    assert_equal(:ok, status)
    event = {'id'=>2, 'actor'=>'Alice', 'action'=>'shot', 'value'=>plan.events.first.value, 'created_at'=>1059}
    match.events << event
    assert_equal(1, match.replay.state[:shots])
    assert(match.replay.state[:last].duration > 1, 'Fixture did not cross TIME during the stroke')
    late = BilliardsFixture::Match.new(players: %w[Alice Bob], options: options.merge('race_to'=>1))
    late.events.concat([match.events.first, event.merge('created_at'=>1060)])
    assert_equal(0, late.replay.state[:shots], 'A stroke beginning at TIME changed the table')
    assert_equal(1, late.replay.accepted_events.length)
  end

  def self.check_executor
    previous = Time.method(:now)
    now = 1_800_000_000
    Time.define_singleton_method(:now) { Time.at(now) }
    game = GameRoomGames::Billiards.new
    h = NativeRoomHarness.new(game: game, users: %w[Alice Bob], options: game.normalize_options(
      'discipline'=>'english', 'english_limit'=>'time', 'time_limit_minutes'=>1))
    h.start
    runner = runner_for(h)
    clock = Object.new
    clock.define_singleton_method(:now) { |_session| now }
    runner.instance_variable_set(:@clock, clock)
    tick = -> do
      runner.publish_view(session: h.session, replay: h.replay('Alice'), busy: false, context: GameRoomGames::ActionContext.new)
      step(h, runner)
    end
    3.times { tick.call }
    assert_equal(['clock_start'], h.events('Alice').map { |e| e['action'] })
    now += 61
    3.times { tick.call }
    assert(h.replay('Alice').finished?, 'The active session executor missed TIME')
    assert_equal(%w[clock_start time], h.events('Alice').map { |e| e['action'] })
    3.times { tick.call }
    assert_equal(2, h.events('Alice').length, 'TIME was written repeatedly')
    h.assert_converged('timed English expiry')
  ensure
    runner&.close
    Time.define_singleton_method(:now, previous) if previous
  end
end
BilliardsTimedEnglishTest.run if $PROGRAM_NAME == __FILE__
