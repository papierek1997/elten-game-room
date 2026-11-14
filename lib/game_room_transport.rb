require_relative "game_participants"
require_relative "live_session_store"
require_relative "game_session_feed"

class GameRoomTransport
  attr_writer :presence_listener

  def initialize(program, clock: GameRoomClock, local_view: false)
    @program = program
    @live_store = GameRoomLiveSessionStore.new(program, changed: method(:live_store_changed),
      presence_changed: -> { @presence_listener&.changed }, clock: clock, local_view: local_view)
    @pending_table_changes = {}
    @pending_game_changes = {}
    @pending_game_starts = {}
    @pending_recoveries = {}
    @newly_joined = {}
    @session_feeds = {}
    @mutex = Mutex.new
  end

  # Zwalnia wyłącznie własny, jawnie lokalny widok transakcji.
  def close_local_view
    @live_store.close_local_view
  end

  def start
    @live_store.start
  end

  def local_actor
    @live_store.local_actor
  end

  def invitation_account_identity
    @live_store.invitation_account_identity
  end

  # Also used by the shared table-activity repository to choose its transport.
  def live_store?
    true
  end

  def dispatch_pending_events
    result = @live_store.dispatch_pending_events
    with_retained_rooms { |_rooms| }
    result
  end

  def maintain_pending_work
    @live_store.maintain_pending_work
    with_retained_rooms { |_rooms| }
    nil
  end

  def with_retained_rooms
    @live_store.with_retained_rooms do |rooms|
      @mutex.synchronize do
        @session_feeds.each_key { |id| rooms[id] = true }
        result = yield rooms
        prune_pending_rooms(rooms)
        result
      end
    end
  end

  def subscribe_game_session(table_id)
    feed = GameRoomSessionFeed.new(self, table_id)
    @live_store.retain_room_subscription(table_id)
    @mutex.synchronize { ((@session_feeds ||= {})[table_id.to_i] ||= []) << feed }
    feed
  end

  def unsubscribe_game_session(table_id, feed)
    removed = @mutex.synchronize do
      feeds = (@session_feeds || {})[table_id.to_i]
      deleted = feeds&.delete(feed)
      @session_feeds.delete(table_id.to_i) if feeds&.empty?
      deleted
    end
    @live_store.release_room_subscription(table_id) if removed
    with_retained_rooms { |_rooms| }
  end

  def reconcile(table_id)
    @live_store.reconcile(table_id)
  end

  def pending_move_error(table_id)
    @live_store.pending_move_error(table_id)
  end

  def consume_recovered_game_events(session)
    @live_store.consume_recovered_game_events(session)
  end

  def send_private_game(**arguments)
    @live_store.send_private_game(**arguments)
  end

  def private_game_messages_pending?(table_id, session_id)
    @live_store.private_game_messages_pending?(table_id, session_id)
  end

  def take_private_game_messages(table_id, session_id)
    @live_store.take_private_game_messages(table_id, session_id)
  end

  def send_game_preview(**arguments)
    @live_store.send_game_preview(**arguments)
  end

  def take_game_previews(table_id, session_id)
    @live_store.take_game_previews(table_id, session_id)
  end

  def create_room(**arguments)
    @live_store.create_room(**arguments)
  end

  def discover_rooms(game: nil, include_private: false)
    @live_store.discover_rooms(game: game, include_private: include_private)
  end

  def discovered_roster(table)
    @live_store.discovered_roster(table)
  end

  def discovered_options(table)
    @live_store.discovered_options(table)
  end

  def note_realtime_activity(table_id, session_id)
    @live_store.note_realtime_activity(table_id, session_id)
  end

  def current_room(user)
    @live_store.current_room(user)
  end

  def room_snapshot(table_or_id, force: false, **options)
    @live_store.room_snapshot(table_or_id, force: force, **options)
  end

  def transfer_room_owner(table_or_id, user, control_guard: nil)
    @live_store.transfer_room_owner(table_or_id, user, control_guard: control_guard)
  end

  def set_seat_controller(table_or_id, **options)
    @live_store.set_seat_controller(table_or_id, **options)
  end

  def replace_game_player(table_or_id, **options)
    @live_store.replace_game_player(table_or_id, **options)
  end

  def set_observer(table_or_id, observing, actor:, subject: nil)
    @live_store.set_observer(table_or_id, observing, actor: actor, subject: subject)
  end

  def join_room(table, user)
    @live_store.join_room(table, user)
  end

  def update_room(table_or_id, changes, actor:)
    @live_store.update_room(table_or_id, changes, actor: actor)
  end

  def table_voice(table, **options); @live_store.table_voice(table, **options); end
  def change_table_voice(table, data, actor:); @live_store.change_table_voice(table,data,actor:actor); end

  def change_game_options(**arguments)
    @live_store.change_game_options(**arguments)
  end

  def abort_game(session, **options)
    @live_store.abort_game(session, **options)
  end

  def append_activity(**arguments)
    @live_store.append_activity(**arguments)
  end

  def activity_records(table_or_id)
    @live_store.activity_records(table_or_id)
  end

  def start_game(**arguments)
    @live_store.start_game(**arguments)
  end

  def game_sessions(table_or_id = nil, force: false)
    @live_store.game_sessions(table_or_id, force: force)
  end

  def game_session(session_id, table: nil)
    @live_store.game_session(session_id, table: table)
  end

  def find_game_session(table_or_id, force: false, &predicate)
    @live_store.find_game_session(table_or_id, force: force, &predicate)
  end

  def append_game_action(**arguments)
    @live_store.append_game_action(**arguments)
  end

  def game_action_limits(table_or_id)
    @live_store.game_action_limits(table_or_id)
  end

  def game_events(session, force: false, read_only: false)
    @live_store.game_events(session, force: force, read_only: read_only)
  end

  def private_cards_snapshot(session, events)
    @live_store.private_cards_snapshot(session, events)
  end

  def shared_private_draws_snapshot(session, audiences)
    @live_store.shared_private_draws_snapshot(session, audiences)
  end

  def freeze_game(session, frozen: true, expected_boundary: nil)
    @live_store.freeze_game(session, frozen: frozen, expected_boundary: expected_boundary)
  end

  def append_tournament_presence(session, **options)
    @live_store.append_tournament_presence(session, **options)
  end

  def pending_invitations
    @live_store.pending_invitations
  end

  def reject_discovered_invitation(table)
    @live_store.reject_discovered_invitation(table)
  end

  def activate_table(table_id:, owner:, capacity:, user: nil)
    room = @live_store.current_room(user || owner)
    return room != nil && room["__id"].to_i == table_id.to_i
  end

  def establish_membership(table_id:, owner:, capacity:, user:, invitation_id: nil, bootstrap: false, timeout: 10.0, table: nil)
    current_user = user.to_s
    return false if current_user.empty?

    current = @live_store.current_room(current_user)
    return true if current != nil && current["__id"].to_i == table_id.to_i

    if invitation_id != nil
      accepted = @live_store.accept_invitation(
        table_id: table_id,
        invitation_id: invitation_id,
        participant_metadata: { "table_id" => table_id.to_i }
      )
      @mutex.synchronize { @newly_joined[[table_id.to_i, current_user.downcase]] = true } if accepted
      return accepted
    end
    status = establish_membership_status(table_id: table_id, owner: owner, capacity: capacity, user: current_user, table: table)
    return [:joined, :already_here].include?(status)
  end

  def establish_membership_status(table_id:, owner:, capacity:, user:, table: nil)
    candidate = table || { "__id" => table_id, "owner" => owner, "max_players" => capacity }
    status = @live_store.join_room(candidate, user.to_s)
    @mutex.synchronize { @newly_joined[[table_id.to_i, user.to_s.downcase]] = true } if status == :joined
    status
  end

  def wait_for_membership(table_id:, timeout: 10.0)
    @live_store.wait_for_room(table_id, timeout: timeout)
  end

  def deactivate_table(table_id:, deferred: false)
    @live_store.deactivate_room(table_id, deferred: deferred)
  end

  def connected_users(table_id)
    @live_store.connected_users(table_id)
  end

  def active_membership?(table_id)
    @live_store.active_membership?(table_id)
  end

  def membership_token(table_id)
    @live_store.membership_token(table_id)
  end

  def ownership_token(table_id)
    @live_store.ownership_token(table_id)
  end

  def consume_new_join(table_id, user)
    @mutex.synchronize { @newly_joined.delete([table_id.to_i, user.to_s.downcase]) == true }
  end

  def invite_user(table_id:, user:, metadata:)
    @live_store.invite_user(table_id: table_id, user: user, metadata: metadata)
  end

  def accept_invitation(table_id:, invitation_id:, participant_metadata: {})
    return @live_store.accept_invitation(
      table_id: table_id,
      invitation_id: invitation_id,
      participant_metadata: participant_metadata
    )
  end

  def reject_invitation(table_id:, invitation_id:)
    @live_store.reject_invitation(table_id: table_id, invitation_id: invitation_id)
  end

  def consume_table_change(table_id)
    @mutex.synchronize { @pending_table_changes.delete(table_id.to_i) == true }
  end

  def consume_game_change(session_id)
    @mutex.synchronize do
      # Compatibility for ID-only adapters. Real screens know their room and
      # use the bounded room signal below; game IDs are not globally unique.
      matches = @pending_game_changes.select { |_id, change| change.first == session_id.to_i }
      @pending_game_changes.delete(matches.keys.first)&.last if matches.one?
    end
  end

  def consume_room_game_change(table_id)
    @mutex.synchronize { @pending_game_changes.delete(table_id.to_i)&.last }
  end

  def consume_game_start(table_id)
    @mutex.synchronize do
      session_id = @pending_game_starts.delete(table_id.to_i).to_i
      session_id > 0 ? session_id : nil
    end
  end

  def consume_recovery(table_id)
    recovery = @mutex.synchronize { @pending_recoveries.delete(table_id.to_i) }
    # Leaving queues a terminal event even when no table window is waiting
    # anymore. Rejoining the same room must not deliver that old event to a
    # new window. Unlike the late-callback guard in the store, this also
    # handles a closure which was already queued BEFORE the new membership.
    # The check is local, with no reconnect or polling. A genuinely closed
    # current membership still returns :closed (including cache eviction).
    return nil if recovery == :closed && @live_store.active_membership?(table_id)

    recovery
  end

  private

  def live_store_changed(table_id, kind, value)
    with_retained_rooms do |_rooms|
      case kind.to_sym
      when :game_started
        @pending_game_starts[table_id.to_i] = value.to_i if value.to_i.positive?
        @pending_table_changes[table_id.to_i] = true
      when :game
        if value.to_i.positive?
          # A wake-up only requests a verified revision check, not a session
          # switch. Retain one signal per room across rematches, including late
          # historical/invalid hints; keep the earliest unconsumed timestamp.
          previous = @pending_game_changes[table_id.to_i]
          @pending_game_changes[table_id.to_i] = [value.to_i, previous ? previous.last : monotonic_time]
        end
      when :closed
        @pending_recoveries[table_id.to_i] = :closed
      when :recovery
        @pending_recoveries[table_id.to_i] ||= true
        @pending_table_changes[table_id.to_i] = true
      when :network_error
        @pending_recoveries[table_id.to_i] = value if @pending_recoveries[table_id.to_i] != :closed
      when :table
        @pending_table_changes[table_id.to_i] = true
      end
      (@session_feeds || {}).fetch(table_id.to_i, []).each { |feed| feed.notify(kind, value) }
    end
  end

  def prune_pending_rooms(retained)
    [@pending_table_changes, @pending_game_changes, @pending_game_starts, @pending_recoveries].each do |map|
      map.delete_if { |id, _| !retained[id] }
    end
    @newly_joined.delete_if { |(id, _user), _| !retained[id] }
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

end
