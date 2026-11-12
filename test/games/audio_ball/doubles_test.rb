require_relative '../../support/audio_ball_relay'

[[0,1,0,1],[0,0,1,1],[1,0,1,0]].each do |teams|
  4.times do |server|
    engine=GameRoomAudioBall::Engine.new(level:3,server:server,teams:teams)
    8.times do |offset|
      seat=GameRoomAudioBall::Rotation.seat(teams,server,offset)
      assert(engine.holder==seat,'Teammate rotation changed')
      assert(engine.press(seat,'prepare'),'Active player could not prepare')
      assert(engine.press(seat,'up'),'Active player could not return')
      receiver=GameRoomAudioBall::Rotation.seat(teams,server,offset+1)
      assert(engine.receiver==receiver,'Return went to the wrong partner')
      copy=GameRoomAudioBall::Engine.new(level:3,server:server,teams:teams)
      assert(copy.restore(engine.snapshot),'Four-seat flight snapshot rejected')
      assert(copy.snapshot==engine.snapshot,'Restoring changed the flight')
      engine.step(engine.duration,controlled:[receiver],defenses:{receiver=>'up'})
    end
    assert(4.times.none? { |seat| engine.wrong_turn(seat) }, 'A key during preparation awarded a point')
    engine.press(engine.holder, 'prepare')
    assert(4.times.none? { |seat| engine.wrong_turn(seat) }, 'A key before the serve awarded a point')
    engine.press(engine.holder, 'up')
    receiver = engine.receiver
    wrong=(0...4).find { |seat| seat != receiver && teams[seat] == teams[receiver] }
    (0...4).reject { |seat| seat == wrong }.each do |seat|
      assert(!engine.wrong_turn(seat), 'An active defender or opposing player was penalized')
      assert(!engine.apply('action' => 'wrong_turn', 'side' => seat, 'turn' => engine.turn + 1),
        'An invalid remote fault bypassed the receiver/team guard')
    end
    missed = GameRoomAudioBall::Engine.new(level:3, server:server, teams:teams)
    assert(missed.restore(engine.snapshot), 'Could not restore a live doubles flight')
    missed.step(missed.duration, controlled:[receiver])
    late = {'action' => 'wrong_turn', 'side' => wrong, 'turn' => missed.turn}
    opponent = (0...4).find { |seat| teams[seat] != teams[receiver] }
    assert(!missed.apply(late.merge('side' => opponent)), 'Late fault accepted an opposing player')
    assert(missed.apply(late), 'Same-flight teammate fault could not replace a competing miss')
    assert(missed.goal == 1 - teams[receiver], 'Late fault changed the team awarded the point')
    assert(engine.wrong_turn(wrong),'Wrong-turn press did not end the rally')
    assert(engine.goal==1-teams[wrong],'Wrong-turn point awarded to the wrong team')
    copy=GameRoomAudioBall::Engine.new(level:3,server:server,teams:teams)
    assert(copy.restore(engine.snapshot),'Wrong-turn result snapshot rejected')
    assert(!copy.restore(engine.snapshot.merge('fault' => opponent, 'goal' => 1 - teams[opponent])),
      'A snapshot allowed an opposing player to cause a wrong-turn goal')
  end
end

