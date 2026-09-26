require_relative "support/session_runner"

h = NativeRoomHarness.new(game: GameRoomGames::TicTacToe.new, users: %w[Alice Bob])
h.start
seen = []
program = ProgramDouble.new(h.broker.endpoint("Alice"))
transport = h.transports.fetch("Alice")
lobby = LobbyRepository.new(program, transport: transport, server_tables: Object.new)
context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::LocalSecureSource.new)
runner = h.as("Alice") do
  GameRoomSessionRunner.new(program: program, transport: transport, repository: h.repositories.fetch("Alice"),
    game: h.game, session: h.session, table: h.table, owner: "Alice", viewer: "Alice",
    room_snapshot_provider: -> { lobby.snapshot_for(h.table) }, context: context, covered: -> { true },
    statistics_observer: ->(session, replay) { seen << [session["__id"], replay.finished?] })
end
begin
  step(h, runner)
  first_id = h.session["__id"]
  assert(seen.include?([first_id, false]), "Background execution did not observe a confirmed start")
  12.times do
    replay = h.replay("Alice")
    break if replay.finished?
    actor = replay.current_player
    h.submit(actor, h.game.legal_actions(replay, actor).first)
    step(h, runner)
  end
  assert(h.replay("Alice").finished?, "The fixture did not finish a real replay")
  assert(seen.include?([first_id, true]), "The background runner missed the completed replay")
  h.start
  step(h, runner, count: 3)
  assert(seen.include?([h.session["__id"], false]), "The runner observer missed a rematch")
ensure
  runner.close
end
puts "PASS statistics observes real background start, completion and rematch"
