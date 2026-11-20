require_relative "../../support/cat_head_tail"
require_relative "../../../games/yahtzee"

game = GameRoomGames::Yahtzee.new
repository = CatHeadTailRepository.new(%w[Alice Bob])
options = game.default_options.merge('extra_categories' => false, 'upper_bonus' => false)
session = {'options' => JSON.generate(options)}
build_match = lambda do |alice_dice, bob_dice|
  events = []
  GameRoomGames::Yahtzee::STANDARD_CATEGORIES.each do |category|
    [['Alice', alice_dice], ['Bob', bob_dice]].each do |actor, dice|
      events << cht_event(events.length + 1, actor, 'roll', dice)
      events << cht_event(events.length + 1, actor, 'score', category)
    end
  end
  events
end
[['1,2,3,4,5', '1,2,3,4,5', true], ['6,6,6,6,6', '1,1,1,1,1', false]].each do |alice, bob, draw|
  events = build_match.call(alice, bob)
  finished = game.replay(session, events, repository)
  assert(finished.finished? && finished.draw == draw && finished.accepted_events.length == 52, 'fixture must genuinely finish expected result')
  late = [cht_event(53, finished.current_player, 'roll', '1,2,3,4,5'), cht_event(54, finished.current_player, 'score', 'ones')]
  replay = game.replay(session, events + late, repository)
  assert(replay.to_h == finished.to_h, "finished #{draw ? 'draw' : 'win'} accepted or displayed a late event")
  assert(game.legal_actions(replay, replay.current_player).empty?, 'finished game exposes actions')
  assert(game.round_timing_event_ids(finished, repository: repository) == [nil, 52], 'final sheet duration has the wrong end boundary')
end
multi = {'options' => JSON.generate(options.merge('matches' => 2))}
first = build_match.call('1,2,3,4,5', '1,2,3,4,5')
next_sheet = game.replay(multi, first, repository)
assert(!next_sheet.finished? && next_sheet.state[:match] == 2, 'intermediate tied sheet ended multi-match game')
assert(game.round_timing_event_ids(next_sheet, repository: repository) == [52, nil], 'second sheet duration did not restart')
continued = game.replay(multi, first + [cht_event(53, next_sheet.current_player, 'roll', '1,2,3,4,5')], repository)
assert(continued.accepted_events.length == 53 && continued.state[:turn_rolls] == 1, 'new sheet rejected legitimate next roll')
puts 'Yahtzee: terminal draw/win reject late roll/score; intermediate sheet continues OK'
