# encoding: UTF-8
require_relative '../support/temporary_directory'
# Pionowa regresja: prawdziwy hub, natywne kontrolki, Tasks i lokalny magazyn.
# Wszystkie pliki wyłącznie w odizolowanym TMPDIR; wyjścia urządzeń w pamięci.
require 'tmpdir'
require_relative '../support/tournament_native'
require_relative '../support/native_tasks'
require_relative '../support/tournament_local_hub'
require_relative '../support/tournament_public_service'
require_relative '../support/localization'
require_relative '../../lib/tournaments/local_test_hub'
GameRoomTestLocalization.use_language('en')
G = GameRoomTournaments
T = TournamentLocalHubTest
E = TournamentPublicationEditorTest

module EltenAPI
  def loop_update
    Thread.pass
  end
end

module PreflightWorkspaceTrace
  def publish(**values)
    $preflight_trace[:save] += 1
    super
  end
end
module PreflightServiceTrace
  def publish(**values)
    $preflight_trace[:service] += 1
    super
  end
end
module PreflightJournalTrace
  def prepare(**values)
    $preflight_trace[:prepare] += 1
    raise Errno::EACCES, 'Izolowana odmowa dziennika' if $preflight_failure == :journal
    super
  end
end
module PreflightInsertTrace
  def insert_row(*values)
    $preflight_trace[:insert] += 1
    result = super
    raise G::LocalTestTables::Error, :store_io_error if $preflight_failure == :after_append
    result
  end
end
module PreflightModelTrace
  def from_draft(**values)
    $preflight_trace[:validation] << values
    $preflight_validate&.call(values)
    super
  rescue G::Publication::Invalid => error
    $preflight_trace[:codes] << error.code
    raise
  end
end
module PreflightEditorSaveTrace
  def initialize(**values)
    callback = values.fetch(:save)
    super(**values.merge(save: lambda { |**data|
      $preflight_trace[:callback] += 1
      callback.call(**data)
    }))
  end
end
G::PublicationEditor.prepend(PreflightEditorSaveTrace)
G::LocalWorkspace.prepend(PreflightWorkspaceTrace)
G::PublicService.prepend(PreflightServiceTrace)
G::OperationJournal.prepend(PreflightJournalTrace)
G::LocalTestTables.prepend(PreflightInsertTrace)
G::Publication.singleton_class.prepend(PreflightModelTrace)

observations = []
{
  incomplete_settings: ['pairing', nil, 'This form has not requested publication. Complete the match settings in the saved draft: tournament format, pairing, rematches and players per match.'],
  missing_windows: ['windows', [], 'This form has not requested publication. Add or correct the playing windows in the saved draft.'],
  invalid_options: ['game_options', {'bot_delay' => 'wrong'}, 'This form has not requested publication. Correct the game options in the saved draft.'],
  invalid_players_per_match: ['players_per_match', 3, 'This form has not requested publication. Correct the number of players per match in the saved draft.']
}.each do |code, (key, value, expected)|
  GameRoomTest::TemporaryDirectory.create('publication-preflight-') do |directory|
    $preflight_trace = {callback: 0, save: 0, service: 0, prepare: 0, insert: 0, validation: [], codes: []}
    alerts = []
    program = Object.new
    program.define_singleton_method(:data_path) { directory }
    program.define_singleton_method(:server_tables) { raise 'Niedozwolona sieć' }
    args = T.args(program: program, alert: ->(message) { alerts << message })
    drafts = G::DraftWorkspace.new(**args)
    input = Object.new.extend(TournamentPublicServiceSupport).draft.merge(key => value)
    row = drafts.persist(nil, input)
    assert(row, "Nie zapisano fixture: #{alerts.inspect}")
    path = File.join(directory, Dir.glob('tournament-drafts-*.json', base: directory).fetch(0))
    bytes = File.binread(path)
    driver = TournamentNativeDriver.new
    driver.open_test_participant
    driver.step('Choose a test participant', [13]) do |form|
      T.field(form, 'Test participant name').set_text('Testowa Alicja')
      form.index = form.fields.index(T.button(form, 'Use test participant'))
    end
    driver.step('Local tournament tests', [13]) { |form| form.index = form.fields.index(T.button(form, 'Publish a draft in local test')) }
    driver.step('Choose a local draft', [13]) { |form| form.index = form.fields.index(T.button(form, 'Publish')) }
    observed = nil
    driver.step(E::HEADER) do |form|
      E.fill(form)
      form.index = form.fields.index(E.button(form))
      before = E.document(form)
      E.button(form).press
      observed = {code: code, alerts: alerts.dup, status: T.field(form, 'Status').text,
        document_unchanged: E.document(form) == before, rules_editable: !E.readonly?(T.field(form, E::RULES)),
        focus: form.fields[form.index].equal?(E.button(form)), summary_readonly: E.readonly?(form.fields.first)}
      form.cancel_button.press
    end
    driver.step('Choose a local draft', [27])
    driver.step('Local tournament tests', [27])
    G::LocalTestHub.new(**args, clock: -> { 100 }).run
    driver.finish
    workspace = G::LocalWorkspace.new(**args.reject { |name, _| name == :confirm }, actor: 'Testowa Alicja')
    observed.merge!(trace: $preflight_trace.reject { |name, _| name == :validation },
      operations: workspace.operations, announcements: workspace.load.fetch('announcements'),
      draft_unchanged: File.binread(path) == bytes, expected: expected)
    observations << observed
  end
