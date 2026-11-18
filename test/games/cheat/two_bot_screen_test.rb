require_relative '../../support/background_help_game_screen'
require_relative '../../../games/cheat'
require_relative '../../../lib/local_name_presentation'
require_relative '../../support/cheat_sound'

class ProgramDouble
  def self.normalized_settings; {'background_game_sounds' => 'all'}; end
end

runtime = Object.new
runtime.define_singleton_method(:read_json) { |_path, default: nil| default }
runtime.define_singleton_method(:write_json) { |_path, _value| true }

game = GameRoomGames::Cheat.new
harness, screen = screen_fixture(game, bots: 2)
program = screen.instance_variable_get(:@program)
audio = CheatSoundProgram.new
program.define_singleton_method(:game_room_optional_sounds?) { true }
program.define_singleton_method(:game_room_sound_volume) { |_name| 0.4 }
program.define_singleton_method(:play_sound_from_asset) { |name, **options| audio.play_sound_from_asset(name, **options) }
names = GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Alice')
names.save('Anna Żółć')
program.define_singleton_method(:local_name_presentation) { names }
prepare = screen.method(:prepare_action_view)
displayed = nil
screen.define_singleton_method(:prepare_action_view) do |replay|
  displayed = replay
  prepare.call(replay)
end
changed, finished, corrected = false, false, false
submitted = {}
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 70
Form.driver = lambda do |form|
  layout = screen.instance_variable_get(:@layout)
  if layout && !form.equal?(layout.form)
    form.accept_button.trigger(:press)
    next
  end
  next unless layout
  if !corrected && audio.played.any? { |cue, _| cue == 'buzzer2' }
    store = harness.transports['Alice'].instance_variable_get(:@live_store)
    row = store.instance_variable_get(:@rooms).fetch(harness.table['__id']).records.find do |record|
      record.packet['kind'] == 'game_action' && record.packet.dig('data', 'events').any? { |event| event['action'] == 'challenge' }
    end
    raise 'Missing native challenge record' unless row
    row.estimated_time = true
    store.send(:ingest_record, harness.table['__id'], sequence: row.sequence, message_id: row.message_id,
      sender: row.sender, packet: row.packet, created_at: row.created_at + 7)
    corrected = true
  end
  audio.voices.each { |voice| voice.done = true } if $help_frames % 12 == 0
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
  if events.length >= 12 && corrected || harness.replay('Alice').finished?
    finished = true
    layout.back_button.trigger(:press)
    next
  end
  unless screen.send(:event_presentation_busy?) || form.game_room_pending_operation || !layout.surface.action_allowed?
    replay = displayed
    boundary = replay.accepted_events.length
    if replay.current_player == 'Alice' && !submitted[boundary]
      actions = game.legal_actions(replay, 'Alice')
      action = actions.find { |item| item['action'] == 'challenge' } || actions.first
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
  assert(finished && changed && corrected, "#{game.id}: missing name change, deferred challenge or timestamp correction")
  puts 'PASS Cheat GameScreen: two real bot seats, normal executor, deferred challenge sounds, native timestamp correction and name refresh'
ensure
  screen.send(:stop_session_runner)
end
