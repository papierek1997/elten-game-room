require_relative '../lib/axel_pong/peer_engine'
require_relative '../lib/axel_pong/bot'

def assert(value, message); raise message unless value; end

assert(GameRoomPong::Engine.instance_method(:initialize).parameters.include?([:key, :teams]),
  'owner engine has no doubles team layout')
[[0, 0, 1, 1], [0, 1, 0, 1]].each do |teams|
  engine = GameRoomPong::Engine.new(teams: teams)
  assert(engine.rotation.teams == teams && engine.turn == 0, 'owner engine has no initial rotation turn')
  state = engine.snapshot
  assert(state['teams'] == teams && state['receiver'] == engine.rotation.receiver, 'doubles snapshot lost the receiving player')
  %w[p shields edges].each { |key| assert(state[key].length == 4, "doubles snapshot truncated #{key}") }
  engine.step(Array.new(4) { {'move' => 1} })
  assert(engine.paddles == [16.0] * 4, 'inactive partners cannot move during play')
  engine.position([5, 10, 20, 25].map { |x| {'paddle' => x} })
  assert(engine.paddles == [5, 10, 20, 25], 'inactive partners cannot move between rallies')
  next_engine = GameRoomPong::Engine.new(teams: teams, rally: 1, paddles: engine.paddles,
    shields: [100, 200, 300, 400], movement_feedback: engine.movement_feedback)
  assert(next_engine.paddles == [5, 10, 20, 25] && next_engine.shields == [100, 200, 300, 400],
    'player-owned state was lost between doubles rallies')
end
singles = GameRoomPong::Engine.new.snapshot
assert(singles.keys.sort == %w[b edges fx goal invisible p server shields tick], 'singles wire shape changed')

[[0, 0, 1, 1], [0, 1, 0, 1], [1, 0, 1, 0]].each do |teams|
  [0, 1].each do |first|
    16.times do |rally|
      engine = GameRoomPong::Engine.new(teams: teams, rally: rally, first_server: first, rng: Random.new(32))
      court = teams[engine.server]
      reference = GameRoomPong::Engine.new(first_server: court, rng: Random.new(32))
      assert(engine.ball == reference.ball, 'serve was positioned on the participant index instead of their team')
      9.times do |turn|
        side = engine.rotation.hitter(turn)
        court = teams[side]
        if turn > 0
          [engine, reference].each { |e| e.ball.merge!('x' => 17.0, 'y' => court.zero? ? 3.0 : 17.0) }
        end
        before = Marshal.dump([engine.snapshot, engine.turn])
        (teams.each_index.to_a - [side]).each do |wrong|
          assert(!engine.strike(wrong, force: true), 'a teammate returned out of order')
          assert(Marshal.dump([engine.snapshot, engine.turn]) == before, 'rejected hitter changed the flight')
        end
        assert(engine.strike(side) && reference.strike(court), 'designated doubles hitter cannot return')
        assert(engine.turn == turn + 1, 'owner engine did not increment exactly once per return')
        assert(engine.ball == reference.ball, 'doubles strike changed the singles physics')
        next_side = engine.rotation.hitter(engine.turn)
        assert(teams.each_index.select { |seat| engine.incoming?(seat) } == [next_side], 'incoming includes a non-designated partner')
        teams.each_index do |seat|
          assert(engine.distance_to(seat) == reference.distance_to(teams[seat]), 'distance used participant instead of court')
        end
      end
    end
  end
end
peer = GameRoomPong::PeerEngine.new(side: 0, authority: true)
assert(peer.strike(0) && peer.turn == 1 && peer.take_transition['turn'] == 1, 'peer counted serve twice')

