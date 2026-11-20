require_relative '../../support/billiards_rules'
require_relative '../../../lib/billiards/points_pool'
require_relative '../../../lib/billiards/carom'
require_relative '../../../lib/billiards/shot_candidates'

module BilliardsShotCandidatesTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  C = B::ShotCandidates

  def self.state(id, balls, turn = 0)
    {options: {'discipline'=>id}, balls: balls, turn: turn, breaking: false, hand: nil, choices: [], point_pockets: [2, 5]}
  end
  def self.ball(id, x, y); B::Ball.new(id: id, x: x, y: y); end
  def self.build(value)
    C.build(value, B::Rules.table(value[:options]), value[:balls].find { |b| b.id == B::Rules.cue_id(value) })
  end
  def self.run
    value = state('one_pocket', [ball(0, 0.4, 0.635), ball(1, 1.2, 0.635)])
    original = Marshal.dump(value)
    srand(73)
    expected_random = rand
    srand(73)
    candidates = build(value)
    assert(candidates.any?, 'No own-pocket geometric proposal')
    assert(candidates.all? { |_, distance, id, pocket, rails| distance > 0 && id == 1 && pocket == 2 && rails.empty? })
    assert_equal(original, Marshal.dump(value))
    assert_equal(candidates, build(value), 'Proposals depend on an earlier call')
    assert_equal(expected_random, rand, 'Proposing geometry consumed global RNG')

    value = state('bank_short', [ball(0, 0.4, 0.7), ball(1, 1.7, 0.7)])
    candidates = build(value)
    assert(candidates.any?, 'No reflected bank proposals')
    assert(candidates.all? { |_, _, id, _, rails| id == 1 && rails.length.between?(1, 2) && rails.all? { |rail| rail.between?(0, 3) } })
    table = B::Rules.table(value[:options])
    candidates.each do |angle, _, id, pocket, rails|
      target = value[:balls].find { |b| b.id == id }
      path = C.reflected_path([target.x, target.y], table.pockets[pocket], rails, table)
      assert_equal(rails.length + 2, path.length)
      assert(C.clear_path?(path, table, value[:balls], [0, 1]))
      first = B::Geometry.trace(table, value[:balls], 0, angle)
      assert_equal([:ball, 1], [first[:kind], first[:id]], 'A bank proposal kicked or used a combination')
    end
    assert(candidates.any? { |_, _, _, _, rails| rails.length == 2 }, 'Two-cushion bank paths were not proposed')

    # A straight obstacle blocks the direct pot path, and the fixed budget
    # holds even with the full roster and all destination pockets.
    value = state('straight', [ball(0, 0.4, 0.635), ball(1, 1.2, 0.635), ball(2, 1.8, 0.635)])
    direct = build(value)
    assert(direct.all? { |_, _, id, _, rails| [1, 2].include?(id) && rails.empty? })
    target = value[:balls][1]
    path = [[target.x, target.y], [2.54, 0.635]]
    assert_equal(false, C.clear_path?(path, table, value[:balls], [0, 1]))
    value = state('bank_full', B::PointPool.rack({'discipline'=>'bank_full', 'rack_seed'=>42}, 0))
    assert(build(value).length <= C::LIMIT)

    # The second player keeps physical cue1; white0 remains a target.
    %w[carom one_cushion three_cushion].each do |id|
      value = state(id, [ball(0, 1.6, 0.4), ball(1, 0.5, 0.7), ball(2, 1.9, 1.0)], 1)
      candidates = build(value)
      assert(candidates.any?, "No #{id} tangent/reflected carom proposals")
      assert(candidates.length <= C::LIMIT)
      required = {'carom'=>[0, 1], 'one_cushion'=>[1], 'three_cushion'=>[3]}.fetch(id)
      assert(candidates.all? { |_, distance, target_id, _, rails| [0, 2].include?(target_id) && distance.finite? && distance > 0 && required.include?(rails.length) })
      assert(candidates.any? { |_, _, target_id, _, _| target_id == 0 }, 'Active cue selection excluded physical white0')
      table = B::Rules.table(value[:options])
      candidates.each do |angle, _, target_id, _, _|
        first = B::Geometry.trace(table, value[:balls], 1, angle)
        assert_equal([:ball, target_id], [first[:kind], first[:id]])
      end
    end
    value[:choices] = ['carom_start_left']
    assert_equal([], build(value))
    puts 'Billiards bot proposals: bounded deterministic own-pocket/ghost-ball paths, ordered one/two-cushion banks, dynamic cue0/1, direct/one/three-cushion carom tangents, obstruction and pre-shot decisions passed.'
  end
end
BilliardsShotCandidatesTest.run if $PROGRAM_NAME == __FILE__
