require_relative '../support/tournament_elimination_model'
require_relative '../../games/catalog'
require_relative '../../lib/tournaments/game_result'

check = TournamentEliminationModel.method(:assert)
fixture = lambda do |id, options = {}|
  TournamentEliminationModel::Fixture.new(GameRoomGames::CATALOG.build(id),
    players: %w[Alice Bob Carol], options: options).tap { |f| f.session['__tournament_match'] = {} }
end

bingo = fixture.call('bingo', 'marking'=>'manual', 'variant'=>'30')
bingo.automatic
bingo.automatic
bingo.append('Alice', 'ready', '1|0')
bingo.append('Carol', 'ready', '1|0')
bingo.refuse('Alice', 'tournament_elimination', '[1]')
bingo.eliminate('Bob')
bingo.assert_roster(%w[Alice Carol])
check.call(bingo.replay.state[:phase] == :drawing && bingo.replay.state[:called].length == 1,
  'Bingo lost its call or still waits for the departed player')
bingo.automatic
bingo.refuse('Bob', 'ready', '2|0')

roulette = fixture.call('roulette', 'mode'=>'social', 'round_limit'=>1)
roulette.append('Alice', 'bet', '1|red|10')
roulette.append('Alice', 'ready', '1')
roulette.append('Bob', 'bet', '1|red|10')
roulette.append('Bob', 'ready', '1')
roulette.append('Carol', 'bet', '1|black|5')
roulette.append('Carol', 'ready', '1')
roulette.eliminate('Alice')
roulette.assert_roster(%w[Bob Carol])
check.call(roulette.replay.current_player == 'Bob' && roulette.replay.state[:bets]['Bob']['red'] == 20,
  'Roulette lost the remaining bets or kept an absent spinner')
bad = GameRoomServerRandom.command(action: 'spin', count: 1, sides: 2).random_request
roulette.refuse('Bob', 'spin', '2', '__server_random'=>bad)
good = GameRoomServerRandom.command(action: 'spin', count: 1, sides: 37).random_request
roulette.append('Bob', 'spin', '2', '__server_random'=>good)
check.call(roulette.replay.finished? && roulette.replay.winner == 'Bob', 'Roulette did not finish naturally')

dice = fixture.call('blackjack_dice', 'variant'=>'one_die', 'score_limit'=>2)
%w[Alice Bob Carol].zip(%w[6 5 4]).each do |player, face|
  dice.append(player, 'roll', face)
  dice.append(player, 'stand')
end
checkpoint = dice.game.tournament_scored_checkpoint(dice.replay, options: dice.options)
dice.append('Bob', 'roll', '6')
dice.eliminate('Bob')
dice.assert_roster(%w[Alice Carol])
check.call(dice.replay.state[:total].zero? && checkpoint['scores']['Alice'] == 1 &&
  checkpoint == dice.game.tournament_scored_checkpoint(dice.replay, options: dice.options),
  'Blackjack Dice lost the completed round or kept the abandoned throw')
dice.append('Carol', 'roll', '4')
dice.append('Carol', 'stand')
dice.append('Alice', 'roll', '5')
dice.append('Alice', 'stand')
check.call(dice.replay.winner == 'Alice', 'Blackjack Dice did not score the restarted round')

%w[blackjack_dice dice_poker blackjack].each do |id|
  chips = fixture.call(id, {'scoring'=>'chips', 'starting_chips'=>100, 'stake'=>10}.reject { |key,_| id == 'blackjack' && key == 'scoring' })
  starting_chips = chips.replay.state[:chips].dup
  chips.automatic
  check.call(chips.replay.state[:chips].values.sum < starting_chips.values.sum, "#{id}: expected opening contribution")
  chips.eliminate('Alice')
  chips.assert_roster(%w[Bob Carol])
  check.call(chips.replay.state[:chips] == starting_chips, "#{id}: refunded wrong chip amounts")
  chips.automatic
  check.call(chips.replay.state[:auction][:order] == %w[Bob Carol], "#{id}: charged removed seat again")
end

extended = fixture.call('blackjack', 'variant'=>'extended', 'starting_chips'=>100)
initial_balances = extended.replay.state[:chips].dup
extended.automatic
extended.players.each { |player| extended.perform(player, {'kind'=>'command', 'action'=>'check'}) }
extended.automatic
extended.append('Alice', 'double')
check.call(extended.replay.state[:chips]['Alice'] < extended.replay.state[:chips]['Bob'], 'Fixture did not increase the stake')
extended.eliminate('Carol')
check.call(extended.replay.state[:chips] == initial_balances && extended.replay.state[:round].zero? &&
  extended.replay.state[:hands].empty?, 'Blackjack did not refund the double or reset the interrupted deal')
extended.assert_roster(%w[Alice Bob])

liar = fixture.call('liars_dice', 'variant'=>'classic')
liar.players.each { |player| liar.automatic(player) }
liar.automatic
liar.append('Alice', 'bid', '1:0:3:6')
liar.append('Bob', 'challenge', '1:1')
liar.automatic('Alice')
liar.automatic('Bob')
old = liar.game.automatic_action(liar.replay, 'Carol', context: liar.context)
status, plan = liar.game.action_for(old, liar.replay, 'Carol', context: liar.context)
check.call(status == :ok, "Expected Carol's pending reveal")
liar.eliminate('Carol')
liar.assert_roster(%w[Alice Bob])
check.call(liar.replay.state[:round] == 2 && liar.replay.state[:commits].empty? && liar.replay.state[:seed].nil?,
  'Liar’s dice reused a public seed or the old commitments')
liar.refuse('Carol', 'reveal', plan.events.first.value)
%w[Alice Bob].each { |player| liar.automatic(player) }
liar.automatic
check.call(liar.replay.state[:phase] == :bidding, 'Liar’s dice did not restart after the departure')

# A shared first place does not automatically tie the absent player with the winners.
tie = fixture.call('dice_poker', 'round_limit'=>1)
tie.eliminate('Carol')
%w[Alice Bob].each do |player|
  tie.append(player, 'roll', '2,2,3,4,5')
  tie.append(player, 'stand', '1')
end
export = GameRoomTournaments::GameResult
people = tie.players.map { |name| {'username'=>name, 'account'=>name.downcase} }
summary = export.from_replay(game: tie.game, replay: tie.replay, players: people, options: tie.options,
  event_count: tie.events.length, events: tie.events, result_policy: export::CURRENT_RESULT_POLICY)
placed = export.with_eliminations(summary, [%w[carol]])
check.call(placed['places'] == [%w[alice bob], %w[carol]] && placed['scores'].nil?,
  'Tournament tied first place, elimination or small-point rules changed')
puts 'PASS round-game tournament continuation: wagers, public rolls, hidden commitments and final places'
