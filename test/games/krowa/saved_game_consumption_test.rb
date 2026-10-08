require_relative "../../support/saved_games_ui"
require_relative "../../support/krowa"

$game_room_test_user = "Alice"
broker = NativeLiveSessionsBroker.new
app = SaveAppDriver.new(broker)
run = KrowaTestGame.new(variant: "tower", players: %w[Alice Bob])
game = run.game
app.define_singleton_method(:data_path) { |name| run.program.data_path(name) }
app.define_singleton_method(:game_definition) { |id| id == game.id ? game : super(id) }
table = app.lobby.create_table(name: "Tower archive consumption", game: game.id, owner: "Alice",
  game_options: run.session["options"]).table
join = lambda do |row|
  bob = GameRoomTransport.new(ProgramDouble.new(broker.endpoint("Bob", fresh: true)))
  discovered = bob.discover_rooms.find { |item| item["__id"] == row["__id"] }
  assert(bob.establish_membership(table_id: row["__id"], owner: "Alice", capacity: 8,
    user: "Bob", table: discovered), "Tower guest could not join")
  bob
end
join.call(table)
session = app.games.start_session(table: table, game: game.id, players: %w[Alice Bob], options: table["game_options"])
run.context.session_id = app.games.session_id(session)
run.context.table_id = table["__id"]
move = lambda do |actor, selection = nil|
  snapshot = app.games.snapshot_for(session, force_events: true)
  replay = game.replay(snapshot.session, snapshot.events, app.games)
  selection ||= game.automatic_action(replay, actor, context: run.context)
  status, plan = game.action_for(selection, replay, actor, context: run.context)
  assert(status == :ok, "Tower action failed: #{status}")
  app.games.append_events(session: session, sequence: app.games.next_sequence(session, snapshot.events),
    actor: actor, controller: true, events: plan.events)
end
move.call("Alice")
move.call("Alice", {"kind" => "question", "action" => "submit", "question_id" => "krowa-answer-1", "answer" => "las"})
move.call("Alice")
assert(app.send(:save_current_game, table, session, game), "Tower could not be saved")
saves = app.send(:saved_games)
saved = saves.fetch(saves.list.first.fetch("id"))
assert(saved["private_data"], "Tower fixture has no private word")
table = app.send(:create_saved_game_table, saved)
join.call(table)

game.define_singleton_method(:restore_private_data) { |*args, **| raise IOError, "private storage unavailable" }
assert(app.send(:resume_saved_game_at_table, table, app.room_state(table)).nil?, "failed secret restoration started Tower")
assert(saves.fetch(saved["id"]) == saved, "failed secret restoration consumed the only copy of the word")
game.singleton_class.remove_method(:restore_private_data)

resources = app.instance_variable_get(:@save_resources)
delete = resources.method(:delete)
resources.define_singleton_method(:delete) do |id, **options|
  state = app.room_state(table)
  context = saves.send(:private_context, app.games.session_id(state.session))
  assert(game.saved_private_data(state.replay, context: context) == saved["private_data"],
    "server archive was deleted before the secret was restored")
  delete.call(id, **options)
end
session = app.send(:resume_saved_game_at_table, table, app.room_state(table))
assert(session && saves.list.empty?, "confirmed Tower resume did not consume its server archive")
run.context.session_id = app.games.session_id(session)
run.context.table_id = table["__id"]
move.call("Bob", {"kind" => "question", "action" => "submit", "question_id" => "krowa-answer-1", "answer" => "dom"})
move.call("Alice")
state = app.room_state(table)
assert(state.replay.state[:pending].empty? && state.replay.state[:attempts].length == 2,
  "Tower lost its private word when the archive was deleted")
assert(!JSON.generate(broker.cores.values.last.entries).include?('"kot"'), "Tower secret leaked into public history")
app.transport.deactivate_table(table_id: table["__id"])
puts "PASS Tower save consumption: secret-write failure preserved save; confirmed restore deleted it and next guess was scored"
