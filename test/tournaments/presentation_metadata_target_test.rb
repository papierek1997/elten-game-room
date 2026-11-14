require_relative '../support/tournament_ft2b1_native_support'
include GameRoomTest::Assertions
N = TournamentFT2B1Native
T = N::T
require_relative '../support/temporary_directory'
GameRoomTest::TemporaryDirectory.create('named-target-') do |directory|
old_environment = ENV.to_h.slice('FT2_SCRATCH', 'ENTRY_EVIDENCE')
ENV['FT2_SCRATCH'] = directory
ENV['ENTRY_EVIDENCE'] = directory
fixture = N.fixture('display-names')
original = GameRoomParticipants.method(:local_display_name)
GameRoomParticipants.define_singleton_method(:local_display_name) { 'Anna Kowalska' }
begin
  N.ready(fixture, 0)
  N.execute(fixture, 0) do |execution|
    result = execution.request_match
    assert_equal(:bound, result[:state], result.inspect)
    target = result.fetch(:target).to_h
    readback = target.fetch('readback')
    assert_equal('Anna Kowalska', readback.fetch('discovery').fetch('owner_display_name'))
    assert_equal(2, readback.fetch('stack').size)
    assert_equal('room_profile', readback['stack'].last['packet']['kind'])
    assert_equal(target, execution.reconcile[:target].to_h, 'Cosmetic profile broke the persisted native capture')
    document = JSON.parse(File.binread(execution.instance_variable_get(:@storage).path))
    operation = document.fetch('executions').values.first.fetch('operations').fetch('create_bind')
    build = lambda { |value| T::FixedTeamBoundTarget.build(record: fixture[:record], response: operation,
      readback: value, registry: N::F::REGISTRY) }
    mutations = [
      ->(v) { v['stack'].last['sender']['user'] = 'SomeoneElse' },
      ->(v) { v['stack'].last['seq'] = 4 },
      ->(v) { v['stack'].last['packet']['data']['options'] = {} },
      ->(v) { v['discovery']['owner_display_name'] = "bad\nname" },
      ->(v) { v['table']['owner'] = 'SomeoneElse' }
    ]
    mutations.each do |mutate|
      copy = T::CoordinationContract.copy(readback)
      mutate.call(copy)
      failure = nil
      begin
        build.call(copy)
      rescue T::CoordinationContract::Invalid, T::CoordinationContract::Blocked => error
        failure = error
      end
      assert(failure, 'Unknown or unauthenticated fields loosened the sealed target')
    end
  end
ensure
  GameRoomParticipants.define_singleton_method(:local_display_name, original)
  N.close(fixture)
  %w[FT2_SCRATCH ENTRY_EVIDENCE].each { |key| old_environment.key?(key) ? ENV[key] = old_environment[key] : ENV.delete(key) }
end
end
puts 'PASS authenticated cosmetic target metadata, exact capture and tamper refusal'
