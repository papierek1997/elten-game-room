# encoding: UTF-8
require 'base64'
require 'digest'
require 'zlib'
require_relative '../../content/mania_pisania_words'

module GameRoomTyping
  using GameRoomLocalization::Translations
  # The supplied word list is identical on every Game Room client.
  # Compressed blocks are sampled deterministically and inflated
  # on demand; no three-million-word Array is built during a round.
  class WordBank
    MIN_LENGTH = 3
    MAX_LENGTH = 12

    attr_reader :language

    def self.for_options(options)
      new(language: options.fetch('word_language', 'pl'))
    end

    def initialize(language: 'pl', blocks: nil, checksum: nil)
      @language = language
      data = case language
      when 'pl' then WordData
      when 'en'
        require_relative '../../content/mania_pisania_words_en'
        WordDataEN
      when 'cs'
        require_relative '../../content/mania_pisania_words_cs'
        WordDataCS
      when 'es'
        require_relative '../../content/mania_pisania_words_es'
        WordDataES
      when 'ru'
        require_relative '../../content/mania_pisania_words_ru'
        WordDataRU
      else raise ArgumentError, 'Unknown typing word language'
      end
      blocks ||= data::BLOCKS
      checksum ||= data::CHECKSUM
      @blocks, @checksum = blocks, checksum
      @cache = {}
      @mutex = Mutex.new
    end

    def word(seed, index, length: nil)
      blocks = @blocks
      32.times do |attempt|
        hash = Digest::SHA256.digest("mania-pisania:#{@checksum}:#{seed}:#{index}:#{attempt}")
        block_index = hash.unpack1('L<') % blocks.length
        candidates = words_in(block_index, blocks[block_index], length)
        next if candidates.empty?

        pick = hash.byteslice(4, 4).unpack1('L<') % candidates.length
        return candidates[pick]
      end
      raise ArgumentError, _('The word pack has no words of the requested length.')
    end

    def call(seed, index)
      word(seed, index)
    end

    private

    def words_in(index, encoded, length)
      key = [index, length]
      @mutex.synchronize do
        cached = @cache.delete(key)
        if cached == nil
          text = Zlib::Inflate.inflate(Base64.strict_decode64(encoded)).force_encoding(Encoding::UTF_8)
          raise ArgumentError, _('Invalid word block.') unless text.valid_encoding? && text.bytesize <= 131_072
          cached = text.split("\n").select do |word|
            size = word.each_char.count
            size.between?(MIN_LENGTH, MAX_LENGTH) && (length == nil || size == length.to_i) &&
              word.match?(@language == 'pl' ? /\A[a-ząćęłńóśźż]+\z/ : /\A[\p{Latin}\p{Cyrillic}]+\z/)
          end.freeze
        end
        @cache[key] = cached
        @cache.shift while @cache.length > 24
        cached
      end
    end
  end
end
