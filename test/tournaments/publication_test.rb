# encoding: UTF-8
require 'json'
require_relative '../support/assertions'
require_relative '../../games/catalog'
require_relative '../support/model_contract'
source = File.expand_path('../../lib/tournaments/publication.rb', __dir__)
require source if File.file?(source)

module PublicationTest
  extend GameRoomTest::Assertions
  module_function

  def test(name)
    yield
    puts JSON.generate({ 'pass' => name }, ascii_only: true)
  end

  def draft(game_id = 'chess')
    game = GameRoomGames::CATALOG.build(game_id)
    options = game.default_options
    { 'name' => 'Żółty turniej', 'game_id' => game_id, 'game_options' => options,
      'format' => 'round_robin', 'rematch' => false,
      'players_per_match' => GameRoomTest::ModelContract.players_for(game, options).length,
      'pairing' => 'all_combinations', 'participants' => [],
      'windows' => [{ 'date' => '2026-10-15', 'start' => '12:00', 'end_date' => '2026-10-16', 'end' => '21:00' }] }
  end

  def build(value = draft, **changes)
    GameRoomTournaments::Publication.from_draft(draft: value, registry: GameRoomGames::CATALOG,
      publication_key: 'publication-1', rules: "Uzgodniony regulamin.\nDrugi akapit.",
      registration_opens_at: 100, registration_closes_at: 200, timezone: 'Europe/Warsaw', **changes)
  end

  def row(id = 10, author = 'Żaneta', **changes)
    build(**changes).to_row.merge('__id' => id, '__insertion_user' => author, '__insertion_time' => 90)
  end

  def project(rows, complete: true)
    GameRoomTournaments::Publication.project(rows: rows, registry: GameRoomGames::CATALOG, complete: complete)
  end

  def invalid(value = draft, **changes)
    assert_raises(GameRoomTournaments::Publication::Invalid) { build(value, **changes) }
  end

  def roundtrip(value, expected_options: value.fetch('game_options'))
    before = Marshal.dump(value)
    snapshot = build(value).to_row
    assert(expected_options.eql?(JSON.parse(snapshot.fetch('settings_json')).fetch('game_options')))
    metadata = { '__id' => 37, '__insertion_user' => 'Testowa Żaneta', '__insertion_time' => 90 }
    row = snapshot.merge(metadata)
    row_before = Marshal.dump(row)
    result = project([row])
    assert_equal([], result.fetch('diagnostics'))
    assert_equal([row.merge('alias_ids' => [37])], result.fetch('announcements'))
    assert_equal(before, Marshal.dump(value))
    assert_equal(row_before, Marshal.dump(row))
    assert_raises(FrozenError) { snapshot.fetch('settings_json').clear }
    assert_raises(FrozenError) { result.fetch('announcements').first.fetch('settings_json').clear }
    snapshot
  end

  def reject_options(value, options, code: :invalid_options)
    before = Marshal.dump(options)
    error = invalid(value.merge('game_options' => options))
    assert_equal(code, error.code)
    row = build(value).to_row.merge('__id' => 38, '__insertion_user' => 'Testowy autor', '__insertion_time' => 90)
    settings = JSON.parse(row.fetch('settings_json')).merge('game_options' => options)
    # Wstrzyknięte opcje trafiają surowe do obu granic; bez normalizacji fixture.
    row['settings_json'] = JSON.generate(settings)
    result = project([row])
    assert_equal([], result.fetch('announcements'))
    assert(result.fetch('diagnostics').any? { |item| item['code'] == code.to_s })
    assert_equal(before, Marshal.dump(options))
  end

  def choice_variants(game)
    definitions = game.effective_option_definitions
    choices = definitions.select { |definition| definition.kind.to_s == 'choice' && !definition.visible_if }
    variants = choices.flat_map do |definition|
      definition.choices.map { |choice| { definition.key.to_s => choice.value } }
    end
    # Jeden dodatkowy poziom zależności zamiast iloczynu wszystkich opcji.
    variants.dup.each do |selected|
      game.effective_option_definitions(selected).each do |definition|
        next unless definition.kind.to_s == 'choice'
        next unless game.option_visible?(definition, selected)
        base = choices.find { |item| item.key == definition.key }
        next if base && !definition.visible_if && base.choices.map(&:value).eql?(definition.choices.map(&:value))
        definition.choices.each { |choice| variants << selected.merge(definition.key.to_s => choice.value) }
      end
    end
    assert(variants.length <= 1024, 'Przekroczono ograniczenie wariantów jednego modelu')
    variants.each do |selected|
      # Zależna pula własna wymaga jawnego, niepustego wyboru (Państwa-miasta).
      game.effective_option_definitions(selected).each do |definition|
        next unless definition.kind.to_s == 'multiple_choice' && definition.visible_if
        next unless game.option_visible?(definition, selected)
        width = definition.choices.length
        mask = (1 << width) - 1
        selected[definition.key.to_s] = width > 63 ? mask.to_s : mask
      end
    end
    variants.uniq
  end
