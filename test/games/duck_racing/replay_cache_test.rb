require 'fileutils'
require_relative '../../support/duck_game_adapter'
include DuckGameAdapterTest

# Local model/codec/repository trials, never a live ELTEN or a network trial.
def copy(value); Marshal.load(Marshal.dump(value)); end
def canonical(value); DuckGameAdapterTest.semantic(value); end

def cold(h, session = h.session, events = h.events, repository = h.repository, resources: h.resources)
  GameRoomGames::DuckRacing.new(resources: resources).replay(session, events, repository)
end

def counted
  count = 0
  trace = TracePoint.new(:call) { |point| count += 1 if point.method_id == :apply && point.self.equal?(LOGIC::Session) }
  value = trace.enable { yield }
  [count, value]
end

def same_as_cold(h, session = h.session, events = h.events, repository = h.repository)
  actual = h.game.replay(session, events, repository)
  assert_equal(canonical(cold(h, session, events, repository)), canonical(actual))
  actual
end

def finished_fixture(count: 3)
  h = Harness.new(count: count)
  h.open_round
  h.begin_round
  h.finish_private
  h
end

checks = []
check = lambda do |name, &block|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  item = {name: name, status: 'PASS'}
  begin
    block.call
  rescue StandardError => error
    item.merge!(status: 'FAIL', error: "#{error.class}: #{error.message}", location: error.backtrace.first(5))
  ensure
    item[:seconds] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(4)
    checks << item
  end
end

check.call('unchanged history reuses checked private attempts; one appended action is checked once') do
  h = Harness.new
  h.start
  before = canonical(h.replay)
  calls, again = counted { h.replay }
  assert_equal(0, calls, 'An unchanged authenticated prefix was reduced again')
  assert_equal(before, canonical(again))
  status, plan = h.plan({'action' => 'race', 'input' => {'kind' => 'roll'}}, actor: h.players.first)
  assert_equal(:ok, status)
  h.append(plan, actor: h.players.first)
  calls, appended = counted { h.replay }
  assert_equal(1, calls, 'Appending a logical action re-ran earlier rules')
  assert_equal(canonical(cold(h)), canonical(appended))
  h = finished_fixture
  calls, again = counted { h.replay }
  assert_equal(0, calls, 'Verified concealed traces were checked again')
  assert_equal(canonical(cold(h)), canonical(again))
end

check.call('native CAS-only changes preserve semantic prefix reuse without changing caller CAS') do
  h = Harness.new
  h.start
  h.session['__game_revision'] = 'native-cas-1'
  expected = canonical(h.replay)
  h.session['__game_revision'] = 'native-cas-2'
  original_session = Marshal.dump(h.session)
  calls, again = counted { h.replay }
  assert_equal(0, calls, 'A write-only native CAS invalidated the existing game prefix')
  assert_equal(expected, canonical(again))
  assert_equal(original_session, Marshal.dump(h.session), 'Replay modified the caller CAS/session')
  status, plan = h.plan({'action' => 'race', 'input' => {'kind' => 'roll'}}, actor: h.players.first)
  assert_equal(:ok, status)
  h.append(plan, actor: h.players.first)
  h.session['__game_revision'] = 'native-cas-3'
  calls, appended = counted { h.replay }
  assert_equal(1, calls, 'Native append reduced old game actions again')
  assert_equal(canonical(cold(h)), canonical(appended))
end

