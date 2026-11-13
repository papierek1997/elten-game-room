# encoding: UTF-8

class GameRoomLiveSessionStore
  # Names are room presentation metadata. These records never enter a game's
  # actor, seat, move revision, statistics or authorization projection.
  def publish_display_name
    start
    results = []
    active_table_ids.each do |table_id|
      native = active_session(table_id)
      next unless native && !native.closed?
      results << publish_room_profile(table_id, native)
    end
    results.all?
  end

  private

  def publish_room_profile(table_id, native)
    account = invitation_account_identity
    return false unless account.first.sessions.any? { |session| session.equal?(native) } && invitation_account_current?(account)
    name = GameRoomParticipants.local_display_name
    previous = records_for(table_id).reverse.find do |record|
      record.packet['kind'] == 'room_profile' && same_user?(record.sender, account.last)
    end
    return true if previous && previous.packet['data']['display_name'] == name
    return true if previous.nil? && name.empty?
    record = append_record(table_id, 'room_profile', {'display_name' => name}, actor: account.last,
      write_guard: ->(current) {
        raise GameRoomNetworkErrors::GamePaused, 'The profile account changed' unless
          invitation_account_current?(account) && active_session(table_id).equal?(native) && current.equal?(native)
        true
      })
    return false unless record
    publish_discovery(table_id) if native.owner?
    true
  end

  def publish_initial_profile(table_id, native)
    publish_room_profile(table_id, native)
  rescue StandardError => error
    raise unless GameRoomNetworkErrors.expected?(error)
    # Membership already succeeded. A failed cosmetic publication cannot undo
    # that admission; native participant metadata still describes this member.
    log_warning('display name publication', table_id, error)
    false
  end

  def room_display_names(table_id, native)
    names, bytes = {}, 0
    retain = lambda do |account, name|
      key = account.downcase
      previous = names.delete(key)
      bytes -= previous.sum(&:bytesize) if previous
      names[key] = [account, name]
      bytes += account.bytesize + name.bytesize
      while names.length > GameRoomParticipantNames::MAX_NAMES || bytes > GameRoomParticipantNames::MAX_NAMES_BYTES
        _old_key, pair = names.shift
        bytes -= pair.sum(&:bytesize)
      end
    end
    native&.participants.to_a.first(MAX_CAPACITY).each do |person|
      next unless person.respond_to?(:metadata)
      value = person.metadata.to_h['display_name']
      clean = GameRoomParticipants.normalize_display_name(value)
      retain.call(person.user.to_s, clean) if clean
    end
    records_for(table_id).each do |record|
      next unless record.packet['kind'] == 'room_profile'
      retain.call(record.sender, record.packet['data']['display_name'])
    end
    values = names.values.to_h
    values.each { |account, name| GameRoomParticipants.remember_display_name(account, name, remote: true) }
    values
  end

  def discovery_display_names(metadata, members:)
    # Discovery metadata is an owner's relay, not the member's authenticated
    # profile. Keep it inside this view, bound to native membership identities.
    return {} unless members.is_a?(Array)
    names = metadata['display_names']
    names = {} unless names.is_a?(Hash) && names.length <= MAX_CAPACITY
    members.first(MAX_CAPACITY).each_with_object({}) do |person, result|
      next unless person.is_a?(Hash) && person['user'].is_a?(String)
      account = person['user']
      value = same_user?(account, metadata['owner']) ? metadata['owner_display_name'] : names[account]
      label = GameRoomParticipants.normalize_display_name(value)
      result[account.dup.freeze] = label.freeze if label
    end
  end
end
