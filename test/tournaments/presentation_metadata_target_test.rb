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
    selection = execution.selection
    provider = N::Provider.new
    adapter = T::FixedTeamNativeTargetAdapter.new(provider: provider, registry: N::F::REGISTRY)
    projection = adapter.budget_readback(native: selection[:native], request: selection[:request].to_h,
      owner: selection[:request].to_h.fetch('players').first.fetch('username'))
    native_projection = adapter.budget_native(projection)
    assert_equal(2, projection['stack'].size, 'Named owners need space for the initial profile packet')
    assert_equal(2, native_projection['cores'].first['last_seq'])
    assert_equal(2, native_projection['cores'].first['dedup'].size)
    assert_equal('Anna Kowalska', native_projection['creates'].first['arguments']['participant_metadata']['display_name'])
    provider.advertised_limits = {
      'options_bytes' => JSON.generate(selection[:native].to_h['options']).bytesize,
      'discovery_bytes' => JSON.generate(projection['discovery']).bytesize,
      'stack_entry_bytes' => projection['stack'].map { |entry| JSON.generate(entry['packet']).bytesize }.max,
      'core_bytes' => JSON.generate(native_projection).bytesize
    }
    execution.native_provider = provider
    result = execution.request_match
    assert_equal(:bound, result[:state], result.inspect)
    target = result.fetch(:target).to_h
    readback = target.fetch('readback')
    assert_equal('Anna Kowalska', readback.fetch('discovery').fetch('owner_display_name'))
    assert_equal(2, readback.fetch('stack').size)
    assert_equal('room_profile', readback['stack'].last['packet']['kind'])
    assert_equal(target, execution.reconcile[:target].to_h, 'Cosmetic profile broke the persisted native capture')
    document = JSON.parse(File.binread(execution.instance_variable_get(:@storage).path))
    assert(JSON.generate(document.fetch('native')).bytesize <= provider.limits.fetch('core_bytes'),
      'Named owners exceeded the advertised native storage budget')
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
