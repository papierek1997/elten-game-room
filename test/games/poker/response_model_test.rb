require_relative '../../support/new_games_fixture'
model = GameRoomPokerOpponents
cases = model.responders(%w[B C], {'B'=>0.2,'C'=>0.7})
assert(cases.size == 4 && (cases.sum(&:last) - 1).abs < 1e-12, 'Partial-response probability mass changed')
assert((cases.to_h[['B']] - 0.56).abs < 1e-12, 'B calls while C folds was not modeled')
assert(model.responders(%w[B C], {'B'=>0.0,'C'=>1.0}) == [[['B'],1.0]], 'All-in or certain fold created impossible response branches')
many = ('B'..'H').to_a
assert(model.responders(many, many.to_h { |player| [player,0.4] }).size == 128, 'Response enumeration is not bounded by the real table capacity')

# Controlled showdown leaf: A beats B, loses to C. Public response frequencies
# are the only uncertainty here. This isolates partial-call pot accounting
# from the separate card sampler and supplies an independent analytical oracle.
game = GameRoomGames::Poker.new
state = game.send(:initial_state, %w[A B C], game.default_options)
state.update(current_player:'A', stacks:{'A'=>50,'B'=>50,'C'=>50}, contributions:{'A'=>50,'B'=>50,'C'=>50},
  hands:{'A'=>%w[QS QH], 'B'=>%w[JS JH], 'C'=>%w[KS KH]},
  street_bets:{'A'=>0,'B'=>0,'C'=>0}, current_bet:0, all_in:{}, folded:{})
game.define_singleton_method(:poker_equity) { |_state, _actor, opponents:, ranges:| opponents.include?('C') ? 0.0 : 1.0 }
ranges = {profiles:{'b'=>{fold:0.0}, 'c'=>{fold:1.0}}}
pot, paid = 150.0, 50
b = model.fold_probability(ranges[:profiles]['b'], paid / (pot + paid), 0)
c = model.fold_probability(ranges[:profiles]['c'], paid / (pot + paid), 0)
expected = c * (b * 150 + (1 - b) * 200) + (1 - c) * -50
actual = game.send(:poker_raise_expectation, state, 'A', paid, ranges, pot:pot, raise_by:paid)
assert((actual - expected).abs < 1e-9, "Folded rival still participates or its dead chips disappeared: #{actual} vs #{expected}, #{b}, #{c}")
former = b * c * pot + (1 - b * c) * -paid
assert(actual > 0 && former < 0, 'Partial-fold counterexample no longer distinguishes the former all-call model')
puts 'PASS bounded public response subsets, all-in, partial folds, dead money and analytical raise expectation'
