require_relative '../../support/duck_challenge_native'
require_relative '../../support/cat_head_tail'
require_relative '../../support/localization'
require_relative '../../../games/kosciane'
require_relative '../../../games/balut'

# Use accepted turns, not a second sheet model. Earlier entries occupy only
# the target row, so other rows still offer their first column.
def column_entry_trial(game, filled, columns: 3)
  players = %w[Alice Bob]
  repository = CatHeadTailRepository.new(players)
  session = {'options'=>JSON.generate(game.default_options.merge('columns'=>columns))}
  events = []
  general = game.id == 'kosciane'
  filled.times do
    events << cht_event(events.size + 1, 'Alice', 'roll', general ? '3,3,3,5,5' : '4,4,4,4,6')
    events << cht_event(events.size + 1, 'Alice', 'score', general ? 'full_house' : 'fours')
    events << cht_event(events.size + 1, 'Bob', 'roll', '6,6,6,6,6')
    events << cht_event(events.size + 1, 'Bob', 'score', general ? '6' : 'choice')
  end
  3.times { events << cht_event(events.size + 1, 'Alice', 'roll', '1,5,5,5,5') }
  replay = game.replay(session, events, repository)
  assert(replay.accepted_events.size == events.size, 'Column fixture contains a refused turn')
  [session, events, repository, replay]
end

expected = {
  'en'=>['Full house: record 0, column 3 of 3', 'Fours: enter 0, column 4 of 4'],
  'pl'=>['Full: do zapisu 0, kolumna 3 z 3', 'Czwórki: zapisz 0, kolumna 4 z 4'],
  'cs'=>['Full house: k zápisu 0, sloupec 3 z 3', 'Čtyřky: zapsat 0, sloupec 4 z 4'],
  'es'=>['Full: anotar 0, columna 3 de 3', 'Cuatros: anotar 0, columna 4 de 4'],
  'ru'=>['Фулл-хаус: записать 0, столбец 3 из 3', 'Четвёрки: записать 0, столбец 4 из 4']
}
games = [GameRoomGames::Kosciane.new, GameRoomGames::Balut.new]
expected.each do |language, labels|
  GameRoomTestLocalization.use_language(language)
  games.each_with_index do |game, index|
    general = index.zero?
    category = general ? 'cross:full_house' : 'fours'
    filled = general ? 2 : 3
    session, events, repository, replay = column_entry_trial(game, filled)
    before = Marshal.dump(replay)
    grid = game.send(:score_grid, replay.state, 'Alice', writable: true)
    row = grid.row_actions.index { |action| action['category'] == category }
    assert(row, 'Zero result disappeared from the writable sheet')
    assert(grid.cells[row].first == labels[index], "#{language}/#{game.id}: wrong proposed entry or destination")
    assert(grid.row_actions.size == (general ? replay.state[:match_model].categories.size : 7),
      'Column readout filtered or duplicated the available categories')
    bare = game.send(:category_label, general ? :full_house : :fours)
    readonly = game.send(:score_grid, replay.state, 'Alice', writable: false)
    assert(readonly.cells.any? { |cells| cells.first == bare }, 'Read-only inspection gained a proposed-entry label')

    surface = GameSurfaces.build(grid, state: {'x'=>0, 'y'=>row})
    driver = DuckChallengeNativeDriver.new
    form = driver.form(surface)
    SpeechOutput.reset
    form.focus
    assert(SpeechOutput.calls.size == 1 && SpeechOutput.calls.first.first.scan(labels[index]).size == 1,
      "#{language}/#{game.id}: native focus omits or repeats the column label")
    selections = []
    surface.on_action { |action| selections << action.to_h }
    SpeechOutput.reset
    driver.frame(form, driver.tap(0x27))
    driver.frame(form)
    assert(SpeechOutput.calls.none? { |call| call.first.include?(grid.header) }, 'Inspecting a past cell repeats the table header')
    assert(surface.state['x'] == 1, 'The historical-cell inspection did not move')
    assert(Marshal.dump(replay) == before, 'Building or reading the destination changes the game')
    driver.frame(form, driver.tap(0x0d))
    assert(selections.one? && selections.first['category'] == category, 'Enter from a past cell changes the destination action')
    assert(game.action_for(selections.first, replay, 'Alice').first == :ok, 'The announced zero cannot be recorded')
    after = game.replay(session, events + [cht_event(events.size + 1, 'Alice', 'score', category)], repository)
    values = general ? after.state[:match_model].sheet('Alice').fetch(:full_house) : after.state[:sheets]['Alice'].fetch(:fours)
    assert(values.size == filled + 1 && after.current_player == 'Bob', 'The entry did not use the announced first empty column')
  end
end

GameRoomTestLocalization.use_language('en')
[1, 6].each do |columns|
  _, _, _, replay = column_entry_trial(games.first, 0, columns: columns)
  label = games.first.score_grid(replay.state, 'Alice', writable: true).cells.first.first
  assert(label == "Ones: record 0, column 1 of #{columns}", 'General assumes three columns')
end
games.each_with_index do |game, index|
  _, _, _, replay = column_entry_trial(game, index.zero? ? 3 : 4, columns: index.zero? ? 6 : 3)
  grid = game.send(:score_grid, replay.state, 'Alice', writable: true)
  if index.zero?
    row = grid.row_actions.index { |action| action['category'] == 'cross:full_house' }
    assert(grid.cells[row].first == 'Full house: record 0, column 4 of 6', 'General does not follow the configured column count')
  else
    assert(grid.row_actions.none? { |action| action['category'] == 'fours' }, 'A completed Balut row still advertises another column')
  end
end
puts 'PASS native score-entry columns: both production games, five languages on retained instances, zeros, configured limits, one prompt, quiet inspection, unchanged actions and actual next-column writes'