check.call('sealed native input reuses only the same authenticated generation and enforces retention cap') do
  h = Harness.new
  h.start
  repository_class = Class.new do
    attr_accessor :generation
    attr_reader :actor_calls
    def initialize(delegate)
      @delegate, @generation, @actor_calls = delegate, 'generation-1', 0
    end
    def players_for(session); @delegate.players_for(session); end
    def event_id(row); @delegate.event_id(row); end
    def actor_of(row, session)
      @actor_calls += 1
      @delegate.actor_of(row, session)
    end
    def replay_authentication_identity; generation; end
  end
  repository = repository_class.new(h.repository)
  events = GameRoomSnapshot::Log.from_owned(copy(h.events))
  game = GameRoomGames::DuckRacing.new(resources: h.resources)
  session = h.session.merge('__game_revision' => 'native-cas-1')
  expected = canonical(game.replay(session, events, repository))
  previous_calls = repository.actor_calls
  actual = game.replay(session.merge('__game_revision' => 'native-cas-2'), events, repository)
  assert_equal(previous_calls, repository.actor_calls, 'Unchanged sealed native log reauthenticated all rows')
  assert_equal(expected, canonical(actual))
  repository.generation = 'generation-2'
  game.replay(session, events, repository)
  assert_equal(previous_calls + events.length, repository.actor_calls, 'A new authority generation reused old authentication')
  assert(game.instance_variable_get(:@duck_replay_input).retention_bytes <= LOGIC::ReplayCache::MAX_BYTES)
  huge = {'id' => events.length + 1, 'actor' => 'Alice', 'action' => 'unrelated',
    'value' => 'x' * (LOGIC::ReplayCache::MAX_BYTES + 1)}
  # Mutable caller rows must be copied and count against cache ownership;
  # sealed rows are already owned/accounted for by the native bounded log.
  huge_events = copy(h.events) + [huge]
  game.replay(session, huge_events, repository)
  assert(game.instance_variable_get(:@duck_replay_input).nil?, 'Oversized owned input remained retained')
  assert_equal(expected, canonical(game.replay(session, events, repository)))
end

check.call('every partial fragment boundary remains inert until a complete authenticated action') do
  h = finished_fixture
  game = GameRoomGames::DuckRacing.new(resources: h.resources)
  (0..h.events.length).each do |count|
    prefix = h.events.first(count)
    actual = game.replay(h.session, prefix, h.repository)
    assert_equal(canonical(cold(h, h.session, prefix)), canonical(actual), "Partial prefix #{count}")
  end
  assert_equal(h.events.length, game.replay(h.session, h.events, h.repository).accepted_events.length)
end

check.call('MAX_PARTS action completes across the longest possible incomplete tail') do
  h = Harness.new
  random = Random.new(734)
  padding = Array.new(3_000) { random.rand(256) }.pack('C*').unpack1('H*')
  data = {'action' => 'start', 'revision' => 0, 'session' => h.session['__id'], 'seed' => 4,
    'at' => 1_000, 'fingerprint' => h.resources[:fingerprint]}
  commands = nil
  (100..padding.length).step(4) do |length|
    candidate = GameRoomActionPayload.commands('duck_racing', data.merge('padding' => padding[0, length]))
    if candidate.length == GameRoomActionPayload::MAX_PARTS
      commands = candidate
      break
    end
  end
  assert(commands, 'Fixture did not fill the maximum payload')
  rows = commands.each_with_index.map do |command, index|
    {'id' => index + 1, 'actor' => 'Alice', '__insertion_user' => 'Alice', '__authority_user' => 'Alice',
      'action' => command.action, 'value' => command.value}
  end
  assert_equal(nil, h.game.replay(h.session, rows.first(rows.length - 1), h.repository).state[:race])
  calls, actual = counted { h.game.replay(h.session, rows, h.repository) }
  assert_equal(1, calls)
  assert_equal(rows.length, actual.accepted_events.length)
  assert_equal(canonical(cold(h, h.session, rows)), canonical(actual))
end

check.call('a rejected old action is never retried on a later state, even inside the overlap') do
  h = Harness.new
  h.start
  old = {'action' => 'race', 'input' => {'kind' => 'roll'}, 'revision' => 1,
    'session' => h.session['__id'], 'at' => 1_000_000}
  rejected = GameRoomActionPayload.commands('duck_racing', old).map do |command|
    {'actor' => 'Alice', '__insertion_user' => 'Alice', '__authority_user' => 'Alice',
      'action' => command.action, 'value' => command.value}
  end
  rows = (rejected + copy(h.events)).each_with_index.map { |row, index| row.merge('__id' => index + 1, 'id' => index + 1) }
  first = same_as_cold(h, h.session, rows)
  assert_equal(1, first.state[:revision])
  rows << {'id' => rows.length + 1, 'actor' => 'Alice', 'action' => 'unrelated', 'value' => 'ignored'}
  calls, actual = counted { h.game.replay(h.session, rows, h.repository) }
  assert_equal(0, calls, 'An old rejected move was retried and could become legal')
  assert_equal(canonical(cold(h, h.session, rows)), canonical(actual))
  assert_equal(1, actual.state[:revision])
