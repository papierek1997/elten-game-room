require_relative "../../support/translation_reference"
# encoding: UTF-8
require_relative "../../support/ui"
require_relative "../../support/log"
require_relative "../../support/localization"

class Program
  def self.server_app(**_options); end
end

module Session
  def self.name; 'Alice'; end
end

class FormTimer
  def initialize(*_args, **_options); end
end

class Form
  class << self
    attr_accessor :driver
  end
  def wait; Form.driver.call(self); end
  def resume; end
  def keyboard_idle_frame?; true; end
end

require_relative "../../../__app"
require_relative "../../../lib/audio_ball/audio"

def assert(value, message)
  raise message unless value
end

def check(name)
  yield
  puts "PASS #{name}"
end

class ListeningSound
  attr_accessor :pan, :volume, :frequency
  attr_reader :plays, :seeks
  def initialize(&on_play)
    @plays, @seeks, @playing, @frequency, @on_play = 0, [], false, 48_000, on_play
  end
  def length; 0.35; end
  def finished?; !playing?; end
  def position=(value); @seeks << value; end
  def play; @plays += 1; @playing = true; @on_play.call; end
  def playing?; @playing; end
  def pause; @playing = false; end
  def close; pause; end
end

class ListeningProgram
  attr_accessor :side
  attr_reader :sounds, :played
  def initialize(side); @side, @sounds, @played = side, {}, []; end
  def create_sound_from_asset(name, **_options)
    @sounds[name] = ListeningSound.new { @played << name }
  end
  private
  def audio_ball_preferences; {'listening_side' => @side}; end
end

check('Flight mirrors immediately for both viewers without changing state or restarting streams') do
  [0, 1, nil].product(%w[up left down]).each do |viewer, shot|
    program = ListeningProgram.new('right')
    audio = GameRoomAudioBall::Audio.new(program)
    sound = program.sounds.fetch("audio_ball_#{shot}")
    [25.0, 18.75, 12.5, 6.25, 0.0, 6.25, 12.5, 18.75, 25.0].each do |position|
      snapshot = {'phase' => 'flying', 'position' => position, 'shot' => shot, 'turn' => 1, 'goal' => nil}.freeze
      before = Marshal.dump(snapshot)
      original = (position / 25.0 * 2.0 - 1.0) * (viewer == 1 ? -1 : 1)
      %w[right left right].each do |side|
        program.side = side
        audio.update(snapshot, viewer: viewer)
        expected = side == 'left' ? -original : original
        assert([sound.pan].pack('G') == [expected].pack('G'), 'Flight did not follow the personal listening side exactly')
        assert(sound.plays == 1 && sound.seeks == [0], 'Changing listening side restarted the current flight')
        assert(Marshal.dump(snapshot) == before, 'Listening side altered a shared snapshot')
      end
    end
    audio.close
  end
end

check('Audio Ball personal preferences default right and reject malformed values') do
  assert(defined?(GameRoomAudioBall::Preferences), 'Audio Ball personal preferences are missing')
  prefs = GameRoomAudioBall::Preferences
  [nil, [], 'left', {}, {'listening_side' => 'LEFT'}, {'listening_side' => 1}].each do |values|
    assert(prefs.normalize(values) == {'listening_side' => 'right', 'sound_pack' => 'default'}, 'Invalid listening side changed the default')
  end
  assert(prefs.normalize('listening_side' => 'left', 'other' => true) == {'listening_side' => 'left', 'sound_pack' => 'default'}, 'Left preference was not normalized')
  assert(prefs.read(Object.new) == {'listening_side' => 'right', 'sound_pack' => 'default'}, 'Programs without personal settings lost the original audio')
  [nil, 1, {}, '../audiodisc', 'AUDIODISC'].each do |value|
    assert(prefs.normalize('sound_pack' => value)['sound_pack'] == 'default', 'Invalid sound pack escaped normalization')
  end
  assert(prefs.normalize('sound_pack' => 'audiodisc')['sound_pack'] == 'audiodisc', 'Valid sound pack lost')
  program = Object.new
  program.define_singleton_method(:audio_ball_preferences) { {'listening_side' => 'left'} }
  program.singleton_class.send(:private, :audio_ball_preferences)
  assert(prefs.read(program) == {'listening_side' => 'left'}, 'Private program preferences were ignored')
