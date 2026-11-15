require_relative '../../support/cash_auction_native'
require_relative '../../support/session_runner'
require_relative '../../../lib/game_screen'

module EltenAPI::Tasks
  class << self
    attr_accessor :bid_ack_probe, :bid_ack_after_probe
    alias run_without_bid_ack_probe run
    def run(**options, &block)
      bid_ack_probe&.call(options)
      result = run_without_bid_ack_probe(**options, &block)
      bid_ack_after_probe&.call(options)
      result
    end
  end
end

class CashBidAcknowledgementFixture
  Clock = Struct.new(:value) do
    def now(_session); value; end
    def server_now; value; end
  end
  attr_reader :h, :runner, :layout, :screen, :wait, :driver, :alerts

  def initialize(clock)
    $game_room_test_user = 'Alice'
    $currentthread = Thread.current
    @driver = CashAuctionNative::Driver.new
    game = GameRoomGames::CashAuction.new
    @h = NativeRoomHarness.new(game: game, users: %w[Alice Bob], options: game.table_creation_options)
    h.start
    @runner = runner_for(h)
    runner.instance_variable_set(:@clock, clock)
    h.view('Alice').next_random_values = Array.new(16, 1)
    step(h, runner)
    clock.value += 3
    step(h, runner)
    replay = h.replay('Alice')
    raise 'Bid ACK fixture did not enter auction' unless replay.state[:phase] == :auction && !replay.state[:chest]
    @layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(replay, 'Alice'),
      user_items: replay.players, users_header: 'Players', phase: :active)
    layout.session_id = h.repositories['Alice'].session_id(h.session)
    layout.begin_bindings
    layout.focus_game(silent: true)
    layout.form.focus
    @screen = GameScreen.allocate
    {game: game, table: h.table, session: h.session, table_owner: 'Alice',
      repository: h.repositories['Alice'], session_runner: runner, layout: layout,
      pending_event_ids: [], game_services: {transport: h.transports['Alice']}}.each do |name, value|
      screen.instance_variable_set("@#{name}", value)
    end
    @alerts = []
    alerts = @alerts
    screen.define_singleton_method(:event_presentation_busy?) { false }
    screen.define_singleton_method(:alert) { |message| alerts << message }
    # Speech/history are separate from acknowledgement and draft ownership.
    screen.define_singleton_method(:process_new_events) { |_replay| }
    screen.define_singleton_method(:refresh_history_control) { |_history, _replay| }
    @wait = GameScreen::WaitState.new(replay: replay,
      revision: h.repositories['Alice'].events_revision(replay.accepted_events),
      session: h.session, actor: 'Alice', membership: h.transports['Alice'].membership_token(h.table['__id']))
    screen.send(:bind_wait_surface, wait, layout, -> { screen.send(:remember_layout_position, layout) })
  end

  def field; layout.surface.fields.first; end

  def type(text)
    field.set_text('')
    field.restore_selection(index: 0, check: 0)
    driver.frame(layout.form, text.chars.flat_map { |character| driver.tap(character.upcase.ord) }, characters: text)
    raise 'Native bid did not receive the typed text' unless field.text == text
  end

  def enter
    driver.frame(layout.form, driver.tap(13))
    raise 'Native Enter bypassed GameScreen binding' unless wait.action == :game_action
  end

  def submit(inline: false)
    h.as('Alice') do
      inline ? screen.send(:handle_inline_wait, wait, layout) : screen.send(:submit_action, wait.replay)
    end
  end

  def refresh
    # This is the same saved surface state consumed by prepare_action_view.
    layout.update(view_spec: h.game.game_view_spec(h.replay('Alice'), 'Alice'),
      surface_state: screen.instance_variable_get(:@surface_state),
      user_items: %w[Alice Bob], users_header: 'Players', history_items: [], phase: :active)
  end

  def close
    layout&.form&.game_room_pending_operation&.close
    runner&.close
    h&.users&.each { |user| h.as(user) { h.view(user)&.close } }
    $activecontrols = $lastactivecontrols = []
  end
end

original_now = Time.method(:now)
clock = CashBidAcknowledgementFixture::Clock.new(original_now.call.to_i)
Time.define_singleton_method(:now) { Time.at(clock.value) }
begin
  [false, true].each do |inline|
    [:unchanged, :new_draft, :retyped_same, :different_session, :invalid].each do |boundary|
      f = CashBidAcknowledgementFixture.new(clock)
      begin
        initial = boundary == :invalid ? 'xyz' : '125'
        f.type(initial)
        f.enter
        submitted = f.screen.instance_variable_get(:@selected_surface_action)
        raise 'Native bid lacked its immutable edit receipt' unless submitted['_text_input'].length == 2
        before = f.h.events('Alice').length
        captured = false
        EltenAPI::Tasks.bid_ack_probe = lambda do |options|
          next unless !captured && options[:ui].is_a?(GameRoomUI::PendingOperation)
          captured = true
          f.type(boundary == :new_draft ? '500' : initial) if [:new_draft, :retyped_same].include?(boundary)
        end
        EltenAPI::Tasks.bid_ack_after_probe = lambda do |options|
          # The native write succeeded for the old session, but the currently
          # displayed session changed before its acknowledgement reached UI.
          f.layout.session_id += 1 if boundary == :different_session && options[:ui].is_a?(GameRoomUI::PendingOperation)
        end
        f.submit(inline: inline)
        raise 'Bid did not use the actual network-task UI boundary' unless captured
        expected = boundary == :unchanged ? '' : boundary == :new_draft ? '500' : initial
        raise "#{inline ? 'inline' : 'ordinary'} #{boundary}: ACK cleared or retained the wrong native draft" unless f.field.text == expected
        f.refresh
        raise "#{inline ? 'inline' : 'ordinary'} #{boundary}: refresh restored the submitted bid from stale saved state" unless f.field.text == expected
        inserted = f.h.events('Alice').drop(before)
        if boundary == :invalid
          raise 'Invalid bid entered native history' unless inserted.empty? && !f.alerts.empty?
        else
          raise 'ACK test did not append exactly the original bid' unless inserted.length == 1 && inserted.first['action'] == 'bid' && inserted.first['value'].split('|').last == initial
          raise 'Local edit receipt leaked into a native packet' if JSON.generate(f.h.core.entries).include?('_text_input')
        end
      ensure
        EltenAPI::Tasks.bid_ack_probe = nil
        EltenAPI::Tasks.bid_ack_after_probe = nil
        f&.close
      end
    end
  end
  puts 'PASS native Cash bid Enter through real GameScreen/network-task/runner ACK, saved-state refresh, invalid drafts and concurrent/ABA edits'
ensure
  EltenAPI::Tasks.bid_ack_probe = nil
  EltenAPI::Tasks.bid_ack_after_probe = nil
  Time.define_singleton_method(:now, original_now)
end
