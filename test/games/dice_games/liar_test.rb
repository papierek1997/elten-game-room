require_relative "../../support/dice_games"
require_relative "../../../games/liars_dice"
include DiceGamesSupport

game = GameRoomGames::LiarsDice.new
players = %w[Alice Bob Carol]
repo = DiceGamesSupport::Repository.new(players)
session = dice_session(game, variant: "rdr", starting_dice: 1)
seeds = players.each_with_index.to_h { |player, i| [player, (i+1).to_s * 32] }
nonce = 'f'*32
server = 'a'*32
commits = players.map.with_index do |player, index|
  scope = {session_id:19,round:1,players:players}
  digest = HiddenSubmissions::Commitment.create(GameRoomLiarsDiceSecrets.payload(scope,player,seeds[player]), nonce: nonce).first
  dice_event(index+1, player, 'commit', '1:'+GameRoomLiarsDiceSecrets.encode(digest))
end
events = commits + [dice_event(4, 'Alice', 'deal', '1:'+server)]
replay = game.replay(session, events, repo)
check(replay.state[:phase] == :bidding && replay.state[:reveals].empty?, "Hidden dice leaked before a challenge")
copied = commits[1].merge('value'=>commits[0]['value'])
check(game.replay(session,[commits.first,copied],repo).accepted_events == [commits.first], "Copied seat commitment accepted")
check(!JSON.generate(replay.state).include?(seeds['Alice']), "Secret appears in public replay")
early_reveal = dice_event(5, 'Alice', 'reveal', '1:'+GameRoomLiarsDiceSecrets.encode(seeds['Alice']+nonce))
check(game.replay(session, events+[early_reveal], repo).accepted_events == events, "Premature reveal accepted")
all_dice = players.flat_map { |player| GameRoomLiarsDiceRules.dice(server, seeds[player], 1) }
face = all_dice.first
quantity = all_dice.count(face)
events << dice_event(5, 'Alice', 'bid', "1:0:#{quantity}:#{face}")
before = game.replay(session, events, repo)
check(game.action_for({'action'=>'bid','round'=>1,'bid_index'=>0,'quantity'=>3,'face'=>6}, before, 'Bob').first == :invalid, "Stale bid accepted")
check(game.action_for({'action'=>'exact','round'=>1,'bid_index'=>1}, before, 'Carol').first == :not_your_turn, "Out-of-turn RDR exact call")
events << dice_event(6, 'Bob', 'exact', '1:1')
forged = dice_event(7, 'Alice', 'reveal', '1:'+GameRoomLiarsDiceSecrets.encode('e'*32+nonce))
check(game.replay(session, events+[forged], repo).accepted_events == events, "Forged reveal accepted")
players.each { |player| events << dice_event(events.size+1, player, 'reveal', '1:'+GameRoomLiarsDiceSecrets.encode(seeds[player]+nonce)) }
finished = game.replay(session, events, repo)
check(finished.finished? && finished.winner == 'Bob' && finished.state[:counts] == {'Alice'=>0,'Bob'=>1,'Carol'=>0}, "RDR exact call did not penalize every opponent")
check(finished.accepted_events == events && finished.state[:answer_cleanup][:receipts].values.first.size == 3, "Disclosure receipts missing")
check(game.eliminated_from_game?(finished, 'Carol'), "Permanent elimination not exposed")

perudo = dice_session(game, variant: 'perudo', starting_dice: 2, calza: true)
perudo_events = commits + [dice_event(4, 'Alice', 'deal', '1:'+server), dice_event(5, 'Alice', 'bid', '1:0:6:6')]
perudo_replay = game.replay(perudo, perudo_events, repo)
check(game.legal_actions(perudo_replay, 'Carol').any? { |input| input['action'] == 'exact' }, "Out-of-turn Calza unavailable")
check(game.action_for({'action'=>'exact','round'=>1,'bid_index'=>1}, perudo_replay, 'Carol').first == :ok, "Out-of-turn Calza rejected")
perudo_events << dice_event(6, 'Bob', 'challenge', '1:1')
players.each { |player| perudo_events << dice_event(perudo_events.size+1, player, 'reveal', '1:'+GameRoomLiarsDiceSecrets.encode(seeds[player]+nonce)) }
after = game.replay(perudo, perudo_events, repo)
check(after.state[:counts]['Alice'] == 1 && after.state[:starter] == 'Alice' && after.state[:palifico] && after.state[:palifico_used] == ['Alice'], "First one-die loss did not start Palifico")
check(game.participant_replacement_error(game.replay(perudo, commits.take(1), repo), player: 'Alice') != nil, "Pending secret replacement allowed")
check(game.participant_replacement_error(game.replay(perudo, commits.take(1), repo), player: 'Bob').nil?, "Other person's secret blocked an unrelated replacement")
check(game.save_game_error(game.replay(perudo, [], repo)).nil?, "Empty private phase cannot be saved")
check(game.save_game_error(perudo_replay), "Pending private secrets can be saved")
check(game.validation_error({'starting_dice'=>0}), "Zero starting dice accepted")
puts "Liar's dice: secrecy, premature/forged reveals, RDR exact result, out-of-turn Calza, Palifico, stale bids, private guards and cleanup receipts passed"
