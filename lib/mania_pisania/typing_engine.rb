# encoding: UTF-8
require_relative 'text'
require 'digest'

# The typing rules do not depend on ELTEN controls or the network. A client may
# feed one character at a time and publish a result only at the end of a round.
module GameRoomTyping
  using GameRoomLocalization::Translations
  class WordStream
    MAX_ERRORS = 5
    KEY_INTERVAL = 5.0

    attr_reader :variant, :errors, :correct_words, :typed_words, :levels, :started_at,
      :finished_at, :sequence, :word_index, :buffer

    def initialize(variant:, word_source:, seed:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
      expected_transform: ->(word, _index) { word }, max_errors: MAX_ERRORS, key_interval: KEY_INTERVAL)
      raise ArgumentError, 'unknown variant' unless %w[words memory].include?(variant.to_s)

      @variant = variant.to_s
      @word_source, @seed, @clock, @expected_transform = word_source, seed.to_i, clock, expected_transform
      @max_errors = max_errors.to_i
      @key_interval = key_interval == nil ? nil : key_interval.to_f
      raise ArgumentError, 'invalid error limit' unless @max_errors.positive?
      raise ArgumentError, 'invalid key interval' if @key_interval && !@key_interval.positive?

      @errors = @correct_words = @typed_words = @levels = @word_index = 0
      @buffer = +''
      @sequence = []
      @next_word = 0
      @started_at = @finished_at = @deadline = @first_key_at = nil
      @ready = false
      @active_seconds = 0.0
      @typing_seconds = 0.0
      add_word
    end

    def current_word
      @variant == 'memory' ? @sequence.fetch(@word_index) : @sequence.last
    end

    def current_expected
      current_expectations.first
    end

    def current_expectations
      index = @variant == 'memory' ? @word_index : @next_word - 1
      key = [index, current_word]
      if @expected_key != key
        @expected = Array(@expected_transform.call(current_word, index)).map(&:to_s).uniq
        @expected_key = key
      end
      @expected
    end

    def reset_expected
      @expected_key = nil
    end

    def word_complete?; current_expectations.include?(@buffer); end

    def deadline; @deadline; end
    def finished?; @finished_at != nil; end
    def wpm
      seconds = @typing_seconds
      seconds += [@clock.call.to_f - @first_key_at, 0.0].max if @first_key_at && !finished?
      seconds.positive? ? (@correct_words * 60.0 / seconds).round(1) : 0.0
    end

    # Called only after the prompt has finished speaking. Before that, speech
    # latency must not consume the player's input window.
    def prompt_finished(at: @clock.call)
      return if finished?

      @started_at ||= at.to_f
      @ready = true
      @segment_start = at.to_f
      @deadline = @key_interval && at.to_f + (@resume_remaining || @key_interval)
      @resume_remaining = nil
    end

    def type(character, at: @clock.call)
      return :finished if finished?
      return :not_ready unless @ready && !@help_paused

      tick(at: at)
      return :finished if finished?

      value = character.to_s
      return :ignored if value == "\b" || value == "\u007f"
      return :invalid if value.each_char.count != 1

      if value == ' '
        if word_complete?
          finish_word(at.to_f)
        else
          :ignored
        end
      elsif value.match?(/\s/)
        :ignored
      else
        @first_key_at ||= at.to_f
        position = @buffer.each_char.count
        spelling = current_expectations.find do |candidate|
          candidate.start_with?(@buffer) && (next_character = candidate.each_char.to_a[position]) &&
            KeyboardText.equivalent?(value, next_character)
        end
        expected = spelling && spelling.each_char.to_a[position]
        if expected
          @buffer << expected
        else
          # A wrong press costs an error, not a letter. Keep the cursor on
          # the character the player still needs to enter.
          add_error(at.to_f)
        end
        @deadline = at.to_f + @key_interval if @key_interval && !finished?
        finished? ? :finished : :character
      end
    end

    def tick(at: @clock.call)
      return :finished if finished?
      return :waiting if @deadline == nil

      now = at.to_f
      while !finished? && now >= @deadline
        missed_at = @deadline
        add_error(missed_at)
        @deadline = missed_at + @key_interval unless finished?
      end
      finished? ? :finished : :waiting
    end

    def result
      return nil unless finished?

      { 'variant' => @variant, 'words' => @correct_words, 'typed_words' => @typed_words,
        'levels' => @levels, 'errors' => @errors,
        'elapsed_ms' => [(@active_seconds * 1000).round, 0].max, 'wpm' => wpm }
    end

    def snapshot(at: @clock.call)
      active = @active_seconds + (@ready && @segment_start ? [at.to_f - @segment_start, 0].max : 0)
      typing = @typing_seconds + (@first_key_at ? [at.to_f - @first_key_at, 0].max : 0)
      {'errors' => @errors, 'correct_words' => @correct_words, 'typed_words' => @typed_words,
        'levels' => @levels, 'next_word' => @next_word, 'word_index' => @word_index,
        'active_seconds' => active, 'typing_seconds' => typing, 'ready' => @ready,
        'word' => current_word, 'sequence_digest' => Digest::SHA256.hexdigest(@sequence.join("\0")),
        'remaining' => deadline && [deadline - at.to_f, 0].max}
    end

    def restore_snapshot(data, buffer:, at: @clock.call)
      @next_word = data.fetch('next_word')
      indices = @variant == 'memory' ? (0...@next_word).to_a : [@next_word - 1]
      @sequence = indices.map { |index| @word_source.call(@seed, index).to_s }
      @word_index = data.fetch('word_index')
      unless current_word == data.fetch('word') && Digest::SHA256.hexdigest(@sequence.join("\0")) == data.fetch('sequence_digest')
        raise ArgumentError, _('The word bank has changed; this game cannot be resumed.')
      end
      @buffer = buffer.dup
      raise ArgumentError, _('Invalid saved word prefix') unless current_expectations.any? { |candidate| candidate.start_with?(@buffer) }
      @errors, @correct_words, @typed_words, @levels = data.values_at('errors', 'correct_words', 'typed_words', 'levels')
      @active_seconds, @typing_seconds = data.values_at('active_seconds', 'typing_seconds')
      @started_at = at.to_f
      @ready = @help_paused = false
      @finished_at = @deadline = @segment_start = @first_key_at = nil
      @resume_remaining = data['remaining']
    end

    def help_started(at: @clock.call)
      return if finished? || !@ready || @help_paused
      @deadline = nil
      finish_typing_segment(at.to_f)
      @active_seconds += [at.to_f - @segment_start, 0.0].max if @segment_start
      @segment_start = nil
      @help_paused = true
    end

    def help_finished(at: @clock.call)
      return unless @help_paused
      @help_paused = false
      @segment_start = at.to_f unless finished?
      @deadline = at.to_f + @key_interval if @key_interval && !finished? && @ready
    end

    def stop(at: @clock.call)
      return if finished?
      @active_seconds += [at.to_f - @segment_start, 0.0].max if @ready && @segment_start
      finish_typing_segment(at.to_f)
      @finished_at = at.to_f
    end

    private

    def add_word
      word = @word_source.call(@seed, @next_word).to_s
      raise ArgumentError, 'word source returned an empty or spaced word' if word.empty? || word.match?(/\s/)

      @variant == 'words' ? @sequence = [word] : @sequence << word
      @next_word += 1
    end

    def add_error(at)
      @errors += 1
      stop(at: at) if @errors >= @max_errors
    end

    def finish_word(at)
      return :ignored if @buffer.empty?

      @typed_words += 1
      @correct_words += 1 if word_complete?
      @buffer = +''
      finish_typing_segment(at)
      return :finished if finished?

      @active_seconds += [at - @segment_start, 0.0].max if @segment_start
      @ready = false

      if @variant == 'words'
        add_word
      else
        @word_index += 1
        if @word_index >= @sequence.length
          @levels += 1
          add_word
          @word_index = 0
        end
      end
      @deadline = nil # The next spoken prompt must finish first.
      :word
    end

    def finish_typing_segment(at)
      @typing_seconds += [at - @first_key_at, 0.0].max if @first_key_at
      @first_key_at = nil
    end
  end

  class FreeText
    attr_reader :sentences, :position, :correct_words, :mistakes, :active_seconds, :document

    def initialize(text, position: 0, correct_words: 0, mistakes: 0, active_seconds: 0.0)
      @document = Document.new(text)
      @sentences = @document.sentences
      @words = @document.tokens.map(&:text)

      @position = [[position.to_i, 0].max, @words.length].min
      @correct_words, @mistakes = correct_words.to_i, mistakes.to_i
      @active_seconds = active_seconds.to_f
    end

    def current_word; @words[@position]; end
    def finished?; @position >= @words.length; end
    def progress; ((@position.to_f / @words.length) * 100).round(1); end
    def wpm; @active_seconds.positive? ? (@correct_words * 60.0 / @active_seconds).round(1) : 0.0; end

    def current_sentence
      token = @document.tokens[@position]
      token && @sentences[token.sentence]
    end

    def sentence_start?; !!@document.tokens[@position]&.sentence_start; end

    def remaining_sentence
      token = @document.tokens[@position]
      return nil unless token
      @document.tokens.drop(@position).take_while { |item| item.sentence == token.sentence }.map(&:text).join(' ')
    end

    def submit(word, braille_expected: nil, first_key_at:, space_at:, prior_seconds: 0)
      return :finished if finished?

      expected = current_word
      if braille_expected ? Array(braille_expected).include?(word) : KeyboardText.equivalent?(word, expected)
        @correct_words += 1
      else
        @mistakes += 1
      end
      @active_seconds += [space_at.to_f - first_key_at.to_f, 0.0].max + prior_seconds
      @position += 1
      finished? ? :finished : :word
    end

    def snapshot
      { 'position' => @position, 'correct_words' => @correct_words,
        'mistakes' => @mistakes, 'active_seconds' => @active_seconds }
    end

    def restore_snapshot(data)
      position = data.fetch('position')
      raise ArgumentError, _('Invalid saved text position') unless position.between?(0, @words.length)
      @position, @correct_words, @mistakes, @active_seconds = data.values_at('position', 'correct_words', 'mistakes', 'active_seconds')
    end
  end
end
