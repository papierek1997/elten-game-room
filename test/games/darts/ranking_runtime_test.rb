require_relative '../../support/darts_rankings'
require_relative '../../../lib/game_room_analytics_runtime'
require_relative '../../../lib/darts/rankings/runtime'
require 'tmpdir'

module EltenLink
  module Apps
    class << self
      attr_accessor :backend
      def schema(*args); backend.schema(*args); end
      def table(*args); backend.table(*args); end
    end
  end
end

module Session
  def self.name; 'Alice'; end
  def self.token; 'darts-ranking-fixture-token'; end
end

TableAccess = Struct.new(:state) do
  def available?; state == :available; end
end

class DartsRuntimeApp
  extend GameRoomAnalyticsRuntime
  extend GameRoomDartsRankings::Runtime
  class << self
    attr_accessor :root, :runtime
    def app_runtime; self.runtime ||= Object.new; end
    def server_app_uuid; 'darts-runtime-test'; end
    def data_path; root || raise('Unexpected data access'); end
  end
end

previous = $developer_mode
begin
  [false, true].each do |developer|
    $developer_mode = developer
    assert(DartsRuntimeApp.darts_rankings_service.nil?, 'Unknown access created a Darts ranking service')
    tables = TableAccess.new(:unchecked)
    DartsRuntimeApp.server_table_access = tables
    %i[unchecked stamp_required unavailable].each do |state|
      tables.state = state
      assert(DartsRuntimeApp.darts_rankings_service.nil?, "#{developer}/#{state}: denied access created a service")
      DartsRuntimeApp.darts_rankings_tick
      assert(DartsRuntimeApp.instance_variable_get(:@darts_rankings_context).nil?, 'Denied access retained a new context')
    end
    Dir.mktmpdir('darts-ranking-runtime-') do |root|
      api = EltenLink::Apps.backend = DartsRankingMemoryApi.new
      DartsRuntimeApp.root = root
      tables.state = :available
      service = DartsRuntimeApp.darts_rankings_service
      assert(service && !service.last_error, "#{developer}: confirmed table access failed to create the service")
      assert(service.publish_saved_records, 'Confirmed access did not stage an account operation')
      record = ranking_row("runtime-#{developer}", score:200, time:5000)
      assert(service.send(:enqueue, result_operation(record, publish:true)), 'The result was not staged')
      service.flush(nil, upload:false)
      assert(service.last_error.nil?, "Actual analytics storage refused the Darts queue: #{service.last_error.inspect}")
      path = File.join(root, GameRoomDartsRankings::Service::PATH)
      assert(File.file?(path), 'Darts did not use its durable application storage file')
      before = File.binread(path)
      $developer_mode = !developer
      assert(DartsRuntimeApp.darts_rankings_service.equal?(service), 'Changing developer mode disabled table-authorized Darts')
      tables.state = :stamp_required
      assert(DartsRuntimeApp.darts_rankings_service.nil?, 'Lost table access returned an enabled service')
      assert(!service.withdraw_public_records, 'A captured service staged a publication without table access')
      service.flush(nil, upload:false)
      assert(!service.flush, 'A captured worker uploaded after access was denied')
      DartsRuntimeApp.darts_rankings_tick
      assert(File.binread(path) == before, 'Lost access changed the persisted ranking queue')
      assert(api.table_object.rows.empty? && api.personal_tables.empty?, 'Denied access reached the tables')
      begin
        service.store.ranking(difficulty:'normal', category:'triple')
        raise 'A captured store read a ranking without table access'
      rescue GameRoomDartsRankings::Unavailable
      end
      begin
        service.store.highest_unlocked_difficulty
        raise 'A captured store read personal progress without table access'
      rescue GameRoomDartsRankings::Unavailable
      end
      tables.state = :available
      assert(DartsRuntimeApp.darts_rankings_service.equal?(service), 'Restoring access discarded the pending service')
      assert(File.binread(path) == before, 'Restoring access lost the durable queue')
      assert(service.flush && !service.last_error, "Recovered Darts upload failed: #{service.last_error.inspect}")
      assert(api.table_object.rows.one? && api.personal_table.rows.one?, 'Recovery did not upload public and personal records')
      assert(service.store.ranking(difficulty:'normal', category:'triple').first['best_round_score'] == 200,
        'Table-authorized runtime could not read its uploaded record')
      assert(service.flush && api.table_object.rows.one?, 'An upload retry duplicated the public record')
      old_runtime = DartsRuntimeApp.runtime
      DartsRuntimeApp.runtime = Object.new
      assert(DartsRuntimeApp.darts_rankings_service.nil?, 'A new runtime inherited the old table-access decision')
      assert(!service.publish_saved_records, 'The old runtime staged a new operation')
      DartsRuntimeApp.runtime = old_runtime
      DartsRuntimeApp.stop_darts_rankings
      DartsRuntimeApp.server_table_access = nil
    end
  end
ensure
  DartsRuntimeApp.stop_darts_rankings
  $developer_mode = previous
end
puts 'PASS Darts runtime: both launch modes, unchecked/denied/available tables, cached service/store gates, preserved queue, actual uploads and runtime isolation'
