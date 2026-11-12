# encoding: UTF-8
require_relative '../support/temporary_directory'
require 'tmpdir'
require_relative '../support/tournament_native'
require_relative '../support/native_tasks'
require_relative '../support/tournament_local_hub'
require_relative '../support/tournament_public_service'
require_relative '../support/localization'
require_relative '../../lib/tournaments/hub'
require_relative '../../lib/tournaments/local_test_hub'
GameRoomTestLocalization.use_language('en')
T = TournamentLocalHubTest
G = GameRoomTournaments
PICK = 'Choose a test participant'
HUB = 'Local tournament tests'
DRAFTS = 'Choose a local draft'
EDITOR = 'Publish draft in local test'

# Prawdziwy Tasks.run z workerem. Brak GUI, urządzeń i usług sieciowych.
module EltenAPI
  def loop_update
    $local_hub_task_tick&.call
    Thread.pass
  end
end

module NativeLocalHubFlow
  extend TournamentPublicServiceSupport
  module_function
  def actor(driver, name)
    driver.step(PICK, [13]) do |form|
      assert(T.field(form, 'Test participant name').text.empty?, 'Podstawiono aktora')
      T.field(form, 'Test participant name').set_text(name)
      form.index = form.fields.index(T.button(form, 'Use test participant'))
    end
  end
  def action(driver, header, label)
    driver.step(header, [13]) { |form| form.index = form.fields.index(T.button(form, label)) }
  end
  def fill(form)
    TournamentPublicationEditorTest.fill(form)
    [Date.today + 1].zip(%w[closes]).each do |date, kind|
      [date.year, date.month, date.day, 12, 0].zip(%w[year month day hour minute]).each do |value, part|
        field = T.field(form, "Registration #{kind}: #{part}")
        field.index = field.options.index(format(part == 'year' ? '%04d' : '%02d', value)) || raise('Brak daty')
        field.trigger(:move)
      end
    end
  end
  def presentation(header)
    [SpeechOutput.calls.last&.first, NVDA.calls.last&.first].each do |message|
      assert(message.to_s.start_with?(header), "Brak fokusu/mowy/brajla #{header}: #{message.inspect}")
    end
  end
end
F = NativeLocalHubFlow

