require_relative '../support/statistics_screen'
require_relative '../support/quiz_creator_native'
require EltenTestHost.file('src/ui/controls/table_box.rb')
Object.const_set(:TableBox, EltenAPI::Controls.const_get(:TableBox)) unless Object.const_defined?(:TableBox)
require EltenTestHost.file('src/eapi/server_clock.rb')
require_relative '../../lib/game_statistics_screen'

# The host clock is real. Only the authenticated account and the already
# received sample are local fixtures; no HTTP or running client is used.
Session = Struct.new(:name, :token).new('Alice', 'token-one') unless Object.const_defined?(:Session)
Session.name = 'Alice'
Session.token = 'token-one'
def Session.logged?; true; end

module StatisticsNativeClockBoundary
  def self.assert(value, message)
    raise message unless value
    @checks = @checks.to_i + 1
  end

  def self.sample(time)
    clock = EltenAPI::ServerClock
    tick = clock.send(:monotonic_time)
    key = [Session.name, Session.token]
    request = clock.const_get(:Request).new(key, tick - 0.01, nil)
    clock.instance_variable_set(:@key, key)
    clock.instance_variable_set(:@request, request)
    clock.send(:complete, request, time, tick)
  end

  GameRoomLocalization.boot(host_language: 'en', settings: {'interface_language' => 'en'})
  EltenAPI::ServerClock.send(:start)
  registry = Object.new
  registry.define_singleton_method(:ids) { ['quiz'] }
  registry.define_singleton_method(:name) { |_id| 'Quiz' }
  reads, years, visits = [], [], 0
  snapshot = {'visitors' => 9, 'players' => 4, 'started' => 2, 'completed' => 1,
    'games' => [], 'first_day' => 20261201, 'partial' => false}
  Form.driver = lambda do |form|
  settle_statistics(form)
    visits += 1
    summary, periods, table, refresh = form.fields.first(4)
    assert(periods.is_a?(EltenAPI::Controls::ListBox) && table.is_a?(EltenAPI::Controls::TableBox),
      'Clock regression did not exercise native controls')
    assert(EltenAPI::ServerClock.now.nil? && reads.empty? && years.empty?, 'Cold host clock fabricated a date or read tables')
    assert(summary.text.include?('Statistics could not be loaded.') && table.rows.empty? && periods.options.empty?,
      'Cold native clock did not reach an unavailable but usable form')
    form.index = 2
    form.accept_button.trigger(:press)
    assert(visits == 1, 'Empty unavailable table opened invented details')

    sample(Time.utc(2026, 12, 31, 23, 30)) # January 1 in Warsaw, not December 31.
    refresh.trigger(:press)
    settle_statistics(form)
    assert(reads.last.key == 'today' && reads.last.to_day == 20270101 && years == [20270101],
      'Recovered default clock did not use its confirmed Warsaw date')
    periods.index = periods.options.index('2026')
    periods.trigger(:move)
    settle_statistics(form)
    assert(reads.last.key == 'year_2026', 'Native period selection failed')
    before = [reads.length, years.length]

    # A token change invalidates the native anchor even for the same username.
    Session.token = 'token-two'
    assert(EltenAPI::ServerClock.now.nil?, 'Native account-token invalidation did not invalidate the fixture anchor')
    refresh.trigger(:press)
    settle_statistics(form)
    assert([reads.length, years.length] == before && periods.options.empty? && table.rows.empty?,
      'Lost native clock performed undated reads or retained old results')
    assert(!summary.text.include?('Visitors: 9') && !summary.text.include?('2027-01-01'),
      'Clock loss left a plausible stale report on the native screen')
    periods.trigger(:move)
    settle_statistics(form)
    form.accept_button.trigger(:press)
    assert([reads.length, years.length] == before && visits == 1, 'Empty native selection or Enter caused work')

    sample(Time.utc(2027, 1, 2, 12, 0))
    refresh.trigger(:press)
    settle_statistics(form)
    assert(reads.last.key == 'year_2026' && periods.options[periods.index] == '2026',
      'Recovery failed to retain calendar-year identity across a missing native clock')
    assert(summary.text.include?('2026-01-01 to 2026-12-31') && summary.text.include?('Visitors: 9'),
      'Recovery mixed the retained period with the new current date')
    assert(form.instance_variable_get(:@timers).to_a.empty?, 'Recovery added unsolicited polling')
    form.cancel_button.trigger(:press)
  end
  GameRoomStatisticsScreen.new(program: Object.new, registry: registry,
    reader: ->(period, _token) { reads << period; snapshot },
    years_reader: ->(_token) { years << GameRoomStatistics::Periods.today.strftime('%Y%m%d').to_i; [2026] }).run
  assert(reads.map(&:key) == %w[today year_2026 year_2026], 'Unexpected duplicate report reads across recovery')
  puts "PASS independent native statistics clock boundary: #{@checks} checks"
ensure
  EltenAPI::ServerClock.send(:stop)
end
