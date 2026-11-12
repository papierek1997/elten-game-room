require_relative '../support/native_tasks'
require_relative '../support/native_live_endpoint'
require EltenTestHost.file('src/eltenlink/error.rb')
require EltenTestHost.file('src/eltenlink/client.rb')
require EltenTestHost.file('src/eltenlink/apps.rb')
require_relative '../support/assertions'
require_relative '../../lib/game_room_transport'
require_relative '../../lib/lobby_repository'
require 'uri'
include GameRoomTest::Assertions

# Real SDK construction, blocking stack queue, envelope parser and callbacks;
# only HTTP/discovery replies are local. No profile, socket or OS input exists.
class ResourceIdentityReply
  attr_accessor :context
  attr_reader :histories, :reads

  def initialize
    @histories, @reads = {}, []
  end

  def e_json_request(method, path, params, **_options)
    raise 'Identity probe unexpectedly mutated a resource' unless method == 'GET'
    uri = URI.parse(path)
    native = URI.decode_www_form_component(uri.path.split('/')[-2])
    after = Integer(URI.decode_www_form(uri.query.to_s).to_h.merge(params).fetch('after'))
    @reads << [native, after]
    history = histories.fetch(native)
    selected = history.select { |entry| entry['seq'] > after }
    yield JSON.generate('success' => true, 'data' => {'session_id' => native,
      'entries' => selected, 'cursor' => selected.last&.fetch('seq') || after,
      'through' => history.last&.fetch('seq') || 0, 'has_more' => false}), nil
  end
end

def with_resource_identity
  client = ResourceIdentityReply.new
  endpoint = EltenAPI::LiveSessions::Endpoint.new(app_id: 'ef8a0700-2d36-411b-ae13-6e6811a63a78',
    client: client, user: 'Alice', token: 'offline-only')
  context = Object.new
  context.define_singleton_method(:loop_update) { |*_| endpoint.send(:tick_stack_requests); Thread.pass }
  client.context = context
  metadata = {'kind' => GameRoomLiveSessionStore::KIND, 'protocol' => 7, 'table_id' => 41,
    'owner' => 'Alice', 'name' => 'Resource identity', 'game' => 'uno', 'game_options' => '{}', 'created_at' => 1}
  counter = 0
  endpoint.define_singleton_method(:discovery_request) do |operation, params, **options|
    raise "Unexpected discovery mutation #{operation}" unless [:create, :join].include?(operation)
    counter += 1
    id = operation == :join ? options.fetch(:session_id) : format('10000000-0000-4000-8000-%012d', counter)
    {'id' => id, 'metadata' => metadata.merge(params.fetch('metadata', {})),
      'participant_id' => "alice-#{counter}", 'owner_id' => "alice-#{counter}", 'private_messages' => true,
      'capacity' => 8, 'participants' => [{'id' => "alice-#{counter}", 'user' => 'Alice'}, {'id' => 'bob', 'user' => 'Bob'}],
      'limits' => {'stack' => true, 'pools' => true, 'private_messages' => true,
        'max_stack_entries' => 4096, 'max_stack_entry_bytes' => 16384}}
  end
  store = GameRoomLiveSessionStore.new(Struct.new(:live_sessions).new(endpoint), local_view: true)
  build = lambda do |table_id = 41|
    native = endpoint.create(metadata: metadata.merge('table_id' => table_id), capacity: 8, stack_entries: 4096,
      stack_entry_bytes: 16384, pool_count: 1, private_messages: true)
    client.histories[native.id] = []
    native
  end
  yield store, endpoint, client, build
ensure
  store&.close_local_view
  endpoint&.close
  EltenAPI::LiveSessions.unregister(endpoint) if endpoint
end

def retained_start(client, native)
  client.histories[native.id] = [{'seq' => 1, 'message_id' => SecureRandom.uuid,
    'sender' => {'user' => 'Alice'}, 'sender_id' => native.participants.find { |person| person.user == 'Alice' }.id, 'created_at' => 1,
    'packet' => GameRoomEventProtocol.record_packet(kind: 'game_started', actor: 'Alice',
      data: {'session_id' => 123, 'game' => 'uno', 'players' => %w[Alice Bob], 'options' => '{}', 'created_at' => 1})}]
