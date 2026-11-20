require_relative '../../support/new_games_fixture'
game = GameRoomGames::Poker.new
model = GameRoomPokerOpponents
neutral = model.profile({}, 'B')
assert(model.call_weight(neutral, 0, 0.1, 0.5) == 1, 'No call invented evidence')
assert(model.call_weight(neutral, 1, 0.1, 0.5) < model.call_weight(neutral, 1, 0.1, 0.05), 'A large call did not narrow weak hands')
assert(model.call_weight(neutral, 1, 0.9, 0.5) > model.call_weight(neutral, 1, 0.9, 0.05), 'A large call did not support stronger hands')
assert(model.call_weight(neutral.merge(fold:0.05), 1, 0.1, 0.5) > model.call_weight(neutral, 1, 0.1, 0.5), 'A calling station got a tight range')

state = game.send(:initial_state, %w[A B], game.default_options)
state.update(phase: :betting, current_player:'A', street:3, hand_number:1,
  hands:{'A'=>%w[KS 9S], 'B'=>%w[2C 3C]}, community:%w[QC TH JD 7S 6C],
  stacks:{'A'=>400,'B'=>400}, contributions:{'A'=>600,'B'=>600},
  street_bets:{'A'=>0,'B'=>0}, current_bet:0)
events = [{'id'=>1, 'actor'=>'A', 'action'=>'deal'},
  {'id'=>2, 'actor'=>'B', 'action'=>'bet', 'value'=>'call|400'}]
entry = GameRoomGames::HistoryEntry.new(event_id:2, actor:'B', field:'poker_bet',
  value:{'action'=>'call','call'=>400,'paid'=>400,'pot'=>800,'raise_by'=>0,'hand'=>1,'street'=>0})
replay = GameRoomGames::Replay.new(players:%w[A B], current_player:'A', state:state,
  history:[entry], accepted_events:events)
before = Marshal.dump(replay)
ranges = game.send(:poker_public_ranges, replay)
assert(ranges[:decisions]['B'][0][:calls] == 1, 'Accepted preflop call was ignored')
assert(ranges[:decisions]['B'][0][:call_price] == 1.0 / 3, 'Call price ignored paid amount/pot')
game.send(:poker_equity, state, 'A', ranges:ranges)
worlds = game.instance_variable_get(:@poker_worlds)
assert(worlds.length == 256, 'Equity budget changed')
strengths = game.send(:poker_range_strengths, worlds, state[:community], 0, 'holdem', {})
other = game.send(:poker_range_strengths, worlds, state[:community].reverse, 0, 'holdem', {})
assert(strengths == other, 'Preflop evidence used a later board')
weighted = game.instance_variable_get(:@poker_samples).map { |_,rivals| rivals['B'][1] }
expected = strengths.map { |seats| model.call_weight(model.profile(ranges[:profiles], 'B', street:0, pressure:1.0/3), 1, seats[0], 1.0/3) }
assert(weighted == expected, 'Integration used current-street instead of call-street strength')
changed = Marshal.load(Marshal.dump(ranges))
changed[:decisions]['B'][0][:call_price] = 0.5
game.send(:poker_equity, state, 'A', ranges:changed)
assert(game.instance_variable_get(:@poker_worlds).equal?(worlds), 'Changing evidence resampled the cards')
assert(game.instance_variable_get(:@poker_samples).map { |_,rivals| rivals['B'][1] } != weighted,
  'Changing the price reused stale likelihood weights')
assert(Marshal.dump(replay) == before, 'Planning changed the replay')

poisoned = Marshal.load(before)
poisoned.state[:hands]['B'] = %w[AS AH]
poisoned.state[:deck] = %w[AS AH AD AC]
poisoned.state[:seed] = 'do not read'
def scores(game, replay)
  game.legal_actions(replay, 'A').map { |action| [action, game.bot_action_score(replay, 'A', action)] }
end
assert(scores(GameRoomGames::Poker.new, replay) == scores(GameRoomGames::Poker.new, poisoned), 'Hidden hand/deck changed a decision')
entry.value['paid'] = 0
entry.value['call'] = 0
entry.value['action'] = 'check'
events.last['value'] = 'check|0'
free = game.send(:poker_public_ranges, Marshal.load(Marshal.dump(replay)))
assert(free[:decisions].empty?, 'A free check was treated as a paid call')

royal = Marshal.load(Marshal.dump(state))
royal[:community] = %w[TS JS QS KS AS]
royal[:hands]['A'] = %w[2C 3D]
assert(game.send(:poker_equity, royal, 'A', ranges:ranges) == 0.5, 'Common royal flush is not a shared pot')
worlds = game.instance_variable_get(:@poker_worlds)
strengths = game.send(:poker_range_strengths, worlds, royal[:community], 3, 'holdem', {})
assert(strengths.flatten.uniq == [0.5], 'A shared board invented private card strength')
puts 'PASS unweighted-world reuse, weight invalidation, common-board ties and street-specific inference'
puts 'PASS accepted call/price/style evidence, street chronology, bounded worlds, nonmutation and hidden-information independence'