end

check('Preparation mirrors for both players including a live preference change during its tail') do
  [0, 1, nil].product([0, 1], %w[right left]).each do |viewer, preparing, side|
    program = ListeningProgram.new(side)
    audio = GameRoomAudioBall::Audio.new(program)
    audio.prepare(preparing, viewer: viewer)
    sound = program.sounds.fetch('audio_ball_prepare')
    original = (preparing == 0 ? 1.0 : -1.0) * (viewer == 1 ? -1 : 1)
    assert(sound.pan == (side == 'left' ? -original : original), 'Preparation did not mirror with the flight')
    %w[left right left].each do |choice|
      program.side = choice
      audio.update({'phase' => 'prepared'}, viewer: viewer)
      assert(sound.pan == (choice == 'left' ? -original : original), 'An audible preparation ignored a saved listening side')
      assert(sound.plays == 1 && sound.seeks == [0], 'Changing listening side restarted preparation')
    end
    sound.pause
    audio.update({'phase' => 'prepared'}, viewer: viewer)
    assert(sound.plays == 1 && !sound.playing?, 'Presentation revived completed preparation')
    audio.close
  end
end

check('Local dialog saves only Audio Ball settings and Cancel preserves file and cached preference') do
  require 'tmpdir'
  Dir.mktmpdir('audio-ball-settings-') do |directory|
    file = File.join(directory, 'settings.json')
    initial = {'unrelated' => {'keep' => true}, 'pong' => {'auto_return' => true}, 'widget_games' => ['uno']}
    File.binwrite(file, JSON.generate(initial))
    reads, writes = 0, 0
    build = lambda do
      app = EltenGameRoom.allocate
      app.define_singleton_method(:read_json) do |name, default:|
        assert(name == 'settings.json', 'Personal settings read the wrong file')
        reads += 1
        JSON.parse(File.binread(file))
      end
      app.define_singleton_method(:update_json) do |name, default:, &block|
        assert(name == 'settings.json', 'Personal settings saved to the wrong file')
        writes += 1
        result = block.call(JSON.parse(File.binread(file)))
        File.binwrite(file, JSON.generate(result))
        result
      end
      app.define_singleton_method(:run_network_task) { |*| raise 'Personal settings accessed the network' }
      app
    end
    app = build.call
    assert(app.respond_to?(:audio_ball_preferences, true), 'Program does not expose local Audio Ball preferences')
    100.times { assert(app.send(:audio_ball_preferences) == {'listening_side' => 'right', 'sound_pack' => 'default'}, 'Default is not right') }
    assert(reads == 1 && writes == 0, 'Audio presentation repeatedly reads disk')
    Form.driver = lambda do |form|
      assert(form.is_a?(GameRoomUI::Form) && form.game_room_program.equal?(app), 'Settings bypassed the Game Room form')
      assert(form.fields.length == 4, 'Personal settings added unexpected controls')
      field = form.fields.first
      assert(field.header == 'Your listening side (only for you)', 'Personal setting label is unclear')
      assert(field.options == ['Right (default)', 'Left'] && field.index == 0, 'Listening side choices/default are wrong')
      field.index = 1
      pack = form.fields[1]
      assert(pack.header == 'Sound pack (only for you)' && pack.options == ['Default', 'Sounds from Audiodisc'] && pack.index == 0, 'Wrong sound-pack choices or default')
      pack.index = 1
      assert(app.send(:audio_ball_preferences)['sound_pack'] == 'default', 'An unsaved pack changed live audio')
      assert(app.send(:audio_ball_preferences)['listening_side'] == 'right', 'An unsaved choice changed live audio')
      form.accept_button.trigger(:press)
    end
    app.send(:show_audio_ball_settings)
    saved = JSON.parse(File.binread(file))
    assert(saved == initial.merge('audio_ball' => {'listening_side' => 'left', 'sound_pack' => 'audiodisc'}), 'Save lost other local settings')
    assert(app.send(:audio_ball_preferences) == saved['audio_ball'], 'Save did not immediately refresh cached audio preferences')
    assert(build.call.send(:audio_ball_preferences) == saved['audio_ball'], 'Preference was not persistent across program instances')
    before = File.binread(file)
    Form.driver = lambda do |form|
      assert(form.fields.first.index == 1, 'Dialog did not reopen on the saved choice')
      form.fields.first.index = 0
      assert(form.fields[1].index == 1, 'Dialog lost the saved sound pack')
      form.fields[1].index = 0
      form.cancel_button.trigger(:press)
    end
    app.send(:show_audio_ball_settings)
    assert(File.binread(file) == before && writes == 1, 'Cancel wrote personal settings')
    assert(app.send(:audio_ball_preferences)['listening_side'] == 'left', 'Cancel changed cached listening side')
    assert(app.send(:audio_ball_preferences)['sound_pack'] == 'audiodisc', 'Cancel changed the saved sound pack')
    File.binwrite(file, JSON.generate(saved.merge('audio_ball' => {'listening_side' => 'right'})))
    app.send(:game_room_settings, reload: true)
    assert(app.send(:audio_ball_preferences)['listening_side'] == 'right', 'Reload kept stale personal settings')
  end