GameRoomTest::TemporaryDirectory.create('native-local-hub-') do |directory|
  owner = 'RealOwner'
  messages, io_threads = [], []
  program = Object.new
  program.define_singleton_method(:data_path) { io_threads << Thread.current; directory }
  args = T.args(program: program, user: -> { owner }, alert: ->(message) { messages << message })
  drafts = G::DraftWorkspace.new(**args)
  draft = F.draft
  date = (Date.today + 2).iso8601
  draft['windows'] = [{'date' => date, 'start' => '12:00', 'end_date' => date, 'end' => '21:00'}]
  row = drafts.persist(nil, draft)
  assert(row, "Fixture szkicu: #{messages.inspect}")
  draft_path = File.join(directory, Dir.glob('tournament-drafts-*.json', base: directory).fetch(0))
  before = File.binread(draft_path)
  driver = TournamentNativeDriver.new
  driver.open_test_participant
  F.actor(driver, 'Testowa Alicja')
  F.action(driver, HUB, 'Publish a draft in local test')
  driver.step(DRAFTS, [13]) { |form| assert(form.fields.first.is_a?(ListBox), 'Brak listy szkiców') }
  # Drugi Enter w istniejącym podglądzie może otworzyć plan, NIGDY edytor/publikację.
  driver.press('Tournament settings', 13)
  driver.step('Tournament settings', [27])
  driver.step(DRAFTS) do |form|
    F.presentation(DRAFTS)
    assert(form.index == 0 && form.fields.first.index == 0, 'Nie wróciło ID/pole')
  end
  F.action(driver, DRAFTS, 'Publish')
  driver.step(EDITOR, [13]) do |form|
    F.fill(form)
    form.index = form.fields.index(T.button(form, 'Publish in local test'))
  end
  driver.step(DRAFTS, [27])
  F.action(driver, HUB, 'Change test participant')
  F.actor(driver, 'Testowy Bob')
  F.action(driver, HUB, 'Browse local test tournaments')
  driver.step('Tournaments', [13]) { |form| form.index = 0 }
  driver.step(/Próba chess/, [13]) do |form|
    T.field(form, 'Virtual player name (local test only)').set_text('Testowy Bob')
    actions = form.fields.first
    actions.index = actions.options.index('Join tournament') || raise('Missing join action')
    form.index = form.fields.index(actions)
  end
  driver.step(/Próba chess/, [27])
  driver.step('Tournaments', [27])
  driver.step(HUB, [27])
  G::LocalTestHub.new(**args).run
  driver.finish
  assert(io_threads.none? { |thread| thread == Thread.current }, 'data_path na UI zamiast w Tasks')
  assert(File.binread(draft_path) == before, 'Zmieniono szkic/roster')
  alice = G::LocalWorkspace.new(**args.reject { |key, _| key == :confirm }, actor: 'Testowa Alicja')
  snapshot = alice.load
  assert(snapshot['announcements'].length == 1 && snapshot['members'].map { |row| row['account'] }.sort == ['testowa alicja', 'testowy bob'], 'Missing publication, automatic organizer registration or Bob registration')
  record = alice.operations.fetch(0)
  assert(record['intent_id'] == "draft:#{row['id']}:revision:#{row['revision']}", 'Losowy albo zmieniony zamiar')
  tables = File.join(directory, Dir.glob('**/' + G::LocalTestTables::FILE_NAME, base: directory).fetch(0))
  tables_before = File.binread(tables)
  # Nowy hub, ten sam aktor: ponowne otwarcie rewizji prowadzi do operacji, nie edytora.
  driver = TournamentNativeDriver.new
  driver.open_test_participant
  F.actor(driver, 'Testowa Alicja')
  F.action(driver, HUB, 'Publish a draft in local test')
  F.action(driver, DRAFTS, 'Publish')
  driver.step('Tournament operations', [27])
  driver.step(DRAFTS, [27])
  driver.step(HUB, [27])
  G::LocalTestHub.new(**args).run
  driver.finish
  assert(File.binread(tables) == tables_before && File.binread(draft_path) == before, 'Restart powtórzył publikację albo zmienił szkic')
  assert(messages.any? { |message| message.include?('already exists') }, 'Nie ogłoszono poprzedniej operacji')
  puts 'PASS native Tasks+LocalWorkspace+LocalTestTables+PublicationEditor+PublicScreen: A publish/B join/restart dedup; Enter listy tylko podgląd; szkic bajtowo bez zmian'
end

