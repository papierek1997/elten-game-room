require_relative "support/native_live_sessions"
require_relative "../lib/saved_games"
require_relative "../lib/game_simulation"
require_relative "../content/monopoly_boards"
%w[four_in_a_row tic_tac_toe chess checkers reversi ludo spades farkle cat_head_tail ninety_nine tysiac three_five_eight monopoly yahtzee uno poker makao].each do |name|
  require_relative "../games/#{name}"
end

def n_(one, many, count); count == 1 ? one : many; end

class ArchiveStorage
  attr_accessor :fail_write, :ignore_write
  def initialize; @state = {}; end
  def read_json(_path, default:); JSON.parse(JSON.generate(@state)); end
  def update_json(_path, default:)
    raise IOError, "write denied" if fail_write
    root = read_json(nil, default: {})
    yield(root)
    @state = JSON.parse(JSON.generate(root)) unless ignore_write
  end
end

def expect_error(message)
  begin
    yield
  rescue ArgumentError, IOError
    return
  end
  raise message
end

invalid_storage = ArchiveStorage.new
invalid_storage.instance_variable_set(:@state, { "games" => "broken" })
expect_error("corrupt saved storage escaped validation") { SavedGames.new(invalid_storage, owner: "Alice").delete("missing") }

types = %w[FourInARow TicTacToe Chess Checkers Reversi Ludo Spades Farkle CatHeadTail NinetyNine Tysiac ThreeFiveEight Monopoly Yahtzee Uno Poker Makao]
# Optional class names allow a new game to run the same save assertions on its
# own. The ordinary invocation still covers every game in the list.
unless ARGV.empty?
  unknown = ARGV - types
  raise "Unknown save-test game: #{unknown.join(', ')}" unless unknown.empty?
  types &= ARGV
