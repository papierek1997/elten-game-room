require_relative '../../support/darts_rankings'
require_relative '../../../lib/game_room_analytics_runtime'
require_relative '../../../lib/darts/rankings/runtime'
require 'tmpdir'

module EltenLink
  module Apps; end
end

module Session
  def self.name; 'Alice'; end
end

class DartsRuntimeApp
  extend GameRoomAnalyticsRuntime
  extend GameRoomDartsRankings::Runtime
  class << self
    attr_accessor :root
    def app_runtime; @runtime ||= Object.new; end
    def server_app_uuid; 'darts-runtime-test'; end
    def data_path; root || raise('Unexpected data access'); end
  end
end

previous = $developer_mode
begin
  $developer_mode = true
  assert(DartsRuntimeApp.darts_rankings_service.nil?, 'Developer mode created a Darts ranking service')
  DartsRuntimeApp.darts_rankings_tick
  assert(DartsRuntimeApp.instance_variable_get(:@darts_rankings_context).nil?, 'Developer mode retained an analytics context')
  $developer_mode = false
  Dir.mktmpdir('darts-ranking-runtime-') do |root|
    DartsRuntimeApp.root = root
    service = DartsRuntimeApp.darts_rankings_service
    assert(service && !service.last_error, 'Normal mode failed to create the ranking service')
    assert(service.publish_saved_records, 'Normal mode did not stage an account operation')
    service.flush(nil, upload:false)
    assert(service.last_error.nil?, "Actual analytics storage refused the Darts queue: #{service.last_error.inspect}")
    path = File.join(root, GameRoomDartsRankings::Service::PATH)
    assert(File.file?(path), 'Darts did not use its durable application storage file')
    before = File.binread(path)
    $developer_mode = true
    assert(DartsRuntimeApp.darts_rankings_service.nil?, 'Developer mode reused an enabled service')
    assert(!service.withdraw_public_records, 'An existing service staged a developer-mode publication')
    service.flush(nil, upload:false)
    DartsRuntimeApp.darts_rankings_tick
    assert(File.binread(path) == before, 'Developer mode changed the persisted ranking queue')
    DartsRuntimeApp.stop_darts_rankings
  end
ensure
  DartsRuntimeApp.stop_darts_rankings
  $developer_mode = previous
end
puts 'PASS Darts runtime: real queue storage, developer-mode creation and existing-service gates'
