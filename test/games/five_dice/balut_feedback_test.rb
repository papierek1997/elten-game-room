require_relative '../../support/cat_head_tail'
require_relative '../../../games/balut'
require_relative '../../../lib/game_sounds'

game = GameRoomGames::Balut.new
repository = CatHeadTailRepository.new(%w[Alice Bob])
turn = lambda do |events, actor, dice, category|
  events << cht_event(events.length + 1, actor, 'roll', dice.sort.join(','))
  before = game.replay({}, events, repository)
  score = cht_event(events.length + 1, actor, 'score', category)
  events << score
  after = game.replay({}, events, repository)
  assert(after.accepted_events.length == events.length, 'A feedback fixture was refused')
  entries = after.history.select { |entry| entry.event_id == score['id'] }
  cue = GameRoomSounds.event_cue(game: game, event: score, before_replay: before,
    after_replay: after, repository: repository, viewer: actor)
  assert(game.replay({}, events, repository) == after, 'Cold replay changes or repeats feedback')
  [entries, cue, after]
end

events = []
[[4] * 5, [4] * 5, [1, 1, 4, 4, 4]].each_with_index do |dice, index|
  entries, cue = turn.call(events, 'Alice', dice, 'fours')
  if index == 2
    assert(entries.map(&:text) == ['Alice records 12 in Fours, entry 3.',
      'Alice earns 2 game points for Fours.', 'Alice: game points: 0.'], 'The category threshold lacks a clear, ordered reason and game total')
    assert(cue == 'kosciane_column_3_win1', 'The threshold does not use the common column/bonus recording')
  else
    assert(entries.length == 1, 'Unchanged category points create extra speech')
  end
  turn.call(events, 'Bob', [1, 1, 1, 1, 2], 'choice') if index < 2
end

events = []
{fours: [4] * 5, fives: [5] * 5, sixes: [6] * 5}.each do |category, dice|
  4.times do
    entries, cue, replay = turn.call(events, 'Alice', dice, category)
    if replay.state[:sheets]['Alice'].values.sum(&:sum) == 300
      assert(entries.map(&:text) == ['Alice records 30 in Sixes, entry 4.',
        'Alice: points for the sum of recorded scores: -1.', 'Alice: game points: 5.'], 'The total-score adjustment has no reason or is mixed with category points')
      assert(cue == 'kosciane_column_4_win1', 'A better sum threshold has no success cue')
    end
    turn.call(events, 'Bob', [1] * 5, category)
  end
end

rules = GameRoomGames::BalutScoring
assert(!rules.row_points_possible?(:straight, [15, 0]), 'A zero can supposedly still complete four straights')
assert(!rules.row_points_possible?(:full_house, [0]), 'A zero can supposedly still complete four full houses')
assert(!rules.row_points_possible?(:fours, [0, 0]), 'Two remaining fours throws can supposedly reach 52')
assert(rules.row_points_possible?(:fours, [0, 12]), 'An exactly reachable 52-point target was hidden')
assert(rules.row_points_possible?(:straight, [15, 20, 15]), 'A still reachable straight bonus was hidden')
sheet = rules::CATEGORIES.to_h { |category| [category, []] }
sheet[:straight] = [15, 0]
sheet[:fours] = [0, 0]
sheet[:fives] = [25, 25, 25, 0]
state = {sheets: {'Alice'=>sheet}, dice: [1, 1, 1, 1, 2]}
readonly = game.send(:score_grid, state, 'Alice', writable: false)
assert(readonly.cells[0].last == 'No game points can be earned in this category.', 'The numeric target still promises an impossible bonus')
assert(readonly.cells[3].last == 'No game points can be earned in this category.', 'The zeroed straight still promises a bonus')
assert(readonly.cells[1].last == 'Game points for this category: 2', 'An earned threshold disappears after a later zero')
assert(readonly.cells[2].last == 'Score still needed: 78', 'The numeric hint lost its score units')
assert(readonly.cells[4].last == 'Successful entries still needed: 4', 'The full-house hint lost its entry units')
assert(readonly.cells[0][5] == 'Sum of entries: 0', 'The row sum is confused with game points')
writable = game.send(:score_grid, state, 'Alice', writable: true)
assert(writable.cells.first.first == 'Fours: enter 0', 'The record action still suggests four final game points')
assert(game.score_sheet_choices(state, 'Alice').first.label.end_with?('No game points can be earned in this category.'), 'V disagrees with the grid about an impossible bonus')
puts 'PASS Balut feedback: accepted threshold and total transitions, ordered explanations, common bonus recordings, silent unchanged totals, cold replay and reachable/impossible row hints'
