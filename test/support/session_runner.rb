require_relative "native_room_harness"
require_relative "log"
require_relative "../../games/tic_tac_toe"
require_relative "../../games/uno"
require_relative "../../games/categories"
require_relative "../../lib/game_session_runner"

def runner_for(h, user = h.users.first, covered: -> { true })
  program = ProgramDouble.new(h.broker.endpoint(user))
  transport = h.transports.fetch(user)
  lobby = LobbyRepository.new(program, transport: transport, server_tables: Object.new)
  context = GameRoomGames::ActionContext.new(hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
    random_source: GameRoomRandom::LocalSecureSource.new)
  h.as(user) do
    runner = GameRoomSessionRunner.new(program: program, transport: transport, repository: h.repositories.fetch(user),
      game: h.game, session: h.session, table: h.table, owner: h.users.first, viewer: user,
      room_snapshot_provider: -> { lobby.snapshot_for(h.table) }, context: context,
      game_status_changed: ->(table, active) { lobby.set_game_active(table, active) }, covered: covered)
    runner.instance_variable_set(:@clock, h.clock.session_clock) if h.clock
    runner
  end
end

def step(h, runner, user = h.users.first, count: 1)
  h.as(user) { count.times { runner.step } }
  error = runner.take_error
  raise error if error
end

def submit(h, runner, user = h.users.first)
  h.as(user) do
    replay = h.replay(user)
    action = h.game.legal_actions(replay, user).first
    runner.submit(session: h.session, replay: replay, selection: action, actor: user)
  end
end