[[0, 0, 1, 1], [0, 1, 0, 1]].each do |teams|
  [0, 1].each do |first|
    (1..4).each do |turn|
      %i[automatic held shield partner_automatic partner_held miss].each do |mode|
        engine = GameRoomPong::Engine.new(teams: teams, first_server: first, arcade: true)
        turn.times do |index|
          side = engine.rotation.hitter(index)
          engine.ball['y'] = teams[side].zero? ? 3.0 : 17.0 if index > 0
          assert(engine.strike(side), 'contact fixture could not advance the hitter ring')
        end
        side = engine.rotation.hitter(turn)
        partner = (engine.rotation.members(teams[side]) - [side]).first
        engine.shields.fill(0)
        engine.instance_variable_set(:@invisible, true)
        engine.paddles[side] = 25.0
        engine.ball.merge!('x' => 15.0, 'y' => teams[side].zero? ? 0.5 : 19.5)
        inputs = Array.new(4) { {} }
        case mode
        when :automatic
          engine.automatic_for(side, true)
          engine.paddles[side] = 15.0
        when :held
          inputs[side] = {'hit' => true}
          engine.paddles[side] = 15.0
        when :shield
          [side, partner].each { |member| engine.shields[member] = 100 }
        when :partner_automatic
          engine.automatic_for(partner, true)
        when :partner_held
          inputs[partner] = {'hit' => true}
        end
        engine.step(inputs)
        assert(engine.turn == turn + 1, "#{mode} did not consume exactly one designated contact")
        if [:automatic, :held, :shield].include?(mode)
          assert(engine.goal.nil? && engine.incoming?(engine.rotation.hitter(turn + 1)), "#{mode} did not advance to the next partner")
          if mode == :shield
            assert([side, partner].all? { |member| engine.shields[member] == 99 } && engine.invisible,
              'team shield timer or invisibility changed')
            assert(engine.ball['y'] == (teams[side].zero? ? 1.0 : 19.0), 'shield returned from the wrong baseline')
            assert(engine.events.last[1, 2] == ['shield_hit', side], 'shield cue identified the court instead of the player')
          end
        else
          assert(engine.goal == 1 - teams[side], "#{mode} let the wrong partner save the ball or scored for a participant")
          assert(engine.events.last[1, 2] == ['goal', 1 - teams[side]], 'goal cue did not identify the winning team')
          frozen = Marshal.dump([engine.snapshot, engine.turn])
          engine.step(inputs)
          assert(Marshal.dump([engine.snapshot, engine.turn]) == frozen, 'goal was counted more than once')
        end
      end
    end
  end
end
[0, 1].product([false, true]).each do |side, shield|
  engine = GameRoomPong::Engine.new
  engine.ball.merge!('x' => 1.0, 'y' => side.zero? ? 0.0 : 20.0, 'dy' => side.zero? ? -1 : 1, 'speed' => 0.1)
  engine.shields[side] = 100 if shield
  engine.step([{}, {}])
  assert(engine.turn == 1 && (shield ? engine.goal.nil? : engine.goal == 1 - side), 'singles direct-ball contacts lost their turn')
end

[0, 1].each do |first|
  [false, true].each do |served|
    peer = GameRoomPong::PeerEngine.new(side: first, authority: true, first_server: first)
    peer.strike(first) if served
    assert(peer.serve_timeout(confirmed: served), 'authoritative serve timeout was rejected')
    assert(peer.turn == 1 && peer.goal == 1 - first && peer.take_transition.nil?, 'serve timeout counted twice or retained a late serve')
    assert(!peer.serve_timeout(confirmed: true) && peer.turn == 1, 'duplicate timeout changed the turn')
  end
  server = GameRoomPong::PeerEngine.new(side: first, authority: true, first_server: first)
  receiver = GameRoomPong::PeerEngine.new(side: 1 - first, authority: false, first_server: first)
  server.strike(first)
  assert(receiver.apply_return(server.take_transition), 'miss fixture rejected the serve')
  receiver.ball.merge!('x' => 1.0, 'y' => first.zero? ? 20.0 : 0.0)
  receiver.step([{}, {}])
  message = receiver.take_transition
  assert(message['turn'] == 2 && message['action'] == 'goal', 'local miss transition counted twice')
  assert(server.apply_miss(message) && server.turn == 2 && server.goal == first, 'remote miss counted twice')
  assert(!server.apply_miss(message) && server.turn == 2, 'duplicate miss changed the turn')
end

