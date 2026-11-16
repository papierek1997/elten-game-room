require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions

game = GameRoomGames::HeartsTable.new
assert_equal(100, game.default_options['score_limit'])
assert(game.validation_error({'score_limit'=>0}, player_count:4), 'Zero point limit accepted')
assert(game.validation_error({'score_limit'=>-1}, player_count:4), 'Negative point limit accepted')
assert_equal(nil, game.validation_error({'score_limit'=>30}, player_count:4))
table = GameRoomTest::DealtCardTable.new('hearts', count:4, options:{'score_limit'=>1}, seed:137)
table.play_strategy while table.state[:phase] == :passing
actor = table.replay.current_player
bad = table.state[:hands][actor].find { |card| card != '2C' }
before = Marshal.dump(table.replay)
status, plan = game.action_for({'kind'=>'card','action'=>'select','zone'=>'hand','card'=>bad}, table.replay, actor)
assert_equal(:hearts_opening_club, status)
assert_equal(nil, plan)
assert_equal('You must start with the two of clubs.', game.move_error(status))
assert_equal(before, Marshal.dump(table.replay), 'Refusal changed the hand or history')
assert_equal(:not_your_turn, game.action_for({'kind'=>'card','action'=>'select','zone'=>'hand','card'=>bad}, table.replay,
  table.replay.players.find { |player| player != actor }).first)
assert_equal(:card_not_in_hand, game.action_for({'kind'=>'card','action'=>'select','zone'=>'hand','card'=>'XX'}, table.replay, actor).first)

# These small public positions isolate the reason while still using the actual
# action validator and HeartsRules legal-card calculation.
cases = [
  {hand:%w[3C 4D], trick:[['Bob','2C']], count:1, broken:false, card:'4D', status: :must_follow_suit},
  {hand:%w[3D QS], trick:[['Bob','2C']], count:1, broken:false, card:'QS', status: :hearts_first_trick},
  {hand:%w[3D 4H], trick:[], count:4, broken:false, card:'4H', status: :hearts_not_broken}
]
cases.each do |position|
  state = Marshal.load(Marshal.dump(table.state))
  state.merge!(phase: :playing, current_player:actor, trick:position[:trick],
    play_count:position[:count], hearts_broken:position[:broken])
  state[:hands][actor] = position[:hand]
  replay = table.replay.dup
  replay.state, replay.current_player = state, actor
  status, plan = game.action_for({'kind'=>'card','action'=>'select','zone'=>'hand','card'=>position[:card]}, replay, actor)
  assert_equal(position[:status], status)
  assert_equal(nil, plan)
  assert(game.move_error(status) != game.move_error(:invalid), 'Specific refusal lost its explanation')
end

# Complete the real match, retaining the normal extra-deal rule for a tied low
# score. Default 100 would keep this exact low-limit match running.
table.finish_production_round
if table.state[:scores].values.count(table.state[:scores].values.min) > 1
  assert(!table.replay.finished?, 'A tied lowest score stopped the match')
end
table.finish_production_match
assert(table.replay.finished? && table.state[:scores].values.max < 100, 'Configured limit does not govern settlement')
assert_equal(table.state[:scores].values.min, table.state[:scores].fetch(table.replay.winner))
scores = game.game_shortcuts(table.replay, actor).find { |key| key.key == 's' && key.modifiers.empty? }
assert(scores.message.end_with?("\nScore limit: 1 point."), 'S does not append the actual target last')
puts 'PASS Hearts configurable limit, real low-limit match, all four refusal reasons, turn/ownership precedence and unchanged rejected state'
