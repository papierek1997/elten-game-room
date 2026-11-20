require_relative '../../support/new_games_fixture'
game = GameRoomGames::Poker.new
players = ('A'..'H').to_a
state = game.send(:initial_state, players, game.default_options)
state.update(phase: :betting,current_player:'A',street:3,community:%w[QC TH JD 7S 6C],
  hands:players.to_h { |player| [player, player == 'A' ? %w[9C KC] : %w[2C 3D]] })
evidence = players.drop(1).to_h do |player|
  [player, (0..3).to_h { |street| [street,{raises:3,calls:3,pressure:1.0,call_price:0.4}] }]
end
ranges = {profiles:{},decisions:evidence}
count = 0
original = game.method(:hand_rank)
game.define_singleton_method(:hand_rank) { |cards| count += 1; original.call(cards) }
value = game.send(:poker_equity, state, 'A', ranges:ranges)
assert(value.between?(0,1) && count <= 8000, 'Full eight-seat/street model exceeded its rank budget')
cold = count
assert(game.send(:poker_equity, state, 'A', ranges:ranges) == value && count == cold, 'Warm equity recomputed ranks')
worlds = game.instance_variable_get(:@poker_worlds)
assert(worlds.size == 256 && game.instance_variable_get(:@poker_subset_equities).size == 1, 'Position cache grew beyond its current worlds/subset')

state = game.send(:initial_state, %w[A B], game.default_options)
state[:hands] = {'A'=>%w[9C KC], 'B'=>%w[2C 3D]}
neutral = game.send(:poker_equity, state, 'A')
state[:hands]['A'].reverse!
assert(game.send(:poker_equity, state, 'A') == neutral, 'Hand-list order changed equity')
renamed = Marshal.load(Marshal.dump(state))
renamed[:players] = %w[Other Rival]
renamed[:hands] = {'Other'=>state[:hands]['A'], 'Rival'=>state[:hands]['B']}
assert(GameRoomGames::Poker.new.send(:poker_equity, renamed, 'Other') == neutral, 'Account identity changed card odds')
puts "PASS bounded eight-seat/four-street worlds, #{cold} rank calls, warm reuse and identity/hand-order invariance"
