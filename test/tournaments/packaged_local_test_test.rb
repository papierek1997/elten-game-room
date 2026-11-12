# encoding: UTF-8
require_relative '../support/temporary_directory'
# Próba kodu z dokładnej paczki; bez argumentu kontroluje binarne źródła repo.
$stdout.set_encoding(Encoding::UTF_8)
$stderr.set_encoding(Encoding::UTF_8)
require 'tmpdir'
require 'date'
require 'digest'
require_relative '../support/binary_rules_load'
raise 'Brak nowego huba turniejów w badanym artefakcie' unless defined?(GameRoomTournaments::Hub)
require_relative '../support/tournament_local_hub'
require_relative '../support/tournament_public_service'
require_relative '../../tools/support/translation_extractor'
require_relative '../../lib/tournaments/local_test_hub'

T = TournamentLocalHubTest
G = GameRoomTournaments
Form.prepend(T::Script)
def loop_update
  Thread.pass
end

def caption(value)
  return value if value.is_a?(Regexp)
  $package_language == 'pl' ? RULES_CATALOG.fetch(value) : value
end

def field(form, header)
  T.field(form, caption(header))
end

def press(form, label)
  T.button(form, caption(label)).trigger(:press)
end

def close(form)
  form.cancel_button.trigger(:press)
end

def inspected(header, &block)
  lambda do |form|
    puts "FORM #{header}: #{form.fields.first.header}"
    assert(caption(header) === form.fields.first.header, "Nieoczekiwane okno zamiast #{header}")
    form.fields.each do |control|
      values = []
      values << control.header if control.respond_to?(:header)
      values << control.label if control.respond_to?(:label)
      values << control.text if control.respond_to?(:text)
      values.concat(control.options) if control.respond_to?(:options)
      assert(values.compact.all? { |text| text.encoding == Encoding::UTF_8 && text.valid_encoding? }, 'Binarne/uszkodzone napisy okna')
    end
    block.call(form)
  end
end

def actor_step(actor)
  inspected('Choose a test participant') do |form|
    assert(field(form, 'Test participant name').text.empty?, 'Podstawiono testowego uczestnika')
    field(form, 'Test participant name').text = actor
  press(form, 'Use test participant')
  end
end

def snapshot_files(directory)
  Dir.glob('**/*', base: directory).select { |path| File.file?(File.join(directory, path)) }.to_h do |path|
    [path, File.binread(File.join(directory, path))]
  end
end

entries = BinaryRulesLoad.instance_variable_get(:@entries)
paths = entries ? entries.keys.grep(%r{\Alib/tournaments/.*\.rb\z}) : Dir.glob('lib/tournaments/**/*.rb', base: BinaryRulesLoad::ROOT)
records, warnings = {}, []
paths.sort.each do |path|
  bytes = BinaryRulesLoad.read(File.join(BinaryRulesLoad::ROOT, path))
  GameRoomTranslationExtractor.extract_source(bytes.dup.force_encoding('UTF-8'), path: path, warnings: warnings).each do |record|
    GameRoomTranslationExtractor.merge_record(records, **record)
  end
end
assert(warnings.empty? && !records.empty?, 'Niepełna ekstrakcja tekstów badanego artefaktu')
records.each_value do |record|
  key = (record[:msgctxt] ? record[:msgctxt] + "\004" : '') + record[:msgid]
  key += "\0" + record[:msgid_plural] if record[:msgid_plural]
  value = RULES_CATALOG.fetch(key)
  assert(!value.empty? && value.valid_encoding?, "Brak compiled PL: #{key}")
  assert(record[:msgid].scan(/%\{[^}]+\}/).sort == value.scan(/%\{[^}]+\}/).sort, "Placeholdery #{key}")
end
assert(EltenGameRoom::MAIN_OPTIONS.include?('Turnieje'), 'Brak nowej polskiej pozycji menu')

