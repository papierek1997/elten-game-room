require_relative '../lib/axel_pong/audio'

class DoublesAudioSound
  attr_accessor :frequency, :volume, :pan, :position
  attr_reader :plays

  def initialize(name, played)
    @name, @played = name, played
    @frequency, @volume, @pan, @plays = 44100, 0, 0, 0
  end

  def play
    @playing = true
    @plays += 1
    @played << @name
  end

  def pause; @playing = false; end
  def playing?; @playing; end
  def finished?; !playing?; end
  def length; 2.0; end
  def close; pause; end
end

class DoublesAudioProgram
  attr_reader :sounds, :played
  attr_accessor :pong_preferences, :sound_gain

  def initialize
    @sounds, @played = {}, []
    @sound_gain = 1.0
    @voices = Hash.new { |h, key| h[key] = [] }
    @pong_preferences = GameRoomPong::Preferences::DEFAULTS.dup
  end

  def create_sound_from_asset(name, loop:)
    sound = DoublesAudioSound.new(name, @played)
    @sounds[name] ||= sound
    @voices[name] << sound
    sound
  end

  def voice(name, source); @voices.fetch(name).fetch(source); end
  def game_room_sound_volume(_asset); @sound_gain; end
end

def assert(value, message)
  raise message unless value
end

def near(actual, expected, message)
  assert((actual - expected).abs < 0.000001, "#{message}: #{actual} != #{expected}")
end

def rendered_pan(delta)
  pan = (Math.sqrt([delta.abs / 25.0, 1.0].min) * (delta.negative? ? -100 : 100)).to_i / 100.0
  pan.negative? ? (1 + pan)**1.4 - 1 : 1 - (1 - pan)**1.4
end

def identity_pitch(teams, source)
  teams.take(source).include?(teams[source]) ? 1.0 : 2.0**(-4.0 / 12)
end

def step_asset(teams, source, viewer)
  return 'pong_move_double' unless teams.take(source).include?(teams[source])
  teams[source] == teams[viewer] ? 'pong_move' : 'pong_op_move'
end

def movement_sample_gain(asset)
  asset == 'pong_move_double' ? 0.7079457843841379 : 1.0
end

def snapshot(teams)
  {'teams' => teams, 'p' => [5.0, 10.0, 20.0, 25.0],
    'b' => {'x' => 15.0, 'y' => 5.0, 'dy' => 1.0}, 'fx' => [], 'invisible' => false}
end

def with_audio(clock: -> { 0.0 })
  program = DoublesAudioProgram.new
  audio = GameRoomPong::Audio.new(program, clock: clock, rng: Random.new(17))
  audio.load
  audio.prepare_players(4)
  yield audio, program
ensure
  audio&.close
end

failures = []
checks = 0
check = lambda do |name, &body|
  checks += 1
  body.call
  puts "PASS #{name}"
rescue StandardError => error
  failures << "#{name}: #{error.message}"
end

check.call('doubles ball depth follows teams while pan follows each local paddle') do
  [[0, 0, 1, 1], [0, 1, 0, 1], [1, 0, 1, 0]].each do |teams|
    teams.each_index do |viewer|
      with_audio do |audio, program|
        state = snapshot(teams)
        audio.update(state, viewer: viewer, paused: false)
        sound = program.sounds['pong_ball']
        near(sound.volume, teams[viewer].zero? ? 0.8 : 0.4, "team #{teams.inspect}, viewer #{viewer}: wrong depth")
        near(sound.pan, rendered_pan(state['b']['x'] - state['p'][viewer]), "viewer #{viewer}: wrong local paddle")
      end
    end
  end
end

check.call('doubles wall pitch and impact depth use the listener team') do
  [[0, 0, 1, 1], [0, 1, 0, 1]].each do |teams|
    teams.each_index do |viewer|
      with_audio do |audio, program|
        state = snapshot(teams)
        state['fx'] = [[1, 'wall', nil, 29.0, 5.0]]
        audio.update(state, viewer: viewer, paused: false)
        sound = program.sounds['pong_wall']
        depth = teams[viewer].zero? ? 5 : 15
        near(sound.volume, 0.95 - (depth - 4) * 0.06, "viewer #{viewer}: wrong wall depth")
        near(sound.frequency, 44100 * (teams[viewer].zero? ? 1.15 : 0.85), "viewer #{viewer}: wrong wall pitch")
        near(sound.pan, rendered_pan(29 - state['p'][viewer]), "viewer #{viewer}: wrong impact pan")
        state['b'].merge!('x' => 3.0, 'y' => 15.0)
        state['fx'] = []
        audio.update(state, viewer: viewer, paused: false)
        near(sound.volume, teams[viewer].zero? ? 0.4 : 0.8, "viewer #{viewer}: ringing wall used wrong end")
        near(sound.pan, rendered_pan(3 - state['p'][viewer]), "viewer #{viewer}: ringing wall did not follow ball")
        assert(sound.plays == 1, 'ringing wall restarted')
      end
    end
  end
