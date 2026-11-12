# encoding: UTF-8
# Izolowane dzieci Ruby; require definiuje pomocniki, nie uruchamia scenariusza.
require 'json'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'
require 'timeout'
require 'digest'
require 'base64'
require 'date'
require 'time'
require_relative 'assertions'
require_relative 'temporary_directory'

module TournamentRestartProcess
  extend GameRoomTest::Assertions
  OWNER = 'RealOwner'.freeze
  ACTOR_A = 'Testowa Alicja'.freeze
  ACTOR_B = 'Testowy Bob'.freeze
  HUB = 'Local tournament tests'.freeze
  DRAFTS = 'Choose a local draft'.freeze
  EDITOR = 'Publish draft in local test'.freeze
  OPERATIONS = 'Tournament operations'.freeze
  CHILD_SECONDS = 15
  module_function

  # Każdy dostęp do danych fixture poprzedza kontrola zasięgu. Nie korzystamy
  # z domyślnego katalogu tymczasowego systemu ani z profilu użytkownika.
  def temporary_base
    File.realpath(GameRoomTest::TemporaryDirectory.parent)
  end

  def safe_path(path)
    base = temporary_base.tr('\\', '/')
    expanded = File.expand_path(path).tr('\\', '/')
    compare = File::ALT_SEPARATOR ? expanded.downcase : expanded
    prefix = File::ALT_SEPARATOR ? base.downcase : base
    assert(compare.start_with?(prefix + '/'), "Katalog fixture poza własnym katalogiem testów: #{expanded}")
    cursor = expanded
    until cursor.casecmp?(base)
      assert(!File.symlink?(cursor), "Dowiązanie w fixture: #{cursor}")
      cursor = File.dirname(cursor)
    end
    expanded
  end

  def files(directory)
    directory = safe_path(directory)
    Dir.glob('**/*', base: directory).sort.each_with_object({}) do |relative, result|
      path = safe_path(File.join(directory, relative))
      next unless File.file?(path)
      bytes = File.binread(path)
      result[relative] = {'base64' => Base64.strict_encode64(bytes),
        'sha256' => Digest::SHA256.hexdigest(bytes), 'size' => bytes.bytesize}
    end
  end

  def subset(snapshot, pattern)
    snapshot.select { |name, _| pattern.match?(name) }
  end

  def verify_snapshot(snapshot, joined:)
    assert(snapshot.fetch('announcements').length == 1, 'Brak pojedynczej publikacji aktora A po restarcie')
    publication = snapshot.fetch('announcements').first
    assert(publication.fetch('__insertion_user') == ACTOR_A, 'Publikację przypisano właścicielowi zamiast aktorowi A')
    members = snapshot.fetch('members')
    if joined
      assert(members.map { |row| row.fetch('account') }.sort == [ACTOR_A.downcase, ACTOR_B.downcase].sort &&
        members.all? { |row| row.fetch('tournament_id') == publication.fetch('__id') }, 'Brak zapisu organizatora lub aktora B po restarcie')
    else
      assert(members.map { |row| row.fetch('account') } == [ACTOR_A.downcase], 'Publikacja powinna zapisać tylko organizatora')
    end
  end

  def run_child(phase, directory, log_directory)
    directory, log_directory = safe_path(directory), safe_path(log_directory)
    report_path = safe_path(File.join(log_directory, phase + '.json'))
    output_path = safe_path(File.join(log_directory, phase + '.log'))
    command = [RbConfig.ruby, File.expand_path(__FILE__), phase, directory, report_path]
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    pid = nil
    status = nil
    begin
      File.open(output_path, 'wb') do |output|
        pid = Process.spawn(*command, out: output, err: output)
        Timeout.timeout(CHILD_SECONDS) { _, status = Process.wait2(pid) }
      end
    ensure
      if pid && !status
        begin
          Process.kill('KILL', pid)
        rescue Errno::ESRCH
          nil
        end
        Process.wait(pid) rescue Errno::ECHILD
      end
      puts "CHILD_LOG #{phase}\n#{File.binread(output_path).force_encoding(Encoding::UTF_8)}" if File.file?(output_path)
    end
    reaped = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert(status.success?, "Proces #{phase}/PID #{pid} zakończył się #{status.exitstatus}")
    report = JSON.parse(File.binread(report_path))
    assert(report.fetch('pid') == pid && pid != Process.pid, 'Raport nie pochodzi z uruchomionego dziecka')
    report['lifecycle'] = {'command' => command, 'spawn_pid' => pid, 'parent_pid' => Process.pid,
      'started_monotonic' => started, 'reaped_monotonic' => reaped, 'exit_status' => status.exitstatus}
    puts 'RESTART_REPORT ' + JSON.generate(report, ascii_only: true)
    report
  end

  # Wyłącznie istniejące odcięte granice urządzeń; prawdziwe kontrolki i Tasks.
  def boot
    require_relative 'tournament_native'
    require_relative 'native_tasks'
    require_relative 'tournament_local_hub'
    require_relative 'tournament_public_service'
    require_relative 'localization'
    require_relative '../../lib/tournaments/hub'
    require_relative '../../lib/tournaments/local_workspace'
    require_relative '../../lib/tournaments/draft_workspace'
    require_relative '../../lib/tournaments/local_test_hub'
    runtime = GameRoomTestLocalization.runtime('en', files: {}, reader: ->(*) { raise 'Niedozwolony odczyt MO' })
    GameRoomLocalization.boot(runtime: runtime, host_language: 'en', known_languages: ['en'])
    assert(runtime.settings.fetch('known_languages') == ['en'] && GameRoomLocalization.primary_language == 'en', 'Nie uruchomiono jawnego EN')
    EltenAPI.module_eval { define_method(:loop_update) { Thread.pass } }
    GameRoomTournaments::LocalTestTables.prepend(InsertBoundary)
    runtime
  end

  # Fault injection identycznej granicy jak w native_local_test_hub_test:
  # super naprawdę zapisuje JSON; dopiero potem tracimy potwierdzenie.
  module InsertBoundary
    def insert_row(*arguments)
      probe = TournamentRestartProcess.probe
      probe.fetch(:inserts) << {'table' => arguments.first, 'on_ui' => Thread.current == probe.fetch(:ui)}
      result = super
      if probe[:fail_after_insert]
        probe[:fail_after_insert] = false
        raise GameRoomTournaments::LocalTestTables::Error, :store_io_error
      end
      result
    end
  end

  def probe
    @probe
  end

  def action(driver, header, label)
    driver.step(header, [13]) do |form|
      form.index = form.fields.index(TournamentLocalHubTest.button(form, label))
    end
  end

  def choose_actor(driver, actor)
    driver.open_test_participant
    driver.step('Choose a test participant', [13]) do |form|
      field = TournamentLocalHubTest.field(form, 'Test participant name')
      assert(field.text.empty?, 'Tożsamość aktora została wybrana niejawnie')
      field.set_text(actor)
      form.index = form.fields.index(TournamentLocalHubTest.button(form, 'Use test participant'))
    end
    driver.step(HUB) do |form|
      assert(form.fields.first.text.include?("Test actor: #{actor}"), 'Hub nie pokazuje jawnego aktora')
    end
  end

  def fill_editor(form)
    now = Time.now
    date = Date.new(now.year, now.month, now.day) + 1
    TournamentLocalHubTest.field(form, 'Tournament rules').set_text('Jawny regulamin próby restartu. Graj uczciwie.')
    assert(TournamentLocalHubTest.field(form, 'Registration').text == 'Registration opens when you publish.', 'Brak informacji o automatycznym otwarciu')
    assert(form.fields.none? { |field| field.respond_to?(:header) && field.header.to_s.start_with?('Registration opens:') }, 'Pozostawiono wybieraki otwarcia')
    deadline = TournamentLocalHubTest.field(form, 'Registration deadline')
    deadline.index = deadline.options.index('Specific date and time') || raise('Brak konkretnego terminu')
    deadline.trigger(:move)
    [date.year, date.month, date.day, 12, 0].zip(%w[year month day hour minute]).each do |value, part|
      field = TournamentLocalHubTest.field(form, "Registration closes: #{part}")
      field.index = field.options.index(format(part == 'year' ? '%04d' : '%02d', value)) || raise('Brak daty w kontrolce')
      field.trigger(:move)
    end
    {'closes' => {'date' => date.iso8601, 'time' => '12:00',
      'timestamp' => GameRoomTournaments::LocalRegistrationTime.convert(date.iso8601, '12:00')}}
  end

  # Obserwacja dokładnego natywnego trigger(:press), bez podmiany czasu/save.
  # Przekroczenie sekundy od widocznego edytora wykrywa zapamiętany stary czas.
  def observe_publish(button, report)
    observed = Time.now.to_i
    report['editor_observed_at'] = observed
    Timeout.timeout(2) { sleep(0.01) until Time.now.to_i > observed }
    original = button.method(:trigger)
    button.define_singleton_method(:trigger) do |event, *arguments|
      next original.call(event, *arguments) unless event == :press
      raise 'Powtórne wywołanie Publish' if report.key?('publish_button')
      before = Time.now
      bounds = report['publish_button'] = {'before' => before.to_i, 'before_utc' => before.utc.iso8601(9)}
      begin
        original.call(event, *arguments)
      ensure
        after = Time.now
        bounds['after'], bounds['after_utc'] = after.to_i, after.utc.iso8601(9)
      end
    end
  end

  def check_details(form, joined:)
    text = TournamentLocalHubTest.field(form, 'Information and rules').text
    assert(text.include?("Organizer: #{ACTOR_A}"), 'Podgląd pomylił organizatora')
    assert(text.include?("Accepted participants: #{joined ? 2 : 1}"), 'Błędna liczba zapisów w podglądzie')
    assert(text.include?(ACTOR_B), 'Podgląd nie widzi zapisu B') if joined
  end

  def run_phase(phase, directory)
    directory = safe_path(directory)
    assert(Dir.exist?(directory), 'Brak izolowanego katalogu fixture')
    now = Time.now
    runtime = boot
    actor = phase == 'join' ? ACTOR_B : ACTOR_A
    owner = phase == 'other_owner' ? 'OtherOwner' : OWNER
    @probe = {inserts: [], ui: Thread.current, fail_after_insert: phase == 'uncertain_publish'}
    messages, io_threads = [], []
    program = Object.new
    program.define_singleton_method(:data_path) { io_threads << Thread.current; TournamentRestartProcess.safe_path(directory) }
    program.define_singleton_method(:server_tables) { raise 'Niedozwolona sieć' }
    args = TournamentLocalHubTest.args(program: program, user: -> { owner }, alert: ->(message) { messages << message })
    workspace = GameRoomTournaments::LocalWorkspace.new(**args.reject { |key, _| key == :confirm }, actor: actor)
    drafts = GameRoomTournaments::DraftWorkspace.new(**args)
    report = {'phase' => phase, 'pid' => Process.pid, 'owner' => owner, 'actor' => actor,
      'ruby' => RUBY_DESCRIPTION, 'ruby_executable' => RbConfig.ruby, 'json_version' => JSON::VERSION,
      'language' => {'primary' => GameRoomLocalization.primary_language, 'known' => ['en'],
        'source' => 'angielskie msgid źródeł; files={}; reader odmawia MO'},
      'clock' => {'source' => 'Time.now lokalnego procesu; bez podmiany Time/TZ', 'epoch' => now.to_i,
        'local' => now.iso8601, 'utc_offset' => now.utc_offset}, 'before' => files(directory)}
    creating = %w[publish uncertain_publish].include?(phase)
    if creating
      fixture = Object.new.extend(TournamentPublicServiceSupport).draft
      date = (Date.new(now.year, now.month, now.day) + 7).iso8601
      fixture['windows'] = [{'date' => date, 'start' => '12:00', 'end_date' => date, 'end' => '21:00'}]
      fixture['participants'] = ['Lokalny roster A', 'Lokalny roster B']
      row = drafts.persist(nil, fixture)
      assert(row, "Nie udało się przygotować legalnego szkicu: #{messages.inspect}")
      report['draft_prepared'] = files(directory)
    else
      row = drafts.load.fetch(0) unless phase == 'other_owner'
    end
    driver = TournamentNativeDriver.new
    choose_actor(driver, actor)
    if creating
      action(driver, HUB, 'Publish a draft in local test')
      action(driver, DRAFTS, 'Publish')
      driver.step(EDITOR, [13]) do |form|
        assert(probe.fetch(:inserts).empty?, 'Sam wybór szkicu wykonał insert')
        report['registration_dates'] = fill_editor(form)
        button = TournamentLocalHubTest.button(form, 'Publish in local test')
        observe_publish(button, report)
        form.index = form.fields.index(button)
      end
      if phase == 'uncertain_publish'
        driver.step(EDITOR, [27]) do |form|
          assert(TournamentLocalHubTest.field(form, 'Status').text.include?('not confirmed'), 'Niepewny append udaje potwierdzenie')
        end
      end
      driver.step(DRAFTS, [27])
    elsif phase == 'join' || phase == 'return'
      action(driver, HUB, 'Browse local test tournaments')
      driver.step('Tournaments', [13]) do |form|
        list = TournamentLocalHubTest.field(form, 'Tournaments')
        assert(list.options.length == 1, 'Brak publikacji A na liście świeżego procesu')
        form.index = form.fields.index(list)
      end
      preview_header = /\APróba chess —/
      driver.step(preview_header)
      driver.step(preview_header, [13]) do |form|
        list = form.fields.first
        list.index = list.options.index('Information and rules') || raise('Missing rules action')
        form.index = 0
      end
      driver.step('Information and rules', [27]) { |form| check_details(form, joined: phase == 'return') }
      if phase == 'join'
        driver.step(preview_header)
        driver.step(preview_header, [13]) do |form|
          report['before_join'] = files(directory)
          assert(probe.fetch(:inserts).empty? && report['before_join'] == report.fetch('before'), 'Lista i podgląd zapisały uczestnika bez jawnego Join')
          TournamentLocalHubTest.field(form, 'Virtual player name (local test only)').set_text(actor)
          list = form.fields.first
          list.index = list.options.index('Join tournament') || raise('Missing join action')
          form.index = 0
        end
        driver.step(preview_header)
        driver.step(preview_header, [13]) do |form|
          list = form.fields.first
          list.index = list.options.index('Information and rules') || raise('Missing rules after join')
          form.index = 0
        end
        driver.step('Information and rules', [27]) { |form| check_details(form, joined: true) }
      end
      driver.step(preview_header)
      driver.step(preview_header, [27])
      driver.step('Tournaments')
      driver.step('Tournaments', [27])
    elsif phase != 'reconcile' && phase != 'other_owner'
      raise ArgumentError, "Nieznana faza #{phase}"
    end
    if %w[return reconcile].include?(phase)
      action(driver, HUB, 'Publish a draft in local test')
      action(driver, DRAFTS, 'Publish')
      driver.step(OPERATIONS) do |form|
        operations = workspace.operations.select { |row| row['kind'] == 'publication' }
        assert(operations.one?, 'Brak jednej istniejącej operacji tej rewizji')
        operation = operations.first
        assert(operation.fetch('intent_id') == "draft:#{row.fetch('id')}:revision:#{row.fetch('revision')}", 'Zmieniono revision intent')
        text = TournamentLocalHubTest.field(form, 'Operation details').text
        assert(text.include?(operation.fetch('id')), 'Operations pokazuje inne operation ID')
        expected = phase == 'reconcile' ? 'attempted' : 'confirmed'
        assert(operation.fetch('status') == expected && text.include?(expected), 'Reopen nie zachował stanu operacji')
        report['before_check'] = {'operations' => operations, 'files' => files(directory)}
        assert(probe.fetch(:inserts).empty?, 'Reopen ponowił wysłanie')
      end
      if phase == 'reconcile'
        action(driver, OPERATIONS, 'Check selected operation')
        driver.step(OPERATIONS) do |form|
          assert(TournamentLocalHubTest.field(form, 'Operation details').text.include?('; confirmed'), 'Jawne Check nie potwierdziło operacji w UI')
        end
      end
      driver.step(OPERATIONS, [27])
      driver.step(DRAFTS, [27])
    elsif phase == 'other_owner'
      action(driver, HUB, 'Browse local test tournaments')
      driver.step('Tournaments', [27]) { |form| assert(form.fields.first.options.empty?, 'Inny owner widzi publikację') }
      action(driver, HUB, 'Operations')
      driver.step(OPERATIONS, [27]) { |form| assert(form.fields.first.options.empty?, 'Inny owner widzi dziennik aktora A') }
    end
    driver.step(HUB, [27])
    GameRoomTournaments::LocalTestHub.new(**args).run
    driver.finish
    report['snapshot'] = workspace.load
    report['operations'] = workspace.operations
    report['draft_rows'] = drafts.load
    report['after'] = files(directory)
    report['inserts'] = probe.fetch(:inserts)
    report['messages'] = messages
    report['forms'] = driver.forms.map { |form| form.fields.first.header }
    report['speech_count'], report['braille_count'] = SpeechOutput.calls.length, NVDA.calls.length
    report['language']['catalog_reads'] = runtime.catalog_reads
    assert(runtime.catalog_reads.empty?, 'Próba EN odczytała katalog MO')
    assert(!io_threads.empty? && io_threads.none? { |thread| thread == Thread.current }, 'data_path poza natywnym workerem Tasks')
    assert(report['inserts'].none? { |call| call.fetch('on_ui') }, 'Insert na wątku UI')
    assert(report['speech_count'].positive? && report['braille_count'].positive?, 'Nie użyto pamięciowej mowy/brajla')
    if phase == 'uncertain_publish'
      assert(report.fetch('snapshot').fetch('members').empty?, 'Unconfirmed publication must not enroll its organizer yet')
    elsif phase != 'other_owner'
      verify_snapshot(report.fetch('snapshot'), joined: %w[join return].include?(phase))
    end
    report
  ensure
    runtime&.close
  end

  def cli(argv)
    phase, directory, report_path = argv
    raise ArgumentError, 'Faza, katalog danych i raport są wymagane' unless argv.length == 3
    directory, report_path = safe_path(directory), safe_path(report_path)
    result = run_phase(phase, directory)
    File.binwrite(report_path, JSON.pretty_generate(result))
    puts "PASS proces Ruby #{phase}; PID=#{Process.pid}"
  end
end

TournamentRestartProcess.cli(ARGV) if $PROGRAM_NAME == __FILE__
