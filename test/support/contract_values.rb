require 'digest'
require 'json'

module GameRoomTest
  module ContractValues
    module_function

    # Keep key/value types, ordering and all Replay fields. Marshal bytes encode
    # object sharing as well as values, so they are unsuitable as golden values.
    def canonical(value)
      case value
      when Hash then ['hash', value.map { |key, item| [canonical(key), canonical(item)] }]
      when Random then ['Random', Marshal.dump(value).unpack1('H*')]
      when Data then [value.class.name, canonical(value.to_h)]
      when Struct
        fields = value.each_pair.map do |key, item|
          # These two legacy presenters use Ruby's process-randomized String
          # hash in UI identity. Check its derivation, not a different process's
          # hash salt. The complete text, kind and event ID remain in the value.
          if value.class.name == 'GameRoomGames::HistoryEntry' && key == :key &&
              item == "#{value.kind}:#{value.event_id}:#{value.text.hash}"
            item = "#{value.kind}:#{value.event_id}:sha256:#{Digest::SHA256.hexdigest(value.text)}"
          end
          [key.to_s, canonical(item)]
        end
        [value.class.name, fields]
      when Array then value.map { |item| canonical(item) }
      when Symbol then ['symbol', value.to_s]
      when String then value.dup.force_encoding(Encoding::UTF_8)
      when Numeric, TrueClass, FalseClass, NilClass then value
      else
        # Mahjong uses value objects for ownership/round state. Marshal-based
        # owned snapshots need not retain frozen flags; compare every field.
        if value.class.name == 'GameRoomGames::FiveDiceMatch' || value.class.name&.start_with?('GameRoomMahjong::')
          [value.class.name, value.instance_variables.sort.map { |key| [key.to_s, canonical(value.instance_variable_get(key))] }]
        else
          raise TypeError, "Unsupported contract value: #{value.class}"
        end
      end
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
    end
  end
end
