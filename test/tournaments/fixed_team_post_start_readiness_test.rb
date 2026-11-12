require_relative '../support/tournament_moves_fixture'
include GameRoomTest::Assertions
F = TournamentFT2B1
T = F::T

def state_for(fixture)
  path = File.join(fixture.fetch(:plans), 'fixed-teams-v1', 'execution-ft2-v1', 'state.json')
  JSON.parse(File.binread(path))
end

def close_fixture(fixture)
  fixture.fetch(:program).finalize
  fixture.fetch(:program).class.app_runtime.close
end

def prepare_entered_fixture
  fixture = F.fixture(GameRoomTest::TemporaryDirectory.create('started-readiness-'))
  record = fixture.fetch(:record)
  %w[Ala Anna Bartek Beata].each do |actor|
    F.with_execution(fixture, actor) do |execution|
      F.select_execution(execution, record)
      assert_equal(:confirmed, execution.declare(availability: 'ready', expected_revision: 0)[:state])
    end
  end
  deadline = record.dig('evidence', 'plan', 'matches').first.fetch('windows').first.fetch('closes') - 60
  F.with_execution(fixture, 'Ala', expires_at: deadline) do |execution|
    F.select_execution(execution, record)
    assert_equal(:bound, execution.request_match[:state])
  end
  %w[Ala Anna Bartek Beata].each do |actor|
    F.with_execution(fixture, actor) do |execution|
      F.select_execution(execution, record)
      binding = execution.admission(action: :admission_status).dig(:status, 'binding')
      consent = execution.admission(action: :consent, binding_digest: T::CoordinationContract.digest(binding))[:effect]
      assert_equal(:confirmed, execution.admission(action: :enter, consent_id: consent.fetch('id'))[:state])
    end
  end
  fixture
end

%w[ready withdrawn].each do |availability|
  fixture = TournamentMovesFixture.build
  begin
    before = state_for(fixture)
    F.with_execution(fixture, 'Ala') do |execution|
      F.select_execution(execution, fixture.fetch(:record))
      port = execution.instance_variable_get(:@port)
      assert_equal('started', port.snapshot(scope: port.scope, match_ref: port.match_ref).fetch('phase'))
      error = assert_raises(T::ReadinessContract::Blocked) { port.negotiate(scope: port.scope, required: T::ReadinessContract::WRITE) }
      assert_equal(:already_started, error.code)
      assert_equal(:already_started, execution.declare(availability: availability, expected_revision: 1)[:reason])
      # Repeated original ready still reads its old receipt after Start.
      original = execution.declare(availability: 'ready', expected_revision: 0)
      assert_equal(:confirmed, original[:state])
      assert_equal(:confirmed, execution.reconcile_readiness(operation_id: original.fetch(:operation_id))[:state])
    end
    assert_equal(before, state_for(fixture), 'Post-Start readiness changed epoch, grant, roster or history')
    F.with_execution(fixture, 'Beata') do |execution|
      F.select_execution(execution, fixture.fetch(:record))
      status = execution.local_game(action: :local_game_status).fetch(:status)
      assert_equal(:confirmed, execution.local_game(action: :local_game_move, operation_id: 'legal-next-deal',
        revision: status.fetch('revision'), move_selection: status.fetch('actions').first)[:state])
    end
  ensure
    close_fixture(fixture)
  end
end

# Start really commits after the readiness snapshot but before its store. The
# atomic store must return a recognisable conflict without invalidating play.
fixture = prepare_entered_fixture
begin
  record = fixture.fetch(:record)
  F.with_execution(fixture, 'Ala') do |execution|
    F.select_execution(execution, record)
    port = execution.instance_variable_get(:@port)
    binding = execution.admission(action: :admission_status).dig(:status, 'binding')
    original_snapshot = port.method(:snapshot)
    started = false
    at_start = nil
    port.define_singleton_method(:snapshot) do |**arguments|
      observed = original_snapshot.call(**arguments)
      unless started
        started = true
        assert_equal('not_started', observed.fetch('phase'))
        assert_equal(:confirmed, execution.local_game(action: :start_local_game,
          binding_digest: T::CoordinationContract.digest(binding))[:state])
        at_start = state_for(fixture)
      end
      observed
    end
    answer = execution.declare(availability: 'withdrawn', expected_revision: 1)
    assert_equal(:conflict, answer[:state])
    assert_equal('already_started', answer.dig(:receipt, 'reason'))
    after = state_for(fixture)
    assert_equal(at_start.reject { |key, _| key == 'readiness' }, after.reject { |key, _| key == 'readiness' })
    assert_equal(at_start.fetch('readiness') + [answer.fetch(:receipt)], after.fetch('readiness'))
    assert_equal(answer.fetch(:receipt), execution.reconcile_readiness(operation_id: answer.fetch(:operation_id)).fetch(:receipt))
    T::LocalFixedTeamReadinessPort.validate_document!(after, identity: port.identity)

    # The exception for an equal revision requires this exact started lineage.
    missing_start = Marshal.load(Marshal.dump(after))
    missing_start.fetch('executions').each_value { |row| row.delete('start') }
    assert_raises(T::ReadinessContract::Blocked) do
      T::LocalFixedTeamReadinessPort.validate_document!(missing_start, identity: port.identity)
    end
    wrong_reason = Marshal.load(Marshal.dump(after))
    wrong_reason.fetch('readiness').last['reason'] = 'conflict'
    assert_raises(T::ReadinessContract::Blocked) do
      T::LocalFixedTeamReadinessPort.validate_document!(wrong_reason, identity: port.identity)
    end
    wrong_target = Marshal.load(Marshal.dump(after))
    receipt = wrong_target.fetch('readiness').last
    operation = receipt.fetch('operation')
    request = operation.fetch('request').merge('match_ref' => operation.dig('request', 'match_ref').merge('leg' => 2))
    receipt['operation'] = T::ReadinessContract.operation(request, operation.fetch('account'),
      operation.fetch('accepted_match'), SecureRandom.uuid)
    receipt['request_digest'] = receipt.dig('operation', 'request_digest')
    assert_raises(T::ReadinessContract::Blocked) do
      T::LocalFixedTeamReadinessPort.validate_document!(wrong_target, identity: port.identity)
    end
  end
  F.with_execution(fixture, 'Beata') do |execution|
    F.select_execution(execution, record)
    status = execution.local_game(action: :local_game_status).fetch(:status)
    assert_equal(:confirmed, execution.local_game(action: :local_game_move, operation_id: 'legal-after-racing-start',
      revision: status.fetch('revision'), move_selection: status.fetch('actions').first)[:state])
  end
ensure
  close_fixture(fixture)
end
puts 'PASS actual local Start: Ready/Withdraw refusal, original receipt lookup, atomic racing Start conflict, strict lineage validation and continued legal moves'
