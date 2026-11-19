require_relative '../support/settings_widget'
require_relative '../support/assertions'
require_relative '../support/temporary_directory'
require_relative '../support/tournament_tables'
include GameRoomTest::Assertions

T = GameRoomTournaments
stamp = EltenLink::Error.new(code: GameRoomServerTables::STAMP_REQUIRED, response: {'error'=>{'status'=>403}})
timeout = EltenLink::Error.new(code: 'timeout')
original_name = Session.method(:name)
original_account = Session.instance_variable_get(:@name)
original_token = Session.token
original_client = EltenLink::Client.method(:new)
original_clock = GameRoomClock.method(:now)
now = 1_800_000_000
fail_tables = nil
client = TournamentTablesTestSupport::MemoryClient.new do |method, path, _params|
  raise "Unexpected request: #{method} #{path}" unless method == 'GET' && path.match?(%r{/tables/(?:game_room_users|tournament_[a-z_]+)/rows\z})
  raise fail_tables if fail_tables
  {'rows'=>[]}
end
runtime = TestTaskRuntime.new('tournament-table-access')
app = Class.new(EltenGameRoom)
app.define_singleton_method(:app_runtime) { runtime }
EltenLink::Client.define_singleton_method(:new) { client }
GameRoomClock.define_singleton_method(:now) { now }
Session.singleton_class.attr_accessor :name

def coordinator(app)
  app.instance_variable_get(:@tournament_coordinator)
end

def tick(app, wait: false)
  app.instance_variable_set(:@tournament_coordination_tick_at, nil)
  app.tournament_coordination_tick
  wait_background_work(coordinator(app).instance_variable_get(:@worker)) if wait
end

begin
  GameRoomTest::TemporaryDirectory.create('tournament-table-access-') do |path|
    Session.name, Session.token = 'Alice', 'first-login'
    program = app.new
    program.define_singleton_method(:data_path) { path }
    app.start_tournament_coordination(program)
    assert_equal(nil, app.server_table_access)
    tick(app, wait: true)
    tick(app)
    assert(client.calls.any?, 'No directory read after login without opening Power Games')
    assert(client.calls.none? { |_, path, _| path.include?('/game_room_users/') }, 'Startup made an extra permission probe')
    assert_equal(nil, coordinator(app).last_error)

    fail_tables = timeout
    app.refresh_tournament_deadlines
    tick(app, wait: true)
    tick(app)
    assert_equal(timeout, coordinator(app).last_error.cause)
    after_timeout = client.calls.size
    now += 29
    tick(app)
    assert_equal(after_timeout, client.calls.size, 'Timeout bypassed the normal backoff')
    fail_tables = nil
    now += 1
    tick(app, wait: true)
    tick(app)
    assert(client.calls.size > after_timeout, 'A network failure prevented recovery')
    assert_equal(nil, coordinator(app).last_error)

    # An older successful explicit check is not evidence of recovery after
    # a later denial in the actual SDK table operation.
    tables = GameRoomServerTables.new(app)
    app.server_table_access = tables
    assert(tables.check_access(username: Session.name), 'Fixture did not confirm initial access')
    fail_tables = stamp
    before_denial = client.calls.size
    app.refresh_tournament_deadlines
    tick(app, wait: true)
    assert_equal(before_denial + 1, client.calls.size)

    identity = "elten-tournaments:#{app.server_app_uuid}"
    reference = {'author'=>'bob', 'publication_key'=>'missing-tournament'}
    metadata = {'version'=>2, 'backend_identity'=>identity, 'publication_ref'=>reference, 'recipient'=>'alice',
      'title'=>'Tournament fixture', 'game'=>'chess',
      'event_id'=>Digest::SHA256.hexdigest(JSON.generate(['tournament-start-v1', identity, reference]))}
    notification = Struct.new(:id, :app_uuid, :metadata, :sender).new(23, app.server_app_uuid, metadata, 'Bob')
    assert(app.receive_tournament_start(notification), 'Valid notification fixture was not queued')
    inbox = app.instance_variable_get(:@tournament_start_inbox)
    start_worker = inbox.instance_variable_get(:@worker)
    3.times do
      now += 300
      tick(app)
      app.tournament_starts_tick
    end
    assert_equal(before_denial + 1, client.calls.size, 'Denied background table work was retried')
    assert(!start_worker.busy?, 'Known refusal admitted notice verification')

    fail_tables = timeout
    assert(!tables.check_access(username: Session.name), 'Timeout was mistaken for a valid check')
    after_probe = client.calls.size
    tick(app)
    app.tournament_starts_tick
    assert_equal(after_probe, client.calls.size, 'A failed recheck cleared a confirmed refusal')

    fail_tables = nil
    assert(tables.check_access(username: Session.name), 'Fixture did not confirm recovered access')
    after_recovery = client.calls.size
    app.tournament_starts_tick
    assert(wait_background_work(start_worker), 'A fresh success did not resume notice verification')
    app.tournament_starts_tick
    assert(client.calls.size > after_recovery, 'No notice table request after recovery')
    tick(app)
    now += 30
    before_retry = client.calls.size
    tick(app, wait: true)
    tick(app)
    assert(client.calls.size > before_retry, 'Suspended directory work did not resume')

    fail_tables = stamp
    assert(!tables.check_access(username: Session.name), 'Stamp denial was mistaken for a valid check')
    after_explicit_denial = client.calls.size
    app.refresh_tournament_deadlines
    tick(app)
    assert_equal(after_explicit_denial, client.calls.size, 'Explicit refusal did not protect background work')

    # Rotating credentials for the same account cannot reuse the old result.
    old = coordinator(app)
    Session.token = 'second-login'
    fail_tables = nil
    tick(app, wait: true)
    assert(!old.equal?(coordinator(app)), 'A new login kept the denied worker')
    assert_equal(nil, app.server_table_access)
    assert(client.calls.size > after_explicit_denial, 'An earlier login suppressed a new bootstrap')
    tick(app)

    assert(tables.check_access(username: Session.name), 'Fixture did not confirm the new login')
    app.server_table_access = tables
    access = app.instance_variable_get(:@tournament_background_table_access)
    assert_equal(stamp, assert_raises(EltenLink::Error) do
      access.perform do
        assert(tables.check_access(username: Session.name), 'Concurrent check was not confirmed')
        raise stamp
      end
    end)
    assert(!access.blocked?, 'A late refusal overrode a newer successful check')

    # Permission failure can also arrive first from a notice validator.
    fail_tables = stamp
    before_notice = client.calls.size
    assert(app.receive_tournament_start(notification), 'The new login could not receive a notice')
    inbox = app.instance_variable_get(:@tournament_start_inbox)
    app.tournament_starts_tick
    assert(wait_background_work(inbox.instance_variable_get(:@worker)), 'The first notice request did not finish')
    assert_equal(before_notice + 1, client.calls.size)
    fail_tables = nil
    now += 300
    app.refresh_tournament_deadlines
    tick(app)
    app.tournament_starts_tick
    assert_equal(before_notice + 1, client.calls.size, 'Notice refusal did not suspend coordination')
  end
ensure
  app.stop_tournament_coordination
  runtime.close
  Session.name = original_account
  Session.token = original_token
  Session.define_singleton_method(:name, original_name)
  GameRoomClock.define_singleton_method(:now, original_clock)
  EltenLink::Client.define_singleton_method(:new, original_client)
end
puts 'PASS tournament background table access: cold login, network retry, verified refusal, independent recovery and fresh login'
