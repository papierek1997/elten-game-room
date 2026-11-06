# encoding: UTF-8
require 'digest'
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
    MAX_PARTS = (MAX_BYTES + CHUNK_BYTES - 4) / (CHUNK_BYTES - 3)
    module_function

    def required?(options, players, owner: nil)
      others = owner && players.to_a.any? { |player| !player.to_s.casecmp?(owner.to_s) }
      options && (players.to_a.length > 1 || others) && options['variant'] == 'free' && %w[local pasted].include?(options['text'])
    end

    def parts(item)
      text = Document.new(item.fetch('text')).text
      raise ArgumentError, _('A shared text may contain at most 1000000 UTF-8 bytes.') if text.bytesize > MAX_BYTES
      chunks, buffer = [], +''
      text.each_char do |character|
        if buffer.bytesize + character.bytesize > CHUNK_BYTES
          chunks << buffer.freeze
          buffer = +''
        end
        buffer << character
      end
      chunks << buffer.freeze unless buffer.empty?
      digest = Digest::SHA256.hexdigest(text).freeze
      title = GameRoomContent.utf8(item.fetch('title')).each_char.take(150).join.freeze
      chunks.each_with_index.map do |chunk, index|
        part = {'digest' => digest, 'index' => index, 'total' => chunks.length, 'text' => chunk}
        part['title'] = title if index == 0
        part.freeze
      end.freeze
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
