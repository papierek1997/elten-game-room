require_relative '../lib/axel_pong/peer_engine'
require_relative '../lib/axel_pong/bot'

def assert(value, message); raise message unless value; end

class TeamShieldRandom
  attr_accessor :value
  def initialize; @value = 0.5; end
  def rand(*_args); @value; end
end

layouts = [0, 0, 1, 1].permutation.to_a.uniq + [[0, 1]]
layouts.each do |teams|
  teams.each_index do |winner|
    random = TeamShieldRandom.new
    engine = GameRoomPong::Engine.new(teams: teams, arcade: true, rng: random)
    peers = teams.each_index.map do |seat|
      GameRoomPong::PeerEngine.new(teams: teams, side: seat, authority: seat.zero?, arcade: true)
    end
    members = engine.rotation.members(teams[winner])
    expected = teams.map { |team| team == teams[winner] ? 625 : 0 }
    random.value = 0.01
    engine.roll_effects(winner)
    assert(engine.shields == expected, "shield won by #{winner} did not protect the whole team #{teams.inspect}")
    peers.each do |peer|
      assert(peer.apply_effects('side' => winner, 'turn' => 0, 'renew' => true, 'invisible' => false),
        'peer rejected the shield effect')
      assert(peer.shields == expected, 'remote shield did not protect the same team')
    end
    [engine, *peers].each do |copy|
      assert(copy.events.count { |fx| fx[1] == 'shield_on' } == 1, 'one team shield produced duplicate activation cues')
    end
    random.value = 0.5
    assert(engine.strike(engine.server), 'shield fixture could not serve')
    engine.step(Array.new(teams.length) { {} }, now_ms: 1600)
    assert(members.all? { |seat| engine.shields[seat] == 525 }, 'team shield timers did not count down together')
    partner = members.last
    random.value = 0.01
    engine.roll_effects(partner)
    assert(engine.shields == expected, 'partner shield did not renew both timers to ten seconds')
    random.value = 0.5
    protected = []
    (teams.length * 2).times do
      seat = engine.rotation.hitter(engine.turn)
      court = teams[seat]
      if court == teams[winner]
        engine.paddles[seat] = 29.0
        engine.ball.merge!('x' => 1.0, 'y' => court.zero? ? 0.5 : 19.5)
        previous_turn = engine.turn
        engine.step(Array.new(teams.length) { {} }, now_ms: engine.now_ms + 16)
        assert(engine.goal.nil? && engine.turn == previous_turn + 1, 'shared shield did not save a missed ball')
        assert(engine.events.last[1, 2] == ['shield_hit', seat], 'shield return lost the designated hitter')
        assert(members.map { |member| engine.shields[member] }.uniq.length == 1,
          'a shield bounce used up only one partner timer')
        protected << seat
      else
        engine.ball.merge!('x' => engine.paddles[seat], 'y' => court.zero? ? 3.0 : 17.0)
        assert(engine.strike(seat), 'opponent could not return between shield saves')
      end
    end
    assert(protected.uniq.sort == members.sort, 'fixture did not miss with every protected teammate')
    saved = engine.shields.dup
    next_rally = GameRoomPong::Engine.new(teams: teams, arcade: true, rally: 1, shields: saved)
    next_rally.step(Array.new(teams.length) { {} }, now_ms: 5000)
    assert(next_rally.shields == saved, 'waiting for the next serve consumed the shared shield')
    assert(next_rally.strike(next_rally.server), 'expiry fixture could not serve')
    next_rally.step(Array.new(teams.length) { {} }, now_ms: 15000)
    assert(next_rally.shields.all?(&:zero?), 'the shared shield did not expire for both partners')
    assert(next_rally.events.count { |fx| fx[1] == 'shield_off' } == 1,
      'one team shield produced duplicate expiry cues')
  end
end
layouts.select { |teams| teams.length == 4 }.each do |teams|
  random = TeamShieldRandom.new
  engine = GameRoomPong::PeerEngine.new(teams: teams, side: nil, authority: true,
    bots: [0, 1, 2, 3], arcade: true, rng: random)
  teams.each_index { |seat| GameRoomPong::Bot.new(seat, level: 2, rng: Random.new(seat)).step(engine) }
  assert(engine.strike(engine.server), 'bot shield fixture could not serve')
  winner = engine.rotation.hitter(engine.turn)
  random.value = 0.01
  engine.host_effects(winner)
  random.value = 0.5
  saved = []
  4.times do
    turn = engine.turn
    seat = engine.rotation.hitter(turn)
    friendly = teams[seat] == teams[winner]
    engine.paddles[seat] = friendly ? 29.0 : 15.0
    engine.ball.merge!('x' => 15.0, 'y' => teams[seat].zero? ? 0.0 : 20.0)
    engine.step(Array.new(4) { {} })
    transition = engine.take_transition
    assert(engine.goal.nil? && engine.turn == turn + 1, 'a protected bot lost the point')
    assert(transition['action'] == (friendly ? 'shield_hit' : 'hit'), 'bot contact bypassed the shared shield')
    saved << seat if friendly
    engine.host_effects(seat) unless friendly
  end
  assert(saved.sort == engine.rotation.members(teams[winner]).sort, 'both bot partners were not protected')
end
layouts.each do |teams|
  random = TeamShieldRandom.new
  random.value = 0.01
  engine = GameRoomPong::Engine.new(teams: teams, arcade: true, rng: random)
  [0, 1].each { |team| engine.roll_effects(teams.index(team)) }
  engine.strike(engine.server)
  engine.step(Array.new(teams.length) { {} }, now_ms: 624 * 16)
  assert(engine.shields.all? { |ticks| ticks == 1 }, 'a team shield expired before ten seconds')
  assert(engine.events.none? { |fx| fx[1] == 'shield_off' }, 'expiry cue preceded the final shield tick')
  engine.step(Array.new(teams.length) { {} }, now_ms: 625 * 16)
  assert(engine.shields.all?(&:zero?), 'a team shield outlasted ten seconds')
  expired = engine.events.select { |fx| fx[1] == 'shield_off' }
  assert(expired.map { |fx| teams[fx[2]] }.sort == [0, 1], 'simultaneous expiry did not emit once per team')
  [0, 1].each { |team| engine.roll_effects(teams.index(team)) }
  engine.step(Array.new(teams.length) { {} }, now_ms: 725 * 16)
  opponent = engine.shields[teams.index(1)]
  engine.roll_effects(teams.rindex(0))
  assert(teams.each_index.all? { |seat| engine.shields[seat] == (teams[seat].zero? ? 625 : opponent) },
    'renewing one team changed the opposing active shield')
end
puts 'PASS team shields: every seating layout, local and remote grants, partner renewal, repeated human/bot misses, exact expiry, singles and rally carry-over'
