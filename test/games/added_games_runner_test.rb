require_relative '../support/session_runner'
require_relative '../../games/go'
require_relative '../../games/roulette'
require_relative '../../games/dice_poker'
require_relative '../../games/blackjack'

cases = [[GameRoomGames::Go.new, {'variant'=>'atari'}],
  [GameRoomGames::Roulette.new, {'mode'=>'casino','round_limit'=>1}],
  [GameRoomGames::Roulette.new, {'mode'=>'social','round_limit'=>1}],
  [GameRoomGames::DicePoker.new, {'scoring'=>'chips','round_limit'=>1}],
  [GameRoomGames::Blackjack.new, {'variant'=>'social','round_limit'=>1}]]
cases.each do |game, options|
  options = game.new_game_options(options.merge('bot_delay'=>0))
  h = NativeRoomHarness.new(game:game, users:['Alice'], bots:1, options:options)
  h.start
  runner = runner_for(h)
  begin
    100.times do
      step(h, runner)
      replay = h.replay('Alice')
      break if replay.finished? || (game.id=='go' && replay.accepted_events.size>=8)
      next unless replay.current_player=='Alice'
      actions = game.legal_actions(replay,'Alice',context:runner.send(:context))
      next if actions.empty?
      selection = actions.find { |a| a['action']=='check' } || actions.find { |a| a['action']=='call' } ||
        actions.find { |a| a['action']=='stand' } || actions.find { |a| a['action']=='ready' } || actions.first
      h.as('Alice') { assert(runner.submit(session:h.session,replay:replay,selection:selection,actor:'Alice').first==:ok,'Active human write rejected') }
    end
    replay, events = h.replay('Alice'), h.events('Alice')
    assert(replay.finished? || (game.id=='go' && events.size>=8),'Active executor stalled')
    assert(events.any? { |e| GameRoomParticipants.bot?(e['actor']) },'Bot did not write through active executor')
    assert_equal(events.size, replay.accepted_events.size,'Executor wrote rejected events')
    random = events.select { |e| %w[roll spin deal].include?(e['action']) }
    assert(random.all? { |e| e['__server_random'] },'Game bypassed native entropy')
    h.assert_converged("#{game.id} #{options['mode']} active executor")
  ensure
    runner.close
  end
end
puts 'Active SessionRunner: Go, both roulette modes, chip dice poker and rotating-dealer blackjack; bot writes, ACKs, server entropy and convergence passed.'
