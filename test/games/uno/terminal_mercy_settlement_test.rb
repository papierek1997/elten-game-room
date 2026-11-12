require_relative '../../support/new_games_fixture'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

game = GameRoomGames::Uno.new
repo = NewGames116Repository.new(%w[Alice Bob Carol])
[100, 5000].each do |score_limit|
  [0, 10].each do |mercy_limit|
    [%w[Alice Bob], %w[Alice Bob Carol]].each do |players|
      options = game.normalize_options('deck' => 'no_mercy', 'no_mercy_limit' => mercy_limit,
        'score_limit' => score_limit, 'thinking_time' => 0)
      state = game.send(:initial_state, players, options)
      hands = {'Alice' => ['RDa'], 'Bob' => %w[G0a G1a G2a G3a G4a G5a G6a G7a]}
      hands['Carol'] = ['Y1a'] if players.include?('Carol')
      state.update(phase: :playing, round: 1, current_player: 'Alice', colour: 'R',
        discard: ['R5a'], hands: hands, draw_pile: %w[B1a B2a B3a B4a])
      history = []
      [['Alice', 'play', 'RDa||0'], ['Bob', 'draw', '0']].each_with_index do |(actor, action, value), index|
        event = {'id' => index + 1, 'actor' => actor, 'action' => action, 'value' => value}
        assert(game.send(:apply_replay_event, state, event, {}, repo, history), 'The terminal penalty path was not legal')
      end
      assert_equal(1, history.count { |entry| entry.kind == :round_result },
        "One terminal penalty announced the round twice: #{[score_limit, mercy_limit, players.size].inspect}")
      scoring = history.select { |entry| entry.kind == :score }
      assert_equal(scoring.map(&:actor).uniq, scoring.map(&:actor), 'One player received duplicate round-score entries')
      assert_equal(0, state[:scores].fetch('Alice'))
      if mercy_limit.positive?
        assert_equal(250, state[:scores].fetch('Bob'), 'No Mercy penalty was lost or applied twice')
        assert_equal([], state[:hands].fetch('Bob'))
      else
        assert_equal(10, state[:hands].fetch('Bob').size, 'Closing the round skipped the actual penalty draw')
      end
      assert_equal(nil, state[:pending_finisher], 'A settled round retained a pending finisher')
      assert(!state.key?(:pending_finishers), 'A settled round retained a pending-finisher queue')
      assert_equal(players.size == 2 && mercy_limit.positive? && score_limit == 100 ? :finished : :round_complete, state[:phase])
    end
  end
end
puts 'PASS UNO terminal No Mercy: one round/score settlement, real penalty draw,2/3players, mercy disabled and final/nonfinal games'
