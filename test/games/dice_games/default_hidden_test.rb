require_relative '../../support/dice_games'
include DiceGamesSupport

game = GameRoomGames::DicePoker.new
repo = Repository.new(%w[Alice Bob])
check(game.option_definitions.none? { |definition| definition.key == 'scoring' }, 'Removed scoring selector is exposed')
check(game.default_options.values_at('starting_chips', 'stake') == [1000, 10], 'Chip defaults changed')
['points', 'chips', nil].each do |retired_setting|
  options = game.normalize_options('scoring'=>retired_setting)
  check(!options.key?('scoring'), 'Removed setting survived normalization')
  current = game.replay({'options'=>JSON.generate(options)}, [], repo)
  check(current.state[:phase] == :awaiting_ante && current.state[:chips].values == [1000,1000], 'A default table uses the retired point game')
  check(!current.state.key?(:scores) && game.participant_scores(current).values == [1000,1000], 'Point-only scoreboard remains')
end

# Paying every remaining chip still permits both players to roll. No phantom
# betting phase or message is needed when neither player can bet any more.
session = dice_session(game, starting_chips:10, stake:10, round_limit:1)
events = [['Alice','ante','1'], ['Alice','roll','6,6,6,6,6'], ['Alice','stand','1'],
  ['Bob','roll','1,1,1,1,1'], ['Bob','stand','1']].each_with_index.map { |move,i| dice_event(i+1,*move) }
result = game.replay(session, events, repo)
check(result.accepted_events == events && result.finished? && result.winner == 'Alice', 'Ante all-in prevents rolling or automatic settlement')
check(result.state[:chips] == {'Alice'=>20,'Bob'=>0} && result.state[:pot] == 0, 'Ante-only pot settlement changes chip supply')
check(result.history.none? { |entry| entry.kind == :betting }, 'All-in settlement announces an unavailable auction')
puts 'PASS Dice Poker always uses hidden dice/chips, no retired selector or score state, ante defaults and complete all-in showdown'
