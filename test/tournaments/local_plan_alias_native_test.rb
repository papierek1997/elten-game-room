require_relative '../support/temporary_directory'
require_relative '../support/tournament_ft2b1_entry'
require_relative '../../games/tic_tac_toe'
include GameRoomTest::Assertions
F = TournamentFT2B1
T = F::T
GameRoomLocalization.boot(settings: {'interface_language' => 'en', 'known_languages' => ['en']})

%i[team individual].each do |family|
  GameRoomTest::TemporaryDirectory.create('plan-alias') do |directory|
    individual = family == :individual
    registry = individual ? GameRoomGames::Registry.new([GameRoomGames::TicTacToe]) : F::REGISTRY
    fixture = F.fixture(directory, accept_plan: false, registry: registry,
      game_id: individual ? 'tic_tac_toe' : 'spades',
      names: individual ? %w[Alpha Beta] : F::NAMES, players_per_match: individual ? 2 : 4)
    program = fixture.fetch(:program)
    owner = T::LocalTestDialogs::Owner.new(-> { F::OWNER }, ->(message) { raise message })
    workspace = T::LocalWorkspace.new(program: program, registry: registry, user: owner.method(:current),
      actor: 'Organizator', alert: ->(message) { raise message }, clock: -> { fixture[:now] })
    preview_label = individual ? 'Preview individual plan' : 'Preview fixed-team plan'
    details_label = individual ? 'Individual plan preview' : 'Fixed-team plan preview'
    intents = []
    begin
      2.times do
        screen = (individual ? T::LocalIndividualPlanScreen : T::LocalFixedTeamPlanScreen).
          new(program: program, workspace: workspace, owner: owner)
        driver = TournamentNativeDriver.new
        driver.press('Tournament to plan', 13) do |form|
          F.field(form, 'Teams: two accounts per line, separated by a comma').set_text(
            "Anna, Ala\nBartek, Beata\nCelina, Cezary") unless individual
          form.index = form.fields.index(F.button(form, preview_label))
        end
        driver.press('Tournament to plan', 13) do |form|
          intents << screen.instance_variable_get(:@preview).fetch('intent_id')
          form.index = form.fields.index(F.button(form, 'Accept displayed plan'))
        end
        driver.press('Tournament to plan', 13) do |form|
          assert(screen.instance_variable_get(:@accepted), 'Preview was not accepted')
          F.field(form, 'Maximum simultaneous tables').set_text('2')
          form.index = form.fields.index(F.button(form, 'Set tournament table limit'))
        end
        driver.step('Tournament to plan', [27]) do |form|
          assert(F.field(form, details_label).text.include?('Automatic invitations enabled for up to 2 tables'),
            'Accepted plan alias could not configure its canonical plan')
        end
        screen.run
        driver.finish
      end
      assert_equal(2, intents.uniq.length)
      family_path = individual ? 'individual-v1' : 'fixed-teams-v1'
      plan_directory = individual ? fixture[:plans] : File.join(fixture[:plans], family_path)
      plans = JSON.parse(File.binread(File.join(plan_directory, 'sandbox-k02.json')))
      assert_equal(1, plans.fetch('records').length)
      assert_equal(2, plans.fetch('intents').length)
      canonical = plans['records'].first.dig('preview', 'intent_id')
      assert_equal([canonical], plans['intents'].map { |link| link['record_intent_id'] }.uniq)
      execution_path = individual ? 'execution-v1' : 'execution-ft2-v1'
      document = JSON.parse(File.binread(File.join(fixture[:plans], family_path, execution_path, 'state.json')))
      assert_equal([canonical], document.fetch('dispatch').fetch('policies').keys)
      assert_equal(2, document['dispatch']['policies'][canonical]['max_tables'])
    ensure
      program.finalize
      program.class.app_runtime.close
    end
  end
end
puts 'PASS native local plan aliases: two visits per family, one canonical plan/policy, two accepted intents and successful configuration'
