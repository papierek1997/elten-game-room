require_relative "../../tools/translations"
require_relative "../../lib/game_rules"
require_relative "../support/mille_bornes"

missing_lookups = []
catalog_probe = Module.new do
  define_method(:translate) do |source, **options|
    result = super(source, **options)
    missing_lookups << source if result.to_s.empty?
    result
  end
end
GameRoomLocalization::Catalog.prepend(catalog_probe)

root = File.expand_path("../..", __dir__)
paths = ["games/mille_bornes.rb", "games/generated/rulebooks/mille_bornes.rb"] +
  Dir.glob("games/mille_bornes/**/*.rb", base: root)
warnings = []
records = {}
paths.each do |path|
  source = File.read(File.join(root, path), encoding: "UTF-8")
  GameRoomTranslationExtractor.extract_source(source, path: path, warnings: warnings).each do |message|
    GameRoomTranslationExtractor.merge_record(records, **message)
  end
end
raise "Unextractable 1000 miles messages: #{warnings.inspect}" unless warnings.empty?
raise "No 1000 miles source messages found" if records.empty?

book = JSON.parse(File.read(File.join(root, "tools/data/rulebooks/mille_bornes.json"), encoding: "UTF-8"))
rule_pairs = book.fetch("sections").flat_map { |section| [section.fetch("title"), *section.fetch("paragraphs")] }
rule_pairs.each do |pair|
  raise "Unextracted rule: #{pair.fetch('en')}" unless records.key?([nil, pair.fetch("en")])
end
controls = book.fetch("sections").find { |section| section.fetch("id") == "controls" }.fetch("paragraphs")
expected_keys = %w[Arrows Enter Escape Space J Delete H I Shift+I S T Z Shift+Z Shift+C Shift+H Shift+M]
raise "Incomplete game shortcut reference" unless controls.map { |pair| pair.fetch("en").split(": ", 2).first } == expected_keys
option_chapters = JSON.parse(File.read(File.join(root, "tools/rulebook_option_chapters.json"), encoding: "UTF-8")).fetch("mille_bornes")
counterflow_labels = {
  "counterflow" => "Add counterflow cards"
}
counterflow_labels.each_key do |key|
  raise "Missing counterflow option chapter: #{key}" unless option_chapters.fetch(key) == "variants"
end
boolean_labels = {
  "accumulate_hazards" => "Accumulate problems",
  "recycle_discard" => "Use discarded cards as a new deck when the current deck runs out",
  "include_safeties" => "Add safety cards",
  "custom_deck" => "Custom deck",
  "include_instant_repairs" => "Add instant repair cards"
}
boolean_labels.each_key do |key|
  chapter = { "custom_deck" => "custom_deck", "include_instant_repairs" => "instant_repair" }.fetch(key, "variants")
  raise "Missing option chapter: #{key}" unless option_chapters.fetch(key) == chapter
end
default_counts = {
  "25" => 10, "50" => 10, "75" => 10, "100" => 12, "200" => 4,
  "stop" => 5, "speed_limit" => 4, "out_of_gas" => 3, "flat_tire" => 3, "accident" => 3,
  "go" => 14, "end_limit" => 6, "fuel" => 6, "spare_tire" => 6, "repairs" => 6,
  "right_of_way" => 1, "extra_tank" => 1, "puncture_proof" => 1, "driving_ace" => 1,
  "counterflow" => 4, "end_counterflow" => 6, "instant_repair" => 2
}
raise "Incomplete custom-deck type coverage" unless default_counts.keys == GameRoomGames::MilleBornes::CARD_ORDER
default_counts.each_key do |type|
  raise "Missing custom-deck option chapter: #{type}" unless option_chapters.fetch("#{type}_cards") == "custom_deck"
end
sidecar_rules = book.fetch("sections").select { |section| %w[instant_repair custom_deck].include?(section.fetch("id")) }
  .flat_map { |section| [section.fetch("title"), *section.fetch("paragraphs")] }