end
types.each do |type|
  game = GameRoomGames.const_get(type).new
  broker = NativeLiveSessionsBroker.new
  owner = GameRoomTransport.new(ProgramDouble.new(broker.endpoint("Alice")))
  bob = GameRoomTransport.new(ProgramDouble.new(broker.endpoint("Bob")))
  repo = GameRepository.new(ProgramDouble.new(broker.endpoint("Alice")), transport: owner, server_tables: {})
  $game_room_test_user = "Alice"
  count = [game.minimum_players, [3, game.maximum_players].min].max
  bot_names = %w[pl20 en03 pl24 en26].first(count - 2)
  table = owner.create_room(name: "Archive #{game.id}", game: game.id, owner: "Alice", game_options: "{}", bot_count: count - 2, bot_names: bot_names)
  players = %w[Alice Bob] + GameRoomParticipants.bots_for(table["__id"], count - 2, names: bot_names)
  public_row = bob.discover_rooms.first
  assert(bob.establish_membership(table_id: table["__id"], owner: "Alice", capacity: 8, user: "Bob", table: public_row), "Bob could not join")
  session = repo.start_session(table: table, game: game.id, players: players, options: JSON.generate(game.default_options))
  env = GameRoomSimulation::Environment.new_game(game: game, players: players, seed: 42)
  2.times do
    action = env.legal_actions.first
    break if action == nil || env.finished?
    assert(env.step(action) == :ok, "#{game.id} fixture action failed")
  end
  if game.id == "tysiac"
    12.times do
      break if env.replay.state[:phase] == :playing
      actions = env.legal_actions
      action = actions.find { |item| item["bid"] == "pass" } || actions.reject { |item| item["action"] == "surrender" }.first
      assert(env.step(action) == :ok, "Tysiac fixture passing failed")
    end
    assert(env.events.any? { |event| event["action"] == "pass_card" && event["value"].start_with?("bot:") }, "Tysiac test does not exercise a bot target inside an event")
  end
  # Finish only a mandatory choice; do not simulate a complete match.
  3.times do
    break if game.save_game_error(env.replay) == nil || env.finished?
    assert(env.step(env.legal_actions.first) == :ok, "#{game.id} fixture choice failed")
  end
  env.events.each do |event|
    actor = event["actor"]
    $game_room_test_user = "Alice"
    repo.append_events(session: session, sequence: event["sequence"],
      events: [GameRoomGames::EventCommand.new(action: event["action"], value: event["value"])], actor: actor, controller: true)
  end
  boundary = owner.freeze_game(session)
  snapshot = repo.snapshot_for(session, force_events: true)
  assert(snapshot.session["__frozen"], "#{game.id}: stale snapshot lost freeze boundary")
  before = game.replay(snapshot.session, snapshot.events, repo)
  assert(before.accepted_events.length == env.events.length, "#{game.id}: fixture replay rejected events")
  storage = ArchiveStorage.new
  saves = SavedGames.new(storage, owner: "Alice")
  row = saves.put(game: game, table: table, snapshot: snapshot, repository: repo, now: boundary.created_at)
  assert(SavedGames.new(storage, owner: "Alice").list == [row], "save was not durable across instances")
  assert(SavedGames.new(storage, owner: "Bob").list.empty?, "another account saw private archives")
  storage.fail_write = true
  expect_error("failed disk write was treated as a save") { saves.put(game: game, table: table, snapshot: snapshot, repository: repo) }
  storage.fail_write = false
  storage.ignore_write = true
  expect_error("unpersisted disk write was treated as a save") { saves.put(game: game, table: table, snapshot: snapshot, repository: repo) }
  storage.ignore_write = false
  owner.deactivate_table(table_id: table["__id"])
  $game_room_test_user = "Alice"
  restored_table = owner.create_room(name: table["name"], game: game.id, owner: "Alice", game_options: row["options"], bot_count: count - 2, bot_names: bot_names, resume_save_id: row["id"])
  bob = GameRoomTransport.new(ProgramDouble.new(broker.endpoint("Bob", fresh: true)))
  selected = bob.discover_rooms.first
  assert(bob.establish_membership(table_id: restored_table["__id"], owner: "Alice", capacity: 8, user: "Bob", table: selected), "Bob could not enter restoration room")
  restoration = saves.restored_data(row, game: game, table_id: restored_table["__id"], now: row["saved_at"] + 86_400)
  assert(restoration[:players].map { |player| GameRoomParticipants.display_name(player) } == players.map { |player| GameRoomParticipants.display_name(player) }, "#{game.id}: restoring changed computer names")
  restored = repo.restore_session(table: restored_table, game: game.id, players: restoration[:players], options: row["options"], restore: restoration)
  snapshot = repo.snapshot_for(restored, force_events: true)
  after = game.replay(snapshot.session, snapshot.events, repo)
  assert(after.accepted_events.length == row["events"].length, "#{game.id}: imported replay lost events")
  assert(snapshot.events.map { |event| repo.event_id(event) } == row["events"].map { |event| event["id"] }, "#{game.id}: old event IDs changed")
  remapped = JSON.generate(after.state).gsub(/bot:#{restored_table['__id']}:/, "bot:#{table['__id']}:")
  expected = JSON.generate(before.state)
  # Session clock metadata changes when a frozen archive is resumed. Compare
  # the actual game state separately, and verify the preserved game time below.
  if before.state.is_a?(Hash) && after.state.is_a?(Hash)
    remapped = JSON.generate(JSON.parse(remapped).reject { |key, _| %w[clock_epoch_offset clock_offset frozen_at].include?(key) })
    expected = JSON.generate(JSON.parse(expected).reject { |key, _| %w[clock_epoch_offset clock_offset frozen_at].include?(key) })
  end
  assert(remapped == expected, "#{game.id}: restored state differs")
  assert(GameRoomSessionClock.from_server(snapshot.session, snapshot.session.fetch("__server_started_at")) == row["game_time"], "#{game.id}: restored game time changed")
  remote_repo = GameRepository.new(ProgramDouble.new(broker.endpoint("Bob", fresh: true)), transport: bob, server_tables: {})
  remote = remote_repo.session_for_table(selected)
  assert(remote_repo.snapshot_for(remote).events.length == snapshot.events.length, "#{game.id}: remote client did not import archive")
  assert(repo.restore_session(table: restored_table, game: game.id, players: restoration[:players], options: row["options"], restore: restoration)["__id"] == restored["__id"], "repeated resume created a second game")
  actor = game.active_actors(after).first
  context = GameRoomGames::ActionContext.new(now: row["game_time"], random_source: GameRoomRandom::SeededSource.new(43))
  action = game.legal_actions(after, actor, context: context).first
  if action
    status, plan = game.action_for(action, after, actor, context: context)
    assert(status == :ok, "#{game.id}: next restored move unavailable")
    events = repo.append_events(session: restored, sequence: after.accepted_events.length + 1, events: plan.events, actor: actor, controller: true)
    assert(events.first["__id"] > row["events"].map { |event| event["id"] }.max.to_i, "new move collided with old IDs")
    advanced = repo.snapshot_for(restored)
    assert(game.replay(advanced.session, advanced.events, repo).accepted_events.length == after.accepted_events.length + plan.events.length, "#{game.id}: next restored move rejected")
  end
  invalid = JSON.parse(JSON.generate(row))
  invalid["options"] = "{}"
  invalid["checksum"] = "broken"
  expect_error("damaged archive was accepted") { saves.validate(invalid, game: game) }
  invalid = JSON.parse(JSON.generate(row))
  invalid["events"] << { "id" => 9_999_999, "sequence" => 0, "actor" => "Alice", "action" => "unknown", "value" => "", "created_at" => 1 }
  invalid["checksum"] = saves.send(:checksum, invalid)
  expect_error("invalid replay event was accepted") { saves.validate(invalid, game: game) }
  saves.delete(row["id"])
  assert(saves.list.empty?, "local delete failed")
  puts "#{game.id}: local save, exact replay, remote import, next move, failure checks OK"
end