end

check.call('duplicate IDs and reused Hash references do not reapply an accepted action') do
  h = Harness.new
  h.start
  baseline = canonical(h.replay)
  duplicate = h.events + h.events
  actual = h.game.replay(h.session, duplicate, h.repository)
  assert_equal(baseline, canonical(actual))
  assert_equal(canonical(cold(h, h.session, duplicate)), canonical(actual))
  assert_equal(0, counted { h.game.replay(h.session, duplicate, h.repository) }.first)
end

event_mutations = {
  'old compressed payload' => ->(row) { row['value'] = row['value'].sub(/.$/, '?') },
  'claimed actor' => ->(row) { row['actor'] = 'Bob' },
  'authenticated author' => ->(row) { row['__insertion_user'] = 'Intruder' },
  'authority' => ->(row) { row['__authority_user'] = 'Bob' },
  'controller marker' => ->(row) { row['__controller'] = !row['__controller'] },
  'old ID' => ->(row) { row['__id'] += 20_000 },
  'archive provenance' => ->(row) { row['move_id'] = 'archive:modified' },
  'additional metadata' => ->(row) { row['new_metadata'] = {'nested' => ['changed']} }
}
event_mutations.each do |label, mutate|
  check.call("in-place change of #{label} invalidates the whole old prefix") do
    h = finished_fixture
    h.replay
    rows = copy(h.events)
    count, last_id = rows.length, rows.last['__id']
    mutate.call(rows[rows.length / 2])
    calls, actual = counted { h.game.replay(h.session, rows, h.repository) }
    assert(calls > 1, 'A modified prefix was not fully revalidated')
    assert_equal(count, rows.length)
    assert_equal(last_id, rows.last['__id'])
    assert_equal(canonical(cold(h, h.session, rows)), canonical(actual))
    same_as_cold(h)
  end
end

session_mutations = {
  'physical session' => ->(row) { row['__id'] += 1 },
  'table' => ->(row) { row['table_id'] += 1 },
  'options' => ->(row) { values = JSON.parse(row['options']); values['laps'] = 6; row['options'] = JSON.generate(values) },
  'roster' => ->(row) { row['__players'][1] = 'Replacement' },
  'owner' => ->(row) { row['__table_owner'] = 'Bob' },
  'control epoch' => ->(row) { row['__control_epoch'] = 'other-epoch' },
  'controllers' => ->(row) { row['__controllers'] = {'Bob' => 'bot'} },
  'pending transition' => ->(row) { row['__replay_participant_transitions'] = [{'id' => 90_000, 'seats' => [0]}] },
  'clock' => ->(row) { row['__clock_offset'] = 999; row['__frozen_at'] = 4 },
  'future authentication metadata' => ->(row) { row['authority_version'] = {'value' => 2} }
}
session_mutations.each do |label, mutate|
  check.call("change of #{label} cannot reuse a differently authorized model") do
    h = finished_fixture
    changed = copy(h.session)
    mutate.call(changed)
    calls, actual = counted { h.game.replay(changed, h.events, h.repository) }
    assert(calls > 1)
    assert_equal(canonical(cold(h, changed)), canonical(actual))
  end
end

