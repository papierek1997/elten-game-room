require_relative '../game_sound_output'

module GameRoomBilliards
  # Local, finite cues: no timer, worker, assets or saved game state.
  class AimAudio
    RATE = 48_000
    FRAMES = 1920

    def self.frequency(contact)
      return 3000 if contact && contact[:kind] == :pocket
      return nil unless contact && contact[:kind] == :ball
      (5000 - 4500 * contact.fetch(:offset).abs.clamp(0.0, 1.0)).round
    end

    def self.wave(frequency)
      pcm = Array.new(FRAMES) do |i|
        envelope = [i / 144.0, (FRAMES - 1 - i) / 144.0, 1.0].min
        (Math.sin(2 * Math::PI * frequency * i / RATE) * 4915 * envelope).round
      end.pack('s<*')
      'RIFF'.b + [36 + pcm.bytesize].pack('V') + 'WAVEfmt '.b +
        [16, 1, 1, RATE, RATE * 2, 2, 16].pack('VvvVVvv') + 'data'.b + [pcm.bytesize].pack('V') + pcm
    end

    def initialize(program)
      @program, @pool = program, program.sound_pool
    end

    def update(contact)
      stop
      return if @failed
      frequency = self.class.frequency(contact)
      return unless frequency
      return unless @program.__send__(:game_room_optional_sounds?) && @program.__send__(:game_room_sound_enabled?, 'billiards_aim')
      volume = @program.__send__(:game_room_sound_volume, 'billiards_aim')
      return unless volume > 0
      return if GameRoomSoundOutput.current(@program)&.muted?
      @sound = ::Sound.new(stream: self.class.wave(frequency))
      raise 'Cannot open billiards aiming tone' unless @sound.opened?
      # A new aiming step replaces this 40 ms cue; keep it off the delayed HRTF pipeline.
      GameRoomSoundOutput.apply(@program, @sound, volume, restart: true)
      @pool.play(@sound)
    rescue RuntimeError => error
      stop
      @failed = true
      Log.warning("Billiards aiming tone disabled: #{error.class}: #{error.message}")
    end

    def stop
      sound, @sound = @sound, nil
      if sound
        sound.close
        @pool.remove(sound)
      end
    end
  end
end
