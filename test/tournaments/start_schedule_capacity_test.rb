require_relative '../support/tournament_public_service'
require_relative '../../lib/tournaments/public_service'
include TournamentPublicServiceSupport
include GameRoomTest::Assertions

# These are complete PublicService/RegistrationProjection/planner paths with
# isolated tables and journals, not fabricated closed-publication projections.
[
  ['chess', 0, 2, 23, false, 253],
  ['chess', 0, 2, 24, false, nil],
  ['audio_ball', 2, 4, 46, false, 253],
  ['audio_ball', 2, 4, 48, false, nil],
  ['audio_ball', 2, 4, 32, true, 240],
  ['audio_ball', 2, 4, 34, true, nil],
  ['spades', 0, 3, 12, false, 220],
  ['spades', 0, 3, 13, false, nil]
].each do |game_id, team_size, per_match, count, rematch, expected_matches|
  sandbox do |context|
    context.actor = 'Owner'
    game = GameRoomGames::CATALOG.build(game_id)
    options = game.default_options
    options = options.merge('team_size' => team_size) if game_id != 'chess'
    candidate = draft(game_id).merge('game_options' => options,
      'players_per_match' => per_match, 'participant_limit' => count,
      'participants' => [], 'windows' => [], 'starts_at' => 0,
      'deadline_at' => 0, 'rematch' => rematch)
    service = context.service(journal: context.reopen_journal)
    publication = service.publish(draft: candidate, intent_id: 'capacity-publication',
      rules: 'Capacity regression', registration_opens_at: 100,
      registration_closes_at: 0, timezone: 'UTC')
    assert_equal('confirmed', publication['status'])
    row = service.list.fetch('announcements').first
    (['Owner'] + (1...count).map { |index| "Person#{index}" }).each_with_index do |name, index|
      context.actor = name
      context.provider.insert_row(REG, T::RegistrationProjection.join_values(
        tournament_id: row['__id'], operation_key: "capacity-join-#{index}"))
    end
    context.actor = 'Owner'
    service = context.service(journal: context.reopen_journal)
    row = service.list.fetch('announcements').first
    reference = {'author' => 'owner', 'publication_key' => row['publication_key']}
    generation = T::RegistrationProjection.publication_generation(row)
    # Previewing/entering still requires closed registration by default.
    error = assert_raises(T::Publication::Invalid) { service.server_schedule_source(publication_ref: reference) }
    assert_equal(:registration_open, error.code)
    operation = -> { service.change_phase(tournament_id: row['__id'], action: 'start',
      intent_id: 'capacity-start', expected_generation: generation) }
    if expected_matches
      receipt = operation.call
      assert_equal('confirmed', receipt['status'])
      assert_equal(receipt['id'], operation.call['id'], 'Repeated Start must adopt the confirmed receipt')
      fresh = service.list
      assert(T::TournamentTiming.started?(fresh['announcements'].first, context.now))
      assert_equal(count, fresh.fetch('members').size, 'Same-second joins disappeared during Start')
      planned = service.server_schedule_source(publication_ref: reference).fetch('candidate')
      assert_equal(expected_matches, planned.fetch('matches').size)
      assert_equal(false, planned.fetch('start_allowed'), 'Pure planning conferred execution authority')
      assert_equal(false, planned.fetch('dispatch_allowed'))
    else
      error = assert_raises(T::Publication::Invalid, &operation)
      assert_equal(:server_match_capacity, error.code)
      fresh = service.list
      assert(!T::TournamentTiming.started?(fresh['announcements'].first, context.now), 'Rejected Start froze the tournament')
      assert_equal(count, fresh.fetch('members').size)
      assert(!context.inserts.any? { |table, values| table == REG && values['kind'] == 'amendment' },
        'An impossible plan must be rejected before its durable Start amendment')
      assert(!service.instance_variable_get(:@journal).list.any? { |record| record['intent_id'] == 'capacity-start' },
        'An unsent invalid Start must not strand a prepared intent')
    end
  end
end
puts 'PASS Start preflight: actual individual/team/multiplayer/rematch planner limits, original same-second joins, no frozen invalid tournament, strict normal source and repeated receipt'
