require_relative "table_watch"
require_relative "game_room_notifications"

module GameRoomTableWatchRuntime
  def table_watch_repository
    GameRoomTableWatch::Preferences.new(
      EltenLink::Apps.table(EltenLink::Client.new, server_app_uuid, GameRoomTableWatch::TABLE), games: self::GAME_REGISTRY.ids)
  end

  def table_watch_receiver
    user = Session.name.to_s
    if !@table_watch_receiver || !@table_watch_receiver.user.casecmp?(user)
      @table_watch_sender&.close
      @table_watch_sender = nil
      @table_watch_loader&.close
      @table_watch_loader = nil
      @table_watch_load_state = nil
      @table_watch_receipt_writer&.close
      @table_watch_pruned = {}
      @table_watch_clock = GameRoomTableWatch::Clock.new
      data = begin
        GameRoomTableWatch::Timing.measure(:receipts_startup_read) do
          respond_to?(:read_json) ? read_json("table-notice-receipts.json", default: {}) : {}
        end
      rescue StandardError => error
        Log.warning("Game Room table receipts could not be read: #{error.class}") if defined?(Log)
        {}
      end
      runtime = Programs.current_runtime if defined?(Programs) && Programs.respond_to?(:current_runtime)
      receipt_clock = @table_watch_clock
      @table_watch_receipt_writer = GameRoomTableWatch::ReceiptWriter.new(runtime: runtime) do |value|
        if respond_to?(:update_json)
          update_json("table-notice-receipts.json", default: {}) do |state|
            raise TypeError, "Invalid table receipt storage" unless state.is_a?(Hash)
            previous = state[user.downcase].is_a?(Hash) ? state[user.downcase]["resolved"] : {}
            previous = {} unless previous.is_a?(Hash)
            previous = previous.select { |_key, expiry| GameRoomNotificationTime.integer_value?(expiry) }
            # Older writes from a prior runtime/account must not undo a
            # newer join. Only expiration can remove a resolved session.
            merged = previous.merge(value.fetch("resolved")) { |_key, old, fresh| [old.to_f, fresh.to_f].max }
            now = receipt_clock.call
            merged = merged.select { |_key, expiry| expiry.to_f > now }.to_a.last(1024).to_h
            state[user.downcase] = { "resolved" => merged }
          end
        end
      end
      writer = @table_watch_receipt_writer
      @table_watch_receiver = GameRoomTableWatch::Receiver.new(user: user, games: self::GAME_REGISTRY.ids,
        uuid: server_app_uuid, clock: @table_watch_clock,
        stored: data.is_a?(Hash) ? data[user.downcase] || {} : {}, persist: ->(value) { writer.enqueue(value) })
    end
    @table_watch_receiver
  end

  def table_watch_start(refresh: false)
    receiver = table_watch_receiver
    sharing = @table_watch_loader && @table_watch_load_state == :loading
    table_watch_preferences_snapshot
    return if sharing
    return if receiver.user.empty? || @table_watch_loader&.busy?
    return if !refresh && @table_watch_loader
    # A refused explicit refresh still owns a pending read, even when older
    # preferences are cached. Do not report those as a fresh Settings result.
    return if !refresh && receiver.games != nil && @table_watch_load_state != :loading
    @table_watch_loader&.close
    runtime = Programs.current_runtime if defined?(Programs) && Programs.respond_to?(:current_runtime)
    @table_watch_loader = GameRoomBackground::Work.new(runtime: runtime)
    @table_watch_load_state = :loading
    user = receiver.user
    admitted = GameRoomBackground.admit(@table_watch_loader) do
      # Preferences need no timestamp. The receiver defers notifications until
      # the native clock is ready; a cold clock must not fail this one-off load.
      table_watch_repository.load(user)
    end
    unless admitted
      @table_watch_loader.close
      @table_watch_loader = nil
    end
  end

  def table_watch_set_games(games)
    receiver = table_watch_receiver
    @table_watch_loader&.close
    @table_watch_loader = nil
    receiver.games = games
    @table_watch_load_state = :ready
  end

  # Both the extension and Settings drain the same finite read. No callbacks
  # retain a form, and a pending/failed read never means an empty selection.
  def table_watch_preferences_snapshot
    receiver = table_watch_receiver
    if @table_watch_loader && (result = @table_watch_loader.take)
      games, error = result
      receiver.games = games unless error
      @table_watch_load_state = error ? :unavailable : :ready
      # One attempt per startup, not a background preference poll. Opening
      # Settings retries explicitly; no failed read can overwrite the server.
      Log.warning("Game Room watched games could not be loaded: #{error.class}") if error && defined?(Log)
    end
    state = @table_watch_load_state || (receiver.games == nil ? :loading : :ready)
    { state: state, games: state == :ready ? receiver.games.to_a.dup : nil }
  end

  def table_watch_tick
    receiver = table_watch_receiver
    table_watch_start
    @table_watch_sender&.tick
    @table_watch_receipt_writer&.tick
    if (!GameRoomClock.server_available? || GameRoomClock.synchronized?) && defined?(EltenAPI::NotificationService) && EltenAPI::NotificationService.respond_to?(:active_notifications)
      GameRoomTableWatch::Timing.measure(:list_cleanup) do
        ids = EltenAPI::NotificationService.active_notifications.filter_map do |row|
          next unless row.cat.to_s == "app" && row.app_uuid.to_s.casecmp?(server_app_uuid.to_s)
          notification = Programs.app_notification_from(row)
          next unless notification.type.to_s == GameRoomTableWatch::TYPE
          next if receiver.visible?(notification) || @table_watch_pruned[row.id.to_i]
          @table_watch_pruned[row.id.to_i] = true
          row.id.to_i
        end
        # Only this new type; never change the deferred invitation expiration.
        EltenAPI::NotificationService.revoke_active_notifications(ids) unless ids.empty?
        @table_watch_pruned = @table_watch_pruned.to_a.last(2048).to_h
      end
    end
  rescue StandardError => error
    Log.warning("Game Room table notification update failed: #{error.class}") if defined?(Log)
  end

  def table_watch_stop
    # The finite receipt writer drains its latest snapshot without a UI join.
    # Retain it for extension restarts; it owns no recurring background loop.
    @table_watch_sender&.close
    @table_watch_loader&.close
    @table_watch_sender = nil
    @table_watch_loader = nil
    @table_watch_load_state = nil
  end

  def announce_new_public_table(row)
    receiver = table_watch_receiver
    @table_watch_sender ||= begin
      client = EltenLink::Client.new
      GameRoomTableWatch::Sender.new(user: receiver.user, repository: table_watch_repository,
        variant: ->(table) { GameRoomTableVariant.payload(self::GAME_REGISTRY.build(table["game"]), table["game_options"]) },
        clock: @table_watch_clock,
        online: -> { EltenLink::Users.online(client) }, send_notice: ->(user, metadata, expires) {
          GameRoomNotifications.deliver(self, user, client: client, type: GameRoomTableWatch::TYPE,
            metadata: metadata.merge("expires_in" => expires), expires_in: expires) if expires > 0
        })
    end
    @table_watch_sender.enqueue(row)
  rescue StandardError => error
    Log.warning("Game Room new table notice could not be queued: #{error.class}") if defined?(Log)
  end

  def cancel_new_table_notice(row)
    @table_watch_sender&.cancel(row.to_h["__live_session_id"])
  end

  def table_notice_visible?(notification)
    table_watch_receiver.visible?(notification) && contact_notification_allowed?(notification) == true
  end
end