end

check('Modal settings pump the supplied realtime tick and clean up the timer on cancel or failure') do
  app = EltenGameRoom.allocate
  app.instance_variable_set(:@game_room_settings, {})
  now, ticks = 0.0, 0
  captured, timer = nil, nil
  [:cancel, :failure].each do |outcome|
    before = ticks
    Form.driver = lambda do |form|
      captured = form
      timer = form.instance_variable_get(:@timers).fetch(0)
      4.times { now += 0.02; timer.update }
      assert(ticks == before + 4, 'The realtime client stopped ticking in the dialog')
      raise 'Dialog failed' if outcome == :failure
      form.cancel_button.trigger(:press)
    end
    begin
      app.send(:show_audio_ball_settings, tick: -> { ticks += 1 }, clock: -> { now })
      assert(outcome == :cancel, 'Dialog failure was swallowed')
    rescue RuntimeError => error
      raise unless outcome == :failure && error.message == 'Dialog failed'
    end
    assert(captured.instance_variable_get(:@timers).empty?, 'A modal timer remained attached after closing')
    now += 1
    timer.update
    assert(ticks == before + 4, 'A detached settings timer still invoked the client')
  end
end

check('Personal Ctrl+P and its context entry are scoped to games with local settings without resuming gameplay') do
  [GameRoomGames::AudioBall.new, GameRoomGames::AxelPong.new, GameRoomGames::Darts.new, GameRoomGames::Makao.new].each do |game|
    users, chat = ListBox.new(['Alice'], header: 'Users'), EditBox.new('Chat', text: 'draft')
    layout = Struct.new(:form, :users, :back_button).new(GameRoomUI::Form.new([users, chat]), users, nil)
    calls = 0
    GameRoomParticipantMenu.bind(layout, available: -> { [] }, game: game,
      settings: -> { calls += 1; {'saved' => true} }) { raise 'Personal settings dispatched a shared game action' }
    [users, chat].each do |focused|
      layout.form.index = layout.form.fields.index(focused)
      menu = FakeMenu.new
      layout.form.context(menu, false)
      items = menu.options.select { |entry| entry[2] == 'p' }
      if game.id == 'makao'
        assert(items.empty?, 'An unrelated game received Ctrl+P')
        next
      end
      assert(items.length == 1, 'Ctrl+P is missing or duplicated')
      expected = {'audio_ball'=>'Audio Ball settings', 'axel_pong'=>'Pong settings', 'darts'=>'Darts settings'}.fetch(game.id)
      assert(items.first[0] == expected, 'Wrong personal settings menu label')
      items.first[3].call
      assert(layout.form.fields[layout.form.index].equal?(focused) && chat.text == 'draft', 'Settings moved focus or edited chat')
      returned_label = focused.respond_to?(:last_focus_header) ? focused.last_focus_header : focused.last_focus_label
      assert(returned_label.start_with?('Settings saved. '), 'Saved personal settings did not announce their return control')
      original_label = focused.respond_to?(:header) ? focused.header : focused.label
      assert(!original_label.start_with?('Settings saved. '), 'The temporary settings result changed the control permanently')
    end
    assert(calls == (game.id == 'makao' ? 0 : 2), 'Ctrl+P did not dispatch the local callback')
    assert(layout.form.instance_variable_get(:@handlers).keys.none? { |key| key.to_s == 'key_p' }, 'Bare P was bound outside the native menu')
  end