end

PublicationTest.test('snapshot treści nie publikuje ręcznego rosteru ani lokalnej tożsamości') do
  include GameRoomTest::Assertions
  assert(defined?(GameRoomTournaments::Publication), 'Brak modelu Publication')
  draft = PublicationTest.draft.merge('participants' => ['Lokalny nick'], 'owner' => 'Nie autor', 'id' => 'szkic')
  before = Marshal.dump(draft)
  publication = PublicationTest.build(draft)
  row = publication.to_row
  assert_equal(%w[publication_key schema_version title game rules settings_json schedule_json registration_opens_at registration_closes_at timezone].sort, row.keys.sort)
  assert_equal(1, row['schema_version'])
  assert_equal('chess', row['game'])
  settings = JSON.parse(row['settings_json'])
  assert_equal(draft['game_options'], settings['game_options'])
  assert_equal(draft['format'], settings['format'])
  assert_equal(false, settings['rematch'])
  assert_equal(2, settings['players_per_match'])
  assert_equal('all_combinations', settings['pairing'])
  assert_equal({ 'windows' => draft['windows'] }, JSON.parse(row['schedule_json']))
  assert_equal('Europe/Warsaw', row['timezone'])
  assert_equal(before, Marshal.dump(draft))
  draft['windows'].first['start'].replace('15:00')
  draft['name'].clear
  assert_equal('12:00', JSON.parse(publication.to_row['schedule_json'])['windows'].first['start'])
  assert_equal('Żółty turniej', publication.to_row['title'])
  assert_raises(FrozenError) { row['title'].clear }
  assert_raises(FrozenError) { row['schema_version'] = 8 }
  assert(publication.frozen?)
end

PublicationTest.test('publikacja wymaga kompletnych ustawień i pełnych okien') do
  %w[name game_id game_options format rematch players_per_match pairing windows].each do |field|
    value = PublicationTest.draft
    value.delete(field)
    assert_raises(ArgumentError) { PublicationTest.build(value) }
  end
  { 'format' => 'liga', 'rematch' => 'false', 'players_per_match' => 3,
    'pairing' => nil, 'windows' => [], 'game_id' => 'nieznana' }.each do |key, value|
    PublicationTest.invalid(PublicationTest.draft.merge(key => value))
  end
  window = PublicationTest.draft['windows'].first
  [{ 'end' => '11:00', 'end_date' => window['date'] }, { 'date' => '2026-02-30' },
    { 'end_date' => nil }].each do |change|
    PublicationTest.invalid(PublicationTest.draft.merge('windows' => [window.merge(change)]))
  end
  PublicationTest.invalid(PublicationTest.draft.merge('windows' => [window, window]))
end

PublicationTest.test('UTC jest jawnym integerem, strefa tylko metadaną, teksty są ograniczone') do
  [nil, 100.0, '100', true, -1, 2**63].each do |value|
    PublicationTest.invalid(registration_opens_at: value)
    PublicationTest.invalid(registration_closes_at: value)
  end
  PublicationTest.invalid(registration_closes_at: 100)
  PublicationTest.invalid(registration_closes_at: 99)
  ['', ' ', "A\0B", 'Ż' * 257, "\xFF".b, 'abc'.encode('UTF-16LE')].each do |value|
    PublicationTest.invalid(PublicationTest.draft.merge('name' => value))
  end
  ['', ' ', "a\0b", 'a' * 16_385].each { |value| PublicationTest.invalid(rules: value) }
  ['', ' ', 'a' * 65, "A\nB"].each { |value| PublicationTest.invalid(timezone: value) }
  ['', 'a' * 65, 'has spaces', 'Ż'].each { |value| PublicationTest.invalid(publication_key: value) }
  # Granice tekstów nie pochodzą z wdrożonego schematu.
  assert_equal(16_384, PublicationTest.build(rules: 'x' * 16_384).to_row['rules'].bytesize)