end

check.call('doubles contacts place teammates near and opponents far without claiming local hits') do
  [[0, 0, 1, 1], [0, 1, 0, 1]].each do |teams|
    teams.each_index do |viewer|
      with_audio do |audio, program|
        state = snapshot(teams)
        number = 0
        %w[hit serve].each do |kind|
          teams.each_index do |source|
            state['fx'] = [[number += 1, kind, source, 1.0, 10.0]]
            before = program.played.length
            audio.update(state, viewer: viewer, paused: false)
            own = source == viewer
            name = own ? 'pong_hit' : 'pong_op_hit'
            sound = program.voice(name, source)
            assert(program.played[before..].include?(name), "viewer #{viewer}, source #{source}: wrong contact voice")
            near(sound.volume, teams[source] == teams[viewer] ? 1.0 : 0.2, "viewer #{viewer}, source #{source}: wrong contact depth")
            near(sound.pan, own ? 0 : rendered_pan(state['p'][source] - state['p'][viewer]), "viewer #{viewer}, source #{source}: wrong contact position")
            near(sound.frequency, 44100 * identity_pitch(teams, source), 'contact lost its participant identity')
          end
        end
      end
    end
  end
end

check.call('doubles edge cues use the actual participant court end') do
  [[0, 0, 1, 1], [0, 1, 0, 1]].each do |teams|
    teams.each_index do |viewer|
      with_audio do |audio, program|
        state = snapshot(teams)
        teams.each_index do |source|
          state['fx'] = [[source + 1, 'edge', source, 1.0, 10.0]]
          audio.update(state, viewer: viewer, paused: true)
          name = source == viewer ? 'pong_edge' : 'pong_op_edge'
          sound = program.voice(name, source)
          assert(sound.playing?, "viewer #{viewer}, source #{source}: edge cue missing during pause")
          near(sound.volume, teams[source] == teams[viewer] ? 1.0 : 0.2, "viewer #{viewer}, source #{source}: wrong edge depth")
        end
      end
    end
  end
end

check.call('doubles footsteps use team samples and gains with each participant position and pitch') do
  [0, 0, 1, 1].permutation.to_a.uniq.each do |teams|
    teams.each_index do |viewer|
      [[100, 100], [40, 150], [150, 25], [0, 150], [150, 0]].each do |own_gain, opponent_gain|
        with_audio do |audio, program|
          program.pong_preferences.merge!('own_volume' => own_gain, 'opponent_volume' => opponent_gain,
            'announcer_volume' => 20)
          state = snapshot(teams)
          state['p'] = [2.0, 9.0, 18.0, 26.0]
          number = 0
          [false, true].each do |paused|
            teams.each_index do |source|
              state['fx'] = [[number += 1, 'step', source, 15, 10]]
              before = program.played.length
              audio.update(state, viewer: viewer, paused: paused)
              friendly = teams[source] == teams[viewer]
              name = step_asset(teams, source, viewer)
              sound = program.voice(name, source)
              steps = program.played[before..].select { |asset| %w[pong_move pong_op_move pong_move_double].include?(asset) }
              context = "teams #{teams.inspect}, viewer #{viewer}, source #{source}"
              assert(steps == [name], "#{context}: wrong footstep sample #{steps.inspect}, expected #{name}")
              volume = friendly ? 0.5 * own_gain / 100.0 : 0.2 * opponent_gain / 100.0
              volume *= movement_sample_gain(name)
              near(sound.volume, volume, "#{context}: wrong footstep volume group or baseline")
              pan = volume.zero? ? 0 : rendered_pan(state['p'][source] - state['p'][viewer])
              near(sound.pan, pan, "#{context}: footstep did not use the actual participant position")
              pitch = 1.3 - (state['p'][source].to_i - 15).abs * (0.6 / 14)
              near(sound.frequency, 44100 * pitch, "#{context}: footstep did not use the actual participant pitch")
            end
          end
        end
      end
    end
  end
