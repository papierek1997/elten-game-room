require_relative '../../support/session_runner'
require_relative '../../../games/cheat'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

%w[ascending descending neighbour fixed_bluff suit].each do |variant|
  game = GameRoomGames::Cheat.new
  room = NativeRoomHarness.new(game: game, users: %w[Alice Bob Carol],
    options: game.normalize_options('variant' => variant, 'bot_delay' => 0))
  room.start
  runners = room.users.to_h { |user| [user, runner_for(room, user)] }
  begin
    room.view('Alice').next_random_values = Array.new(16, 2)
    step(room, runners.fetch('Alice'))
    room.assert_converged('native deal', expected_count: 1)
    assert_equal(1, room.view('Alice').calls[:random], 'Deal used client-only or repeated randomness')
    snapshots = {}
    decisions = 0
    challenged = false
    until room.replay('Alice').finished?
      replay = room.replay('Alice')
      actor = replay.current_player
      actions = game.legal_actions(replay, actor)
      action = if replay.state[:phase] == :reaction
        command = !challenged && replay.state[:pile].length >= 3 ? 'challenge' : 'accept'
        challenged ||= command == 'challenge'
        actions.find { |candidate| candidate['action'] == command }
      else
        actions.select { |candidate| candidate['action'] == 'play' }.max_by { |candidate| JSON.parse(candidate['cards']).length }
      end
      previous = room.events('Alice').length
      room.as(actor) do
        status, = runners.fetch(actor).submit(session: room.session, replay: replay, selection: action, actor: actor)
        assert_equal(:ok, status, 'Ordinary executor rejected a human decision')
      end
      room.assert_converged('accepted decision', expected_count: previous + 1)
      if decisions.zero?
        stale = replay
        room.as(actor) do
          assert_raises(GameRoomSessionRunner::StaleView) do
            runners.fetch(actor).submit(session: room.session, replay: stale, selection: action, actor: actor)
          end
        end
        assert_equal(previous + 1, room.events('Alice').length)
      end
      decisions += 1
      assert(decisions < 180, 'Explicit human match failed to finish')
    end
    result = room.replay('Alice')
    assert(result.winner && !result.draw, 'Single winner is missing')
    assert_equal(result.accepted_events.length, room.events('Bob').length)
    assert(challenged, 'Match did not cover a challenge')
  ensure
    runners.each_value(&:close)
  end
end
puts 'PASS Cheat normal executor: five complete explicit-human matches, authenticated server seed, three clients, reaction, challenge, pile transfer, stale refusal and one result (local broker)'
