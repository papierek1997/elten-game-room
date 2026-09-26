require_relative 'audio_extras'
require_relative 'preferences'
require_relative '../realtime/score_announcements'

module GameRoomPong
  class Audio
    include AudioExtras
    include GameRoomRealtime::ScoreAnnouncements
    SHIELD_HITS = (1..10).flat_map { |n| ["pong_own_shield_hit#{n}", "pong_op_shield_hit#{n}"] }.freeze
    MOVEMENT_ASSETS = %w[pong_move pong_op_move pong_move_double pong_edge pong_op_edge].freeze
    PARTICIPANT_ASSETS = (MOVEMENT_ASSETS + %w[pong_hit pong_op_hit]).freeze
    DOUBLES_FIRST_PLAYER_PITCH = 2.0**(-4.0 / 12)
    ASSETS = (%w[pong_ball pong_hit pong_op_hit pong_wall pong_move pong_op_move pong_move_double pong_edge pong_op_edge
      pong_shield_on pong_shield_off pong_shield_hit pong_op_shield_on pong_op_shield_off pong_invisible] +
      SHIELD_HITS + ANNOUNCEMENTS + ECHO_ASSETS + CROWD_ASSETS).freeze
    # Original default: own steps start at 50%; opponent steps settle at 20%
    # after UpdateSounds applies the far-end attenuation. The user selected
    # these proportions instead of increasing both old 25% cues by 10%.
    OWN_MOVEMENT_LEVEL = 0.5
    OPPONENT_MOVEMENT_LEVEL = 0.2
    # Balance only the new recording, independently of side and user sliders.
    DOUBLES_MOVEMENT_GAIN = 10.0**(-3.0 / 20.0)
    # Original default opponent steps = 100%; depth gain .2 times 4.55.
    # Independent of the personal score-announcer regulator.
    OPPONENT_SHIELD_HIT_LEVEL = 0.91
    WALL_PITCH = [1.3, 1.15, 1.0, 0.85, 0.7].freeze

    def initialize(program, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, rng: Random.new,
      speaker: nil, speech_active: nil)
      @program, @clock, @rng = program, clock, rng
      initialize_score_announcements(speaker: speaker, speech_active: speech_active)
      @sounds, @frequencies = {}, {}
      @voice_assets, @movement_players = {}, 2
      @levels, @pans = {}, {}
      @echo, @crowd = 'off', false
      reset
    end

    def load
      ASSETS.each { |name| load_sound(name, name) }
      @loaded = true
      prepare_players(@movement_players)
    end

    # Allocate once during client setup, not in the high-frequency audio tick.
    # Single retains the existing handles. Doubles reuses each base handle for
    # seat zero and adds independent voices for the other three seats. Assets
    # are shared; restarting one paddle never rewinds another paddle's voice.
    def prepare_players(count)
      @movement_players = count == 4 ? 4 : 2
      return unless @loaded && @movement_players == 4
      PARTICIPANT_ASSETS.each do |asset|
        (1...4).each do |seat|
          key = participant_sound_key(asset, seat)
          next if @sounds.key?(key)
          @voice_assets[key] = asset
          load_sound(asset, key)
        end
      end
    end

    def reset
      @last_effect = 0
      @movement_cue_sources = {}
      @movement_volume_groups = {}
      crowd_reset
      suspend
    end

    # A reliable, mutually agreed miss can sound immediately. The score and
    # match result still come exclusively from an accepted LiveSessions point.
    def goal(viewer:, winner: nil)
      clear_announcements
      crowd_reset
      return unless gain('pong_goal') > 0
      suspend
      play_goal_recordings
      crowd_event(winner == viewer ? 'cheer' : 'epicfail') if winner != nil
    end

    def tick
      now = @clock.call
      if gain('pong_goal') <= 0
        clear_announcements
        @sounds.each_value(&:pause)
        return
      end
      if @crowd_result && now >= @crowd_result[0]
        crowd_event(@crowd_result[1])
        @crowd_result = nil
      end
      retire_announcements(now)
      @levels.each do |name, level|
        apply_mix(name, @pans[name], level) if @sounds[name]&.playing?
      end
      advance_score_queue(now)
    end

    def update(snapshot, viewer:, paused:)
      return suspend unless snapshot
      paddle, ball = snapshot['p'][viewer], snapshot['b']
      pan, volume = spatial(paddle, ball['x'], ball['y'], court_side(snapshot, viewer))
      level = paused || snapshot['invisible'] || ball['dy'] == 0 ? 0 : volume
      loop_sound('pong_ball', pan: pan, level: level)
      update_echo(paddle)
      update_crowd(paused)
      # Update an already ringing impact before processing fresh effects:
      # a new wall contact still starts with its original impact curve.
      if @sounds['pong_wall']&.playing?
        @pans['pong_wall'], @levels['pong_wall'] = pan, volume
        apply_mix('pong_wall', pan, volume)
      end
      snapshot['fx'].each do |number, kind, side, x, y|
        next if number <= @last_effect
        @last_effect = number
        next if paused && !%w[step edge].include?(kind)
        play_effect(kind, side, x, y, snapshot, viewer)
        crowd_event('chant') if kind == 'serve'
        crowd_event('increase') if kind == 'hit'
      end
      update_movement_cues(snapshot, viewer)
    end

    def silence
      suspend
      clear_announcements
    end

    def suspend
      @sounds.each { |name, sound| sound.pause unless ANNOUNCEMENTS.include?(name) }
    end

    def close
      silence
      @sounds.each_value do |sound|
        @program.release(sound) if @program.respond_to?(:release)
        sound.close
      end
      @sounds.clear
      @loaded = false
    end

    private

    def load_sound(asset, key)
      sound = @program.create_sound_from_asset(asset, loop: asset == 'pong_ball' || LOOP_ASSETS.include?(asset))
      return unless sound
      @program.manage(sound) if @program.respond_to?(:manage)
      @sounds[key] = sound
      @frequencies[key] = sound.frequency
    end

    def participant_sound_key(asset, seat)
      @movement_players == 4 && seat != 0 ? "#{asset}:#{seat}" : asset
    end

    # First member of each team keeps the lower contact voice for every listener.
    # Do not derive identity from the observer, the current hitter or service.
    def participant_pitch(snapshot, seat)
      first_team_player?(snapshot, seat) ? DOUBLES_FIRST_PLAYER_PITCH : 1.0
    end

    def first_team_player?(snapshot, seat)
      teams = snapshot['teams']
      teams && teams.length == 4 && seat != nil && teams.index(teams[seat]) == seat
    end

    def court_side(snapshot, participant)
      snapshot['teams'] ? snapshot['teams'][participant] : participant
    end

    def update_movement_cues(snapshot, viewer)
      @movement_cue_sources.each do |name, source|
        next unless @sounds[name]&.playing?
        next if source == nil
        pan, = spatial(snapshot['p'][viewer], snapshot['p'][source],
          court_side(snapshot, source) * 20, court_side(snapshot, viewer))
        @pans[name] = pan
        apply_mix(name, pan, @levels[name])
      end
    end

    # Match SoundMgr._apply_panvol: scale L/R by the master first, then
    # saturate each channel independently. ELTEN/BASS uses linear balance;
    # recover volume + pan from those channel gains without global changes.
    # Keep raw pan/level separately so a later volume change is reversible.
    def apply_mix(name, pan, level)
      asset = @voice_assets.fetch(name, name)
      sample_gain = asset == 'pong_move_double' ? DOUBLES_MOVEMENT_GAIN : 1.0
      volume = [level * sample_gain * personal_gain(name) * gain(name), 0.0].max
      left = [volume * (pan > 0 ? (1 - pan)**1.4 : 1), 1.0].min
      right = [volume * (pan < 0 ? (1 + pan)**1.4 : 1), 1.0].min
      volume = [left, right].max
      pan = volume.zero? ? 0 : (right >= left ? 1 - left / right : right / left - 1)
      @sounds[name].pan, @sounds[name].volume = pan, volume
    end

    def play_effect(kind, side, x, y, snapshot, viewer)
      paddle = snapshot['p'][viewer]
      own = side == viewer
      viewer_side = court_side(snapshot, viewer)
      distance = (viewer_side.zero? ? y : 20 - y).clamp(0, 20)
      pan, volume = spatial(paddle, x, y, viewer_side)
      pitch = 1.0
      case kind
      when 'step', 'edge'
        return if side == nil
        own = court_side(snapshot, side) == viewer_side if kind == 'step'
        x = snapshot['p'][side]
        pan, volume = spatial(paddle, x, court_side(snapshot, side) * 20, viewer_side)
        name = kind == 'step' ? (own ? 'pong_move' : 'pong_op_move') : (own ? 'pong_edge' : 'pong_op_edge')
        name = 'pong_move_double' if kind == 'step' && first_team_player?(snapshot, side)
        name = participant_sound_key(name, side)
        @movement_cue_sources[name] = side if kind == 'step' || !own
        volume = own ? OWN_MOVEMENT_LEVEL : OPPONENT_MOVEMENT_LEVEL if kind == 'step'
        if kind == 'step'
          @movement_volume_groups[name] = own ? 'own_volume' : 'opponent_volume'
          pitch = 1.3 - (x.to_i - 15).abs.clamp(0, 14) * (0.6 / 14)
        end
      when 'hit', 'serve'
        @sounds['pong_ball'].position = 0 if @sounds['pong_ball']
        name = participant_sound_key(own ? 'pong_hit' : 'pong_op_hit', side)
        pitch = participant_pitch(snapshot, side)
        pan, volume = own ? [0, 1.0] : spatial(paddle, snapshot['p'][side], court_side(snapshot, side) * 20, viewer_side)
      when 'wall'
        name = 'pong_wall'
        pitch = WALL_PITCH[(distance / 4).to_i.clamp(0, 4)]
        volume = distance <= 3 ? 1.0 : [0.95 - (distance - 4) * 0.06, 0].max
      when 'shield_on', 'shield_off'
        own = court_side(snapshot, side) == viewer_side
        name = "pong_#{own ? '' : 'op_'}#{kind}"
        pan, volume = 0, own ? 2.0 : 0.24
        pitch = 0.9438743126816935 unless own
      when 'shield_hit'
        @sounds['pong_ball'].position = 0 if @sounds['pong_ball']
        name = "pong_#{own ? 'own' : 'op'}_shield_hit#{@rng.rand(10) + 1}"
        name = 'pong_shield_hit' unless @sounds[name]
        pitch = participant_pitch(snapshot, side)
        pan = panorama(x - paddle)
        volume = own ? 2.0 : OPPONENT_SHIELD_HIT_LEVEL
      when 'invisible'
        name = 'pong_invisible'
      else
        return
      end
      play_sound(name, pan: pan, level: volume, pitch: pitch)
    end

    def clear_announcements
      super
      @crowd_result = nil
    end

    def score_result_scheduled(at, winner, viewer)
      @crowd_result = [at, winner == viewer ? 'won' : 'lost']
    end

    def play_sound(name, pan: 0, level: 1.0, pitch: 1.0)
      sound = @sounds[name]
      return unless sound && gain(name) > 0
      @pans[name], @levels[name] = pan, level
      apply_mix(name, pan, level)
      sound.frequency = @frequencies[name] * pitch
      sound.position = 0
      sound.play
      sound
    end

    def loop_sound(name, pan: 0, level:)
      sound = @sounds[name]
      return unless sound
      @pans[name], @levels[name] = pan, level
      apply_mix(name, pan, level)
      if sound.volume > 0
        sound.play unless sound.playing?
      else
        sound.pause if sound.playing?
      end
    end

    def spatial(paddle, x, y, side)
      delta = x - paddle
      pan = panorama(delta)
      distance = side.zero? ? y : 20 - y
      [pan, (1.0 - distance * 0.04).clamp(0, 1)]
    end

    def panorama(delta)
      (Math.sqrt([delta.abs / 25.0, 1.0].min) * (delta.negative? ? -100 : 100)).to_i / 100.0
    end

    def personal_gain(name)
      movement_group = @movement_volume_groups[name]
      name = @voice_assets.fetch(name, name)
      key = if movement_group
        movement_group
      elsif ANNOUNCEMENTS.include?(name)
        'announcer_volume'
      elsif name == 'pong_move'
        'own_volume'
      elsif %w[pong_op_move pong_op_edge].include?(name)
        'opponent_volume'
      end
      key ? Preferences.read(@program).fetch(key, 100) / 100.0 : 1.0
    end

    def gain(asset)
      asset = @voice_assets.fetch(asset, asset)
      return 0.0 if @program.respond_to?(:game_room_sound_enabled?, true) && !@program.send(:game_room_sound_enabled?, asset)
      @program.respond_to?(:game_room_sound_volume, true) ? @program.send(:game_room_sound_volume, asset) : 1.0
    end
  end
end
