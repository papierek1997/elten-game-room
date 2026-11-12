require_relative '../support/tournament_local_workspace'
require_relative '../support/tournament_server_plan_table'
require_relative '../support/host_source'
require EltenTestHost.file('src/eltenlink/error.rb')
require_relative '../../lib/tournaments/server_trial_workspace'
include TournamentLocalWorkspaceSupport
include GameRoomTest::Assertions
T = GameRoomTournaments

[T::GroupAdvancement::AUTOMATIC, T::GroupAdvancement::COMPACT].product([false, true]).each do |policy, doubles|
  sandbox do |context|
    tables = T::LocalTestTables.new(directory: File.join(context.directory, 'server'),
      user: -> { context.user }, clock: -> { context.now })
    plans = TournamentServerPlanTableSupport::Table.new(user: -> { context.user })
    provider = Object.new
    provider.define_singleton_method(:fetch) { |name| name == 'tournament_plan_documents' ? plans : tables.fetch(name) }
    provider.define_singleton_method(:available?) { true }
    build = -> { T::ServerTrialWorkspace.new(program: context.program,
      registry: GameRoomGames::CATALOG, user: -> { context.user },
      alert: ->(message) { context.alerts << message }, clock: -> { context.now }, provider_factory: -> { provider }) }
    organizer = build.call
    game_id, per_match, limit, initially = doubles ? ['audio_ball', 4, 8, 6] : ['chess', 2, 4, 3]
    values = params(game_id, timezone: 'UTC')
    game = GameRoomGames::CATALOG.build(game_id)
    values[:draft] = values[:draft].merge('format' => 'groups_knockout',
      'players_per_match' => per_match,
      'game_options' => doubles ? game.normalize_options('team_size' => 2) : game.default_options,
      'group_advancement' => policy, 'group_count' => nil, 'places_per_group' => nil,
      'rematch' => false, 'knockout_rematch' => false, 'final_rematch' => false,
      'participant_limit' => limit, 'starts_at' => 0, 'deadline_at' => 0, 'windows' => [])
    published = organizer.publish(**values)
    assert_equal('confirmed', published && published['status'], context.alerts.inspect)
    id = published.dig('evidence', 'canonical_id')
    (1...initially).each do |index|
      context.user = "Person#{index}"
      assert_equal('confirmed', build.call.join(id)['status'])
    end
    context.user, context.now = 'RealOwner', 151
    row = organizer.load.fetch('announcements').first
    reference = {'author' => row['__insertion_user'].downcase, 'publication_key' => row['publication_key']}
    intent = 'actual-groups-start'
    generation = T::RegistrationProjection.publication_generation(row)
    assert_equal(nil, organizer.change_phase(tournament_id: id, action: 'start',
      intent_id: intent, expected_generation: generation))
    assert_equal(:invalid_group_configuration, organizer.last_error.code)
    assert_equal('The confirmed roster does not fit the group settings. Check the number of groups, players per match and qualifying places.',
      context.alerts.last, 'A group configuration refusal must explain the roster, not claim a connection failure')
    fresh = organizer.load
    assert(!T::TournamentTiming.started?(fresh['announcements'].first, context.now), 'Three units froze a valid advertised tournament')
    assert_equal(initially, fresh['members'].size)
    assert(!organizer.operations.any? { |record| record['kind'] == 'amendment' }, 'Rejected Start left a prepared or durable amendment')
    # Registrations remain usable after the refusal, and the same unsent Start
    # intent can later succeed under the unchanged publication generation.
    (initially...limit).each do |index|
      context.user = "Person#{index}"
      assert_equal('confirmed', build.call.join(id)['status'])
    end
    context.user, context.now = 'RealOwner', 152
    receipt = organizer.change_phase(tournament_id: id, action: 'start',
      intent_id: intent, expected_generation: generation)
    assert_equal('confirmed', receipt && receipt['status'], context.alerts.inspect)
    fresh = organizer.load
    assert(T::TournamentTiming.started?(fresh['announcements'].first, context.now))
    assert_equal(limit, fresh['members'].size)
    schedule = organizer.shared_schedule(publication_ref: reference)
    assert_equal('confirmed', schedule['storage'], schedule.inspect)
    assert_equal(2, schedule.fetch('candidate').fetch('matches').size)
    assert_equal(receipt['id'], organizer.change_phase(tournament_id: id, action: 'start',
      intent_id: intent, expected_generation: generation)['id'])
  end
end
puts 'PASS current workspace Start: legal maximum but unplannable actual roster stays open; singles/teams and both automatic group policies later start with the original intent'
