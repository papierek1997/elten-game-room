require_relative '../../support/binary_rule_dictionary'

game = GameRoomGames::Farkle.new
state = {players:%w[A B],options:game.normalize_options('score_limit'=>1000,'entry_minimum'=>50,'turn_minimum'=>30,'farkle_rules_version'=>2),
  scores:{'A'=>1000,'B'=>930},phase: :selecting,current_player:'B',turn_points:0,dice_to_roll:6,
  last_roll:[1,2,2,3,3,3],selected_indices:[],winner:nil,final_round:true}
replay = GameRoomGames::Replay.new(players:%w[A B],current_player:'B',winner:nil,draw:false,state:state)
before = Marshal.dump(state)
choice = game.bot_strategy.choose(actions:game.legal_actions(replay,'B'),actor:'B',game:game,replay:replay,
  random_source:GameRoomRandom::SeededSource.new(17))
raise 'Final race still prefers immediate triple to a better five-dice chance' unless choice['indices']=='0'
raise 'Normal validation refuses final-race choice' unless game.action_for(choice,replay,'B').first==:ok
raise 'Race computation changed real score or dice' unless Marshal.dump(state)==before
puts 'PASS Farkle: known final deficit uses full finite continuation, legal selection and nonmutation'
