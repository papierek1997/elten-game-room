require_relative '../../support/billiards'
require_relative '../../../lib/billiards/match_presentation'
include GameRoomTest::Assertions

match = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'eight'})
state = match.replay.state
state[:groups] = [0, 1]
first = GameRoomBilliards::MatchPresentation.status(state)
assert(first.include?("Current player's group: solid balls."), 'Shared status does not identify whose group it describes')
assert(first.include?('Ball on: Any object ball.') && !first.include?('Ball 15'), 'Initial status reads the whole rack instead of the target group')
state[:turn] = 1
other = GameRoomBilliards::MatchPresentation.status(state)
assert(other.include?("Current player's group: striped balls."))
assert(!other.include?('Your group:'), 'An observer is told that the opponent group is their own')
match = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'one_pocket'})
state = match.replay.state
state[:point_pockets] = [0, 2]
assert(GameRoomBilliards::MatchPresentation.status(state).include?("Current player's scoring pocket:"))
puts 'PASS Billiards shared status: current-player group and scoring pocket do not claim the viewer owns them'