end

PublicationTest.test('JSON nie przyjmuje obcych typów, NaN, złego UTF8 ani przekroczenia budżetu') do
  cycle = {}; cycle['self'] = cycle
  nested = {}; cursor = nested
  12.times { cursor['child'] = {}; cursor = cursor['child'] }
  invalid = [[], nil, { a: 1 }, { 'a' => Object.new }, { 'a' => Float::NAN },
    { 'a' => Float::INFINITY }, { 'a' => "\xFF".b }, { 'a' => 2**100_000 },
    { 'a' => 'x' * 65_537 }, { 'a' => Array.new(4097, 0) }, cycle, nested,
    { 'thinking_time' => [] }, { 'thinking_time' => {} }, { 'thinking_time' => '1' }]
  invalid.each { |options| PublicationTest.invalid(PublicationTest.draft.merge('game_options' => options)) }
  PublicationTest.invalid(PublicationTest.draft.merge('game_options' => { 'thinking_time' => 1 }))
end

PublicationTest.test('legalne choice Axel Ponga custom i unlimited przechodzą pełny roundtrip bez mutacji') do
  failures = []
  %w[custom unlimited].each do |target|
    value = PublicationTest.draft('axel_pong')
    value['game_options'].merge!('target' => target.dup, 'custom_target' => 37)
    game = GameRoomGames::CATALOG.build('axel_pong')
    assert_equal(2, value.fetch('players_per_match'))
    assert_equal(nil, game.validation_error(value.fetch('game_options'), player_count: 2))
    assert(value.fetch('game_options').eql?(game.normalize_options(value.fetch('game_options'))))
    begin
      snapshot = PublicationTest.roundtrip(value)
      value.fetch('game_options').fetch('target').replace('zmieniono szkic')
      value.fetch('game_options').clear
      saved = JSON.parse(snapshot.fetch('settings_json')).fetch('game_options')
      assert_equal(37, saved.fetch('custom_target'))
      assert_equal(target, saved.fetch('target'))
    rescue GameRoomTournaments::Publication::Invalid => error
      failures << "#{target}: #{error.code}"
    end
  end
  assert_equal([], failures, 'Legalne choice odrzucone przed normalizacją')
end

PublicationTest.test('wszystkie gry zachowują rzeczywiste opcje i legalną liczebność') do
  assert(GameRoomGames::CATALOG.ids.include?('mille_bornes'), 'Missing Power Games model')
  GameRoomGames::CATALOG.ids.each do |id|
    value = PublicationTest.draft(id)
    snapshot = PublicationTest.build(value).to_row
    assert_equal(value['game_options'], JSON.parse(snapshot['settings_json'])['game_options'], id)
    game = GameRoomGames::CATALOG.build(id)
    [game.minimum_players - 1, game.maximum_players + 1].each do |count|
      PublicationTest.invalid(value.merge('players_per_match' => count))
    end
  end
end

PublicationTest.test('choice odrzuca obce wartości i coercion przed normalizacją szkicu oraz wiersza') do
  value = PublicationTest.draft('axel_pong')
  value['game_options'].merge!('target' => 'custom', 'custom_target' => 37)
  {
    'target' => ['11', 11.0, 'nieznane', nil, true, 12],
    'custom_target' => ['37', 37.0, nil, true, '', 'abc'],
    'arcade' => ['false', 'true', '1', 0, 1, nil],
    'p2p_enabled' => ['false', 'true', '1', 0, 1, nil],
    'nieznany_choice' => ['custom', 'unlimited', 11, nil]
  }.each do |key, invalids|
    invalids.each { |invalid| PublicationTest.reject_options(value, value['game_options'].merge(key => invalid)) }
  end
  [0, 1, 1000, -1].each do |invalid|
    PublicationTest.reject_options(value, value['game_options'].merge('custom_target' => invalid), code: :game_validation)
  end
  [2, 999].each do |limit|
    PublicationTest.roundtrip(value.merge('game_options' => value['game_options'].merge('custom_target' => limit)))
  end