# Każde NOWE okno: pierwszy fokus, wspólne F1, resume i powrót mowy/brajla
# pozostają pod jednym guardem. Atak nie dotyka urządzeń, tylko callbacków.
%w[participant local picker].each do |kind|
  [13, 27].each do |close_key|
    driver = TournamentNativeDriver.new
    target, parent, cursor, presentation_header = nil, nil, nil, nil
    header = {'hub' => 'Tournaments', 'participant' => PICK, 'local' => HUB, 'picker' => DRAFTS}.fetch(kind)
    owner = G::LocalTestDialogs::Owner.new(-> { 'RealOwner' }, ->(message) { raise message })
    args = T.args
    target = case kind
    when 'hub' then G::Hub.new(**args)
    when 'local' then G::LocalTestHub.new(**args)
    when 'participant' then G::LocalTestDialogs::Participant.new(program: args[:program], owner: owner, alert: args[:alert])
    when 'picker'
      rows = [T.draft, T.draft.merge('id' => 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'name' => 'Drugi szkic')]
      G::LocalTestDialogs::DraftPicker.new(program: args[:program], registry: args[:registry], rows: rows,
        owner: owner, alert: args[:alert], context: 'Local test — this computer only; Test actor: Alicja',
        publish: ->(*) { raise 'Publikacja podczas fokusu/pomocy' })
    end
    return_counts, chain, returning = nil, [], false
    input = Marshal.dump(rows) if kind == 'picker'
    attacks = 0
    attack = lambda do |form|
      attacks += 1
      assert(target.instance_variable_get(:@busy), 'Callback poza busy')
      form.fields.grep(Button).each(&:press)
      form.game_room_hotkey_action(1).call
      target.run
    end
    attached = false
    tick = driver.method(:tick)
    driver.define_singleton_method(:tick) do |form|
      tick.call(form)
      next unless !attached && form.is_a?(GameRoomUI::Form) && form.fields.first.header == header
      attached = true
      [:before_focus, :focus].each { |event| form.fields.first.on(event) { attack.call(form) } }
    end
    driver.step(header) do |form|
      parent = form
      if kind == 'participant'
        name = T.field(form, 'Test participant name')
        name.set_text('Żaneta testowa')
        name.index, name.check = 2, 5
        cursor = [name.text, name.index, name.check]
        form.index = 1
        [:before_focus, :focus].each { |event| name.on(event) { attack.call(form) } }
      elsif kind == 'picker'
        form.fields.first.index = 1
      end
      presentation_header = form.fields[form.index].header
      field = form.fields[form.index]
      [:before_focus, :focus].each do |event|
        field.on(event) { chain << [event, form.index, kind == 'picker' ? form.fields.first.index : nil] if returning }
      end
      native_focus = field.method(:focus)
      field.define_singleton_method(:focus) do |*arguments|
        if returning
          chain << [:control_focus, form.index, kind == 'picker' ? form.fields.first.index : nil]
          attack.call(form)
        end
        native_focus.call(*arguments)
      end
      returning = true
      form.game_room_hotkey_action(1).call
      returning = false
      speech = SpeechOutput.calls.drop(return_counts[0]).map(&:first)
      braille = NVDA.calls.drop(return_counts[1]).map(&:first)
      puts "CHECK hub F1 #{kind}/#{close_key}: #{ {speech: speech.length, braille: braille.length, chain: chain}.inspect }"
      assert(speech.length == 1 && braille.length == 1, 'Hub F1 musi ogłosić rodzica dokładnie raz w mowie i brajlu')
      origin = kind == 'participant' ? 1 : 0
      expected = [:before_focus, :control_focus, :focus].map { |event| [event, origin, kind == 'picker' ? 1 : nil] }
      assert(chain == expected, 'Hub F1 pominął łańcuch fokusu albo przejściowo odczytał inne pole/wiersz')
      (speech + braille).each do |message|
        assert(message.start_with?(presentation_header), 'Hub F1 odczytał inne pole')
        assert(message.include?('Drugi szkic') && !message.include?('Szkic — Łódź'), 'Pierwszy odczyt dotyczył innego szkicu') if kind == 'picker'
      end
      assert(!target.instance_variable_get(:@busy), 'Hub nie zwolnił busy po pomocy')
      F.presentation(presentation_header)
      assert(form.index == (kind == 'participant' ? 1 : 0), 'F1 zgubił pole')
      assert(form.fields.first.index == 1, 'F1 zgubił wiersz') if kind == 'picker'
      if cursor
        name = T.field(form, 'Test participant name')
        assert([name.text, name.index, name.check] == cursor, 'F1 zmienił tekst/caret')
      end
    end
    driver.step('Keyboard shortcuts', [close_key]) do |form|
      form.game_room_hotkey_action(1).call
      attack.call(parent)
      return_counts = [SpeechOutput.calls.length, NVDA.calls.length]
    end
    driver.step(header, [27])
    driver.on_resume = lambda do |form|
      if form.equal?(parent)
        assert(target.instance_variable_get(:@finished), 'Resume przed finished')
        attack.call(form)
      elsif parent
        attack.call(parent)
        parent.index = parent.fields.length - 1
        parent.fields.first.index = 0 if kind == 'picker'
      end
    end
    target.run
    target.run
    driver.finish
    assert(attacks >= 3, 'Brak rzeczywistych callbacków fokus/resume')
    assert(Marshal.dump(rows) == input, 'Pomoc zmieniła wejściowy snapshot szkiców') if kind == 'picker'
    puts "PASS native #{kind}/#{close_key}: first focus/F1/before_focus/control.focus/focus/resume/reentry, pojedyncza mowa/brajl, pole/wiersz/tekst/caret"
  end
