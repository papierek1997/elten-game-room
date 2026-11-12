require_relative '../../support/dealt_card_games'
require_relative '../../../lib/game_sounds'
include GameRoomTest::Assertions

# Produce every result through the ordinary legal action/replay path. Do not
# write a winner, scores or terminal phase into a prepared model.
def finish_dealt_match(table)
  before = nil
  5000.times do
    break if table.replay.finished?

    before = table.replay
    if table.state[:phase] == :round_complete
      assert_equal(:ok, table.deal, 'Next legal round deal was refused')
    else
      assert_equal(:playing, table.state[:phase], 'Unexpected ordinary round phase')
      table.play
    end
  end
  assert(table.replay.finished?, 'Legal match did not reach its ordinary result')
  assert(before && !before.finished?, 'The terminal accepted transition was not captured')
  assert_equal(table.events, table.replay.accepted_events,
    'A normally produced event was rejected or disappeared from the terminal replay')
  [before, table.replay]
end

cases = [
  ['scopa', 2, {}, 1],
  ['scopa', 4, {'team_size' => 2}, 2],
  ['scopa', 6, {'team_size' => 2}, 3],
  ['scopa', 6, {'team_size' => 3}, 4],
  ['bouillabaisse', 2, {}, 5]
]
accepted = 0
cases.each do |id, count, options, seed|
  options = {'score_limit' => 1, 'two_point_lead' => false}.merge(options) if id == 'scopa'
  table = GameRoomTest::DealtCardTable.new(id, count: count, options: options, seed: seed)
  before, finished = finish_dealt_match(table)
  accepted += table.events.length
  current_options = table.game.options_from_json(table.session['options'])
  # The public result exporter is an independent oracle: it does not call
  # bot_reward, and its winners are canonical units rather than member names.
  result = table.game.tournament_result(finished, options: current_options)
  winners = result[:winners].flat_map { |unit| result[:units].fetch(unit) }
  if id == 'scopa' && options['team_size']
    assert_equal(options['team_size'], winners.length,
      'The legal team fixture did not finish with exactly one winning team')
    assert(finished.winner.start_with?('team:'), 'The result did not use a team ID')
  end
  frozen_input = Marshal.dump([table.session, table.events, before, finished,
    table.instance_variable_get(:@random)])
  cold = table.game.build_session_game.replay(table.session, table.events, table.repository)
  assert_equal(finished, cold, 'Cold reconstruction changed the accepted result')

  finished.players.each do |player|
    expected = result[:draw] ? 0.0 : winners.include?(player) ? 1.0 : -1.0
    expected_cue = expected.positive? ? 'win_party' : expected.negative? ? 'lose_party' : nil
    [player, player.upcase].each do |viewer|
      label = "#{id}/#{count}/#{options['team_size'] || 0}/#{viewer}"
      assert_equal(expected_cue, GameRoomSounds.result_cue(table.game, before, finished, viewer),
        "Wrong final cue for #{label}; winner=#{finished.winner.inspect}")
      assert_equal(expected, table.game.bot_reward(finished, viewer), "Wrong unit reward for #{label}")
      assert_equal(0.0, table.game.bot_reward(before, viewer), "Unfinished reward for #{label}")
      assert_equal(nil, GameRoomSounds.result_cue(table.game, nil, cold, viewer),
        "Cold reconstruction replayed the result cue for #{label}")
      assert_equal(nil, GameRoomSounds.result_cue(table.game, finished, cold, viewer),
        "Refreshing a finished match replayed the result cue for #{label}")
    end
  end
  assert_equal(result[:draw] ? 0.0 : -1.0, table.game.bot_reward(finished, 'Observer'),
    'A foreign actor acquired a winning team reward')
  assert_equal(nil, GameRoomSounds.result_cue(table.game, before, finished, 'Observer'),
    'An observer heard a participant result cue')
  assert_equal(frozen_input, Marshal.dump([table.session, table.events, before, finished,
    table.instance_variable_get(:@random)]), 'Result inspection changed state, history or subsequent RNG')
end

puts "PASS five legal dealt-card results: single/team4/team6, unit rewards, case folding, observer/cold/refresh silence and immutable input (#{accepted} accepted events)"
