require_relative '../../support/billiards'
require_relative '../../support/session_runner'

module BilliardsCompetitionRunnerTest
  extend GameRoomTest::Assertions
  def self.run
    runner = nil
    %w[eight nine snooker].each do |discipline|
      game = GameRoomGames::Billiards.new
      options = game.normalize_options('discipline'=>discipline, 'bot_delay'=>0, 'bot_skill'=>'easy', 'rack_seed'=>123)
      harness = NativeRoomHarness.new(game: game, users: ['Alice', 'Observer'], bots: 2, options: options)
      harness.users.each { |user| harness.as(user) { harness.transports[user].set_observer(harness.table, true, actor: user) } }
      bots = harness.transports['Alice'].room_snapshot(harness.table)[:bots]
      session = harness.as('Alice') do
        harness.repositories['Alice'].start_session(table: harness.table, game: game.id, players: bots,
          options: JSON.generate(options), recipients: harness.users)
      end
      harness.instance_variable_set(:@session, session)
      runner = runner_for(harness)
      writes = []
      commit = runner.method(:commit)
      runner.define_singleton_method(:commit) do |selection, actor, **args|
        result = commit.call(selection, actor, **args)
        writes << result.first
        result
      end
      32.times do
        runner.publish_view(session: session, replay: harness.replay('Alice'), busy: false, context: GameRoomGames::ActionContext.new)
        step(harness, runner)
        break if harness.replay('Alice').state[:shots] >= 4 || harness.replay('Alice').finished?
      end
      replay = harness.replay('Alice')
      assert(replay.state[:shots] >= 4 || replay.finished?, "#{discipline} stalled: #{writes.inspect}")
      assert(writes.all? { |status| status == :ok }, "#{discipline}: #{writes.inspect}")
      assert(replay.accepted_events.any? { |e| e['action'] == 'shot' })
      harness.assert_converged("#{discipline} competition")
      runner.close
      runner = nil
    end
    puts 'Competitive billiards executor: 8-ball, 9-ball and snooker bots, observer host, acknowledged legal decisions/shots and converged clients passed.'
  ensure
    runner&.close
  end
end
BilliardsCompetitionRunnerTest.run if $PROGRAM_NAME == __FILE__
