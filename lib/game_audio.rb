# Optional per-game audio, using the program's normal ELTEN output device.
# This class owns streams, not game state or keyboard bindings.
class GameRoomAudio
  DEFAULTS = {"music" => false, "effects" => false, "music_volume" => 40, "effects_volume" => 70}.freeze
  attr_reader :settings

  def initialize(program, game_id:)
    @program, @path = program, "game_audio/#{game_id}.json"
    @settings = normalize(@program.read_json(@path, default: {}))
    @music, @asset = nil, nil
  end

  def save(settings)
    next_settings = normalize(settings)
    raise "Cannot save audio settings" if @program.write_json(@path, next_settings) == false
    @settings = next_settings
    update(@requested_asset)
  end

  def update(asset)
    @requested_asset = asset
    desired = @settings["music"] ? asset : nil
    if desired != @asset
      close
      if desired
        @music = @program.create_sound_from_asset(desired, loop: true, sample: false)
        raise "Cannot open music asset" unless @music
        @program.manage(@music)
        @music.volume = @settings["music_volume"] / 100.0
        @music.play
        @asset = desired
      end
    elsif @music
      @music.volume = @settings["music_volume"] / 100.0
    end
  rescue StandardError => error
    close
    Log.warning("Game Room music: #{error.class}: #{error.message}") if defined?(Log)
  end

  def play(asset)
    return unless asset && @settings["effects"]
    @program.play_sound_from_asset(asset, sample: false, max_voices: 4, volume: @settings["effects_volume"] / 100.0)
  rescue StandardError => error
    Log.warning("Game Room effect: #{error.class}: #{error.message}") if defined?(Log)
  end

  def close
    sound, @music, @asset = @music, nil, nil
    @program.release(sound, close: true) if sound
  end

  private

  def normalize(value)
    values = value.is_a?(Hash) ? value : {}
    DEFAULTS.to_h do |key, default|
      raw = values.fetch(key, default)
      [key, key.end_with?("_volume") ? [[raw.to_i, 0].max, 100].min : raw == true]
    end
  end
end