end

check.call('doubles ringing movement cues follow their own participant independently') do
  [[0, 0, 1, 1], [0, 1, 0, 1]].each do |teams|
    teams.each_index do |viewer|
      with_audio do |audio, program|
        state = snapshot(teams)
        teammate = teams.each_index.find { |seat| seat != viewer && teams[seat] == teams[viewer] }
        opponents = teams.each_index.select { |seat| teams[seat] != teams[viewer] }
        sources = [[step_asset(teams, teammate, viewer), teammate],
          [step_asset(teams, opponents[0], viewer), opponents[0]], ['pong_op_edge', opponents[0]]]
        state['fx'] = [[1, 'step', teammate, 15, 10], [2, 'step', opponents[0], 15, 10],
          [3, 'edge', opponents[0], 15, 10]]
        audio.update(state, viewer: viewer, paused: false)
        sources.each do |name, source|
          assert(program.voice(name, source).playing?, "#{name}: movement cue missing for viewer #{viewer}")
          near(program.voice(name, source).pan, rendered_pan(state['p'][source] - state['p'][viewer]), "#{name}: wrong initial source for viewer #{viewer}")
        end
        state['fx'] = [[4, 'step', opponents[1], 15, 10], [5, 'step', viewer, 15, 10]]
        audio.update(state, viewer: viewer, paused: false)
        sources << [step_asset(teams, opponents[1], viewer), opponents[1]]
        sources << [step_asset(teams, viewer, viewer), viewer]
        local_voice = program.voice(step_asset(teams, viewer, viewer), viewer)
        near(local_voice.volume, 0.5 * movement_sample_gain(step_asset(teams, viewer, viewer)), 'local movement level was lost')
        near(local_voice.pan, 0, 'local movement was not centred')
        near(local_voice.frequency, 44100 * (1.3 - (state['p'][viewer].to_i - 15).abs * (0.6 / 14)), 'local movement used a teammate paddle')
        plays = sources.to_h { |name, source| [[name, source], program.voice(name, source).plays] }
        state['p'] = [24.0, 18.0, 7.0, 2.0]
        state['fx'] = []
        audio.update(state, viewer: viewer, paused: false)
        audio.tick
        sources.each do |name, source|
          sound = program.voice(name, source)
          near(sound.pan, rendered_pan(state['p'][source] - state['p'][viewer]), "#{name}: ringing cue followed the wrong source for viewer #{viewer}")
          volume = (teams[source] == teams[viewer] ? 0.5 : 0.2) * movement_sample_gain(name)
          near(sound.volume, volume, "#{name}: ringing cue changed level")
          assert(sound.plays == plays[[name, source]], "#{name}: position update replayed movement")
        end
        assert(program.voice(step_asset(teams, viewer, viewer), viewer).plays == 1 && program.voice(step_asset(teams, teammate, viewer), teammate).plays == 1,
          'teammate and local movement did not retain independent voices of the own sample')
        previous_edge_plays = program.voice('pong_op_edge', teammate).plays
        state['fx'] = [[6, 'edge', teammate, 15, 10]]
        audio.update(state, viewer: viewer, paused: false)
        sound = program.voice('pong_op_edge', teammate)
        near(sound.volume, 1.0, 'teammate edge was attenuated to the far end')
        near(sound.pan, rendered_pan(state['p'][teammate] - state['p'][viewer]), 'teammate edge used the previous opponent')
        state['p'] = [4.0, 28.0, 11.0, 22.0]
        audio.update(state, viewer: viewer, paused: false)
        near(sound.pan, rendered_pan(state['p'][teammate] - state['p'][viewer]), 'ringing teammate edge used the previous opponent')
        near(sound.volume, 1.0, 'ringing teammate edge moved to the far end')
        assert(sound.plays == previous_edge_plays + 1, 'repeated snapshot replayed teammate edge')
      end
    end
  end
end