sidecar_rules << book.fetch("sections").find { |section| section.fetch("id") == "variants" }.fetch("paragraphs").fetch(3)
polish_feedback = {
  "Accumulate problems" => "Kumulowanie problemów",
  "Use discarded cards as a new deck when the current deck runs out" => "Użyj odrzuconych kart jako nowej talii, gdy obecna się skończy",
  "Add counterflow cards" => "Dodaj kartę jazdy pod prąd",
  "Add safety cards" => "Dodaj karty uniewrażliwiające",
  "Out of gas" => "Spuszczenie paliwa",
  "Gas" => "Zatankowanie",
  "Flat tire" => "Przedziurawienie opon",
  "Extra tank" => "Dodatkowy zbiornik",
  "Puncture-proof" => "Opony odporne na przebicie",
  "Right of way" => "Pierwszeństwo przejazdu",
  "Driving ace" => "As drogi",
  "Discard %{card}?" => "Czy chcesz odrzucić kartę %{card}?",
  "discard the selected card" => "odrzuć wybraną kartę",
  "Custom deck" => "Tryb dowolny",
  "Add instant repair cards" => "Dodaj karty błyskawicznej naprawy",
  "Instant repair" => "Błyskawiczna naprawa",
  "Choose a problem to remove" => "Wybierz problem do usunięcia",
  "No green light" => "Brak zielonego światła",
  "%{player} used %{card} to remove %{problem}." => "%{player} zagrywa %{card}. Usuwa %{problem}.",
  "%{player} played %{card} against %{target}." => "%{player} zagrywa %{card} na %{target}.",
  "%{player} played %{card}, now at %{miles} miles." => "%{player} zagrywa %{card}. Łącznie %{miles} mil.",
  "%{player} played %{card}: dirty trick! 300 bonus points and an extra turn." => "%{player}: nieczysta zagrywka — %{card}. Premia 300 punktów i dodatkowa tura.",
  "%{player} reached exactly 1000 miles and won the round." => "%{player}: 1000 mil, wygrywa rundę.",
  "%{player}: %{points} points this round; total %{total}." => "%{player}: runda %{points}, łącznie %{total}.",
  "Round %{round}. Six cards dealt to each player." => "Runda %{round}. Rozdano po sześć kart."
}
confirmation_labels = {
  "PL" => ["Potwierdzenie", "Nie", "Tak", "Anuluj"],
  "CS" => ["Potvrzení", "Ne", "Ano", "Zrušit"],
  "ES" => ["Confirmación", "No", "Sí", "Cancelar"],
  "RU" => ["Подтверждение", "Нет", "Да", "Отмена"]
}
polish_dirty_trick_phrases = {
  "%{player} played %{card}: dirty trick!" => ["nieczysta zagrywka — %{card}.", "Premia 300 punktów i dodatkowa tura."],
  "A counterflow attack" => ["jako nieczysta zagrywka."],
  "A dirty trick cancels" => ["Nieczysta zagrywka anuluje atak i zachowuje poprzedni stan jazdy."],
  "Add safety cards is on by default" => ["bez stałej ochrony i nieczystych zagrywek."],
  "Arrow keys move through your hand" => ["Aby wykonać nieczystą zagrywkę, zagraj pasujące zabezpieczenie"],
  "Dirty tricks" => ["Nieczyste zagrywki"],
  "Distance cards score" => ["a nieczysta zagrywka dodatkowe 300."],
  "Shift+Z:" => ["poza czasem na nieczystą zagrywkę."],
  "With the bot move delay set to 0" => ["Aby łatwiej wykonywać nieczyste zagrywki, ustaw niezerowe opóźnienie ruchów botów.",
    "możliwość wykonania nieczystej zagrywki nadal kończy się, gdy następny gracz dobierze lub zagra kartę."],
  "Your current mileage contributes" => ["a nieczysta zagrywka dodatkowe 300."],
  "Z:" => ["poza czasem na nieczystą zagrywkę."]
}
polish_rules = rule_pairs.map { |pair| pair.fetch("pl") }.join(" ")
polish_readme = File.read(File.join(root, "README.md"), encoding: "UTF-8")
[polish_rules, polish_readme].each do |text|
  raise "Outdated Polish driving-ace name in documentation" if text.downcase.include?("as kierownicy")
  raise "Polish driving-ace name missing from documentation" unless text.downcase.include?("as drogi")
  raise "Outdated Polish dirty-trick name in documentation" if text.match?(/kontratak|brudn/i)
  raise "Polish dirty-trick name missing from documentation" unless text.include?("Nieczyst")
