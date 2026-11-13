# encoding: UTF-8
require_relative '../game_sound_output'
require_relative 'scoring'

module GameRoomDarts
  # The locator is deliberately sound-only. It never changes global speech or
  # asks NVDA to stop; ordinary interface and post-throw announcements remain
  # available to the screen reader.
  class Audio
    LOCATOR = 'pong_ball'.freeze
    READY = 'ding'.freeze
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
    QUALITY = 'notice'.freeze

    def initialize(program)
      @program = program
      @sounds = {}
    end

    def load
      return if @loaded
      ([[LOCATOR, true], [READY, false], [THROW, false], [WIN, false], [LOSS, false], [QUALITY, false]] +
        IMPACTS.values.uniq.map { |asset| [asset, false] }).each do |asset, looped|
        sound = @program.create_sound_from_asset(asset, loop: looped, sample: false)
        next unless sound
        @program.manage(sound) if @program.respond_to?(:manage)
        @sounds[asset] = sound
      end
      @locator_frequency = @sounds[LOCATOR]&.frequency
      @quality_frequency = @sounds[QUALITY]&.frequency
      @impact_frequencies = IMPACTS.values.uniq.to_h { |asset| [asset, @sounds[asset]&.frequency] }
      @loaded = true
    end

    def update(x, y, active:)
      sound = @sounds[LOCATOR]
      return unless sound
      return silence unless active

      x = x.to_f.clamp(-Scoring::BOARD_LIMIT, Scoring::BOARD_LIMIT)
      y = y.to_f.clamp(-Scoring::BOARD_LIMIT, Scoring::BOARD_LIMIT)
      radius = Math.sqrt(x * x + y * y)
      sound.pan = x / Scoring::BOARD_LIMIT
      sound.frequency = @locator_frequency * (1.0 + y / Scoring::BOARD_LIMIT * 0.25) if @locator_frequency
      level = 0.18 + 0.72 * (1.0 - [radius / (Scoring::BOARD_LIMIT * Math.sqrt(2)), 1.0].min)
      GameRoomSoundOutput.apply(@program, sound, level, continuous: true)
      sound.play unless sound.playing?
    end

    def ready; play_once(READY); end

    def throw_dart
      play_once(THROW)
      sound_length(@sounds[THROW])
    end

    def impact(points, x:, y:)
      durations = []
      if points.to_i.positive?
        asset = IMPACTS.fetch(Scoring.sector(x, y))
        impact = @sounds[asset]
        if impact
          impact.pan = x.to_f.clamp(-Scoring::BOARD_LIMIT, Scoring::BOARD_LIMIT) / Scoring::BOARD_LIMIT
          base = @impact_frequencies[asset]
          impact.frequency = base * (1.0 + y.to_f.clamp(-Scoring::BOARD_LIMIT, Scoring::BOARD_LIMIT) /
            Scoring::BOARD_LIMIT * 0.12) if base
          play_once(asset)
          durations << sound_length(impact)
        end
      end
      sound = @sounds[QUALITY]
      return durations.max.to_f unless sound
      ratio = {100 => 1.50, 75 => 1.25, 50 => 1.0, 25 => 0.80, 0 => 0.58}.fetch(points.to_i, 0.58)
      sound.frequency = @quality_frequency * ratio if @quality_frequency
      sound.pan = 0
      play_once(QUALITY)
      durations << sound_length(sound)
      durations.max.to_f
    end

    def result(won:)
      play_once(won ? WIN : LOSS)
    end

    def silence
      sound = @sounds[LOCATOR]
      sound.pause if sound&.playing?
    end

    def close
      silence
      @sounds.each_value do |sound|
        @program.release(sound) if @program.respond_to?(:release)
        sound.close
      end
      @sounds.clear
    end

    private

    def play_once(asset)
      sound = @sounds[asset]
      return unless sound
      sound.position = 0
      GameRoomSoundOutput.apply(@program, sound, 1.0, restart: true)
      sound.play
    end

    def sound_length(sound)
      return 0.0 unless sound && sound.respond_to?(:length)

      [sound.length.to_f, 0.0].max
    end
  end
end
