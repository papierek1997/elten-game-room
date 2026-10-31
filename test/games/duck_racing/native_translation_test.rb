# frozen_string_literal: true

require_relative '../../support/host_source'
require_relative '../../support/game_room_language_runtime'
require_relative '../../support/assertions'

include GameRoomTest::Assertions

host_source = EltenTestHost.root
GameRoomLanguageRuntime.load_host(File.expand_path(host_source))
root = GameRoomLanguageRuntime::ROOT
Configuration.language = 'pl-PL'
host = Object.new
host.send(:loadmo, File.binread(File.join(host_source, 'locale/pl-PL/LC_MESSAGES/elten.mo')))
assert_equal('Anuluj', host.send(:_, 'Cancel'), 'The host must use its actual Polish dictionary')

catalogs = %w[pl cs es ru].to_h { |code| [code, File.binread(File.join(root, "locale/#{code.upcase}.mo"))] }
independent = {
  'en' => ['Duck Racing', 'Mine', 'Golden sleep', 'Peaceful Pond', 'Question sets', 'Waiting for others.'],
  'pl' => ['Wyścigi kaczek', 'Mina', 'Złoty sen', 'Spokojny staw', 'Zestawy pytań', 'Oczekiwanie na pozostałych.'],
  'cs' => ['Závody kachen', 'Mina', 'Zlatý spánek', 'Klidný rybník', 'Sady otázek', 'Čekání na ostatní.'],
  'es' => ['Carrera de patos', 'Mina', 'Sueño dorado', 'Estanque tranquilo', 'Conjuntos de preguntas', 'Esperando a los demás.'],
  'ru' => ['Утиные гонки', 'Мина', 'Золотой сон', 'Тихий пруд', 'Наборы вопросов', 'Ожидание остальных.']
}
runtimes = {}
rendered_counts = {}
short_expected = {
  'en' => ['', '', '', 'Alice wins.'],
  'pl' => ['', '', '', 'Wygrywa Alice.'],
  'cs' => ['', '', '', 'Vyhrává Alice.'],
  'es' => ['', '', '', 'Gana Alice.'],
  'ru' => ['', '', '', 'Побеждает Alice.']
}
card_messages = {
  'en' => ['%{player} plays %{card}.', '%{player} plays %{card} on %{target}.'],
  'pl' => ['%{player} zagrywa „%{card}”.', '%{player} zagrywa „%{card}” na %{target}.'],
  'cs' => ['%{player} hraje „%{card}“.', '%{player} hraje „%{card}“ na %{target}.'],
  'es' => ['%{player} juega «%{card}».', '%{player} juega «%{card}» sobre %{target}.'],
  'ru' => ['%{player} разыгрывает «%{card}».', '%{player} применяет «%{card}» к %{target}.']
}
movement_messages = {
  'en' => ['%{player} lands on square %{square}. %{name}.', 'Begins lap %{lap}.', 'Returns to lap %{lap}.', '%{player} reaches the finish.'],
  'pl' => ['%{player} zatrzymuje się na polu %{square}. %{name}.', 'Rozpoczyna okrążenie %{lap}.', 'Wraca na okrążenie %{lap}.', '%{player} dociera do mety.'],
  'cs' => ['%{player} končí na poli %{square}. %{name}.', 'Začíná %{lap}. kolo.', 'Vrací se do %{lap}. kola.', '%{player} dorazí do cíle.'],
  'es' => ['%{player} cae en la casilla %{square}. %{name}.', 'Empieza la vuelta %{lap}.', 'Vuelve a la vuelta %{lap}.', '%{player} llega a la meta.'],
  'ru' => ['%{player} останавливается на клетке %{square}. %{name}.', 'Начинает круг %{lap}.', 'Возвращается на круг %{lap}.', '%{player} достигает финиша.']
}
shared_play_messages = {
  'en' => '%{player} plays %{card}.', 'pl' => '%{player} zagrywa: %{card}.',
  'cs' => nil, 'es' => nil,
  'ru' => '%{player} разыгрывает %{card}.'
}