%w[en pl].each do |language|
  $package_language = language
  GameRoomTestLocalization.use_language(language)
  GameRoomTest::TemporaryDirectory.create('tournament-package-flow-') do |directory|
    messages, threads = [], []
    program = Object.new
    program.define_singleton_method(:data_path) { threads << Thread.current; directory }
    program.define_singleton_method(:server_tables) { raise 'Niedozwolona sieć' }
    args = T.args(program: program, alert: ->(text) { messages << text })
    drafts = G::DraftWorkspace.new(**args)
    data = Object.new.extend(TournamentPublicServiceSupport).draft
    data['name'] = 'Próba paczki — Żółć'
    date = (Date.today + 2).iso8601
    data['windows'] = [{'date' => date, 'start' => '12:00', 'end_date' => date, 'end' => '21:00'}]
    saved = drafts.persist(nil, data)
    assert(saved, "Nie zapisano szkicu: #{messages.inspect}")
    initial = snapshot_files(directory)
    initial_drafts = initial.select { |name, _| name.start_with?('tournament-drafts-') && name.end_with?('.json') }
    assert(initial_drafts.length == 1, 'Brak jednoznacznego pliku szkicu do porównania bajtów')
    alice, bob = 'Testowa Alicja', 'Testowy Bob'
    T.script(
      inspected('Local tournament tests') do |form|
        assert(form.fields.first.text.include?('RealOwner'), 'Organizer must default to signed-in account')
        press(form, 'Advanced local test tools')
        press(form, 'Change test participant')
        press(form, 'Publish a draft in local test')
        press(form, 'Change test participant')
        press(form, 'Browse local test tournaments')
        close(form)
      end,
      actor_step(alice),
      inspected('Choose a local draft') { |form| press(form, 'Publish'); close(form) },
      inspected('Publish draft in local test') do |form|
        field(form, 'Tournament rules').text = 'Jawny regulamin paczki. Żółć.'
        [Date.today + 1].zip(%w[closes]).each do |date, kind|
          [date.year, date.month, date.day, 12, 0].zip(%w[year month day hour minute]).each do |value, part|
            control = field(form, "Registration #{kind}: #{part}")
            control.index = control.options.index(format(part == 'year' ? '%04d' : '%02d', value)) || raise('Brak daty')
            control.trigger(:move)
          end
        end
        press(form, 'Publish in local test')
      end,
      actor_step(bob),
      inspected('Tournaments') do |form|
        list = form.fields.first
        assert(!list.options.empty?, "Published tournament missing: #{messages.inspect}")
        list.index = 0
        form.index = form.fields.index(list)
        list.trigger(:focus)
        form.accept_button.trigger(:press)
        close(form)
      end,
      inspected(/Próba paczki — Żółć/) do |form|
        assert(form.fields.first.header.include?('Próba paczki — Żółć'), 'Brak opublikowanego turnieju')
        before_join = snapshot_files(directory)
        form.accept_button&.trigger(:press)
        assert(snapshot_files(directory) == before_join, 'Enter w podglądzie wykonał zapis')
        field(form, 'Virtual player name (local test only)').set_text(bob)
        actions = form.fields.first
        actions.index = actions.options.index(caption('Join tournament')) || raise('Missing join action')
        actions.trigger(:select)
        assert(field(form, 'Status').text.split(/\r?\n\r?\n/).include?(caption('Registration confirmed.')), "Join niepotwierdzony: #{field(form, 'Status').text.inspect}")
        close(form)
      end
    ) { G::LocalTestHub.new(**args).run }
    workspace = G::LocalWorkspace.new(**args.reject { |key, _| key == :confirm }, actor: alice)
    snapshot = workspace.load
    assert(snapshot['announcements'].one? && snapshot['members'].map { |row| row['account'] }.sort == [alice.downcase, bob.downcase].sort, 'Missing publication, organizer or guest registration')
    assert(drafts.load.first == saved, 'Zmieniono szkic/roster')
    after_join = snapshot_files(directory)
    assert(initial_drafts.all? { |name, bytes| after_join[name] == bytes }, 'Zmieniono bajty szkicu')
    old_operation = workspace.operations.fetch(0)
    T.script(
      inspected('Local tournament tests') { |form| press(form, 'Advanced local test tools'); press(form, 'Change test participant'); press(form, 'Publish a draft in local test'); close(form) },
      actor_step(alice),
      inspected('Choose a local draft') { |form| press(form, 'Publish'); close(form) },
      inspected('Tournament operations') do |form|
        assert(field(form, 'Operation details').text.include?(old_operation['id']), 'Zmieniono ID operacji')
        close(form)
      end
    ) { G::LocalTestHub.new(**args).run }
    assert(snapshot_files(directory) == after_join, 'Ponowne wejście zmieniło dane lub ponowiło publikację')
    assert(threads.none? { |thread| thread == Thread.current }, 'data_path na UI')
    assert(messages.any? { |text| text.include?(caption('A publication operation for this draft revision already exists. Use Operations to check it; no new publication will be sent.')) }, 'Brak wyjaśnienia deduplikacji')
  end
  puts "PASS #{language}: binarne Hub → A publikuje → B dołącza → powrót A/Operations bez zapisu; szkic bez zmian"
end
puts "PASS #{records.length} msgidów z badanego artefaktu w compiled PL.mo; źródło: #{ARGV.first || 'binarne źródła repo, NIE paczka'}"
