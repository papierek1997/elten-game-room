if ARGV.first
  require_relative "../support/binary_rules_load"
  GameRoomTestLocalization.use_language("en")
end
require_relative "../support/saved_games_ui"
require_relative "../support/elten_array_shuffle"

module MilleBornesCreationRequests
  def creation_requests
    @creation_requests ||= []
  end

  def current_table_checks
    @current_table_checks.to_i
  end

  def create_table(**arguments)
    creation_requests << arguments.dup
    super
  end

  def current_table_for(user)
    @current_table_checks = current_table_checks + 1
    super
  end
end

module MilleBornesCapacityTranslation
  SOURCE = "This saved game needs %{count} seats, but tables support at most %{maximum}.".freeze

  attr_accessor :capacity_translation

  def capacity_translation_requests
    @capacity_translation_requests ||= []
  end

  def translate(source, **options)
    if source == SOURCE
      capacity_translation_requests << source
      return capacity_translation if capacity_translation
    end
    super
  end
end

GameRoomLocalization.singleton_class.prepend(MilleBornesCapacityTranslation)

class MilleBornesCreationApp < SaveAppDriver
  attr_reader :opened_table

  def initialize(broker)
    super
    lobby.singleton_class.prepend(MilleBornesCreationRequests)
  end

  def default_table_name
    "Eight-seat Mille Bornes"
  end

  def show_table_screen(table)
    @opened_table = table
  end

  def speech_wait
  end

  def simulated_archive(game, players:, options:)
    environment = GameRoomSimulation::Environment.new_game(game: game, players: players, options: options, seed: 73)
    saved_games.put(game: game, table: { "owner" => "Alice", "name" => "Archived Mille Bornes", "private" => true },
      snapshot: environment, repository: environment.repository, now: 1_000)
  end
end

def assert_saved_capacity_rejected(app, broker, saved, required_seats:)
  creation_requests = app.lobby.creation_requests.dup
  table_checks = app.lobby.current_table_checks
  session_ids = broker.cores.keys
  previous_notices = app.notices.length
  translation_count = GameRoomLocalization.capacity_translation_requests.length
  original = JSON.generate(saved)
  result = app.send(:create_saved_game_table, saved)
  assert_equal(nil, result, "An oversized archive created a table")
  assert_equal(creation_requests, app.lobby.creation_requests, "Oversized archive reached lobby creation")
  assert_equal(table_checks, app.lobby.current_table_checks, "Capacity rejection performed a current-table network lookup")
  assert_equal(session_ids, broker.cores.keys, "Capacity rejection created a native session")
  assert_equal([], app.errors, "Capacity rejection reached a network error instead of the local guard")
  assert_equal(previous_notices + 1, app.notices.length, "Capacity rejection must show exactly one alert")
  assert_equal(translation_count + 1, GameRoomLocalization.capacity_translation_requests.length,
    "Capacity alert bypassed translation of the exact parameterized source")
  template = GameRoomLocalization.capacity_translation || MilleBornesCapacityTranslation::SOURCE
  assert_equal(template % { count: required_seats, maximum: 8 }, app.notices.last, "Capacity alert lost the required or supported seat count")
  assert_equal(original, JSON.generate(saved), "Rejected archive was modified")
  assert_equal(saved, app.send(:saved_games).fetch(saved.fetch("id")), "Rejected archive was lost or modified in account storage")
end

broker = NativeLiveSessionsBroker.new
app = MilleBornesCreationApp.new(broker)
$game_room_test_user = "Alice"
game = GameRoomGames::MilleBornes.new
options = game.normalize_options("custom_deck" => true, "counterflow" => true,
  "include_instant_repairs" => true, "instant_repair_cards" => 8, "25_cards" => 18)
