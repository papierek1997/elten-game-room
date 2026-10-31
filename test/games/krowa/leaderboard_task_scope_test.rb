require_relative '../../support/room_interface'
require_relative '../../support/krowa_services'
require_relative '../../../games/krowa_support/leaderboards'

# Keep native Tasks and the real client/store. Only the host event tick and
# visible controls use the same deterministic headless boundary as room tests.
def loop_update(*_arguments); Thread.pass; end

class TableBox < ListBox
  attr_reader :columns, :rows
  def initialize(columns, rows, **options)
    @columns, @rows = columns, rows
    super(rows, **options)
  end
end

GameRoomClock.define_singleton_method(:synchronize) { true }
GameRoomClock.define_singleton_method(:synchronized?) { true }
GameRoomClock.define_singleton_method(:now) { Time.utc(2026, 10, 18, 12).to_f }

class RankingScopeFixture
  attr_reader :calls, :views, :alerts, :client, :menus

  def initialize(failure_at: nil, cancel: false, histories: false)
    @ui_thread = Thread.current
    @calls, @views, @alerts, @menus = [], [], [], 0
    bank = GameRoomGames::KrowaWordBank.default
    @tables = KrowaTestTables.new
    store = GameRoomGames::KrowaServerStore.new(server_tables: @tables, bank: bank, user: 'Alice')
    assignments = @tables.fetch('krowa_daily_assignments')
    scores = @tables.fetch('krowa_daily_scores')
    %w[2026-10-16 2026-10-17 2026-10-18 2026-10-19].each do |date|
      assignments.insert('day_key' => date.delete('-').to_i,
        'assignment' => GameRoomKrowa::DailyAssignment.seal(date, 'kot'))
      scores.insert('day_key' => date.delete('-').to_i, 'attempts' => 6)
      store.record_daily_open(date)
      store.publish_daily(date, 4, words: %w[las dom sok kot]) if histories
    end
    @original_rows = Marshal.dump(@tables.instance_variable_get(:@tables).transform_values(&:rows))
    @tables.instance_variable_get(:@tables).each do |name, table|
      original = table.method(:select)
      calls, ui_thread = @calls, @ui_thread
      table.define_singleton_method(:select) do |**options|
        calls << {table: name, on_ui: Thread.current.equal?(ui_thread), options: options}
        assignment_number = calls.count { |row| row[:table] == 'krowa_daily_assignments' }
        if name == 'krowa_daily_assignments' && assignment_number == failure_at
          raise EltenAPI::Tasks::Cancelled, 'controlled cancellation' if cancel
          raise IOError, 'controlled assignment read failure'
        end
        original.call(**options)
      end
    end
    @client = GameRoomGames::KrowaLeaderboardClient.new(KrowaTestProgram.new,
      GameRoomGames::Krowa.new(bank: bank), store: store)
    alerts = @alerts
    ui_thread = @ui_thread
    @client.define_singleton_method(:alert) do |message|
      assert(Thread.current.equal?(ui_thread), 'Alert escaped the UI thread')
      alerts << message
    end
  end

  def browse(select: nil, open_attempts: false)
    drive(select: select, open_attempts: open_attempts) { client.run }
  end

  def publish(date)
    drive { client.publish_daily(date, 4) }
  end

  def assignment_reads
    calls.select { |call| call[:table] == 'krowa_daily_assignments' }
  end

  def unchanged?
    @original_rows == Marshal.dump(@tables.instance_variable_get(:@tables).transform_values(&:rows))
  end

  private

  def drive(select: nil, open_attempts: false)
    Form.driver = lambda do |form|
      assert(Thread.current.equal?(@ui_thread), 'A visible form was opened on the worker')
      field = form.fields.first
      if field.header == 'Krowa leaderboards'
        @menus += 1
        field.index = 1
        (@menus == 1 ? form.accept_button : form.cancel_button).trigger(:press)
      else
        @views << {header: field.header, rows: Marshal.load(Marshal.dump(field.rows))}
        if open_attempts && field.header.start_with?('Daily Krowa:')
          details = form.fields[1]
          assert(details.header == 'Attempt list', 'Tab field missing')
          details.trigger(:before_focus)
          @views.last[:attempts] = details.options.dup
          @views.last[:empty_label] = details.empty_label
        end
        if select && @views.length == 1
          field.index = select
          form.accept_button.trigger(:press)
        else
          form.cancel_button.trigger(:press)
        end
      end
    end
    yield
  ensure
    Form.driver = nil
  end