check.call('doubles friendly footsteps track partner and self switches without replaying position updates') do
  [0, 0, 1, 1].permutation.to_a.uniq.each do |teams|
    teams.each_index do |viewer|
      with_audio do |audio, program|
        state = snapshot(teams)
        teammate = teams.each_index.find { |seat| seat != viewer && teams[seat] == teams[viewer] }
        source_plays = Hash.new(0)
        [viewer, teammate, viewer, teammate].each_with_index do |source, number|
          sound = program.voice(step_asset(teams, source, viewer), source)
          source_plays[source] += 1
          program.pong_preferences.merge!('own_volume' => 100, 'opponent_volume' => 150)
          state['fx'] = [[number + 1, 'step', source, 15, 10]]
          audio.update(state, viewer: viewer, paused: false)
          context = "teams #{teams.inspect}, viewer #{viewer}, source #{source}"
          assert(sound.plays == source_plays[source], "#{context}: friendly footstep did not use its independent own sample")
          near(sound.pan, rendered_pan(state['p'][source] - state['p'][viewer]), "#{context}: fresh footstep retained the previous source")
          pitch = 1.3 - (state['p'][source].to_i - 15).abs * (0.6 / 14)
          near(sound.frequency, 44100 * pitch, "#{context}: fresh footstep retained the previous pitch")
          sound.position = 0.375
          state['p'].reverse!
          state['fx'] = []
          program.pong_preferences['own_volume'] = 40
          audio.update(state, viewer: viewer, paused: false)
          audio.tick
          near(sound.pan, rendered_pan(state['p'][source] - state['p'][viewer]), "#{context}: ringing friendly footstep followed the wrong participant")
          near(sound.volume, 0.2 * movement_sample_gain(step_asset(teams, source, viewer)), "#{context}: ringing friendly footstep ignored the own volume control")
          near(sound.frequency, 44100 * pitch, "#{context}: position-only update changed the footstep pitch")
          near(sound.position, 0.375, "#{context}: position-only update rewound the footstep")
          assert(sound.plays == source_plays[source], "#{context}: position-only update replayed the footstep")
          program.pong_preferences['own_volume'] = 160
          audio.tick
          near(sound.volume, 0.8 * movement_sample_gain(step_asset(teams, source, viewer)), "#{context}: ringing friendly footstep lost its own baseline")
          near(sound.pan, rendered_pan(state['p'][source] - state['p'][viewer]), "#{context}: gain update restored a stale position")
          assert(sound.plays == source_plays[source], "#{context}: gain update replayed the footstep")
        end
        audio.reset
        state['p'].reverse!
        audio.update(state, viewer: viewer, paused: true)
        [viewer, teammate].each do |source|
          voice = program.voice(step_asset(teams, source, viewer), source)
          assert(!voice.playing? && voice.plays == 2, 'reset resumed a stale friendly footstep')
        end
        state['fx'] = [[1, 'step', viewer, 15, 10]]
        audio.update(state, viewer: viewer, paused: true)
        sound = program.voice(step_asset(teams, viewer, viewer), viewer)
        near(sound.pan, 0, 'first footstep after reset retained the teammate position')
        assert(sound.plays == 3, 'reset did not accept the new footstep sequence')
      end
    end
  end
end

check.call('doubles echo remains anchored to the local participant paddle') do
  [[0, 0, 1, 1], [0, 1, 0, 1]].each do |teams|
    teams.each_index do |viewer|
      with_audio do |audio, program|
        state = snapshot(teams)
        state['p'] = [1.0, 29.0, 8.0, 22.0]
        audio.cycle_echo
        audio.update(state, viewer: viewer, paused: true)
        [-1, 1].each do |direction|
          edge = direction.negative? ? 1.0 : 29.0
          distance = (state['p'][viewer] - edge).abs
          sound = program.sounds["pong_echo_noise_#{direction.negative? ? 'left' : 'right'}"]
          level = [30.0 - distance * 2, 0].max / 100
          near(sound.volume, level, "viewer #{viewer}: echo used another paddle")
          near(sound.pan, level.zero? ? 0 : rendered_pan(distance * direction), "viewer #{viewer}: echo used another edge")
        end
      end
    end
  end
end

