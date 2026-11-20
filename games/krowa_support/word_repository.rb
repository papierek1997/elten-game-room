# encoding: UTF-8

require_relative "normalizer"
require_relative "noun_data"
require_relative "word_length"
require "digest"

module GameRoomKrowa
  class WordRepository
    attr_reader :lengths, :size, :words

    def self.default
      new(NounData::WORDS.each_line, retired: NounData::RETIRED_WORDS.each_line)
    end

    def initialize(lines, retired: [])
      @words_by_length = Hash.new { |hash, length| hash[length] = [] }
      @word_set = {}
      @word_indexes = {}
      @all_words = []

      lines.each do |line|
        word = Normalizer.call(line)
        next if word.empty? || !WordLength.valid?(word)

        @word_set[word] = true
        @word_indexes[word] ||= @all_words.length
        @all_words << word
        @words_by_length[word.length] << word
      end

      @all_words.freeze
      @words = @all_words
      @words_by_length.each_value(&:freeze)
      @lengths = @words_by_length.keys.sort.freeze
      @size = @all_words.size
      @word_set.freeze
      @word_indexes.freeze
      @words_by_length.freeze
      @retired = retired.to_h { |word| [Normalizer.call(word), true] }.freeze

      raise ArgumentError, "The noun repository is empty" if @size == 0
    end

    def include?(word)
      @word_set.key?(Normalizer.call(word))
    end

    def historical?(word)
      normalized = Normalizer.call(word)
      @word_set.key?(normalized) || @retired.key?(normalized)
    end

    def words_of_length(length)
      @words_by_length.fetch(length.to_i, EMPTY_WORDS)
    end

    def index_of(word)
      @word_indexes[Normalizer.call(word)]
    end

    # Stable identity, independent of array positions and duplicate entries.
    def id_of(word)
      normalized = Normalizer.call(word)
      Digest::SHA256.hexdigest("krowa-word-v1|#{normalized}") if @word_set.key?(normalized)
    end

    def word_at(index)
      numeric = Integer(index, exception: false)
      return nil if numeric.nil? || numeric.negative?

      @all_words[numeric]
    end

    EMPTY_WORDS = [].freeze
    private_constant :EMPTY_WORDS
  end
end
