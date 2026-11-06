# encoding: UTF-8
require 'json'
require 'digest'
require_relative 'text'
require_relative 'braille_catalog'

module GameRoomTyping
  using GameRoomLocalization::Translations
  module Checkpoint
    FORMAT = 1
    MAX_BYTES = 6000
    MAX_MEMORY_WORDS = 10_000
    TABLES = (BrailleCatalog::FILES.keys + ['custom']).freeze
    module_function

    def valid?(data, variant:, seed:)
      return false unless data.is_a?(Hash) && data['format'] == FORMAT && data['variant'] == variant && data['seed'] == seed
      return false unless data['buffer'].is_a?(String) && data['buffer'].valid_encoding? && data['buffer'].length <= 4096
      return false unless [true, false].include?(data['assisted']) && [true, false].include?(data['finished'])
      return false unless number?(data['elapsed']) && number?(data['partial_seconds'])
      if data['finished']
        result = data['result']
        return false unless result.is_a?(Hash) && %w[words errors levels elapsed_ms].all? { |key|
          result[key].is_a?(Integer) && result[key].between?(0, 1_000_000_000) }
        return false unless number?(result['wpm']) && result['wpm'] <= 100_000 && result['assisted'] == data['assisted']
      else
        return false unless data['result'] == nil
      end
      engine = data['engine']
      return false unless engine.is_a?(Hash)
      counters = variant == 'free' ? %w[position correct_words mistakes] : %w[errors correct_words typed_words levels next_word word_index]
      return false unless counters.all? { |key| engine[key].is_a?(Integer) && engine[key].between?(0, 1_000_000_000) }
      return false unless number?(engine['active_seconds'])
      if variant != 'free'
        return false unless engine['errors'] <= 5 && engine['next_word'].positive? && engine['word_index'] < engine['next_word']
        return false if variant == 'memory' && engine['next_word'] > MAX_MEMORY_WORDS
        return false unless number?(engine['typing_seconds']) && (engine['remaining'] == nil || number?(engine['remaining']))
        return false unless engine['word'].is_a?(String) && engine['sequence_digest'].is_a?(String)
        return false unless engine['sequence_digest'].match?(/\A[0-9a-f]{64}\z/)
        return false unless [true, false].include?(engine['ready'])
        return false if variant == 'survival' && (!number?(engine['recording_seconds']) || engine['recording_seconds'] <= 0)
      end
      TABLES.include?(data['table']) && JSON.generate(data).bytesize <= MAX_BYTES
    rescue TypeError, JSON::GeneratorError
      false
    end

    def number?(value)
      value.is_a?(Numeric) && value.finite? && value.between?(0, 1_000_000_000)
    end

    def validate_word_source!(data, word_bank:)
      return if data['variant'] == 'free'
      engine = data.fetch('engine')
      count = engine.fetch('next_word')
      indices = data['variant'] == 'memory' ? (0...count).to_a : [count - 1]
      sequence = indices.map { |index| word_bank.call(data['seed'], index).to_s }
      word = data['variant'] == 'memory' ? sequence.fetch(engine['word_index']) : sequence.last
      unless word == engine['word'] && Digest::SHA256.hexdigest(sequence.join("\0")) == engine['sequence_digest']
        raise ArgumentError, _('The saved word bank is no longer compatible.')
      end
    end
  end
end
