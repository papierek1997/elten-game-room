# encoding: UTF-8
require_relative '../support/binary_rules_load' if ARGV.first
require_relative '../support/tournament_phase_connection'
include TournamentPhaseConnectionSupport

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
$stdout.sync = true
directory = last_record = state = nil
copy = ->(value) { T::Publication::Data.copy(value,
  max_bytes: T::LocalFixedTeamExecutionStorage::MAX_BYTES,
  max_nodes: T::LocalFixedTeamExecutionStorage::MAX_NODES, max_depth: 24) }

with_fixture(game: 'tic_tac_toe', names: %w[Organizator Beta], rematch: false,
  group_advancement: T::GroupAdvancement::COMPACT,
  knockout_rematch: false, final_rematch: false, final_wins_to: 9) do |fixture|
  directory = fixture.directory
  backend = fixture.backend
  record = backend.accept(preview: backend.preview(publication_ref: fixture.reference,
    base_seats: fixture.base, intent_id: 'nine-stage-final'))
  root_intent = record['preview']['intent_id']
  fixture.now = record['evidence']['plan']['matches'].first['windows'].first['opens'] + 1

  9.times do |index|
    puts "phase capacity: legal stage #{index + 1}/9"
    intent = record['preview']['intent_id']
    with_dispatch(fixture, record, 'Organizator') do |dispatcher|
      assert_equal(3, dispatcher.configure(intent_id: intent, max_tables: 3))
      assert_equal(true, dispatcher.available(intent_id: intent, available: true)['available'])
    end
    with_individual_execution(fixture, record, 'Organizator') do |execution|
      status = execution.organizer_result_status
      result = execution.organizer_forfeit(operation_id: "no-show-#{index + 1}",
        winner: 'organizator', reason: 'Opponent did not appear',
        expected_revision: status[:revision])
      assert_equal(:confirmed, result[:state], result.inspect)
      if index < 7
        preview = execution.knockout_preview
        assert_equal(:confirmed, preview[:state], preview.inspect)
        assert_equal(index + 2, preview[:plan]['series']['attempt'])
        assert_equal(:confirmed, execution.knockout_accept(preview: preview[:preview])[:state])
        shown = execution.knockout_execution_preview
        assert_equal(:confirmed, shown[:state], shown.inspect)
        accepted = execution.knockout_execution_accept(preview: shown[:preview])
        assert_equal(:confirmed, accepted[:state], accepted.inspect)
        record = accepted[:record]
      elsif index == 8
        progress = execution.progress
        assert_equal('completed', progress['knockout_state'])
        assert_equal('organizator', progress['champion'])
      end
    end
    if index == 7
      # Exercise the actual overview's automatic eighth-to-ninth transition.
      with_phase_connection(fixture, 'Organizator') do |connection|
        advanced = connection.advance_tournament(publication_ref: fixture.reference, root_intents: [root_intent])
        assert_equal(1, advanced[:transitions].length)
        accepted = advanced[:transitions].first
        assert_equal(:confirmed, accepted[:state], accepted.inspect)
        record = accepted[:record]
        assert_equal(9, record.dig('preview', 'source', 'candidate', 'knockout', 'series', 'attempt'))
      end
    end
  end
  last_record = record
  state = dispatch_state(fixture)
  assert_equal(9, state['records'].length)
  assert_equal(9, state['dispatch']['policies'].length)
  assert_equal(9, state['dispatch']['availability'].length)
  assert_equal(9, state['executions'].values.count { |row| row['result'] })
  assert_equal([], state['native']['cores'], 'Forfeits before Start must not invent native games')

  # The proposal producer creates per-intent maps only for actually accepted
  # records. These are real produced records, not synthetic ninth records.
  proposal_view = copy.call(state)
  proposal_view['records'].each_key { |intent| T::LocalMatchProposals.rows(proposal_view, intent) }
  assert_equal(9, proposal_view.dig('dispatch', 'proposals').length)
  T::LocalDispatchContract.validate!(proposal_view)

  %w[policies availability proposals].each do |map|
    unknown = copy.call(proposal_view)
    entries = unknown['dispatch'][map]
    known = entries.keys.first
    entries['unknown-intent'] = entries.delete(known)
    assert_equal(9, entries.length)
    failure = assert_raises(T::Publication::Invalid) { T::LocalDispatchContract.validate!(unknown) }
    assert_equal(:sandbox_corrupt, failure.code, "Unknown #{map} key bypassed per-key validation")

    over = copy.call(proposal_view)
    over['dispatch'][map]['unknown-extra-intent'] = {}
    failure = assert_raises(T::Publication::Invalid) { T::LocalDispatchContract.validate!(over) }
    assert_equal(:sandbox_corrupt, failure.code, "Oversized #{map} map bypassed record-count bound")
  end

  # Synthetic counter-only denial, not an accepted plan or an attempted write.
  with_dispatch(fixture, record, 'Organizator') do |dispatcher|
    storage = dispatcher.instance_variable_get(:@storage)
    over = copy.call(state)
    seed = over['records'].values.first
    over['records'] = (T::LocalFixedTeamExecutionStorage::MAX_RECORDS + 1).times.to_h { |index| ["counter-#{index}", seed] }
    failure = assert_raises(T::Publication::Invalid) { storage.budget(over) }
    assert_equal(:sandbox_limit, failure.code)
  end
  assert_equal(64, T::LocalFixedTeamExecutionStorage::MAX_RECORDS)
  assert_equal(32, T::LocalExecutionPlanStorage::MAX_RECORDS)
  assert_equal(60, T::LocalDispatchContract::TTL)
end

# A new fixture/context reopens the same real documents after all first-scope
# resources have closed. Cold read must retain the ninth result and champion.
reopened = TournamentLocalExecutionPlanSupport::Fixture.new(directory, game: 'tic_tac_toe', reopen: true)
begin
  with_individual_execution(reopened, last_record, 'Organizator') do |execution|
    progress = execution.progress
    assert_equal('completed', progress['knockout_state'])
    assert_equal('organizator', progress['champion'])
  end
  assert_equal(state, dispatch_state(reopened), 'Cold read mutated the durable execution aggregate')
ensure
  reopened.close
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
puts "PASS nine legal series stages, automatic ninth dispatch, cold reopen and bounded canonical intent maps (#{elapsed.round(3)}s)"
