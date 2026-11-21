require_relative '../../support/rules_native_navigation'

names = {'pl'=>'Kościany Generał', 'en'=>'Dice General', 'cs'=>'Kostkový generál',
  'es'=>'General de dados', 'ru'=>'Генерал на костях'}
columns = {'pl'=>['1 kolumna punktacji','2 kolumny punktacji','5 kolumn punktacji'],
  'en'=>['1 score column','2 score columns','5 score columns'],
  'cs'=>['1 sloupec bodování','2 sloupce bodování','5 sloupců bodování'],
  'es'=>['1 columna de puntuación','2 columnas de puntuación','5 columnas de puntuación'],
  'ru'=>['1 столбец счёта','2 столбца счёта','5 столбцов счёта']}
page_labels = {'en'=>'Completed categories', 'pl'=>'Wypełnione kategorie', 'cs'=>'Vyplněné kategorie',
  'es'=>'Categorías completas', 'ru'=>'Заполненные категории'}
bonus_labels = {'en'=>'Bonus: 0', 'pl'=>'Premia: 0', 'cs'=>'Prémie: 0', 'es'=>'Bonificación: 0', 'ru'=>'Премия: 0'}
names.each do |language,name|
  GameRoomTestLocalization.use_language(language)
  general = GameRoomGames::Kosciane.new
  balut = GameRoomGames::Balut.new
  assert(general.name == name, "#{language}: Dice General has an untranslated name")
  [1,2,5].zip(columns.fetch(language)).each do |count,expected|
    actual = general.options_summary('columns'=>count)
    assert(actual == expected, "#{language}: untranslated score-column plural: #{actual.inspect}")
  end
  [general,balut].each do |game|
    assert(game.rule_book.sections.any?, "#{language}/#{game.id}: missing rules")
    game.option_definitions.each do |definition|
      assert(!definition.label.empty?, "#{language}/#{game.id}: missing option label")
    end
  end
end
puts 'PASS new games: all five runtime languages and singular/few/many score-column forms'

# Keep the same instances across language changes, as the application does.
# The three games share category names but must not retain their load language.
general = GameRoomGames::Kosciane.new
yahtzee = GameRoomGames::Yahtzee.new
balut = GameRoomGames::Balut.new
[['en', 'Ones'], ['pl', 'Jedynki'], ['cs', 'Jedničky'], ['es', 'Unos'], ['ru', 'Единицы'], ['en', 'Ones']].each do |language, expected|
  GameRoomTestLocalization.use_language(language)
  assert(general.send(:category_label, 1) == expected, "#{language}: General retained a category's load-time language")
  state = yahtzee.send(:initial_state, %w[Alice Bob], yahtzee.default_options)
  first_row = yahtzee.score_sheet_choices(state, 'Alice')[1].label
  assert(first_row.start_with?(expected + ':'), "#{language}: Yahtzee retained a category's load-time language")
  expected_fours = GameRoomLocalization.translate('Fours')
  assert(balut.send(:category_label, :fours) == expected_fours, "#{language}: Balut retained a category's load-time language")
  players = %w[Alice Bob]
  options = general.normalize_options('columns'=>1, 'parity'=>true)
  match = GameRoomGames::FiveDiceMatch.new(players, columns: 1, parity: true)
  state = {players: players, match_model: match, options: options, turn_rolls: 0, dice: match.dice}
  full_sheet = general.score_grid(state, 'Alice', writable: false)
  full_labels = full_sheet.cells.map(&:first)
  assert(full_sheet.cells.first.include?(bonus_labels.fetch(language)), "#{language}: the row bonus uses a different language")
  replay = GameRoomGames::Replay.new(players: players, current_player: 'Alice', state: state)
  key = general.game_shortcuts(replay, 'Alice').find { |shortcut| shortcut.key == 'f' && shortcut.modifiers.empty? }
  assert(key.alternate_page.prompt == page_labels.fetch(language), "#{language}: the completed-categories page uses a different language")
  general_label = GameRoomLocalization.translate('General (five of a kind)')
  assert(full_labels.include?(general_label), "#{language}: the full sheet omitted General")
  %w[Even Odd].each do |label|
    assert(full_labels.include?(GameRoomLocalization.translate(label)), "#{language}: an enabled parity category was hidden")
  end
  match.roll('Alice', (0...5).to_a, [6,6,6,6,6])
  state.update(turn_rolls: 1, dice: match.dice)
  writable = general.score_grid(state, 'Alice', writable: true)
  assert(writable.row_actions.any? { |action| action['category'] == 'poker' }, "#{language}: five equal dice could not be recorded as General")
  assert(writable.cells.any? { |row| row.first.include?(general_label) }, "#{language}: writable General used an obsolete label")
  sheet = GameRoomGames::BalutScoring::CATEGORIES.to_h { |category| [category, []] }
  sheet[:straight] = [0]
  balut_state = {sheets: {'Alice'=>sheet}, dice: [4, 4, 4, 4, 4]}
  grid = balut.send(:score_grid, balut_state, 'Alice', writable: true)
  enter = GameRoomLocalization.translate('%{category}: enter %{points}') % {category: expected_fours, points: 20}
  enter = GameRoomLocalization.translate('%{label}, column %{column} of %{columns}') % {label: enter, column: 1, columns: 4}
  impossible = GameRoomLocalization.translate('No game points can be earned in this category.')
  assert(grid.cells.first.first == enter, "#{language}: Balut entry label changed language or confused game points")
  assert(grid.cells[3].last == impossible, "#{language}: Balut's impossible-row status is untranslated")
  assert(balut.score_sheet_choices(balut_state, 'Alice')[3].label.include?(impossible), "#{language}: Balut V readout disagrees with its grid")
  if language != 'en'
    assert(!enter.include?(': enter ') && !impossible.start_with?('No game'), "#{language}: an English fallback hid missing Balut text")
  end
end
puts 'PASS score-sheet labels follow the current language on the same General, Yahtzee and Balut instances'
