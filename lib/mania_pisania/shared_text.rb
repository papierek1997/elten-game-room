# encoding: UTF-8
require 'digest'
require_relative '../game_action_payload'
require_relative 'text'
require_relative 'text_library'
require_relative 'text_selection'

module GameRoomTyping
  using GameRoomLocalization::Translations
  # Bounded fragments use the existing atomic LiveSessions action writer.
  # Only a host-confirmed selection is supplied here, never the local library.
  module SharedText
    MAX_BYTES = TextLibrary::MAX_BYTES
    CHUNK_BYTES = 1000
    MAX_PARTS = 4096
    UUID_PLACEHOLDER = '00000000-0000-0000-0000-000000000000'.freeze
    # A handover can replace the initial epoch with a SHA-256 hex digest.
    EPOCH_PLACEHOLDER = ('0' * 64).freeze
    # The action sequence can grow between preparation and writing.
    MAX_SEQUENCE = (1 << 63) - 1
    module_function

    def required?(options, players, owner: nil)
      others = owner && players.to_a.any? { |player| !player.to_s.casecmp?(owner.to_s) }
      options && (players.to_a.length > 1 || others) && options['variant'] == 'free' && %w[local pasted].include?(options['text'])
    end

    def parts(item, game_id:, round:, packet:, limits:)
      packet_limit, stack_entries = limits.values_at('max_stack_entry_bytes', 'max_stack_entries')
      too_large = _('This action contains too much data and was not sent.')
      raise ArgumentError, too_large unless packet_limit.to_i.positive? && stack_entries.to_i > 1

      text = Document.new(item.fetch('text')).text
      raise ArgumentError, _('A shared text may contain at most 1000000 UTF-8 bytes.') if text.bytesize > MAX_BYTES
      chunks = split_text(text)
      digest = Digest::SHA256.hexdigest(text).freeze
      title = GameRoomContent.utf8(item.fetch('title')).each_char.take(150).join.freeze
      max_parts = [MAX_PARTS, stack_entries - 1].min # The round starts with a separate write.

      loop do
        raise ArgumentError, too_large if chunks.length > max_parts
        parts = chunks.each_with_index.map do |chunk, index|
          part = {'digest' => digest, 'index' => index, 'total' => chunks.length, 'text' => chunk}
          part['title'] = title if index == 0
          part.freeze
        end
        resized = parts.flat_map do |part|
          chunk = part.fetch('text')
          next [chunk] if packet_bytes(game_id, action_data(round, part), packet) <= packet_limit

          midpoint = chunk.length / 2
          raise ArgumentError, too_large if midpoint.zero?
          [chunk[0...midpoint].freeze, chunk[midpoint..].freeze]
        end
        return parts.freeze if resized.length == chunks.length
        chunks = resized
      end
    end

    def action_data(round, part)
      {'action' => 'text_part', 'round' => round, 'part' => part}
    end

    def packet_bytes(game_id, data, metadata)
      events = GameRoomActionPayload.commands(game_id, data).map do |event|
        GameRoomEventProtocol.normalized(event).merge('move_id' => UUID_PLACEHOLDER)
      end
      packet = GameRoomEventProtocol.game_action_packet(**metadata, sequence: MAX_SEQUENCE,
        control_epoch: EPOCH_PLACEHOLDER, controller: false, events: events)
      JSON.generate(packet).bytesize
    end

    def split_text(text)
      chunks, buffer = [], +''
      text.each_char do |character|
        if buffer.bytesize + character.bytesize > CHUNK_BYTES
          chunks << buffer.freeze
          buffer = +''
        end
        buffer << character
      end
      chunks << buffer.freeze unless buffer.empty?
      chunks
    end

    def next_index(transfer, part)
      return 0 unless transfer && transfer.values_at(:digest, :total) == part.values_at('digest', 'total')
      return 0 if part.key?('title') && transfer[:title] != part['title']

      transfer[:chunks].length
    end

    def apply(state, part)
      return false unless part.is_a?(Hash)
      digest, title, index, total, text = part.values_at('digest', 'title', 'index', 'total', 'text')
      transfer = state[:text_transfer]
      selection = TextSelection.descriptor(state[:options])
      return false if selection && (digest != selection['text_sha256'] || index == 0 && title != selection['text_title'])
      title = transfer[:title] if index.is_a?(Integer) && index > 0 && transfer
      return false unless digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/)
      return false unless title.is_a?(String) && title.valid_encoding? && title.length <= 150
      return false unless index.is_a?(Integer) && total.is_a?(Integer) && total.between?(1, MAX_PARTS) && index.between?(0, total - 1)
      return false unless text.is_a?(String) && text.valid_encoding? && !text.empty? && text.bytesize <= CHUNK_BYTES
      return false if index == 0 && transfer && transfer.values_at(:digest, :title, :total) == [digest, title, total]
      transfer = {digest: digest, title: title, total: total, chunks: []} if index == 0
      return false unless transfer && transfer.values_at(:digest, :title, :total) == [digest, title, total] && transfer[:chunks].length == index
      chunks = transfer[:chunks] + [text.dup.freeze]
      return false if chunks.sum(&:bytesize) > MAX_BYTES
      if chunks.length == total
        joined = chunks.join
        return false unless Digest::SHA256.hexdigest(joined) == digest && Document.new(joined).text == joined
        return false if selection && joined.length != selection['text_characters']
        state[:shared_text] = {'title' => title, 'text' => joined, 'id' => "shared:#{digest}"}.freeze
      end
      state[:text_transfer] = transfer.merge(chunks: chunks.freeze).freeze
      true
    rescue UnsupportedCharacters, ArgumentError
      false
    end
  end
end
