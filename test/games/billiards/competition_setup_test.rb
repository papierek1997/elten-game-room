require_relative '../../support/billiards'
require_relative '../../../lib/billiards/rules'
require_relative '../../support/elten_array_shuffle'

module BilliardsCompetitionSetupTest
  extend GameRoomTest::Assertions
  R = GameRoomBilliards::Rules
  def self.run
    %w[eight nine snooker].each do |discipline|
      options = {'discipline'=>discipline, 'rack_seed'=>123}
      balls, table = R.rack(options, 0), R.table(options)
      assert_equal(balls, R.rack(options, 0))
      balls.each do |ball|
        assert(table.placement?(balls, ball.id, ball.x, ball.y), "Overlapping rack #{discipline}: #{ball.id}")
      end
      state = {options: options, balls: balls, racks: [0, 0], scores: [0, 0], rack_number: 0}
      R.setup(state)
      old = Marshal.dump(state[:balls].drop(1))
      state[:balls].first.status = :potted
      state[:hand] = discipline == 'snooker' ? :d : :any
      assert(R.placement?(state, 0, 0.5, table.height / 2))
      assert(!R.placement?(state, 1, 0.5, table.height / 2))
      assert(!R.placement?(state, 0, 2, 0.5)) if discipline == 'snooker'
      assert_equal(old, Marshal.dump(state[:balls].drop(1)), 'Cue scratch altered the object balls')
      if discipline == 'eight'
        rack = balls.drop(1).sort_by { |b| [b.x.round(5), b.y] }
        assert_equal(8, rack[4].id)
        assert(R.group(rack[10].id) != R.group(rack[14].id))
      elsif discipline == 'nine'
        assert_equal(table.width * 0.75, balls.find { |b| b.id == 9 }.x)
      end
    end
    puts 'Competitive billiards setup: deterministic racks under ELTEN shuffle, dimensions, no overlap and cue-only restricted placement passed.'
  end
end
BilliardsCompetitionSetupTest.run if $PROGRAM_NAME == __FILE__
