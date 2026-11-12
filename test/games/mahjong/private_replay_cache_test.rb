require_relative '../../support/mahjong_private_pools'
require 'timeout'

class MahjongCacheRepository
  attr_accessor :resource
  attr_reader :actor_calls
  def initialize(source, session)
    @source, @resource, @actor_calls, @actors, @generation = source, source.replay_resource_identity(session), 0, {}, Object.new
  end
  def replay_resource_identity(_session); @resource; end
  def replay_authentication_identity; [@source.replay_authentication_identity, @generation]; end
  def reset_calls; @actor_calls = 0; end
  def change_actor(id, actor); @actors[id] = actor; @generation = Object.new; end
  def actor_of(event, session)
    @actor_calls += 1
    @actors.fetch(@source.event_id(event)) { @source.actor_of(event, session) }
  end
  def method_missing(name, *args, **kwargs, &block); @source.public_send(name, *args, **kwargs, &block); end
  def respond_to_missing?(name, private = false); @source.respond_to?(name, private) || super; end
end

def normalized_private_replay(value)
  case value
  when Hash then value.to_h { |key, item| [key, normalized_private_replay(item)] }
  when Array then value.map { |item| normalized_private_replay(item) }
  when Struct then [value.class.name, value.each_pair.to_h { |key, item| [key, normalized_private_replay(item)] }]
  when String, Symbol, Numeric, NilClass, TrueClass, FalseClass then value
  else
    if value.is_a?(Data)
      [value.class.name, value.members.to_h { |key| [key, normalized_private_replay(value.public_send(key))] }]
    else
      [value.class.name, value.instance_variables.sort.to_h { |key| [key, normalized_private_replay(value.instance_variable_get(key))] }]
    end
  end
end

def checked_private_cache(game, session, events, repository, label:, applies: nil, audits: nil)
  resource = repository.resource
  begin
    repository.resource = nil
    expected = GameRoomGames::Mahjong.new.replay(session, events, repository)
  ensure
    repository.resource = resource
  end
  repository.reset_calls
  counts = Hash.new(0)
  trace = TracePoint.new(:call) do |point|
    if point.defined_class == GameRoomGames::MahjongPrivateTableReplay
      counts[point.method_id] += 1
    end
  end
  actual = nil
  trace.enable { actual = game.replay(session, events, repository) }
  assert(normalized_private_replay(actual) == normalized_private_replay(expected), "#{label}: differs from a complete uncached replay")
  assert(counts[:private_table_apply] == applies, "#{label}: repeated #{counts[:private_table_apply]} rules, expected #{applies}") unless applies.nil?
  assert(counts[:private_table_audit] == audits, "#{label}: repeated #{counts[:private_table_audit]} audits, expected #{audits}") unless audits.nil?
  [actual, counts]
ensure
  trace&.disable
end

def check_private_cache_refusal(game, session, events, repository)
  adapter = game.send(:adapter_for_options, 'variant'=>'hong_kong')
  reduce = adapter.method(:private_table_reduce)
  adapter.define_singleton_method(:private_table_reduce) do |*arguments|
    result = reduce.call(*arguments)
    line = GameRoomGames::HistoryEntry.new(key: 'cache-budget-fixture', kind: :info,
      text: 'x' * GameRoomReplayCache::MAX_BYTES)
    result.history = result.history + [line]
    result
  end
  repository.resource = Object.new
  result = game.replay(session, events, repository)
  assert(result.history.last.text.size == GameRoomReplayCache::MAX_BYTES, 'Checkpoint refusal did not return the full current result')
  %i[@mahjong_private_input @mahjong_private_resource @mahjong_private_cache].each do |name|
    assert(adapter.instance_variable_get(name).nil?, "Refused checkpoint retained #{name}")
  end
ensure
  adapter&.singleton_class&.send(:remove_method, :private_table_reduce)
end

