require_relative '../../support/dice_games'
include DiceGamesSupport

strategy = GameRoomDicePokerStrategy
%w[classic no_straights aces_high].each do |variant|
  single = strategy.random_outcomes(variant)
  [2, 3].each do |attempts|
    distribution = strategy.modeled_outcomes(variant, attempts)
    check((distribution.values.sum(&:last) - 1).abs < 1e-10, 'Opponent probability mass was lost')
    check(distribution.keys == single.keys, 'Opponent model dropped possible own hands')
    last = 0.0
    distribution.each_value do |lower, equal|
      check((lower - last).abs < 1e-10 && equal >= 0, 'Invalid cumulative opponent distribution')
      last += equal
    end
    percentile = distribution.sum { |rank, (_, equal)| lower, tie = single.fetch(rank); equal * (lower + tie / 2) }
    check(percentile > 0.6, 'Retaining dice has no advantage over a single full throw')
  end
end
check(strategy.modeled_outcomes('classic', 3).equal?(strategy.modeled_outcomes('classic', 3)), 'Model is rebuilt per action')
puts 'PASS bounded retained-dice opponent distributions, all variants and cache reuse'
