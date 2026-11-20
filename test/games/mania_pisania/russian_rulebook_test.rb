require_relative '../../support/game_option_editor_native'

NativeOptionTest.language = 'ru'
game = GameRoomGames::ManiaPisania.new
book = game.rule_book(options: game.table_creation_options)
rules = book.documents.find { |document| document.id == :rules }.text
NativeOptionTest.assert(rules.include?('Можно играть самостоятельно, соревноваться с друзьями'),
  'The supplied Russian rules were added to PO but did not reach the actual rulebook')
NativeOptionTest.assert(rules.include?('Максимальный размер файла или вставленного текста — 1000 КБ'),
  'Russian source-text help still uses the previous document')
scoring_base = 'В сетевой Свободной печати, Случайных словах, Цепочке памяти и Выживании ' \
  'основой служит число правильно набранных слов.'
NativeOptionTest.assert(rules.include?(scoring_base) &&
  rules.include?('Игра дважды умножает исходное число очков на коэффициент точности.'),
  'Russian help must explain the word-count base and squared accuracy factor')
NativeOptionTest.assert(!rules.include?('Итог матча появится, когда все закончат игру.'),
  'The removed match outcome paragraph still appears in Russian help')
source = JSON.parse(File.read(File.join(NativeOptionSource::ROOT, 'tools/data/rulebooks/RU/mania_pisania.json'), encoding: 'UTF-8'))
NativeOptionTest.assert(source.fetch('option_chapters').values_at('text', 'minutes') == %w[main_6 main_6],
  'Source-text settings point to the objective instead of their actual chapter')
puts 'PASS Russian Typoholism: supplied translation reaches the actual native rulebook and option-help chapters'
