require_relative "native_live_sessions"
require_relative "../../lib/game_sync"
require_relative "../../lib/game_random"
require_relative "../../lib/hidden_submissions"
require_relative "replay_snapshot"

def n_(singular, plural, count); count == 1 ? singular : plural; end

class NativeRoomHarness
  attr_reader :broker, :users, :table, :transports, :repositories, :session, :game, :clock

  def initialize(game: nil, users: %w[Alice Bob Carol Dave], options: nil, bots: 0, tournament: nil, clock: nil)
    @clock = clock
    @broker = clock ? NativeLiveSessionsBroker.new(clock: clock) : NativeLiveSessionsBroker.new
    @users = users
    @game = game
    @options = options || game&.default_options || {}
    @transports = {}
    @repositories = {}
    users.each { |user| add_client(user) }
    @table = as(users.first) do
      @transports.fetch(users.first).create_room(
        name: "Native test room", game: game&.id || "test", owner: users.first,
        game_options: JSON.generate(@options), capacity: 8, tournament_match: tournament,
        stack_entries: game&.session_history_capacity(@options) || GameRoomLiveSessionStore::STACK_ENTRIES
      )
    end
    users.drop(1).each do |user|
      assert(join(user), "#{user} could not join the native room")
    end
    @transports.fetch(users.first).update_room(table, { "bot_count" => bots }, actor: users.first) if bots > 0
  end

  def as(user)
    previous = Thread.current[:game_room_test_user]
    Thread.current[:game_room_test_user] = user
    yield
  ensure
    Thread.current[:game_room_test_user] = previous
  end

  def add_client(user)
    program = ProgramDouble.new(broker.endpoint(user))
    @transports[user] = GameRoomTransport.new(program)
    @repositories[user] = GameRepository.new(program, transport: @transports[user], server_tables: Object.new)
    @transports[user].start
  end

  def join(user)
    transport = transports.fetch(user)
    discovered = transport.discover_rooms.find { |room| room["__id"] == table["__id"] }
    return false if discovered == nil
    as(user) do
      transport.establish_membership(table_id: table["__id"], owner: users.first,
        capacity: 8, user: user, table: discovered)
    end
  end

  def start
    @session = as(users.first) do
      repositories.fetch(users.first).start_session(table: table, game: game&.id || "test",
        players: users + transports.fetch(users.first).room_snapshot(table)[:bots], options: JSON.generate(@options))
    end
  end

  def view(user); broker.endpoint(user).sessions.find { |view| view.id == table["__live_session_id"] }; end
  def core; broker.cores.fetch(table["__live_session_id"]); end
  def events(user); repositories.fetch(user).snapshot_for(session).events; end
  def replay(user)
    repository = repositories.fetch(user)
    snapshot = repository.snapshot_for(session)
    game.replay(snapshot.session, snapshot.events, repository)
  end

  def write(user, commands, sequence: nil)
    as(user) do
      repository = repositories.fetch(user)
      repository.append_events(session: session, sequence: sequence || repository.next_sequence(session, events(user)),
        events: commands, actor: user)
    end
  end

  def submit(user, selection = nil, context: nil, replay: nil)
    current = replay || self.replay(user)
    context ||= GameRoomGames::ActionContext.new(session_id: session["__id"], table_id: table["__id"], now: 1_000)
    context.server_random = session['__server_random'] == GameRoomServerRandom::VERSION
    selection ||= game.automatic_action(current, user, context: context)
    status, plan = game.action_for(selection, current, user, context: context)
    assert(status == :ok, "#{game.id}: #{user}'s action failed: #{status}, #{selection.inspect}")
    write(user, plan.events)
  end

  def assert_converged(stage, expected_count: nil)
    all = users.map { |user| events(user) }
    assert(all.uniq.length == 1, "#{stage}: clients disagree about the ordered stack")
    ids = all.first.map { |event| event["__id"] }
    assert(ids == ids.sort && ids == ids.uniq, "#{stage}: unordered or duplicated events")
    assert(ids.length == expected_count, "#{stage}: #{ids.length} events instead of #{expected_count}") if expected_count
    if game
      snapshots = users.map { |user| GameRoomTest::ReplaySnapshot.capture(replay(user)) }
      differences = GameRoomTest::ReplaySnapshot::FIELDS.select do |field|
        snapshots.map { |snapshot| snapshot[field] }.uniq.length != 1
      end
      assert(differences.empty?, "#{stage}: game replays diverged: #{differences.join(', ')}")
    end
  end
end