end

PublicationTest.test('bool i team_seats zachowują ścisłe typy oraz walidację liczebności gry') do
  value = PublicationTest.draft('axel_pong')
  value['players_per_match'] = 4
  value['game_options'].merge!('target' => 'unlimited', 'team_size' => 2, 'team_seats' => [0, 1, 0, 1])
  [true, false].product([true, false]).each do |arcade, p2p|
    PublicationTest.roundtrip(value.merge('game_options' => value['game_options'].merge('arcade' => arcade, 'p2p_enabled' => p2p)))
  end
  [[0, 1, 0, '1'], [0, 1, 0, 1.0], [0, false, 0, 1], nil, '0,1,0,1'].each do |seats|
    PublicationTest.reject_options(value, value['game_options'].merge('team_seats' => seats))
  end
  [[0, 0, 0, 1], [0, 1]].each do |seats|
    PublicationTest.reject_options(value, value['game_options'].merge('team_seats' => seats), code: :game_validation)
  end
  [2, 3].each do |count|
    assert_equal(:game_validation, PublicationTest.invalid(value.merge('players_per_match' => count)).code)
  end
  ludo = PublicationTest.draft('ludo')
  [true, false].each { |flag| PublicationTest.roundtrip(ludo.merge('game_options' => ludo['game_options'].merge('enter_on_one' => flag))) }
end

PublicationTest.test('bounded choice wszystkich modeli zachowują dokładne wartości i zależne definicje') do
  counts = {}
  GameRoomGames::CATALOG.ids.each do |id|
    game = GameRoomGames::CATALOG.build(id)
    variants = PublicationTest.choice_variants(game)
    variants.each do |options|
      # Normalizacja służy jedynie wyznaczeniu oczekiwanych brakujących domyślnych;
      # Publication otrzymuje pierwotne jawne choice, nigdy poprawiony wariant.
      expected = game.normalize_options(options)
      definitions = game.effective_option_definitions(options).to_h { |definition| [definition.key.to_s, definition] }
      assert(options.all? { |key, value| expected.fetch(key) { definitions.fetch(key).default }.eql?(value) },
        "Normalizator zmienił choice: #{id} #{options.inspect}")
      count = (game.minimum_players..game.maximum_players).find { |size| game.validation_error(expected, player_count: size).nil? }
      assert(count, "Brak legalnej liczebności: #{id} #{options.inspect}")
      value = PublicationTest.draft(id).merge('game_options' => options, 'players_per_match' => count)
      PublicationTest.roundtrip(value, expected_options: expected)
    end
    game.effective_option_definitions.each do |definition|
      next unless definition.kind.to_s == 'choice'
      ['__nieznany_choice__', nil].each do |invalid|
        assert(!definition.choices.any? { |choice| choice.value.eql?(invalid) })
        PublicationTest.reject_options(PublicationTest.draft(id), { definition.key.to_s => invalid })
      end
    end
    counts[id] = variants.length
  end
  assert_equal(GameRoomGames::CATALOG.ids.length, counts.length)
  assert(counts.values.sum.between?(1, 1024), 'Niepełny albo nieograniczony przegląd choice')
  puts JSON.generate({ 'choice_variants_by_game' => counts, 'total' => counts.values.sum }, ascii_only: true)
end

PublicationTest.test('zależne domyślne nie nadpisują jawnego wyboru ani nie naprawiają wstrzyknięcia') do
  rummy = GameRoomGames::CATALOG.build('rummy')
  [{ 'elimination' => true }, { 'elimination' => true, 'score_limit' => 1700 }].each do |options|
    PublicationTest.roundtrip(PublicationTest.draft('rummy').merge('game_options' => options),
      expected_options: rummy.normalize_options(options))
  end
  quiz = GameRoomGames::CATALOG.build('quiz')
  selected = { 'content_language_id' => 'pl-PL' }
  definition = quiz.effective_option_definitions(selected).find { |item| item.key == 'content_set_id' }
  base = quiz.effective_option_definitions.find { |item| item.key == definition.key }
  dependent = definition.choices.find { |choice| !base.choices.any? { |item| item.value.eql?(choice.value) } }
  assert(dependent, 'Fixture musi mieć choice niedostępny w języku domyślnym')
  options = selected.merge(definition.key => dependent.value)
  PublicationTest.roundtrip(PublicationTest.draft('quiz').merge('game_options' => options),
    expected_options: quiz.normalize_options(options))
  PublicationTest.reject_options(PublicationTest.draft('quiz'), { definition.key => dependent.value })