end

class ListeningRepository
  def players_for(_session); %w[Alice Bob]; end
  def actor_of(event, _session = nil); event['actor']; end
  def event_id(event); event['id']; end
  def session_id(session); session.to_h['__id'].to_i; end
end

def listening_room(game)
  row = {'__id' => 7, 'owner' => 'Alice', 'game' => game.id, 'status' => 'waiting',
    'max_players' => 2, 'name' => 'Test room', 'game_options' => JSON.generate(game.default_options)}
  LobbyRepository::TableSnapshot.new(table: row, members: %w[Alice Bob], bots: [])
end

def invoke_listening_menu(form, label: false)
  menu = FakeMenu.new
  form.context(menu, false)
  item = menu.options.find { |entry| label ? entry[0] == 'Audio Ball settings' : entry[2] == 'p' }
  assert(item, 'The real table form did not expose Audio Ball settings / Ctrl+P')
  item[3].call
end

check('Waiting table opens the real local dialog from Ctrl+P and menu without changing chat or focus') do
  game = GameRoomGames::AudioBall.new
  room = listening_room(game)
  state = GameRoomLifecycle::State.new(room: room, game_snapshot: nil, game: game, replay: nil)
  app = EltenGameRoom.allocate
  {lobby: LobbyRepository.allocate, games: ListeningRepository.new, transport: Object.new,
    game_room_settings: {}}.each { |key, value| app.instance_variable_set("@#{key}", value) }
  tracker = Object.new
  tracker.define_singleton_method(:observe) { |_| [] }
  app.define_singleton_method(:room_membership_tracker) { |_| tracker }
  app.define_singleton_method(:play_game_sounds) { |_| }
  app.define_singleton_method(:announce_new_table_activity) { |_, after_id:| after_id }
  app.define_singleton_method(:room_history_items) { |*| [] }
  app.define_singleton_method(:table_header) { |_| 'Users' }
  app.define_singleton_method(:load_room_state) { |*_, **_options| state }
  app.define_singleton_method(:leave_table_from_screen) { |_| true }
  dialogs = 0
  Form.driver = lambda do |form|
    if form.fields.first.is_a?(ListBox) && form.fields.first.header == 'Your listening side (only for you)'
      dialogs += 1
      form.cancel_button.trigger(:press)
      next
    end
    layout = app.instance_variable_get(:@table_layouts).fetch(7)
    [layout.users, layout.chat].each_with_index do |field, index|
      form.index = form.fields.index(field)
      layout.chat.text, layout.chat.index, layout.chat.check = 'draft', 4, 1
      invoke_listening_menu(form, label: index == 1)
      assert(form.fields[form.index].equal?(field), 'Closing table settings moved focus')
      assert([layout.chat.text, layout.chat.index, layout.chat.check] == ['draft', 4, 1], 'Table settings changed the chat draft')
    end
    layout.back_button.trigger(:press)
  end
  app.send(:show_table_screen, room.table)
  assert(dialogs == 2, 'Waiting-table settings did not open the actual dialog twice')
end

