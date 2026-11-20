require_relative '../../support/binary_rule_dictionary'
game = GameRoomGames::Battleship.new
state = game.send(:initial_state,%w[A B],game.normalize_options('fleet'=>'classic','touching'=>false))
shots = {}
[[38,48,58,68,78],[30,40,50,60],[16,17,18]].each do |ship|
  ship.each_with_index { |cell,index|shots[cell]=index==ship.size-1 ? 'sunk' : 'hit' }
end
[95,79,64,4,21,76,53,27,92,26,3,47,29,42,91,85,59,0,41,35,56,2,46,89,67,97,6,25,20,28,88,52,37,10,32].each { |cell|shots[cell]='miss' }
[82,72,54].each { |cell|shots[cell]='hit' }
fleet = [[38,48,58,68,78],[30,40,50,60],[16,17,18],[62,72,82],[44,54]]
raise 'Invalid witness fleet' unless game.legal_fleet?(state,fleet)
state[:phase],state[:current_player],state[:shots]['A'] = :playing,'A',shots
replay = GameRoomGames::Replay.new(players:%w[A B],current_player:'A',state:state,winner:nil,draw:false)
before = Marshal.dump(state)
choice = game.bot_strategy.choose(actions:game.legal_actions(replay,'A'),actor:'A',random_source:GameRoomRandom::SeededSource.new(17),game:game,replay:replay)
raise 'Bot still shoots impossible square instead of certain joint-fleet hit' unless choice.values_at('x','y')==[2,6]
raise 'Incomplete enumeration advertised as joint probability' unless game.bot_strategy.last_stats[:joint] && game.bot_strategy.last_stats[:worlds]==2
raise 'Fleet inference changed real shots' unless before==Marshal.dump(state)
raise 'Normal shot validator refuses inference choice' unless game.action_for(choice,replay,'A').first==:ok
puts 'PASS Battleship: public chronology, legal full-fleet witness, certain joint hit and nonmutation'
