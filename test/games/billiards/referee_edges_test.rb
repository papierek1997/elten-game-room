require_relative '../../support/billiards_rules'

module BilliardsRefereeEdgesTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  F = BilliardsRulesFixture
  R = B::Rules
  def self.run
    state = F.state('eight')
    state[:breaking], state[:hand] = false, :kitchen
    state[:balls].first.x = 1.0
    data = {'call'=>1, 'pocket'=>0, 'mode'=>0, 'shot'=>{'angle'=>0, 'power'=>300, 'top'=>0, 'side'=>0}}
    assert(!R.valid_declaration?(state, data), 'A shot bypassed kitchen placement')
    state[:balls].first.x, state[:balls].first.y = 0.3, 0.5
    state[:balls].each { |b| b.status = :potted unless [0, 1].include?(b.id) }
    state[:balls][1].x, state[:balls][1].y = 0.45, 0.5
    assert_equal(1, R.head_spot(state))
    spot = Marshal.load(Marshal.dump(state))
    R.spot_pool(spot, R.head_spot(spot))
    assert_equal(1.905, spot[:balls][1].x)
    assert_equal(state[:balls].first, spot[:balls].first, 'Requested object spotting moved white')
    before = Marshal.load(Marshal.dump(state))
    result = B::Physics.simulate(R.table(state[:options]), state[:balls], data['shot'])
    first = result.events.find { |e| e[:kind] == :ball }
    assert_equal(false, first[:head_crossed])
    state[:balls] = result.balls.map(&:dup)
    R.pool_shot(state, before, result, data)
    assert_equal(:head_string, state[:ruling][:foul])

    touching = F.state('snooker')
    touching[:hand], touching[:breaking] = nil, false
    touching[:balls].each { |b| b.status = :potted unless [0, 1, 21].include?(b.id) }
    touching[:balls].first.x, touching[:balls].first.y = 0.5, 0.5
    touching[:balls][1].x, touching[:balls][1].y = 0.5525, 0.5
    before = Marshal.load(Marshal.dump(touching))
    shot = data['shot'].merge('power'=>100)
    result = B::Physics.simulate(R.table(touching[:options]), touching[:balls], shot)
    assert(result.events.find { |e| e[:kind] == :ball }[:t] > 0.000001, 'Regression must use real integration timestamps')
    touching[:balls] = result.balls.map(&:dup)
    R.snooker_shot(touching, before, result, data.merge('shot'=>shot))
    assert_equal(:push, touching[:ruling][:foul])
    away = Marshal.load(Marshal.dump(before))
    shot = shot.merge('angle'=>18000)
    result = B::Physics.simulate(R.table(away[:options]), away[:balls], shot)
    away[:balls] = result.balls.map(&:dup)
    R.snooker_shot(away, before, result, data.merge('shot'=>shot))
    assert_equal(nil, away[:ruling][:foul], 'Playing away from a touching ball was penalized')

    points = F.state('snooker')
    points[:balls].each { |b| b.status = :potted if b.id.between?(2, 15) }
    points[:balls].first.x, points[:balls].first.y = 0.5, 0.5
    points[:balls][1].x, points[:balls][1].y = 1.0, 0.5
    points[:scores], points[:hand] = [0, 34], nil
    F.apply(points, F.result(points, first: nil))
    assert_equal([0, 38], points[:scores])
    assert_equal(false, points[:ruling][:miss], 'Miss ignored the score after the penalty')

    table = B::Table.new(discipline: 'snooker')
    balls = [B::Ball.new(id: 0, x: 0.4, y: 0.4, status: :potted),
      B::Ball.new(id: 16, x: 2.0, y: 0.889), B::Ball.new(id: 17, x: 1.94, y: 0.889)]
    saved = Marshal.dump(balls)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert(B::Visibility.d_snookered?(table, balls, [16]), 'Free ball omitted when all legal D placements are obstructed')
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_equal(saved, Marshal.dump(balls))
    balls[2].y += 0.15
    assert(!B::Visibility.d_snookered?(table, balls, [16]))
    match = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'snooker'})
    replay = match.replay
    replay.state[:choices], replay.state[:hand] = [], :d
    replay.state[:balls].first.status = :potted
    places = [0.5354, 0.7138].product([0.7112, 0.8890, 1.0668])
    replay.state[:balls].select { |b| b.id >= 16 }.zip(places).each { |b, (x, y)| b.x, b.y = x, y }
    objects = Marshal.dump(replay.state[:balls].drop(1))
    chosen = match.game.bot_strategy.choose(actions: match.game.legal_actions(replay, 'Alice'), replay: replay)
    assert_equal('place', chosen['action'], 'Bot conceded with most of the D still free')
    assert_equal(:ok, match.game.action_for(chosen, replay, 'Alice').first)
    assert_equal(objects, Marshal.dump(replay.state[:balls].drop(1)))
    puts "Billiards referee edges: real kitchen crossing, real touching push/away, post-penalty Miss exemption and complete D visibility cells passed (blocked D #{elapsed.round(3)}s)."
  end
end
BilliardsRefereeEdgesTest.run if $PROGRAM_NAME == __FILE__
