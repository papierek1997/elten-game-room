# encoding: UTF-8
require_relative '../game_sound_output'
require_relative 'scoring'
require_relative 'preferences'

module GameRoomDarts
  # The locator is deliberately sound-only. It never changes global speech or
  # asks NVDA to stop; ordinary interface and post-throw announcements remain
  # available to the screen reader.
  class Audio
    LOCATOR_EDGE_PITCH = 0.82
    LOCATOR_PITCH_SPAN_SEMITONES = 16.0
    LOCATOR_CURVE_EXPONENT = 1.6
    READY = 'ding'.freeze
    COUNTDOWN = 'duck_note_c'.freeze
    EDGE = 'darts_edge'.freeze
    LIMIT = 'darts_limit'.freeze
    THROW = 'darts_throw'.freeze
    WIN = 'darts_applause'.freeze
    LOSS = 'darts_consolation'.freeze
    IMPACTS = {
      east: 'darts_hit_1', north_east: 'darts_hit_2',
      north: 'darts_hit_3', north_west: 'darts_hit_4',
      west: 'darts_hit_5', south_west: 'darts_hit_4',
      south: 'darts_hit_3', south_east: 'darts_hit_2',
      center: 'darts_hit_1'
    }.freeze
    # The supplied board recordings contain different amounts of leading
    # quiet.  Start the score-quality cue only after the audible attack of the
    # selected impact has had a short, consistent lead.
    IMPACT_ATTACK_SECONDS = {
      'darts_hit_1' => 0.371,
      'darts_hit_2' => 0.539,
      'darts_hit_3' => 0.511,
      'darts_hit_4' => 0.194,
      'darts_hit_5' => 0.253
    }.freeze
    IMPACT_QUALITY_LEAD_SECONDS = 0.10
    QUALITY = 'notice'.freeze

    def initialize(program)
      @program = program
      @sounds = {}
    end

    def load
      return if @loaded
      ([READY, COUNTDOWN, EDGE, LIMIT, THROW, WIN, LOSS, QUALITY] + IMPACTS.values.uniq).each do |asset|
        load_asset(asset, looped: false)
      end
      @countdown_frequency = @sounds[COUNTDOWN]&.frequency
      @quality_frequency = @sounds[QUALITY]&.frequency
      @impact_frequencies = IMPACTS.values.uniq.to_h { |asset| [asset, @sounds[asset]&.frequency] }
      @loaded = true
      refresh_preferences
    end

    def refresh_preferences
      asset = Preferences.locator_asset(Preferences.read(@program))
      return asset unless @loaded
      return asset if @locator_asset == asset && @sounds[asset]

      release_asset(@locator_asset) if @locator_asset
      @locator_asset = asset
      sound = load_asset(asset, looped: true)
      @locator_frequency = sound&.frequency
      asset
    end

    def update(x, y, active:)
      sound = @sounds[@locator_asset]
      return unless sound
      return silence unless active

      x = x.to_f.clamp(-Scoring::BOARD_LIMIT, Scoring::BOARD_LIMIT)
      y = y.to_f.clamp(-Scoring::BOARD_LIMIT, Scoring::BOARD_LIMIT)
      radius = Math.sqrt(x * x + y * y)
      proximity = 1.0 - [radius / Scoring::BOARD_LIMIT, 1.0].min
      sound.pan = x / Scoring::BOARD_LIMIT
      # Pitch describes radial accuracy, not vertical position. A fractional
      # exponent keeps the inner board more distinct without the harder feel of
      # a quadratic curve. Frequency remains continuous, below quarter tones.
      semitones = LOCATOR_PITCH_SPAN_SEMITONES * proximity**LOCATOR_CURVE_EXPONENT
      pitch = LOCATOR_EDGE_PITCH * 2.0**(semitones / 12.0)
      sound.frequency = @locator_frequency * pitch if @locator_frequency
      level = 0.55 + 0.45 * proximity
      GameRoomSoundOutput.apply(@program, sound, level, continuous: true)
      sound.play unless sound.playing?
    end

    def ready; play_once(READY); end

    def deadline_warning(seconds)
      ratio = {3 => 0.72, 2 => 0.86, 1 => 1.00}[seconds.to_i]
      return false unless ratio

      sound = @sounds[COUNTDOWN]
      return false unless sound
      sound.frequency = @countdown_frequency * ratio if @countdown_frequency
      sound.pan = 0
      play_once(COUNTDOWN)
      true
    end

    def edge
      return false unless @sounds[EDGE]

      @sounds[EDGE].pan = 0
      play_once(EDGE, level: 0.9)
      true
    end

    def limit
      return false unless @sounds[LIMIT]

      @sounds[LIMIT].pan = 0
      play_once(LIMIT, level: 0.9)
      true
    end

    def throw_dart
      play_once(THROW)
      sound_length(@sounds[THROW])
    end

    def impact(points, x:, y:)
      return 0.0 unless points.to_i.positive?

      asset = IMPACTS.fetch(Scoring.sector(x, y))
      impact = @sounds[asset]
      return 0.0 unless impact

      impact.pan = x.to_f.clamp(-Scoring::BOARD_LIMIT, Scoring::BOARD_LIMIT) / Scoring::BOARD_LIMIT
      base = @impact_frequencies[asset]
      pitch_ratio = 1.0 + y.to_f.clamp(-Scoring::BOARD_LIMIT, Scoring::BOARD_LIMIT) /
        Scoring::BOARD_LIMIT * 0.12
      impact.frequency = base * pitch_ratio if base
      play_once(asset)
      IMPACT_ATTACK_SECONDS.fetch(asset) / pitch_ratio + IMPACT_QUALITY_LEAD_SECONDS
    end

    def quality(points)
      sound = @sounds[QUALITY]
      return 0.0 unless sound
      score = points.to_i.clamp(0, 100)
      ratio = score.zero? ? 0.58 : 0.58 + score / 100.0 * 0.92
      sound.frequency = @quality_frequency * ratio if @quality_frequency
      sound.pan = 0
      play_once(QUALITY)
      sound_length(sound)
    end

    def result(won:)
      asset = won ? WIN : LOSS
      play_once(asset)
      sound_length(@sounds[asset])
    end

    def silence
      sound = @sounds[@locator_asset]
      sound.pause if sound&.playing?
    end

    def close
      silence
      @sounds.each_value do |sound|
        @program.release(sound) if @program.respond_to?(:release)
        sound.close
      end
      @sounds.clear
      @locator_asset = nil
      @loaded = false
    end

    private

    def load_asset(asset, looped:)
      sound = @program.create_sound_from_asset(asset, loop: looped, sample: false)
      return nil unless sound
      @program.manage(sound) if @program.respond_to?(:manage)
      @sounds[asset] = sound
    end

    def release_asset(asset)
      sound = @sounds.delete(asset)
      return unless sound
      sound.pause if sound.respond_to?(:pause) && sound.playing?
      @program.release(sound) if @program.respond_to?(:release)
      sound.close
    end

    def play_once(asset, level: 1.0)
      sound = @sounds[asset]
      return unless sound
      sound.position = 0
      GameRoomSoundOutput.apply(@program, sound, level, restart: true)
      sound.play
    end

    def sound_length(sound)
      return 0.0 unless sound && sound.respond_to?(:length)

      [sound.length.to_f, 0.0].max
    end
  end
end
