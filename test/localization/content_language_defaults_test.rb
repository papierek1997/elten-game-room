require_relative "../support/game_option_editor_native"

def check(value, message)
  NativeOptionTest.assert(value, message)
end

games = [GameRoomGames::QuizParty.new, GameRoomGames::CashAuction.new, GameRoomGames::Scrabble.new,
  GameRoomGames::Taboo.new, GameRoomGames::Categories.new, GameRoomGames::DuckRacing.new]
general_sets = {"en" => "quiz.general", "pl-PL" => "quiz.wikidata", "ru-RU" => "quiz.general.ru"}
historical_defaults = games.to_h { |game| [game.id, game.default_options] }
created = {}
scenarios = []

%w[en pl cs es ru].each do |ui|
  NativeOptionTest.language = ui
  games.each do |game|
    key = game.content_language_option_key
    expected = if ui == "pl"
      game.id == "categories" ? "pl" : "pl-PL"
    elsif ui == "ru" && %w[quiz cash_auction duck_racing].include?(game.id)
      "ru-RU"
    else
      "en"
    end
    loaded = GameRoomContent.registry.packs.map(&:verified?)
    defaults = game.table_creation_options
    check(GameRoomContent.registry.packs.map(&:verified?) == loaded, "#{game.id}: defaults loaded content data")
    check(defaults[key] == expected, "#{game.id}/#{ui}: expected #{expected}, got #{defaults[key]}")
    check(game.default_options == historical_defaults.fetch(game.id), "#{game.id}: viewer language changed replay defaults")
    definitions = game.effective_option_definitions(defaults)
    if game.id == "quiz"
      check(defaults["content_set_id"] == general_sets.fetch(expected), "Quiz did not select the general set")
    elsif game.id == "cash_auction"
      pack = GameRoomContent.registry.pack_for(game_id: 'quiz', kind: 'quiz', set_id: general_sets.fetch(expected), language_id: expected)
      check(defaults['content_pack_ids'] == [pack.id], 'Cash Auction did not select only the matching general set')
    elsif game.id == "duck_racing"
      check(defaults["question_sets"] == [general_sets.fetch(expected)], "Duck Racing did not select the matching general set")
    end

    # The actual option editor must build dependent choices from the selected
    # language before displaying the form, not fix a mismatched set on Save.
    driver = NativeOptionTest::Driver.new(game, creating_table: true)
    control = driver.control(key)
    choices = definitions.find { |definition| definition.key == key }.choices
    check(choices[control.index].value == expected, "#{game.id}/#{ui}: native language control disagrees")
    if game.id == "quiz"
      set = definitions.find { |definition| definition.key == "content_set_id" }
      check(driver.control(set.key).options == set.choices.map(&:label), "Quiz opened with the wrong set list")
    elsif game.id == "cash_auction"
      set = definitions.find { |definition| definition.key == 'content_pack_ids' }
      checklist = driver.control(set.key)
      check(checklist.options == set.choices.map(&:label), 'Cash Auction opened with the wrong checklist')
      check(checklist.multiselections.map { |index| set.choices[index].value } == defaults['content_pack_ids'], 'Cash Auction checked additional topics by default')
    elsif game.id == "duck_racing"
      set = definitions.find { |definition| definition.key == "question_sets" }
      checklist = driver.control(set.key)
      check(checklist.options == set.choices.map(&:label), "Duck Racing opened with the wrong checklist")
      check(checklist.multiselections.map { |index| set.choices[index].value } == defaults["question_sets"], "Duck checklist lost its language-specific default")
    end
    driver.focus(driver.form.accept_button)
    driver.press([13])
    result = driver.finished
    check(driver.program.alerts.empty?, "#{game.id}/#{ui}: valid defaults were rejected")
    check(result[:game_options] == defaults, "#{game.id}/#{ui}: submitting untouched controls changed defaults")
    created[[game.id, ui]] = result[:game_options]
    scenarios << "#{game.id}/#{ui}"
  end
end

# An interface override wins over the host's language and the optional known
# languages. Unsupported content falls back to English, not a known language.
GameRoomLocalization.boot(host_language: "pl-PL", settings: {"interface_language" => "es", "known_languages" => ["pl", "ru"]})
games.each do |game|
  check(game.table_creation_options[game.content_language_option_key] == "en", "#{game.id}: host/known languages overrode English fallback")
end