end
raise "README does not identify the original dirty-trick term" unless polish_readme.include?("Dirty trick / Coup Fourré")
raise "README confuses a dirty trick with an attack" unless polish_readme.split.join(" ").include?("dozwolona obrona anulująca atak, nie atak zwrotny")
dirty_paragraphs = book.fetch("sections").find { |section| section.fetch("id") == "dirty_tricks" }
  .fetch("paragraphs").map { |pair| pair.fetch("en") }
dirty_rules = dirty_paragraphs.join(" ")
["matching safety", "outside your normal turn", "next player draws or plays", "300", "100", "replacement card", "extra turn with its normal draw"].each do |phrase|
  raise "Incomplete dirty-trick rules: #{phrase}" unless dirty_rules.include?(phrase)
end
timing_paragraphs = dirty_paragraphs.select { |text| text.start_with?("With the bot move delay set to 0") }
raise "Missing or duplicated bot-delay advice" unless timing_paragraphs.length == 1
bot_delay_advice = timing_paragraphs.first
["before you can react", "nonzero bot move delay", "No reaction time is guaranteed", "next player draws or plays"].each do |phrase|
  raise "Incomplete bot-delay advice: #{phrase}" unless bot_delay_advice.include?(phrase)
end

names = { "PL" => "1000 mil", "CS" => "1000 mil", "ES" => "1000 millas", "RU" => "1000 миль" }
names.each do |language, name|
  missing_lookups.clear
  path = File.join(root, "locale", "#{language}.po")
  catalog = GameRoomTranslationCatalog.read_po(path)
  GameRoomTranslationCatalog.validate!(catalog)
  GameRoomTranslationCatalog.compile_file(path, File.join(root, "locale", "#{language}.mo"), check: true)
  GameRoomLocalization.boot(directory: File.join(root, "locale"), host_language: "en",
    settings: { "interface_language" => language.downcase, "known_languages" => [] })
  raise "Wrong interface language: #{language}" unless GameRoomLocalization.primary_language == language.downcase
  %w[Confirm No Yes Cancel].zip(confirmation_labels.fetch(language)).each do |source, expected|
    entry = catalog[nil, source]
    unless entry && !entry.obsolete? && !entry.fuzzy? && entry.msgstr == expected
      raise "#{language}: missing native confirmation label: #{source}"
    end
    actual = GameRoomLocalization.translate(source.b)
    unless actual == expected && actual.encoding == Encoding::UTF_8 && actual.valid_encoding?
      raise "#{language}: native confirmation lookup failed: #{source}"
    end
  end
  if language == "PL"
    polish_feedback.each do |source, expected|
      raise "Polish feedback wording changed: #{source}" unless catalog[nil, source]&.msgstr == expected
    end
    dirty_entries = catalog.select { |entry| entry.msgid.match?(/dirty[ -]trick/i) }
    raise "No Polish dirty-trick messages checked" if dirty_entries.empty?
    dirty_entries.each do |entry|
      prefix = polish_dirty_trick_phrases.keys.find { |candidate| entry.msgid.start_with?(candidate) }
      raise "Missing Polish dirty-trick inflection regression: #{entry.msgid}" unless prefix
      polish_dirty_trick_phrases.fetch(prefix).each do |phrase|
        raise "Incorrect Polish dirty-trick inflection: #{entry.msgid}" unless entry.msgstr.include?(phrase)
      end
      raise "Old dirty-trick terminology retained: #{entry.msgid}" if entry.msgstr.match?(/kontratak|dirty[ -]trick|brudn/i)
      unless GameRoomLocalization.translate(entry.msgid.b) == entry.msgstr
        raise "Stale compiled dirty-trick translation: #{entry.msgid}"
      end
    end
  end

  records.each_value do |message|
    source = message.fetch(:msgid)
    context = message[:msgctxt]
    entry = catalog[context, source]
    unless entry && !entry.obsolete? && !entry.fuzzy? && !entry.msgstr.to_s.empty?
      raise "#{language}: missing 1000 miles translation: #{source}"
    end
    if language == "PL" && entry.msgstr.match?(/brudn/i)
      raise "Old Polish dirty-trick wording in a game message: #{source}"
    end
    variants = entry.msgstr.split("\0", -1)
    raise "#{language}: empty plural form: #{source}" if variants.any?(&:empty?)
    samples = message[:msgid_plural] ? [0, 1, 2, 5, 21, 101] : [nil]
    samples.each do |count|
      text = GameRoomLocalization.translate(source.b, context: context&.b,
        plural: message[:msgid_plural]&.b, count: count)
      raise "#{language}: runtime fallback: #{source}" unless variants.include?(text)
      if text == source && !(language == "ES" && source == "No")
        raise "#{language}: untranslated 1000 miles message: #{source}"
      end
      raise "#{language}: invalid runtime encoding: #{source}" unless text.encoding == Encoding::UTF_8 && text.valid_encoding?
      parameters = source.scan(/%\{([^}]+)\}/).flatten.to_h do |key|
        value = %w[player target].include?(key) ? "Żaneta — Игрок" : 200
        [key.to_sym, value]
      end
      rendered = parameters.empty? ? text : text % parameters
      raise "#{language}: invalid formatted message: #{source}" unless (rendered + " — žółć, проба").valid_encoding?
    end
  end

  rule_pairs.each do |pair|
    source = pair.fetch("en")
    expected = catalog[nil, source].msgstr
    raise "#{language}: binary rule lookup failed: #{source}" unless GameRoomRules.translate(source.b) == expected
    raise "Stale Polish rulebook source: #{source}" if language == "PL" && pair.fetch("pl") != expected
  end
  keys = controls.map do |pair|
    text = GameRoomRules.translate(pair.fetch("en").b)
    key, body = text.split(": ", 2)
    raise "#{language}: malformed shortcut row: #{text}" if key.empty? || body.to_s.empty?
    raise "#{language}: global shortcut in game controls: #{text}" if text.match?(/F[123]|Ctrl\+|chat|czat/i)
    key
  end
  raise "#{language}: duplicate shortcut keys" unless keys == keys.uniq
  raise "#{language}: wrong game name" unless GameRoomRules.translate("1000 miles".b) == name
  readme = File.read(File.join(root, language == "PL" ? "README.md" : "content/readme/#{language}.md"), encoding: "UTF-8")
  overview = readme.split(/\n\s*\n/).find { |paragraph| paragraph.include?(name) && paragraph.include?("QuentinC") }
  raise "#{language}: missing game overview" unless overview
  raise "#{language}: missing game controls" unless %w[Shift+I Shift+Z Delete Ctrl+F1 Escape].all? { |key| readme.include?(key) } && readme.match?(/\bJ\b/)
  raise "#{language}: missing safety deck counts" unless %w[106 102].all? { |count| readme.include?(count) }
  readable = readme.split.join(" ")
  sidecar_rules.each do |pair|
    unless readable.include?(catalog[nil, pair.fetch("en")].msgstr)
      raise "#{language}: README and rules disagree on custom deck or instant repair: #{pair.fetch('en')}"
    end
  end
  unless readable.include?(catalog[nil, bot_delay_advice].msgstr)
    raise "#{language}: README and rules disagree on bot-delay advice"
  end
  [*boolean_labels.values, counterflow_labels.fetch("counterflow")].each do |source|
    raise "#{language}: missing option in README: #{source}" unless readable.include?(catalog[nil, source].msgstr)
  end

  fixture = MilleBornesTest::Fixture.new(players: ["Żaneta", "Игрок"])
  game = fixture.game
  replay = fixture.start
  raise "#{language}: runtime game name" unless game.name == name
  runtime_rules = game.rule_book(options: game.default_options)
  book.fetch("sections").each do |section|
    actual = runtime_rules.sections.find { |candidate| candidate.id.to_s == section.fetch("id") }
    raise "#{language}: missing runtime rule section: #{section.fetch('id')}" unless actual
    expected_title = catalog[nil, section.fetch("title").fetch("en")].msgstr
    expected_paragraphs = section.fetch("paragraphs").map { |pair| catalog[nil, pair.fetch("en")].msgstr }
    unless actual.title == expected_title && actual.paragraphs == expected_paragraphs
      raise "#{language}: untranslated runtime rules or shortcut help: #{actual.id}"
    end
  end
  definitions = game.option_definitions.to_h { |definition| [definition.key, definition] }
  boolean_labels.each do |key, source|
    definition = definitions.fetch(key)
    unless definition.label == catalog[nil, source].msgstr && definition.kind == :boolean
      raise "#{language}: untranslated boolean option: #{key}"
    end
    raise "#{language}: changed default: #{key}" unless definition.default == (key == "include_safeties")
  end
  disabled_summary = game.options_summary("include_safeties" => false)
  expected_disabled = "#{catalog[nil, 'Add safety cards'].msgstr}: #{catalog[nil, 'No'].msgstr}"
  raise "#{language}: untranslated disabled safety option" unless disabled_summary.include?(expected_disabled)
  counterflow_labels.each do |key, source|
    definition = definitions.fetch(key)
    raise "#{language}: untranslated option label: #{key}" unless definition.label == catalog[nil, source].msgstr
    expected_default = false
    raise "#{language}: assumed counterflow deck default: #{key}" unless definition.default == expected_default
  end
  default_counts.each do |type, count|
    definition = definitions.fetch("#{type}_cards")
    expected_label = catalog[nil, "Card count (0 to 100): %{card}"].msgstr % { card: game.send(:card_label, type) }
    unless definition.label == expected_label && definition.kind == :integer && definition.default == count
      raise "#{language}: custom count label/default: #{type}"
    end
    conditions = { "custom_deck" => true }
    conditions["include_safeties"] = [nil, true] if %w[right_of_way extra_tank puncture_proof driving_ace].include?(type)
    conditions["counterflow"] = true if %w[counterflow end_counterflow].include?(type)
    conditions["include_instant_repairs"] = true if type == "instant_repair"
    unless definition.visible_if == conditions
      raise "#{language}: custom count visibility disagrees with rules: #{type}"
    end
  end
  {
    "counterflow" => "Counterflow", "end_counterflow" => "End of counterflow",
    "out_of_gas" => "Out of gas", "fuel" => "Gas", "flat_tire" => "Flat tire",
    "extra_tank" => "Extra tank", "puncture_proof" => "Puncture-proof",
    "right_of_way" => "Right of way", "driving_ace" => "Driving ace", "instant_repair" => "Instant repair"
  }.each do |type, source|
    raise "#{language}: untranslated card: #{type}" unless game.send(:card_label, type) == catalog[nil, source].msgstr
  end
  if language == "PL"
    unless game.send(:card_label, "counterflow") == "Jazda pod prąd" &&
        game.send(:card_label, "end_counterflow") == "Koniec jazdy pod prąd"
      raise "Polish counterflow names changed"
    end
  end
  custom_options = { "counterflow" => true, "counterflow_cards" => 2, "end_counterflow_cards" => 3 }
  raise "#{language}: custom test counts rejected" unless game.options_error(custom_options, player_count: 2).nil?
  summary_source = "Counterflow: %{attacks} attack cards and %{remedies} remedy cards"
  expected_summary = catalog[nil, summary_source].msgstr % { attacks: 2, remedies: 3 }
  raise "#{language}: untranslated counterflow summary" unless game.options_summary(custom_options).include?(expected_summary)
  variant_rules = game.rule_book(options: custom_options).sections.find { |section| section.id == :variants }
  expected_rules = book.fetch("sections").find { |section| section.fetch("id") == "variants" }
    .fetch("paragraphs").map { |pair| catalog[nil, pair.fetch("en")].msgstr }
  raise "#{language}: stale counterflow rules" unless variant_rules.paragraphs == expected_rules
  game.surface_spec(replay, fixture.players.first)
  game.game_shortcuts(replay, fixture.players.first)
  replay = fixture.act(fixture.players.first, { "kind" => "command", "action" => "draw" })
  surface = game.surface_spec(replay, fixture.players.first)
  shortcuts = game.game_shortcuts(replay, fixture.players.first)
  discard_shortcut = shortcuts.find { |shortcut| shortcut.key == "j" && shortcut.modifiers.empty? }
  raise "#{language}: missing selected-card shortcut" unless discard_shortcut
  unless discard_shortcut.label == catalog[nil, "discard the selected card"].msgstr
    raise "#{language}: untranslated selected-card shortcut"
  end
  confirmation = catalog[nil, "Discard %{card}?"].msgstr
  raise "#{language}: J must discard without confirmation" if discard_shortcut.payload.key?("confirmation")
  checked_confirmations = 0
  surface.zones.flat_map(&:cards).each do |surface_card|
    next unless surface_card.confirmation
    expected = confirmation % { card: game.send(:card_label, surface_card.id) }
    raise "#{language}: untranslated card confirmation" unless surface_card.confirmation == expected
    checked_confirmations += 1
  end
  raise "#{language}: no discard confirmation exercised" if checked_confirmations.zero?
  card = replay.state[:hands].fetch(fixture.players.first).first
  replay = fixture.act(fixture.players.first, { "kind" => "card", "action" => "discard", "card" => card })
  replay.history.each do |entry|
    raise "#{language}: invalid history encoding" unless (entry.text + " — žółć, проба").valid_encoding?
  end
  errors = [
    [{ "target_score" => 99 }, 2, "The target score must be between 100 and 100000."],
    [{}, 1, "1000 miles requires between 2 and 8 players."],
    [{ "team_count" => 3 }, 4, "Choose equal teams: 4 players in 2 teams; 6 in 2 or 3; 8 in 2 or 4."],
    [{ "counterflow" => true, "counterflow_cards" => 21, "end_counterflow_cards" => 3 }, 2, "Enter the number of counterflow cards (an integer from 1 to 20) to enable counterflow."],
    [{ "counterflow" => true, "counterflow_cards" => 2, "end_counterflow_cards" => 21 }, 2, "Enter the number of end of counterflow cards (an integer from 1 to 20) to enable counterflow."]
  ]
  errors.each do |options, player_count, source|
    expected = catalog[nil, source].msgstr
    actual = game.options_error(options, player_count: player_count)
    raise "#{language}: untranslated option error: #{source}" unless actual == expected
  end
  count_error = catalog[nil, "The number of %{card} cards must be an integer from 0 to 100."].msgstr
  default_counts.each_key do |type|
    [-1, 101, "1.5", "invalid"].each do |invalid|
      actual = game.options_error({ "custom_deck" => true, "counterflow" => true,
        "include_instant_repairs" => true, "#{type}_cards" => invalid }, player_count: 2)
      expected = count_error % { card: game.send(:card_label, type) }
      raise "#{language}: untranslated count error: #{type}, #{invalid}" unless actual == expected
    end
  end
  empty_deck = default_counts.to_h { |type, _count| ["#{type}_cards", 0] }.merge("custom_deck" => true)
  [2, 6, 8].each do |player_count|
    expected = catalog[nil, "The deck must contain at least %{count} cards to deal six cards to each player."].msgstr % { count: player_count * 6 }
    actual = game.options_error(empty_deck, player_count: player_count)
    raise "#{language}: untranslated deal-size error: #{player_count}" unless actual == expected
  end
  no_points = empty_deck.merge("25_cards" => 12)
  points_error = "The deck must allow players to score points: include a safety card, or mileage cards and a Green light, Right of way or Instant repair card."
  unless game.options_error(no_points, player_count: 2) == catalog[nil, points_error].msgstr
    raise "#{language}: untranslated scoring error"
  end
  enabled_repairs = no_points.merge("include_instant_repairs" => true, "instant_repair_cards" => 2)
  raise "#{language}: documented repair start rejected" unless game.options_error(enabled_repairs, player_count: 2).nil?
  raise "#{language}: documented standard counterflow rejected" unless game.options_error({ "counterflow" => true }, player_count: 2).nil?
  expected_defaults = catalog[nil, summary_source].msgstr % { attacks: 4, remedies: 6 }
  raise "#{language}: wrong default counterflow summary" unless game.options_summary("counterflow" => true).include?(expected_defaults)
  %w[Custom\ deck Add\ instant\ repair\ cards].each do |source|
    unless game.options_summary("custom_deck" => true, "include_instant_repairs" => true).include?(catalog[nil, source].msgstr)
      raise "#{language}: missing custom-deck summary: #{source}"
    end
  end

  repair_fixture = MilleBornesTest::Fixture.new(players: ["Żaneta", "Игрок"],
    options: { "include_instant_repairs" => true, "counterflow" => true, "accumulate_hazards" => true })
  repair_game = repair_fixture.game
  repair_player = repair_fixture.players.first
  %w[go stop out_of_gas flat_tire accident speed_limit counterflow].each do |problem|
    state = repair_fixture.scenario
    state[:hands][repair_player] = %w[instant_repair:1 25:1]
    track = state[:tracks].first
    track[:moving] = false
    track[:hazards] = problem == "go" ? [] : %w[stop out_of_gas flat_tire accident]
    track[:speed_limit] = true
    track[:counterflow] = true
    current = repair_fixture.snapshot(state)
    surface = repair_game.surface_spec(current, repair_player)
    card = surface.zones.flat_map(&:cards).find { |candidate| candidate.id == "instant_repair:1" }
    unless card && card.label == catalog[nil, "Instant repair"].msgstr &&
        card.choice_header == catalog[nil, "Choose a problem to remove"].msgstr
      raise "#{language}: untranslated repair card or choice header"
    end
    expected_problem = problem == "go" ? catalog[nil, "No green light"].msgstr : repair_game.send(:card_label, problem)
    choice = card.choices.find { |candidate| candidate.id == problem }
    raise "#{language}: untranslated repair choice: #{problem}" unless choice && choice.label == expected_problem
    selection = { "kind" => "card", "action" => "play", "card" => card.id, "problem" => problem }
    status, plan = repair_game.action_for(selection, current, repair_player, context: repair_fixture.context)
    raise "#{language}: repair choice rejected: #{problem}" unless status == :ok
    history = []
    plan.events.each_with_index do |command, index|
      event = MilleBornesTest.event(200 + index, repair_player, command.action, command.value)
      unless repair_game.send(:apply_event, state, event, repair_player, event.fetch("id"), history)
        raise "#{language}: repair event rejected: #{problem}"
      end
    end
    expected_history = catalog[nil, "%{player} used %{card} to remove %{problem}."].msgstr % {
      player: repair_player, card: card.label, problem: expected_problem
    }
    unless history.length == 1 && history.first.text == expected_history &&
        (history.first.text + " — žółć, проба").valid_encoding?
      raise "#{language}: untranslated repair history: #{problem}"
    end
  end
  raise "#{language}: English fallback during real game presentation: #{missing_lookups.uniq.inspect}" unless missing_lookups.empty?
end

GameRoomLocalization.boot(directory: File.join(root, "locale"), host_language: "en",
  settings: { "interface_language" => "en", "known_languages" => [] })
rule_pairs.each do |pair|
  raise "English source rules changed" unless GameRoomRules.translate(pair.fetch("en").b) == pair.fetch("en")
end
english_readme = File.read(File.join(root, "content/readme/EN.md"), encoding: "UTF-8")
sidecar_rules.each do |pair|
  raise "English README and rules disagree: #{pair.fetch('en')}" unless english_readme.include?(pair.fetch("en"))
end
raise "English README missing bot-delay advice" unless english_readme.split.join(" ").include?(bot_delay_advice)
[*boolean_labels.values, counterflow_labels.fetch("counterflow"), "106", "102", "replacement card", "No or Escape"].each do |text|
  raise "English README missing feedback: #{text}" unless english_readme.include?(text)
end
puts "PASS 1000 miles: #{records.length} messages and #{rule_pairs.length} rule texts in PL/CS/ES/RU; compiled MO, binary lookup, placeholders, real game presentation/history/errors, all 22 custom card counts and bounds, seven instant-repair choices and history, native confirmations, optional deck switches, dirty-trick rules, English source and all five guides"
