require 'json'

# The legacy action dialect measures characters, not bytes. Keep its limits
# distinct from native stack byte limits and private payload codecs.
module GameRoomEventProtocol
  MAX_EVENTS = 50
  MAX_ACTION_LENGTH = 32
  MAX_VALUE_LENGTH = 64
  NATIVE_PACKET_VERSION = 2
  # Saved moves have no native proof or projection metadata. Both file and
  # independently authenticated stack imports enforce this same boundary.
  ARCHIVE_EVENT_FIELDS = %w[id sequence actor action value created_at game_time].freeze
  module_function

  def command_value(command, key)
    return command.public_send(key) if command.respond_to?(key)
    return nil if !command.respond_to?(:key?)
    return command[key] if command.key?(key)
    return command[key.to_sym] if command.key?(key.to_sym)
    nil
  end

  def normalized(command)
    { 'action' => command_value(command, 'action').to_s, 'value' => command_value(command, 'value').to_s }
  end

  # The native stack limit applies to this entire JSON object, including the
  # authenticated-action metadata and per-command UUIDs, not just its values.
  # This pure builder is shared by Writer and preflight; it performs no I/O.
  def record_packet(kind:, actor:, data:)
    {'version' => NATIVE_PACKET_VERSION, 'kind' => kind.to_s, 'actor' => actor.to_s,
      'data' => JSON.parse(JSON.generate(data))}
  end

  def game_action_packet(session_id:, sequence:, control_epoch:, events:, actor:, controller: false)
    record_packet(kind: 'game_action', actor: actor, data: {
      'session_id' => session_id, 'sequence' => sequence.to_i,
      'controller' => controller == true, 'control_epoch' => control_epoch, 'events' => events
    })
  end

  def validate_commands!(commands)
    if commands.empty? || commands.length > MAX_EVENTS
      raise ArgumentError, 'The game action contains an invalid number of events'
    end
    commands.each do |command|
      action = command_value(command, 'action').to_s
      value = command_value(command, 'value').to_s
      raise ArgumentError, 'A game event requires an action' if action.empty?
      raise ArgumentError, 'The game event action is too long' if action.length > MAX_ACTION_LENGTH
      raise ArgumentError, 'The game event value is too long' if value.length > MAX_VALUE_LENGTH
    end
    commands
  end

  # Incoming wire values are checked independently; do not coerce malformed
  # remote values using the local command adapter.
  def valid_wire_command?(command, move_id: false)
    command.is_a?(Hash) && command['action'].is_a?(String) &&
      command['action'].length.between?(1, MAX_ACTION_LENGTH) &&
      command['value'].is_a?(String) && command['value'].length <= MAX_VALUE_LENGTH &&
      (!move_id || (command['move_id'].is_a?(String) && !command['move_id'].empty?))
  end

  def valid_wire_commands?(commands)
    commands.is_a?(Array) && commands.length.between?(1, MAX_EVENTS) &&
      commands.all? { |command| valid_wire_command?(command, move_id: true) }
  end
end