end

PublicationTest.test('własna pula kategorii zachowuje format zapisu i odrzuca nieznane bity') do
  game = GameRoomGames::CATALOG.build('categories')
  draft = PublicationTest.draft('categories')
  key = 'custom_categories'
  width = game.effective_option_definitions(draft.fetch('game_options')).find { |item| item.key == key }.choices.length
  assert_equal(86, width)

  first_undefined = 1 << width
  wide = draft.fetch('game_options').merge('category_set' => 'custom', key => (first_undefined - 1).to_s)
  wide_draft = draft.merge('game_options' => wide)
  PublicationTest.roundtrip(wide_draft)
  # Tekst z nieznanym bitem mieści się w JSON-ie, ale nie jest poprawną opcją.
  [first_undefined.to_s, '01', 1].each do |invalid|
    PublicationTest.reject_options(wide_draft, wide.merge(key => invalid))
  end
  # Taka liczba jest odrzucana już na granicy dokumentu, przed walidacją opcji.
  PublicationTest.reject_options(wide_draft, wide.merge(key => first_undefined), code: :invalid_json)

  legacy = game.normalize_options('category_set' => 'custom', 'round_category_count' => 1, key => 1)
  legacy_width = game.effective_option_definitions(legacy).find { |item| item.key == key }.choices.length
  assert(legacy_width.between?(1, 62), 'Historyczny wybór powinien zmieścić się w liczbie całkowitej')
  legacy_draft = draft.merge('game_options' => legacy)
  PublicationTest.roundtrip(legacy_draft)
  PublicationTest.reject_options(legacy_draft, legacy.merge(key => 1 << legacy_width))
end

PublicationTest.test('retry ogłoszenia zachowuje aliasy, minimum ID i różnych autorów') do
  assert(GameRoomTournaments::Publication.respond_to?(:project), 'Brak projekcji publicznych wierszy')
  rows = [PublicationTest.row(14), PublicationTest.row(3, 'ŻANETA'), PublicationTest.row(9, 'Bartek')]
  before = Marshal.dump(rows)
  result = PublicationTest.project(rows)
  assert_equal([3, 9], result['announcements'].map { |row| row['__id'] })
  assert_equal([3, 14], result['announcements'].first['alias_ids'])
  rows.permutation.each { |order| assert_equal(result, PublicationTest.project(order)) }
  assert_equal(before, Marshal.dump(rows))
  assert_raises(FrozenError) { result['announcements'].first['alias_ids'].clear }
  rows.first['__insertion_user'].clear
  assert_equal('ŻANETA', result['announcements'].first['__insertion_user'])
end

PublicationTest.test('metadane są ścisłe i żadna deklarowana tożsamość ich nie zastępuje') do
  invalids = { '__id' => [nil, '10', 10.0, false, -1, 0],
    '__insertion_time' => [nil, '90', 90.0, false, -1],
    '__insertion_user' => [nil, '', ' Ala', "A\nB", 4, "\xFF".b] }
  invalids.each do |field, values|
    values.each do |value|
      row = PublicationTest.row.merge(field => value, 'owner' => 'Ala', 'created_at' => 90, 'id' => 10)
      result = PublicationTest.project([row])
      assert_equal([], result['announcements'])
      assert(!result['diagnostics'].empty?)
    end
  end
  row = PublicationTest.row.merge('owner' => 'Fałszywy', 'username' => 'Fałszywy')
  assert_equal('Żaneta', PublicationTest.project([row])['announcements'].first['__insertion_user'])
end

