require_relative "../../support/dice_games"
require_relative "../../../lib/game_simulation"
include DiceGamesSupport

game = GameRoomGames::DicePoker.new
repo = DiceGamesSupport::Repository.new(%w[Alice Bob Carol])
session = dice_session(game,scoring:'chips',starting_chips:100,stake:10,round_limit:1)
events = [dice_event(1,'Alice','ante','1')]
r = game.replay(session,events,repo)
check(r.state[:chips].values == [90,90,90] && r.state[:pot] == 30,'Ante was not paid by every seat')
native_action = GameSurfaces::Action.new(kind:'command',name:'check',payload:{'amount'=>0})
check(r.state[:phase] == :playing && r.current_player == 'Alice','Ante did not release dice directly')
check(game.action_for(native_action,r,'Alice').first == :invalid,'A betting action is allowed before the dice')
rejected = game.replay(session,events + [dice_event(2,'Alice','bet','raise|20')],repo)
check(rejected.accepted_events == events && rejected.state == r.state,'An injected opening bid changed the game')
hands = {'Alice'=>'6,6,6,6,6','Bob'=>'5,5,5,5,5','Carol'=>'1,2,3,4,5'}
repo.players.each do |p|
  events << dice_event(events.size+1,p,'roll',hands[p])
  events << dice_event(events.size+1,p,'stand','1')
end
r = game.replay(session,events,repo)
check(r.state[:phase] == :betting && r.history.count { |entry| entry.kind == :betting } == 1,'Missing single betting round after throws')
check(game.action_for(native_action,r,'Alice').first == :ok,'Actual shortcut action fails the final auction interface')
events << dice_event(events.size+1,'Alice','bet','raise|20')
events << dice_event(events.size+1,'Bob','bet','call|20')
events << dice_event(events.size+1,'Carol','bet','fold|0')
r = game.replay(session,events,repo)
check(r.finished? && r.state[:chips] == {'Alice'=>140,'Bob'=>70,'Carol'=>90},'Wrong post-throw pot settlement')
check(r.state[:chips].values.sum == 300 && r.state[:pot] == 0,'Chip supply changed')

coordinator = GameRoomBots::Coordinator.new
%w[classic no_straights aces_high].each do |variant|
  env = GameRoomSimulation::Environment.new_game(game:game,players:%w[bot:1:1:pl01 bot:1:2:pl02 bot:1:3:pl03],
    options:{'scoring'=>'chips','starting_chips'=>100,'stake'=>10,'round_limit'=>3,'variant'=>variant,'bot_delay'=>0},seed:144)
  250.times do
    break if env.finished?
    decision = coordinator.decide_next(game:game,replay:env.replay,context:env.context,strategy:game.bot_strategy)
    check(decision && env.step(decision.action,actor:decision.actor)==:ok,'Betting bot could not act')
    check(env.replay.state[:chips].values.sum + env.replay.state[:pot] == 300,'In-flight money is not conserved')
  end
  check(env.finished? && env.replay.accepted_events == env.events,'Betting match did not finish')
end
puts 'Dice poker betting: ante only before throws, final auction, actual shortcut actions, pot conservation and three complete bot matches passed'

state=game.replay(session,[dice_event(1,'Alice','ante','1')],repo).state
state[:chips]={'Alice'=>0,'Bob'=>20,'Carol'=>0}
state[:auction][:contributions]={'Alice'=>20,'Bob'=>80,'Carol'=>100}
state[:pot]=200
state[:hands]={'Alice'=>[6,6,6,6,6],'Bob'=>[5,5,5,5,5],'Carol'=>[1,2,3,4,5]}
game.send(:settle_chip_round,state,10,[])
check(state[:chips]=={'Alice'=>60,'Bob'=>140,'Carol'=>20},'Short all-in won an uncovered layer or excess was not returned')
check(state[:chips].values.sum==220,'Side-pot supply changed')
puts 'Dice poker betting: short all-in, covered side pot and uncalled excess passed'
