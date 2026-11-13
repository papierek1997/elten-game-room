require_relative '../../support/billiards_rules'
require_relative '../../../lib/billiards/ten_ball'
require_relative '../../../lib/billiards/blackball'
require_relative '../../../lib/billiards/cutthroat'

module BilliardsAdditionalPoolTest
  extend GameRoomTest::Assertions
  F = BilliardsRulesFixture
  B = GameRoomBilliards
  R = B::Rules
  def self.state(id, breaking: false)
    result = F.state('eight')
    result[:options]['discipline'] = id
    result[:racks], result[:scores] = [0, 0, 0], [0, 0, 0] if id == 'cutthroat'
    R.setup(result)
    result[:hand], result[:breaking] = nil, breaking
    result
  end
  def self.data(call = 0, mode = 0)
    {'call'=>call, 'pocket'=>0, 'mode'=>mode, 'cue'=>0,
      'shot'=>{'angle'=>0, 'power'=>350, 'top'=>0, 'side'=>0}}
  end
  def self.event(kind, a, **values); {kind: kind, a: a, t: 0.0}.merge(values); end
  def self.contact(id = 1); event(:ball, 0, b: id); end
  def self.rail(id = 1); event(:rail, id, rail: :right); end
  def self.pot(id, pocket = 0); event(:pocket, id, pocket: pocket); end
  def self.apply(state, events, declaration = data)
    before = Marshal.load(Marshal.dump(state))
    balls = state[:balls].map(&:dup)
    events.each_with_index do |e, i|
      e[:t], e[:order] = i / 10.0, i
      balls.find { |b| b.id == e[:a] }.status = :potted if %i[pocket off].include?(e[:kind])
    end
    result = B::ShotResult.new(balls: balls, events: events, head_crossings: [], steps: 1, duration: 1.0)
    state[:balls] = balls.map(&:dup)
    R.resolve_shot(state, before, result, declaration)
    state
  end
  def self.run
    blackball_rack
    ten_ball
    blackball
    cutthroat
    puts 'Additional pool: WPA2026 10-ball and Blackball, diagram rack, free shot/current position, simultaneous final pots, Cutthroat three seats/revival/corners/draw passed.'
  end

  def self.blackball_rack
    s = state('blackball')
    rows = s[:balls].reject { |b| b.id == 0 }.sort_by { |b| [b.x, b.y] }.group_by { |b| b.x.round(5) }.values
    expected = [[0], [1, 0], [0, nil, 1], [1, 0, 1, 0], [0, 1, 1, 0, 1]]
    assert_equal(expected, rows.map { |row| row.map { |b| R.group(b.id) } }, 'Blackball group pattern differs from WPA8.4 diagram')
    black = s[:balls].find { |b| b.id == 8 }
    assert((black.x - R.table(s[:options]).width * 0.75).abs < 1e-8)
    assert((black.y - R.table(s[:options]).height / 2).abs < 1e-8)
  end

  def self.ten_ball
    s = state('ten', breaking: true)
    one, ten = s[:balls].values_at(1, 10)
    assert_equal(s[:balls].reject { |b| b.id == 0 }.map(&:x).min, one.x)
    assert((ten.y - R.table(s[:options]).height / 2).abs < 1e-8)
    assert(!B::TenBall.declaration?(s, data(1)))
    apply(s, [contact, rail(1), rail(2), rail(3), rail(4)])
    assert_equal(nil, s[:ruling][:foul])
    assert_equal(true, s[:push_available])
    assert_equal(1, s[:turn])
    assert(B::TenBall.declaration?(s, data(0, 2)))
    assert(!B::TenBall.declaration?(s, data(0, 1)), '10-ball admitted safety declaration')
    apply(s, [], data(0, 2))
    assert_equal(%w[accept return], s[:choices])
    assert_equal(nil, s[:ruling][:foul], 'Push-out wrongly required contact or rail')
    R.choose(s, 'return')
    assert_equal(1, s[:turn])
    s = state('ten')
    apply(s, [contact, pot(10)], data(10))
    assert_equal(:playing, s[:phase], 'Early 10-ball won the rack')
    assert(s[:balls][10].on_table?)
    assert_equal(0, s[:turn], 'A successful early called ten did not retain the shooter')
    s = state('ten')
    apply(s, [contact, pot(2)], data(3))
    assert_equal(%w[accept return], s[:choices], 'Uncalled pot lost the opponent choice')
    s = state('ten')
    apply(s, [contact, rail, event(:off, 10)], data(1))
    assert_equal(:off_table, s[:ruling][:foul])
    assert_equal(:any, s[:hand])
    assert(s[:balls][10].on_table?, 'Off-table ten was not spotted')
    s = state('ten')
    s[:balls].each { |b| b.status = :potted if b.id.between?(1, 9) }
    apply(s, [contact(10), pot(10)], data(10))
    assert_equal(:finished, s[:phase])
    assert_equal(0, s[:winner])
    s = state('ten')
    s[:fouls][0] = 2
    apply(s, [], data(1))
    assert_equal(1, s[:winner], 'Third consecutive foul did not lose 10-ball')
  end

  def self.blackball
    s = state('blackball', breaking: true)
    apply(s, [contact, event(:crossing, 1, line: :middle), event(:crossing, 2, line: :middle)])
    assert_equal(nil, s[:ruling][:foul])
    assert_equal(nil, s[:groups])
    s = state('blackball', breaking: true)
    apply(s, [contact, pot(8), pot(0)])
    assert_equal(true, s[:breaking])
    assert_equal(0, s[:turn])
    assert_equal(16, s[:balls].count(&:on_table?))
    s = state('blackball')
    s[:balls].first.x = 1.0
    apply(s, [])
    assert_equal(true, s[:blackball_free])
    assert_equal(nil, s[:hand], 'Free shot forced the cue away from its current position')
    assert_equal(1.0, s[:balls].first.x)
    apply(s, [contact, rail])
    assert_equal(1, s[:turn], 'A missed free shot consumed the normal shot')
    assert_equal(false, s[:blackball_free])
    apply(s, [contact, rail])
    assert_equal(0, s[:turn], 'A missed normal shot did not finish the visit')
    s = state('blackball')
    s[:blackball_free] = true
    apply(s, [contact, pot(1)])
    assert_equal(nil, s[:groups], 'Groups assigned on free shot')
    apply(s, [contact(2), pot(2)])
    assert_equal([0, 1], s[:groups])
    apply(s, [contact(3), pot(9)])
    assert_equal(:wrong_pot, s[:ruling][:foul])
    s = state('blackball')
    s[:groups] = [0, 1]
    s[:balls].each { |b| b.status = :potted if b.id.between?(2, 7) }
    apply(s, [contact, pot(1), pot(8)])
    assert_equal(0, s[:winner], 'Simultaneous last colour and black did not win')
    s = state('blackball')
    s[:groups] = [0, 1]
    apply(s, [contact, pot(8)])
    assert_equal(1, s[:winner], 'Early black did not lose')
    s = state('blackball')
    apply(s, [contact, pot(0)])
    assert_equal(:baulk, s[:hand], 'Scratch did not require baulk placement')
    s = state('blackball')
    s[:groups] = [0, 1]
    cue, target = s[:balls].values_at(0, 1)
    cue.x, cue.y = 1.0, 0.6
    target.x, target.y = cue.x + 2 * R.table(s[:options]).radius, cue.y
    apply(s, [rail(0), contact(9)], data.merge('shot'=>data['shot'].merge('angle'=>18000)))
    assert_equal(nil, s[:ruling][:foul], 'Rail before a later collision was ignored after playing away from a touching ball on')
  end

  def self.cutthroat
    6.times do |seed|
      s = state('cutthroat')
      s[:options]['rack_seed'] = seed
      s[:balls] = B::Cutthroat.rack(s[:options], 0)
      objects = s[:balls].reject { |b| b.id == 0 }
      back = objects.select { |b| (b.x - objects.map(&:x).max).abs < 1e-8 }
      corner = [objects.min_by(&:x), back.min_by(&:y), back.max_by(&:y)]
      assert_equal([0, 1, 2], corner.map { |b| B::Cutthroat.owner(b.id) }.sort, 'Rack corners do not represent all three groups')
    end
    s = state('cutthroat')
    s[:balls].each { |b| b.status = :potted if b.id.between?(6, 10) }
    apply(s, [pot(0)])
    assert_equal(1, B::Cutthroat.remaining(s, 1), 'A foul did not revive the eliminated opponent')
    assert_equal(1, s[:turn], 'Revived seat was skipped in original turn order')
    s = state('cutthroat')
    s[:balls].each { |b| b.status = :potted if b.id.between?(1, 5) }
    s[:turn] = 1
    apply(s, [contact(6), pot(11), pot(12), pot(13), pot(14), pot(15)])
    assert_equal(1, s[:winner])
    s = state('cutthroat')
    s[:balls].each { |b| b.status = :potted if b.id != 0 && ![1, 6, 11].include?(b.id) }
    apply(s, [contact, pot(1), pot(6), pot(11)])
    assert_equal(:finished, s[:phase], 'Simultaneous empty groups left a stuck turn')
    assert_equal(nil, s[:winner])
  end
end
BilliardsAdditionalPoolTest.run if $PROGRAM_NAME == __FILE__
