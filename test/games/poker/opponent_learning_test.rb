require_relative '../../support/new_games_fixture'

model = GameRoomPokerOpponents
entry = ->(field, data, id) { GameRoomGames::HistoryEntry.new(key: "learn:#{id}", event_id: id, actor: 'Bob', field: field, value: data) }
folds, calls = [], []
24.times do |hand|
  common = {'call' => 10, 'raise_by' => 0, 'hand' => hand, 'street' => 3}
  folds << entry.call('poker_bet', common.merge('action' => 'fold'), hand)
  calls << entry.call('poker_bet', common.merge('action' => 'call'), hand)
end
folder = model.profile(model.profiles(folds), 'BOB')
caller = model.profile(model.profiles(calls), 'bob')
assert(folder[:fold] > caller[:fold], 'Public repeated folds were not learned')
assert(model.fold_probability(folder, 0.5, 0) > model.fold_probability(caller, 0.5, 0), 'Learned calling station is bluffed like a frequent folder')

weak, value = [], []
18.times do |hand|
  bet = entry.call('poker_bet', {'action' => 'raise', 'call' => 10, 'raise_by' => 20, 'hand' => hand, 'street' => 3}, hand * 2)
  weak << bet
  value << bet
  weak << entry.call('poker_showdown', {'variant' => 'holdem', 'hand' => hand, 'category' => 0}, hand * 2 + 1)
  value << entry.call('poker_showdown', {'variant' => 'holdem', 'hand' => hand, 'category' => 5}, hand * 2 + 1)
end
bluffer = model.profile(model.profiles(weak), 'Bob')
honest = model.profile(model.profiles(value), 'Bob')
assert(bluffer[:weak_aggression] > honest[:weak_aggression], 'Revealed final-stage weak aggression was not learned')
assert(model.range_weight(bluffer, 2, 0.9) < model.range_weight(honest, 2, 0.9), 'Frequent bluffer still has the tight value range')
assert(model.profile(model.profiles(weak), 'Carol')[:observations].zero?, 'One opponent inherited another opponent profile')
neutral = model.profile({}, 'New player')
assert((model.range_weight(neutral, 1, 0.8) - 1.45).abs < 1e-10, 'Missing history weakened the neutral aggression model')
before = Marshal.dump(weak)
model.profiles(weak)
assert(before == Marshal.dump(weak), 'Learning changed historical entries')

# Integration: ordinary public betting creates evidence, not a scan of state hands.
game = GameRoomGames::Poker.new
repository = NewGames116Repository.new(%w[Alice Bob Carol])
session, events = {'options' => JSON.generate(game.default_options)}, []
replay = game.replay(session, events, repository)
replay = append_action(game, session, repository, events, replay, 'Alice', game.automatic_action(replay, 'Alice'), context_for)
actor = replay.current_player
move = game.legal_actions(replay, actor).find { |action| %w[call check].include?(action['action']) }
replay = append_action(game, session, repository, events, replay, actor, move)
record = replay.history.find { |item| item.field == 'poker_bet' }
assert(record && record.value['action'] == move['action'], 'Accepted bet did not expose typed public evidence')
assert(!record.value.key?('cards'), 'Bet evidence disclosed a concealed hand')
ranges = game.send(:poker_public_ranges, replay)
assert(model.profile(ranges[:profiles], actor)[:observations] == 1, 'The accepted public action was not learned')
assert(ranges.equal?(game.send(:poker_public_ranges, replay)), 'Public model rebuilt for each legal action')
poisoned = Marshal.load(Marshal.dump(replay))
poisoned.state[:hands].each { |player, hand| hand.reverse! if player != actor }
assert(ranges == game.send(:poker_public_ranges, poisoned), 'Model learned from actual foreign hands')

# The same low-equity river hand adapts its actual legal action to public
# opponent history. Hidden cards are arbitrary and never read by the model.
state = game.send(:initial_state, %w[Alice Bob], game.default_options)
state.update(phase: :betting, current_player: 'Alice', street: 3,
  hands: {'Alice'=>%w[7C 2D], 'Bob'=>%w[AH AD]}, community: %w[TS 3H 9S 6H 5S],
  stacks: {'Alice'=>50,'Bob'=>50}, street_bets: {'Alice'=>0,'Bob'=>0},
  contributions: {'Alice'=>50,'Bob'=>50}, current_bet: 0, min_raise: 10, hand_number: 100,
  folded: {}, all_in: {}, acted: {})
chosen = [folds, calls].map do |history|
  position = GameRoomGames::Replay.new(players: %w[Alice Bob], current_player: 'Alice', state: state,
    accepted_events: [], history: history)
  actions = game.legal_actions(position, 'Alice')
  action = actions.max_by { |item| game.bot_action_score(position, 'Alice', item) }
  assert(game.action_for(action, position, 'Alice').first == :ok, 'Adaptation bypassed ordinary bet validation')
  action
end
assert(chosen.first['amount'] == 50 && chosen.last['action'] == 'check', 'Learning never changed the actual bluff/check decision')
puts 'PASS public opponent learning, smoothed folds/aggression/showdowns, identity isolation, cache and concealed-hand boundary'
