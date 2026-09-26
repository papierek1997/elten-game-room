require "monitor"
require_relative "game_sync"
require_relative "game_bots"
require_relative "game_simulation"
require_relative "game_session_clock"
require_relative "game_execution_policy"

# One executor for turn-based automatic actions, in foreground AND background.
# The screen owns presentation and input; this object never calls a control,
# speaks, pumps the UI, or decides an action outside the game's normal policy.
class GameRoomSessionRunner
  class StaleView < StandardError; end
  CapturedSurface = Struct.new(:submission_action)
  INTERVAL = 0.05

  # ELTEN can open another instance above Messages while an earlier instance
  # still owns a covered game. They must not both drive the same account/table.
  # The active screen wins; while all are covered, the most recent one wins.
  # Handover reconciles once, not periodically, and preserves an outage delay.
  class ExecutionGroup
    attr_reader :operation

    def initialize
      @operation, @members_lock = Monitor.new, Mutex.new
      @members, @executor, @used, @retry_at = [], nil, false, 0.0
      @control_users = 0
    end

    def add(runner); @members_lock.synchronize { @members << runner }; end
    def remove(runner); @members_lock.synchronize { @members.delete(runner); @members.empty? && @control_users.zero? }; end
    def retain_control; @members_lock.synchronize { @control_users += 1 }; end
    def release_control; @members_lock.synchronize { @control_users -= 1; @members.empty? && @control_users.zero? }; end

    def activate(runner)
      members = @members_lock.synchronize { @members.dup }.reject(&:closed?)
      selected = members.reverse.find { |member| !member.covered? } || members.last
      return [false, false, 0.0] unless selected.equal?(runner)
      changed = !@executor.equal?(runner)
      reconcile = changed && @used
      @executor, @used = runner, true
      [true, reconcile, [@retry_at - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0.0].max]
    end

    def defer(delay)
      @retry_at = [@retry_at, Process.clock_gettime(Process::CLOCK_MONOTONIC) + delay].max
    end
  end
  GROUPS_LOCK = Mutex.new
  GROUPS = {}

  # UI management uses the same account/table boundary as the executor. In
  # particular no old-owner bot may seal a choice between validation and
  # ownership transfer. Do not hold this across a UI dialog or another table.
  def self.synchronize_table(program:, table_id:, viewer:, &operation)
    key = [program.class, table_id.to_i, viewer.to_s.downcase]
    group = GROUPS_LOCK.synchronize do
      value = GROUPS[key] ||= ExecutionGroup.new
      value.retain_control
      value
    end
    group.operation.synchronize(&operation)
  ensure
    GROUPS_LOCK.synchronize do
      GROUPS.delete(key) if group && group.release_control && GROUPS[key].equal?(group)
    end
  end

  def initialize(program:, transport:, repository:, game:, session:, table:,
    owner:, viewer:, room_snapshot_provider:, context:, game_status_changed: nil,
    covered: nil, activity_repository: nil, statistics_observer: nil)
    @program, @transport, @repository = program, transport, repository
    @game = game.build_session_game
    @session, @table = copy(session), copy(table)
    @owner, @viewer = owner.to_s, viewer.to_s
    @table_id = (table["__id"] || table["id"]).to_i
    @room_snapshot_provider, @game_status_changed = room_snapshot_provider, game_status_changed
    @activity_repository = activity_repository
    @statistics_observer = statistics_observer
    @context_template = context
    @clock = GameRoomSessionClock.new
    @coordinator = GameRoomBots::Coordinator.new
    @planning_game = game.build_session_game
    @turn = repository.bot_turn_controller(@table_id)
    @operation = Monitor.new
    @state_lock = Mutex.new
    @wake = ConditionVariable.new
    @closed = false
    @view = nil
    @ui_thread = Thread.current
    @covered = covered || -> { defined?($currentthread) && $currentthread && $currentthread != @ui_thread }
    @feed = transport.subscribe_game_session(@table_id)
    @sync = GameRoomSync::Controller.new(transport: @feed, table_id: @table_id,
      session_id: repository.session_id(session))
    @dirty = true
    @errors = Queue.new
    @action_errors = Queue.new
  end

  def start
    return self if @thread
    runtime = @program.class.app_runtime if @program.class.respond_to?(:app_runtime)
    register_execution_group
    @program.class.manage(self) if @program.class.respond_to?(:manage)
    @thread = Thread.new do
      Thread.current.report_on_exception = false
      work = -> do
        until closed?
          step
          @state_lock.synchronize { @wake.wait(@state_lock, INTERVAL) unless @closed }
        end
      end
      if runtime && defined?(Programs) && Programs.respond_to?(:with_runtime)
        Programs.with_runtime(runtime) { work.call }
      else
        work.call
      end
    ensure
      @feed.close
      unregister_execution_group
      @program.class.release(self) if @program.class.respond_to?(:release)
    end
    self
  rescue Exception
    @feed.close
    unregister_execution_group
    @program.class.release(self) if @program.class.respond_to?(:release)
    raise
  end

  # Called exclusively by the UI thread. Plain data is copied, never controls.
  # A visible screen acknowledges presentation before another automatic move;
  # a covered screen need not acknowledge every intermediate position.
  def publish_view(session:, replay:, busy:, context:, surface: nil)
    value = {session_id: @repository.session_id(session), revision: revision(replay),
      busy: busy, local_data: copy(context.local_data), surface: nil}
    identity = @game.automatic_surface_identity(replay)
    if identity && surface&.respond_to?(:submission_action)
      value[:surface_identity] = copy(identity)
      value[:surface] = CapturedSurface.new(copy(surface.submission_action))
    end
    @state_lock.synchronize { @view = value; @wake.signal }
  end

  # Used only INSIDE a Tasks worker, never around a UI wait or loop_update.
  def synchronize(&block)
    (@execution_group&.operation || @operation).synchronize(&block)
  end

  # Human input and automatic actions share the same commit boundary. Reject a
  # stale view before action_for can consume a hidden answer or randomness.
  def submit(session:, replay:, selection:, actor:, controller: false)
    synchronize do
      raise @internal_error if @internal_error
      raise StaleView if closed? || !activate_executor || @sync.waiting?
      refresh(force: @sync.recovery_pending?)
      raise StaleView unless @snapshot && !@session["__frozen"] && !@session["__aborted"] &&
        session["__control_epoch"] == @session["__control_epoch"] && @session["__control_ready"] != false &&
        GameRoomParticipants.includes?(@replay.players, actor) &&
        @repository.session_id(session) == @repository.session_id(@session) &&
        (revision(replay) == revision(@replay) || @game.concurrent_session_input?(replay, @replay, selection))
      commit(selection, actor, controller: controller)
    end
  end

  def close
    @state_lock.synchronize { @closed = true; @wake.broadcast }
    @feed.close
    # An in-flight bounded request may still finish. Never kill an uncertain
    # write. GameScreen waits through Tasks on exit before closing its services.
    nil
  end

  def closed?; @state_lock.synchronize { @closed }; end
  def alive?; @thread&.alive?; end
  def join; @thread&.join; end
  def covered?; @covered.call; end

  # Immutable-by-ownership: only the worker replaces this packet; UI copies it
  # before use. No network request or wait for an in-flight write on this path.
  def presentation_snapshot
    @state_lock.synchronize { @presentation_snapshot }
  end

  def take_error
    # A covered screen may return after the worker has already recovered.
    # Do not turn that historical failure into a fresh UI outage.
    return nil unless @internal_error || @sync.recovery_pending?
    @errors.pop(true)
  rescue ThreadError
    nil
  end

  def recovery_delay
    return 0.0 unless @sync.waiting?
    [@sync.next_reconcile_at - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0.0].max
  end

  def take_action_error(session, replay)
    key, status = @action_errors.pop(true)
    status if key == [@repository.session_id(session), revision(replay), session['__control_epoch']]
  rescue ThreadError
    nil
  end

  # Public for deterministic lifecycle/clock regression tests. Production has
  # exactly one caller, the managed worker above.
  def step
    return if closed? || @internal_error
    bot_work = nil
    @transport.dispatch_pending_events
    synchronize do
      return if closed?
      event = @sync.next_event
      if event&.kind == :closed
        close
        return
      end
      @dirty = true if event
      return unless activate_executor
      return if @sync.waiting?
      verified = @turn.verification_due?
      refresh(force: verified || event&.kind == :recovery) if @dirty || verified
      return unless @snapshot && @replay
      return if closed? || @session["__frozen"] || @session["__aborted"] || @session["__control_ready"] == false
      update_table_status
      return if @replay.finished? || @sync.recovery_pending?
      view = @state_lock.synchronize { @view }
      covered = covered?
      return unless covered || (view && view[:session_id] == @repository.session_id(@session) &&
        view[:revision] == revision(@replay) && !view[:busy])
      bot_work = prepare_bot unless perform_automatic(view)
    end
    perform_bot(bot_work) if bot_work
  rescue StandardError => error
    @dirty = true
    if GameRoomNetworkErrors.expected?(error) || GameRoomNetworkErrors.cancelled?(error)
      @sync.failed!(error)
      synchronize { @execution_group&.defer(recovery_delay) }
      @turn.defer_verification
    else
      # Do not repeatedly execute a broken action or pretend it is an outage.
      # The UI receives the exception once; no leave/close is sent to the room.
      @internal_error = error
      @errors.clear # A recovered, undelivered network error cannot hide this fault.
    end
    @errors << error if @errors.empty?
    Log.warning("ELTEN Game Room session runner failed: #{error.class}: #{error.message}\n#{Array(error.backtrace).first(8).join("\n")}") if defined?(Log)
  end

  private

  def register_execution_group
    @execution_key = [@program.class, @table_id, @viewer.downcase]
    GROUPS_LOCK.synchronize do
      @execution_group = GROUPS[@execution_key] ||= ExecutionGroup.new
      @execution_group.add(self)
    end
  end

  def unregister_execution_group
    GROUPS_LOCK.synchronize do
      if @execution_group && @execution_group.remove(self)
        GROUPS.delete(@execution_key) if GROUPS[@execution_key].equal?(@execution_group)
      end
    end
  end

  def activate_executor
    return true unless @execution_group
    active, reconcile, delay = @execution_group.activate(self)
    if reconcile
      @dirty = true
      @sync.request_recovery!(delay: delay)
    end
    active
  end

  def refresh(force: false)
    @sync.synchronize do
      room = @room_snapshot_provider.call
      unless room
        @snapshot = @replay = nil
        close
        return
      end
      @room, @table = room, copy(room.table)
      @owner = @table["owner"].to_s
      latest_id = @repository.latest_session_id_for_table(@table)
      if latest_id.positive? && latest_id != @repository.session_id(@session)
        next_session = @repository.session_by_id(latest_id, table: @table)
        raise StaleView unless next_session
        @session = next_session
        @sync.update_session(latest_id)
      end
      snapshot = @repository.snapshot_for(@session, force_events: force && !@sync.reconciled?)
      unless snapshot
        @snapshot = @replay = nil
        return
      end
      @snapshot, @session = snapshot, snapshot.session
      @replay = @game.replay(@session, snapshot.events, @repository)
      if reconcile_departed_players
        snapshot = @repository.snapshot_for(@session)
        @snapshot, @session = snapshot, snapshot.session
        @replay = @game.replay(@session, snapshot.events, @repository)
        room = @room_snapshot_provider.call || room
        @room, @table = room, copy(room.table)
      end
      @statistics_observer&.call(@session, @replay)
      @turn.observe(session_id: @repository.session_id(@session), events: snapshot.events,
        confirmed_event_ids: @repository.confirmed_event_ids(@session), verified: force)
      presentation = copy({session: @session, table: @table, replay: @replay, members: room.members,
        activity: @activity_repository ? @activity_repository.entries_for(@table, viewer: @viewer) : []})
      @state_lock.synchronize { @presentation_snapshot = presentation }
      @dirty = false
    end
    @errors.clear unless @sync.recovery_pending?
  end

  def context
    view = @state_lock.synchronize { @view }
    GameRoomGames::ActionContext.new(
      session_id: @repository.session_id(@session), table_id: @table_id,
      hidden_submissions: @context_template.hidden_submissions,
      random_source: @context_template.random_source,
      options: @game.options_from_json(@session["options"]), table_owner: @owner,
      local_data: view ? view[:local_data] : @context_template.local_data,
      now: @clock.public_send(@game.precise_action_clock? ? :now_f : :now, @session)
    )
  end

  def perform_automatic(view)
    ctx = context
    key = [@repository.session_id(@session), revision(@replay), @session['__control_epoch']]
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    retrying = @automatic_retry_key == key
    return false if retrying && now < @automatic_retry_at
    if GameRoomParticipants.same?(@viewer, @owner)
      controlled_actors.each do |seat|
        next unless @game.automatic_action_allowed?(@replay, seat, table_owner: @owner)
        selection = @game.automatic_action(@replay, seat, context: ctx)
        return execute_automatic(selection, seat, key, now, controller: true) if selection
      end
    end
    # The last UI-owned answer snapshot can be submitted at its real deadline
    # without ever reading an EditBox in this thread. The identity above keeps
    # that draft in its own round; action_for validates the current phase.
    if !controlled_actors.include?(@viewer) && view && view[:session_id] == @repository.session_id(@session) && view[:surface] &&
        view[:surface_identity] && view[:surface_identity] == @game.automatic_surface_identity(@replay)
      local = @game.automatic_surface_action(@replay, @viewer, surface: view[:surface], context: ctx)
      return execute_automatic(local, @viewer, key, now) if local
    end
    return false unless @game.automatic_action_allowed?(@replay, @viewer, table_owner: @owner)
    return false if controlled_actors.include?(@viewer) && !GameRoomParticipants.same?(@owner, @viewer)
    actor = @game.automatic_actor(@replay, @viewer, table_owner: @owner)
    return false if actor.to_s.empty?
    return false if @automatic_checked == key && !retrying &&
      !@game.automatic_action_due?(@replay, actor, context: ctx)
    @automatic_checked = key
    selection = @game.automatic_action(@replay, actor, context: ctx)
    return false unless selection
    execute_automatic(selection, actor, key, now, controller: !GameRoomParticipants.same?(actor, @viewer))
  end

  def execute_automatic(selection, actor, key, now, controller: false)
    status = commit(selection, actor, controller: controller).first
    if status == :ok
      @automatic_retry_key = nil
      true
    else
      @automatic_retry_key, @automatic_retry_at = key, now + 1.0
      unless @last_action_error == [key, status]
        @last_action_error = [key, status]
        @action_errors.clear
        @action_errors << [key, status]
        Log.warning("ELTEN Game Room automatic action was rejected: #{@game.id}, #{status}") if defined?(Log) && status != :local_storage_unavailable
      end
      false
    end
  end

  def prepare_bot
    return nil unless GameRoomParticipants.same?(@owner, @viewer)
    actor = @coordinator.pending_bot(@game, @replay, controlled_actors: controlled_actors)
    return nil unless actor
    ctx = context
    rev = @repository.events_revision(@snapshot.events)
    @turn.schedule_decision(session_id: @repository.session_id(@session), actor: actor,
      revision: @game.bot_delay_revision(@replay, rev), delay: @game.bot_move_delay(@replay, actor, context: ctx))
    lease = @turn.acquire(session_id: @repository.session_id(@session), actor: actor, revision: rev)
    return nil unless lease
    {lease: lease, actor: actor, context: ctx, session: copy(@session), replay: copy(@replay),
      revision: revision(@replay), players: @repository.players_for(@session), controlled_actors: controlled_actors}
  rescue Exception
    @turn.cancel(lease) if lease
    raise
  end

  # Planning has its own game/caches and an immutable input snapshot. It must
  # not hold the commit lock: UNO interceptions, Makao declarations and chat
  # remain usable while a strategy is calculating. Revalidate before writing.
  def perform_bot(work)
    lease, session, replay = work.values_at(:lease, :session, :replay)
    begin
      return false if closed?
      @planning_game.prepare_view(replay, work[:actor], context: work[:context])
      decision = GameRoomExecutionPolicy.bot_decision(game: @planning_game, session: session, replay: replay,
        repository: @repository, coordinator: @coordinator, context: work[:context], players: work[:players],
        controlled_actors: work[:controlled_actors])
      return false if closed? || !decision
      # The native client may have received another move while this worker was
      # calculating and the UI was covered. Decode that already queued change
      # before checking the planned revision; no additional server polling.
      @transport.dispatch_pending_events
      synchronize do
        return false unless activate_executor
        change = @sync.next_event
        if change&.kind == :closed
          close
          return false
        end
        @dirty = true if change
        return false if closed? || @sync.recovery_pending?
        refresh
        return false unless GameRoomParticipants.same?(@owner, @viewer) && session["__control_epoch"] == @session["__control_epoch"]
        return false if @session["__frozen"] || @session["__aborted"] || !@replay ||
          [@repository.session_id(session), work[:revision]] != [@repository.session_id(@session), revision(@replay)]
        commit(decision.action, decision.actor, lease: lease,
          controller: controlled_actors.include?(decision.actor)).first == :ok
      end
    ensure
      @turn.cancel(lease)
    end
  end

  def commit(selection, actor, controller: false, lease: nil)
    return [:closed, nil] if closed?
    status, plan = @game.action_for(selection, @replay, actor, context: context)
    return [status, nil] unless status == :ok
    unless plan.is_a?(GameRoomGames::ActionPlan) && !plan.events.to_a.empty?
      raise ArgumentError, "a successful game action must return an ActionPlan"
    end
    if plan.events.size > GameRepository::MAX_EVENTS_PER_ACTION || plan.events.any? { |event|
        event['action'].to_s.length > GameRepository::MAX_ACTION_LENGTH ||
        event['value'].to_s.length > GameRepository::MAX_VALUE_LENGTH }
      Log.warning("ELTEN Game Room rejected oversized session action: #{@game.id}") if defined?(Log)
      return [:oversized_session_action, nil]
    end
    return [:busy, nil] if lease && !@turn.submitting(lease, events: plan.events)
    begin
      inserted = @repository.append_events(session: @session,
        sequence: @repository.next_sequence(@session, @replay.accepted_events), events: plan.events,
        recipients: GameRoomParticipants.humans(@room.members), actor: actor, controller: controller)
      raise GameRoomNetworkErrors::UncertainWrite, "Game action was not confirmed" unless inserted && !inserted.empty?
      @turn.submitted(lease, event_ids: inserted.map { |event| @repository.event_id(event) }) if lease
      @dirty = true
      [:ok, inserted]
    rescue Exception => error
      @turn.submission_failed(lease) if lease
      @dirty = true
      if GameRoomNetworkErrors.expected?(error) || GameRoomNetworkErrors.cancelled?(error)
        @sync.request_recovery!(delay: GameRoomSync::ERROR_BACKOFF)
        @execution_group&.defer(recovery_delay)
      end
      raise
    end
  end

  def update_table_status
    return unless @game_status_changed && GameRoomParticipants.same?(@owner, @viewer)
    desired = @replay.finished? ? "waiting" : "playing"
    return if @table["status"].to_s == desired
    updated = @game_status_changed.call(@table, !@replay.finished?)
    @table = updated if updated.is_a?(Hash)
  end

  def controlled_actors
    @session.fetch("__controllers", {}).select { |_seat, kind| kind == "bot" }.keys
  end

  def reconcile_departed_players
    departed = GameRoomExecutionPolicy.departed_players(game: @game, replay: @replay, session: @session,
      players: @repository.players_for(@session), members: @room&.members, owner: @owner, viewer: @viewer, transport: @transport)
    changed = false
    departed.each do |seat|
      current = @repository.snapshot_for(@session).session
      guard = @repository.control_change_guard(table: @table, game: @game, session: current, player: seat)
      changed = @transport.set_seat_controller(@table_id, session_id: @repository.session_id(@session), seat: seat, bot: true,
        control_guard: guard) || changed
    end
    changed
  end

  def revision(replay)
    @repository.events_revision(replay.accepted_events)
  end

  def copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
