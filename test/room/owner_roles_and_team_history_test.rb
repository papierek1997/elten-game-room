require_relative "../support/ui"
require_relative "../support/native_room_harness"
require_relative "../support/log"
require_relative "../../lib/participant_menu"
require_relative "../../lib/room_presentation"
require_relative "../../lib/game_surfaces"
require_relative "../../lib/game_layout"
require_relative "../../games/axel_pong"
require_relative "../../games/spades"
require_relative "../../games/domino"
require_relative "../../games/taboo"

def room(h, user)
  LobbyRepository::TableSnapshot.new(**h.transports.fetch(user).room_snapshot(h.table, force: true))
end

def lobby(h, user)
  LobbyRepository.new(nil, transport: h.transports.fetch(user), server_tables: {})
end

def activity(h, user)
  TableActivityRepository.new(server_tables: {}, transport: h.transports.fetch(user))
end

def denied
  begin
    yield
  rescue ArgumentError
    return
  end
  raise 'Unauthorized or stale role change was accepted'
end

h = NativeRoomHarness.new(users: %w[Alice Bob Carol])
before = h.core.last_seq
h.as('Alice') { lobby(h, 'Alice').set_observer(h.table, 'Carol', true) }
assert(h.core.last_seq == before + 1, 'Role and announcement wrote more than one stack entry')
h.users.each do |user|
  assert(room(h, user).game_participants == %w[Alice Bob], "#{user}: third person counted in a two-player start")
  entries = activity(h, user).entries_for(h.table)
  assert(entries.length == 1 && entries.first.kind == 'role_changed', 'Confirmed role event missing/duplicated')
  text = activity(h, user).text_for(entries.first, game_name: ->(id) { id })
  assert(text == 'Alice chose Carol as an observer for the next game.', 'Role announcement ambiguous')
end
session = h.as('Alice') do
  h.repositories['Alice'].start_session(table: h.table, game: 'test', players: %w[Alice Bob], options: '{}')
end
h.as('Alice') do
  lobby(h, 'Alice').set_observer(h.table, 'Bob', true)
  lobby(h, 'Alice').set_observer(h.table, 'Carol', false)
end
h.users.each do |user|
  assert(h.repositories[user].players_for(session) == %w[Alice Bob], 'Role change ejected a player mid-match')
  assert(room(h, user).game_participants == %w[Alice Carol], 'Next roster did not follow the owner choice')
end
before = h.core.last_seq
h.as('Bob') { denied { lobby(h, 'Bob').set_observer(h.table, 'Carol', true) } }
h.as('Alice') do
  denied { lobby(h, 'Alice').set_observer(h.table, 'Absent', true) }
  denied { lobby(h, 'Alice').set_observer(h.table, "bot:#{h.table['__id']}:1", true) }
end
assert(before == h.core.last_seq, 'Rejected role change wrote a record')

# Validate received packets too, not only the owner UI/repository.
invalid = [
  ['Bob', 'Bob', {'subject' => 'Carol', 'role' => 'observer'}],
  ['Bob', 'Alice', {'subject' => 'Carol', 'role' => 'observer'}],
  ['Alice', 'Alice', {'subject' => [], 'role' => 'observer'}],
  ['Alice', 'Alice', {'subject' => 'bot:1:1', 'role' => 'observer'}],
  ['Alice', 'Alice', {'subject' => 'Carol', 'role' => 'owner'}],
  ['Alice', 'Alice', {'subject' => 'Carol', 'role' => 'observer', 'extra' => true}]
]
invalid.each do |sender, actor, data|
  h.view(sender).stack_push({'version' => 2, 'kind' => 'room_role', 'actor' => actor, 'data' => data}, message_id: SecureRandom.uuid)
end
h.broker.deliver(duplicate: true)
h.users.each { |user| assert(room(h, user).game_participants == %w[Alice Carol], 'Forged/malformed packet changed roles') }
h.add_client('Dave')
assert(h.join('Dave'), 'Late client could not join')
assert(room(h, 'Dave').observer?('Bob'), 'Late reader lost an owner-assigned role')

