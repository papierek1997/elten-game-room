require_relative '../../support/new_games_fixture'

class FullPortfolioTradeMonopoly < GameRoomGames::Monopoly
  private
  def trade_gain(state, offer, player)
    incoming, outgoing = same_user?(offer[:from], player) ? [:receive, :give] : [:give, :receive]
    after = state.merge(owners: state[:owners].dup)
    offer_properties(offer, :give).each { |index| after[:owners][index] = offer[:target] }
    offer_properties(offer, :receive).each { |index| after[:owners][index] = offer[:from] }
    offer["#{incoming}_cash".to_sym] - offer["#{outgoing}_cash".to_sym] +
      owned_squares(after, player).sum { |s| trade_property_value(after, s[:index], player) } -
      owned_squares(state, player).sum { |s| trade_property_value(state, s[:index], player) }
  end
end

game = GameRoomGames::Monopoly.new
state = game.send(:initial_state, %w[Alice Bob], game.default_options)
property = state[:board].find { |square| square[:type] == :property }[:index]
state[:owners][property] = 'Alice'
state[:cash]['Bob'] = 0
state[:phase], state[:current_player] = :trade_response, 'Bob'
[[[property], 0], [[], 10], [[property], 10]].each do |given, money|
  state[:trade_offer] = {from: 'Alice', target: 'Bob', give_properties: given, receive_properties: [],
    give_cash: money, receive_cash: 0}
  replay = GameRoomGames::Replay.new(players: state[:players], current_player: 'Bob', state: state, history: [], accepted_events: [])
  assert(game.send(:monopoly_trade_safe?, state, 'Bob'), 'A poor bot rejected a legal free gift')
  actions = game.legal_actions(replay, 'Bob')
  chosen = game.bot_strategy.choose(actions: actions, actor: 'Bob', game: game, replay: replay, random_source: NewGames116Random.new)
  assert(chosen['action'] == 'trade_accept', 'Actual bot chooser rejected the gift')
end
state[:trade_offer][:receive_cash] = 1
assert(!game.send(:monopoly_trade_safe?, state, 'Bob'), 'Unaffordable purchase was treated as a gift')

reference = FullPortfolioTradeMonopoly.new
players = %w[Alice Bob Carol Dave]
profiles = GameRoomContent::MonopolyBoards.choices.values_at(0, -1).map(&:value).uniq
checked = 0
profiles.each do |board|
  3.times do |variant|
    state = game.send(:initial_state, players, game.normalize_options('board' => board))
    state[:cash].transform_values! { 5000 }
    state[:board].select { |square| square[:price] }.each_with_index do |square, index|
      state[:owners][square[:index]] = players[(index + variant) % players.length]
    end
    players.each do |player|
      state[:current_player] = player
      replay = GameRoomGames::Replay.new(players: players, current_player: player, state: state, history: [], accepted_events: [])
      original = Marshal.dump(state)
      actions = game.legal_actions(replay, player)
      actions.select { |action| action['action'] == 'trade_offer' }.each do |action|
        offer = game.send(:parse_trade_offer, state, action['offer']).merge(from: player)
        players.each do |viewer|
          assert(game.send(:trade_gain, state, offer, viewer) == reference.send(:trade_gain, state, offer, viewer),
            'Affected-group valuation differs from the complete portfolio calculation')
          checked += 1
        end
      end
      actual_rng, reference_rng = GameRoomRandom::SeededSource.new(77), GameRoomRandom::SeededSource.new(77)
      decisions = [game, reference].zip([actual_rng, reference_rng]).map do |model, rng|
        model.bot_strategy.choose(actions: actions, actor: player, replay: replay, game: model, random_source: rng)
      end
      assert(decisions.uniq.size == 1, 'Optimization changed the selected strategy')
      assert(actual_rng.roll(count: 2, sides: 1000).values == reference_rng.roll(count: 2, sides: 1000).values, 'Optimization consumed extra randomness')
      assert(Marshal.dump(state) == original, 'Hypothetical valuation changed game state')
    end
  end
end
puts "PASS Monopoly gifts and #{checked} independent portfolio comparisons: identical choices, RNG and unmodified state"