def check_private_cache_concurrency(game, session, events, native)
  first, second = 2.times.map { MahjongCacheRepository.new(native, session) }
  first.resource = Object.new
  second.resource = nil
  entered, release, started = Queue.new, Queue.new, Queue.new
  actor_of = first.method(:actor_of)
  first.define_singleton_method(:actor_of) do |event, context|
    if Thread.current[:pause_private_cache]
      Thread.current[:pause_private_cache] = false
      entered << true
      release.pop
    end
    actor_of.call(event, context)
  end
  expected = GameRoomGames::Mahjong.new.replay(session, events, second)
  second.reset_calls
  threads = []
  threads << Thread.new do
    Thread.current[:pause_private_cache] = true
    game.replay(session, events, first)
  end
  Timeout.timeout(5) { entered.pop }
  threads << Thread.new { started << true; game.replay(session, events, second) }
  Timeout.timeout(5) do
    started.pop
    Thread.pass until threads.last.stop?
  end
  assert(second.actor_calls.zero? && threads.last.alive?, 'A concurrent refusal overtook an in-progress adapter replay')
  release << true
  results = Timeout.timeout(5) { threads.map(&:value) }
  assert(results.all? { |result| normalized_private_replay(result) == normalized_private_replay(expected) }, 'Concurrent replay changed either account result')
  adapter = game.send(:adapter_for_options, 'variant'=>'hong_kong')
  %i[@mahjong_private_input @mahjong_private_resource @mahjong_private_cache].each do |name|
    assert(adapter.instance_variable_get(name).nil?, "A concurrent refusal resurrected #{name}")
  end
ensure
  release << true if release
  threads&.each { |thread| thread.join(5) }
end