check.call('repository interpretation of actors and IDs is authenticated afresh even with unchanged rows') do
  h = finished_fixture
  proxy = Object.new
  proxy.instance_variable_set(:@repository, h.repository)
  proxy.instance_variable_set(:@actor, nil)
  proxy.instance_variable_set(:@offset, 0)
  def proxy.players_for(session); @repository.players_for(session); end
  def proxy.actor_of(event, session); @actor || @repository.actor_of(event, session); end
  def proxy.event_id(event); @offset + @repository.event_id(event); end
  h.game.replay(h.session, h.events, proxy)
  assert_equal(0, counted { h.game.replay(h.session, h.events, proxy) }.first)
  proxy.instance_variable_set(:@actor, 'Intruder')
  changed = same_as_cold(h, h.session, h.events, proxy)
  assert_equal([], changed.accepted_events)
  proxy.instance_variable_set(:@actor, nil)
  proxy.instance_variable_set(:@offset, 4_000)
  same_as_cold(h, h.session, h.events, proxy)
end

check.call('callers may mutate every returned collection and RNG without poisoning canonical replay or input') do
  h = finished_fixture
  original_inputs = copy([h.session, h.events])
  expected = canonical(cold(h))
  returned = h.replay
  returned.players.first.replace('Edited player')
  returned.accepted_events.first['value'].replace('corrupt')
  returned.history.first.text.replace('changed')
  returned.history.clear
  returned.state[:race][:racers][0][:feathers] = 99_999
  returned.state[:race].each_value { |value| value.rand(99) if value.is_a?(Random) }
  returned.state[:last_resolution].clear
  returned.state[:options].clear
  returned.state.clear
  calls, again = counted { h.replay }
  assert_equal(0, calls)
  assert_equal(expected, canonical(again))
  assert_equal(original_inputs, [h.session, h.events])
end

check.call('historical prefixes cannot poison or evict the current longer prefix') do
  h = finished_fixture
  full = canonical(h.replay)
  [0, 2, h.events.length / 2, h.events.length - 1, 1].each do |length|
    same_as_cold(h, h.session, h.events.first(length))
    calls, actual = counted { h.replay }
    assert_equal(0, calls, 'Reading an older presentation unnecessarily evicted the current checkpoint')
    assert_equal(full, canonical(actual))
  end
end

check.call('deferred participant cancellation is applied to the view, not the append checkpoint') do
  h = Harness.new
  h.open_round
  h.begin_round
  before = h.replay
  status, plan = h.plan({'action' => 'alive', 'challenge' => before.state[:round][:challenge][:id]},
    actor: h.players.first, at: h.now_ms + 30_000, snapshot: before)
  assert_equal(:ok, status)
  h.session['__replay_participant_transitions'] = [{'id' => 90_000, 'seats' => [0]}]
  final_view = same_as_cold(h)
  assert_equal(:participant_changed, final_view.state[:last_resolution][:cancelled])
  h.append(plan, actor: h.players.first)
  actual = same_as_cold(h)
  assert_equal(h.events.length, actual.accepted_events.length, 'Deferred cancellation prematurely rejected a newly arrived earlier action')
end

check.call('actual participant projections retain old names, cancellation and subsequent new controller actions') do
  h = finished_fixture
  h.replace(1, 'Replacement')
  same_as_cold(h)
  old = copy(h.events)
  h.reach_save_boundary
  same_as_cold(h)
  assert_equal(old, h.events.first(old.length))
  prefix = h.events.first(old.length / 2)
  same_as_cold(h, h.session, prefix)
  same_as_cold(h)
end

check.call('mutating a returned historical participant entry cannot poison later views') do
  h = finished_fixture
  h.replace(1, 'Replacement')
  returned = h.replay
  returned.history.first.text.replace('tampered historical name')
  expected = cold(h).history.map(&:to_h)
  actual = h.replay.history.map(&:to_h)
  assert_equal(expected, actual, 'The participant wrapper reused a caller-owned history entry')
end

check.call('changed resource identity and localization catalogs invalidate cached presentation') do
  h = finished_fixture
  h.game.instance_variable_set(:@prepared_resources, h.resources.dup.freeze)
  assert(counted { h.replay }.first > 1, 'Different resource preparation reused the prior model')
  GameRoomLocalization.boot(host_language: 'en', settings: {'interface_language' => 'en', 'known_languages' => []})
  assert(counted { h.replay }.first > 1, 'Replaced catalogs reused old public text')
  actual = h.replay
  assert_equal(canonical(cold(h)), canonical(actual))
