require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions

(2..8).each do |count|
  t = GameRoomTest::DealtCardTable.new('bouillabaisse', count: count, seed: count)
  game = t.game
  assert(game.default_options['all_or_nothing'], 'all or nothing not enabled')
  assert(t.state[:hands].values.map(&:size).uniq == [52 / count], 'uneven deck')
  assert(t.state[:hands].values.flatten.uniq.size == 52 - 52 % count, 'duplicate cards')
  penalties = t.state[:penalties].dup
  6.times do |round|
    assert(t.state[:penalties] == penalties, 'penalties changed')
    assert(t.state[:round] == round + 1, 'wrong round')
    assert(t.game.surface_spec(t.replay, 'Spectator').is_a?(GameSurfaces::QuestionSpec), 'spectator received a hand')
    wrong = t.replay.players.find { |actor| actor != t.replay.current_player }
    action = t.game.legal_actions(t.replay, t.replay.current_player).first
    assert(t.act(wrong, action) == :not_your_turn, 'wrong player could play')
    t.finish_round
    played = t.state[:taken].values.flatten
    remaining = t.state[:hands].values.flatten
    assert((played + remaining).uniq.size == 52 - 52 % count, 'missing dealt card')
    assert((played & remaining).empty?, 'captured card remained in a hand')
    assert(remaining.empty? || [2, 3, 4].include?(round + 1) &&
      remaining.none? { |card| game.penalty_value(card, round + 1, penalties).positive? }, 'scoring cards remain at round end')
    old_dealer = t.state[:dealer]
    t.deal if round < 5
    assert(t.state[:dealer] == (old_dealer + 1) % count, 'dealer did not rotate') if round < 5
  end
  assert(t.replay.finished?, 'six rounds did not end game')
  assert(t.events.size == t.replay.accepted_events.size, 'a generated legal move was rejected')
  result = t.game.tournament_placement_scores(t.replay, options: t.game.default_options)
  assert(result[:order] == 'lower' && result[:scores] == t.state[:scores], 'tournament order inverted')
end

t = GameRoomTest::DealtCardTable.new('bouillabaisse', options: {'all_or_nothing' => false})
state = t.state
actor = state[:current_player]
led = state[:hands][actor].first
assert(t.act(actor, {'kind'=>'card','action'=>'select','zone'=>'hand','card'=>led}) == :ok, 'lead rejected')
next_actor = t.replay.current_player
following = t.state[:hands][next_actor].select { |card| card[1] == led[1] }
off = t.state[:hands][next_actor].find { |card| card[1] != led[1] }
if following.any? && off
  assert(t.act(next_actor, {'kind'=>'card','action'=>'select','zone'=>'hand','card'=>off}) == :must_follow_suit, 'revoke accepted')
end
penalties = {'suit'=>'H', 'rank'=>'Q', 'card'=>'QH'}
assert(t.game.penalty_value('QH', 5, penalties) == 260, 'overlapping penalties not cumulative')
assert(t.game.penalty_value('QH', 4, penalties) == 200, 'round 4 includes other penalties')
[1,2,3,4,5,6].each do |round|
  state = t.state.dup
  state[:round], state[:phase] = round, :playing
  state[:scores] = {'Alice'=>0, 'Bob'=>0}
  state[:tricks] = {'Alice'=>26, 'Bob'=>0}
  state[:taken] = {'Alice'=>t.game.deck_for(2), 'Bob'=>[]}
  state[:penalties] = penalties
  state[:options] = t.game.default_options
  t.game.send(:score_round, state, {'id'=>999}, t.repository, [])
  raw = ([1,5,6].include?(round) ? 130 : 0) + t.game.deck_for(2).sum { |card| t.game.penalty_value(card, round, penalties) }
  expected = round == 4 || round == 6 ? raw : -raw
  assert(state[:scores]['Alice'] == expected, "all-or-nothing round #{round}")
end
puts 'PASS Bouillabaisse: 2–8 players, six rounds, trims, rotation, follow suit, cumulative penalties, all or nothing, tournament order'
