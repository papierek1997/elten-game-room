require_relative '../../../games/blackjack'
game = GameRoomGames::Blackjack.new
state = {players:%w[Alice Bob],options:game.default_options,hand_index:0,round:1}
state.update(phase: :playing,current_player:'Alice',hands:{'Alice'=>[{cards:%w[0:TC 1:TH],bet:10,done:false}],
  'Bob'=>[{cards:%w[0:AS 1:AS],bet:10,done:false}]},dealer:%w[2:TH 3:AS],deck:%w[0:2D 0:3D])
replay = GameRoomGames::Replay.new(players:state[:players],current_player:'Alice',state:state,history:[],accepted_events:[])
observation = game.bot_observation(replay,'Alice')
weights = game.send(:blackjack_public_weights,state,observation)
raise 'Known tens were not removed from the six-pack shoe' unless weights[10]==93 && weights[1]==24
poison = Marshal.load(Marshal.dump(state))
poison[:deck].reverse!
poison[:dealer][1]='0:2C'
poison[:hands]['Bob'].first[:cards]=%w[1:2C 2:3D]
raise 'Public composition read concealed cards' unless weights==game.send(:blackjack_public_weights,poison,observation)
dealer = GameRoomTwentyOneStrategy.card_dealer(10,weights:weights)
raise 'Dealer distribution lost probability mass' unless (dealer.values.sum-1).abs<1e-9
raise 'Observed depletion was ignored' if dealer==GameRoomTwentyOneStrategy.card_dealer(10)
raise 'Public weights mutated while planning' unless weights[10]==93
puts 'PASS Blackjack known removals, actual six-pack size, conditioned dealer model, no hidden shoe/hole/foreign hand'
