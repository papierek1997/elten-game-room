require_relative '../../../games/roulette'
require_relative '../../support/dice_games'
require_relative '../../../lib/game_simulation'
include DiceGamesSupport

%w[european american french].each do |wheel|
  defs = GameRoomRouletteBets.definitions(wheel)
  check(defs.map { |bet| bet[:key] }.uniq.size==defs.size,'Duplicate roulette bet ID')
  defs.each do |bet|
    check(bet[:numbers].uniq==bet[:numbers] && bet[:numbers].all? { |n| n.between?(0,wheel=='american' ? 37 : 36) },'Invalid layout group')
    check(GameRoomRouletteBets.payout(bet,20,bet[:numbers].first,wheel)==20*(bet[:odds]+1),'Wrong payout')
  end
  %w[red black odd even low high].each do |key|
    bet = defs.find { |b| b[:key]==key }
    check(GameRoomRouletteBets.payout(bet,6,0,wheel)==(wheel=='french' ? 3 : 0),'Zero outside payout wrong')
  end
  check(defs.none? { |bet| bet[:numbers]==[3,4] },'Nonadjacent split offered')
end

game, repo = GameRoomGames::Roulette.new, DiceGamesSupport::Repository.new(%w[Alice Bob])
def roulette_round(game,repo,options,number,bets)
  session = dice_session(game,**options)
  events=[]
  bets.each_with_index do |(key,amount),i|
    player=repo.players[i]
    events << dice_event(events.size+1,player,'bet',"1|#{key}|#{amount}") if key
    events << dice_event(events.size+1,player,'ready','1')
  end
  events << dice_event(events.size+1,'Alice','spin',(number+1).to_s)
  [game.replay(session,events,repo),session,events]
end
result,session,events=roulette_round(game,repo,{round_limit:1,starting_chips:100},7,[['n7',5],['black',10]])
check(result.state[:chips]=={'Alice'=>550,'Bob'=>180} && result.winner=='Alice','Casino gross payout or balance wrong')
check(game.replay(session,events+[events.last],repo)==result,'Duplicate spin changed balance')
result,=roulette_round(game,repo,{round_limit:1,starting_chips:100,wheel:'french'},0,[['red',3],['n0',2]])
check(result.state[:chips]=={'Alice'=>197,'Bob'=>340},'Odd-chip la partage lost half chip')
result,=roulette_round(game,repo,{round_limit:1,starting_chips:100,mode:'social'},7,[['red',5],['black',10]])
check(result.state[:chips]=={'Alice'=>220,'Bob'=>180} && result.state[:chips].values.sum==400,'Social pool created/lost chips')
result,=roulette_round(game,repo,{round_limit:1,starting_chips:100,mode:'social'},0,[['red',5],['black',10]])
check(result.state[:chips]=={'Alice'=>200,'Bob'=>200},'Unwon social pot not refunded')
result,=roulette_round(game,repo,{round_limit:2,starting_chips:100,mode:'social'},7,[['red',5],['black',10]])
check(result.state[:spinner]=='Bob' && result.current_player=='Bob','Social spinner did not rotate')
first=game.replay(dice_session(game),[],repo)
check(game.action_for({'action'=>'bet','bet'=>'red','amount'=>'17','round'=>1},first,'Alice').first==:ok,'Native form numeric text rejected')
%w[-1 1.5 1e3].each do |amount|
  check(game.action_for({'action'=>'bet','bet'=>'red','amount'=>amount,'round'=>1},first,'Alice').first==:invalid_bet,'Invalid amount accepted')
end
check(game.action_for({'action'=>'bet','bet'=>'fake','amount'=>1,'round'=>1},first,'Alice').first==:invalid_bet,'Forged bet accepted')
check(game.replay(dice_session(game),[dice_event(1,'Alice','spin','1')],repo).accepted_events.empty?,'Spin before betting accepted')

coordinator=GameRoomBots::Coordinator.new
%w[casino social].product(%w[european american french]).each do |mode,wheel|
  env=GameRoomSimulation::Environment.new_game(game:game,players:%w[bot:1:1:pl01 bot:1:2:pl02],options:{'mode'=>mode,'wheel'=>wheel,'round_limit'=>3,'bot_delay'=>0},seed:12)
  60.times do
    break if env.finished?
    auto=game.automatic_action(env.replay,env.replay.players.first,context:env.context)
    if auto
      check(env.step(auto,actor:env.replay.players.first)==:ok,'Automatic spin rejected')
    else
      decision=coordinator.decide_next(game:game,replay:env.replay,context:env.context,strategy:game.bot_strategy)
      check(decision && env.step(decision.action,actor:decision.actor)==:ok,'Roulette bot failed')
    end
    check(env.replay.state[:chips].values.sum+env.replay.state[:bets].values.sum { |bets| bets.values.sum }==4000,'Social supply changed') if mode=='social'
  end
  check(env.finished? && env.replay==game.replay(env.session,env.events,env.repository),'Roulette bot match/replay diverged')
end
puts 'Roulette: all layout payouts, zeros, half chips, social pool/refunds/rotation, input validation and six bot matches passed.'
