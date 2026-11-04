require_relative "../game_content"
require_relative "preferences"
require_relative "sound_pack"
require_relative "point_audio"
require_relative "../game_background_policy"

require_relative "../game_room_localization"

module GameRoomAudioBall
  using GameRoomLocalization::Translations
  class Audio
    SHOTS = {'up' => 'audio_ball_up', 'left' => 'audio_ball_left', 'down' => 'audio_ball_down'}.freeze
    PREPARE = 'audio_ball_prepare'.freeze
    ASSETS = SoundPack::DEFAULT.values.compact.freeze

    attr_reader :presents_point
    attr_accessor :background_provider

    def initialize(program, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, rng: Random.new,
      speaker: nil, speech_active: nil)
      @program = program
      @speaker = speaker || ->(text) {
        next false unless GameRoomBackgroundPolicy.speech?(@program, covered: @background_provider&.call)
        speak(text, stop: false, break_sequence: false)
        true
      }
      @point_audio = PointAudio.new(program, clock: clock, rng: rng, speaker: @speaker, speech_active: speech_active)
      @sounds = {}
      @presents_point = false
      load
    end

    def load
      return if @loaded
      refresh_preferences
      @point_audio.load
      @loaded = true
    end

    # Called at construction and after Ctrl+P, never to allocate in a flight tick.
    # Keep existing handles cached; switching back does not open duplicate streams.
    def refresh_preferences
      return if @closed
      pack = SoundPack.selected(@program)
      return if @pack.equal?(pack)
      silence
      @pack = pack
      @pack.each do |role, name|
        next if !name || role == 'goal' || @sounds.key?(name)
        sound = @program.create_sound_from_asset(name, sample: false, loop: SHOTS.key?(role))
        next unless sound
        @program.manage(sound) if @program.respond_to?(:manage)
        @sounds[name] = sound
      end
      @point_audio.refresh_preferences
    end

    def update(snapshot, viewer:, paused: false)
      return silence if paused || !snapshot || snapshot['phase'] == 'over' || snapshot['goal'] != nil
      if snapshot['phase'] != 'flying'
        stop_flight
        sound = @sounds[@cue_name]
        if sound && sound.playing?
          sound.pan = listening_pan((@cue_side == 0 ? 1.0 : -1.0) * (viewer == 1 ? -1 : 1))
          GameRoomSoundOutput.apply(@program, sound, gain(@cue_name))
          sound.pause unless gain(@cue_name) > 0
        end
        return
      end
      name = @pack[snapshot['shot']]
      sound = @sounds[name]
      return silence unless sound
      flight = [name, snapshot['turn']]
      if @flight != flight
        @sounds.each_value { |entry| entry.pause if entry.playing? }
        sound.position = 0
        @flight = flight
      end
      sound.pan = listening_pan((snapshot['position'].to_f / 25.0 * 2.0 - 1.0) * (viewer == 1 ? -1 : 1))
      GameRoomSoundOutput.apply(@program, sound, gain(name), continuous: true)
      if gain(name) > 0
        sound.play unless sound.playing?
      else
        sound.pause if sound.playing?
      end
    end

    def prepare(side, viewer:)
      play_cue('prepare', side, viewer)
    end

    def stop_ball(side, viewer:)
      play_cue('stop', side, viewer)
    end

    def goal(viewer:, winner:, reason: nil)
      return if @closed
      silence
      @point_audio.goal(viewer: viewer, winner: winner, reason: reason)
    end

    def point(scores, sets:, set_finished:, winner:, viewer:, finished:, goal_at: nil)
      return if @closed
      silence
      @presents_point = false
      return @point_audio.cancel unless @point_audio.presentation_enabled?
      ordered = viewer == 1 ? scores.reverse : scores
      score_text = GameRoomContent.utf8(_("Score: %{own} to %{opponent}.")) % {own: ordered[0], opponent: ordered[1]}
      @point_audio.point(scores, viewer: viewer, winner: winner, score_text: score_text, goal_at: goal_at)
      @presents_point = @point_audio.presents_point
      parts = []
      if set_finished
        parts << if viewer == nil
          GameRoomContent.utf8(_("Player %{player} wins the set.")) % {player: winner + 1}
        else
          winner == viewer ? _("You win the set.") : _("You lose the set.")
        end
      end
      if set_finished || finished
        ordered_sets = viewer == 1 ? sets.reverse : sets
        parts << GameRoomContent.utf8(_("Sets: %{own} to %{opponent}.")) % {own: ordered_sets[0], opponent: ordered_sets[1]}
      end
      if finished
        parts << if viewer == nil
          GameRoomContent.utf8(_("Player %{player} wins the match.")) % {player: winner + 1}
        else
          winner == viewer ? _("You win the match.") : _("You lose the match.")
        end
      end
      announce(parts.map { |part| GameRoomContent.utf8(part) }.join(' ')) unless parts.empty?
    end

    def tick
      return if @closed
      unless @point_audio.presentation_enabled?
        @presents_point = false
        return @point_audio.cancel
      end
      @point_audio.tick
    end

    def announcement_pending?
      @point_audio.announcement_pending?
    end

    def recording_sound_handles
      @sounds.values+@point_audio.recording_sound_handles
    end

    def recording_seek(seconds)
      @point_audio.recording_seek(seconds)
    end

    def announce(text)
      return if @closed
      if @point_audio.presentation_enabled?
        @point_audio.announce(GameRoomContent.utf8(text))
      else
        tick
        @speaker.call(GameRoomContent.utf8(text))
      end
    end

    def announce_set(number)
      return if @closed
      text = case number
      when 1 then _("First set.")
      when 2 then _("Second set.")
      when 3 then _("Third set.")
      when 4 then _("Fourth set.")
      when 5 then _("Fifth set.")
      end
      announce(text) if text
    end

    def hurry(player)
      return if @closed
      announce(GameRoomContent.utf8(_("%{player}, you have 10 seconds left.")) % {player: GameRoomContent.utf8(player)})
    end

    def close
      return if @closed
      silence
      @closed = true
      @presents_point = false
      @sounds.each_value do |sound|
        @program.release(sound) if @program.respond_to?(:release)
        sound.close
      end
      @sounds.clear
      @point_audio.close
    end

    def reset
      silence
      @sounds.each_value { |sound| sound.position = 0 }
    end

    def silence
      @sounds.each_value { |sound| sound.pause if sound.playing? }
      @flight = nil
      @cue_name = nil
    end

    private

    def play_cue(role, side, viewer)
      return if @closed
      silence
      @cue_name, @cue_side = @pack[role], side
      sound = @sounds[@cue_name]
      return unless sound
      sound.pan = listening_pan((side == 0 ? 1.0 : -1.0) * (viewer == 1 ? -1 : 1))
      GameRoomSoundOutput.apply(@program, sound, gain(@cue_name), restart: true)
      return unless gain(@cue_name) > 0
      sound.position = 0
      sound.play
    end

    def listening_pan(pan)
      Preferences.read(@program)['listening_side'] == 'left' ? -pan : pan
    end

    def stop_flight
      SHOTS.each_key do |role|
        name = @pack[role]
        sound = @sounds[name]
        sound.pause if sound && sound.playing?
      end
      @flight = nil
    end

    def gain(name)
      return 0.0 if @program.respond_to?(:game_room_sound_enabled?, true) && !@program.send(:game_room_sound_enabled?, name)
      @program.respond_to?(:game_room_sound_volume, true) ? @program.send(:game_room_sound_volume, name).to_f : 1.0
    end
  end
end