end
puts JSON.pretty_generate(observations)
observations.each do |row|
  assert(row[:trace].values_at(:callback, :save, :service, :prepare, :insert) == [0, 0, 0, 0, 0], "#{row[:code]}: odmowa powinna poprzedzać save/service/prepare/insert")
  assert(row[:trace][:codes] == [row[:code]], 'Brak rzeczywistej przyczyny walidatora')
  assert(row[:alerts] == [row[:expected]] && row[:status] == row[:expected], 'Status przykrył konkretną przyczynę')
  assert(row.values_at(:document_unchanged, :rules_editable, :focus, :summary_readonly, :draft_unchanged).all?, 'Odmowa zmieniła dokument, fokus lub szkic')
  assert(row[:operations].empty? && row[:announcements].empty?, 'Odmowa utworzyła operację/publikację')
end
puts 'PASS brak pairing i okien: Hub → Editor → prawdziwy model; 0save/0prepare/0insert, dokładny Status, zachowany dokument/szkic/fokus'

module PreflightSnapshotFailure
  def read_rows(*values, **options)
    raise G::TablesGateway::Error, 'Izolowana awaria snapshotu' if $preflight_failure == :snapshot
    super
  end
end
G::TablesGateway.prepend(PreflightSnapshotFailure)

# Dodatnia kontrola i prawdziwe awarie zapisu. Żaden callback nie fabrykuje nil.
[:confirmed, :after_append, :journal, :snapshot, :program].each do |scenario|
  GameRoomTest::TemporaryDirectory.create('publication-preflight-boundary-') do |directory|
    $preflight_trace = {callback: 0, save: 0, service: 0, prepare: 0, insert: 0, validation: [], codes: []}
    $preflight_failure = scenario
    messages, active, editor = [], nil, nil
    program = Object.new
    program.define_singleton_method(:data_path) { directory }
    program.define_singleton_method(:server_tables) { raise 'Niedozwolona sieć' }
    reenter = lambda do
      3.times { E.button(active).press; active.cancel_button.press; active.game_room_hotkey_action(1).call; editor.wait }
    end
    args = T.args(program: program, alert: ->(message) { messages << message; reenter.call if active })
    row = G::DraftWorkspace.new(**args).persist(nil, Object.new.extend(TournamentPublicServiceSupport).draft)
    assert(row, 'Nie udał się zapis fixture')
    driver = TournamentNativeDriver.new
    driver.open_test_participant
    driver.step('Choose a test participant', [13]) do |form|
      T.field(form, 'Test participant name').set_text('Testowa Alicja')
      form.index = form.fields.index(T.button(form, 'Use test participant'))
    end
    driver.step('Local tournament tests', [13]) { |form| form.index = form.fields.index(T.button(form, 'Publish a draft in local test')) }
    driver.step('Choose a local draft', [13]) { |form| form.index = form.fields.index(T.button(form, 'Publish')) }
    cause = RuntimeError.new('Pierwotna przyczyna walidatora')
    failure = ArgumentError.new('Błąd programu walidatora')
    $preflight_validate = lambda do |values|
      next unless $preflight_trace[:save].zero?
      assert(editor.instance_variable_get(:@busy), 'Walidator poza guardem')
      assert(!editor.instance_variable_get(:@attempted) && !E.readonly?(T.field(active, E::RULES)), 'Zatrzask przed walidacją')
      assert(values[:draft].frozen? && values[:draft]['game_options'].frozen?, 'Walidator bez immutable snapshotu')
      reenter.call
      raise failure, cause: cause if scenario == :program
    end
    driver.step(E::HEADER) do |form|
      active = form
      E.fill(form)
      form.index = form.fields.index(E.button(form))
      before = E.document(form)
      if scenario == :program
        caught = assert_raises(ArgumentError) { E.button(form).press }
        assert(caught.equal?(failure) && caught.cause.equal?(cause), 'Zamaskowano błąd programu/cause')
        assert($preflight_trace.values_at(:callback, :save, :prepare, :insert) == [0, 0, 0, 0], 'Błąd walidatora przeszedł do zapisu')
        assert(!editor.instance_variable_get(:@attempted) && !E.readonly?(T.field(form, E::RULES)), 'Błąd walidatora zlecił próbę')
        form.cancel_button.press
      else
        E.button(form).press
        count = $preflight_trace[:validation].length
        3.times { E.button(form).press }
        assert($preflight_trace[:validation].length == count && $preflight_trace[:callback] == 1 && $preflight_trace[:save] == 1, 'Ponowne Submit uruchomiło walidację/zapis')
        assert(E.document(form) == before && form.fields.grep(ListBox).empty? && form.fields.grep(EditBox).all? { |field| E.readonly?(field) }, 'Próba odblokowała dokument')
        expected = scenario == :confirmed ? 'Publication confirmed in local test.' : 'Publication not confirmed. This form cannot send again. Check the operation in the local test hub.'
        assert(T.field(form, 'Status').text == expected, 'Awaria storage udaje brak zlecenia')
        form.cancel_button.press unless scenario == :confirmed
      end
      active = nil
    end
    driver.step('Choose a local draft', [27])
    driver.step('Local tournament tests', [27])
    original_new = G::PublicationEditor.method(:new)
    T.replace(G::PublicationEditor, :new, ->(**values) { editor = original_new.call(**values) }) do
      G::LocalTestHub.new(**args, clock: -> { 100 }).run
    end
    driver.finish
    $preflight_validate = nil
    $preflight_failure = nil
    workspace = G::LocalWorkspace.new(**args.reject { |key, _| key == :confirm }, actor: 'Testowa Alicja')
    operations = workspace.operations
    view = workspace.load
    expected_publications = [:confirmed, :after_append].include?(scenario) ? 1 : 0
    expected_inserts = scenario == :confirmed ? 2 : expected_publications
    assert($preflight_trace[:insert] == expected_inserts && view['announcements'].length == expected_publications, 'Niepoprawna liczba zapisów publikacji i zgłoszenia organizatora')
    if scenario == :program
      assert(operations.empty? && messages.empty?, 'Błąd programu utworzył operację lub alert danych')
    elsif scenario == :journal
      assert(operations.empty? && $preflight_trace[:prepare] == 1, 'EACCES utworzył rekord albo omija prepare')
    else
      record = operations.fetch(0)
      expected = {confirmed: 'confirmed', after_append: 'attempted', snapshot: 'prepared'}.fetch(scenario)
      assert(record['status'] == expected, 'Zmieniono prawdziwy stan dziennika')
      inputs = $preflight_trace[:validation]
      assert(inputs.length == 2 && inputs.first.reject { |key, _| key == :publication_key } == inputs.last.reject { |key, _| key == :publication_key }, 'Walidacja dostała inne dane niż Service')
      assert(record['values']['publication_key'] != inputs.first[:publication_key], 'Utrwalono techniczny klucz preflight')
      assert(record['intent_id'] == "draft:#{row['id']}:revision:#{row['revision']}", 'Zmieniono zamiar publikacji')
      if scenario == :after_append
        driver = TournamentNativeDriver.new
        driver.open_test_participant
        driver.step('Choose a test participant', [13]) do |form|
          T.field(form, 'Test participant name').set_text('Testowa Alicja')
          form.index = form.fields.index(T.button(form, 'Use test participant'))
        end
        driver.step('Local tournament tests', [13]) { |form| form.index = form.fields.index(T.button(form, 'Publish a draft in local test')) }
        driver.step('Choose a local draft', [13]) { |form| form.index = form.fields.index(T.button(form, 'Publish')) }
        driver.step('Tournament operations', [13]) { |form| form.index = form.fields.index(T.button(form, 'Check selected operation')) }
        driver.step('Tournament operations', [27])
        driver.step('Choose a local draft', [27])
        driver.step('Local tournament tests', [27])
        G::LocalTestHub.new(**args, clock: -> { 100 }).run
        driver.finish
        assert(workspace.operations.fetch(0)['status'] == 'confirmed' && $preflight_trace[:insert] == 2, 'Check powinno uzgodnić publikację i dokończyć zapis organizatora')
        assert(workspace.load['announcements'].one?, 'Check powieliło publikację')
      end
    end
    puts "PASS granica #{scenario}: #{$preflight_trace.slice(:callback, :save, :service, :prepare, :insert).inspect}; prawdziwe dane, reentry walidatora/alertu, readonly, journal/Check"
  end
