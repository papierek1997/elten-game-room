require_relative "support/settings_widget"
require_relative "support/host_source"
module Programs
  class ProgramError < StandardError; end
end
%w[eltenlink/client eltenlink/apps eapi/tasks eapi/scheduler eapi/extensions].each do |source|
  require File.join(EltenTestHost.root, "src", source)
end

original_name = Session.method(:name)
original_client = EltenLink::Client.method(:new)
original_queue = GameRoomStatistics::Queue.method(:new)
original_warning = Log.method(:warning)
original_developer_mode = $developer_mode
calls, warnings = [], []
account = "Alice"
Session.define_singleton_method(:name) { account }
EltenLink::Client.define_singleton_method(:new) do |*args|
  calls << :client
  original_client.call(*args).tap do |client|
    client.define_singleton_method(:api_data) { |*_args, **_options| calls << :raw_sdk; raise "Unexpected telemetry SDK request" }
  end
end
GameRoomStatistics::Queue.define_singleton_method(:new) do |**options|
  calls << :queue
  original_queue.call(**options)
end
Log.define_singleton_method(:warning) { |message| warnings << message }

begin
  %w[Alice papierek].each do |user|
    account = user
    data = {}
    factory = Class.new(EltenGameRoom)
    factory.define_singleton_method(:app_runtime) { :runtime }
    factory.define_singleton_method(:server_app_uuid) { "11111111-1111-4111-8111-111111111111" }
    factory.define_singleton_method(:read_json) do |path, default:|
      calls << :read_storage
      JSON.parse(JSON.generate(data.fetch(path, default)))
    end
    factory.define_singleton_method(:update_json) do |path, default:, &operation|
      calls << :write_storage
      state = JSON.parse(JSON.generate(data.fetch(path, default)))
      operation.call(state)
      data[path] = state
    end
    app = factory.new
    app.define_singleton_method(:live_sessions) { calls << :endpoint; raise "Development telemetry opened gameplay endpoint" }
    app.define_singleton_method(:alert) { |_message| calls << :alert }
    $developer_mode = true
    calls.clear
    assert(factory.statistics_service.nil? && factory.room_presence_collector.nil?,
      "Development mode constructed telemetry services for #{user}")
    app.send(:record_statistics_visit)
    app.send(:register_room_presence)
    assert(calls.empty? && warnings.empty?, "Development mode touched telemetry storage, queue, client or error reporting")

    $developer_mode = false
    service = factory.statistics_service
    collector = factory.room_presence_collector
    assert(service && collector && factory.analytics_enabled?, "Normal mode no longer initializes analytics")
    game = Struct.new(:id).new("tic_tac_toe")
    session = {"__id" => 7, "__players" => [user, "Bob"], "__statistics" => {
      "id" => "22222222-2222-4222-8222-222222222222", "mode" => "humans", "started_at" => 1_790_294_400}}
    replay = Struct.new(:finished?).new(false)
    observer = app.send(:statistics_observer_for, game, service: service)
    start = -> { app.send(:record_statistics_start, session, game, service: service) }
    app.send(:record_statistics_visit)
    assert(!data.fetch(GameRoomStatistics::Queue::PATH).fetch("accounts").fetch(user.downcase).fetch("pending").empty?,
      "Normal mode did not preserve a pending visit for the disable test")
    collector.register do |_token|
      calls << :source_snapshot
      [LobbyRepository::TableSnapshot.new(table: {"__statistics_room_id" => "33333333-3333-4333-8333-333333333333",
        "game" => game.id, "status" => "waiting", "private" => true}, members: [user, "Bob"], bots: [], observers: ["Bob"])]
    end
    collector.store.define_singleton_method(:publish) { |rooms, **_options| calls << :presence_publish; true }
    service.store.define_singleton_method(:write_batch) { |entries, **_options| calls << :statistics_publish; true }
    pending = JSON.generate(data)

    definitions = []
    extension = Object.new
    extension.define_singleton_method(:trigger) { |_key| calls << :trigger }
    factory.define_singleton_method(:extension) do |name, &registration|
      definition = Programs::Extensions::Definition.new(name)
      registration.call(definition)
      definitions << definition.finalize!
      extension
    end
    factory.activate
    schedules = definitions.first.schedules.select { |definition| %w[statistics_upload room_presence].include?(definition.key) }
    assert(schedules.length == 2, "Telemetry lifecycle schedules are missing")
    context = Struct.new(:token).new(EltenAPI::Tasks::CancellationToken.new)
    $developer_mode = true
    calls.clear
    warnings.clear
    assert(factory.statistics_service.nil? && factory.room_presence_collector.nil?, "Development mode returned cached telemetry")
    observer.call(session, replay)
    start.call
    app.send(:record_statistics_visit)
    app.send(:register_room_presence)
    schedules.each { |definition| definition.callback.call(context) }
    collector.heartbeat(context.token)
    assert(app.send(:read_statistics) { calls << :report; service.store.report(nil) }.nil?,
      "Explicit statistics read did not return unavailable in development mode")
    assert(calls.empty?, "Disabled telemetry touched captured callbacks, snapshots, storage or publications: #{calls.inspect}")
    assert(warnings.empty?, "Expected development disable emitted sending-error messages")
    assert(JSON.generate(data) == pending, "Disabling analytics deleted or modified normal-mode pending history")

    $developer_mode = false
    assert(factory.statistics_service.equal?(service) && factory.room_presence_collector.equal?(collector),
      "Returning to normal mode discarded the pending services")
    observer.call(session, replay)
    start.call
    assert(calls.include?(:write_storage), "Normal-mode captured observers no longer enqueue")
    schedules.each { |definition| definition.callback.call(context) }
    assert(calls.include?(:source_snapshot) && calls.include?(:presence_publish) && calls.include?(:statistics_publish),
      "Normal-mode scheduled telemetry no longer works")
    assert(data.fetch(GameRoomStatistics::Queue::PATH).fetch("accounts").fetch(user.downcase).fetch("pending").empty?,
      "Normal-mode upload did not acknowledge preserved history")
  end
ensure
  $developer_mode = original_developer_mode
  Session.define_singleton_method(:name, original_name)
  EltenLink::Client.define_singleton_method(:new, original_client)
  GameRoomStatistics::Queue.define_singleton_method(:new, original_queue)
  Log.define_singleton_method(:warning, original_warning)
end
puts "PASS development-mode telemetry suppression, captured callbacks, preserved pending history and normal-mode recovery (member and author)"
