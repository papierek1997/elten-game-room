require_relative '../../support/cheat'
include GameRoomTest::CheatFixture

cheat_start
4_095.times do
  actor = @replay.current_player
  selection = if @replay.state[:phase] == :reaction
    cheat_command('challenge')
  else
    claim = @game.send(:allowed_claims, @replay.state).first
    card = @replay.state[:hands].fetch(actor).find { |candidate| candidate[0] != claim }
    cheat_play([card])
  end
  status, plan = @game.action_for(selection, @replay, actor)
  assert_equal(:ok, status)
  command = plan.events.fetch(0)
  event = {'id' => @events.length + 1, 'actor' => actor, 'action' => command.action, 'value' => command.value}
  decoded = @game.send(:event_selection, event)
  assert_equal(:ok, @game.send(:validate_move, @replay.state, decoded, actor))
  @game.send(:apply_move, @replay.state, decoded, actor, event['id'], @replay.history)
  @replay.current_player = @replay.state[:current_player]
  @replay.winner = @replay.state[:winner]
  @replay.accepted_events << event
  @events << event
end
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
reconstructed = @game.replay(@session, @events, @repository)
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
assert_equal(@replay.state, reconstructed.state)
assert_equal(@events, reconstructed.accepted_events)
cheat_conservation(reconstructed.state)
assert(!reconstructed.finished?, 'History length awarded an artificial victory')
assert(elapsed < 5, "4096-record cold replay exceeded the bounded trial: #{elapsed}")
puts "PASS Cheat long history: 4096 accepted production transitions; cold replay #{elapsed.round(3)}s, exact state/conservation, no implicit result"
