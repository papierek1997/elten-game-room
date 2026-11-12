# encoding: UTF-8
require_relative 'typing_engine'

module GameRoomTyping
  using GameRoomLocalization::Translations
  module SurvivalRules
    # Durations of the supplied recordings, excluding codec padding.
    DURATIONS = {'easy' => 16.0, 'medium' => 10.6675, 'hard' => 6.64}.freeze
    SPEED_STEP = 1.025
    MAX_RATE = 51.0 # Bounded playback rate shared by the clock and audio.
    MAX_SPEED_WORDS = (Math.log(MAX_RATE) / Math.log(SPEED_STEP)).ceil

    def self.rate(correct_words)
      # Bound the exponent too; a corrupted score cannot overflow a Float.
      [SPEED_STEP ** correct_words.to_i.clamp(0, MAX_SPEED_WORDS), MAX_RATE].min
    end
  end

  # The clock is authoritative even with muted audio or a covered game form.
  # One expired recording costs one error, never a burst of per-key timeouts.
  class SurvivalStream < WordStream
    attr_reader :difficulty, :recording_seconds

    def initialize(difficulty:, recording_seconds: nil, **arguments)
      @difficulty = difficulty.to_s
      @recording_seconds = (recording_seconds || SurvivalRules::DURATIONS.fetch(@difficulty)).to_f
      raise ArgumentError, 'invalid recording duration' unless @recording_seconds.finite? && @recording_seconds > 0
      @word_deadline = nil
      super(**arguments, variant: 'words', key_interval: nil)
    end

    def playback_rate; SurvivalRules.rate(@correct_words); end
    def deadline; @word_deadline; end

    def prompt_finished(at: @clock.call)
      return if finished? || @ready
      super
      @word_deadline = at.to_f + (@resume_word_seconds || @recording_seconds / playback_rate)
      @resume_word_seconds = nil
    end

    def restore_snapshot(data, **arguments)
      if data['recording_seconds'] && (data['recording_seconds'] - @recording_seconds).abs > 0.002
        raise ArgumentError, _('The survival recording has changed.')
      end
      super
      @word_deadline = nil
      @resume_word_seconds = data['remaining']
    end

    def playback_position
      @resume_word_seconds ? [@recording_seconds - @resume_word_seconds * playback_rate, 0].max : 0.0
    end

    def snapshot(**arguments)
      super.merge('recording_seconds' => @recording_seconds)
    end

    def type(character, at: @clock.call)
      state = tick(at: at)
      return state if [:word, :finished].include?(state)
      state = super
      if state == :character && !finished? && word_complete?
        state = finish_word(at.to_f)
      end
      @word_deadline = nil if [:word, :finished].include?(state)
      state
    end

    # Help never extends the music-based deadline in survival.
    def help_started(**_arguments); end
    def help_finished(**_arguments); end

    def tick(at: @clock.call)
      return :finished if finished?
      return :waiting unless @word_deadline && at.to_f >= @word_deadline
      expired_at = @word_deadline
      @word_deadline = nil
      add_error(expired_at)
      @typed_words += 1
      @buffer = +''
      return :finished if finished?
      finish_typing_segment(expired_at)
      @active_seconds += [expired_at - @segment_start, 0].max
      @ready = false
      add_word
      :word
    end

    def result
      super&.merge('variant' => 'survival', 'difficulty' => @difficulty)
    end
  end
end