end

check.call('corrupt, removed, inserted and reordered old records never escape full revalidation') do
  h = finished_fixture(count: 4)
  baseline = copy(h.events)
  random = Random.new(49)
  80.times do |index|
    rows = copy(baseline)
    position = random.rand(rows.length)
    case index % 8
    when 0 then rows.delete_at(position)
    when 1 then rows.insert(position, copy(rows[position]))
    when 2 then rows[position]['value'] = 'not a payload'
    when 3 then rows[position]['__insertion_user'] = 'Impostor'
    when 4 then rows[position], rows[(position + 1) % rows.length] = rows[(position + 1) % rows.length], rows[position]
    when 5 then rows = rows.first(random.rand(rows.length + 1))
    when 6 then rows[position]['__controller'] = true; rows[position]['__authority_user'] = 'Impostor'
    when 7 then rows[position]['action'] = 'chat'; rows[position]['value'] = 'ordinary message'
    end
    same_as_cold(h, h.session, rows)
    same_as_cold(h, h.session, baseline)
  end
end

check.call('cache memory is bounded and oversized checkpoints do not truncate or change rules') do
  cache = LOGIC::ReplayCache.new
  h = Harness.new
  input = LOGIC::ReplayCache::Input.new(h.session, [], h.repository)
  limit = LOGIC::ReplayCache::MAX_BYTES
  large = 'x' * (limit + 1)
  result = cache.reduce(input, context: []) { |previous, prefix| assert_equal(nil, previous); assert_equal(0, prefix); [large] }
  assert_equal(limit + 1, result.first.bytesize)
  assert_equal(nil, cache.instance_variable_get(:@entry))
  20.times do |index|
    current = LOGIC::ReplayCache::Input.new(h.session.merge('__id' => index + 1), [], h.repository)
    cache.reduce(current, context: []) { [{index: index}] }
    entry = cache.instance_variable_get(:@entry)
    assert(entry.checkpoint.frozen? && entry.signature.frozen? && entry.key.frozen?)
    assert_equal([{index: index}], entry.checkpoint.restore)
  end
  assert(!cache.instance_variables.any? { |key| key.to_s.include?('entries') }, 'Cache unexpectedly retained multiple sessions')
end

check.call('out-of-order concurrent completion cannot replace a newer session checkpoint') do
  cache = LOGIC::ReplayCache.new
  h = Harness.new
  first = LOGIC::ReplayCache::Input.new(h.session, [], h.repository)
  second = LOGIC::ReplayCache::Input.new(h.session.merge('__id' => 999), [], h.repository)
  entered, release = Queue.new, Queue.new
  worker = Thread.new do
    cache.reduce(first, context: []) { entered << true; release.pop; ['older'] }
  end
  entered.pop
  cache.reduce(second, context: []) { ['newer'] }
  release << true
  assert_equal(['older'], worker.value)
  result = cache.reduce(second, context: []) { |previous, _| assert_equal(['newer'], previous); previous }
  assert_equal(['newer'], result)
end

report_dir = File.expand_path('../../../tmp/duck-racing', __dir__)
FileUtils.mkdir_p(report_dir)
path = File.join(report_dir, 'replay-cache-local.json')
report = File.file?(path) ? JSON.parse(File.read(path)) : {'runs' => []}
failures = checks.count { |entry| entry[:status] == 'FAIL' }
report['runs'] << {scope: 'Local adversarial authenticated-prefix cache and actual Duck game replay; no live accounts',
  cases: checks, failures: failures}
File.write(path, JSON.pretty_generate(report) + "\n")
checks.each { |entry| puts "#{entry[:status]} #{entry[:name]}#{entry[:error] ? ': ' + entry[:error] : ''}" }
raise "#{failures} Duck replay cache checks failed" unless failures.zero?
puts "PASS #{checks.length} Duck replay cache scenarios"