GameRoomLanguageRuntime.protect_host do
  independent.each_key do |code|
    runtime = GameRoomLanguageRuntime::Runtime.new(settings: {
      'interface_language' => code,
      # Deliberately put another language first: these preferences must not
      # override the interface, even for callbacks outside current_runtime.
      'known_languages' => (%w[ru es cs pl en] - [code]) + [code]
    }, catalogs: catalogs).start
    Programs.with_runtime(runtime) do
      runtime.require_file(File.join(root, 'test/support/duck_challenge_ui.rb'))
      runtime.require_file(File.join(root, 'games/duck_racing_support/challenge_presentation.rb'))
    end
    ns = runtime.namespace
    helper = Object.new.extend(ns::DuckChallengeTest)
    resources = helper.challenge_resources.merge(fingerprint: 'a' * 64).freeze
    game = ns::GameRoomGames::DuckRacing.new(resources: resources)
    runtimes[code] = [runtime, game]
    expected = independent.fetch(code)
    assert_equal(nil, Programs.current_runtime, "#{code}: test callback still has an active runtime")
    assert_equal([Encoding::ASCII_8BIT], runtime.source_encodings.uniq, "#{code}: sources did not cross the binary loading boundary")
    assert_equal(code, ns::GameRoomLocalization.primary_language)
    assert_equal(expected[0], game.name)
    assert_equal(expected[1], game.card_name('mine'))
    assert_equal(expected[2], game.card_name('golden_sleep'))

    logic = ns::GameRoomDuckRacing
    english_game = runtimes.fetch('en').last
    mo = code == 'en' ? nil : ns::GameRoomLocalization::Catalog.new(catalogs.fetch(code))
    translate = ->(source) { code == 'en' ? source : mo.translate(source) }
    texts = [game.name, game.short_description]
    logic::Cards::TYPES.each do |card|
      label = game.card_name(card.id)
      assert_equal(translate.call(english_game.card_name(card.id)), label, "#{code}: card #{card.id} used another locale")
      assert(!label.match?(/[()]/), "#{code}: card name includes a second language")
      description = game.card_description(card.id)
      assert(description.start_with?(label + '. '), "#{code}: card description uses another name")
      source = english_game.card_description(card.id).delete_prefix(english_game.card_name(card.id) + '. ')
        .sub(/ Cost: \d+ feathers?\.\z/, '')
      translated = translate.call(source)
      assert(translated && !translated.empty?, "#{code}: missing complete card description for #{card.id}")
      assert(description.start_with?(label + '. ' + translated), "#{code}: mixed language in #{card.id} description")
      texts.concat([label, description])
    end
    logic::Challenges::TYPES.each do |type|
      assert_equal(translate.call(english_game.challenge_name(type.id)), game.challenge_name(type.id), "#{code}: challenge #{type.id}")
      next if logic::ChallengeEngine::REALTIME.include?(type.id)
      model = helper.challenge_state(type.id)
      [0, 1, nil].each do |viewer|
        view = logic::ChallengeEngine.view(model, seat: viewer)
        projection = logic::ChallengePresentation.project(kind: type.id, view: view, viewer: viewer)
        texts.concat([projection[:name], projection[:instruction], projection[:header], projection[:status], projection[:announcement], *projection[:options]])
      end
    end
    assert_equal(expected[5], logic::ChallengePresentation.status('simon', {}, {}, true, true, nil, 0))

    # Exercise the separate short automatic projection through each actual
    # native Dictionary/RuntimeBackend, including binary-loaded own text.
    samples = [
      ['blackjack', {type: 'blackjack', participants: [0, 1], own: {card_ranks: [2, 4], total: 6}},
        {type: 'blackjack', participants: [0, 1], own: {card_ranks: [2, 4, 12], total: 16}}],
      ['sound_memory', {type: 'sound_memory', seats: [0, 1], public: {removed: [2, 7], turn: 0}},
        {type: 'sound_memory', seats: [0, 1], public: {removed: [2, 7, 3, 8], turn: 1}}],
      ['simon', {type: 'simon', seats: [0, 1], own: {phase: :listening, level: 6}},
        {type: 'simon', seats: [0, 1], own: {phase: :responding, level: 6}}]
    ]
    samples.each_with_index do |(kind, old, current), index|
      projection = logic::ChallengePresentation.project(kind: kind, view: current, viewer: 0, previous_view: old)
      assert_equal(short_expected.fetch(code)[index], projection[:announcement], "#{code}: short #{kind} announcement")
      assert_equal('', logic::ChallengePresentation.project(kind: kind, view: current, viewer: 0, previous_view: current)[:announcement])
      if kind == 'simon'
        assert(projection[:status].start_with?(translate.call('Repeat.')), "#{code}: manual status was removed")
        assert(!projection[:header].include?(translate.call('Repeat.')), "#{code}: native focus would still announce repeat")
        listening = Marshal.load(Marshal.dump(old))
        listening[:own][:level] += 1
        following = logic::ChallengePresentation.project(kind: kind, view: listening, viewer: 0, previous_view: current)
        assert_equal('', following[:announcement], "#{code}: automatic listening/count announcement")
        assert(!following[:header].include?(translate.call('Listen.')), "#{code}: native focus would still announce listening")
        assert(following[:status].start_with?(translate.call('Listen.')), "#{code}: manual listening status was removed")
      end
      texts.concat(projection.values_at(:instruction, :status, :header, :announcement))
    end

    definitions = game.effective_option_definitions('question_language' => 'pl-PL')
    assert_equal(expected[4], definitions.find { |item| item.key == 'question_sets' }.label)
    definitions.each { |item| texts.concat([item.label, *item.choices.to_a.map(&:label)]) }
    # Language/pack labels are created at boot, so check those too.
    languages = definitions.find { |item| item.key == 'question_language' }.choices
    assert_equal(translate.call('Polish'), languages.find { |choice| choice.value == 'pl-PL' }.label)
    sets = definitions.find { |item| item.key == 'question_sets' }
    assert_equal(['quiz.harry_potter.books', 'quiz.wikidata', 'quiz.witcher.books'], sets.choices.map(&:value).sort)
    assert_equal(translate.call('General knowledge'), sets.choices.find { |choice| choice.value == 'quiz.wikidata' }.label)
    assert_equal(translate.call('Witcher — books'), sets.choices.find { |choice| choice.value == 'quiz.witcher.books' }.label)
    quiz = ns::GameRoomGames::QuizParty.new
    %w[pl-PL en ru-RU].each do |language|
      logic::QuestionSets.choices(language: language).each do |choice|
        pack_set = ns::GameRoomContent.registry.pack_set(choice.fetch(:value))
        label = quiz.content_set_choice_label(pack_set, language)
        assert(label.start_with?(choice.fetch(:label) + ', '), "#{code}: Quiz and Duck use different pack labels")
        title = {'quiz.witcher.books'=>'Witcher — books', 'quiz.harry_potter.books'=>'Harry Potter'}.fetch(choice.fetch(:value), 'General knowledge')
        expected_title = title == 'Harry Potter' ? title : translate.call(title)
        assert_equal(expected_title, choice.fetch(:label), "#{code}: #{language} pack title uses its content language")
      end
    end

    state = logic::Session.initial(session_id: 91, player_count: 2, laps: 3,
      enabled_challenges: ['copy_number'], fingerprint: resources[:fingerprint])
    preparing = ns::GameRoomGames::Replay.new(players: %w[Alice Bob], state: state,
      current_player: nil, history: [], accepted_events: [])
    assert_equal('', game.surface_spec(preparing, 'Alice').zones.first.header, "#{code}: preparation field still speaks")
    assert(logic::Session.apply(state, {'action' => 'start', 'seed' => 17, 'revision' => 0},
      seat: 0, moderator: true, now_ms: 0, resources: resources))
    replay = ns::GameRoomGames::Replay.new(players: %w[Alice Bob], state: state,
      current_player: 'Alice', history: [], accepted_events: [])
    texts.concat([game.turn_text(replay), game.standings_text(replay)])
    texts.concat((1..30).map { |square| game.square_text(replay, square) })
    shortcuts = game.custom_game_shortcuts(replay, 'Alice')
    assert_equal(expected[3], shortcuts.find { |shortcut| shortcut.key == 'v' }.prompt)
    texts.concat(shortcuts.flat_map { |shortcut| [shortcut.label, shortcut.message, shortcut.prompt, *shortcut.choices.to_a.map(&:label)] }.compact)
    surface = game.surface_spec(replay, 'Alice')
    labels = surface.parts.find { |part| part.id == 'hand' }.surface.zones.first.cards.map(&:label)
    assert_equal(state[:race][:racers][0][:hand].map { |card| game.card_name(card.type) }, labels)

    # Actual history and result formatting, not a list of isolated msgids.
    notices = [[:started], [:played, 0, 'golden_sleep', 1], [:placed, 0, 'mine', 2],
      [:rolled, 0, 6], [:feathers, 0, 2], [:feathers, 0, -5], [:drew_cards, 0, 3],
      [:stole_feathers, 0, 1, 2], [:stole_card, 0, 1], [:swapped_hands, 0, 1], [:passed_hands],
      [:skip_added, 0, 2], [:skipped, 0], [:thawed, 0, 5], [:frozen, 0, 3],
      [:die_changed, 0, 4, 3], [:trap, 1, 'mine', 0], [:challenge, 'id', 'simon', [0, 1]],
      [:challenge_cancelled]]
    history = []
    game.send(:append_notices, history, notices, 1, replay.players)
    assert_equal(notices.length, history.length)
    replay.history = history
    repository = Object.new
    def repository.event_id(event); event.fetch('id'); end
    assert_equal(history.reject { |entry| entry.kind == :started }.map(&:text),
      game.describe_event_for_display({'id' => 1}, repository, replay, 'Alice'), "#{code}: startup speech filter lost a consequence")
    assert(history.find { |entry| entry.kind == :played }.text.include?(expected[2]))
    assert(history.find { |entry| entry.kind == :trap }.text.include?(expected[1]))
    texts.concat(history.map(&:text))

    concise = []
    game.send(:append_notices, concise, [[:played, 0, 'super_challenge', 0],
      [:played, 0, 'helix', 0], [:played, 0, 'golden_sleep', 1],
      [:played, 0, 'mine', 0], [:placed, 0, 'mine', 2], [:feathers, 1, 6]], 2, replay.players)
    assert_equal([:played, :played, :played, :placed, :feathers], concise.map(&:kind), "#{code}: duplicated placement or lost effect")
    assert_equal(card_messages.fetch(code)[0] % {player: 'Alice', card: game.card_name('super_challenge')}, concise[0].text)
    assert_equal(card_messages.fetch(code)[0] % {player: 'Alice', card: game.card_name('helix')}, concise[1].text)
    assert_equal(card_messages.fetch(code)[1] % {player: 'Alice', card: expected[2], target: 'Bob'}, concise[2].text)
    assert_equal(1, concise[0].text.scan('Alice').length, "#{code}: global card still names its actor as target")
    assert(concise[3].text.include?(expected[1]) && concise[3].text.include?('2'))
    assert_equal(shared_play_messages.fetch(code), code == 'en' ? '%{player} plays %{card}.' : mo.translate('%{player} plays %{card}.'), "#{code}: Duck changed the shared War catalog entry")
    texts.concat(concise.map(&:text))
    if code == 'pl'
      # One sentence identifies the placed card and its owner; its effect
      # follows on a separate history line and names the affected player.
      [0, 1].each do |owner|
        trap = []
        game.send(:append_notices, trap, [[:trap, 0, 'thick_die', owner],
          [:die_changed, 0, 3, 2]], 3, %w[papierek peterman])
        assert_equal([
          "papierek trafia na kartę „Ociężała kość” położoną przez #{%w[papierek peterman].fetch(owner)}.",
          'papierek przez 2 rzuty używa kości o 3 oczkach.'
        ], trap.map(&:text))
        texts.concat(trap.map(&:text))
      end
      [1, 2, 3, 5].zip(%w[rzut rzuty rzuty rzutów]).each do |count, word|
        history = []
        game.send(:append_notices, history, [[:die_changed, 0, 12, count]], 4, ['papierek'])
        assert_equal("papierek przez #{count} #{word} używa kości o 12 oczkach.", history.first.text)
        texts << history.first.text
      end
    end
    moves = []
    [[0, 4], [4, 32], [32, 35], [35, 29], [29, 93]].each_with_index do |(from, to), index|
      movement = logic::Board.advance(from, by: to - from, laps: 3)
      game.send(:append_notices, moves, [[:moved, 0, movement]], 30 + index, replay.players)
      messages = movement_messages.fetch(code)
      expected_move = if movement.finished
        messages[3] % {player: 'Alice'}
      else
        base = messages[0] % {player: 'Alice', square: movement.square, name: game.square_name(movement.square)}
        suffix = index == 1 ? messages[1] % {lap: 2} : (index == 3 ? messages[2] % {lap: 1} : nil)
        [base, suffix].compact.join(' ')
      end
      assert_equal(expected_move, moves.reverse.find { |entry| entry.kind == :moved }.text, "#{code}: lap transition #{index}")
    end
    texts.concat(moves.map(&:text))
    (1..30).each do |square|
      source = english_game.send(:square_scenery, square)
      scenery = game.send(:square_scenery, square)
      assert_equal(translate.call(source), scenery, "#{code}: square #{square} scenery")
      assert(!scenery.to_s.empty?)
      texts << scenery
    end
    extra = []
    game.send(:append_notices, extra, [[:challenge_draw, 0, 13, 24], [:skipped, 0, true],
      [:die_changed, 0, 6, 0], [:die_changed, 0, 10, 2]], 88, replay.players)
    english_extra = []
    english_game.send(:append_notices, english_extra, [[:challenge_draw, 0, 13, 24],
      [:skipped, 0, true], [:die_changed, 0, 6, 0], [:die_changed, 0, 10, 2]], 88, replay.players)
    if code != 'en'
      extra.zip(english_extra).each { |local, english| assert(local.text != english.text, "#{code}: untranslated #{local.kind}") }
    end
    texts.concat(extra.map(&:text))
    settlement = logic::Settlement.difference(balances: {0 => 18, 1 => 18}, scores: {0 => 21, 1 => 25}, ceiling: 21)
    settlement_message = game.send(:settlement_text, settlement, replay.players)
    assert(settlement_message.start_with?(short_expected.fetch(code).last), "#{code}: shortened winner announcement")
    texts << settlement_message
    texts << game.send(:challenge_details_text, 'rock_paper_scissors', {0 => {choice: 'rock'}, 1 => {choice: nil}}, nil, replay.players)
    texts << game.send(:challenge_details_text, 'quiz', {0 => {correct: true}, 1 => {answer: 1, correct: false}}, 'A', replay.players)
    replay.winner = 'Alice'
    texts << game.result_text(replay)
    assert_equal(translate.call('%{player} won the game.') % {player: 'Alice'}, texts.last)

    # The independent complete rulebook is selected by the same UI language.
    book = JSON.parse(File.read(File.join(root, "tools/data/rulebooks/#{code.upcase}/duck_racing.json"), encoding: 'UTF-8'))
    sections = game.send(:localized_rule_sections)
    assert_equal(book['sections'].map { |section| section['title'][code] }, sections.map(&:title))
    texts.concat(sections.flat_map { |section| [section.title, *section.paragraphs] })
    texts.each do |text|
      assert(text.encoding == Encoding::UTF_8 && text.valid_encoding?, "#{code}: non-UTF-8 UI text #{text.inspect}")
      assert(!text.include?('%{'), "#{code}: unexpanded placeholder #{text.inspect}")
      next if code == 'en'
      english_names = logic::Cards::TYPES.map { |card| english_game.card_name(card.id) } + ['Peaceful Pond']
      assert(english_names.none? { |name| text.include?(" (#{name})") }, "#{code}: English parenthetical in #{text.inspect}")
    end
    rendered_counts[code] = texts.length
  end

  # Delayed callbacks from an old app namespace must not borrow the current
  # native application's language; this is where a plain require misses bugs.
  runtimes.each do |code, (runtime, game)|
    other = runtimes.fetch(code == 'en' ? 'pl' : 'en').first
    Programs.with_runtime(other) do
      assert_equal(independent.fetch(code)[0], game.name)
      assert_equal(independent.fetch(code)[2], game.card_name('golden_sleep'))
    end
    assert_equal(['settings.json'], runtime.settings_reads, "#{code}: presentation reread language settings")
  end
end

assert_equal('Anuluj', host.send(:_, 'Cancel'), 'Duck changed the host language')
puts "PASS native Duck localization: five binary-loaded runtimes, actual host Dictionary/RuntimeBackend, cards, options, histories, results, views and rules (#{rendered_counts.inspect})"