%w[Alice Watcher].each do |owner|
  h=AudioBallRelayHarness.new(players:%w[Alice Bob Carol Dave],owner:owner,
    options:{'team_size'=>2,'sets_to_win'=>2},server:2)
  h.wait_ready
  assert(h.clients.values.all?{|c|c.engine.server==2},'Random first server was lost')
  h.press('Alice','up')
  assert(h.clients.values.all? { |client| client.engine.goal.nil? }, 'Inactive input before service awarded a point')
  h.press('Carol','prepare','up')
  h.press('Alice','up')
  h.press('Bob','prepare')
  assert(h.clients.values.all? { |client| client.engine.goal.nil? }, 'Input outside a teammate defence awarded a point')
  # A real defence press by Dave's partner reaches the owner as a request and
  # produces one agreed point; observers cannot create such a request.
  h.press('Bob','up')
  800.times {h.advance;break if h.clients[owner].context_data['audio_ball_point']}
  assert(h.clients[owner].context_data['audio_ball_point']=='0:0','Wrong-turn request did not agree')
  assert(h.clients.values.all?{|c|c.engine.goal==0},'Peers disagree on the wrong-turn point')
  # Agreement queues the reliable presentation event; let recipients receive it
  # before asserting their cue, without injecting any acknowledgement or sound.
  800.times do
    h.advance
    break if h.audios.values.all? { |audio| audio.calls.any? { |call| call.first == :goal } }
  end
  assert(h.audios.values.all?{|audio|audio.calls.select{|call|call.first==:goal}.map{|call|call[1][:reason]}==['wrong_turn']},
    'An agreed wrong-turn goal did not select the replacement sound on every client')
  h.commit
  assert(h.replay.state[:scores]==[1,0],'One bad press did not score exactly once')
  assert(h.audios.values.all?{|audio|audio.calls.count{|call|call.first==:goal}==1},'Durable point repeated a goal sound')
  h.wait_ready
  assert(h.clients.values.all?{|c|c.engine.server==2},'Service changed before two points')
  h.press('Watcher','up')
  h.advance(8)
  assert(h.clients[owner].engine.goal.nil?,'Observer input awarded a point')
  # A normal serve and missed defence use the existing durable result path.
  h.press('Carol','prepare','up')
  1000.times {h.advance;break if h.clients[owner].context_data['audio_ball_point']}
  assert(h.clients[owner].context_data['audio_ball_point']=='1:0','Ordinary doubles point failed')
  800.times do
    h.advance
    break if h.audios.values.all? { |audio| audio.calls.count { |call| call.first == :goal } == 2 }
  end
  assert(h.audios.values.all?{|audio|audio.calls.select{|call|call.first==:goal}.last[1][:reason].nil?},
    'An ordinary goal inherited the preceding wrong-turn sound')
  h.commit
  assert(h.replay.state[:server]==3,'Third point did not rotate service')
  assert(h.game.participant_scores(h.replay)=={'Alice'=>0,'Bob'=>0,'Carol'=>0,'Dave'=>0},'A multi-set match must rank by completed sets')
  assert(h.game.tournament_export_small_scores(h.replay,options:h.replay.state[:options])[:scores]=={'team:0'=>2,'team:1'=>0},'Small scores must use one value per team unit')
  h.close
  assert(h.rig.endpoints.values.all?(&:closed?),'Doubles leaked a channel')
end
bot_players=['Alice','Bob',GameRoomParticipants.bot_id(20,1),GameRoomParticipants.bot_id(20,2)]
mixed=AudioBallRelayHarness.new(players:bot_players,owner:'Watcher',options:{'team_size'=>2},server:2)
mixed.wait_ready
2000.times {mixed.advance;break if mixed.clients['Watcher'].context_data['audio_ball_point']}
assert(mixed.clients['Watcher'].context_data['audio_ball_point'],'A doubles bot at seat 2 could not serve with a spectator owner')
mixed.commit
assert(mixed.replay.state[:rally]==1,'The mixed human/bot doubles point did not commit')
mixed.close

engine=GameRoomAudioBall::Engine.new(level:5,server:2,teams:[0,1,0,1])
bots=4.times.map{|seat|GameRoomAudioBall::Bot.new(seat,level:5,rng:Random.new(seat+10))}
2000.times do
  bots.each{|bot|bot.step(engine,seconds:0.016)}
  defenses=bots.to_h{|bot|[bot.side,bot.selected_lane(engine)]}.compact
  engine.step(0.016,controlled:[0,1,2,3],defenses:defenses)
  break if engine.goal || engine.hits>=8
end
assert(engine.hits>=4,'The ordinary bot logic failed to rotate through all four seats')
puts 'PASS doubles: every seat/team layout, normal returns, snapshots, wrong-turn fields, mixed bots, spectator host, agreement, scoring and two-point service'