end

# Błąd walidacji nazwy odtwarza natywny fokus i chroni przed Cancel/Use z alertu.
driver = TournamentNativeDriver.new
messages, target, active = [], nil, nil
alert = lambda do |message|
  messages << message
  assert(target.instance_variable_get(:@busy), 'Alert nazwy poza busy')
  active.fields.grep(Button).each(&:press)
  target.run
end
owner = G::LocalTestDialogs::Owner.new(-> { 'RealOwner' }, alert)
target = G::LocalTestDialogs::Participant.new(program: Object.new, owner: owner, alert: alert)
driver.step(PICK) do |form|
  active = form
  name = T.field(form, 'Test participant name')
  name.set_text(' Alicja')
  name.index, name.check = 2, 4
  form.index = 2
end
driver.press(PICK, 13)
driver.step(PICK, [27]) do |form|
  name = T.field(form, 'Test participant name')
  assert(messages.one? && form.index == 1 && [name.text, name.index, name.check] == [' Alicja', 2, 4], 'Naprawiono nazwę albo utracono caret')
  F.presentation('Test participant name')
end
target.run
driver.finish
puts 'PASS native invalid actor: kontrolowany alert i chroniony tekst/caret/fokus'

# Bezpośrednio wejście/wybór aktora nie buduje nawet katalogu sandboxa.
GameRoomTest::TemporaryDirectory.create('hub-no-io-') do |directory|
  program = Object.new
  program.define_singleton_method(:data_path) { raise 'data_path podczas samego wejścia' }
  [false, true].each do |choose|
    driver = TournamentNativeDriver.new
    if choose
      driver.open_test_participant
      F.actor(driver, 'Testowa Alicja')
      driver.step(HUB, [27])
    else
      driver.step(HUB, [27])
    end
    G::LocalTestHub.new(**T.args(program: program)).run
    driver.finish
    assert(Dir.children(directory).empty?, 'Wejście zbudowało katalog')
  end
end
puts 'PASS native Cancel/wybór aktora bez data_path i bez folderów'

# Rzeczywisty append dochodzi do pliku; błąd po zapisie jest niepewnością,
# nie poleceniem drugiego insertu. Podczas każdego Tasks.run pompujemy atak UI.
module NativeLocalHubInsertBoundary
  def insert_row(*arguments)
    $local_hub_inserts << [arguments.first, Thread.current] if $local_hub_inserts
    result = super
    if $local_hub_fail_after_insert
      $local_hub_fail_after_insert = false
      raise GameRoomTournaments::LocalTestTables::Error, :store_io_error
    end
    result
  end
