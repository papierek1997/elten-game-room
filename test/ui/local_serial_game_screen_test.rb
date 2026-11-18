require_relative '../support/background_help_game_screen'
require_relative '../../games/cheat'
require_relative '../../games/kosciane'
require_relative '../../lib/local_name_presentation'

runtime = Object.new
runtime.define_singleton_method(:read_json) { |_path, default: nil| default }
runtime.define_singleton_method(:write_json) { |_path, _value| true }

[GameRoomGames::Cheat.new, GameRoomGames::Kosciane.new].each do |game|
  harness, screen = screen_fixture(game, bots: 1)
  program = screen.instance_variable_get(:@program)
  names = GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Alice')
  names.save('Anna Żółć')
  program.define_singleton_method(:local_name_presentation) { names }
  prepare = screen.method(:prepare_action_view)
  displayed = nil
  screen.define_singleton_method(:prepare_action_view) do |replay|
    displayed = replay
    prepare.call(replay)
  end
  changed, finished = false, false
  submitted = {}
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
  Form.driver = lambda do |form|
    layout = screen.instance_variable_get(:@layout)
    if layout && !form.equal?(layout.form)
      form.accept_button.trigger(:press)
      next
    end
    next unless layout
    events = harness.events('Alice')
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      raise "#{game.id}: events=#{events.map { |event| event['action'] }.inspect}, submitted=#{submitted.keys.inspect}, busy=#{screen.send(:event_presentation_busy?)}, guard=#{layout.surface.action_allowed?}"
    end
    if events.length >= 2 && !changed
      changed = true
      names.save('Jan Kowalski')
      form.trigger(:local_presentation_changed)
      next
    end
    if events.length >= 10 || harness.replay('Alice').finished?
      finished = true
      layout.back_button.trigger(:press)
      next
    end
    unless screen.send(:event_presentation_busy?) || form.game_room_pending_operation || !layout.surface.action_allowed?
      replay = displayed
      boundary = replay.accepted_events.length
      if replay.current_player == 'Alice' && !submitted[boundary]
        action = game.legal_actions(replay, 'Alice').first
        if action
          action = GameSurfaces::Action.from_h(action)
          layout.surface.send(:emit_action, action.kind, action.name, action.payload)
          submitted[boundary] = true unless form.instance_variable_get(:@wait)
        end
      end
    end
    sleep 0.002
  end
  begin
    screen.run
    assert(finished && changed, "#{game.id}: no real view refresh after the local-name change")
    puts "PASS #{game.id}: name change and ordinary native GameScreen view"
  ensure
    screen.send(:stop_session_runner)
  end
end
puts 'PASS local names through GameScreen.run: bot executor, live sound queue, real hand/dice view refresh and name change'
