require_relative "../../support/pong_ui"

rules = GameRoomGames::AxelPong.new
repo = Object.new
def repo.players_for(s); s['__players']; end
def repo.actor_of(e, _s); e['actor']; end
def repo.event_id(e); e['__id']; end
session = {'__players' => ['Łucja'.b, 'Żaneta'.b], 'player_one' => 'Łucja'.b, 'options' => JSON.generate(rules.default_options)}
native_dictionary = $rules_dictionary
[:pl, :en, :fallback].each do |language|
  $rules_english = language == :en
  GameRoomTestLocalization.use_language(language)
  $rules_dictionary = language == :fallback ? BinaryRuleDictionary.new({}) : native_dictionary
  replay = rules.replay(session, [{'__id' => 1, 'actor' => 'Łucja'.b, 'action' => 'pong_point', 'value' => '0:0'}], repo)
  replay.history.each { |entry| assert(entry.text.valid_encoding?, 'binary history encoding') }
  documents = rules.rule_book(options: rules.default_options).documents
  assert(documents.all? { |d| d.text.encoding == Encoding::UTF_8 && d.text.valid_encoding? }, 'rule encoding')
  expected = language == :pl ? 'W Axel Pongu odbijasz piłkę rakietką' : 'In Axel Pong, move your paddle'
  assert(documents.first.text.include?(expected), "wrong #{language} rule language")
  spec = rules.surface_spec(replay, 'Żaneta'.b)
  surface = GameSurfaces.build(spec)
  state = GameRoomPong::Engine.new.snapshot
  state['p'] = [10, 20]
  state['shields'] = [125, 0]
  surface.present(state, GameRoomLocalization.translate('Match in progress.'))
  field = surface.fields.first
  field.model_keyboard_input! # This fixture supplies held/pressed keys, not native press snapshots.
  keys, pressed = [], []
  field.define_singleton_method(:key_held?) { |key| keys.include?(key) }
  field.define_singleton_method(:key_pressed?) { |key| pressed.include?(key) }
  form = Form.new([field, EditBox.new('Chat')])
  $activecontrols = [form, field]
  keys.replace([0x27, 0x26]); pressed.replace([:key_up, :key_right]); field.update
  assert(surface.input(form) == {'move' => 1, 'aim' => 1, 'hit' => true, 'press' => 1,
    'left_press' => 0, 'right_press' => 1}, 'keyboard movement/strike/independent DOWN counters')
  keys.clear; pressed.clear; field.update
  assert(surface.input(form)['press'] == 1 && !surface.input(form)['hit'], 'brief strike vanished on release')
  form.index = 1
  assert(surface.input(form)['move'] == 0 && !surface.input(form)['hit'], 'chat arrows steered paddle')
  assert(form.fields[1].text == '', 'Pong changed chat text')
  form.index = 0
  $activecontrols = []
  assert(surface.input(form)['move'] == 0, 'inactive application steered paddle')
  $activecontrols = [form, field]
  keys.replace([0x11, 0x27, 0x26]); pressed.replace([:key_up]); field.update
  assert(surface.input(form)['move'].zero? && surface.input(form)['press'] == 1, 'room shortcut became a stroke')
  assert(%w[left right up space].all? { |key| field.key_processed(key.to_sym) }, 'movement keys not reserved')
  %w[scores server position effects].each do |command|
    $spoken_messages.clear
    surface.handle_command(command)
    assert($spoken_messages.length == 1 && $spoken_messages.first.encoding == Encoding::UTF_8 && $spoken_messages.first.valid_encoding?, "#{language} #{command}: speech encoding/count")
  end
  surface.handle_command('position')
  assert($spoken_messages.last.include?('20'), 'guest position did not use shared X')
  observed = GameSurfaces.build(rules.surface_spec(replay, 'Watcher'))
  observed.listening_seat = 0
  observed.present(state, 'Ready')
  $spoken_messages.clear
  observed.handle_command('position')
  assert($spoken_messages == ['Łucja: 10.'] && $spoken_messages.first.valid_encoding?, 'binary observer C lost Unicode name/position')
  observer_c = rules.game_shortcuts(replay, 'Watcher').find { |s| s.key == 'c' }
  assert(observer_c.label.include?(language == :pl ? 'obserwowanego' : 'observed'), 'observer C help still says your paddle')
  shortcuts = rules.game_shortcuts(replay, 'Żaneta'.b)
  assert(shortcuts.map(&:key).sort == %w[c e e s t w], 'missing/extra Pong shortcuts')
  assert(shortcuts.all? { |s| s.label.valid_encoding? }, 'shortcut encoding')
  echo_shortcut = shortcuts.find { |s| s.key == 'e' && s.modifiers == [:shift] }
  assert(echo_shortcut && echo_shortcut.label.include?(language == :pl ? 'brzmienie band' : 'side-wall cues'),
    'new shortcut not translated')
  assert(shortcuts.none? { |s| s.key == 'c' && s.modifiers == [:shift] }, 'unavailable crowd shortcut')
  assert(rules.game_shortcuts(replay, 'Observer').none? { |s| s.key == 'w' }, 'observer can hurry')
  assert(rules.game_shortcuts(replay, 'Observer').none? { |s| s.key == 'm' }, 'observer can control a mouse paddle')
  bot_session = session.merge('__players' => ['Łucja'.b, 'bot:1:1'])
  bot_replay = rules.replay(bot_session, [], repo)
  assert(rules.game_shortcuts(bot_replay, 'Łucja'.b).none? { |s| s.key == 'w' }, 'bot game advertises hurry')

  # Exercise the same callback used by the real surface shortcuts, including
  # attach/detach, without creating a device sound or a network connection.
  local = GameRoomPong::Client.new(Object.new, rules, audio: PongUiAudio.new)
  local.instance_variable_set(:@replay, replay)
  local.send(:rally_state).public_send(:snapshot=, state)
  local.instance_variable_set(:@side, 1)
  local.send(:start_progress) # This UI-only fixture has no native network endpoint.
  local.attach_view(form, surface)
  $spoken_messages.clear
  3.times { surface.handle_command('echo') }
  expected_echo = language == :pl ? ['Brzmienie band: szum.', 'Brzmienie band: tony.', 'Brzmienie band: wyłączone.'] :
    ['Side-wall cues: noise.', 'Side-wall cues: tones.', 'Side-wall cues: off.']
  assert($spoken_messages == expected_echo && $spoken_messages.all? { |s| s.encoding == Encoding::UTF_8 },
    "#{language} echo callback/encoding")
  local.define_singleton_method(:request_hurry) { @hurry_called = true }
  surface.handle_command('hurry')
  assert(local.instance_variable_get(:@hurry_called), 'hurry shortcut not connected to client')
  local.detach_view
  assert(surface.on_pong_command == nil && form.instance_variable_get(:@timers).empty?, 'shortcut/timer survived detach')
  count = $spoken_messages.length
  surface.handle_command('echo')
  assert($spoken_messages.length == count, 'detached shortcut still invoked client')
  local.close
  client = GameRoomPong::Client.allocate
  client.instance_variable_set(:@players, replay.players)
  client.send(:rally_state).public_send(:snapshot=, state)
  client.send(:rally_state).public_send(:paused=, true)
  state['b']['dy'] = 1
  $spoken_messages.clear
  client.send(:set_paused, false)
  assert($spoken_messages == [GameRoomLocalization.translate('Match resumed.')], 'rally recovery announced a new serve')
  state['b']['dy'] = 0
  client.send(:rally_state).public_send(:paused=, true)
  client.send(:set_paused, false)
  client.instance_variable_set(:@server_announced, false)
  client.send(:rally_state).public_send(:serve_announce_at=, 0)
  client.instance_variable_set(:@audio, Object.new.tap { |a| def a.start_match; end })
  client.send(:announce_ready, 1)
  assert($spoken_messages.last.include?('Łucja') && $spoken_messages.last.encoding == Encoding::UTF_8, 'binary server name')
  spectator = GameSurfaces.build(rules.surface_spec(replay, 'Observer'))
  spectator.present(state, 'ready')
  assert(spectator.input(Form.new(spectator.fields))['move'].zero?, 'observer input')
end
$rules_dictionary = native_dictionary
GameRoomTestLocalization.use_language(:en)
now = 0.0
calls = 0
timer = GameRoomRealtime::Timer.new(clock: -> { now }) { calls += 1 }
timer.update; timer.update
now = 3600; timer.update
assert(calls == 2, 'timer catches up elapsed hour')
timer.stop; now += 1; timer.update
assert(calls == 2, 'stopped timer still active')
puts 'PASS binary Pong UI: PL/EN/fallback, names/history/rules, readouts, chat/focus/modifiers, timer, echo/hurry shortcut lifecycle and roles'
