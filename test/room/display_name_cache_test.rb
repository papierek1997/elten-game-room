require_relative '../../lib/game_simulation'
require_relative '../../lib/table_activity_repository'
require_relative '../../games/monopoly'
require_relative '../../games/four_in_a_row'
require_relative '../support/assertions'
include GameRoomTest::Assertions

GameRoomParticipants.configure_display_name(account: 'Viewer', name: '')
GameRoomParticipants.remember_display_name('Alice', 'Anna Kowalska')
GameRoomParticipants.remember_display_name('Bob', 'Jan Nowak')
env = GameRoomSimulation::Environment.new_game(game: GameRoomGames::Monopoly.new, players: %w[Alice Bob], seed: 1729)
6.times do
  actor = env.active_actor
  action = env.legal_actions(actor).first
  assert(action && env.step(action, actor: actor) == :ok, 'could not prepare cached game')
end
before = env.game.replay(env.session, env.events, env.repository)
assert(before.history.map(&:text).join.include?('Anna Kowalska'), 'fixture has no named history')
GameRoomParticipants.remember_display_name('Alice', 'Alicja Kowalska')
after = env.game.replay(env.session, env.events, env.repository)
assert(after.history.map(&:text).join.include?('Alicja Kowalska') && !after.history.map(&:text).join.include?('Anna Kowalska'), 'reducer cache retained old name')
assert(before.state == after.state && before.accepted_events == after.accepted_events, 'renaming changed rules or accepted events')

board = GameRoomSimulation::Environment.new_game(game: GameRoomGames::FourInARow.new, players: %w[Alice Bob])
2.times do
  actor = board.active_actor
  assert(board.step(board.legal_actions(actor).first, actor: actor) == :ok, 'board fixture move failed')
end
boundary = board.events.map { |event| event['id'] }.max + 1
session = board.session.merge('__initial_players' => %w[Alice Bob], '__players' => %w[Alice Carol],
  '__seat_changes' => [{'id' => boundary, 'players' => %w[Alice Carol]}])
repository = GameRoomSimulation::Repository.new(%w[Alice Carol])
old = board.game.replay(session, board.events, repository)
GameRoomParticipants.remember_display_name('Bob', 'Piotr Nowak')
fresh = board.game.replay(session, board.events, repository)
assert(fresh.history.map(&:text).join.include?('Piotr Nowak') && !fresh.history.map(&:text).join.include?('Jan Nowak'), 'participant-history segment retained old name')
assert(old.board == fresh.board && old.accepted_events == fresh.accepted_events, 'name revision changed historical actors or board')

activity = TableActivityRepository.new(server_tables: {})
entry = TableActivityRepository::Entry.new(id: 1, table_id: 1, kind: 'joined', actor: 'Bob', owner: 'Alice', game: 'uno', message: '', subject: '', created_at: 1, stack_sequence: 1)
render = -> { activity.merged_history_entries(game_entries: [], game_events: [], activity_entries: [entry], game_name: ->(_) { 'UNO' }).map(&:text).join }
assert(render.call.include?('Piotr Nowak'), 'activity fixture did not show name')
GameRoomParticipants.remember_display_name('Bob', 'Jan Kowalski')
assert(render.call.include?('Jan Kowalski') && !render.call.include?('Piotr Nowak'), 'formatted room activity cache retained old name')
puts 'PASS name revision invalidates cached reducer, historical participant segments and formatted activity without changing state/actors/events'
