require_relative "../support/saved_games_ui"

# Exercise the application's resume boundary, not just the non-consuming
# archive/transport primitives. Every resource and table here is in memory.
class SavedGameConsumptionScenario
  attr_reader :app, :broker, :game, :table, :session, :saved, :resources

  def initialize
    $game_room_test_user = "Alice"
    @broker = NativeLiveSessionsBroker.new
    @app = SaveAppDriver.new(broker)
    @resources = app.instance_variable_get(:@save_resources)
    @game = GameRoomGames::FourInARow.new
    @table = app.lobby.create_table(name: "Consume save", game: game.id, owner: "Alice",
      game_options: JSON.generate(game.default_options)).table
    join_bob
    @session = app.games.start_session(table: table, game: game.id, players: %w[Alice Bob], options: table["game_options"])
    3.times do
      drop("Alice", 0)
      drop("Bob", 1)
    end
    assert(!replay.finished?, "fixture ended before saving")
    assert(app.send(:save_current_game, table, session, game), "fixture could not be saved")
    @saved = saves.fetch(saves.list.fetch(0).fetch("id"))
    @table = app.send(:create_saved_game_table, saved)
    assert(table && saves.fetch(saved["id"]) == saved, "waiting room consumed its archive")
  end

  def saves; app.send(:saved_games); end

  def join_bob
    @bob = GameRoomTransport.new(ProgramDouble.new(broker.endpoint("Bob", fresh: true)))
    row = @bob.discover_rooms.find { |item| item["__id"] == table["__id"] }
    assert(@bob.establish_membership(table_id: table["__id"], owner: "Alice", capacity: 8,
      user: "Bob", table: row), "Bob could not join")
  end

  def resume
    result = app.send(:resume_saved_game_at_table, table, app.room_state(table))
    @session = result if result
    result
  end

  def replay
    snapshot = app.games.snapshot_for(session, force_events: true)
    game.replay(snapshot.session, snapshot.events, app.games)
  end

  def drop(actor, column)
    snapshot = app.games.snapshot_for(session, force_events: true)
    status, plan = game.action_for({"kind" => "grid", "action" => "select", "x" => column, "y" => 0},
      game.replay(snapshot.session, snapshot.events, app.games), actor)
    assert(status == :ok, "fixture selected an illegal move: #{status}")
    app.games.append_events(session: session, sequence: app.games.next_sequence(session, snapshot.events),
      actor: actor, controller: true, events: plan.events)
    assert(replay.accepted_events.length == snapshot.events.length + 1, "fixture move was not accepted")
  end

  def close
    app.transport.deactivate_table(table_id: table["__id"])
  end
end

scenario = SavedGameConsumptionScenario.new
app, saves = scenario.app, scenario.saves
assert(scenario.resume.nil? && saves.fetch(scenario.saved["id"]), "missing player consumed the save")
scenario.join_bob
app.games.define_singleton_method(:restore_session) { |**| raise EltenAPI::LiveSessions::TimeoutError, "restore denied" }
assert(scenario.resume.nil? && saves.fetch(scenario.saved["id"]), "unconfirmed restoration consumed the save")
app.games.singleton_class.remove_method(:restore_session)

# Check the deletion ordering against the actual restored stack. An unrelated
# archive must remain untouched even when the game eventually finishes.
deletion = scenario.resources.method(:delete)
scenario.resources.define_singleton_method(:delete) do |id, **options|
  state = app.room_state(scenario.table)
  assert(state.session && state.replay.accepted_events.length == scenario.saved["events"].length,
    "archive deletion preceded the restored game")
  deletion.call(id, **options)
end
other = Marshal.load(Marshal.dump(scenario.saved))
other["id"] = SecureRandom.uuid
other["checksum"] = saves.send(:checksum, other)
saves.persist(other)
resumed = scenario.resume
assert(resumed && !saves.fetch(scenario.saved["id"]), "confirmed restore kept its archive")
assert(saves.fetch(other["id"]) == other, "resume deleted another saved game")
assert(app.send(:start_new_game, scenario.table, state: app.room_state(scenario.table))["__id"] == resumed["__id"],
  "opening the resumed game tried to load the removed archive")
scenario.drop("Alice", 0)
assert(scenario.replay.finished? && scenario.replay.winner == "Alice", "resumed board could not finish")
assert(saves.list.map { |item| item["id"] } == [other["id"]], "completion recreated the consumed archive")
scenario.close

# A resumed game can be saved again, but only with its current progress and a
# new archive identity. The old checkpoint cannot be played twice.
scenario = SavedGameConsumptionScenario.new
scenario.join_bob
assert(scenario.resume, "second fixture did not resume")
scenario.drop("Alice", 2)
assert(scenario.app.send(:save_current_game, scenario.table, scenario.session, scenario.game), "resumed game could not be saved again")
fresh = scenario.saves.fetch(scenario.saves.list.fetch(0).fetch("id"))
assert(fresh["id"] != scenario.saved["id"] && fresh["events"].length == 7, "new save reused the old checkpoint")
assert(scenario.saves.fetch(scenario.saved["id"]).nil?, "saving again resurrected the old archive")

# Lost deletion replies are reconciled; real failures warn without treating
# an accepted restoration as damaged or starting the game twice.
[:lost_reply, :denied, :ignored, :status_timeout, :cancelled_restore].each do |failure|
  scenario = SavedGameConsumptionScenario.new
  scenario.join_bob
  case failure
  when :lost_reply
    scenario.resources.lost_delete_reply = true
  when :denied
    scenario.resources.define_singleton_method(:delete) { |*args, **| raise IOError, "delete denied" }
  when :ignored
    scenario.resources.define_singleton_method(:delete) { |*args, **| nil }
  when :status_timeout
    scenario.app.lobby.define_singleton_method(:set_game_active) { |*| raise EltenAPI::LiveSessions::TimeoutError, "status reply lost" }
  when :cancelled_restore
    # run_network_task returns nil for cancellation, without a confirmed session.
    scenario.app.games.define_singleton_method(:restore_session) { |**| nil }
  end
  resumed = scenario.resume
  remains = scenario.saves.fetch(scenario.saved["id"]) != nil
  warned = scenario.app.notices.any? { |text| text.is_a?(String) && text.include?("saved copy could not be deleted") }
  if failure == :cancelled_restore
    assert(resumed.nil? && remains && !warned, "cancelled restore consumed or misreported its save")
  else
    assert(resumed && scenario.app.games.session_for_table(scenario.table)["__id"] == resumed["__id"],
      "#{failure}: accepted game was lost")
    cleanup_failed = [:denied, :ignored].include?(failure)
    assert(remains == cleanup_failed && warned == cleanup_failed, "#{failure}: cleanup status is misleading")
    assert(!scenario.app.notices.include?("This saved game is not compatible with this version or is damaged."),
      "#{failure}: confirmed restore was reported as damaged")
  end
  scenario.close
end
puts "PASS saved-game consumption: confirmed restore, waiting, failures, exact archive, completion and saving again"