# Explicit table/preset choices and serialized options do not acquire the
# receiver's interface language. A changed checksum still fails validation.
NativeOptionTest.language = "en"
games.each do |game|
  initial = created.fetch([game.id, "pl"])
  serialized = JSON.generate(initial)
  check(game.options_from_json(serialized) == initial, "#{game.id}: reading a table changed its language")
  check(game.table_creation_options(initial) == initial, "#{game.id}: explicit creation choices were replaced")
  preset = GameRoomTablePresets.build(game, {game_options: initial, private_table: false})
  check(preset["options"] == initial && GameRoomTablePresets.valid?(preset, game), "#{game.id}: preset changed its content")
  driver = NativeOptionTest::Driver.new(game, initial_options: initial, submit_label: "Save changes")
  driver.focus(driver.form.accept_button)
  driver.press([13])
  check(driver.finished == initial && driver.program.remembers.empty?, "#{game.id}: editing rewrote the explicit language")
  check(JSON.generate(initial) == serialized, "#{game.id}: options were mutated")
end

# Manual changes use the real arrows and refresh only the dependent choices.
quiz = games.first
driver = NativeOptionTest::Driver.new(quiz, creating_table: true)
language = driver.focus("content_language_id")
choices = quiz.effective_option_definitions.find { |definition| definition.key == "content_language_id" }.choices
driver.press([36])
choices.index { |choice| choice.value == "pl-PL" }.times { driver.press([40]) }
check(driver.form.fields[driver.form.index].equal?(language), "Manual language change moved focus")
set = quiz.effective_option_definitions("content_language_id" => "pl-PL").find { |definition| definition.key == "content_set_id" }
driver.focus("content_set_id")
driver.press([36])
set.choices.index { |choice| choice.value == "quiz.witcher.books" }.times { driver.press([40]) }
driver.focus(driver.form.accept_button)
driver.press([13])
check(driver.finished[:game_options]["content_set_id"] == "quiz.witcher.books", "Manual specialist set was replaced")

duck = games.last
program = NativeOptionTest::Program.new
stored = {duck.id => {"question_sets" => ["quiz.witcher.books"]}}
program.define_singleton_method(:read_json) { |_path, default:| stored }
options = program.send(:remembered_game_option_defaults, duck, duck.effective_option_definitions)
check(options["question_language"] == "en" && options["question_sets"] == ["quiz.general"], "Duck Racing restored former sets instead of its interface defaults")
program.send(:remember_multiple_choice_options, duck, duck.effective_option_definitions(options), options)
check(program.writes.last[1][duck.id].keys == ["challenges"], "Duck Racing persisted its question sets or language")
stored[duck.id] = {"question_language" => "en", "question_sets" => []}
options = program.send(:remembered_game_option_defaults, duck, duck.effective_option_definitions)
check(options["question_sets"] == ["quiz.general"], "A former empty preference removed the general default")

# A content registry missing the preferred pack still defaults to English.
# Merely asking for defaults must not load any lazy resource.
registry = GameRoomContent::Registry.new
original = GameRoomContent.registry
original.languages.each { |language| registry.register_language(language) }
original.packs_for(game_id: "quiz", kind: :quiz).select { |pack| pack.language_id == "en" }.each { |pack| registry.register_pack(pack) }
fixture = Class.new(GameRoomGames::Base) do
  def id; "quiz"; end
  def content_pack_kind; :quiz; end
  define_method(:content_registry) { registry }
end.new
NativeOptionTest.language = "pl"
check(fixture.table_creation_options["content_language_id"] == "en", "Missing Polish pack did not fall back to English")
duck_fixture = GameRoomGames::DuckRacing.new
duck_fixture.define_singleton_method(:content_registry) { registry }
check(duck_fixture.table_creation_options["question_language"] == "en", "Duck Racing's missing general set did not fall back to English")
check(duck_fixture.table_creation_options["question_sets"] == ["quiz.general"], "Duck Racing retained sets from the unavailable language")
wrong = created.fetch(["quiz", "en"]).merge("content_pack_checksum" => "0" * 64)
check(quiz.validation_error(quiz.options_from_json(JSON.generate(wrong))) != nil, "Invalid recorded pack was silently repaired")

%w[four_in_a_row uno krowa].each do |id|
  game = GameRoomGames::CATALOG.build(id)
  check(game.table_creation_options == game.default_options, "#{id}: unrelated defaults changed")
end
puts JSON.generate(status: "PASS", checks: NativeOptionTest.checks, scenarios: scenarios,
  scope: "Native option forms, binary sources, interface defaults and fallback, manual choices, presets and option replay; no live clients or server writes")