app.send(:create_configured_table, game, { game_options: options, private_table: true })
table = app.opened_table
assert(table && table["private"] && table["max_players"] == 8,
  "Actual application creation did not request a private eight-seat table: #{app.errors.map { |error| "#{error.class}: #{error.message}" }.join('; ')}")
assert_equal(8, broker.cores.fetch(table.fetch("__live_session_id")).capacity, "Application sent unsupported native capacity")
assert(!app.lobby.creation_requests.last.key?(:capacity), "Application must use the fixed lobby capacity")
assert(app.lobby.capacity_of(table) == 8, "Lobby changed the actual eight-seat capacity")
7.times { assert(app.lobby.add_bot(table).updated?, "Lobby refused one of the seven bot places") }
room = app.lobby.snapshot_for(table)
players = room.game_participants
assert(players.length == 8 && room.bots.length == 7, "Created room lost the eighth participant")
assert_equal(["Alice"], room.members, "Application fixture must contain one human and seven bots")
assert(app.lobby.add_bot(room.table).status == :full, "Lobby admitted a ninth participant")
session = app.games.start_session(table: room.table, game: game.id, players: players, options: JSON.generate(options))
environment = GameRoomSimulation::Environment.new_game(game: game, players: players, options: options, seed: 73)
environment.events.each do |event|
  app.games.append_events(session: session, sequence: event["sequence"],
    events: [GameRoomGames::EventCommand.new(action: event["action"], value: event["value"])],
    actor: event["actor"], controller: true)
end
before = app.games.snapshot_for(session)
assert(game.replay(before.session, before.events, app.games).state[:hands].length == 8, "Application fixture did not deal eight real hands")
assert(app.send(:save_current_game, room.table, session, game), "Actual eight-seat save flow failed: #{app.errors}")
archives = app.send(:saved_games)
saved = archives.fetch(archives.list.fetch(0).fetch("id"))
assert(saved["players"] == players && saved["options"] == JSON.generate(options), "Application save lost custom counts or eighth seat")
assert(app.transport.current_room("Alice") == nil, "Confirmed save did not release the old table")
restored_table = app.send(:create_saved_game_table, saved)
assert(restored_table && restored_table["max_players"] == 8, "Actual saved-game creation did not use an eight-seat room")
assert_equal(8, broker.cores.fetch(restored_table.fetch("__live_session_id")).capacity, "Restoration sent unsupported native capacity")
assert(!app.lobby.creation_requests.last.key?(:capacity), "Restoration must use the fixed lobby capacity")
restored_room = app.lobby.snapshot_for(restored_table)
assert(restored_room.bots.length == 7 && restored_room.game_participants.length == 8, "Saved-game lobby dropped a bot")
assert(app.send(:create_saved_game_table, saved)["__id"] == restored_table["__id"], "Repeated saved-game entry duplicated the room")
restored = app.send(:resume_saved_game_at_table, restored_table, app.room_state(restored_table))
assert_equal(2, broker.cores.length, "Repeated saved-game entry created an extra native session")
assert(restored && app.games.players_for(restored).length == 8, "Actual resume failed to restore eight seats")
snapshot = app.games.snapshot_for(restored)
replay = game.replay(snapshot.session, snapshot.events, app.games)
assert(replay.accepted_events.length == saved["events"].length, "Actual resumed game rejected saved events")
assert(replay.state[:hands].values.all? { |hand| hand.length == 6 }, "Actual resume truncated a physical hand")
assert(game.deck_counts_for(replay.state[:options]) == game.deck_counts_for(options), "Actual resume changed the custom deck")
assert(app.send(:saved_games).fetch(saved["id"]) == saved, "Actual resume damaged the recovery archive")
assert_equal([], app.errors, "Application creation/save/resume swallowed a network error")
app.lobby.close_table(restored_table)
puts "PASS application creation, eight-place lobby with seven bots, account save, saved-room creation and resume"

rejected_broker = NativeLiveSessionsBroker.new
rejected_app = MilleBornesCreationApp.new(rejected_broker)
assert_equal(8, GameRoomTableControl::MAX_SEATS, "Model/archive capacity must match native rooms")

observer_saved = rejected_app.simulated_archive(game, players: GameRoomParticipants.bots_for(44, 8), options: options)
GameRoomLocalization.capacity_translation = "Localized capacity: %{maximum} maximum, %{count} required."
begin
  assert_saved_capacity_rejected(rejected_app, rejected_broker, observer_saved, required_seats: 9)
ensure
  GameRoomLocalization.capacity_translation = nil
end
puts "PASS eight saved players plus absent owner need nine seats, with translated/interpolated alert"

[[GameRoomParticipants.bots_for(45, 7), true], [["aLiCe"] + GameRoomParticipants.bots_for(46, 7), false]].each do |saved_players, owner_observes|
  boundary_broker = NativeLiveSessionsBroker.new
  boundary_app = MilleBornesCreationApp.new(boundary_broker)
  boundary_saved = boundary_app.simulated_archive(game, players: saved_players, options: options)
  boundary_table = boundary_app.send(:create_saved_game_table, boundary_saved)
  assert(boundary_table, "A supported owner/player boundary failed to create: #{boundary_app.errors}")
  assert_equal(8, boundary_broker.cores.fetch(boundary_table.fetch("__live_session_id")).capacity, "Boundary restoration sent unsupported capacity")
  boundary_room = boundary_app.lobby.snapshot_for(boundary_table)
  assert_equal(owner_observes, boundary_room.observer?("Alice"), "Archive ownership was confused with a saved playing seat")
  assert_equal(8, boundary_room.members.length + boundary_room.bots.length, "Boundary room must use exactly eight total places")
  boundary_session = boundary_app.send(:resume_saved_game_at_table, boundary_table, boundary_app.room_state(boundary_table))
  assert(boundary_session, "Supported boundary failed to resume")
  expected = boundary_app.send(:saved_games).restored_data(boundary_saved, game: game, table_id: boundary_table.fetch("__id"))
  assert_equal(expected.fetch(:players), boundary_app.games.players_for(boundary_session), "Boundary resume changed saved playing seats")
  boundary_snapshot = boundary_app.games.snapshot_for(boundary_session)
  boundary_replay = game.replay(boundary_snapshot.session, boundary_snapshot.events, boundary_app.games)
  assert_equal(boundary_saved.fetch("events").length, boundary_replay.accepted_events.length, "Boundary resume rejected saved events")
  assert_equal(saved_players.length, boundary_replay.state.fetch(:hands).length, "Boundary resume lost a physical hand")
  assert_equal(boundary_saved, boundary_app.send(:saved_games).fetch(boundary_saved.fetch("id")), "Boundary resume modified the archive")
  assert_equal([], boundary_app.errors, "Boundary restoration swallowed a network error")
  boundary_app.lobby.close_table(boundary_table)
end
puts "PASS owner-observer plus seven players and case-insensitive seated owner at the eight-place boundary"
