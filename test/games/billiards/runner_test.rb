require_relative '../../support/billiards'
require_relative '../../support/session_runner'

module BilliardsRunnerTest
  extend GameRoomTest::Assertions
  def self.run
    game = GameRoomGames::Billiards.new
    harness = NativeRoomHarness.new(game: game, users: ['Alice', 'Observer'], bots: 2,
      options: game.normalize_options('shots'=>6, 'bot_delay'=>0))
    harness.users.each { |user| harness.as(user) { harness.transports[user].set_observer(harness.table, true, actor: user) } }
    bots = harness.transports['Alice'].room_snapshot(harness.table)[:bots]
    session = harness.as('Alice') do
      harness.repositories['Alice'].start_session(table: harness.table, game: game.id, players: bots,
        options: JSON.generate(game.normalize_options('shots'=>6, 'bot_delay'=>0)), recipients: harness.users)
    end
    harness.instance_variable_set(:@session, session)
    runner = runner_for(harness)
    writes = []
    commit = runner.method(:commit)
    runner.define_singleton_method(:commit) do |selection, actor, **options|
      result = commit.call(selection, actor, **options)
      writes << result.first
      result
    end
    40.times do
      runner.publish_view(session: session, replay: harness.replay('Alice'), busy: false,
        context: GameRoomGames::ActionContext.new)
      step(harness, runner)
      break if harness.replay('Alice').finished?
    end
    final = harness.replay('Alice')
    assert(final.finished?, "Active runner stalled after #{final.state[:shots]} shots: #{writes.uniq.inspect}")
    assert(writes.all? { |status| status == :ok }, 'An ordinary bot action exceeded the event protocol')
    assert(final.accepted_events.any? { |e| e['action'] == 'shot' }, 'No bot shot was written')
    assert(final.state[:last], 'Runner lost physical outcome')
    harness.assert_converged('billiards bot practice')
    puts "Billiards runner: observer host, #{bots.size} bots, #{final.accepted_events.size} acknowledged events and converged clients passed."
  ensure
    runner&.close
  end
end
BilliardsRunnerTest.run if $PROGRAM_NAME == __FILE__
