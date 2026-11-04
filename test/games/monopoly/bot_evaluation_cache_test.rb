require_relative '../../../lib/game_simulation'
require_relative '../../../games/monopoly'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

class UncachedReserveMonopoly < GameRoomGames::Monopoly
  private
  # Independent uncached reference for the original reserve calculation.
  def monopoly_cash_reserve(state, player)
    rents = state[:board].filter_map do |square|
      owner = state[:owners][square[:index]]
      monopoly_expected_rent(state, square, owner) if owner && !same_user?(owner, player) && !state[:mortgaged][square[:index]]
    end
    baseline = [board_payment(state, 100) + rents.max(3).sum / 3, board_payment(state, 500)].min
    exposure = monopoly_landing_probabilities(state).fetch(player, {}).sum do |index, probability|
      square = state[:board][index]
      owner = state[:owners][index]
      rent = owner && !same_user?(owner, player) && !state[:mortgaged][index] ? monopoly_expected_rent(state, square, owner) : 0
      probability * rent
    end
    [baseline, board_payment(state, 100) + (exposure * 2).ceil].max
  end
end

game, reference = GameRoomGames::Monopoly.new, UncachedReserveMonopoly.new
players = ['Human', *GameRoomParticipants.bots_for(1, 7)]
boards = GameRoomContent::MonopolyBoards.choices.sort_by { |choice| GameRoomContent::MonopolyBoards.build(choice.value)[:squares].size }
profiles = ['atlantic_city', boards.first.value, boards.last.value].uniq
checks = 0
profiles.each do |board|
  [false, true].each do |no_rent|
    state = game.send(:initial_state, players, game.normalize_options('board'=>board, 'no_rent_in_jail'=>no_rent))
    state[:cash].transform_values! { 5000 }
    state[:positions].transform_values!.with_index { |_value, index| index * 4 % state[:board].size }
    state[:jail][players[2]] = 2
    properties = state[:board].select { |square| square[:price] }
    properties.each_with_index { |square, index| state[:owners][square[:index]] = players[index % players.size] }
    [false, true].each do |developed|
      if developed
        groups = properties.select { |square| square[:type] == :property }.group_by { |square| square[:group] }.values
        groups.first(5).each_with_index do |group, index|
          group.each do |square|
            state[:owners][square[:index]] = players[index]
            state[:houses][square[:index]] = [5, 3, 2, 2, 5][index]
          end
        end
      end
      players.each do |player|
        state[:current_player] = player
        replay = GameRoomGames::Replay.new(board:state[:board], players:players, current_player:player,
          accepted_events:[], history:[], state:state)
        before = Marshal.dump(state)
        actions = game.legal_actions(replay, player)
        actual = actions.map { |action| game.bot_action_score(replay, player, action) }
        expected = actions.map { |action| reference.bot_action_score(replay, player, action) }
        assert_equal(expected, actual, 'Forecast cache changed candidate scores')
        rng, expected_rng = GameRoomRandom::SeededSource.new(33), GameRoomRandom::SeededSource.new(33)
        selected = game.bot_strategy.choose(actions:actions, actor:player, game:game, replay:replay, random_source:rng)
        expected_selected = reference.bot_strategy.choose(actions:actions, actor:player, game:reference, replay:replay, random_source:expected_rng)
        assert_equal(expected_selected, selected, 'Forecast cache changed a selected move')
        assert_equal(expected_rng.roll(count:2, sides:1000).values, rng.roll(count:2, sides:1000).values, 'Forecast cache changed tie-breaking RNG')
        assert_equal(before, Marshal.dump(state), 'Scoring modified the caller-owned game state')
        checks += actions.size
      end
    end
  end
end

calls = 0
counter = Module.new do
  define_method(:calculate_monopoly_cash_reserve) do |*args|
    calls += 1
    super(*args)
  end
end
game.singleton_class.prepend(counter)
state = GameRoomSnapshot.copy(game.send(:initial_state, players, game.default_options))
properties = state[:board].select { |square| square[:price] }
properties.each_with_index { |square, index| state[:owners][square[:index]] = players[index % players.size] }
3.times do
  players.each { |player| assert_equal(reference.send(:monopoly_cash_reserve, state, player), game.send(:monopoly_cash_reserve, state, player)) }
end
assert_equal(players.size, calls, 'Identical forecasts were recalculated for each candidate')

street = properties.find { |square| square[:type] == :property }
mutations = [
  -> { state[:owners][street[:index]] = players[1] },
  -> { state[:houses][street[:index]] = 3 },
  -> { state[:mortgaged][street[:index]] = true },
  -> { state[:positions][players.first] += 1 },
  -> { state[:jail][players[1]] = 2 },
  -> { state[:bankrupt][players[2]] = true },
  -> { state[:options]['no_rent_in_jail'] = true },
  -> { street[:rents][3] += 10 },
  -> { state[:board_data][:salary] += 20 },
  -> { state[:players] = state[:players].reverse }
]
mutations.each do |mutate|
  before = calls
  mutate.call
  players.each { |player| assert_equal(reference.send(:monopoly_cash_reserve, state, player), game.send(:monopoly_cash_reserve, state, player)) }
  assert_equal(before + players.size, calls, 'An in-place forecast input change reused a stale valuation')
end
puts "PASS Monopoly reserve cache: #{checks} candidate scores, exact choices/RNG, multiple boards, eight actors, buildings/jail/mortgages, bounded reuse and all mutable dependencies"