end

normal = RankingScopeFixture.new
normal.browse
assert(normal.menus == 2 && normal.views.size == 1, 'Public daily list did not return normally')
assert(normal.calls.none? { |call| call[:on_ui] }, 'Daily solution query remained on the UI thread')
assert(normal.assignment_reads.size == 1, 'Daily list did not batch past solutions or read a current/future solution')
assert(normal.views.first[:rows] == [['2026-10-18', ''], ['2026-10-17', 'kot'], ['2026-10-16', 'kot']],
  'Date filtering, ordering or past solution changed')
assert(normal.alerts.empty? && normal.unchanged?, 'Browsing changed data or reported failure')

past = RankingScopeFixture.new
past.browse(select: 1)
assert(past.views.size == 2 && past.views.last[:header] == 'Daily Krowa: 2026-10-17, kot', 'Past ranking lost its solution')
assert(past.assignment_reads.size == 2 && past.calls.none? { |call| call[:on_ui] }, 'Past ranking header queried on the UI or twice')
assert(past.unchanged?, 'Opening a ranking changed its records')

current = RankingScopeFixture.new
current.browse(select: 0)
assert(current.views.last[:header] == 'Daily Krowa: 2026-10-18', 'Current solution appeared in the ranking header')
assert(current.assignment_reads.size == 1 && current.calls.none? { |call| call[:on_ui] }, 'Current ranking made a hidden solution query')

[[1, 0], [2, 1]].each do |failure_at, expected_views|
  failed = RankingScopeFixture.new(failure_at: failure_at)
  failed.browse(select: 1)
  assert(failed.views.size == expected_views && failed.menus == 2, 'Read failure escaped the public menu')
  assert(failed.alerts == ['Could not connect to the Krowa leaderboard.'], 'Read failure did not use the existing single alert')
  assert(failed.calls.none? { |call| call[:on_ui] } && failed.unchanged?, 'Failed query ran on UI or changed data')
end

cancelled = RankingScopeFixture.new(failure_at: 1, cancel: true)
cancelled.browse
assert(cancelled.views.empty? && cancelled.menus == 2 && cancelled.alerts.empty?, 'Cancelled daily read showed a partial list or an error')
assert(cancelled.unchanged?, 'Cancellation changed records')

%w[2026-10-17 2026-10-18].each do |date|
  published = RankingScopeFixture.new
  assert(published.publish(date), 'Public post-publication ranking failed')
  suffix = date == '2026-10-17' ? ', kot' : ''
  assert(published.views.last[:header] == "Daily Krowa: #{date}#{suffix}", 'Post-publication date/solution policy changed')
  assert(published.calls.none? { |call| call[:on_ui] }, 'Post-publication header queried on the UI')
end

histories = RankingScopeFixture.new(histories: true)
histories.browse(select: 1, open_attempts: true)
assert(histories.views.last[:attempts] == ['las. 0', 'dom. 1', 'sok. 1', 'kot. 3'], 'Past attempt list changed')
assert(histories.calls.none? { |call| call[:on_ui] } && histories.unchanged?, 'Attempt details queried on UI or wrote data')
assert(histories.calls.any? { |call| call[:table] == 'krowa_attempt_lists' }, 'Attempt payload was not read')

hidden_histories = RankingScopeFixture.new(histories: true)
hidden_histories.browse(select: 0, open_attempts: true)
assert(hidden_histories.views.last[:attempts].empty?, 'Today attempts reached the visible control')
assert(hidden_histories.calls.none? { |call| call[:table] == 'krowa_attempt_lists' || call[:on_ui] }, 'Hidden daily payload was downloaded')

GameRoomClock.define_singleton_method(:synchronized?) { false }
unconfirmed = RankingScopeFixture.new
unconfirmed.browse
assert(unconfirmed.views.empty? && unconfirmed.calls.empty?, 'Unconfirmed time read or displayed a daily solution')
assert(unconfirmed.alerts == ['Could not connect to the Krowa leaderboard.'], 'Clock failure lost its existing feedback')
puts 'PASS Krowa leaderboard task scope: public UI paths and lazy histories, native workers, failures/cancellation and date privacy'