end

# A different native UUID must never inherit any cursor, data or unresolved work,
# even when the old app-level number remains in the ordinary inactive cache.
%i[idle pending recovered private io subscription control].each do |protection|
  with_resource_identity do |store, endpoint, client, build|
    old = build.call
    retained_start(client, old)
    store.send(:attach_session, 41, old)
    old.close_local(:closed, confirmed: true, operation: :close)
    endpoint.dispatch_events(100)
    state = store.instance_variable_get(:@rooms).fetch(41)
    case protection
    when :pending then state.pending_move = Object.new
    when :recovered then state.recovered_moves << Object.new
    when :private then state.private_game_messages << {session_id: 123}
    when :io then store.send(:begin_room_io, 41)
    when :subscription then store.retain_room_subscription(41)
    when :control then state.control_lock = Mutex.new; state.control_lock.lock
    end
    pending, records, visit = state.pending_move, state.records.dup, state.attachment
    replacement = build.call
    assert_raises(GameRoomNetworkErrors::GamePaused) { store.send(:attach_session, 41, replacement) }
    assert_equal([], client.reads.select { |native, _| native == replacement.id }, "#{protection}: read the wrong resource")
    assert(store.instance_variable_get(:@rooms).fetch(41).equal?(state), 'Collision replaced owned state')
    assert_equal([pending, records, visit, 1], [state.pending_move, state.records, state.attachment, state.stack_cursor])
    assert_equal(nil, store.send(:active_session, 41), 'Refused resource became the active alias')
    state.control_lock.unlock if protection == :control
    store.send(:end_room_io, 41) if protection == :io
    store.release_room_subscription(41) if protection == :subscription
  end
end

# Same resource, different native membership object: preserve uncertainty,
# subscription and history while rotating the visit and ignoring a late close.
with_resource_identity do |store, endpoint, client, build|
  old = build.call
  retained_start(client, old)
  store.send(:attach_session, 41, old)
  state = store.instance_variable_get(:@rooms).fetch(41)
  state.pending_move = pending = GameRoomSessionContracts::PendingWrite.new(message_id: SecureRandom.uuid,
    packet: {}, sender: 'Alice', writing: false, uncertain: true, error: IOError.new('isolated fixture'))
  store.retain_room_subscription(41)
  visit = state.attachment
  old.close_local(:left, confirmed: true, operation: :leave)
  fresh = endpoint.join_discovered_session(old.id, 'local-only', {})
  store.send(:attach_session, 41, fresh)
  endpoint.dispatch_events(100)
  assert(store.instance_variable_get(:@rooms).fetch(41).equal?(state), 'Rejoin discarded the same resource state')
  assert(state.pending_move.equal?(pending) && pending.uncertain, 'Late close erased uncertainty')
  assert_equal([0, 1, [123]], [state.io_count, state.subscription_count,
    store.game_sessions(41).map { |row| row['__id'] }])
  assert(!state.attachment.equal?(visit), 'Rejoin reused the old visit token')
  before = client.reads.length
  wrong = {'__id' => 41, '__live_session_id' => '20000000-0000-4000-8000-000000000002'}
  assert_equal(nil, store.room_snapshot(wrong, force: true, read_only: true), 'Row-bound snapshot returned another native resource')
  assert_equal(before, client.reads.length, 'Wrong row triggered I/O into the current resource')
  assert_equal(:closed, store.join_room(wrong, 'Alice'), 'Numeric alias was reported as already_here')
  store.release_room_subscription(41)
end

# The lobby must not consume a numeric new-join marker or return :already_here
# before the store gets a chance to check the row's native resource identity.
current = {'__id' => 41, '__live_session_id' => 'native-a'}
candidate = current.merge('__live_session_id' => 'native-b')
transport = Object.new
transport.define_singleton_method(:current_room) { |_user| current }
transport.define_singleton_method(:room_snapshot) { |row, **_| {table: row, members: ['Alice'], bots: [], observers: []} }
transport.define_singleton_method(:consume_new_join) { |*_| raise 'Consumed an unrelated numeric admission' }
lobby = LobbyRepository.new(Object.new, transport: transport)
assert_equal(:already_at_another_table, lobby.join_table(candidate, 'Alice').status)