end

module PreflightDraftLoadTrace
  def load
    rows = super
    $preflight_loaded_rows = rows
    rows
  end
end
G::DraftWorkspace.prepend(PreflightDraftLoadTrace)

# Mutacje caller-a i zmiana realnego konta nie podmieniają migawki/aktora.
[:alert, :help].each do |boundary|
  GameRoomTest::TemporaryDirectory.create('publication-preflight-context-') do |directory|
    $preflight_trace = {callback: 0, save: 0, service: 0, prepare: 0, insert: 0, validation: [], codes: []}
    owner, messages, editor, active, parent, returns = 'RealOwner', [], nil, nil, nil, nil
    program = Object.new
    program.define_singleton_method(:data_path) { directory }
    program.define_singleton_method(:server_tables) { raise 'Niedozwolona sieć' }
    attack = lambda do
      assert(editor.instance_variable_get(:@busy), 'Alert/pomoc/fokus poza busy')
      3.times do
        E.button(active).press
        active.cancel_button.press
        active.game_room_hotkey_action(1).call
        T.button(parent, 'Change test participant').press
        editor.wait
      end
    end
    mutate = lambda do
      source = $preflight_loaded_rows.fetch(0)
      source['pairing'] = 'all_combinations'
      source['revision'] += 1
      source['game_options'].clear
      source['windows'].clear
      source['name'].replace('Inny szkic po callbacku')
      owner = 'OtherOwner'
      attack.call
    end
    alert = lambda do |message|
      messages << message
      mutate.call if boundary == :alert && active
    end
    args = T.args(program: program, user: -> { owner }, alert: alert)
    input = Object.new.extend(TournamentPublicServiceSupport).draft
    input['pairing'] = nil if boundary == :alert
    row = G::DraftWorkspace.new(**args).persist(nil, input)
    path = File.join(directory, Dir.glob('tournament-drafts-*.json', base: directory).fetch(0))
    bytes = File.binread(path)
    snapshot = G::Publication::Data.copy(row)
    driver = TournamentNativeDriver.new
    driver.open_test_participant
    driver.step('Choose a test participant', [13]) do |form|
      T.field(form, 'Test participant name').set_text('Testowa Alicja')
      form.index = form.fields.index(T.button(form, 'Use test participant'))
    end
    driver.step('Local tournament tests', [13]) do |form|
      parent = form
      form.index = form.fields.index(T.button(form, 'Publish a draft in local test'))
    end
    driver.step('Choose a local draft', [13]) { |form| form.index = form.fields.index(T.button(form, 'Publish')) }
    driver.step(E::HEADER) do |form|
      active = form
      E.fill(form)
      rules = E.field(form, E::RULES)
      rules.index, rules.check = 2, 4
      before = E.document(form)
      form.index = form.fields.index(E.button(form))
      [:before_focus, :focus].each { |event| E.button(form).on(event) { attack.call } }
      if boundary == :help
        form.game_room_hotkey_action(1).call
        assert(SpeechOutput.calls.drop(returns[0]).length == 1 && NVDA.calls.drop(returns[1]).length == 1, 'Powrót F1 nie jest pojedynczy')
        assert($preflight_trace[:validation].empty?, 'Pomoc uruchomiła walidację')
      end
      E.button(form).press
      if boundary == :alert
        first_status = E.field(form, 'Status').text
        E.button(form).press
        assert(E.field(form, 'Status').text == first_status && first_status.start_with?('This form has not requested publication.'), 'Ponowna odmowa przykryła przyczynę')
        assert($preflight_trace[:codes] == [:incomplete_settings, :incomplete_settings], 'Zmiana caller-a naprawiła snapshot')
        assert(!editor.instance_variable_get(:@attempted), 'Odmowa danych ustawiła attempted')
      else
        assert(E.field(form, 'Status').text.start_with?('Publication not confirmed.') && editor.instance_variable_get(:@attempted), 'Zmiana konta udaje odmowę danych')
        assert(E.readonly?(rules), 'Zmiana konta po save odblokowała regulamin')
      end
      assert($preflight_trace[:validation].all? { |values| values[:draft] == snapshot }, 'Callback zmienił walidowaną rewizję/migawkę')
      assert(E.document(form) == before && [rules.index, rules.check] == [2, 4], 'Callback zmienił dokument lub kursor')
      assert(editor.instance_variable_get(:@actor) == 'Testowa Alicja', 'Callback zmienił testowego aktora')
      active = nil
      form.cancel_button.press
    end
    if boundary == :help
      driver.step('Keyboard shortcuts', [27]) do
        mutate.call
      end
      driver.on_resume = lambda do |form|
        next unless active && form.fields.first.header == 'Keyboard shortcuts'
        attack.call
        returns = [SpeechOutput.calls.length, NVDA.calls.length]
      end
    end
    driver.step('Choose a local draft', [27])
    driver.step('Local tournament tests', [27])
    original_new = G::PublicationEditor.method(:new)
    T.replace(G::PublicationEditor, :new, ->(**values) { editor = original_new.call(**values) }) do
      G::LocalTestHub.new(**args, clock: -> { 100 }).run
    end
    driver.finish
    assert($preflight_trace.values_at(:save, :service, :prepare, :insert) == [0, 0, 0, 0], 'Callback konta/danych wykonał nieuprawniony zapis')
    assert($preflight_trace[:callback] == (boundary == :alert ? 0 : 1), 'Nieprawidłowa liczba wejść do callbacka save')
    assert(File.binread(path) == bytes, 'Callback zmienił zapisany szkic')
    puts "PASS #{boundary}: zmiana danych/konta i reentry nie zmienia snapshotu, rewizji, aktora, tekstu/caret; 0workspace/0prepare/0insert, callback=#{$preflight_trace[:callback]}"
  end
end
