require_relative '../support/quiz_creator_native'
require_relative '../support/native_tasks'
require EltenTestHost.file('src/ui/controls/table_box.rb')
Object.const_set(:TableBox, EltenAPI::Controls.const_get(:TableBox)) unless Object.const_defined?(:TableBox)
require_relative '../../lib/sports_rankings/screen'
require_relative '../../lib/game_statistics_screen'

GameRoomLocalization.boot(host_language: 'en', settings: {'interface_language'=>'en'})
module Session
  def self.name; @sports_user || 'Alice'; end
  def self.sports_user=(value); @sports_user=value; end
end
module GameRoomClock
  def self.synchronize; true; end
end

def sports_frame(form)
  EltenAPI::KeyboardState.update(raw_state: "\0"*256, events: [], now: Process.clock_gettime(Process::CLOCK_MONOTONIC))
  $input_frame_serial = $input_frame_serial.to_i + 1
  $keyboard_state_frame_serial, $keyboard_state_frame_thread = $input_frame_serial, Thread.current
  $activecontrols = []
  form.update
end

def settle_sports(form)
  Timeout.timeout(5) do
    loop do
      sports_frame(form)
      break unless form.fields.first.text == 'Loading statistics'
      Thread.pass
    end
  end
end

runtime = TestTaskRuntime.new('sports-statistics-ui')
program = Object.new
program.class.define_singleton_method(:app_runtime) { runtime }
program.class.define_singleton_method(:analytics_enabled?) { $developer_mode != true }
ui, calls = Thread.current, []
warnings = []
original_developer_mode = $developer_mode
original_warning = Log.method(:warning)
Log.define_singleton_method(:warning) { |message| warnings << message }
rows = [{'user'=>'Alice','won'=>4,'lost'=>2,'scored'=>45,'conceded'=>31},
  {'user'=>'Bob','won'=>1,'lost'=>5,'scored'=>20,'conceded'=>50}]
store = Object.new
store.define_singleton_method(:report) do |**options|
  raise 'Statistics network read ran on the UI thread' if Thread.current == ui
  calls << options
  rows.map(&:dup)
end
day = ->(date) { date.strftime('%Y%m%d').to_i }
matches = [[%w[Alice], %w[Bob], Date.new(2026,10,24)], [%w[Bob], %w[Alice], Date.new(2026,10,14)],
  [%w[Alice], %w[Carol], Date.new(2026,7,1)]].map do |winner, loser, date|
  {'day_key'=>day.call(date), 'winner'=>0, 'sides'=>[{'players'=>winner, 'goals'=>11}, {'players'=>loser, 'goals'=>4}]}
end
personal_calls = []
store.define_singleton_method(:personal) do |**options|
  raise 'Head-to-head network read ran on the UI thread' if Thread.current == ui
  personal_calls << options
  GameRoomSportsRankings::Personal.summary(matches, user: options.fetch(:player), today: options.fetch(:today))
