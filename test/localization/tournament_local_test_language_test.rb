# encoding: UTF-8
require_relative '../support/tournament_local_test_language'
T = TournamentLocalTestLanguage
$stdout.set_encoding(Encoding::UTF_8)
$stderr.set_encoding(Encoding::UTF_8)

# Oddzielne procesy: natywne kontrolki i lekka atrapa runtime są niezgodne.
# Dzieci uruchamiają ten plik, bez inline Ruby i bez zależności od raportów/tmp.
if ARGV.empty?
  results = %w[catalog native-pl native-en].map do |mode|
    output, status = Open3.capture2e(RbConfig.ruby, __FILE__, mode)
    puts "=== #{mode} ===\n#{output}"
    [mode, status.success?]
  end
  puts "Lokalizacja turniejów: #{results.count { |_, ok| ok }}/#{results.length} izolowanych prób"
  exit(results.all? { |_, ok| ok } ? 0 : 1)
end

if ARGV == ['catalog']
  # Biblioteka parsera PO, nie CLI/Bundler zmieniający zestaw gemów runtime.
  require_relative '../../tools/support/translation_catalog'
  require_relative '../support/game_room_language_runtime'
  host_root = EltenTestHost.root
  GameRoomLanguageRuntime.load_host(host_root)
  Configuration.language = 'en-GB'
  Object.new.send(:loadmo, '')
  messages = T.messages
  po = GameRoomTranslationCatalog.read_po(File.join(T::ROOT, 'locale/PL.po'))
  # GetText może oznaczyć klucze jako UTF-8; porównujemy MO bajtowo,
  # bez zmieniania tekstów ani globalnego gettext/produkcji.
  mo = GameRoomTranslationCatalog::SeedMO.open(File.join(T::ROOT, 'locale/PL.mo')).to_h.transform_keys(&:b).transform_values(&:b)
  failures = []
  GameRoomLanguageRuntime.protect_host do
    pl = GameRoomLanguageRuntime::Runtime.new(settings: {'interface_language' => 'pl', 'known_languages' => ['pl']}).start
    en = GameRoomLanguageRuntime::Runtime.new(settings: {'interface_language' => 'en', 'known_languages' => ['en']}).start
    [pl, en].each do |runtime|
      T.equal([Encoding::ASCII_8BIT], runtime.source_encodings.uniq, 'Pominięto binarną granicę runtime')
      T.equal(['settings.json'], runtime.settings_reads, 'Język nie pochodzi z ustawień aplikacji')
    end
    messages.each do |message|
      id, context, plural = message.values_at(:msgid, :msgctxt, :msgid_plural)
      entry = po[context, id]
      key = (context ? context + "\004" : '') + id + (plural ? "\0" + plural : '')
      if !entry || entry.obsolete? || entry.fuzzy? || entry.msgstr.to_s.split("\0", -1).any?(&:empty?) || !mo.key?(key.b)
        failures << "Brak aktywnego tłumaczenia PO/compiled PL.mo: #{id.inspect}"
        next
      end
      T.equal(entry.msgstr.b, mo[key.b], "MO jest nieaktualne: #{id}")
      counts = plural ? [0, 1, 2, 5, 22] : [nil]
      catalog = pl.namespace::GameRoomLocalization::Catalog.new(File.binread(File.join(T::ROOT, 'locale/PL.mo')))
      counts.each do |count|
        direct = catalog.translate(id, context: context, count: count)
        T.check(direct && !direct.strip.empty?, "Pusty MO/fallback: #{id}")
        value = pl.namespace::GameRoomLocalization.translate(id.b, context: context, plural: plural, count: count)
        T.equal(direct, value, "Runtime PL pominął compiled MO: #{id}")
        T.equal(id.scan(/%\{[^}]+\}/).sort, value.scan(/%\{[^}]+\}/).sort, "Placeholdery: #{id}")
        T.check(value.encoding == Encoding::UTF_8 && value.valid_encoding?, "Kodowanie PL: #{id}")
      end
      fallback = en.namespace::GameRoomLocalization.translate(id.b, context: context)
      T.equal(id, fallback, 'Fallback EN zmieniony przez katalog PL')
      T.equal(Encoding::UTF_8, fallback.encoding, 'Binarna etykieta EN')
    end
    T.equal('Tournaments', en.namespace::EltenGameRoom::MAIN_OPTIONS[3], 'Menu EN')
    failures << 'Menu PL używa fallbacku zamiast Turnieje' unless pl.namespace::EltenGameRoom::MAIN_OPTIONS[3] == 'Turnieje'
  end
  puts "AST: #{messages.length} turniejowych msgidów; nieprawidłowe: #{failures.length}"
  failures.each { |message| warn message }
  T.check(failures.empty?, 'Brakuje polskich tłumaczeń w prawdziwym PL.po/PL.mo/runtime')
  puts 'PASS pełny AST turniejów: aktywne PO, compiled MO, placeholdery, binarny RuntimeBackend PL/EN i izolacja hosta'
  exit 0
