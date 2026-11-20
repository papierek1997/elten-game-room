# Joint allocation of the unknown cards of ONE category. Rival library sizes
# are estimates supplied by Biblios, never read from actual concealed hands.
module GameRoomBibliosCategoryModel
  module_function

  def win_probability(cards, mine:, rivals:, population:, limit:20_000)
    return 0.0 if rivals.any? { |r| (mine <=> r.first(2))<=0 }
    capacities = rivals.map { |r|r[2].clamp(0,population) }
    # Inconsistent neutral size estimates must not invent extra physical cards.
    if capacities.sum>population
      scale = population.fdiv(capacities.sum)
      capacities = capacities.map { |n|(n*scale).floor }
    end
    capacities << population-capacities.sum
    totals = rivals.map(&:first)
    letters = rivals.map { |r|-r[1] }
    memo,nodes = {},0
    visit = lambda do |index,spaces,points,ties|
      next 0.0 if points.each_index.any? { |i|(mine <=> [points[i],-ties[i]])<=0 }
      next 1.0 if index==cards.size
      key = [index,spaces,points,ties]
      next memo[key] if memo.key?(key)
      nodes += 1
      throw :biblios_joint_budget if nodes>limit
      Thread.pass if (nodes % 128).zero?
      value,letter = cards[index]
      denominator = population-index
      memo[key] = spaces.each_index.sum do |owner|
        next 0.0 if spaces[owner].zero?
        after_spaces = spaces.dup
        after_spaces[owner] -= 1
        after_points,after_ties = points.dup,ties.dup
        if owner<rivals.size
          after_points[owner] += value
          after_ties[owner] = [after_ties[owner],letter].min
        end
        spaces[owner].fdiv(denominator)*visit.call(index+1,after_spaces,after_points,after_ties)
      end
    end
    catch(:biblios_joint_budget) { visit.call(0,capacities,totals,letters) }
  end
end
