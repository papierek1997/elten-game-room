require 'json'
require 'base64'
require_relative 'result'

module GameRoomDartsRankings
  # Keep the deployed 4096-byte string columns. Version two retains the
  # same records using fixed tuples and lossless 32-byte result keys, not fewer
  # difficulties, truncated histories or a larger unsupported column type.
  module RecordCodec
    class Invalid < StandardError; end
    Document = Data.define(:records, :unlocked_level)
    FIELDS = {
      'triple'=>%w[key played_at score time_ms].freeze,
      'average'=>%w[key played_at total_score throw_count total_time_ms].freeze
    }.freeze
    module_function

    def encode(records, unlocked_level: nil)
      compact = records.transform_values do |scope|
        scope.to_h do |category, entries|
          fields = FIELDS.fetch(category)
          [category, entries.map do |entry|
            key = entry.fetch('key')
            raise Invalid, 'Invalid Darts result key' unless /\A[0-9a-f]{64}\z/.match?(key.to_s)
            [Base64.urlsafe_encode64([key].pack('H*'), padding:false), *fields.drop(1).map { |field| entry.fetch(field) }]
          end]
        end
      end
      document = {'r'=>compact}
      document['u'] = unlocked_level unless unlocked_level.nil?
      JSON.generate(document)
    end

    def decode(bytes, version:)
      decode_document(bytes, version:version).records
    end

    def decode_document(bytes, version:)
      value = JSON.parse(bytes, max_nesting:7, create_additions:false)
      return Document.new(value, nil) if version == 1
      raise Invalid, 'Invalid Darts records version' unless version == 2
      unless value.is_a?(Hash) && value.key?('r') && (value.keys - %w[r u]).empty? && value['r'].is_a?(Hash)
        raise Invalid, 'Invalid compact Darts records'
      end
      if value.key?('u') && !(value['u'].is_a?(Integer) && value['u'].between?(2, 5))
        raise Invalid, 'Invalid compact Darts progression'
      end
      records = value['r'].transform_values do |scope|
        raise Invalid, 'Invalid compact Darts scope' unless scope.is_a?(Hash)
        scope.to_h do |category, tuples|
          fields = FIELDS[category]
          raise Invalid, 'Invalid compact Darts category' unless fields && tuples.is_a?(Array)
          [category, tuples.map do |tuple|
            raise Invalid, 'Invalid compact Darts entry' unless tuple.is_a?(Array) && tuple.length == fields.length
            key = tuple.first
            raise Invalid, 'Invalid compact Darts key' unless key.is_a?(String) && /\A[A-Za-z0-9_-]{43}\z/.match?(key)
            binary = Base64.urlsafe_decode64(key)
            unless binary.bytesize == 32 && Base64.urlsafe_encode64(binary, padding:false) == key
              raise Invalid, 'Noncanonical compact Darts key'
            end
            fields.zip([binary.unpack1('H*'), *tuple.drop(1)]).to_h
          end]
        end
      end
      Document.new(records, value['u'])
    rescue ArgumentError => error
      raise Invalid, error.message
    end
  end
end
