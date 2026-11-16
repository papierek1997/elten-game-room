require_relative '../../support/new_games_fixture'

game = GameRoomGames::Yahtzee.new
players = %w[Alice Bob]
repository = NewGames116Repository.new(players)
options = game.default_options
keys = %w[ones twos threes fours fives sixes three_kind four_kind full_house
  small_straight large_straight yahtzee chance pair two_pairs misery]
labels = keys.zip(['Ones', 'Twos', 'Threes', 'Fours', 'Fives', 'Sixes', 'Three of a kind',
  'Four of a kind', 'Full house', 'Small straight', 'Large straight', 'Yahtzee',
  'Chance', 'One pair', 'Two pairs', 'Misery']).to_h
special = {'three_kind' => 40, 'four_kind' => 40, 'full_house' => 40,
  'small_straight' => 40, 'large_straight' => 40, 'yahtzee' => 50,
  'chance' => 40, 'pair' => 30, 'two_pairs' => 30, 'misery' => 40}

assert(game.effective_option_definitions.map(&:key).sort == %w[bot_delay extra_categories matches upper_bonus],
  'Settings still expose the bonus/Joker switches')
assert(!options.key?('yahtzee_bonus') && !options.key?('joker_rule'), 'Retired settings remain in game options')
assert(game.normalize_options(options.merge('yahtzee_bonus' => true, 'joker_rule' => true)) == options,
  'Old remembered switches restored the retired rules')
assert(game.options_from_json(JSON.generate(options)) == options, 'Saved options changed on JSON round trip')
assert(!game.options_summary(options).match?(/Joker|bonus/), 'Retired switches remain in the summary')

# Every face and prior Yahtzee entry uses the same special score table.
# Check the model, real action validation, the surface and score sheet together.
1.upto(6) do |face|
  [nil, 0, 50].each do |previous|
    state = game.send(:initial_state, players, options)
    state[:sheets]['Alice']['yahtzee'] = previous unless previous.nil?
    state.update(dice: Array.new(5, face), turn_rolls: 3)
    replay = GameRoomGames::Replay.new(players: players, current_player: 'Alice',
      state: state, accepted_events: [], history: [])
    unused = keys - state[:sheets]['Alice'].keys
    assert(game.legal_actions(replay, 'Alice').map { |action| action['category'] } == unused,
      "#{face}/#{previous}: a category is forced or missing")
    surface = game.surface_spec(replay, 'Alice')
    assert(surface.categories.map(&:id) == unused, 'Surface categories differ from legal actions')
    unused.each do |category|
      upper = %w[ones twos threes fours fives sixes].index(category)
      expected = upper ? (upper + 1 == face ? 5 * face : 0) : special.fetch(category)
      actual = game.send(:score_category, category, state[:dice], state, 'Alice')
      assert(actual == expected, "#{face}/#{previous}/#{category}: #{actual} instead of #{expected}")
      choice = surface.categories.find { |item| item.id == category }
      assert(choice.label == "#{labels.fetch(category)}: #{expected} points",
        'The surface displayed a different score')
      assert(game.action_for({'action' => 'score', 'category' => category}, replay, 'Alice').first == :ok,
        "#{face}/#{previous}/#{category}: legal scoring was refused")
    end
    assert(game.score_sheet_choices(state, 'Alice').none? { |choice| choice.label.start_with?('Additional Yahtzee bonuses:') },
      'The retired bonus line remains on the score sheet')
  end
end

# Full score sheets through action/event/replay, including repeated Yahtzees,
# restoration from serialized events, category reuse and the final result.
events = []
session = {'options' => JSON.generate(options)}
replay = game.replay(session, events, repository)
keys.each do |category|
  players.each do |actor|
    events << {'id' => events.length + 1, 'actor' => actor, 'action' => 'roll', 'value' => '1,1,1,1,1'}
    replay = game.replay(session, events, repository)
    replay = append_action(game, session, repository, events, replay, actor,
      {'action' => 'score', 'category' => category})
    assert(replay.accepted_events == events, 'Replay rejected a scoring event')
    assert(game.replay(session, JSON.parse(JSON.generate(events)), repository).state == replay.state,
      'Restoring the saved event history changed the score sheet')
    if category != keys.last
      assert(game.action_for({'action' => 'score', 'category' => category}, replay, actor).first != :ok,
        'An already filled category could be reused')
    end
  end
end
assert(replay.finished? && replay.draw, 'The equal complete sheets did not finish in a draw')
assert(replay.state[:totals] == {'Alice' => 395, 'Bob' => 395}, 'The complete score table total is incorrect')
assert(replay.history.none? { |entry| entry.key.to_s.start_with?('yahtzee_bonus:') }, 'A game announced a 100-point bonus')

# A bot can use the new scores even after sacrificing Yahtzee.
state = game.send(:initial_state, players, options)
state[:sheets]['Alice'] = keys.to_h { |category| [category, 0] }.except('full_house', 'chance')
state.update(dice: [1, 1, 1, 1, 1], turn_rolls: 3)
view = GameRoomGames::Replay.new(players: players, current_player: 'Alice', state: state,
  history: [], accepted_events: [])
choice = game.legal_actions(view, 'Alice').max_by { |action| game.bot_action_score(view, 'Alice', action) }
assert(choice['category'] == 'full_house', 'Bot did not use the special Full house score')
assert(game.action_for(choice, view, 'Alice').first == :ok, 'The bot chose an invalid score')

puts 'PASS Yahtzee special scoring: all six faces, every category and prior entry, complete saved replay, settings, surface and bot choice'
