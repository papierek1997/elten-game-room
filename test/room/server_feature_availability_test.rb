require_relative '../support/settings_widget'

module EltenLink
  module Apps; end
end

class AccessFeedbackApp < EltenGameRoom
  def self.app_runtime; @runtime ||= Object.new; end
  def self.data_path; raise 'Availability feedback did file work'; end
end

AccessFeedbackTables = Struct.new(:access_state) do
  def available?; access_state == :available; end
  def stamp_required?; access_state == :stamp_required; end
end

original_mode = $developer_mode
begin
  GameRoomLocalization.boot(settings: {'interface_language'=>'en'}, host_language:'en')
  app = AccessFeedbackApp.new
  tables = AccessFeedbackTables.new(:stamp_required)
  app.instance_variable_set(:@server_tables, tables)
  AccessFeedbackApp.server_table_access = tables
  notices, opened = [], []
  app.define_singleton_method(:alert) { |message| notices << message }
  app.define_singleton_method(:select_game) { |*| opened << :rankings; nil }
  AccessFeedbackApp.define_singleton_method(:refresh_tournament_deadlines) { opened << :deadlines }
  app.define_singleton_method(:run_table_screen) { |row| opened << [:table, row['game']] }
  # An entry refusal must happen before game/module lists and their workers.
  $developer_mode = false
  %i[stamp_required unavailable].each do |state|
    tables.access_state = state
    %i[show_leaderboards show_tournaments show_statistics show_general_statistics show_room_activity].each do |action|
      app.send(action)
      assert(notices.last.include?('developer mode'), "#{state}/#{action}: missing developer-mode guidance")
      assert(notices.last.include?('server table access'), "#{state}/#{action}: missing actual restriction")
    end
    assert(opened.empty?, 'A refused module opened a list, deadline task or reader')
    assert(!app.send(:game_join_allowed?, {'game'=>'axel_pong', 'tournament_match'=>{}}), 'A tournament-table join bypassed the entry restriction')
  end
  tables.access_state = :unchecked
  probes = 0
  app.define_singleton_method(:check_server_table_access) { |**| probes += 1; tables.access_state = :unavailable }
  app.send(:show_leaderboards)
  app.send(:show_leaderboards)
  assert(probes == 1 && opened.empty?, 'The first explicit entry failed to probe once, or a refused entry was retried repeatedly')
  notices.clear
  2.times { app.send(:announce_server_table_access) }
  assert(notices.one?, 'The same startup restriction was repeated')
  %w[tournaments rankings statistics invitations].each do |feature|
    assert(notices.first.include?(feature), "Startup omitted #{feature}")
  end
  app.send(:show_table_screen, {'game'=>'darts'})
  assert(opened == [[:table, 'darts']], 'Missing auxiliary tables prevented an ordinary table from opening')
  assert(notices.last.include?('will not send game statistics or ranking results'), 'Entering an ordinary table did not explain missing uploads')
  notices.clear
  tables.access_state = :available
  $developer_mode = true
  app.send(:announce_server_table_access)
  assert(notices.one? && notices.first.include?('Statistics are disabled in developer mode'), 'Confirmed tables were confused with developer statistics policy')
  assert(!notices.first.include?('without server table access'), 'The application claimed available tables were denied')
  app.send(:show_leaderboards)
  assert(opened.last == :rankings, 'Developer mode blocked table-authorized rankings')
  app.send(:show_statistics)
  assert(notices.last == GameRoomAvailability.statistics_disabled, 'Statistics entry did not explain its intentional dev-mode opt-out')
  app.send(:show_table_screen, {'game'=>'darts'})
  assert(notices.last.include?('Rankings remain available'), 'A developer Darts table falsely claimed its records could not be sent')
  app.send(:show_table_screen, {'game'=>'tic_tac_toe'})
  assert(notices.last == GameRoomAvailability.statistics_disabled, 'An ordinary developer table used irrelevant ranking guidance')
  $developer_mode = false
  notices.clear
  app.send(:show_table_screen, {'game'=>'darts'})
  app.send(:announce_server_table_access)
  assert(notices.empty?, 'An unrestricted session received an availability warning')

  # The same confirmed provider gates captured telemetry, without changing the
  # pre-entry widget policy or deleting its pending work.
  service = AccessFeedbackApp.statistics_service
  assert(service && service.visit, 'Confirmed ordinary statistics could not collect a visit')
  tables.access_state = :unavailable
  assert(!AccessFeedbackApp.analytics_enabled? && !service.visit && !service.flush,
    'A captured statistics service ignored the known table denial')
  tables.access_state = :available
  assert(AccessFeedbackApp.statistics_service.equal?(service) && service.visit, 'Recovered access replaced or lost the pending statistics context')
ensure
  AccessFeedbackApp.stop_analytics
  AccessFeedbackApp.stop_darts_rankings
  $developer_mode = original_mode
end
puts 'PASS shared availability: reason-specific module admission, no denied readers, ordinary-table entry notices, no repetition, dev-authorized Darts and captured telemetry recovery'