PublicationTest.test('konflikt treści, ID lub uszkodzony alias kwarantannuje całą publikację') do
  good = PublicationTest.row
  unrelated = PublicationTest.row(50, 'Inna')
  conflicts = [PublicationTest.row(11).merge('title' => 'Zmieniony tytuł'),
    PublicationTest.row(11).merge('settings_json' => '{'),
    PublicationTest.row(11).merge('__insertion_time' => nil),
    PublicationTest.row(10, 'Inna'), good.merge('__insertion_user' => nil),
    good.merge('publication_key' => 'inny'), good.merge('__insertion_time' => 91)]
  conflicts.each do |bad|
    result = PublicationTest.project([good, bad, unrelated])
    # Inna autorka też może zostać objęta konfliktem ID; żadna grupa 10 nie jest zdrowa.
    assert(!result['announcements'].any? { |row| row['alias_ids'].include?(10) })
    assert(result['diagnostics'].any? { |item| item['code'].include?('conflict') })
    assert_equal(result, PublicationTest.project([unrelated, bad, good]))
  end
  result = PublicationTest.project([nil, {}, 'śmieć', unrelated])
  assert_equal([50], result['announcements'].map { |row| row['__id'] })
end

PublicationTest.test('JSON publiczny jest ścisły i zmiana kolejności kluczy nie zmienia treści') do
  row = PublicationTest.row
  same = PublicationTest.row(11)
  same['settings_json'] = JSON.pretty_generate(JSON.parse(row['settings_json']).to_a.reverse.to_h)
  assert_equal([10, 11], PublicationTest.project([row, same])['announcements'].first['alias_ids'])
  bad_json = ['{}', '[]', '{', '{"a":NaN}', ' ' * 65_537]
  bad_json.each do |json|
    result = PublicationTest.project([row.merge('settings_json' => json), PublicationTest.row(50, 'Inna')])
    assert_equal([50], result['announcements'].map { |record| record['__id'] })
    assert(!result['diagnostics'].empty?)
  end
  assert_raises(GameRoomTournaments::Publication::Incomplete) { PublicationTest.project([row], complete: false) }
  assert_raises(GameRoomTournaments::Publication::Incomplete) { PublicationTest.project(Array.new(4097, row)) }
end

PublicationTest.test('duplikat głębokiej opcji odrzuca wcześniej poprawny model gry') do
  options = { 'variant' => { 'levels' => [{ 'leaf' => 1, 'sibling' => { 'leaf' => 2 } }] } }
  game = Object.new
  game.define_singleton_method(:default_options) { options }
  game.define_singleton_method(:effective_option_definitions) { |_selected = {}| [] }
  game.define_singleton_method(:normalize_options) { |value| value }
  game.define_singleton_method(:minimum_players) { 2 }
  game.define_singleton_method(:maximum_players) { 2 }
  game.define_singleton_method(:validation_error) { |_value, player_count:| nil }
  registry = Object.new
  registry.define_singleton_method(:build) { |_id| game }
  row = PublicationTest.row
  settings = JSON.parse(row.fetch('settings_json')).merge('game_options' => options)
  row['settings_json'] = JSON.generate(settings)
  project = ->(value) { GameRoomTournaments::Publication.project(rows: [value], registry: registry, complete: true) }
  assert_equal(1, project.call(row)['announcements'].length)
  ['"leaf":1,"leaf":1', '"leaf":null,"leaf":1', '"\\u006ceaf":1,"leaf":1'].each do |token|
    damaged = row.merge('settings_json' => row.fetch('settings_json').sub('"leaf":1', token))
    assert_equal([], project.call(damaged)['announcements'])
  end
end

PublicationTest.test('duplikaty identyczne, różne i escapowane w poprawnych dokumentach są odrzucane') do
  row = PublicationTest.row
  assert_equal(1, PublicationTest.project([row])['announcements'].length)
  {
    'settings_json' => ['"rematch":false', '"bot_delay":1'],
    'schedule_json' => ['"start":"12:00"']
  }.each do |field, tokens|
    tokens.each do |token|
      key, value = token.split(':', 2)
      escaped = key.sub(key[1], '\\u%04x' % key[1].ord)
      [[key, value], [key, 'null'], [escaped, value], [escaped, 'null']].each do |duplicate_key, duplicate_value|
        json = row.fetch(field).sub(token, "#{duplicate_key}:#{duplicate_value},#{token}")
        assert(json != row.fetch(field))
        result = PublicationTest.project([row.merge(field => json)])
        assert_equal([], result['announcements'], "Przyjęto #{field}: #{json}")
        assert(!result['diagnostics'].empty?)
      end
    end
  end
