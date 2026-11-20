require_relative 'native_room_harness'
require_relative '../../lib/game_session_clock'

module ClockEventContract
  module_function

  # One clock for fixture stack receipts and the real session-clock adapter.
  # Advancing it does not sleep, patch Time globally or bypass a round gate.
  class ManualTime
    attr_reader :now

    def initialize(initial = Time.now.to_i)
      @now = initial
    end

    def call; now; end

    def advance(seconds)
      raise ArgumentError, 'Fixture time cannot go backwards' if seconds.negative?
      @now += seconds
    end

    def session_clock
      GameRoomSessionClock.new(sample: -> { now }, elapsed: -> { 0 }, wall: -> { now })
    end
  end

  def with_server_time(initial = 1000)
    old_time = Time.method(:now)
    stamp = initial
    Time.define_singleton_method(:now) { Time.at(stamp) }
    yield ->(value) { stamp = value }
  ensure
    Time.define_singleton_method(:now, old_time)
  end

  def clock
    GameRoomSessionClock.new(sample: -> { Time.now.to_f }, elapsed: -> { 0 }, wall: -> { Time.now.to_f })
  end

  class Fixture
    attr_reader :h, :game, :contexts

    def initialize(game, users: %w[Alice Bob Carol], options: {})
      @game = game
      @h = NativeRoomHarness.new(game: game, users: users,
        options: game.normalize_options(game.default_options.merge(options)))
      h.start
      @contexts = users.to_h do |user|
        [user, GameRoomGames::ActionContext.new(random_source: GameRoomRandom::LocalSecureSource.new,
          hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new))]
      end
    end

    def snapshot(user = h.users.first)
      h.repositories.fetch(user).snapshot_for(h.session)
    end

    def replay(user = h.users.first)
      current = snapshot(user)
      game.replay(current.session, current.events, h.repositories.fetch(user))
    end

    def context(user)
      current = snapshot(user)
      value = contexts.fetch(user)
      value.session_id = current.session['__id']
      value.table_id = h.table['__id']
      value.table_owner = h.transports.fetch(user).room_snapshot(h.table)[:table]['owner']
      value.now = ClockEventContract.clock.now(current.session)
      value.server_random = current.session['__server_random'] == GameRoomServerRandom::VERSION
      value
    end

    def submit(user, selection = nil, control: false)
      current = snapshot(user)
      state = game.replay(current.session, current.events, h.repositories.fetch(user))
      actor = control ? state.players.first : user
      value = context(user)
      selection ||= game.automatic_action(state, actor, context: value)
      status, plan = game.action_for(selection, state, actor, context: value)
      assert(status == :ok, "#{game.id}: #{user} action rejected in #{state.state&.dig(:phase)}: #{status}, #{selection.inspect}")
      h.as(user) do
        h.repositories.fetch(user).append_events(session: current.session,
          sequence: h.repositories.fetch(user).next_sequence(current.session, current.events),
          events: plan.events, actor: actor, controller: control)
      end
    end

    def freeze(user, value)
      h.as(user) { h.transports.fetch(user).freeze_game(snapshot(user).session, frozen: value) }
    end

    def logical_now(user = h.users.first)
      ClockEventContract.clock.now(snapshot(user).session)
    end
  end
end
