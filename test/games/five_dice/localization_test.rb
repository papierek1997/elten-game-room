require_relative '../../support/rules_native_navigation'

names = {'pl'=>'Kościany Generał', 'en'=>'Dice General', 'cs'=>'Kostkový generál',
  'es'=>'General de dados', 'ru'=>'Генерал на костях'}
columns = {'pl'=>['1 kolumna punktacji','2 kolumny punktacji','5 kolumn punktacji'],
  'en'=>['1 score column','2 score columns','5 score columns'],
  'cs'=>['1 sloupec bodování','2 sloupce bodování','5 sloupců bodování'],
  'es'=>['1 columna de puntuación','2 columnas de puntuación','5 columnas de puntuación'],
  'ru'=>['1 столбец счёта','2 столбца счёта','5 столбцов счёта']}
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
