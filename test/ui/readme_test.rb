require_relative "../support/rules_native_navigation"
require_relative "../../tools/support/release_files"

root = File.expand_path("../..", __dir__)
manifest = JSON.parse(File.read(File.join(root, "manifest.json"), encoding: "UTF-8"))
paths = GameRoomReadmeView::FILES
section_titles = {
  'pl' => ['Turnieje', 'Pomoc w rozwoju programu'],
  'en' => ['Tournaments', 'Helping improve the program'],
  'cs' => ['Turnaje', 'Pomoc s vývojem programu'],
  'es' => ['Torneos', 'Colaborar en el programa'],
  'ru' => ['Турниры', 'Помощь в развитии программы']
}.freeze
invitation_filter_exception_text = {
  'pl' => 'Filtry zaproszeń i czarna lista nie blokują zaproszeń do meczów turniejowych.',
  'en' => 'Invitation filters and the blacklist do not block invitations to tournament matches.',
  'cs' => 'Filtry pozvánek ani černá listina neblokují pozvánky k turnajovým zápasům.',
  'es' => 'Los filtros de invitaciones y la lista negra no bloquean las invitaciones a partidas de torneo.',
  'ru' => 'Фильтры приглашений и чёрный список не блокируют приглашения на турнирные матчи.'
}.freeze
permanent_notice_text = {
  'pl' => ['Informacje o rozpoczęciu i zakończeniu turnieju nie wygasają automatycznie.',
    'Podaje Twoje miejsce', 'zwycięzcę lub wspólnych zwycięzców'],
  'en' => ['Start and completion notices do not expire automatically.',
    'It gives your finishing place', 'the winner or joint winners'],
  'cs' => ['Oznámení o zahájení a dokončení turnaje automaticky nevyprší.',
    'Obsahuje vaše umístění', 'vítěze nebo společné vítěze'],
  'es' => ['Los avisos de inicio y fin del torneo no caducan automáticamente.',
    'Indica tu puesto', 'el ganador o los ganadores empatados'],
  'ru' => ['Уведомления о начале и завершении турнира не имеют срока действия.',
    'В нём указаны ваше место', 'победитель или участники, разделившие победу']
}.freeze
tournament_contract_text = {
  'pl' => ['W pojedynku wybierz przegranego', 'Możesz ustawić wspólne miejsce',
    'Przyznaj wszystkim 0 punktów', 'nie można zapisać ani wznowić z pliku'],
  'en' => ['For a duel, choose the losing side', 'Shared places are allowed',
    'Award zero points to everyone', 'No tournament game can be saved or resumed from a file'],
  'cs' => ['V zápase jeden na jednoho vyberte poraženého', 'Místa lze sdílet',
    'Přidělit všem 0 bodů', 'Žádnou turnajovou partii nelze uložit ani obnovit ze souboru'],
  'es' => ['En un duelo, elige quién pierde', 'Se permiten puestos compartidos',
    'Asignar 0 puntos a todos', 'Ninguna partida de torneo se puede guardar ni reanudar desde un archivo'],
  'ru' => ['В матче один на один выберите проигравшего', 'Места можно делить',
    'Назначить всем 0 очков', 'Ни одну турнирную партию нельзя сохранить или возобновить из файла']
}.freeze
assert(paths.keys.sort == manifest.fetch("supported_languages").sort, "Every interface language needs a complete README")
assert(paths.values.sort == (["README.md"] + GameRoomReleaseFiles::README_TRANSLATIONS).sort, "README runtime and installer lists differ")
assert(GameRoomReadmeView.path("future") == paths.fetch("en"), "Future unknown language has no English fallback")
source = File.read(File.join(root, "README.md"), encoding: "UTF-8")
taboo_intro = "W grze taboo potrzebujesz komunikacji z innymi graczami. Możesz użyć do tego konferencji w eltenie, innego komunikatora lub grać na żywo."
assert(source.gsub(/\s+/, " ").include?(taboo_intro), "Polish Taboo introduction differs from the requested text")
levels = source.lines.filter_map { |line| line[/\A(#+) /, 1]&.length }
bullets = source.lines.count { |line| line.start_with?("- ") }
menu = EltenGameRoom::MAIN_OPTIONS
settings_index = menu.index(GameRoomLocalization.translate("Settings"))
assert(settings_index, "Settings is missing from the initial menu language")
readme_index = menu.index('README')
changelog_index = menu.index(GameRoomLocalization.translate("What's new"))
assert(readme_index && changelog_index && settings_index < readme_index && readme_index < changelog_index,
  "README is not between Settings and What's new")

app = EltenGameRoom.allocate
requested = []
app.define_singleton_method(:asset_path) { |path| requested << path; File.join(root, path) }
app.define_singleton_method(:read_text) { |*| raise "README was read from account data" }
app.define_singleton_method(:run_network_task) { |*| raise "README opened a network task" }
app.define_singleton_method(:alert) { |text| (@readme_alerts ||= []) << text }

paths.each do |language, path|
  GameRoomTestLocalization.use_language(language)
  assert(GameRoomReadmeView.path == path, "#{language}: document does not follow interface language")
  bytes = File.binread(File.join(root, path))
  markdown = bytes.dup.force_encoding(Encoding::UTF_8)
  assert(markdown.valid_encoding?, "#{language}: invalid UTF-8")
  assert(markdown.include?(invitation_filter_exception_text.fetch(language)),
    "#{language}: invitation filters omit the tournament exception")
  tournament_title, help_title = section_titles.fetch(language)
  chapters = markdown.scan(/^## (.+)$/).flatten.map(&:strip)
  # Sports results belong to Statistics, not to a competitive leaderboard.
  sports = markdown.index(/^### Axel Pong /)
  statistics_heading = {'pl'=>'Statystyki','en'=>'Statistics','cs'=>'Statistiky','es'=>'Estadísticas','ru'=>'Статистика'}.fetch(language)
  statistics_offset = markdown.index(/^## #{Regexp.escape(statistics_heading)}\r?$/)
  assert(sports && statistics_offset && sports > statistics_offset,
    "#{language}: sports statistics remain in the leaderboard section")
  assert(markdown.include?({'pl'=>'Wybierz gracza','en'=>'Choose player','cs'=>'Vybrat hráče','es'=>'Elegir jugador','ru'=>'Выбрать игрока'}.fetch(language)),
    "#{language}: README does not explain selecting another player's statistics")
  tournament_index = chapters.index(tournament_title)
  assert(tournament_index && chapters[tournament_index + 1] == help_title,
    "#{language}: tournaments must immediately precede the contribution section")
  tournament_section = markdown[/^## #{Regexp.escape(tournament_title)}\r?\n(.*?)(?=^## |\z)/m, 1]
  assert(tournament_section && tournament_section.include?('guliwer'),
    "#{language}: tournament section is missing the contributor credit")
  (tournament_contract_text.fetch(language) + permanent_notice_text.fetch(language)).each do |description|
    assert(tournament_section.include?(description), "#{language}: current tournament help omits #{description}")
  end
  contents_titles = markdown.lines.filter_map { |line| line[/\A- \[([^\]]+)\]\(#/, 1] }
  contents_index = contents_titles.index(tournament_title)
  assert(contents_index && contents_titles[contents_index + 1] == help_title,
    "#{language}: contents order differs from the tournament chapter order")
  assert(!markdown.include?("*"), "#{language}: README contains unwanted asterisks")
  %w[Ctrl+G Ctrl+W Ctrl+F].each do |key|
    assert(markdown.include?(key), "#{language}: missing tournament action shortcut #{key}")
  end
  cancel_forfeit_key=language=='es' ? 'Ctrl+Mayús+F' : 'Ctrl+Shift+F'
  assert(!markdown.include?(cancel_forfeit_key), "#{language}: obsolete separate started-match forfeit shortcut")
  assert(markdown.lines.filter_map { |line| line[/\A(#+) /, 1]&.length } == levels, "#{language}: section structure differs from the user's README")
  assert(markdown.lines.count { |line| line.start_with?("- ") } == bullets, "#{language}: missing list entries")
  %w[Ctrl+R Ctrl+W Ctrl+I Ctrl+Shift+I Ctrl+J Ctrl+Shift+T Ctrl+O Ctrl+M Ctrl+Shift+R Ctrl+Q Ctrl+X Ctrl+F1 Ctrl+F4 Ctrl+P Ctrl+N Ctrl+S Ctrl+Shift+S Ctrl+Home Ctrl+End Shift+C Shift+H Shift+M Ctrl+C Ctrl+Shift+H Ctrl+H].each do |key|
    assert(markdown.include?(key), "#{language}: missing shortcut #{key}")
  end
  visited = false
  Form.driver = lambda do |form|
    visited = true
    field = form.fields.first
    assert(field.is_a?(GameRoomReadmeView), "README menu did not open its native document view")
    assert(field.flags & EditBox::Flags::ReadOnly != 0, "README can be edited")
    assert(form.accept_button.nil?, "Enter closes README instead of following links")
    assert(form.cancel_button == form.fields.last, "Escape does not use the Close action")
    assert(form.game_room_program.equal?(app), "README bypasses the shared program form")
    field.extend(NativeRuleInput)
    headings = elements(field, EditBox::Element::Header)
    expected_titles = markdown.lines.filter_map { |line| line.chomp[/\A#+ (.+)$/, 1] }
    assert(headings.map { |h| field.text_range(h.from, h.to) } == expected_titles, "#{language}: native headings or Unicode offsets changed")
    links = elements(field, EditBox::Element::Link)
    contents = links.select { |link| link.param[1].start_with?("#") }
    assert(contents.length == 20, "#{language}: lost a contents or chapter link, including separate leaderboards and statistics")
    contents.each do |link|
      target = field.instance_variable_get(:@contents_targets)[link]
      assert(target, "#{language}: broken internal link #{link.param[1]}")
      field.index = link.from
      field.press(:key_enter)
      assert(field.index == target.from && field.check == target.from, "#{language}: contents did not move caret and selection")
      assert(field.announcements == [field.text_range(target.from, target.to)], "#{language}: contents did not read just the heading")
      assert(field.opened_urls.to_a.empty?, "Internal README link opened a browser")
    end
    [[72, headings], [75, links]].each do |key, targets|
      field.index = targets[0].from
      field.press(key)
      assert(field.index == targets[1].from, "#{language}: native forward navigation failed")
      field.press(key, reverse: true)
      assert(field.index == targets[0].from, "#{language}: native backward navigation failed")
    end
    external = links.reject { |link| link.param[1].start_with?("#") }
    assert(external.length == 10, "#{language}: missing repository link")
    assert(external.all? { |link| link.param[1].start_with?("https://github.com/papierek1997/elten-game-room/") }, "Repository-only docs became missing local links")
    external.each do |link|
      field.index = link.from
      field.press(:key_enter)
      assert(field.opened_urls.last == link.param[1], "External link bypassed native process_url")
    end
    form.cancel_button.trigger(:press)
  end
  app.send(:open_main_option, readme_index)
  assert(visited && requested.last == path, "#{language}: menu did not read its packaged asset")
end
Form.driver = nil

# Duplicate headings still have distinct GitHub-style anchors.
field = GameRoomReadmeView.new("README".b, text: "[one](#żółw) [two](#żółw-1)\n\n## Żółw\n\n## Żółw\n".b)
targets = field.instance_variable_get(:@contents_targets).values
assert(targets.none?(&:nil?) && targets.uniq.length == 2, "Duplicate Unicode headings share an anchor")

%i[show_settings show_changelog].each { |method| app.define_singleton_method(method) { @selected_action = method } }
app.send(:open_main_option, settings_index)
assert(app.instance_variable_get(:@selected_action) == :show_settings, "Settings menu route changed")
app.send(:open_main_option, menu.length - 1)
assert(app.instance_variable_get(:@selected_action) == :show_changelog, "What's new menu route changed")
[nil, File.join(root, "does-not-exist-readme.md")].each do |missing|
  app.define_singleton_method(:asset_path) { |_| missing }
  app.send(:show_readme)
end
assert(app.instance_variable_get(:@readme_alerts).length == 2, "Missing README did not show a recoverable error")
puts "PASS README: #{$assertions} checks across all interface languages, native Markdown navigation, main menu, missing files and installer coverage"
