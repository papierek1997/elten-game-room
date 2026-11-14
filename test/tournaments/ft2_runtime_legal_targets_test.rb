# encoding: UTF-8
require_relative '../support/ft2_runtime_cold'
include FT2RuntimeCold
C = T::CoordinationContract
A = T::ExecutionPlanContract
rows = []
fixtures = [0, 3].map do |index|
  context, record = execution_fixture(File.basename(ENV.fetch('ENTRY_EVIDENCE')) + "-#{index}")
  all_ready(context, record, index)
  result = nil
  execution_for(context, record, 'Beata', native_provider: TournamentFixedTeamNativeService.new) do |facade|
    select_match(facade, record, index)
    result = facade.request_match
  end
  assert_equal(:bound, result[:state])
  [context, record, result, state(context)]
end
context, record, first, original = fixtures.first
other = fixtures.last[2][:target].to_h
first_target = first[:target].to_h
assert(first_target['binding']['native_uuid'] != other['binding']['native_uuid'])
assert(first_target['native']['options'] != other['native']['options'])
receipt = original['executions'].values.first['operations']['create_bind']
operation = receipt['operation']
assert_equal(operation, C.operation!(operation, registry: REGISTRY))
assert_equal(receipt, C.response!(receipt, operation))
assert_equal(first[:binding].to_h, C.binding!(receipt, registry: REGISTRY).to_h)
ft1_path = File.join(context.directory, 'plany', 'fixed-teams-v1', 'sandbox-k02.json')
disk = [File.binread(state_path(context)), File.binread(ft1_path)]

# Cały istniejący drugi pokój jest legalny dla własnego receiptu, ale nie dla pierwszego.
mutations = {'existing_uuid' => other['readback']}
options = other['native']['options']
changed = C.copy(first_target['readback'])
[changed['table'], changed['metadata'], changed['discovery'], changed['stack'].first['packet']['data']].each do |part|
  part['game_options'] = JSON.generate(options)
end
# Shape, wewnętrzna zgodność core i natywny konsument nadal są legalne.
owner = operation['request']['players'].find { |person| person['account'] == operation['actor'] }
# Validate the same authenticated cosmetic projection used by build, while
# retaining the complete, unmodified readback for the exact-target refusal.
structural = C.copy(changed)
T::FixedTeamBoundTarget.send(:normalize_presentation_metadata!, structural, operation['request'], operation)
T::FixedTeamBoundTarget.send(:validate_readback!, structural, owner, capacity: operation['request']['players'].size)
game = REGISTRY.build('spades')
assert_equal(options, game.options_for_team_roster(game.new_game_options(options), players: other['native']['players']))
assert(game.prepared_team_assignment(options, players: other['native']['players']))
mutations['existing_team_options'] = changed
mutations.each do |kind, readback|
  observed = nil
  effects do |calls|
    error = assert_raises(T::CoordinationContract::Blocked) do
      T::FixedTeamBoundTarget.build(record: record, response: receipt, readback: readback, registry: REGISTRY)
    end
    assert_equal(:native_target_mismatch, error.code, 'Exact native gate po legalnym operation/response/binding')
    assert_equal([], calls)
    observed = {kind: kind, passed: %w[operation response binding native_consumer], code: error.code,
      trusted_record: record, response: receipt, first: first_target, other: other, mutated: readback, calls: calls}
  end
  rows << observed
end

# Neutralne A pozwala zmienić obie nogi; nie jest autorytetem pierwszej obsady FT1.
both = A.copy(record['evidence'])
[0, 3].each do |index|
  match = both['plan']['matches'][index]
  match['players'] = match['players'].values_at(1, 0, 3, 2).each_with_index.map do |person, seat|
    person.merge('seat' => seat, 'game_role' => "seat:#{seat}")
  end
end
both['plan_digest'] = A.digest(both.slice('scope', 'plan'))
assert_equal(both, A.validate(both, record['expected_source'], registry: REGISTRY))
match = both['plan']['matches'].first
selectors = {evidence: both, expected_source: record['expected_source'], match_id: match['match_id'], leg: match['leg'], window_id: match['windows'].first['id'], registry: REGISTRY}
request = T::CoordinationRequest.from_execution_plan(**selectors)
native = T::FixedTeamNativePayload.from_execution_plan(**selectors)
changed_operation = C.operation(kind: operation['kind'], request: request.to_h, actor: operation['actor'],
  preconditions: operation['preconditions'], operation_id: operation['operation_id'])
changed_receipt = C.copy(receipt).merge('operation' => changed_operation, 'request_digest' => changed_operation['request_digest'])
C.operation!(changed_operation, registry: REGISTRY)
C.response!(changed_receipt, changed_operation)
C.binding!(changed_receipt, registry: REGISTRY)
error = assert_raises(T::CoordinationContract::Blocked) do
  T::FixedTeamBoundTarget.build(record: record, response: changed_receipt, readback: first_target['readback'], registry: REGISTRY)
end
assert_equal(:record_mismatch, error.code)
assert_equal(disk, [File.binread(state_path(context)), File.binread(ft1_path)])
rows << {kind: 'both_legs_base', passed: %w[A_v2 request native operation response binding], code: error.code,
  trusted_record: record, evidence: both, expected_base: record['preview']['base_seats'][match['match_id']],
  mutated_base: match['players'].map { |person| person['account'] }, request: request.to_h, request_digest: request.digest,
  native: native.to_h, native_digest: native.digest, operation: changed_operation, response: changed_receipt}

# Rzeczywisty port, nie tylko fabryka: valid neutral request w state nie zmienia trusted records.
corrupted = JSON.parse(disk.first)
execution = corrupted['executions'].values.first
execution['request'] = request.to_h
execution['operations'].each do |kind, value|
  op = value['operation']
  replacement = C.operation(kind: kind, request: request.to_h, actor: op['actor'], preconditions: op['preconditions'], operation_id: op['operation_id'])
  execution['operations'][kind] = value.merge('operation' => replacement, 'request_digest' => replacement['request_digest'])
  C.response!(execution['operations'][kind], replacement)
end
File.binwrite(state_path(context), JSON.generate(corrupted))
changed_bytes = File.binread(state_path(context))
actual = nil
execution_for(context, record, 'Beata', native_provider: TournamentFixedTeamNativeService.new) do |facade|
  select_match(facade, record)
  effects do |calls|
    actual = outcome { facade.reconcile }
    assert_equal([], calls)
  end
end
assert_equal(:blocked, actual[:state])
assert_equal(:sandbox_corrupt, actual[:reason])
assert(changed_bytes == File.binread(state_path(context)))
assert(disk.last == File.binread(ft1_path))
rows << {kind: 'real_port_trusted_record', actual: actual, corrupted: corrupted, disk_unchanged: true}
oracle_file('legal-targets.json', {fixtures: fixtures.map { |ctx, rec, res, document| {path: ctx.directory, record: rec, target: res[:target].to_h, state: document} }, cases: rows})
puts 'GREEN: dwa rzeczywiste legalne cele, native options i legalne obie nogi; exact odmowa bez skutków'
