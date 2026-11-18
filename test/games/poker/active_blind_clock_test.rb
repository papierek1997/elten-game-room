require_relative '../../support/card_timeouts'

%w[holdem draw].each do |variant|
  trial = TimedCardCase.new(GameRoomGames::Poker.new,
    {'variant' => variant, 'blind_interval' => 'minutes', 'blind_interval_value' => 1,
      'blind_multiplier' => 2, 'starting_chips' => 10000, 'thinking_time' => 120}, %w[A B])
  game = trial.game
  trial.context.now = 155
  trial.act({'action' => 'fold'})
  trial.context.now = 160
  trial.act({'kind' => 'command', 'action' => 'deal'}, 'A')
  assert(trial.replay.state[:blind_paused_seconds] == 5, "#{variant}: five-second gap counted as play")
  assert(game.send(:blind_level, trial.replay.state).zero?, "#{variant}: blinds rose at 55 seconds of play")
  trial.context.now = 165
  trial.act({'action' => 'fold'})
  trial.context.now = 200 # A longer delay must not accelerate the blinds either.
  trial.act({'kind' => 'command', 'action' => 'deal'}, 'A')
  assert(trial.replay.state[:blind_paused_seconds] == 40, "#{variant}: only nominal pauses were deducted")
  assert(game.send(:blind_level, trial.replay.state) == 1, "#{variant}: 60 seconds of actual play did not raise blinds")
  assert(trial.replay.state[:turn_deadline] == 320, "#{variant}: a gap consumed the new turn's time")
  restored = game.replay(trial.session, trial.events, trial.repo)
  assert(restored.state == trial.replay.state, "#{variant}: cold replay changed the blind clock")
  hands = restored.state.merge(options: restored.state[:options].merge('blind_interval' => 'hands', 'blind_interval_value' => 2))
  assert(game.send(:blind_level, hands) == 1, "#{variant}: gaps changed hand-count escalation")
end
puts 'PASS Poker blinds: Holdem/draw, short/long gaps, full turn time, cold replay and unchanged hand-count escalation'
