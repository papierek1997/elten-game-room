require 'securerandom'
require_relative 'game_participants'

module GameRoomStatistics
  module Identity
    module_function

    def create(players:, controllers: {})
      mode = if players.any? { |player| GameRoomParticipants.bot?(player) || controllers[player] == 'bot' }
        'bots'
      else
        players.length == 1 ? 'solo' : 'humans'
      end
      copy({'id' => SecureRandom.uuid, 'mode' => mode})
    end

    def valid?(value, require_started_at: false)
      return false unless value.is_a?(Hash) && (value.keys - %w[id mode started_at]).empty?
      id = value['id']
      return false unless id.is_a?(String) && id.ascii_only? &&
        /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.match?(id)
      return false unless %w[humans bots solo].include?(value['mode'])
      return false if require_started_at && !value.key?('started_at')
      !value.key?('started_at') || (value['started_at'].is_a?(Integer) && value['started_at'].positive?)
    end

    def copy(value, started_at: nil)
      raise ArgumentError, 'Invalid statistics identity' unless valid?(value)
      result = value.each_with_object({}) do |(key, item), metadata|
        metadata[key] = item.is_a?(String) ? item.dup.freeze : item
      end
      result['started_at'] = started_at if !result.key?('started_at') && started_at != nil
      raise ArgumentError, 'Invalid statistics identity' unless valid?(result)
      result.freeze
    end
  end
end
