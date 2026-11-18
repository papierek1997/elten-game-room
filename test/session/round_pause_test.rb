require_relative '../support/assertions'
require_relative '../../games/catalog'
require_relative '../../lib/game_round_pause'
include GameRoomTest::Assertions

repository = Object.new
def repository.event_id(event); event.fetch('id'); end
clock = GameRoomRoundPause.new(repository)
session = {'created_at' => 100, '__server_started_at' => 200, '__clock_offset' => 50}
event = {'id' => 7, 'action' => 'settle', 'created_at' => 230, '__clock_offset' => 10}
selected = %w[spades tysiac three_five_eight bridge hearts belote jass french_tarot cribbage
  bouillabaisse scopa mille_bornes uno ninety_nine rummy domino mexican_train poker
  blackjack blackjack_dice dice_poker liars_dice roulette categories quiz]

selected.each do |id|
  game = GameRoomGames::CATALOG.build(id)
  state = {phase: :round_complete, options: game.default_options}
  state[:phase], state[:resume_at] = :drawing, 125 if id == 'quiz'
  history = [GameRoomGames::HistoryEntry.new(event_id: 7, kind: game.round_pause_end_kinds.first)]
  replay = GameRoomGames::Replay.new(state: state, history: history, accepted_events: [event])
  assert(game.round_pause_seconds(replay) == 5, "#{id}: missing opt-in")
  [120, 124.999].each do |now|
    assert(clock.active?(game: game, replay: replay, session: session, now: now), "#{id}: early next round")
  end
  assert(!clock.active?(game: game, replay: replay, session: session, now: 125), "#{id}: late next round")
  replay.winner = 'Alice'
  assert(!clock.active?(game: game, replay: replay, session: session, now: 121), "#{id}: pause after final result")
end

%w[kosciane balut yahtzee makao axel_pong audio_ball].each do |id|
  game = GameRoomGames::CATALOG.build(id)
  assert(game.round_pause_seconds(nil).zero?, "#{id}: a turn became a round")
end
game = GameRoomGames::Blackjack.new
assert(game.round_pause_seconds(GameRoomGames::Replay.new(state: {options: {'variant' => 'social'}})).zero?,
  'The casino-only request changed social blackjack')

# Settlement in a game that immediately resets to its next playing/betting
# phase must pause once, never again after a first new bet/private commitment.
game = GameRoomGames::BlackjackDice.new
state = {phase: :playing, options: game.default_options}
entry = GameRoomGames::HistoryEntry.new(event_id: 7, kind: :round)
replay = GameRoomGames::Replay.new(state: state, history: [entry], accepted_events: [event])
assert(clock.active?(game: game, replay: replay, session: session, now: 120), 'Immediate round reset bypasses the pause')
started = GameRoomGames::Replay.new(state: state, history: [entry],
  accepted_events: [event, event.merge('id' => 8, 'action' => 'roll', 'created_at' => 235)])
assert(!clock.active?(game: game, replay: started, session: session, now: 125), 'A new round starts a second pause')
initial = GameRoomGames::Replay.new(state: state, history: [], accepted_events: [])
assert(!clock.active?(game: game, replay: initial, session: session, now: 120), 'Initial play was delayed')

archived = GameRoomGames::Replay.new(state: state, history: [entry],
  accepted_events: [event.merge('__game_time' => 120, 'created_at' => 9000)])
assert(clock.active?(game: game, replay: archived, session: session, now: 124), 'Restore reapplies an epoch offset')
assert(!clock.active?(game: game, replay: archived, session: session, now: 125), 'Restore restarts the five seconds')

reads = 0
repository.define_singleton_method(:event_id) { |row| reads += 1; row.fetch('id') }
cached = GameRoomRoundPause.new(repository)
500.times { cached.active?(game: game, replay: replay, session: session, now: 121) }
assert(reads == 1, 'An unchanged executor tick rescans the accepted history')
puts 'PASS round pause: 25 opt-ins, exclusions, event-local/archived clocks, exact deadline, no first/final or repeated pause'
