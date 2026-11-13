require_relative '../../support/assertions'
require_relative '../../../lib/game_surfaces/specifications'
require_relative '../../../games/cash_auction'

extend GameRoomTest::Assertions
game = GameRoomGames::CashAuction.new
options = game.table_creation_options
assert_equal([2, 8], [game.minimum_players, game.maximum_players])
assert_equal([1000, 10, 200, 8, 2, 5], options.values_at('starting_points', 'ante', 'pass_penalty', 'rounds', 'count_interval', 'black_chest_chance'))
assert_equal(nil, game.options_error(options, player_count: 2))
assert_equal(nil, game.options_error(options, player_count: 8))
%w[starting_points ante rounds count_interval black_chest_chance].each do |key|
  assert(game.options_error(options.merge(key=>0)), "Invalid #{key} was accepted")
end
assert_equal(nil, game.options_error(options.merge('pass_penalty'=>0)))
assert_equal('quiz', game.content_pack_game_id)
assert(game.selected_content_pack(options).data.fetch('questions').any?, 'No quiz bank selected')
assert(game.actions_during_bot_turn?, 'Human bids were serialized behind a bot turn')
assert_equal(nil, game.required_decision_key(nil, 'Alice'), 'Opening a foreground game has no previous decision')
finished = GameRoomGames::Replay.new(players: %w[Alice Bob], state: {}, winner: 'Alice')
assert_equal(nil, game.required_decision_key(finished, 'Alice'), 'A finished game still requested a decision')
puts 'Cash Auction setup: minimum/maximum seats, published defaults, settings bounds, quiz pack reuse and concurrent human input passed.'