with_resource_identity do |store, endpoint, client, build|
  first, wanted = build.call, build.call
  joins = []
  discovered = [first, wanted].map do |native|
    item = Struct.new(:id, :discovery_metadata).new(native.id, native.metadata)
    item.define_singleton_method(:join) do |**_options|
      joins << native.id
      endpoint.join_discovered_session(native.id, 'local-only', {})
    end
    item
  end
  # A row from another endpoint cannot carry its join authority into this
  # store. Resolve its exact UUID here, even when the numeric cache matches A.
  store.send(:endpoint)
  store.instance_variable_get(:@discovered)[41] = discovered.first
  store.define_singleton_method(:discover_pages) { |**_| discovered }
  store.define_singleton_method(:publish_discovery) { |*, **_| false }
  row = {'__id' => 41, '__live_session_id' => wanted.id}
  assert_equal(:joined, store.join_room(row, 'Alice'))
  assert_equal([wanted.id], joins, 'Discovery joined the first numeric alias instead of the requested UUID')
  assert(client.reads.all? { |id, after| id == wanted.id && after == 0 }, 'Fresh resource inherited another cursor')
end

with_resource_identity do |store, endpoint, client, build|
  old, wanted = build.call, build.call
  retained_start(client, old)
  store.send(:attach_session, 41, old)
  old.close_local(:left, confirmed: true, operation: :leave)
  endpoint.dispatch_events(100)
  item = Struct.new(:id, :discovery_metadata).new(wanted.id, wanted.metadata)
  item.define_singleton_method(:join) { |**_| raise 'Conflicting discovery created membership before refusal' }
  store.send(:endpoint)
  store.instance_variable_get(:@discovered)[41] = item
  assert_raises(GameRoomNetworkErrors::GamePaused) do
    store.join_room({'__id' => 41, '__live_session_id' => wanted.id}, 'Alice')
  end
  invitation = Object.new
  invitation.define_singleton_method(:accept) { |**_| raise 'Conflicting invitation accepted before refusal' }
  invitation.define_singleton_method(:pending?) { true }
  stored = {table_id: 41, native_id: wanted.id, invitation: invitation}
  store.define_singleton_method(:take_invitation) { |*_| stored }
  restored = []
  store.define_singleton_method(:restore_invitation) { |value| restored << value }
  assert_raises(GameRoomNetworkErrors::GamePaused) { store.accept_invitation(table_id: 41, invitation_id: 1) }
  assert_equal([stored], restored, 'Preflight refusal lost the pending invitation')
  assert_equal([], client.reads.select { |id, _| id == wanted.id })
  random_number = SecureRandom.method(:random_number)
  candidates = [40, 41]
  begin
    SecureRandom.define_singleton_method(:random_number) { |_limit| candidates.shift || raise('Creation did not avoid the retained alias') }
    assert_equal(42, store.send(:unused_identifier), 'Own creation selected a retained inactive number')
  ensure
    SecureRandom.define_singleton_method(:random_number, random_number)
  end
end

# Actual queued native closures can outlive the bounded inactive cache. A
# callback for an evicted visit must not recreate a new, unindexed RoomState.
with_resource_identity do |store, endpoint, _client, build|
  ([41] + (100..108).to_a).each do |id|
    native = build.call(id)
    store.send(:attach_session, id, native)
    native.close_local(:left, confirmed: true, operation: :leave)
    assert_equal(nil, store.send(:active_session, id))
  end
  assert(!store.instance_variable_get(:@rooms).key?(41), 'Control did not evict the inactive first visit')
  expected_ids = store.instance_variable_get(:@rooms).keys.sort
  endpoint.dispatch_events(100)
  assert_equal(expected_ids, store.instance_variable_get(:@rooms).keys.sort, 'Late closure recreated evicted resource state')
end

puts 'PASS native resource identity: distinct UUID refused before read, same UUID rejoin retained, row-bound snapshot/join and lobby admission separated'
