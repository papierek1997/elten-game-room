require_relative '../../support/card_timeouts'

game = GameRoomGames::Poker.new
trial = TimedCardCase.new(game, {}, %w[A B])
trial.context.now = 110
trial.act({'action' => 'fold'})
finished = trial.replay
assert(finished.state[:phase] == :hand_complete, 'The fixture did not finish a hand')
assert(finished.state[:hand_resume_at] == 115, 'The pause is not tied to the accepted final action')

[110, 114].each do |now|
  trial.context.now = now
  assert(game.automatic_action(finished, 'A', context: trial.context).nil?, 'A new hand started before five seconds')
  assert(!game.automatic_action_due?(finished, 'A', context: trial.context), 'The deadline is due too early')
  status, plan = game.action_for({'kind' => 'command', 'action' => 'deal'}, finished, 'A', context: trial.context)
  assert(status != :ok && plan.nil?, 'An already selected deal bypassed the pause')
end
trial.context.now = 115
assert(game.automatic_action_due?(finished, 'A', context: trial.context), 'An unchanged revision never wakes at the deadline')
assert(game.automatic_action(finished, 'A', context: trial.context)['action'] == 'deal', 'The boundary does not deal')
assert(!game.automatic_action_due?(finished, 'B', context: trial.context), 'A non-executor claims the next deal')
assert(game.replay(trial.session, trial.events, trial.repo).state[:hand_resume_at] == 115, 'Replaying restarts the delay')

# A later pause does not move an earlier accepted deadline. The attached clock
# freezes progression and applies the same completed offset when it resumes.
frozen_session = trial.session.merge('__frozen_at' => 614, '__clock_offset' => 500)
frozen = game.replay(frozen_session, trial.events, trial.repo)
assert(frozen.state[:hand_resume_at] == 115, 'A later freeze moved the accepted boundary')
assert(game.automatic_action(frozen, 'A').nil?, 'Frozen logical time consumed the remaining second')
resumed = game.replay(trial.session.merge('__frozen_at' => 715, '__clock_offset' => 600), trial.events, trial.repo)
assert(game.automatic_action(resumed, 'A')['action'] == 'deal', 'A resumed clock reset the boundary')

trial.act({'kind' => 'command', 'action' => 'deal'}, 'A')
assert(trial.replay.state[:hand_number] == 2 && trial.replay.state[:turn_deadline] == 135,
  'The next hand did not receive its full thinking time')
assert(trial.replay.state[:hand_resume_at].to_i.zero?, 'The previous delay leaked into the new hand')

# Untimed poker still uses authenticated event timestamps for the inter-hand
# pause. Event-local offsets, not a later table offset, date the final fold.
off = TimedCardCase.new(game, {'thinking_time' => 0}, %w[A B])
off.context.now = 110
off.act({'action' => 'fold'})
off.events.each { |event| event['created_at'] = 210; event['__clock_offset'] = 10 }
off_session = off.session.merge('created_at' => 100, '__server_started_at' => 190,
  '__clock_offset' => 60, '__frozen_at' => 264)
off_replay = game.replay(off_session, off.events, off.repo)
assert(off_replay.state[:hand_resume_at] == 115, 'Untimed pause did not translate the accepted server timestamp once')
assert(game.automatic_action(off_replay, 'A').nil?, 'Untimed frozen clock skipped the pause')
assert(!off_replay.state.key?(:turn_deadline), 'Inter-hand pause enabled a disabled turn timer')

# Historical immediate deals remain replayable; the presentation pause is
# not a new anti-cheat protocol that invalidates accepted old archives.
legacy = trial.events.map(&:dup)
legacy.last['value'] = legacy.last['value'].sub(/:[0-9a-z]+\z/, ":#{110.to_s(36)}")
restored = game.replay(trial.session, legacy, trial.repo)
assert(restored.accepted_events == legacy && restored.state[:hand_number] == 2,
  'The new scheduling pause invalidated old immediate-deal history')

puts 'PASS Poker: accepted logical five-second pause, untimed timestamps, freeze, replay, due wakeup and legacy deals'
