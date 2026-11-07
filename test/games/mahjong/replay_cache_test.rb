require_relative '../../support/assertions'
require_relative '../../support/mahjong_table_game'
include GameRoomTest::Assertions
include MahjongTableGameTest

repository = MahjongTableGameTest::Repository.new
session = {'id'=>45, 'players'=>%w[Alice Bob Carol Dave],
  'options'=>JSON.generate('variant'=>'hong_kong', 'seats'=>4, 'match_winds'=>1)}
generator = MahjongTableGameTest::Game.new
context = GameRoomGames::ActionContext.new(session_id: 45, random_source: MahjongTableGameTest::RandomSource.new)
events = []
expected = generator.replay(session, events, repository)
6500.times do
  # A change in bot strategy can remove dealer repeats and legitimately
  # finish the match at hand four instead of leaving it between hands.
  break if expected.finished?
  break if expected.state[:hand_number] >= 4 && expected.state[:phase] == :between_hands
  actor = generator.active_actors(expected).first
  selection = generator.automatic_action(expected, actor, context: context) || generator.table_bot_selection(expected, actor)
  status, plan = generator.action_for(selection, expected, actor, context: context)
  assert_equal(:ok, status)
  event = table_event(events.size + 1, plan.events.first, actor: actor)
  events << event
  expected = generator.incremental_replay(expected, session, [event], repository)
end
assert_equal(4, expected.state[:hand_number])
assert([:between_hands, :finished].include?(expected.state[:phase]), 'Fixture did not complete the fourth hand')

signature = lambda do |replay|
  [round_snapshot(replay.state[:round]), replay.state[:phase], replay.state[:hand_number],
    replay.state[:match].points, replay.state[:match].dealer, replay.accepted_events, replay.history]
end
game = MahjongTableGameTest::Game.new
processed = 0
reduce = game.method(:reduce_mahjong_table)
game.define_singleton_method(:reduce_mahjong_table) do |*arguments|
  processed += arguments.fetch(3).size
  reduce.call(*arguments)
end
actual = nil
(0..events.size).each do |count|
  actual = game.replay(session.merge('__game_revision'=>count), events.take(count), repository)
end
assert_equal(events.size, processed, 'Warm refresh replayed earlier Mahjong moves')
assert_equal(signature.call(expected), signature.call(actual), 'Warm Hong Kong replay changed four-hand gameplay')
assert_equal(signature.call(expected), signature.call(MahjongTableGameTest::Game.new.replay(session, events, repository)))

# Returning a mutable UI/planning replay never exposes the retained checkpoint.
actual.history = []
again = game.replay(session, events, repository)
assert_equal(signature.call(expected), signature.call(again), 'A caller mutated the cached checkpoint')
assert_equal(events.size, processed, 'Unchanged input repeated a rule transition')

# Looking at an older prefix must not evict the current longer state.
game.replay(session, events.take(9), repository)
after_history = processed
assert_equal(signature.call(expected), signature.call(game.replay(session, events, repository)))
assert_equal(after_history, processed, 'Historical view evicted the latest checkpoint')

# A corrected early record at exactly the same length invalidates the cache.
changed = GameRoomSnapshot.copy(events)
changed[3]['value'] = '{invalid'
observed = game.replay(session, changed, repository)
cold = MahjongTableGameTest::Game.new.replay(session, changed, repository)
assert_equal(signature.call(cold), signature.call(observed), 'Earlier corrected record reused an old model')
assert(observed.accepted_events.size < events.size, 'Invalid-event fixture did not test a changed history')

# The same raw records with a different authenticated actor interpretation are
# not the same history. The input fingerprint includes the repository result.
repository.define_singleton_method(:actor_of) do |event, _session|
  event['id'] == 1 ? 'Bob' : event.fetch('actor')
end
observed = game.replay(session, events, repository)
cold = MahjongTableGameTest::Game.new.replay(session, events, repository)
assert_equal(signature.call(cold), signature.call(observed), 'Changed author interpretation reused an old prefix')
assert_equal([], observed.accepted_events, 'Forged first dealer was accepted')

puts 'PASS Mahjong cache: four deterministic Hong Kong hands, linear rule applications, cold equality, copies, old views and changed records/authors'