check('Active GameScreen routes Ctrl+P and the menu to its current client without dispatching game actions') do
  game, repository = GameRoomGames::AudioBall.new, ListeningRepository.new
  room = listening_room(game)
  session = {'__id' => 1, 'options' => room.table['game_options']}
  replay = game.replay(session, [], repository)
  client, calls = Object.new, 0
  client.define_singleton_method(:show_settings) { calls += 1 }
  client.define_singleton_method(:context_data) { {} }
  screen = GameScreen.allocate
  controller = Object.new
  controller.define_singleton_method(:cancel) { |_| }
  {game: game, repository: repository, session: session, table: room.table,
    game_services: {},
    bot_turn_controller: controller, board_preferences: GameRoomBoardPreferences.new(nil, game),
    table_owner: 'Alice', room_snapshot: room, surface_state: {}, game_client: client,
    history_navigator: GameRoomHistory::Navigator.new, turn_history_entries: {}, activity_entries: []
  }.each { |key, value| screen.instance_variable_set("@#{key}", value) }
  Form.driver = lambda do |form|
    layout = screen.instance_variable_get(:@layout)
    [layout.surface.fields.first, layout.chat].each_with_index do |field, index|
      form.index = form.fields.index(field)
      layout.chat.text, layout.chat.index, layout.chat.check = 'draft', 4, 1
      invoke_listening_menu(form, label: index == 1)
      assert(form.fields[form.index].equal?(field), 'Active settings moved focus')
      assert([layout.chat.text, layout.chat.index, layout.chat.check] == ['draft', 4, 1], 'Active settings modified chat')
      assert(screen.instance_variable_get(:@selected_surface_action) == nil, 'Personal settings became a game action')
    end
    layout.back_button.trigger(:press)
  end
  assert(screen.send(:wait_for_action, replay, [0, 0]) == :back, 'Personal settings resumed the outer gameplay form')
  assert(calls == 2, 'The active screen did not use its current client settings bridge')
end

check('Binary settings labels support Polish, English and untranslated source beside a translated host') do
  catalog = GameRoomTest::TranslationReference.fetch('audio_ball_settings')
  assert(!catalog.empty?, 'Polish Audio Ball settings reference is missing')
  namespace = Module.new
  %w[preferences settings].each do |name|
    path = File.expand_path("../../../lib/audio_ball/#{name}.rb", __dir__)
    source = defined?(BinaryRulesLoad) ? BinaryRulesLoad.read(path) : File.binread(path)
    namespace.module_eval(source, path, 1)
  end
  previous_language = GameRoomTestLocalization.language
  [:pl, :en, :fallback].each do |language|
    GameRoomTestLocalization.use_language(language)
    catalog.each do |source, translated|
      expected = language == :pl ? translated : source
      assert(GameRoomLocalization.translate(source.b) == expected, "Missing Audio Ball settings translation: #{source}")
    end
    Form.driver = lambda do |form|
      field = form.fields.first
      pack = form.fields[1]
      labels = [field.header, *field.options, pack.header, *pack.options, form.accept_button.label, form.cancel_button.label]
      labels.each do |label|
        assert(label.encoding == Encoding::UTF_8 && label.valid_encoding?, 'Binary settings label was not normalized')
        assert((label + ' — выбранное поле').valid_encoding?, 'Settings label cannot be read beside the host role')
      end
      expected = language == :pl ? 'Twoja strona odsłuchu (tylko dla Ciebie)' : 'Your listening side (only for you)'
      assert(field.header == expected, 'Wrong settings language')
      assert(field.options == (language == :pl ? ['Z prawej (domyślnie)', 'Z lewej'] : ['Right (default)', 'Left']), 'Wrong translated choices')
      field.index = 1
      assert(pack.options == (language == :pl ? ['Domyślny', 'Dźwięki z audiodisca'] : ['Default', 'Sounds from Audiodisc']), 'Wrong pack translations')
      pack.index = 1
      form.accept_button.trigger(:press)
    end
    assert(namespace::GameRoomAudioBall::Settings.new({}, program: nil).wait == {'listening_side' => 'left', 'sound_pack' => 'audiodisc'}, 'Binary settings saved a translated identifier')
  end
ensure
  GameRoomTestLocalization.use_language(previous_language) if previous_language
end

