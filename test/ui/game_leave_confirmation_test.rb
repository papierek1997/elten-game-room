require_relative '../support/background_help_game_screen'

module EltenAPI::UI
  def loop_update; :host; end
end
class LeaveDialogLoop
  include EltenAPI::UI
end
$mainthread = $currentthread = Thread.current

def wait_in_leave_dialog(loop_host, runner)
  # The same paced, real planning worker runs under Help and confirmation.
  # A shorter modal-only wall-clock bound makes correctness depend on CPU load.
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + BackgroundGameScreenSupport::PROGRESS_TIMEOUT
  until yield
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      raise "Game did not progress inside the leave confirmation within #{BackgroundGameScreenSupport::PROGRESS_TIMEOUT.to_i} seconds"
    end
    $help_clock += 0.016
    loop_host.send(:loop_update)
    error = runner.take_error
    raise error if error
    sleep 0.001
  end
end

[GameRoomGames::FourInARow.new, GameRoomGames::AudioBall.new].each do |game|
  clients, audio, network = [], AudioBallTestAudio.new, {}
  if game.id == 'audio_ball'
    game.define_singleton_method(:build_client) do |_program, **_services|
      client = GameRoomAudioBall::Client.new(Program.new, self, clock: -> { $help_clock }, audio: audio,
        channel_factory: ->(**args) { AudioBallTestChannel.new(network, **args) })
      clients << client
      client
    end
  end
  h = screen = runner = layout = nil
  calls, waits = 0, 0
  host = LeaveDialogLoop.new
  leave = lambda do |table|
    calls += 1
    assert(table.equal?(h.table), 'Confirmation received a different table')
    current = screen.instance_variable_get(:@session_runner)
    runner ||= current
    assert(current.equal?(runner) && runner.alive?, 'Runner closed/replaced before confirmation')
    assert(clients.none? { |c| c.instance_variable_get(:@closed) }, 'Client closed before confirmation')
    assert(screen.instance_variable_get(:@background_presentation), 'Presentation detached before confirmation')
    $lastactivecontrols = [Object.new] # Native confirm is a different control on the same UI thread.
    if calls == 1
      if game.id == 'four_in_a_row'
        h.write('Alice', [GameRoomGames::EventCommand.new(action: 'drop', value: '1')])
        wait_in_leave_dialog(host, runner) do
          h.events('Alice').size == 2 && screen.send(:event_presenter).last_seen_event_id.to_i >= h.events('Alice').last['__id']
        end
      else
        wait_in_leave_dialog(host, runner) { h.replay('Alice').state[:rally] >= 1 && audio.calls.any? { |row| row.first == :point } }
        assert(network['alice'].reasons.empty?, 'Confirmation reconnected the realtime channel')
      end
    end
    # No / cancelled or failed departure must both keep the same live screen.
    [false, nil, true].fetch(calls - 1)
  end
  h, screen = screen_fixture(game, bots: 1, leave_table: leave)
  bot_serves_audio_ball(h) if game.id == 'audio_ball'
  Form.driver = lambda do |form|
    waits += 1
    raise 'Leave callback did not return control' if waits > 3
    current = screen.instance_variable_get(:@layout)
    if layout
      assert(current.equal?(layout) && form.equal?(layout.form), 'Cancelling replaced the form')
      assert(layout.chat.text == 'Unsent draft', 'Cancelling lost chat text')
      assert(form.fields[form.index].equal?(layout.chat), 'Cancelling moved focus out of chat')
      assert(screen.instance_variable_get(:@session_runner).equal?(runner), 'Cancelling restarted runner')
      assert(clients.size <= 1, 'Cancelling rebuilt realtime client')
    else
      layout = current
      layout.chat.set_text('Unsent draft')
      form.index = form.fields.index(layout.chat)
    end
    $lastactivecontrols = [form]
    layout.back_button.trigger(:press)
  end
  begin
    h.as('Alice') { assert(screen.run == :left_table, 'Confirmed departure was returned as another request to leave') }
    assert(calls == 3 && waits == 3, 'Missing cancellation/retry/confirmation')
    assert(screen.instance_variable_get(:@session_runner).nil?, 'Successful departure retained runner')
    assert(screen.instance_variable_get(:@background_presentation).nil?, 'Successful departure retained presentation')
    assert(clients.all? { |c| c.instance_variable_get(:@closed) }, 'Successful departure retained client')
    puts "PASS #{game.id}: progress/presentation inside confirmation, cancellation/retry preserve client, focus/draft; success cleans up"
  ensure
    screen.send(:stop_session_runner)
    clients.each(&:close)
    $lastactivecontrols = nil
  end
end

# A genuine server closure is not a user request and must never ask to leave.
h, screen = screen_fixture(GameRoomGames::FourInARow.new,
  leave_table: ->(_table) { raise 'Server closure asked for confirmation' })
screen.define_singleton_method(:wait_for_action) { |*| :room_closed }
assert(screen.run == :room_closed, 'Remote closure lost its result')
assert(screen.instance_variable_get(:@session_runner).nil?, 'Remote closure retained runner')

# Exercise production app wiring, including screens prepared behind another view.
app = EltenGameRoom.allocate
app.instance_variable_set(:@transport, h.transports['Alice'])
app.instance_variable_set(:@games, h.repositories['Alice'])
lobby = LobbyRepository.new(ProgramDouble.new(h.broker.endpoint('Alice')), transport: h.transports['Alice'], server_tables: {})
app.instance_variable_set(:@lobby, lobby)
app.define_singleton_method(:game_local_services) { {transport: @transport} }
app.define_singleton_method(:statistics_observer_for) { |_| nil }
requested = []
app.define_singleton_method(:leave_table_from_screen) { |row| requested << row; false }
prepared = app.send(:build_game_screen, h.session, h.game, table: h.table, layout: nil)
assert(prepared.instance_variable_get(:@leave_table).call(h.table) == false && requested == [h.table],
  'Application/prepared screen bypassed the existing departure guards')
puts 'PASS remote closure and production leave callback wiring'