end

T.check(%w[native-pl native-en].include?(ARGV.first) && ARGV.length == 1, 'Nieznany tryb testu')
language = ARGV.first.delete_prefix('native-')
choose = ->(pl, en) { language == 'pl' ? pl : en }
host, before, fixture = T.boot_native(language)
G = GameRoomTournaments
registry = GameRoomGames::CATALOG
program = Object.new
program.define_singleton_method(:data_path) { raise 'Test etykiet nie może dotknąć profilu' }
alerts = []
args = {program: program, registry: registry, user: -> { 'Izolowany właściciel' },
  alert: ->(text) { alerts << text }, confirm: ->(*) { raise 'Nieoczekiwane potwierdzenie' }}
owner = G::LocalTestDialogs::Owner.new(args[:user], args[:alert])
workspace = G::LocalWorkspace.new(**args.reject { |key, _| key == :confirm }, actor: T::ACTOR)
mode = workspace.mode_label
T.equal(choose.call('Test lokalny — tylko na tym komputerze', 'Local test — this computer only'), mode, 'Oznaczenie sandboxa')
list = choose.call('Turnieje', 'Tournaments')
participant = choose.call('Wybierz testowego uczestnika', 'Choose a test participant')
name = choose.call('Nazwa testowego uczestnika', 'Test participant name')
use_actor = choose.call('Zatwierdź testowego uczestnika', 'Use test participant')
local = choose.call('Lokalne testy turniejów', 'Local tournament tests')
picker = choose.call('Wybierz lokalny szkic', 'Choose a local draft')
preview = choose.call('Szkic — Łódź — Zapisy otwarte', 'Szkic — Łódź — Registration open')
operations = choose.call('Operacje turniejowe', 'Tournament operations')
editor = choose.call('Opublikuj szkic w lokalnym trybie testowym', 'Publish draft in local test')
status_label = choose.call('Stan', 'Status')
rules_label = choose.call('Regulamin turnieju', 'Tournament rules')
information_label = choose.call('Informacje i zasady', 'Information and rules')

# Hub i pojedynczy powrót prawdziwej wspólnej pomocy F1.
driver = TournamentNativeDriver.new
parent, counts = nil, nil
shared_workspace = Object.new
shared_workspace.define_singleton_method(:load) { G::RegistrationProjection.build(announcements: [], registrations: [], registry: registry, complete: true).to_h }
shared_workspace.define_singleton_method(:mode_label) { mode }
shared_workspace.define_singleton_method(:actor) { T::ACTOR }
%i[join withdraw set_partner partnership_action].each do |name|
  shared_workspace.define_singleton_method(name) { |*| raise "Unexpected mutation: #{name}" }
end
driver.step(list) do |form|
  parent = form
  T.read_form(form)
  T.equal([list, choose.call('Pokaż turnieje', 'Show tournaments')], form.fields.grep(ListBox).map(&:header), 'Shared hub list and filter')
  form.game_room_hotkey_action(1).call
  speech, braille = SpeechOutput.calls.drop(counts[0]), NVDA.calls.drop(counts[1])
  T.equal(1, speech.length, 'F1 powtórzył mowę rodzica')
  T.equal(1, braille.length, 'F1 powtórzył brajla rodzica')
  T.check([speech.first.first, braille.first.first].all? { |text| text.start_with?(list) }, 'F1 odczytał inne pole')
  T.equal(0, form.index, 'F1 zgubił pole')
end
driver.step(choose.call('Skróty klawiszowe', 'Keyboard shortcuts'), [27]) do |form|
  T.check(form.fields.first.text.include?('Ctrl+N') && form.fields.first.text.include?('Ctrl+R'), 'F1 lost creation and refresh shortcuts')
  counts = [SpeechOutput.calls.length, NVDA.calls.length]