end
game = Struct.new(:id, :name).new('axel_pong', 'Axel Pong')
build_screen = -> {
  GameRoomSportsRankings::Screen.new(program:program,game:game,
    service:Struct.new(:store).new(store),today:-> {Date.new(2026,10,24)})
}
screen = build_screen.call
screen.instance_variable_set(:@mode, 'singles')
screen.define_singleton_method(:input_user) { |_header| 'Bob' }
Form.driver = lambda do |form|
  field, opponents, period, choose_player, own, refresh = form.fields
  assert(field.is_a?(EditBox) && (field.flags & EditBox::Flags::ReadOnly) != 0, 'Statistics are not read-only text')
  assert(period.options == ['All time','Last 7 days','Last 30 days','Last six months','Last year'], 'Statistics period choices differ')
  settle_sports(form)
  assert(field.header == 'Alice: All time', 'The initial report is not the current account across all recorded history')
  assert(field.text.lines.size == 7 && field.text.lines.first.chomp == "Matches played: 6" && field.text.include?('Matches won: 4') &&
    field.text.include?("Goal balance: 14"), "A requested counter is missing: #{field.text.inspect}")
  assert(!field.text.match?(/ranking|place|points/i), 'Statistics still expose a ranking')
  # The opponents list sits below the counters and counts the selected period.
  assert(opponents.is_a?(TableBox) && opponents.rows == [%w[Bob 2 1 1], %w[Carol 1 1 0]], "Opponents differ: #{opponents.rows.inspect}")
  assert(personal_calls.last.values_at(:player, :mode, :today) == ['Alice', 'singles', Date.new(2026,10,24)], 'Head-to-head read the wrong scope')
  opened = []
  screen.define_singleton_method(:show_head_to_head) { |entry| opened << entry.fetch('players') }
  form.index = 0
  form.accept_button.trigger(:press)
  assert(opened.empty?, 'Enter outside the opponents list opened head-to-head')
  form.index, opponents.index = 1, 1
  form.accept_button.trigger(:press)
  assert(opened == [%w[Carol]], 'Enter on an opponent did not open that head-to-head')
  form.index = 2
  period.index = 1
  period.trigger(:move)
  settle_sports(form)
  assert(calls.last.values_at(:from_day,:to_day)==[20261018,20261024], 'The seven-day period is not inclusive')
  assert(form.index == 2 && period.index == 1, 'A completed read stole focus from the period selector')
  assert(opponents.rows == [%w[Bob 1 1 0]], 'The opponents list ignored the selected period')
  choose_player.trigger(:press)
  settle_sports(form)
  assert(field.header == 'Bob: Last 7 days' && field.text.include?('Matches won: 1'), 'Selecting another player did not replace the report')
  assert(opponents.rows == [%w[Alice 1 0 1]], "The opponents list did not follow the chosen player: #{opponents.rows.inspect}")
  own.trigger(:press)
  settle_sports(form)
  assert(field.header == 'Alice: Last 7 days' && field.text.include?('Matches won: 4'), 'My statistics did not restore the signed-in player')
  refresh.trigger(:press)
  settle_sports(form)
  assert(calls.last[:fresh], 'Explicit Refresh reused the old snapshot')
  assert(screen.send(:range,3,Date.new(2026,10,24))==[20260425,20261024], 'The six-month calendar period differs')
  form.cancel_button.trigger(:press)
end

