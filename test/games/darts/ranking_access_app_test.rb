require_relative '../../support/settings_widget'

module EltenLink
  module Apps; end
end

class DartsAccessApp < EltenGameRoom
  class << self
    def app_runtime; @runtime ||= Object.new; end
    def data_path; raise 'Ranking observation performed disk work'; end
  end
end

class DartsAccessProbe
  attr_accessor :state, :result
  attr_reader :checks
  def initialize; @checks = []; end
  def reset_access!; self.state = :unchecked; end
  def available?; state == :available; end
  def check_access(username:)
    raise 'The entry probe retained an earlier grant' if DartsAccessApp.darts_rankings_enabled?
    @checks << username
    self.state = result
    available?
  end
end

repository = Object.new
def repository.players_for(session); session.fetch('__players'); end
def repository.actor_of(event, _session); event.fetch('actor'); end
def repository.event_id(event); event.fetch('__id'); end
game = GameRoomGames::Darts.new
session = {'__players'=>['Alice'], '__statistics'=>{'id'=>'darts-access-1'},
  'options'=>JSON.generate(game.default_options.merge('rounds'=>3))}
events = [{'__id'=>1, 'created_at'=>1_800_000_001, 'actor'=>'Alice', 'action'=>'darts_start', 'value'=>'a' * 32}]
9.times do |index|
  events << {'__id'=>index + 2, 'created_at'=>1_800_000_002 + index, 'actor'=>'Alice',
    'action'=>'darts_throw', 'value'=>[index, 0, 0, 1000, 'm'].join(':')}
end
replay = game.replay(session, events, repository)
assert(replay.finished?, 'The production Darts reducer did not finish the fixture')

previous_developer = $developer_mode
previous_name = Session.method(:name)
account = 'Alice'
Session.define_singleton_method(:name) { account }
begin
  $developer_mode = true
  app = DartsAccessApp.new
  tables = DartsAccessProbe.new
  app.instance_variable_set(:@server_tables, tables)
  app.define_singleton_method(:run_network_task) { |*_args, **_options, &operation| operation.call }
  app.define_singleton_method(:darts_preferences) { {'public_rankings'=>true} }
  # Exercise the real entry binding, not just a replacement availability flag.
  tables.result = :stamp_required
  app.send(:check_server_table_access)
  assert(app.send(:statistics_observer_for, game).nil?, 'Denied tables created a Darts observer')
  tables.result = :available
  app.send(:check_server_table_access)
  assert(tables.checks == %w[Alice Alice], 'The entry did not probe the signed-in account')
  service = DartsAccessApp.darts_rankings_service
  assert(service, 'Developer mode with confirmed tables did not create Darts records')
  general_calls = []
  general = Object.new
  general.define_singleton_method(:observe) { |**payload| general_calls << payload }
  observer = app.send(:statistics_observer_for, game, service: general)
  assert(observer, 'The shared telemetry gate still hides the Darts observer')
  observer.call(session, replay)
  staged = service.instance_variable_get(:@staged)
  assert(staged.size == 1 && staged.values.first['publish'] == true, 'Completed Darts did not stage its record in developer mode')
  assert(general_calls.empty?, 'Enabling Darts also enabled general developer-mode statistics')
  next_session = session.merge('__statistics'=>{'id'=>'darts-access-2'})
  tables.state = :unavailable
  observer.call(next_session, replay)
  assert(staged.size == 1, 'A captured observer collected a result after table access failed')
  tables.result = :available
  app.send(:check_server_table_access)
  assert(DartsAccessApp.darts_rankings_service.equal?(service), 'Rechecking tables replaced the pending service')
  observer.call(next_session, replay)
  assert(staged.size == 2, 'The captured observer did not recover with table access')
  $developer_mode = false
  observer.call(next_session, replay)
  assert(general_calls.one?, 'Ordinary statistics no longer work outside developer mode')
  $developer_mode = true
  account = 'Bob'
  assert(!DartsAccessApp.darts_rankings_enabled?, 'Another account inherited the access decision')
  observer.call(session.merge('__statistics'=>{'id'=>'darts-access-3'}), replay)
  assert(staged.size == 2, 'An old callback staged an account-switched result')
ensure
  DartsAccessApp.stop_darts_rankings
  Session.define_singleton_method(:name, previous_name)
  $developer_mode = previous_developer
end
puts 'PASS Darts access integration: real entry probe binding and completed-game observer, developer uploads staged, table loss/recovery, account isolation and unchanged general-statistics policy'