end
driver.step(list, [27])
G::Hub.new(**args, workspace_factory: -> { shared_workspace }).run
driver.finish
puts "PASS #{language}: Hub + F1, pojedynczy natywny powrót mowy/brajla"

# Wybór jawnego aktora i właściwy hub, bez tworzenia plików sandboxa.
driver = TournamentNativeDriver.new
driver.open_test_participant
driver.step(participant, [13]) do |form|
  T.read_form(form)
  T.field(form, name).set_text(T::ACTOR)
  form.index = form.fields.index(T.button(form, use_actor))
end
driver.step(local, [27]) do |form|
  T.read_form(form)
  T.check(form.fields.first.text.include?(T::ACTOR) && form.fields.first.text.include?(mode), 'Hub zgubił aktora/backend')
  T.button(form, choose.call('Operacje', 'Operations'))
  T.button(form, choose.call('Przeglądaj lokalne turnieje testowe', 'Browse local test tournaments'))
end
G::LocalTestHub.new(**args).run
driver.finish
puts "PASS #{language}: Participant + LocalTestHub"

driver = TournamentNativeDriver.new
driver.step(picker, [27]) do |form|
  T.read_form(form)
  T.equal(['Szkic — Łódź'], form.fields.first.options, 'Nazwa szkicu')
  T.check(form.fields[1].text.include?(choose.call('Enter na liście otwiera wyłącznie podgląd szkicu', 'Enter on the list only views the draft')), 'Picker sugeruje wysłanie Enterem')
end
G::LocalTestDialogs::DraftPicker.new(program: program, registry: registry, rows: [T.draft], owner: owner,
  alert: args[:alert], context: mode, publish: ->(*) { raise 'Nieoczekiwana publikacja' }).run
driver.finish
puts "PASS #{language}: DraftPicker, odczyt etykiet i kontekstu"

snapshot = T.snapshot
public_args = {program: program, registry: registry, load: -> { snapshot }, join: ->(*) { raise 'Nieoczekiwany zapis' },
  alert: args[:alert], mode_label: mode, actor: T::ACTOR, clock: -> { 150 }}
driver = TournamentNativeDriver.new
driver.step(list, [13]) { |form| T.read_form(form) }
T.action(driver, preview, information_label)
driver.step(information_label, [27]) do |form|
  T.read_form(form)
  text = form.fields.first.text
  %w[18:00 21:00].each { |value| T.check(text.include?(value), 'Brak okien rozgrywek') }
  [GameRoomContent.utf8(GameRoomLocalization.translate('Registration opens')),
    GameRoomContent.utf8(GameRoomLocalization.translate('Registration closes')),
    GameRoomContent.utf8(GameRoomLocalization.translate("Organizer's notes"))].each do |label|
    T.check(text.include?(label), "Podgląd zgubił #{label}")
  end
  T.check(text.include?('Graj uczciwie. Żółć.'), 'Podgląd zmienił oryginalny tekst organizatora')
end
driver.step(preview, [27])
driver.step(list, [27])
G::PublicScreen.new(**public_args).run
driver.finish
puts "PASS #{language}: PublicScreen/PublicPreview, regulamin, terminy zapisów i okna rozgrywek"

['prepared', 'attempted', nil].each do |state|
  record = state && {'status' => state}
  driver = TournamentNativeDriver.new
  T.action(driver, preview, choose.call('Dołącz do turnieju', 'Join tournament'))
  driver.step(preview, [27]) do |form|
    text = T.field(form, status_label).text
    T.check(text.include?(choose.call('Zapis do turnieju nie został potwierdzony.', 'Registration not confirmed.')), 'Brak uczciwego statusu zapisu')
    T.check(!text.include?(choose.call('Zapis do turnieju potwierdzony.', 'Registration confirmed.')), 'Fałszywy sukces zapisu')
    T.read_form(form)
  end
  G::PublicPreview.new(**public_args.merge(join: ->(*) { record }), snapshot: snapshot,
    publication: snapshot.fetch('announcements').first).wait
  driver.finish
end
puts "PASS #{language}: PublicPreview prepared/attempted/nil nie oznaczają sukcesu"

