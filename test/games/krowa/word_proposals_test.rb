require_relative '../../support/krowa_word_proposals'
include GameRoomTest::Assertions

fixture = KrowaProposalFixture
program, client = KrowaTestProgram.new, fixture::Client.new
service = fixture.service(program: program, client: client)
assert_equal(1, service.deliver('zmywarka'))
assert_equal(['zmywarka'], client.posts.map(&:text))
assert_equal([28_245], client.posts.map(&:thread_id))
assert_equal(1, service.deliver('zmywarka'))
assert_equal(1, fixture.service(program: program, client: client).deliver('zmywarka'))
assert_equal(1, client.posts.length, 'Repeated presses or a cold client duplicated a confirmed post')
assert(client.calls.all? { |call| call[3].keys.sort == [:cancellation_token, :timeout] }, 'SDK calls bypass cancellation/timeout wrapper')

[:before, :after].each do |failure|
  program, client = KrowaTestProgram.new, fixture::Client.new
  client.failure = failure
  assert_raises(IOError) { fixture.service(program: program, client: client).deliver('zmywarka') }
  assert_equal(failure == :after ? 1 : 0, client.posts.length)
  client.failure = nil
  fixture.service(program: program, client: client).deliver('zmywarka')
  assert_equal(1, client.posts.length, 'Explicit retry duplicated a lost acknowledgement')
end

client = fixture::Client.new
service = fixture.service(client: client)
[0, 3, 4].each do |role|
  client.role = role
  assert_raises(GameRoomGames::KrowaWordProposals::Unavailable) { service.deliver('zmywarka') }
end
client.role, client.closed = 2, true
assert_raises(GameRoomGames::KrowaWordProposals::Unavailable) { service.deliver('zmywarka') }
assert(client.posts.empty?, 'Non-member or closed-thread attempt posted content')
client.closed = false
['', 'ab', 'a' * 14, 'two words', 'word123', 'taxi;A411;taxi::::'].each do |word|
  assert_raises(GameRoomGames::KrowaWordProposals::Unavailable) { service.deliver(word) }
end

current = 'Alice'
service = fixture.service(client: client, current_user: -> { current })
client.after_call = ->(path) { current = 'Bob' if path == 'structure' }
assert_raises(GameRoomGames::KrowaWordProposals::Unavailable) { service.deliver('zmywarka') }
assert(client.posts.empty?, 'Account changed between discovery and posting')

program, client = KrowaTestProgram.new, fixture::Client.new
client.failure = :after
assert_raises(IOError) { fixture.service(program: program, client: client).deliver('zmywarka') }
client.failure = nil
client.page = fixture::Page.new([], true, 1)
assert_raises(GameRoomGames::KrowaWordProposals::Unavailable) { fixture.service(program: program, client: client).deliver('zmywarka') }
assert_equal(1, client.posts.length, 'Incomplete retry read sent another post')

program, client = KrowaTestProgram.new, fixture::Client.new
client.after_call = ->(path) { program.fail_write = true if path == 'create' }
service = fixture.service(program: program, client: client)
assert_raises(IOError) { service.deliver('zmywarka') }
program.fail_write, client.after_call = false, nil
service.deliver('zmywarka')
assert_equal(1, client.posts.length, 'Failed receipt persistence caused another send')
program.files[program.files.keys.first] = {'pending' => []}
assert_raises(GameRoomGames::KrowaWordProposals::Unavailable) { service.deliver('bankomat') }
assert_equal({'pending' => []}, program.files.values.first, 'Corrupt preferences were overwritten')
program.define_singleton_method(:read_json) { |_path, **_options| raise JSON::ParserError, 'Damaged JSON' }
assert_raises(GameRoomGames::KrowaWordProposals::Unavailable) { service.deliver('bankomat') }

# Exercise the actual SDK post contract, not just the fixture's service API.
require_relative '../../support/host_source'
require EltenTestHost.file('src/eltenlink/forum.rb')
client = fixture::Client.new
native_requests = []
original_request = client.method(:api_data)
client.define_singleton_method(:api_data) do |method, path, params = nil, **options|
  if path == '/api/v1/forum/28245'
    native_requests << [method, params, options]
    {'id' => 19}
  else
    original_request.call(method, path, params, **options)
  end
end
native_api = Class.new(fixture::Api)
native_api.define_singleton_method(:create_post) { |api_client, **options| EltenLink::Forum.create_post(api_client, **options) }
service = GameRoomGames::KrowaWordProposals.new(KrowaTestProgram.new, user: 'Alice', current_user: -> { 'Alice' },
  bank: KrowaTestGame.new.bank, forum: native_api, client: client)
assert_equal(19, service.deliver('zmywarka'))
assert_equal('POST', native_requests.first[0])
assert_equal('zmywarka', native_requests.first[1]['text'])
assert_equal(15, native_requests.first[2][:timeout])
puts 'PASS Krowa word proposals: exact thread, member/closed/format checks, account boundary, cold retry, uncertain reads and receipt failures'