end

PublicationTest.test('zamrożony kontrakt kolumn i jawny bool nie poddają się obcym obiektom') do
  assert_raises(FrozenError) { GameRoomTournaments::Publication::COLUMNS.first.replace('zmienione') }
  assert_raises(FrozenError) { GameRoomTournaments::Publication::SETTINGS.first.replace('zmienione') }
  hostile = Object.new
  def hostile.equal?(_other); true; end
  assert_raises(GameRoomTournaments::Publication::Incomplete) { PublicationTest.project([], complete: hostile) }
end

PublicationTest.test('pełne 366 okien, warianty formatu i gra z niestandardową liczebnością') do
  value = PublicationTest.draft
  value['windows'] = Array.new(366) do |index|
    date = (Date.new(2026, 1, 1) + index).strftime('%Y-%m-%d')
    { 'date' => date, 'start' => '12:00', 'end_date' => date, 'end' => '21:00' }
  end
  %w[round_robin groups_knockout].each do |format|
    snapshot = PublicationTest.build(value.merge('format' => format, 'rematch' => true)).to_row
    assert_equal(value['windows'], JSON.parse(snapshot['schedule_json'])['windows'])
    assert_equal(1, PublicationTest.project([snapshot.merge('__id' => 8, '__insertion_user' => 'Ala', '__insertion_time' => 90)])['announcements'].size)
  end
  spades = PublicationTest.draft('spades')
  spades['game_options']['team_size'] = 2
  error = PublicationTest.invalid(spades.merge('players_per_match' => 3))
  assert_equal(:game_validation, error.code)
end

PublicationTest.test('całkowity budżet bajtów nigdy nie zwraca cichego prefiksu') do
  row = PublicationTest.row.merge('rules' => 'x' * 16_384)
  assert_raises(GameRoomTournaments::Publication::Incomplete) { PublicationTest.project(Array.new(1024, row)) }
  exact = PublicationTest.project([PublicationTest.row, PublicationTest.row])
  assert_equal([10], exact['announcements'].first['alias_ids'])
  assert_equal([], exact['diagnostics'])
end

PublicationTest.test('konfiguracja grup przechodzi publikację bez zmiany dawnych ogłoszeń') do
  value = PublicationTest.draft.merge('format' => 'groups_knockout', 'group_count' => 2, 'places_per_group' => 1)
  row = PublicationTest.build(value).to_row
  settings = JSON.parse(row['settings_json'])
  assert_equal(2, settings['group_count'])
  assert_equal(1, settings['places_per_group'])
  assert_equal(1, PublicationTest.project([row.merge('__id' => 80, '__insertion_user' => 'Ala', '__insertion_time' => 90)])['announcements'].size)
  legacy = PublicationTest.build(PublicationTest.draft.merge('format' => 'groups_knockout')).to_row
  assert_equal(false, JSON.parse(legacy['settings_json']).key?('group_count'))
  [value.merge('group_count' => 1), value.merge('group_count' => '2'), value.merge('places_per_group' => nil)].each do |bad|
    assert_equal(:invalid_group_configuration, PublicationTest.invalid(bad).code)
  end
end

PublicationTest.test('automatyczna polityka awansu pozostaje w ogłoszeniu i nie zamraża liczby zgłoszeń') do
  value = PublicationTest.draft.merge('format' => 'groups_knockout', 'group_advancement' => 'automatic_cross_groups_v1')
  row = PublicationTest.build(value).to_row
  settings = JSON.parse(row['settings_json'])
  assert_equal('automatic_cross_groups_v1', settings['group_advancement'])
  assert_equal(nil, settings['group_count'])
  assert_equal(nil, settings['places_per_group'])
  assert_equal(1, PublicationTest.project([row.merge('__id' => 81, '__insertion_user' => 'Ala', '__insertion_time' => 90)])['announcements'].size)
  tampered = settings.merge('group_count' => 4)
  rejected = PublicationTest.project([row.merge('settings_json' => JSON.generate(tampered), '__id' => 82, '__insertion_user' => 'Ala', '__insertion_time' => 90)])
  assert_equal([], rejected['announcements'])
  assert(!rejected['diagnostics'].empty?, 'Invalid automatic configuration must be quarantined')
end
