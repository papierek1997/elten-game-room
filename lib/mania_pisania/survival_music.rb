# encoding: UTF-8
require_relative 'survival_stream'
require_relative '../game_sound_output'

module GameRoomTyping
  using GameRoomLocalization::Translations
  # One native non-looping stream per round. No file reads or stream creation
  # during input; the game rules own deadlines, while this class owns playback.
  class SurvivalMusic
    attr_reader :duration

    def initialize(program, difficulty:, settings:)
      @program, @settings = program, settings
      @asset = "typing_survival_#{difficulty}"
      @sound = @program.create_sound_from_asset(@asset, loop: false, sample: false)
      raise IOError, _('Cannot open survival music.') unless @sound && @sound.opened?
      @program.manage(@sound)
      @duration = @sound.length.to_f
      raise IOError, _('Invalid survival music duration.') unless @duration.finite? && @duration > 0
      @frequency = @sound.frequency.to_f
      raise IOError, _('Invalid survival music frequency.') unless @frequency.finite? && @frequency > 0
      @playing = false
    rescue StandardError
      close
      raise
    end

    def start(rate:, position: 0.0)
      stop
      @sound.position = position
      update_volume
      # Changing playback frequency raises pitch and speed together, unlike
      # the pitch-preserving tempo effect. Always scale the original frequency.
      value = @sound.frequency_attribute.send(:value=, @frequency * rate)
      raise IOError, _('Cannot change survival music frequency.') if value == nil
      # Native Sound#play returns nil even on success; read its public state.
      @sound.play
      raise IOError, _('Cannot play survival music.') unless @sound.playing?
      @playing = true
    end

    def stop
      @sound.stop if @sound && @playing
      @playing = false
    end

    def update_volume
      return unless @sound
      enabled = !@program.respond_to?(:game_room_sound_enabled?, true) || @program.send(:game_room_sound_enabled?, @asset)
      volume = @program.respond_to?(:game_room_sound_volume, true) ? @program.send(:game_room_sound_volume, @asset).to_f : 1.0
      volume = enabled ? [[volume, 0.0].max, 1.0].min * @settings['music_volume'] / 100.0 : 0.0
      return if volume == @volume
      GameRoomSoundOutput.apply(@program, @sound, volume, continuous: true)
      @volume = volume
    end

    def close
      sound, @sound = @sound, nil
      @playing = false
      @program.release(sound, close: true) if sound
    end
  end
end