end
G::LocalTestTables.prepend(NativeLocalHubInsertBoundary)
GameRoomTest::TemporaryDirectory.create('hub-uncertain-') do |directory|
  messages = []
  program = Object.new
  program.define_singleton_method(:data_path) { directory }
  program.define_singleton_method(:server_tables) { raise 'Niedozwolona sieć' }
  args = T.args(program: program, alert: ->(message) { messages << message })
  drafts = G::DraftWorkspace.new(**args)
  row = drafts.persist(nil, F.draft)
  draft_path = File.join(directory, Dir.glob('tournament-drafts-*.json', base: directory).fetch(0))
  original_draft = File.binread(draft_path)
  driver = TournamentNativeDriver.new
  hub = G::LocalTestHub.new(**args)
  driver.open_test_participant
  F.actor(driver, 'Testowa Alicja')
  F.action(driver, HUB, 'Publish a draft in local test')
  F.action(driver, DRAFTS, 'Publish')
  driver.step(EDITOR) { |form| F.fill(form); form.index = form.fields.index(T.button(form, 'Publish in local test')) }
  driver.press(EDITOR, 13)
  driver.press(EDITOR, 13)
  driver.step(EDITOR, [27]) { |form| assert(T.field(form, 'Status').text.include?('not confirmed'), 'Niepewny wynik udaje sukces') }
  # Ponownie ta sama rewizja jeszcze w tej samej liście i potem po restarcie.
  F.action(driver, DRAFTS, 'Publish')
  driver.step('Tournament operations', [27])
  driver.step(DRAFTS, [27])
  driver.step(HUB, [27])
  $local_hub_inserts = []
  $local_hub_fail_after_insert = true
  ticks = 0
  native_task = EltenAPI::Tasks.method(:run)
  task_wrapper = lambda do |**options, &work|
    gate = Queue.new
    released = false
    $local_hub_task_tick = lambda do
      next if released
      released = true
      ticks += 1
      driver.forms.select { |form| [HUB, DRAFTS].include?(form.fields.first.header) && form.instance_variable_get(:@wait) }.each do |form|
        form.fields.grep(Button).each(&:press)
      end
      hub.run
      gate << true
    end
    begin
      native_task.call(**options) { gate.pop; work.call }
    ensure
      $local_hub_task_tick = nil
    end
  end
  T.replace(EltenAPI::Tasks, :run, task_wrapper) { hub.run }
  driver.finish
  assert(ticks >= 3 && $local_hub_inserts.length == 1, 'Brak pompowania albo powtórzony insert')
  assert($local_hub_inserts.none? { |_, thread| thread == Thread.current }, 'Insert na UI')
  workspace = G::LocalWorkspace.new(**args.reject { |key, _| key == :confirm }, actor: 'Testowa Alicja')
  operation = workspace.operations.fetch(0)
  assert(operation['status'] == 'attempted', 'Niejawne reconcile po niepewności')
  tables = File.join(directory, Dir.glob('**/' + G::LocalTestTables::FILE_NAME, base: directory).fetch(0))
  original_announcements = workspace.load['announcements']
  driver = TournamentNativeDriver.new
  driver.open_test_participant
  F.actor(driver, 'Testowa Alicja')
  F.action(driver, HUB, 'Publish a draft in local test')
  F.action(driver, DRAFTS, 'Publish')
  F.action(driver, 'Tournament operations', 'Check selected operation')
  driver.step('Tournament operations', [27])
  driver.step(DRAFTS, [27])
  F.action(driver, HUB, 'Operations')
  driver.step('Tournament operations', [27])
  driver.step(HUB, [27])
  G::LocalTestHub.new(**args).run
  driver.finish
  assert(workspace.operations.fetch(0)['status'] == 'confirmed', 'Jawne Check nie uzgodniło dowodu')
  assert($local_hub_inserts.map(&:first) == %w[tournament_announcements tournament_registrations], 'Recovery repeated publication instead of adding only organizer registration')
  recovered = workspace.load
  assert(recovered['announcements'] == original_announcements && recovered['members'].map { |member| member['account'] } == ['testowa alicja'], 'Recovery changed the announcement or duplicated the organizer')
  assert(File.binread(draft_path) == original_draft, 'Zmiana pliku szkiców')
  # Inna realna tożsamość izoluje pliki, ten sam aktor nie przenosi wpisów.
  other_args = args.merge(user: -> { 'OtherOwner' })
  other = G::LocalWorkspace.new(**other_args.reject { |key, _| key == :confirm }, actor: 'Testowa Alicja')
  assert(other.load['announcements'].empty? && other.operations.empty?, 'Przeciek między kontami plików')
  # Zmiana rewizji jest świadomie nowym zamiarem; po otwarciu nie wysyłamy automatycznie.
  changed = drafts.persist(row, {'name' => 'Ta sama zawartość, nowa rewizja'})
  driver = TournamentNativeDriver.new
  driver.open_test_participant
  F.actor(driver, 'Testowa Alicja')
  F.action(driver, HUB, 'Publish a draft in local test')
  F.action(driver, DRAFTS, 'Publish')
  driver.step(EDITOR, [27])
  driver.step(DRAFTS, [27])
  driver.step(HUB, [27])
  G::LocalTestHub.new(**args).run
  driver.finish
  assert(changed['revision'] == row['revision'] + 1 && $local_hub_inserts.length == 2, 'Nowa rewizja nie jest odrębnym zamiarem albo sama wysłała')
  $local_hub_inserts = nil