rows = %w[prepared attempted].each_with_index.map do |state, i|
  {'id' => "operacja-#{i}", 'status' => state, 'kind' => 'join', 'values' => {'tournament_id' => 11}, 'evidence' => nil}
end
driver = TournamentNativeDriver.new
driver.step(operations, [27]) do |form|
  T.read_form(form)
  expected = choose.call(['przygotowano; brak potwierdzenia', 'podjęto próbę; brak potwierdzenia'],
    ['prepared; not confirmed', 'attempted; not confirmed'])
  form.fields.first.options.zip(expected).each { |value, label| T.check(value.include?(label), 'Fałszywy status operacji') }
  T.check(form.fields[1].text.include?(choose.call('Sprawdzenie nigdy nie wysyła jej ponownie.', 'Checking never sends it again.')), 'Brak granicy uzgodnienia')
end
G::OperationsScreen.new(program: program, load: -> { rows }, reconcile: ->(*) { raise 'Nieoczekiwane uzgodnienie' },
  alert: args[:alert], mode_label: mode, actor: T::ACTOR).run
driver.finish
puts "PASS #{language}: OperationsScreen, prepared/attempted z nil evidence"

['prepared', 'attempted', nil].each do |state|
  driver = TournamentNativeDriver.new
  publish = choose.call('Opublikuj w lokalnym trybie testowym', 'Publish in local test')
  submits = 0
  driver.step(editor, [13]) do |form|
    T.read_form(form)
    T.equal(choose.call('Nie wysłano.', 'Not submitted.'), T.field(form, status_label).text, 'Stan przed wysłaniem')
    T.check(form.game_room_general_help_tips.include?(choose.call('Zapisy otwierają się przy publikacji.',
      'Registration opens when you publish.')), 'Brak informacji o automatycznym otwarciu')
    deadline = T.field(form, choose.call('Koniec zapisów', 'Registration deadline'))
    T.equal(choose.call(['Konkretna data i godzina', '1 godzina przed rozpoczęciem', '2 godziny przed rozpoczęciem',
      '3 godziny przed rozpoczęciem', 'Dzień (24 godziny) przed rozpoczęciem'], ['Specific date and time',
      '1 hour before the start', '2 hours before the start', '3 hours before the start', 'One day (24 hours) before the start']),
      deadline.options, 'Nieprzetłumaczona lista końca zapisów')
    T.field(form, rules_label).set_text('Graj uczciwie. Żółć.')
    T.fill_dates(form, language)
    form.index = form.fields.index(T.button(form, publish))
  end
  driver.step(editor, [27]) do |form|
    text = T.field(form, status_label).text
    T.check(text.include?(choose.call('Publikacja nie została potwierdzona.', 'Publication not confirmed.')), 'Fałszywy sukces publikacji')
    T.check(!text.include?(choose.call('Publikacja potwierdzona', 'Publication confirmed')), 'Niejednoznaczny sukces')
    T.equal(1, submits, 'Powtórne wysłanie')
    T.read_form(form)
  end
  G::PublicationEditor.new(program: program, draft: T.draft, registry: GameRoomGames::CATALOG, mode_label: mode, actor: T::ACTOR,
    timezone: 'local_test:system', clock: -> { 100 }, convert_time: ->(date, _time) { date == '2026-10-01' ? 100 : 200 },
    save: ->(**_) { submits += 1; state && {'status' => state} }, alert: args[:alert]).wait
  driver.finish
end
puts "PASS #{language}: PublicationEditor, wybieraki i uczciwe prepared/attempted/nil"
T.equal(before, T.host_snapshot, 'Test zmienił słownik lub język hosta')
T.equal(language == 'pl' ? 'Cancel' : 'Anuluj', host.send(:_, 'Cancel'), 'Host przejął język aplikacji')
T.equal([Encoding::ASCII_8BIT], T::NativeSources.loaded.values.uniq, 'Źródła turniejowe nie są binarne')
T.check(T::NativeSources.loaded.keys.any? { |path| path.end_with?('/lib/tournaments/publication_editor.rb') }, 'Nie wczytano binarnie edytora')
T.equal(['pl'], fixture.catalog_reads, 'Nie użyto rzeczywistego PL.mo')
puts "PASS #{language}: #{T::NativeSources.loaded.length} binarnych źródeł, natywne kontrolki i MO, host bez zmian; brak urządzeń/sieci/profilu"
