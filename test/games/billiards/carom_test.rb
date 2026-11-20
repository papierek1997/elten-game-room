require_relative '../../support/billiards_english'
require_relative '../../../lib/billiards/carom'

module BilliardsCaromTest
  extend GameRoomTest::Assertions
  F = BilliardsEnglishFixture
  C = GameRoomBilliards::Carom
  def self.playing(id, **options)
    state = F.state(id, **options)
    C.choose(state, 'carom_start_left')
    state[:breaking] = false
    state
  end
  def self.run
    %w[carom one_cushion three_cushion].each do |id|
      state = F.state(id)
      assert_equal([0,1,2], state[:balls].map(&:id))
      assert_equal(%w[carom_start_left carom_start_right], state[:choices])
      assert(C.choose(state, 'carom_start_right'))
      F.apply(state, [F.rail(0), F.hit(0, 2), F.rail(0), F.rail(0), F.hit(0, 1)])
      assert_equal(:opening_contact, state[:ruling][:foul], 'Opening attack must be directly on red')
      assert_equal([0,0], state[:scores])
      state = playing(id)
      rails = id == 'carom' ? [] : Array.new(id == 'one_cushion' ? 1 : 3) { F.rail(0) }
      F.apply(state, [F.hit(0, 2), *rails, F.hit(0, 1)])
      assert_equal([1,0], state[:scores])
      assert_equal(0, state[:turn])
    end
    early = playing('three_cushion')
    F.apply(early, [F.hit(0, 2), F.hit(0, 1), F.rail(0), F.rail(0), F.rail(0), F.hit(0, 1)])
    assert_equal([0,0], early[:scores], 'Late cushions rescued an already missed cannon')
    assert_equal(:insufficient_cushions, early[:ruling][:foul])
    assert_equal(1, early[:turn])
    yellow = playing('one_cushion')
    yellow[:turn] = 1
    F.apply(yellow, [F.hit(1, 0), F.rail(1), F.hit(1, 2)])
    assert_equal([0,1], yellow[:scores])

    zone = playing('carom')
    zone[:balls][1].x, zone[:balls][1].y = 0.12, 0.10
    zone[:balls][2].x, zone[:balls][2].y = 0.25, 0.10
    zone[:carom_zone], zone[:carom_zone_state] = 0, :entered
    F.apply(zone, [F.hit(0, 1), F.hit(0, 2)])
    assert_equal(:inside, zone[:carom_zone_state])
    F.apply(zone, [F.hit(0, 1), F.hit(0, 2)])
    assert_equal(:zone_limit, zone[:ruling][:foul])
    assert_equal([1,0], zone[:scores])
    escaped = playing('carom')
    escaped[:balls][1].x, escaped[:balls][1].y = 0.12, 0.1
    escaped[:balls][2].x, escaped[:balls][2].y = 0.25, 0.1
    escaped[:carom_zone], escaped[:carom_zone_state] = 0, :inside
    F.apply(escaped, [F.hit(0, 1), {kind: :zone_exit, a: 1, zone: 0}, F.hit(0, 2)])
    assert_equal([1,0], escaped[:scores])
    assert_equal(:entered, escaped[:carom_zone_state], 'Exit and re-entry must restart the zone restriction')

    equal = playing('one_cushion', point_target: 1)
    F.apply(equal, [F.hit(0, 2), F.rail(0), F.hit(0, 1)])
    assert_equal(:playing, equal[:phase])
    assert_equal(1, equal[:turn])
    assert(equal[:carom_equalizing])
    C.choose(equal, 'carom_start_left')
    F.apply(equal, [F.hit(1, 2), F.rail(1), F.hit(1, 0)])
    assert_equal(:finished, equal[:phase])
    assert_equal(nil, equal[:winner])
    immediate = playing('carom', point_target: 1, equalizing: false)
    F.apply(immediate, [F.hit(0, 2), F.hit(0, 1)])
    assert_equal(0, immediate[:winner])

    off = playing('three_cushion')
    untouched = off[:balls][2].dup
    F.apply(off, [{kind: :off, a: 0}])
    assert_equal(untouched, off[:balls][2], 'Three cushion reset unrelated object ball')
    assert_equal(:off_table, off[:ruling][:foul])

    touching = playing('one_cushion')
    touching[:balls][0].x, touching[:balls][0].y = 0.8, 0.7
    touching[:balls][2].x, touching[:balls][2].y = 0.8 + 2 * GameRoomBilliards::Rules.table(touching[:options]).radius, 0.7
    C.prepare_touching(touching)
    assert_equal(%w[carom_play_away carom_respot], touching[:choices])
    C.choose(touching, 'carom_play_away')
    F.apply(touching, [F.hit(0, 2), F.rail(0), F.hit(0, 1)])
    assert_equal(:push, touching[:ruling][:foul])
    assert_equal([0,0], touching[:scores])

    frozen = playing('carom')
    t = GameRoomBilliards::Rules.table(frozen[:options])
    frozen[:balls][0].x = t.radius
    F.apply(frozen, [F.rail(0, :left), F.hit(0, 2), F.hit(0, 1)], shot: {angle: 18000})
    assert_equal(:frozen_cushion, frozen[:ruling][:foul])
    chronology = playing('three_cushion')
    events = [F.hit(0, 1, order: 4), F.rail(0, :top, order: 2), F.hit(0, 2, order: 0),
      F.rail(0, :bottom, order: 1), F.rail(0, :top, order: 3)].map { |event| event.merge(t: 0.1) }
    F.apply(chronology, events)
    assert_equal([1,0], chronology[:scores], 'Equal-time rail evidence ignored the explicit chronology')
    reset = playing('one_cushion')
    reset[:balls][0].x, reset[:balls][0].y = 0.8, 0.7
    reset[:balls][2].x, reset[:balls][2].y = 0.8 + 2 * GameRoomBilliards::Rules.table(reset[:options]).radius, 0.7
    C.prepare_touching(reset)
    C.choose(reset, 'carom_respot')
    assert_equal(%w[carom_start_left carom_start_right], reset[:choices])
    assert_equal(0, reset[:turn])
    assert(reset[:breaking])
    immutable = playing('one_cushion')
    F.apply(immutable, [F.hit(0, 2), F.rail(0), F.hit(0, 1)], preserve_before: true)
    assert_equal([1,0], immutable[:carom_innings])
    puts 'Carom: all three disciplines, direct opening, repeated/late rails, yellow cue, live zone exits, equalizing draw and selective off-table reset passed.'
  end
end
BilliardsCaromTest.run if $PROGRAM_NAME == __FILE__
