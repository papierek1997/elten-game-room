require_relative '../../support/assertions'
require_relative '../../../lib/game_simulation'
require_relative '../../../games/cribbage_support/cribbage_table'
include GameRoomTest::Assertions

game = GameRoomGames::CribbageTable.new
initial_session = {'options'=>'{}'}
initial_repository = Struct.new(:players) do
  def players_for(_session); players; end
  def actor_of(event, _session=nil); event['actor']; end
  def event_id(event); event['id']; end
end.new(%w[Alice Bob])
raw = {'id'=>1, 'actor'=>'Alice', 'action'=>'play', 'value'=>'AC'}
assert_equal([], game.replay(initial_session, [raw], initial_repository).accepted_events,
  'A raw play before the first deal was not safely refused')
env = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob], seed: 2)
assert(env.replay.state[:starter].nil?, 'The starter was exposed before discarding')
4.times { assert_equal(:ok, env.step(env.legal_actions.first)) }
assert_equal('JD', env.replay.state[:starter], 'The regression no longer uses a jack starter')
dealer = env.replay.state[:seats].fetch(env.replay.state[:dealer])
assert_equal(2, env.replay.state[:scores].fetch(dealer), 'Ordinary play omitted heels')
assert(env.replay.history.any? { |entry| entry.kind == :score && entry.actor == dealer },
  'The starter award has no player-facing feedback')

actor = env.active_actor
before = Marshal.load(Marshal.dump(env.replay.state))
bad = {'id'=>env.events.size + 1, 'actor'=>actor, 'action'=>'crib_go', 'value'=>''}
refused = game.replay(env.session, env.events + [bad], env.repository)
assert_equal(env.events, refused.accepted_events, 'A false Go on an empty sequence was accepted')
assert_equal(before, refused.state, 'Refused Go changed the position')

steps = 0
until env.finished? || env.replay.state[:round] >= 3
  assert(steps < 120, 'Two production rounds did not finish')
  assert_equal(:ok, env.step(env.legal_actions.first))
  steps += 1
end
assert(env.replay.accepted_events == env.events, 'Production continuation discarded an accepted move')
puts 'PASS production Cribbage: hidden starter, heels, refused false Go and consecutive complete rounds'
