# encoding: UTF-8
require_relative '../game_content'

module GameRoomTyping
  class UnsupportedCharacters < ArgumentError
    attr_reader :characters

    def initialize(characters)
      @characters = characters.freeze
      super("Unsupported typing characters: #{characters.map { |c| 'U+%04X' % c.ord }.join(', ')}")
    end
  end

  module KeyboardText
    # Deliberately limited to typography. Polish diacritics and meaningful
    # punctuation are preserved. Unknown symbols are reported, never dropped.
    REPLACEMENTS = {
      "\u2018" => "'", "\u2019" => "'", "\u201a" => "'", "\u201b" => "'",
      "\u2039" => "'", "\u203a" => "'", "\u02bc" => "'", "\u2032" => "'",
      "\u201c" => '"', "\u201d" => '"', "\u201e" => '"', "\u201f" => '"',
      "\u00ab" => '"', "\u00bb" => '"', "\u2033" => '"',
      "\u2026" => '...', "\u22ef" => '...', "\u2212" => '-',
      "\u00d7" => '*', "\u00f7" => '/', "\u2044" => '/', "\u2215" => '/',
      "\u2022" => '-', "\u2023" => '-', "\u2043" => '-',
      "\u00bd" => '1/2', "\u00bc" => '1/4', "\u00be" => '3/4',
      "\ufb00" => 'ff', "\ufb01" => 'fi', "\ufb02" => 'fl',
      "\ufb03" => 'ffi', "\ufb04" => 'ffl',
      "\u00ad" => '', "\u200b" => '', "\u2060" => '', "\ufeff" => ''
    }.freeze
    BASIC = /\A[\x20-\x7e\p{Latin}\p{Cyrillic}¡¿\s]*\z/

    def self.normalize(value)
      text = GameRoomContent.utf8(value)
      text = UnicodeNormalize.normalize(text, :nfc)
      text.each_char.map do |character|
        if REPLACEMENTS.key?(character)
          REPLACEMENTS.fetch(character)
        elsif character.match?(/\p{Pd}/)
          '-'
        elsif character.match?(/\p{Zs}/)
          ' '
        elsif character.ord.between?(0xff01, 0xff5e)
          (character.ord - 0xfee0).chr
        else
          character
        end
      end.join.gsub(/\r\n?/, "\n")
    end

    def self.unsupported(value)
      normalize(value).each_char.reject { |character| BASIC.match?(character) }.uniq
    end

    def self.equivalent?(actual, expected)
      normalize(actual).downcase == normalize(expected).downcase
    end
  end

  class Document
    Token = Struct.new(:text, :sentence, :sentence_start, keyword_init: true)
    attr_reader :text, :tokens, :sentences
    ABBREVIATIONS = %w[np. itp. itd. tj. tzn. dr. prof. ul. godz. nr. ok.].freeze

    def initialize(text)
      @text = KeyboardText.normalize(text).strip.freeze
      invalid = KeyboardText.unsupported(@text)
      raise UnsupportedCharacters, invalid unless invalid.empty?
      raise ArgumentError, 'text has no words' if @text.empty?

      @tokens, @sentences = [], []
      current = []
      @text.split(/\s+/).each do |word|
        @tokens << Token.new(text: word.freeze, sentence: @sentences.length,
          sentence_start: current.empty?).freeze
        current << word
        if sentence_end?(word)
          @sentences << current.join(' ').freeze
          current = []
        end
      end
      @sentences << current.join(' ').freeze unless current.empty?
      @tokens.freeze
      @sentences.freeze
    end

    private

    def sentence_end?(word)
      clean = word.sub(/["')\]]+\z/, '')
      clean.match?(/[.!?]\z/) && !ABBREVIATIONS.include?(clean.downcase) && !clean.match?(/\A[A-ZĄĆĘŁŃÓŚŹŻ]\.\z/)
    end
  end
end
