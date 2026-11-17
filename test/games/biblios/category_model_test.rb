require_relative '../../support/biblios'
game = GameRoomGames::Biblios.new
state = blank_state(game, %w[Alice Bob Carol])
state[:hands]['Alice'] = %w[mE mF mG mH mI]
secured = game.send(:category_strength, state, 'Alice', 'm', state[:hands]['Alice'])
extra = game.send(:category_strength, state, 'Alice', 'm', state[:hands]['Alice'] + ['mD'])
assert((secured - extra).abs < 1e-9, 'Already secured majority still encourages buying redundant cards')
snapshot = Marshal.dump(state)
value = game.send(:category_strength, state, 'Alice', 'p', ['pA'])
state[:hands]['Bob'] = game.send(:master_deck).last(20)
state[:hands]['Carol'] = ['mA']
assert(game.send(:category_strength, state, 'Alice', 'p', ['pA']) == value, 'Actual hidden library size/value changed category inference')
state[:revealed]['Bob'] = %w[pE pF pG pH pI]
assert(game.send(:category_strength, state, 'Alice', 'p', ['pA']) < value, 'Public rival strength did not affect category value')
state = Marshal.load(snapshot)
before = Marshal.dump(state)
game.send(:category_strength, state, 'Alice', 'm', state[:hands]['Alice'])
assert(Marshal.dump(state) == before, 'Probability model changed a library')
state[:revealed]['Bob'] = game.send(:setup_deck, state[:players]) - state[:hands]['Alice']
assert(game.send(:category_strength, state, 'Alice', 'm', state[:hands]['Alice']) == secured,
  'Fully accounted-for inventory made an impossible concealed-size estimate erase a secured majority')
puts 'PASS Biblios public probability, secured category saturation, hidden-card/hidden-size isolation and nonmutation'
