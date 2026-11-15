require_relative '../../lib/game_simulation'
require_relative '../../lib/table_activity_repository'
require_relative '../../lib/presentation_replay'
require_relative '../../games/monopoly'
require_relative '../../games/four_in_a_row'
require_relative '../support/assertions'
include GameRoomTest::Assertions

module Session
  def self.name; 'Alice'; end
end

names = GameRoomParticipants
names.set_local_presentation_name(account: 'Alice', name: 'First Person')
env = GameRoomSimulation::Environment.new_game(game: GameRoomGames::Monopoly.new, players: %w[Alice Bob], seed: 1729)
6.times do
  actor = env.active_actor
  action = env.legal_actions(actor).first
  assert(action && env.step(action, actor: actor) == :ok, 'Could not prepare cached game')
end
before = env.game.replay(env.session, env.events, env.repository)
assert(before.history.map(&:text).join.include?('First Person'), 'Fixture has no own named history')
names.set_local_presentation_name(account: 'Alice', name: 'Second Person')
after = env.game.replay(env.session, env.events, env.repository)
assert(after.history.map(&:text).join.include?('Second Person') && !after.history.map(&:text).join.include?('First Person'), 'Reducer retained an old local value')
assert(before.state == after.state && before.accepted_events == after.accepted_events, 'Local value changed model or accepted events')

board = GameRoomSimulation::Environment.new_game(game: GameRoomGames::FourInARow.new, players: %w[Alice Bob])
2.times do
  actor = board.active_actor
  assert(board.step(board.legal_actions(actor).first, actor: actor) == :ok, 'Board move failed')
end
boundary = board.events.map { |event| event['id'] }.max + 1
session = board.session.merge('__initial_players'=>%w[Alice Bob], '__players'=>%w[Alice Carol],
  '__seat_changes'=>[{'id'=>boundary, 'players'=>%w[Alice Carol]}])
repository = GameRoomSimulation::Repository.new(%w[Alice Carol])
old = board.game.replay(session, board.events, repository)
names.set_local_presentation_name(account: 'Alice', name: 'Third Person')
fresh = board.game.replay(session, board.events, repository)
assert(fresh.history.map(&:text).join.include?('Third Person') && !fresh.history.map(&:text).join.include?('Second Person'), 'Historical participant segment retained an old local value')
assert(old.board == fresh.board && old.accepted_events == fresh.accepted_events, 'Historical model or actors changed')

plain = board.game.replay(board.session, board.events, board.repository)
cache = GameRoomPresentationReplay.new(GameRoomGames::FourInARow.new, board.repository)
cache.remember(board.session, plain)
names.set_local_presentation_name(account: 'Alice', name: 'Fourth Person')
actor = board.active_actor
assert(board.step(board.legal_actions(actor).first, actor: actor) == :ok, 'Presentation fixture move failed')
latest = board.game.replay(board.session, board.events, board.repository)
event = latest.accepted_events.last
pair = cache.transitions(board.session, latest, [event]).fetch(board.repository.event_id(event))
assert(pair.first.history.map(&:text).join.include?('Fourth Person') && !pair.first.history.map(&:text).join.include?('Third Person'), 'Presentation prefix retained an old local value')

activity = TableActivityRepository.new(server_tables: {})
entry = TableActivityRepository::Entry.new(id: 1, table_id: 1, kind: 'joined', actor: 'Alice', owner: 'Bob', game: 'uno', message: '', subject: '', created_at: 1, stack_sequence: 1)
render = -> { activity.merged_history_entries(game_entries: [], game_events: [], activity_entries: [entry], game_name: ->(_) { 'UNO' }).map(&:text).join }
assert(render.call.include?('Fourth Person'), 'Activity fixture has no own name')
names.set_local_presentation_name(account: 'Alice', name: 'Fifth Person')
assert(render.call.include?('Fifth Person') && !render.call.include?('Fourth Person'), 'Room activity retained an old local value')
puts 'PASS local revisions in reducer, participant, presentation and room activity caches'