check.call('doubles shield toggles belong to the team while impacts retain participant identity') do
  [[0, 0, 1, 1], [0, 1, 0, 1]].each do |teams|
    teams.each_index do |viewer|
      with_audio do |audio, program|
        state = snapshot(teams)
        number = 0
        teams.each_index do |source|
          %w[shield_on shield_off shield_hit].each do |kind|
            own = kind == 'shield_hit' ? source == viewer : teams[source] == teams[viewer]
            x = state['p'][source]
            state['fx'] = [[number += 1, kind, source, x, teams[source].zero? ? 0 : 20]]
            audio.update(state, viewer: viewer, paused: false)
            name = program.played.last
            if kind == 'shield_hit'
              assert(name.start_with?(own ? 'pong_own_shield_hit' : 'pong_op_shield_hit'), 'shield impact confused teammate and local paddle')
              near(program.sounds[name].volume, own ? 1.0 : 0.91, 'shield impact gain changed')
              near(program.sounds[name].pan, rendered_pan(x - state['p'][viewer]), 'shield impact used the wrong paddle position')
              near(program.sounds[name].frequency, 44100 * identity_pitch(teams, source), 'shield return lost its participant identity')
            else
              assert(name == "pong_#{own ? '' : 'op_'}#{kind}", 'shield toggle did not identify the protected team')
              near(program.sounds[name].volume, own ? 1.0 : 0.24, 'shield toggle gain changed')
              near(program.sounds[name].pan, 0, 'shield toggle pan changed')
              near(program.sounds[name].frequency, 44100 * (own ? 1 : 0.9438743126816935), 'shield toggle pitch changed')
            end
          end
        end
      end
    end
  end
end

check.call('doubles point and goal APIs still accept teams for score order and wins') do
  [[0, 0, 1, 1], [0, 1, 0, 1]].each do |teams|
    teams.each_index do |viewer|
      [0, 1].each do |winner|
        now = 0.0
        with_audio(clock: -> { now }) do |audio, program|
          state = snapshot(teams)
          state['fx'] = [[1, 'goal', winner, 15, 20]]
          audio.update(state, viewer: viewer, paused: true)
          audio.goal(viewer: teams[viewer], winner: winner)
          goals = GameRoomPong::Audio::GOALS.sum { |name| program.sounds[name].plays }
          assert(goals == 1, 'team goal was lost or duplicated')
          audio.point([7, 3], viewer: teams[viewer], winner: winner, finished: true, goal_at: now)
          assert(GameRoomPong::Audio::GOALS.sum { |name| program.sounds[name].plays } == goals, 'durable point repeated the agreed goal')
          program.played.clear
          scores = teams[viewer].zero? ? [7, 3] : [3, 7]
          ordered = ['pong_scores', *scores.map { |score| "pong_number#{score}" }]
          result = teams[viewer] == winner ? 'pong_youwin' : 'pong_theywin'
          expected = [*ordered, result, *ordered]
          # Each recording now gates the next on its own announced length, not a
          # fixed guess, so drain the queue by ticking until it catches up.
          120.times do
            now += 0.25
            audio.tick
            break if program.played.length >= expected.length
          end
          assert(program.played == expected, "viewer #{viewer}: wrong team score/result #{program.played.inspect}")
        end
      end
    end
  end
end

check.call('only move-double has a stable extra -3 dB for every listener and participant') do
  [0, 0, 1, 1].permutation.to_a.uniq.each do |teams|
    teams.each_index do |viewer|
        with_audio do |audio, program|
          state = snapshot(teams)
          state['p'] = [15.0] * 4
          state['fx'] = teams.each_index.map { |source| [source + 1, 'step', source, 15, teams[source] * 20] }
          audio.update(state, viewer: viewer, paused: false)
          [1.0, 0.6, 1.0].each do |gain|
            program.sound_gain = gain
            3.times { audio.tick }
            teams.each_index do |source|
              asset = step_asset(teams, source, viewer)
              voice = program.voice(asset, source)
              baseline = (teams[source] == teams[viewer] ? 0.5 : 0.2) * gain
              expected_db = asset == 'pong_move_double' ? -3.0 : 0.0
              near(20 * Math.log10(voice.volume / baseline), expected_db, "#{asset}: incorrect or cumulative attenuation")
              near(voice.frequency, 44100 * 1.3, "#{asset}: volume trim changed pitch")
              assert(voice.plays == 1, "#{asset}: volume trim replayed a step")
            end
          end
        end
    end
  end
end

abort(failures.join("\n")) unless failures.empty?
puts "PASS #{checks} doubles audio checks (stub sound handles, no device playback)"