begin
  Programs.with_runtime(runtime) { screen.send(:show_statistics) }
  assert(calls.first[:from_day].nil?, 'The default report omitted recorded history')

  # Head-to-head details list every period for the selected opponent.
  screen = build_screen.call
  screen.instance_variable_set(:@player, 'Alice')
  Form.driver = lambda do |form|
    field = form.fields.first
    assert(field.header == 'Alice against Bob' && field.text.lines.map(&:chomp) == ['All time: won 1, lost 1, played 2',
      'Last 7 days: won 1, lost 0, played 1', 'Last 30 days: won 1, lost 1, played 2', 'Last six months: won 1, lost 1, played 2',
      'Last year: won 1, lost 1, played 2'], "Head-to-head details differ: #{[field.header, field.text].inspect}")
    form.cancel_button.trigger(:press)
  end
  bob = GameRoomSportsRankings::Personal.summary(matches, user: 'Alice', today: Date.new(2026,10,24))[1]
  Programs.with_runtime(runtime) { screen.send(:show_head_to_head, bob) }

  # Keep only the latest selection while the first bounded read is pending.
  gate, entered = Queue.new, Queue.new
  held = true
  store.define_singleton_method(:report) do |**options|
    calls << options
    if held
      held = false
      entered << options[:cancellation_token]
      gate.pop
    end
    rows.map(&:dup)
  end
  screen = build_screen.call
  screen.instance_variable_set(:@mode,'doubles')
  Form.driver = lambda do |form|
    Timeout.timeout(5) { entered.pop }
    before = calls.size
    period = form.fields[2]
    [1,2,3,4,1].each { |index| period.index=index; period.trigger(:move) }
    assert(calls.size==before, 'Rapid selections launched overlapping network reads')
    gate << true
    settle_sports(form)
    assert(calls.size==before+1 && calls.last[:mode]=='doubles' && calls.last[:from_day]==20261018,
      'The final selection was dropped or intermediate selections were queried')
    assert(form.fields.first.header=='Alice: Last 7 days', 'A stale read replaced the current report')
    form.cancel_button.trigger(:press)
  end
  Programs.with_runtime(runtime) { screen.send(:show_statistics) }

  # A read error must not become a six-zero report; Refresh can recover.
  unavailable = true
  store.define_singleton_method(:report) do |**_options|
    raise GameRoomSportsRankings::Unavailable, 'offline' if unavailable
    []
  end
  screen = build_screen.call
  screen.instance_variable_set(:@mode,'singles')
  Form.driver = lambda do |form|
    settle_sports(form)
    assert(form.fields.first.text=='Player statistics are unavailable. Try Refresh.', 'Failure became zero statistics')
    assert(form.fields[1].rows.empty? && form.fields[1].empty_label=='Player statistics are unavailable. Try Refresh.',
      'A failed read left an empty-looking opponents list')
    unavailable = false
    form.fields[5].trigger(:press)
    settle_sports(form)
    assert(form.fields.first.text.include?('Matches won: 0'), 'An empty successful report is not distinct from an error')
    form.cancel_button.trigger(:press)
  end
  Programs.with_runtime(runtime) { screen.send(:show_statistics) }
  assert(warnings==['Player statistics read failed: GameRoomSportsRankings::Unavailable'], 'Unexpected or missing read-error diagnostics')

  # Changing accounts closes the old view and cancels its pending read.
  token = nil
  store.define_singleton_method(:report) do |**options|
    entered << options[:cancellation_token]
    gate.pop
    rows.map(&:dup)
  end
  screen = build_screen.call
  screen.instance_variable_set(:@mode,'singles')
  Form.driver = lambda do |form|
    form.instance_variable_set(:@wait,true)
    token = Timeout.timeout(5) { entered.pop }
    Session.sports_user = 'Bob'
    sports_frame(form)
    assert(!form.instance_variable_get(:@wait), 'Account change left the old report open')
    form.cancel_button.trigger(:press)
    gate << true
  end
  Programs.with_runtime(runtime) { screen.send(:show_statistics) }
  assert(token.cancelled?, 'Closing statistics did not cancel the pending request')
  Session.sports_user = 'Alice'

  # The same host-mode predicate also invalidates a captured player-statistics
  # view. Its pending normal-mode read is cancelled, not shown as a send error.
  screen = build_screen.call
  screen.instance_variable_set(:@mode, 'singles')
  Form.driver = lambda do |form|
    form.instance_variable_set(:@wait, true)
    token = Timeout.timeout(5) { entered.pop }
    $developer_mode = true
    form.fields[5].trigger(:press)
    sports_frame(form)
    assert(!form.instance_variable_get(:@wait), 'Developer mode kept the old sports statistics view open')
    form.cancel_button.trigger(:press)
    gate << true
  end
  Programs.with_runtime(runtime) { screen.send(:show_statistics) }
  assert(token.cancelled?, 'Developer mode did not cancel the pending statistics read')
  unavailable_messages = []
  screen = build_screen.call
  screen.define_singleton_method(:alert) { |message| unavailable_messages << message }
  screen.define_singleton_method(:choose) { |*_, **_| raise 'Developer mode opened the sports selector' }
  Programs.with_runtime(runtime) { screen.run }
  assert(unavailable_messages == ['Player statistics are temporarily unavailable.'], 'Developer mode did not report statistics as unavailable')
  $developer_mode = original_developer_mode

  # The common Statistics entry routes General and opt-in games independently.
  opened = []
  client = Struct.new(:key,:opened) do
    def run; opened << key; end
    def close; opened << :closed; end
  end
  statistic_game = Struct.new(:id,:name,:enabled,:factory) do
    def supports_player_statistics?; enabled; end
    def build_player_statistics_client(_program); factory.call; end
  end
  games = [statistic_game.new('krowa','Krowa',false,nil),
    statistic_game.new('axel_pong','Axel Pong',true,-> {client.new(:pong,opened)}),
    statistic_game.new('audio_ball','Audio Ball',true,-> {client.new(:ball,opened)})]
  registry = Object.new
  registry.define_singleton_method(:ids) { games.map(&:id) }
  registry.define_singleton_method(:build) { |id| games.find { |value| value.id==id } }
  Form.driver = lambda do |form|
    list = form.fields.first
    assert(list.options==['General','Axel Pong','Audio Ball'], 'Statistics did not separate program activity from player results')
    3.times { |index| list.index=index; form.accept_button.trigger(:press) }
    form.cancel_button.trigger(:press)
  end
  Programs.with_runtime(runtime) do
    GameRoomStatisticsMenu.new(program:program,registry:registry,general:-> {opened << :general}).run
  end
  assert(opened==[:general,:pong,:closed,:ball,:closed], 'The Statistics menu routed or closed the wrong client')
ensure
  $developer_mode = original_developer_mode
  Session.sports_user = 'Alice'
  gate << true if gate
  screen.close
  runtime.close
  Log.define_singleton_method(:warning, original_warning)
end
puts 'PASS native sports statistics: routing, seven counters, opponents list and head-to-head, periods, responsive reads, coalescing, errors, focus, account/developer-mode cancellation and disabled entry'
