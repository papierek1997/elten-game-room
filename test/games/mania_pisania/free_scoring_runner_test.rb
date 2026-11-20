require_relative '../../support/session_runner'
require_relative '../../../games/mania_pisania'

game = GameRoomGames::ManiaPisania.new
users = %w[Alice Bob]
cases = [
  ['A single fast word cannot outrank four correct words', [[4, 0, 82.8], [1, 0, 198.5]], 'Alice'],
  ['Word count takes precedence even when the shorter result has fewer errors', [[4, 8, 82.8], [1, 0, 198.5]], 'Alice'],
  ['Accuracy separates equal word counts', [[4, 1, 82.8], [4, 2, 198.5]], 'Alice'],
  ['Tempo separates equally accurate results with the same word count', [[4, 0, 82.8], [4, 0, 198.5]], 'Bob'],
  ['Identical results tie', [[4, 0, 82.8], [4, 0, 82.8]], nil],
  ['No correct words earns no round point', [[0, 3, 0.0], [0, 0, 0.0]], nil]
]

cases.each_with_index do |(description, reports, winner), index|
  harness = NativeRoomHarness.new(game: game, users: users, options: {'variant'=>'free', 'text'=>'apple_tree', 'minutes'=>10})
  harness.start
  runners = users.to_h { |name| [name, runner_for(harness, name)] }
  begin
    step(harness, runners.fetch('Alice'), 'Alice', count: 2)
    users.zip(reports).reverse_each do |name, (words, errors, wpm)|
      result = {'words'=>words, 'errors'=>errors, 'wpm'=>wpm, 'levels'=>0,
        'elapsed_ms'=>wpm.positive? ? (words * 60_000 / wpm).round : 0, 'assisted'=>false}
      harness.as(name) do
        replay = harness.replay(name)
        data = {'typing_result'=>{'round'=>replay.state[:round], 'result'=>result}}
        runners.fetch(name).publish_view(session: harness.session, replay: replay, busy: false,
          context: GameRoomGames::ActionContext.new(local_data: data))
      end
      step(harness, runners.fetch(name), name, count: 2)
    end
    harness.assert_converged(description)
    replay = harness.replay('Bob')
    assert(replay.finished? && replay.winner == winner && replay.draw == winner.nil?, description)
    if reports.all? { |words, _errors, _wpm| words.zero? }
      assert(game.participant_scores(replay).values.all?(&:zero?), 'An empty result was awarded a point')
    end
    if index.zero?
      assert(game.surface_spec(replay, 'Alice').status.include?('4 words, 0 errors, 82.8 WPM. Score: 4.0;'),
        'The status must show the word-count score alongside the measured WPM')
    end
  ensure
    runners.each_value(&:close)
  end
end
puts 'PASS multiplayer Free Typing ranks by correct words, accuracy and then typing speed'
