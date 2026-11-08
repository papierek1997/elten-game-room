require_relative 'game_room_preferences'

# One local stream for this application runtime. Only the active UI calls it.
class GameRoomBackgroundMusic
  def initialize(settings:, register: nil, open_sound: ->(path) { ::Sound.new(path, loop: true, sample: false) })
    @settings, @open_sound = settings, open_sound
    @register = register
    @depth, @games = 0, {}
  end

  def enter
    @depth += 1
    update
  end

  def leave
    @depth = [@depth - 1, 0].max
    update
  end

  def game(owner, replay, output: nil)
    return leave_game(owner) if replay.finished?
    @games[owner] = output
    update
  end

  def leave_game(owner)
    return unless @games.key?(owner)
    @games.delete(owner)
    update
  end

  def update(retry_failed: false)
    values = @settings.call
    tracks = GameRoomPreferences.background_music(values)
    kind = @games.empty? ? 'general' : 'game'
    output = @games.values.last
    track = tracks.fetch(kind)
    master = GameRoomPreferences.sound_volumes(values).fetch('all') / 100.0
    volume = track['volume'] / 100.0 * master
    desired = [kind, track['file'], output] if (@depth > 0 || !@games.empty?) &&
      track['enabled'] && !track['file'].empty? && volume > 0
    if desired != @desired || (retry_failed && desired && !@sound)
      stop
      @desired = desired
      if desired
        path = File.expand_path(track['file'])
        raise IOError, 'Background audio file is unavailable' unless File.file?(path)
        @register&.call(self)
        @register = nil
        @sound = @open_sound.call(path)
        raise IOError, 'Background audio format could not be opened' unless @sound&.opened?
        set_volume(output, volume)
        @sound.play
      end
    elsif @sound && @volume != volume
      set_volume(output, volume)
    end
  rescue IOError, SystemCallError, ArgumentError => error
    stop
    Log.warning("Power Games background music: #{error.message}") if defined?(Log)
  end

  def close
    @depth, @games, @desired = 0, {}, nil
    stop
  end

  private

  def set_volume(output, volume)
    if output
      output.apply(@sound, volume, continuous: true, restart: true, silent: false)
    else
      @sound.volume = volume
    end
    @volume = volume
  end

  def stop
    sound, @sound = @sound, nil
    @volume = nil
    sound&.close
  end
end
