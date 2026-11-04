require_relative '../support/recordings'
require_relative '../support/pong_audio'
require_relative '../../lib/recordings/renderer'
include RecordingTest

# Native handles also expose these playback-only properties.
class PongSound
  attr_accessor :tempo
  def closed?; @closed==true; end
end

module RecordingRallyResetTest
  module_function

  def document(doubles:, paused:)
    players = doubles ? %w[Alice Bob Carol Dave] : %w[Alice Bob]
    meta = GameRoomRecordings::Document.metadata(game: 'axel_pong', game_name: 'Axel Pong',
      players: players, complete_start: false)
    meta['duration_ms'] = 1500
    scene = RecordingTest.scene
    scene['b']['y'] = 10.0
    if doubles
      scene.merge!('p'=>[15.0]*4, 'shields'=>[0]*4, 'edges'=>[0]*4, 'teams'=>[0,1,0,1])
    end
    context = RecordingTest.context.merge('players'=>players, 'teams'=>doubles ? [0,1,0,1] : [0,1])
    frame = ->(time, generation, effects, stopped) {
      snapshot = GameRoomRecordings::Document.copy(scene)
      snapshot['fx'] = effects
      snapshot['b']['dy'] = 0.0 if stopped
      {'t'=>time, 'kind'=>'frame', 'data'=>context.merge('snapshot'=>snapshot,
        'generation'=>generation, 'rally'=>generation, 'paused'=>stopped,
        'scores'=>[[0,0],[0,1],[1,1]][generation])}
    }
    audio = ->(time, method, args, keys) {
      {'t'=>time, 'kind'=>'audio', 'data'=>{'method'=>method, 'args'=>args, 'kwargs'=>keys}}
    }
    GameRoomRecordings::Document.header(meta).merge('timeline'=>[
      frame.call(0, 0, [[40,'hit',1,15.0,20.0]], paused),
      audio.call(100, 'goal', [], {'viewer'=>0,'winner'=>1}),
      audio.call(150, 'point', [[0,1]], {'viewer'=>0,'winner'=>1,'finished'=>false,'goal_at'=>0.1}),
      audio.call(200, 'reset', [], {}),
      frame.call(240, 1, [], true),
      frame.call(400, 1, [[1,'serve',0,15.0,0.0]], false),
      frame.call(500, 1, [[1,'serve',0,15.0,0.0],[2,'hit',1,15.0,20.0]], false),
      audio.call(800, 'goal', [], {'viewer'=>0,'winner'=>0}),
      audio.call(850, 'point', [[1,1]], {'viewer'=>0,'winner'=>0,'finished'=>false,'goal_at'=>0.8}),
      audio.call(900, 'reset', [], {}),
      frame.call(940, 2, [], true),
      frame.call(1100, 2, [[1,'serve',1,15.0,20.0]], false),
      frame.call(1200, 2, [[1,'serve',1,15.0,20.0],[2,'hit',0,15.0,0.0]], false)
    ])
  end

  def player(value, now)
    renders = []
    player = GameRoomRecordings::Player.new(value, clock: now, renderer: ->(clock) {
      program = PongAudioProgram.new
      audio = GameRoomPong::Audio.new(program, clock: clock)
      audio.load
      renders << [program, audio]
      GameRoomRecordings::Renderer.new(audio)
    })
    [player, renders]
  end

  def hits(audio)
    # Doubles has independent voices for one asset. The program fixture's
    # asset lookup keeps only its last voice; inspect the renderer's handles.
    audio.instance_variable_get(:@sounds).sum { |name,sound| /\Apong_(?:op_)?hit(?::\d+)?\z/.match?(name) ? sound.plays : 0 }
  end
end
Rally = RecordingRallyResetTest
prepared = GameRoomRecordings::Prepared.copy(Rally.document(doubles: false, paused: true))
resets=prepared.scene_changes.select { |i| prepared.document['timeline'][i]['data']['method']=='reset' }
assert(prepared.scene_changes.frozen? && resets.map { |i| prepared.document['timeline'][i]['t'] }==[200,900],
  'Scene/reset boundaries were not indexed immutably with the prepared recording')

# Use the real Pong renderer and passive player, with sound handles only
# replaced by counters. Do not run physics or open a server session.
[false,true].each do |doubles|
  [false,true].each do |paused|
    [0, doubles ? 3 : 1].each do |seat|
      now = 0.0
      player, renders = Rally.player(Rally.document(doubles: doubles, paused: paused), -> {now})
      player.seat = seat
      player.play
      [0.1,0.15,0.2].each { |time| now=time; player.tick }
      program, audio = renders.last
      assert(audio.instance_variable_get(:@last_effect)==0, 'Reset consumed an effect from the previous rally')
      assert(!program.sounds['pong_ball'].playing?, 'Reset resumed the previous rally flight')
      [0.24,0.4,0.5].each { |time| now=time; player.tick }
      assert(Rally.hits(audio)==2, 'The first serve or return after a goal is missing')
      assert(program.sounds['pong_ball'].playing?, 'The new rally flight is missing')
      now=0.6;player.tick
      assert(Rally.hits(audio)==2, 'An unchanged frame replayed an impact')
      [0.8,0.85,0.9].each { |time| now=time; player.tick }
      assert(audio.instance_variable_get(:@last_effect)==0 && Rally.hits(audio)==2,
        'The second reset reused effects from the preceding rally')
      [0.94,1.1,1.2].each { |time| now=time; player.tick }
      assert(Rally.hits(audio)==4, 'The second rally lost or duplicated a serve/return')
      player.close
    end
  end
end

# Seeking/recreating the renderer inside the gap must retain score information,
# but must not prime or resume an obsolete scene. Include exact reset time.
[200,220,240].each do |position|
  now=0.0
  player, renders = Rally.player(Rally.document(doubles: false, paused: false), -> {now})
  player.seek(position)
  assert(player.frame['scores']==[0,1], 'Seeking across a reset lost the confirmed score')
  player.play
  program, audio = renders.last
  assert(Rally.hits(audio)==0 && !program.sounds['pong_ball'].playing?, 'Seeking into a reset gap resumed the old scene')
  player.pause
  player.speed=2.0
  player.seat=1
  player.play
  program, audio = renders.last
  assert(Rally.hits(audio)==0, 'Resuming after a gap seek replayed an old impact')
  now=(510-position)/2000.0
  player.tick
  assert(Rally.hits(audio)==2, 'Playback after a gap seek lost the next serve/return')
  player.close
end
puts 'PASS replay rally resets: delayed frames, two goals, singles/doubles, both perspectives, paused/flying old scenes, exact/gap seeks, pause/resume and speed changes'
