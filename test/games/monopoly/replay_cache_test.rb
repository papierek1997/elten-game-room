require_relative '../../../lib/game_simulation'
require_relative '../../../games/monopoly'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

class FullReplayMonopoly < GameRoomGames::Monopoly
  def replay(session, events, repository)
    @monopoly_replay_cache = @monopoly_replay_input = nil
    super
  end
end

# Play a complete deterministic eight-seat match through action_for/replay.
# The reference always rebuilds from event zero, not the cached prefix.
players = ['Human', *GameRoomParticipants.bots_for(1, 7)]
cached = GameRoomSimulation::Environment.new_game(game:GameRoomGames::Monopoly.new, players:players, seed:20261103)
reference = GameRoomSimulation::Environment.new_game(game:FullReplayMonopoly.new, players:players, seed:20261103)
max_houses = max_hotels = 0
moves = 0
600.times do
  break if cached.finished?
  actor = cached.active_actor
  assert_equal(actor, reference.active_actor, 'Cache changed the active actor')
  selections = [cached, reference].map do |env|
    actions = env.legal_actions(actor)
    env.game.bot_strategy.choose(actions:actions, actor:actor, random_source:env.random_source,
      game:env.game, replay:env.replay, context:env.context)
  end
  assert_equal(selections.first, selections.last, 'Cache changed a deterministic bot decision')
  [cached, reference].each { |env| assert_equal(:ok, env.step(selections.first, actor:actor), 'A normal move was rejected') }
  assert_equal(reference.replay.to_h, cached.replay.to_h, 'Cached replay diverged in state, history or accepted actions')
  state = cached.replay.state
  max_houses = [max_houses, state[:houses].values.reject { |level| level == 5 }.sum].max
  max_hotels = [max_hotels, state[:houses].values.count(5)].max
  moves += 1
end
assert(cached.finished? && reference.finished?, 'Eight-seat match did not finish within the deterministic fixture budget')
assert(max_houses > 0 && max_hotels > 0, 'Match never reached developed streets and hotels')
assert_equal(reference.events, cached.events, 'Cached game changed RNG-driven event values')
assert_equal(reference.random_source.roll(count:2, sides:1000).values, cached.random_source.roll(count:2, sides:1000).values,
  'Replay optimization consumed extra randomness')

game = GameRoomGames::Monopoly.new
calls = 0
counter = Module.new do
  define_method(:apply_roll) do |*args|
    calls += 1
    super(*args)
  end
end
game.singleton_class.prepend(counter)
repository = GameRoomSimulation::Repository.new(players)
session = cached.session
events = GameRoomSnapshot.copy(cached.events.take(100))
expected = ->(rows = events, row = session, repo = repository) { FullReplayMonopoly.new.replay(row, rows, repo) }
view = game.replay(session, events, repository)
before = calls
game.replay(session.merge('__game_revision'=>'new-cas'), events, repository)
assert_equal(before, calls, 'An unchanged model or CAS-only change replayed old rolls')
appended = GameRoomSnapshot.copy(cached.events.take(101))
assert_equal(expected.call(appended).to_h, game.replay(session, appended, repository).to_h)
assert_equal(before + (appended.last['action'] == 'roll' ? 1 : 0), calls, 'Appending one event reapplied earlier rolls')

# Caller-owned model edits must not poison either the checkpoint or input.
view.state[:cash][players.first] = -999_999
assert(view.history.first.frozen? && view.history.first.text.frozen?, 'Shared history rows are mutable')
view.history.clear
assert_equal(expected.call(appended).to_h, game.replay(session, appended, repository).to_h, 'Returned model leaked into cache')
game.replay(session, appended.take(20), repository)
before = calls
assert_equal(expected.call(appended).to_h, game.replay(session, appended, repository).to_h)
assert_equal(before, calls, 'A shorter historical view evicted the current checkpoint')

# Same length/IDs are insufficient: changed value, actor interpretation,
# session rules, repository identity and presentation language rebuild.
changed = GameRoomSnapshot.copy(appended)
changed.first['value'] = 'malformed-old-roll'
before = calls
assert_equal(expected.call(changed).to_h, game.replay(session, changed, repository).to_h)
assert(calls > before, 'A changed earlier record trusted its cached state')
actor = players.first
repository.define_singleton_method(:actor_of) { |event, _session = nil| event['id'] == 1 ? actor : event.fetch('actor') }
actor = 'Outsider'
assert_equal(expected.call(appended).to_h, game.replay(session, appended, repository).to_h, 'Actor change escaped revalidation')
actor = players.first
different = session.merge('options'=>JSON.generate(cached.game.normalize_options('automatic_rent'=>false)))
assert_equal(expected.call(appended, different).to_h, game.replay(different, appended, repository).to_h, 'Changed rules kept a previous checkpoint')
other = GameRoomSimulation::Repository.new(players)
assert_equal(expected.call(appended, session, other).to_h, game.replay(session, appended, other).to_h, 'Repository change retained prior authority')

original_token = GameRoomLocalization.method(:cache_token)
begin
  token = Object.new
  GameRoomLocalization.define_singleton_method(:cache_token) { token }
  game.replay(session, appended, other)
  before = calls
  token = Object.new
  game.replay(session, appended, other)
  assert(calls > before, 'A new language catalog reused old presentation text')
ensure
  GameRoomLocalization.define_singleton_method(:cache_token, original_token)
end

# A native sealed log may reuse actor interpretation only for the same
# authentication generation; a different authority invalidates the prefix.
auth = 1
other.define_singleton_method(:replay_authentication_identity) { auth }
native = GameRoomSnapshot::Log.from_owned(GameRoomSnapshot.copy(appended))
assert_equal(expected.call(native, session, other).to_h, game.replay(session, native, other).to_h)
other.define_singleton_method(:actor_of) { |event, _session = nil| event['id'] == 1 && auth == 2 ? 'Outsider' : event.fetch('actor') }
auth = 2
assert_equal(expected.call(native, session, other).to_h, game.replay(session, native, other).to_h, 'Sealed rows bypassed changed authentication')
puts "PASS Monopoly cache: #{moves}-move eight-seat match, identical decisions/RNG, buildings/hotels, owned snapshots, append/CAS/history/actor/rules/language/authority boundaries"
