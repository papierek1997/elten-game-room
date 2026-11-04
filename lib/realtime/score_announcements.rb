# Shared recorded score sequencing only. Each game owns its sound handles,
# gain policy, effects and lifecycle; this module never reads Pong preferences
# or a paddle/flight snapshot.
require_relative '../game_background_policy'
require_relative '../game_sound_output'

module GameRoomRealtime
  module ScoreAnnouncements
    GOALS = (1..8).map { |n| "pong_goal#{n}" }.freeze
    GOAL_VOICES = (1..4).map { |n| "pong_score#{n}" }.freeze
    ANNOUNCEMENTS = (GOALS + GOAL_VOICES + ['pong_scores'] +
      (0..21).map { |n| "pong_number#{n}" } + %w[pong_goal pong_gamestart pong_youwin pong_theywin]).freeze
    ANNOUNCER_LEVEL = 0.5

    attr_reader :presents_point
    attr_accessor :background_provider

    # The owner may release a nested game's audio after its final goal, not
    # after an estimated sleep. tick retires recordings and speech deadlines.
    def announcement_pending?
      !@score_queue.empty? || !@announcing.empty? || @speech_pending == true
    end

    def recording_sound_handles
      @sounds.values.dup
    end

    def recording_seek(seconds)
      @score_queue.delete_if { |entry| entry[0]<seconds }
    end

    def start_match
      return if @started
      @started = true
      play_voice('pong_gamestart')
    end

    # Spacing is a minimum, not a deadline for interrupting an earlier voice.
    # A delayed durable write reuses the elapsed pause of its agreed goal.
    def point(scores, viewer:, winner: nil, finished: false, goal_at: nil,
      score_text: nil, result_text: nil)
      goal(viewer: viewer, winner: winner) unless goal_at
      @presents_point = false
      return unless gain('pong_goal') > 0
      @presents_point = true
      ordered = viewer == 1 ? scores.reverse : scores
      at = [@clock.call, (goal_at || @clock.call) + 3.0].max
      names = ['pong_scores', *ordered.map { |n| "pong_number#{n}" }]
      recorded = ordered.all? { |n| n.is_a?(Integer) && n.between?(0, 21) } && names.all? { |n| @sounds[n] }
      score = recorded ? names : [{ speech: score_text || ordered.join(' : ') }]
      silent = GameRoomSoundOutput.current(@program)&.muted? == true
      score.each_with_index { |item, i| @score_queue << [at + i * 0.5, item, silent] }
      if finished
        final_at = at + 2.7
        voice = winner == viewer ? 'pong_youwin' : 'pong_theywin'
        result = !@sounds[voice] ? { speech: result_text } : voice
        @score_queue << [final_at, result, silent] if !result.is_a?(Hash) || !result[:speech].to_s.empty?
        score_result_scheduled(final_at, winner, viewer) if winner != nil
        score.each_with_index { |item, i| @score_queue << [final_at + 0.3 + i * 0.5, item, silent] }
      end
    end

    private

    def initialize_score_announcements(speaker:, speech_active:)
      @speaker = speaker || ->(text) {
        next false unless GameRoomBackgroundPolicy.speech?(@program, covered: @background_provider&.call)
        speak(text, stop: false, break_sequence: false)
        true
      }
      @speech_active = speech_active || -> { respond_to?(:speech_actived, true) && speech_actived }
      @announcing, @score_queue = {}, []
    end

    def score_result_scheduled(_at, _winner, _viewer)
    end

    def retire_announcements(now)
      @announcing.keys.each do |name|
        sound = @sounds[name]
        finished = sound.respond_to?(:finished?) ? sound.finished? : !sound.playing?
        if finished || now >= @announcing[name]
          sound.pause
          @announcing.delete(name)
        end
      end
    end

    def advance_score_queue(now)
      # A recording queued before leaving the table must not become audible
      # on return merely because its scheduled start was still in the future.
      if GameRoomSoundOutput.current(@program)&.muted?
        @score_queue.each { |entry| entry[2] = true unless entry[1].is_a?(Hash) }
      end
      # A delayed UI tick must not start/cut three voices in the same frame.
      voice_busy = @voice && @announcing.key?(@voice)
      speech_busy = @speech_pending && now < @speech_deadline && @speech_active.call
      @speech_pending = false unless speech_busy
      if !voice_busy && !speech_busy && @score_queue.first && now >= @score_queue.first[0]
        scheduled, item, silent = @score_queue.shift
        if item.is_a?(Hash) && personal_gain('pong_scores') > 0
          @speech_pending = @speaker.call(item[:speech]) != false
          @speech_deadline = now + 30.0
        elsif !item.is_a?(Hash)
          play_voice(item, silent: silent)
        end
        lag = now - scheduled
        @score_queue.each { |entry| entry[0] += lag } if lag > 0.05
      end
    end

    def clear_announcements
      @announcing.each_key { |name| @sounds[name]&.pause }
      @announcing.clear
      @score_queue.clear
      @voice = nil
      @speech_pending = false
    end

    def play_goal_recordings(asset = nil)
      unless asset
        goal = GOALS[@rng.rand(GOALS.length)]
        asset = @sounds[goal] ? goal : 'pong_goal'
      end
      play_announcement(asset)
      play_voice(GOAL_VOICES[@rng.rand(GOAL_VOICES.length)])
    end

    def play_voice(name, silent: false)
      @sounds[@voice]&.pause if @voice
      @announcing.delete(@voice)
      @voice = play_announcement(name, silent: silent)
    end

    def play_announcement(name, silent: false)
      sound = play_sound(name, level: ANNOUNCER_LEVEL, silent: silent)
      return unless sound
      duration = sound.respond_to?(:length) ? sound.length.to_f : 3.0
      duration = 3.0 unless duration.finite? && duration > 0
      @announcing[name] = @clock.call + duration.clamp(0.1, 30.0) + 0.25
      name
    end
  end
end