end
puts 'PASS native uncertain append/reopen/restart: one publication, one organizer registration after explicit recovery; Tasks reentry, account isolation and new revision'

# Konto może wrócić do starej wartości jeszcze wewnątrz alertu workera.
# Raz ZAOBSERWOWANA zmiana musi pozostać zatrzaśnięta w całym hubie.
GameRoomTest::TemporaryDirectory.create('hub-account-latch-') do |directory|
  owner, messages = 'RealOwner', []
  program = Object.new
  program.define_singleton_method(:data_path) { owner = 'OtherOwner'; directory }
  args = T.args(program: program, user: -> { owner }, alert: ->(message) { messages << message; owner = 'RealOwner' })
  driver = TournamentNativeDriver.new
  driver.open_test_participant
  F.actor(driver, 'Testowa Alicja')
  F.action(driver, HUB, 'Browse local test tournaments')
  driver.step(HUB) do |form|
    T.button(form, 'Change test participant').press
    T.button(form, 'Publish a draft in local test').press
    T.button(form, 'Operations').press
  end
  driver.step(HUB, [27])
  G::LocalTestHub.new(**args).run
  driver.finish
  assert(messages.length >= 4 && Dir.children(directory).empty?, 'Nie zatrzaśnięto konta albo utworzono pliki')
end
puts 'PASS native zmiana realnego konta w tasku i powrót w alercie: hub pozostaje zablokowany'

# Loader binarny bez deklaracji kodowania, angielskie msgid + polskie role
# hosta. Nie jest to paczka ani potwierdzenie pełnego polskiego tłumaczenia.
%w[Hub LocalTestHub LocalTestDialogs].each { |name| G.send(:remove_const, name) }
%w[local_test_dialogs local_test_hub hub].each do |name|
  path = File.expand_path("../../lib/tournaments/#{name}.rb", __dir__)
  TOPLEVEL_BINDING.eval(File.binread(path).sub(/\A# encoding: UTF-8\r?\n/, ''), path, 2)
end
def p_(context, text)
  return 'Przycisk' if context == 'EAPI_Form' && text == 'Button'
  text
end
GameRoomTestLocalization.use_language('en')
driver = TournamentNativeDriver.new
inspect_fields = lambda do |form|
  form.fields.each_with_index do |field, index|
    values = field.is_a?(Button) ? [field.label] : [field.header, *(field.is_a?(ListBox) ? field.options : [field.text])]
    assert(values.all? { |value| value.valid_encoding? && value.encoding == Encoding::UTF_8 }, 'Etykieta binarna nie jest UTF8')
    form.index = index
    form.focus
  end
end
driver.open_test_participant
driver.step(PICK) { |form| inspect_fields.call(form) }
F.actor(driver, 'Testowa Żaneta')
driver.step(HUB) do |form|
  inspect_fields.call(form)
  assert(form.fields.first.text.include?('Test actor: Testowa Żaneta'), 'Zgubiono UTF8 aktora')
end
F.action(driver, HUB, 'Publish a draft in local test')
driver.step(DRAFTS) { |form| inspect_fields.call(form) }
driver.step(DRAFTS, [27])
driver.step(HUB, [27])
T.with_drafts([T.draft]) { G::LocalTestHub.new(**T.args).run }
driver.finish
puts 'PASS native binary sources: Hub/participant/LocalTestHub/picker EN + UTF8 host, wszystkie kontrolki; nie pełne PL'
puts "PIN #{RUBY_DESCRIPTION}; JSON #{JSON::VERSION}"
%w[hub local_test_hub local_test_dialogs local_workspace publication_editor operations_screen public_preview publication].each do |name|
  path = File.expand_path("../../lib/tournaments/#{name}.rb", __dir__)
  puts "PIN #{name}.rb #{Digest::SHA256.file(path).hexdigest}"
end
