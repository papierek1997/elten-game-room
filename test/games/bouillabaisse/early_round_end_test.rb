require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions

[false, true].each do |all_or_nothing|
  table = GameRoomTest::DealtCardTable.new('bouillabaisse', count: 3, seed: 1,
    options: {'all_or_nothing' => all_or_nothing})
  shortened = []
  6.times do |index|
    round = index + 1
    while table.state[:phase] == :playing
      table.play
      state = table.state
      next unless [2, 3, 4].include?(round) && state[:trick].empty?
      remaining = state[:round_deck] - state[:taken].values.flatten
      scoring = remaining.any? { |card| table.game.penalty_value(card, round, state[:penalties]).positive? }
      assert((state[:phase] == :playing) == scoring, "round #{round}: did not end exactly after the last scoring card")
    end
    state = table.state
    assert(state[:tournament_checkpoint]['index'] == round, 'shortened round lost its tournament score')
    if state[:hands].values.any? { |hand| !hand.empty? }
      shortened << round
      assert([2, 3, 4].include?(round), 'a round with scoring tricks ended early')
    end
    table.deal if round < 6
  end
  assert(shortened.include?(4), 'fixture did not exercise an early special-card round')
  assert(table.replay.finished? && table.state[:round] == 6, 'ending a round ended the entire match')
  assert(table.events.size == table.replay.accepted_events.size, 'early end rejected a real move')
  initial = table.game.replay(table.session, [], table.repository)
  incremental = table.game.incremental_replay(initial, table.session, table.events, table.repository)
  assert(incremental.state == table.replay.state, 'full and incremental early-end replays diverged')
end
puts 'PASS Bouillabaisse: scoring exhausted ends rounds 2-4, both all-or-nothing settings, full/incremental replay and final standings'
