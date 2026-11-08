require_relative 'game_room_preferences'

# One local stream for this application runtime. Only the active UI calls it.
class GameRoomBackgroundMusic
  def initialize(settings:, open_sound: ->(path) { ::Sound.new(path, loop: true, sample: false) })
    @settings, @open_sound = settings, open_sound
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

  def game(owner, replay)
    @games[owner] = !replay.finished?
    update
  end

  def leave_game(owner)
    @games.delete(owner)
    update
  end

  def update(retry_failed: false)
    values = @settings.call
    tracks = GameRoomPreferences.background_music(values)
    kind = @games.value?(true) ? 'game' : 'general'
    track = tracks.fetch(kind)
    master = GameRoomPreferences.sound_volumes(values).fetch('all') / 100.0
    desired = [kind, track['file']] if (@depth > 0 || @games.value?(true)) && track['enabled'] && !track['file'].empty? && track['volume'] > 0 && master > 0
    if desired != @desired || (retry_failed && desired && !@sound)
      stop
      @desired = desired
      if desired
        raise IOError, 'Background audio file is unavailable' unless File.file?(track['file'])
        @sound = @open_sound.call(track['file'])
        raise IOError, 'Background audio format could not be opened' unless @sound&.opened?
        @sound.volume = track['volume'] / 100.0 * master
        @sound.play
      end
    elsif @sound
      @sound.volume = track['volume'] / 100.0 * master
    end
  rescue IOError => error
    stop
    Log.warning("Power Games background music: #{error.message}") if defined?(Log)
  end

  def close
    @depth, @games, @desired = 0, {}, nil
    stop
  end

  private

  def stop
    sound, @sound = @sound, nil
    sound&.close
  end
end
