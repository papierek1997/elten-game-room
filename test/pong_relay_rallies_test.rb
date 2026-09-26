require_relative 'support/pong_relay'

def await_relay(rig, label, limit: 2000)
  limit.times do
    return if yield
    rig.advance(1)
  end
  raise "scheduled relay stalled: #{label}"
end

[
  [%w[Alice Bob], [0, 1], false],
  [%w[Alice Bob Carol Dave], [0, 0, 1, 1], false],
  [%w[Alice Bob Carol Dave], [0, 1, 0, 1], true],
  [%w[Bob Carol Dave Erin], [0, 0, 1, 1], false],
  [['Alice', 'bot:7:1'], [0, 1], false],
  [['Bob', 'bot:7:1'], [0, 1], true],
  [['Alice', 'Bob', 'Carol', 'bot:7:1'], [0, 0, 1, 1], false],
  [['Bob', 'bot:7:1', 'Carol', 'bot:7:2'], [0, 0, 1, 1], true],
  [['bot:7:1', 'Bob', 'bot:7:2', 'bot:7:3'], [0, 1, 0, 1], true]
].each do |players, teams, arcade|
  rig = PongRelayFixture.new(players: players, teams: teams, options: {'arcade' => arcade})
  begin
    rig.one_way = ->(from, to, packet) {
      if packet['k'] != 'event' && packet['n'] % 7 == 0
        :drop
      else
        0.02 + ((from.ord + to.ord + packet['n']) % 5) * 0.02 + (to == players.last ? 0.12 : 0)
      end
    }
    h, host, served = rig.h, rig.h.clients['Alice'], []
    8.times do |rally|
      await_relay(rig, "ready #{rally}") { h.clients.values.none?(&:paused) }
      server = players[host.engine.server]
      served << server
      h.press(server) unless GameRoomParticipants.bot?(server)
      await_relay(rig, 'serve') { h.clients.values.all? { |c| c.engine.turn == 1 } }
      rig.advance(12, names: h.clients.keys - ['Alice']) # a bounded owner UI gap, without a fake disconnection
      4.times do |index|
        turn = index + 1
        side = host.engine.rotation.hitter(turn)
        bot = GameRoomParticipants.bot?(players[side])
        actor = h.clients.fetch(bot ? 'Alice' : players[side])
        distance = bot ? -0.01 : 3.0
        actor.engine.ball.merge!('x' => actor.engine.paddles[side],
          'y' => actor.engine.rotation.team(side).zero? ? distance : 20.0 - distance)
        h.press(players[side]) unless bot
        await_relay(rig, "return #{index}") { h.clients.values.all? { |c| c.engine.turn == turn + 1 } }
        assert(h.clients.values.all? { |c| c.engine.goal == nil }, 'delay created a false goal')
      end
      await_relay(rig, 'effect delivery') do
        h.network.values.all? do |channel|
          channel.instance_variable_get(:@event_outbox).empty? &&
            channel.instance_variable_get(:@deliveries).empty? &&
            !channel.instance_variable_get(:@event_work).busy?
        end
      end
      loser = host.engine.rotation.hitter(host.engine.turn)
      # Make the terminal fixture an actual unprotected miss. Otherwise a
      # valid Arcade shield returns it and the following player can lose.
      h.clients.each_value do |client|
        client.engine.rotation.members(teams[loser]).each { |seat| client.engine.shields[seat] = 0 }
      end
      losing = h.clients[GameRoomParticipants.bot?(players[loser]) ? 'Alice' : players[loser]].engine
      losing.ball.merge!('x' => losing.paddles[loser] < 15 ? 29.0 : 1.0,
        'y' => host.engine.rotation.team(loser).zero? ? -0.01 : 20.01)
      await_relay(rig, 'goal agreement') { host.context_data['pong_point'] != nil }
      winner = 1 - host.engine.rotation.team(loser)
      assert(host.context_data['pong_point'] == "#{rally}:#{winner}",
        "agreed goal did not match forced unshielded miss: expected=#{rally}:#{winner} actual=#{host.context_data['pong_point']} turn=#{host.engine.turn} shields=#{host.engine.shields.inspect}")
      assert(h.clients.values.all? { |c| c.engine.goal == winner }, 'point proposed without agreement')
      h.accept_point(host.context_data['pong_point'])
    end
    assert(served.uniq.sort == players.sort, 'service rotation did not cover every real player')
    assert(h.network.values.all? { |c| c.instance_variable_get(:@generation) == 0 }, 'normal delayed play caused recovery')
    assert(rig.transmissions.all? { |t| JSON.generate(t[:packet]).bytesize <= GameRoomRealtime::Protocol::MAX_BYTES }, 'packet bound increased')
    puts "PASS scheduled #{players.count { |p| !GameRoomParticipants.bot?(p) }}-human relay/#{players.length} seats: teams=#{teams.inspect}, arcade=#{arcade}, owner_observer=#{!players.include?('Alice')}, eight rallies/all server seats, jitter 20-220ms, RPC 120ms, 1/7 positions dropped, owner UI gaps"
  ensure
    rig.close
  end
end