[[0, 0, 1, 1], [0, 1, 0, 1]].each do |teams|
  [0, 1].each do |first|
    16.times do |rally|
      peers = (0..3).map do |side|
        GameRoomPong::PeerEngine.new(teams: teams, side: side, authority: side == 0,
          rally: rally, first_server: first)
      end
      peers << GameRoomPong::PeerEngine.new(teams: teams, side: nil, authority: false,
        rally: rally, first_server: first)
      rotation = peers.first.rotation
      9.times do |turn|
        side = rotation.hitter(turn)
        actor = peers[side]
        peers.each_with_index do |engine, local|
          next if local == side
          assert(!engine.strike(side), 'a peer struck another participant paddle')
          assert(!engine.strike(local), 'an inactive teammate struck locally') if local < 4
          if turn > 0
            engine.ball['y'] = teams[side].zero? ? 0.0 : 20.0
            engine.step(Array.new(4) { {} })
            assert(engine.turn == turn && engine.goal.nil? && engine.take_transition.nil?, 'non-contact peer decided a return or miss')
          end
        end
        if turn > 0 && turn.even?
          actor.ball.merge!('x' => 1.0, 'y' => teams[side].zero? ? 0.5 : 19.5)
          actor.shields[side] = 100
          actor.step(Array.new(4) { {} })
        else
          actor.ball.merge!('x' => 15.0, 'y' => teams[side].zero? ? 3.0 : 17.0) if turn > 0
          assert(actor.strike(side), 'designated local peer could not return')
        end
        message = actor.take_transition
        assert(message && message['side'] == side && message['turn'] == turn + 1, 'peer transition skipped a turn or participant')
        peers.each_with_index do |engine, local|
          next if local == side
          before = Marshal.dump([engine.snapshot, engine.turn])
          wrong = (rotation.members(teams[side]) - [side]).first
          assert(!engine.apply_return(message.merge('side' => wrong)), 'remote teammate returned out of order')
          assert(!engine.apply_return(message.merge('turn' => turn + 2)), 'future remote return skipped a turn')
          assert(Marshal.dump([engine.snapshot, engine.turn]) == before, 'rejected remote return changed state')
          assert(engine.apply_return(message), 'legal remote doubles return was rejected')
          assert(engine.turn == turn + 1, 'remote doubles return incremented twice')
          assert(engine.ball['dy'] == (teams[side].zero? ? 1 : -1), 'remote return used a participant as court direction')
          assert(engine.ball['y'] == (teams[side].zero? ? 0.0 : 20.0), 'remote return did not restart at the far team baseline')
          assert(!engine.apply_return(message), 'duplicate remote return was applied twice')
        end
      end
      side = rotation.hitter(peers.first.turn)
      actor = peers[side]
      actor.shields.fill(0)
      actor.ball.merge!('x' => 1.0, 'y' => teams[side].zero? ? 0.0 : 20.0)
      actor.step(Array.new(4) { {} })
      message = actor.take_transition
      peers.each_with_index do |engine, local|
        next if local == side
        wrong = (rotation.members(teams[side]) - [side]).first
        assert(!engine.apply_miss(message.merge('side' => wrong)), 'wrong teammate reported a miss')
        assert(engine.apply_miss(message) && engine.turn == 10 && engine.goal == 1 - teams[side], 'doubles miss did not converge on the winning team')
      end
      server = rotation.server
      timeout = GameRoomPong::PeerEngine.new(teams: teams, side: server, authority: false,
        rally: rally, first_server: first)
      timeout.strike(server)
      assert(timeout.serve_timeout(confirmed: true) && timeout.turn == 1 && timeout.goal == 1 - teams[server], 'late doubles serve escaped the confirmed timeout')
    end
  end
end

[[0, 0, 1, 1], [0, 1, 0, 1]].each do |teams|
  [0, 1].each do |first|
    16.times do |rally|
      [[0, 1, 2, 3], [1, 2, 3], [0, 1, 2], [0, 2], [1, 3], [0], [3]].each do |bots|
        engine = GameRoomPong::Engine.new(teams: teams, first_server: first, rally: rally,
          bots: bots, rng: Random.new(19), level: 3)
        bots.each { |side| GameRoomPong::Bot.new(side, level: 3, rng: Random.new(side)).step(engine) }
        if bots.include?(engine.server)
          500.times do
            engine.step(Array.new(4) { {} })
            break if engine.turn > 0
          end
          assert(engine.turn == 1 && engine.events.any? { |fx| fx[1, 2] == ['serve', engine.server] }, 'owner bot did not serve its doubles block')
        else
          assert(engine.strike(engine.server), 'mixed match human could not serve')
        end
        8.times do
          turn = engine.turn
          side = engine.rotation.hitter(turn)
          engine.paddles[side] = 15.0
          engine.ball.merge!('x' => 15.0, 'y' => teams[side].zero? ? 0.0 : 20.0)
          inputs = Array.new(4) { {} }
          inputs[side] = {'hit' => true} unless bots.include?(side)
          engine.step(inputs)
          assert(engine.goal.nil? && engine.turn == turn + 1, 'mixed owner engine skipped a designated bot or human')
          assert(engine.events.any? { |fx| fx[1, 2] == ['hit', side] }, 'mixed owner engine credited the wrong hitter')
        end
      end
    end
  end
end

puts 'PASS Pong doubles engine: ordered owner/peer contacts, arbitrary seats, singles physics, team shields, remote rejection, turn counters and mixed/all-bot rallies'