%w[hong_kong riichi mcr].each do |variant|
  ready = [124,125,126,128,129,130,132,133,134,108,109,110,112]
  game, harness, runners = MahjongPrivateTest.create(variant, hands: {'Alice'=>ready}, extra: 113, winds: 1)
  begin
    native = harness.repositories.fetch('Alice')
    initial = harness.as('Alice') { native.snapshot_for(harness.session, read_only: true) }
    repository = MahjongCacheRepository.new(native, initial.session)
    assert(repository.resource, 'Fixture did not expose a genuine local membership token')
    tested = GameRoomGames::Mahjong.new
    empty, = checked_private_cache(tested, initial.session, [], repository, label: "#{variant}/empty")
    assert(!empty.state.key?(:private_audit_sources), 'Cache invented a truthy audit tape before mahjong_begin')
    checked_private_cache(tested, initial.session, [], repository, label: "#{variant}/empty-warm", applies: 0, audits: 0)

    # The raw -> shorter historical -> full hit -> sealed winning append
    # sequence must not retain foreign Hash identities in either audit tape.
    raw = initial.events.map { |event| GameRoomSnapshot.copy(event) }
    checked_private_cache(tested, initial.session, raw, repository, label: "#{variant}/raw")
    checked_private_cache(tested, initial.session, raw.first(10), repository, label: "#{variant}/history")
    actual, = checked_private_cache(tested, initial.session, raw, repository, label: "#{variant}/raw-again", applies: 0, audits: 0)
    actual.state[:hands]['Alice'][0] = -999
    actual.state[:private_audit_sources].clear
    actual.history = []
    checked_private_cache(tested, initial.session, raw, repository, label: "#{variant}/caller-mutation", applies: 0, audits: 0)
    checked_private_cache(tested, initial.session.merge('__game_revision'=>[99, 100]), raw, repository,
      label: "#{variant}/CAS-only update", applies: 0, audits: 0)

    if variant == 'hong_kong'
      changed = GameRoomSnapshot.copy(raw)
      changed[0]['value'] = '999'
      checked_private_cache(tested, initial.session, changed, repository, label: 'earlier same-ID source correction')
      checked_private_cache(tested, initial.session, raw, repository, label: 'restored earlier source')
      repository.change_actor(native.event_id(raw.first), 'Bob')
      checked_private_cache(tested, initial.session, raw, repository, label: 'changed authenticated author')
      repository.change_actor(native.event_id(raw.first), 'Alice')
      checked_private_cache(tested, initial.session, raw, repository, label: 'restored authenticated author')
      context = GameRoomSnapshot.copy(initial.session)
      context['__private_draws'] = context['__private_draws'].transform_values(&:reverse)
      checked_private_cache(tested, context, raw, repository, label: 'changed whole private map')
      checked_private_cache(tested, initial.session, raw, repository, label: 'restored private map')
      repository.resource = Object.new
      _, counts = checked_private_cache(tested, initial.session, raw, repository, label: 'new attachment')
      assert(counts[:private_table_apply] >= raw.size, 'A new attachment reused a prior visit')
      repository.resource = nil
      checked_private_cache(tested, initial.session, raw, repository, label: 'missing attachment')
      adapter = tested.send(:adapter_for_options, 'variant'=>variant)
      assert(!adapter.instance_variable_get(:@mahjong_private_input) && !adapter.instance_variable_get(:@mahjong_private_cache), 'Missing resource retained a private cache')
      repository.resource = native.replay_resource_identity(initial.session)
      checked_private_cache(tested, initial.session, raw, repository, label: 'restored attachment')
      large = GameRoomSnapshot.copy(initial.session)
      large['__private_draws']['unused-admission-map'] = ['x' * GameRoomReplayCache::MAX_BYTES]
      checked_private_cache(tested, large, raw, repository, label: 'oversized nested private context')
      assert(!adapter.instance_variable_get(:@mahjong_private_input) && !adapter.instance_variable_get(:@mahjong_private_cache), 'Oversized context retained a prepared input')
      assert(!adapter.instance_variable_get(:@mahjong_table_input) && !adapter.instance_variable_get(:@mahjong_table_cache), 'An empty public init retained the large private session')
      oversized_raw = GameRoomSnapshot.copy(raw)
      oversized_raw.first['unused-budget-fixture'] = 'x' * GameRoomReplayCache::MAX_BYTES
      checked_private_cache(tested, initial.session, oversized_raw, repository, label: 'oversized mutable input')
      assert(!adapter.instance_variable_get(:@mahjong_private_input) && !adapter.instance_variable_get(:@mahjong_private_cache), 'Oversized mutable input was retained')
      check_private_cache_refusal(tested, initial.session, raw, repository)
      check_private_cache_concurrency(tested, initial.session, raw, native)
      repository.resource = native.replay_resource_identity(initial.session)
      harness.users.each do |viewer|
        view_repository = harness.repositories.fetch(viewer)
        snapshot = harness.as(viewer) { view_repository.snapshot_for(harness.session, read_only: true) }
        view = MahjongCacheRepository.new(view_repository, snapshot.session)
        result, = checked_private_cache(tested, snapshot.session, snapshot.events, view, label: "shared adapter/view #{viewer}")
        assert(result.state[:private_viewer] == viewer, 'A cached private model belongs to a different viewer')
        (harness.users - [viewer]).each do |other|
          assert(result.state[:hands].fetch(other).all? { |tile| GameRoomPrivateCardLedger.hidden?(tile) }, 'Cache disclosed a different viewer hand')
        end
      end
      checked_private_cache(tested, initial.session, raw, repository, label: 'restore after context refusal')
      checked_private_cache(tested, initial.session, raw.first(10), repository, label: 'final short raw history')
      checked_private_cache(tested, initial.session, raw, repository, label: 'final raw full', applies: 0, audits: 0)
    end

    selection = game.legal_actions(harness.replay('Alice'), 'Alice').find { |action| action['action'] == 'win' }
    PrivateCardGamesTest.submit(harness, runners, 'Alice', selection)
    30.times do
      PrivateCardGamesTest.tick(harness, runners)
      item = harness.replay('Alice')
      break if item.state[:phase] == :between_hands || item.state[:private_error]
    end
    complete = harness.as('Alice') { native.snapshot_for(harness.session, read_only: true) }
    assert(complete.session['__private_draws'] == initial.session['__private_draws'], 'Fixture no longer exercises an unchanged-map winning append')
    result, counts = checked_private_cache(tested, complete.session, complete.events, repository, label: "#{variant}/winning-append")
    assert(counts[:private_table_audit] == 1 && result.state[:phase] == :between_hands && !result.state[:private_error], 'A real appended hand skipped or failed strict audit')
    checked_private_cache(tested, complete.session, complete.events, repository, label: "#{variant}/complete-warm", applies: 0, audits: 0)
    assert(repository.actor_calls.zero?, 'An unchanged sealed native log repeated actor authentication')
    ready_action = game.legal_actions(harness.replay('Alice'), 'Alice').find { |action| action['action'] == 'ready' }
    PrivateCardGamesTest.submit(harness, runners, 'Alice', ready_action)
    appended = harness.as('Alice') { native.snapshot_for(harness.session, read_only: true) }
    checked_private_cache(tested, appended.session, appended.events, repository, label: "#{variant}/ready-append", applies: 1, audits: 0)
    puts "PASS private Mahjong #{variant} cache: cold equality, raw/history/sealed ownership, strict winning append, warm0/0 and ready1/0"
  ensure
    runners&.each_value(&:close)
  end
end