# The participant context menu has no owner actions for other users/bots.
snapshot = room(h, 'Alice')
game = GameRoomGames::AxelPong.new
layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new(surface: GameSurfaces::GridSpec.new(
  width: 1, height: 1, header: 'Board', cells: [['empty']], row_origin: :bottom)),
  user_items: RoomPresentation.user_rows(snapshot.members, owner: 'Alice', players: [], active: false, observers: snapshot.observers))
actions = []
h.as('Alice') do
  GameRoomParticipantMenu.bind(layout, available: -> { GameRoomParticipantMenu.role_actions(room: snapshot, viewer: Session.name, owner: 'Alice') },
    game: game, room: -> { snapshot }) { |action, person| actions << [action, person] }
  layout.users.index = snapshot.members.index('Bob')
  menu = FakeMenu.new
  layout.users.context(menu)
  menu.options.find { |item| item.first == 'Make Bob a player for the next game' }.last.call
  assert(actions == [[:make_player, 'Bob']], 'Owner menu targeted another row or wrong role')
  layout.users.index = snapshot.members.index('Alice')
  menu = FakeMenu.new
  layout.users.context(menu)
  role = menu.options.find { |item| item.first == 'Make Alice an observer for the next game' }
  assert(role && menu.options.size == 1, 'Owner self role is missing or duplicated')
  role.last.call
  assert(actions.last == [:make_observer, 'Alice'], 'Owner self role targeted another participant')
end

# Team choice and its history use the same confirmed options record.
h = NativeRoomHarness.new(game: game, options: {'team_size' => 2})
options = game.with_team_assignment({'team_size' => 2}, players: h.users, seats: [0, 0, 1, 1])
before = h.core.last_seq
assert(h.transports['Alice'].change_game_options(table: h.table, options: JSON.generate(options),
  expected_options: h.table['game_options'], expected_session_id: 0), 'Could not save teams')
assert(h.core.last_seq == before + 1, 'Teams wrote more than one record')
h.broker.deliver(duplicate: true)
h.users.each do |user|
  snapshot = room(h, user)
  saved = JSON.parse(snapshot.table['game_options'])
  assert(game.prepared_team_assignment(saved, players: h.users).members_for(0) == %w[Alice Bob], 'Remote teams lost')
  rows = RoomPresentation.game_users(room: snapshot, game: game, replay: nil, players: [], owner: 'Alice', options: saved)
  assert(rows[1].label.include?('team 1') && rows[2].label.include?('team 2'), 'Saved teams invisible in waiting room')
  entries = activity(h, user).entries_for(h.table)
  assert(entries.length == 1, 'Team selection announcement repeated')
  assert(activity(h, user).text_for(entries.first, game_name: ->(id) { id }) == 'Team 1: Alice, Bob. Team 2: Carol, Dave.', 'Team history did not name every player')
end
puts 'PASS owner roles, immutable current roster, malicious packets, late readers, user menu, confirmed team history and room labels'

[[GameRoomGames::Spades.new, {'team_size' => 2}, 4, [0, 0, 1, 1]],
 [GameRoomGames::Domino.new, {'teams' => true, 'team_count' => 3, 'set' => 'double_12'}, 6, [0, 1, 2, 0, 1, 2]],
 [GameRoomGames::Taboo.new, {}, 6, [0, 0, 0, 1, 1, 1]]].each do |definition, settings, count, seats|
  players = %w[Alice Bob Carol Dave Eve Frank].first(count)
  saved = definition.with_team_assignment(settings, players: players, seats: seats)
  remapped = definition.options_for_team_roster(saved, players: players.reverse)
  assert(remapped['team_seats'] == seats.reverse, "#{definition.id}: common line-up remapping failed")
  restored = definition.prepared_team_assignment(remapped, players: players)
  assert(restored && restored.valid?, "#{definition.id}: confirmed teams did not persist")
end
puts 'PASS shared team contract for Spades, Domino and Taboo'
