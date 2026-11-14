class GameRoomLiveSessionStore
  # Optional public hints. The authoritative membership and game log remain
  # unchanged. Scheduling touches memory only; finite HTTP work is off the UI.
  module Discovery
    def note_realtime_activity(table_id, session_id)
      return false unless GameRoomClock.synchronized?
      native = active_session(table_id)
      return false unless native
      latest = records_for(table_id).reverse.find { |record| record.packet['kind'] == 'game_started' }
      return false unless latest&.packet&.dig('data', 'session_id') == session_id
      @mutex.synchronize { @realtime_activity[table_id] = [native, session_id, GameRoomClock.now.to_i] }
      queue_discovery_publication(table_id, activity_only: true)
      true
    end

    def discovered_roster(table)
      item, metadata, status = refreshed_discovery(table)
      return {status: status} unless status == :ready
      return {status: :unavailable} if item.respond_to?(:hide_participants?) && item.hide_participants?
      discovery_participants(table, item, metadata)
    end

    def discovered_options(table)
      _item, metadata, status = refreshed_discovery(table)
      return {status: status} unless status == :ready
      options = discovery_options(metadata)
      return {status: :unavailable} if options.empty? || !GameRoomOptionValues.normalizable_options?(JSON.parse(options))
      {status: :ready, game: metadata['game'], options: options}
    rescue JSON::ParserError, ArgumentError, Zlib::Error
      {status: :unavailable}
    end

    private

    def refreshed_discovery(table)
      item = table.to_h['__discovered_session']
      return [nil, nil, :unavailable] unless item&.respond_to?(:refresh)
      begin
        item.refresh(timeout: 5)
      rescue StandardError => error
        # A Join list can outlive the server-issued discovery token. Renew
        # only this explicit read, once, through public discovery; never join
        # or turn arbitrary permission/network failures into retries.
        raise unless GameRoomNetworkErrors.expected?(error) && error.respond_to?(:code) &&
          error.code.to_s == 'apps.live_sessions.discovery_expired'
        item = discover_pages(sources: [:public]).find { |candidate| candidate.id.to_s == table['__live_session_id'].to_s }
        return [nil, nil, :closed] unless item
        item.refresh(timeout: 5)
      end
      return [nil, nil, :closed] if item.state.to_s == 'closed'
      return [nil, nil, :unavailable] unless item.state.to_s == 'open' && item.visibility.to_s == 'public'
      metadata = item.discovery_metadata
      return [nil, nil, :unavailable] unless supported_metadata?(metadata) &&
        metadata['table_id'].to_i == table_identifier(table) && item.id.to_s == table['__live_session_id'].to_s
      [item, metadata, :ready]
    end

    def discovery_participants(table, item, metadata)
      members = item.respond_to?(:participants) ? item.participants : nil
      roster = metadata['roster']
      return {status: :unavailable} unless members.is_a?(Array) && roster.is_a?(Array) && roster.length == 3 &&
        roster[0] == 1 && roster[1].is_a?(Array) && roster[2].is_a?(Array)
      roles = roster[1]
      return {status: :unavailable} unless roles.length == members.length &&
        roles.all? { |entry| entry.is_a?(Array) && entry.length == 2 && entry[0].is_a?(String) && [0, 1].include?(entry[1]) } &&
        roles.map(&:first).uniq.length == roles.length
      users = {}
      members.each do |person|
        return {status: :unavailable} unless person.is_a?(Hash) && person['id'] && person['user'].is_a?(String) && !person['user'].empty?
        users[person['id'].to_s] = person['user']
      end
      return {status: :unavailable} unless roles.map(&:first).sort == users.keys.sort && users.values.map(&:downcase).uniq.length == users.length
      bots = roster[2]
      return {status: :unavailable} unless bots.length == metadata['bot_count'].to_i && bots.length <= MAX_CAPACITY &&
        bots.all? { |entry| entry.is_a?(Array) && entry.length == 2 && entry[0].is_a?(Integer) && entry[0].positive? && (entry[1] == nil || GameRoomBotNames.name_for(entry[1]) != nil) } &&
        bots.map(&:first).uniq.length == bots.length
      players = roles.select { |_, role| role == 0 }.map { |id, _| users[id] }
      bots.each { |number, name| players << GameRoomParticipants.bot_id(table_identifier(table), number, name_token: name) }
      {status: :ready, players: players, observers: roles.select { |_, role| role == 1 }.map { |id, _| users[id] }}
    end

    def activity_record?(record)
      kind, data = record.packet.values_at('kind', 'data')
      %w[game_started game_action].include?(kind) || (kind == 'room_activity' && data['activity_kind'] == 'chat')
    end

    def queue_discovery_publication(table_id, delay: 0, activity_only: false)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @mutex.synchronize do
        native = @sessions[table_id]
        return unless native && native.owner? && !native.closed?
        at = now + delay
        at = [at, @activity_publish_at.fetch(table_id, 0)].max if activity_only
        previous = @discovery_due[table_id]
        at = [at, previous[1]].min if previous && previous[0].equal?(native)
        @discovery_due[table_id] = [native, at]
      end
    end

    def dispatch_discovery_publication
      return unless @discovery_work_lock.try_lock
      begin
        @discovery_work.take
        return if @discovery_work.busy? || @discovery_work.closed?
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        job = @mutex.synchronize do
          @discovery_due.delete_if { |id, (native, _)| !@sessions[id].equal?(native) || native.closed? || !native.owner? }
          found = @discovery_due.find { |_, (_, at)| at <= now }
          @discovery_due.delete(found[0]) if found
          found
        end
        return unless job
        id, (native, _) = job
        unless GameRoomBackground.admit(@discovery_work) { publish_discovery(id, expected_session: native) }
          queue_discovery_publication(id)
        end
      ensure
        @discovery_work_lock.unlock
      end
    end

    def discovery_roster(table_id, native, row)
      return nil if row['private'] || (native.respond_to?(:hide_participants?) && native.hide_participants?)
      members = native.participants.to_a
      latest = records_for(table_id).reverse.find { |record| record.packet['kind'] == 'game_started' }
      if row['status'] == 'playing' && latest
        playing = game_session_from(latest)&.fetch('__players', nil)
        return nil unless playing
        bots = playing.select { |person| GameRoomParticipants.bot?(person) }
        roles = members.map { |person| [person.id.to_s, GameRoomParticipants.includes?(playing, person.user) ? 0 : 1] }
      else
        observers = observer_users(table_id, members: members.map(&:user))
        roles = members.map { |person| [person.id.to_s, GameRoomParticipants.includes?(observers, person.user) ? 1 : 0] }
        bots = room_bots(table_id, row)
      end
      [1, roles.sort_by(&:first), bots.map { |bot| [GameRoomParticipants.bot_number(bot), GameRoomParticipants.bot_name_token(bot)] }]
    end
  end
end
