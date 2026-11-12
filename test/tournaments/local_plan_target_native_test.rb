require_relative '../support/temporary_directory'
require_relative '../support/tournament_ft2b1_entry'
require_relative '../../games/tic_tac_toe'
include GameRoomTest::Assertions
F = TournamentFT2B1
T = F::T
GameRoomLocalization.boot(settings: {'interface_language' => 'en', 'known_languages' => ['en']})

# Lose only the reply AFTER the real atomic replacement. The production
# backend/workspace, not the UI fixture, classifies the result as uncertain.
T::LocalExecutionPlanStorage.prepend(Module.new do
  def write(document)
    value = super
    if $local_plan_target_lost_reply
      $local_plan_target_lost_reply = false
      raise IOError, 'Lost local acceptance reply after durable replacement'
    end
    value
  end
end)

%i[team individual].product([false, true]).each do |family, lost_reply|
  GameRoomTest::TemporaryDirectory.create('plan-target') do |directory|
    individual = family == :individual
    registry = individual ? GameRoomGames::Registry.new([GameRoomGames::TicTacToe]) : F::REGISTRY
    names = individual ? %w[Alpha Beta] : F::NAMES
    game_id, count = individual ? ['tic_tac_toe', 2] : ['spades', 4]
    fixture = F.fixture(directory, accept_plan: false, registry: registry, game_id: game_id,
      names: names, players_per_match: count)
    program = fixture.fetch(:program)
    actor, now = 'Organizator', 150
    tables = T::LocalTestTables.new(directory: File.join(fixture[:sandbox], 'tables'), user: -> { actor }, clock: -> { now })
    journal = -> { T::OperationJournal.new(directory: File.join(fixture[:sandbox], 'journals'),
      owner: actor, backend_identity: tables.backend_identity) }
    gateway = T::TablesGateway.new(server_tables: tables, user: -> { actor }, operation_error_classes: [T::LocalTestTables::Error])
    service = -> { T::PublicService.new(gateway: gateway, journal: journal.call, registry: registry,
      user: -> { actor }, backend_identity: tables.backend_identity, clock: -> { now }) }
    draft = {'name' => 'Second actual local publication', 'game_id' => game_id,
      'game_options' => registry.build(game_id).normalize_options(individual ? {} : {'team_size' => 2}),
      'format' => 'round_robin', 'rematch' => true, 'players_per_match' => count,
      'pairing' => 'all_combinations', 'participants' => [], 'windows' => [
        {'date' => '2026-10-15', 'start' => '12:00', 'end_date' => '2026-10-15', 'end' => '21:00'}]}
    second = service.call.publish(draft: draft, intent_id: 'second-local-target', rules: 'Local target regression.',
      registration_opens_at: 100, registration_closes_at: 200, timezone: 'local_test:system')
    assert_equal('confirmed', second['status'])
    row = service.call.list['announcements'].find { |item| item['publication_key'] == second.dig('values', 'publication_key') }
    names.each { |name| actor = name; assert_equal('confirmed', service.call.join(tournament_id: row['__id'])['status']) }
    actor, now = 'Organizator', 201
    owner = T::LocalTestDialogs::Owner.new(-> { F::OWNER }, ->(message) { raise message })
    workspace = T::LocalWorkspace.new(program: program, registry: registry, user: owner.method(:current),
      actor: actor, alert: ->(message) { raise message }, clock: -> { now })
    route = individual ? :individual_plan : :fixed_team_plan
    original = workspace.method(route)
    operations = []
    workspace.define_singleton_method(route) do |**args|
      operations << [args.fetch(:action), T::Publication::Data.copy(args.fetch(:input))]
      original.call(**args)
    end
    screen = (individual ? T::LocalIndividualPlanScreen : T::LocalFixedTeamPlanScreen).
      new(program: program, workspace: workspace, owner: owner)
    preview_label = individual ? 'Preview individual plan' : 'Preview fixed-team plan'
    details_label = individual ? 'Individual plan preview' : 'Fixed-team plan preview'
    select = lambda do |form, key, move: true|
      list = F.field(form, 'Tournament to plan')
      list.index = screen.instance_variable_get(:@rows).index { |item| item['publication_key'] == key }
      list.trigger(:move) if move
    end
    driver = TournamentNativeDriver.new
    first_intent = second_intent = nil
    begin
      driver.press('Tournament to plan', 13) do |form|
        select.call(form, fixture[:reference]['publication_key'])
        F.field(form, 'Teams: two accounts per line, separated by a comma').set_text("Anna, Ala\nBartek, Beata\nCelina, Cezary") unless individual
        form.index = form.fields.index(F.button(form, preview_label))
      end
      driver.press('Tournament to plan', 13) do |form|
        first_intent = screen.instance_variable_get(:@preview).fetch('intent_id')
        $local_plan_target_lost_reply = lost_reply
        form.index = form.fields.index(F.button(form, 'Accept displayed plan'))
      end
      driver.press('Tournament to plan', 13) do |form|
        assert(screen.instance_variable_get(lost_reply ? :@uncertain : :@accepted), 'Actual acceptance did not reach the expected state')
        select.call(form, second.dig('values', 'publication_key'))
        if lost_reply
          assert_equal(first_intent, screen.instance_variable_get(:@preview)&.fetch('intent_id'), 'Changing selection erased unresolved intent')
          assert(screen.instance_variable_get(:@shown_input), 'Changing selection erased unresolved shown input')
        end
        F.field(form, 'Maximum simultaneous tables').set_text('2')
        form.index = form.fields.index(F.button(form, 'Set tournament table limit'))
      end
      driver.press('Tournament to plan', 13) do |form|
        assert(operations.none? { |action, _| action == :dispatch_configure }, 'Visible B configured accepted A')
        if lost_reply
          F.button(form, 'Check plan acceptance').press
          assert_equal(first_intent, operations.last[1].fetch('intent_id'), 'Readback changed original uncertain target')
          assert(!screen.instance_variable_get(:@uncertain), 'Confirmed original receipt stayed uncertain')
        end
        form.index = form.fields.index(F.button(form, preview_label))
      end
      driver.press('Tournament to plan', 13) do |form|
        shown = screen.instance_variable_get(:@preview)
        assert_equal(second.dig('values', 'publication_key'), shown.dig('source', 'candidate', 'publication_ref', 'publication_key'))
        second_intent = shown.fetch('intent_id')
        assert(!screen.instance_variable_get(:@accepted), 'New preview inherited old accepted flag')
        form.index = form.fields.index(F.button(form, 'Accept displayed plan'))
      end
      driver.press('Tournament to plan', 13) do |form|
        assert(screen.instance_variable_get(:@accepted), 'B was not accepted')
        form.index = form.fields.index(F.button(form, 'Set tournament table limit'))
      end
      driver.step('Tournament to plan', [27]) do |form|
        calls = operations.select { |action, _| action == :dispatch_configure }
        assert_equal([second_intent], calls.map { |_, input| input.fetch('intent_id') })
        assert(F.field(form, details_label).text.include?('2'), 'B table limit was not confirmed')
        # A selector drift without its move event and edits after acceptance
        # both have to stop at the same input guard, before workspace I/O.
        select.call(form, fixture[:reference]['publication_key'], move: false)
        F.button(form, 'Set tournament table limit').press
        select.call(form, second.dig('values', 'publication_key'), move: false)
        field = individual ? F.field(form, 'Seats: one match per line, accounts separated by commas') :
          F.field(form, 'Teams: two accounts per line, separated by a comma')
        field.set_text(field.text.split(',').reverse.join(','))
        F.button(form, 'Set tournament table limit').press
        assert_equal(1, operations.count { |action, _| action == :dispatch_configure }, 'Changed displayed input configured stale accepted intent')
        F.button(form, preview_label).press
        assert(!screen.instance_variable_get(:@accepted), 'Changed same-publication preview retained old acceptance')
        assert(screen.instance_variable_get(:@preview), 'Changed valid input could not produce a fresh preview')
      end
      screen.run
      driver.finish
    ensure
      $local_plan_target_lost_reply = false
      program.finalize
      program.class.app_runtime.close
    end
  end
end
puts 'PASS native local plan targets: teams/individual, two actual publications, confirmed/lost-reply selection changes, original readback and zero stale configuration writes'