check('Both listening sides preserve real key preparation, attacks, defense, misses and score ordering') do
  require_relative "../../../lib/audio_ball/engine"
  [0, 1].each do |viewer|
    traces = []
    %w[right left].each do |choice|
      program, spoken, now = ListeningProgram.new(choice), [], 0.0
      audio = GameRoomAudioBall::Audio.new(program, clock: -> { now }, speaker: ->(text) { spoken << text })
      engine = GameRoomAudioBall::Engine.new(server: viewer)
      inputs = [0, 1].map do |player|
        spec = GameSurfaces::AudioBallSpec.new(game_id: 'audio_ball', header: 'Audio Ball playfield',
          players: %w[Alice Bob], viewer: player, scores: [4, 7], sets: [0, 1], set_number: 1, finished: false)
        surface = GameSurfaces.build(spec)
        field = surface.fields.first
        keys = []
        field.model_keyboard_input!
        field.define_singleton_method(:key_pressed?) { |key| keys.include?(key) }
        field.define_singleton_method(:key_held?) { |key| keys.include?(key) }
        [surface, Form.new([field, EditBox.new('Chat')]), keys]
      end
      press = lambda do |actor, key|
        surface, form, keys = inputs.fetch(actor)
        $activecontrols = [form, surface.fields.first]
        keys.replace([key]); surface.fields.first.update
        commands = surface.input(form)
        keys.clear; surface.fields.first.update
        assert(commands.length == 1 && engine.press(actor, commands.first), 'Listening preference changed a real gameplay key')
      end
      trace = []
      [[0x27, [0x26, 0x25, 0x28]], [0x41, [0x57, 0x44, 0x53]]].each do |prepare_key, shot_keys|
        shot_keys.zip(%w[up left down]).each do |shot_key, shot|
          holder = engine.holder
          press.call(holder, prepare_key)
          audio.prepare(holder, viewer: viewer)
          audio.update(engine.snapshot, viewer: viewer)
          sign = choice == 'left' ? -1.0 : 1.0
          expected_start = (holder == viewer ? 1.0 : -1.0) * sign
          assert(program.sounds.fetch('audio_ball_prepare').pan == expected_start, 'Preparation is on the wrong personal side')
          press.call(holder, shot_key)
          audio.update(engine.snapshot, viewer: viewer)
          sound = program.sounds.fetch("audio_ball_#{shot}")
          assert(sound.playing? && sound.pan == expected_start, 'Attack starts on the wrong personal side')
          engine.step(engine.duration * 0.96)
          audio.update(engine.snapshot, viewer: viewer)
          assert(sound.pan * expected_start < 0, 'Incoming flight did not cross to the opposite side')
          press.call(engine.receiver, shot_key)
          audio.update(engine.snapshot, viewer: viewer)
          assert(program.sounds.values.none?(&:playing?), 'Defense did not stop the mirrored flight')
          trace << engine.snapshot
        end
      end
      holder = engine.holder
      press.call(holder, 0x41)
      press.call(holder, 0x57)
      audio.update(engine.snapshot, viewer: viewer)
      engine.step(engine.duration)
      audio.update(engine.snapshot, viewer: viewer)
      assert(engine.phase == :over && program.sounds.values.none?(&:playing?), 'Miss did not stop the mirrored flight')
      trace << engine.snapshot
      audio.point([4, 7], sets: [0, 1], set_finished: true, winner: 1, viewer: viewer, finished: false)
      assert(spoken.empty?, 'Result speech overlapped point recordings')
      [3.0, 3.75, 4.5, 5.25].each { |time| now = time; audio.tick }
      expected = viewer == 0 ? 'You lose the set. Sets: 0 to 1.' : 'You win the set. Sets: 1 to 0.'
      numbers = viewer == 0 ? %w[pong_number4 pong_number7] : %w[pong_number7 pong_number4]
      assert(program.played.select { |name| name.start_with?('pong_number') } == numbers, 'Listening side changed recorded score order')
      assert(spoken == [expected], 'Listening side changed set result/participant ordering')
      surface, form, keys = inputs.fetch(viewer)
      field = surface.fields.first
      form.index = 1
      keys.replace([0x41, 0x57]); field.update
      assert(surface.input(form).empty?, 'Chat keys entered the match')
      form.index = 0
      assert(surface.input(form).empty?, 'Chat keys leaked when returning to the playfield')
      keys.replace([0x11, 0x50, 0x57]); field.update
      assert(surface.input(form).empty?, 'Ctrl+P modifiers leaked gameplay input')
      keys.replace([0x57]); field.focus; field.update
      assert(surface.input(form).empty?, 'A held key leaked through focus restoration')
      audio.close
      traces << trace
    end
    assert(traces[0] == traces[1], 'Listening side changed physics, ownership or scoring')
  end
ensure
  $activecontrols = nil
end
