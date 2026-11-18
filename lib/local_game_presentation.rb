require 'digest'
require_relative 'game_snapshot'
require_relative 'local_name_presentation'
require_relative 'game_replay_cache'

class GameRoomLocalGamePresentation
  attr_reader :game, :names

  def initialize(source, names)
    @source = source
    @names = names
    @game = source.build_presentation_game
    @game = source.build_session_game if @game.equal?(source)
    @game.receiver_name_presentation = names
    @game.define_singleton_method(:local_client) { source.local_client } if source.respond_to?(:local_client)
  end

  def replay(session, events, repository, boundary: nil)
    if boundary
      session = boundary.presentation_session || session
      events = boundary.presentation_events || events
      events = events.take(boundary.presentation_event_count) if boundary.presentation_event_count
      last_id = boundary.accepted_events.map { |event| repository.event_id(event) }.max.to_i
      full = @source.replay(session, events, repository)
      unless equivalent?(full, boundary)
        events = events.take_while { |event| repository.event_id(event) <= last_id }
        full = @source.replay(session, events, repository)
        raise ArgumentError, 'Presentation boundary does not match authenticated input' unless equivalent?(full, boundary)
      end
    end
    input = GameRoomReplayCache::Input.new(session, events, repository)
    authority = repository.replay_authentication_identity if repository.respond_to?(:replay_authentication_identity)
    resource = repository.replay_resource_identity(session) if repository.respond_to?(:replay_resource_identity)
    identity = [authority, resource, GameRoomLocalization.cache_token]
    signature = Digest::SHA256.digest(Marshal.dump([input.session, input.players, input.signature,
      names.token]))
    if @signature != signature || @identity != identity
      projected = @game.replay(session, events, repository)
      raise ArgumentError, 'Presentation changed accepted events' if boundary && projected.accepted_events != boundary.accepted_events
      encoded = GameRoomSnapshot.capture(projected)
      @projected, @signature = encoded.bytesize <= GameRoomReplayCache::MAX_BYTES ? [encoded, signature] : [nil, nil]
      @identity = identity
    end
    result = @projected ? @projected.restore : projected
    if boundary
      turns = boundary.history.select { |entry| entry.kind == :turn }
      turns.each do |entry|
        next unless entry.field
        formatted = @game.turn_history_entry(entry.actor, entry.field, event_id: entry.event_id)
        index = result.history.rindex { |item| item.event_id.to_i <= entry.event_id.to_i }
        result.history.insert(index ? index + 1 : 0, formatted)
      end
    end
    result
  end

  private def equivalent?(left, right)
    keys = %i[accepted_events board players current_player winner draw state]
    keys.all? { |key| same_value?(left.public_send(key), right.public_send(key)) }
  end

  private def same_value?(left, right, seen = {})
    return true if left.equal?(right)
    arrays = left.is_a?(Array) && right.is_a?(Array)
    return false unless arrays || left.class == right.class
    return left == right if [String, Numeric, Symbol, NilClass, TrueClass, FalseClass].any? { |type| left.is_a?(type) }
    pair = [left.object_id, right.object_id]
    return true if seen[pair]
    seen[pair] = true
    case left
    when Array
      left.length == right.length && left.each_index.all? { |index| same_value?(left[index], right[index], seen) }
    when Hash
      left.size == right.size && left.compare_by_identity? == right.compare_by_identity? && left.default_proc == right.default_proc &&
        same_value?(left.default, right.default, seen) &&
        left.all? { |key, value| right.key?(key) && same_value?(value, right.fetch(key), seen) }
    when Struct, Data
      left.members == right.members && left.members.all? { |key| same_value?(left.public_send(key), right.public_send(key), seen) }
    else
      variables = left.instance_variables.sort
      return left == right || Marshal.dump(left) == Marshal.dump(right) if variables.empty?
      variables == right.instance_variables.sort && variables.all? do |key|
        same_value?(left.instance_variable_get(key), right.instance_variable_get(key), seen)
      end
    end
  end
end
