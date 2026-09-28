# encoding: UTF-8
require_relative 'support/host_source'
# Uses binary-loaded production sources and the real PL dictionary, like the
# installed runtime, without reading or changing a user's settings file.
require_relative 'support/pong_ui' unless defined?(BinaryRuleDictionary)
require_relative 'support/pong_client' unless defined?(PongHarness)

def _(source)
  return source if $rules_english
  $rules_dictionary.send(:_, source)
end

class CheckBox < FakeControl
  attr_accessor :label, :checked
  def initialize(label, checked: false); super(); @label, @checked = label, checked; end
end unless defined?(CheckBox)
module Configuration
  def self.controlspresentation; :voice_only; end
end
module EltenAPI
  module Controls
    class FormField; end
  end
end
host = EltenTestHost.root
load File.join(host, 'src/ui/controls/check_box.rb')
native_checkbox = EltenAPI::Controls.const_get(:CheckBox)
def p_(_context, source); "Флажок #{source}"; end

defaults = GameRoomPong::Preferences::DEFAULTS
assert(GameRoomPong::Preferences.normalize(nil) == defaults, 'missing preference defaults')
assert(GameRoomPong::Preferences.normalize('auto_return'=>'true', 'own_volume'=>-2,
  'opponent_volume'=>230, 'announcer_volume'=>'20') ==
  {'auto_return'=>false, 'own_volume'=>0, 'opponent_volume'=>200, 'announcer_volume'=>100}, 'malformed preferences')
state = {'unrelated'=>'keep', 'pong'=>defaults.dup, 'table_watch_games'=>['uno']}
reads, writes, network = 0, 0, 0
app = EltenGameRoom.new
app.define_singleton_method(:read_json) { |file, default:| assert(file == 'settings.json', 'wrong local file'); reads += 1; state }
app.define_singleton_method(:update_json) { |file, default:, &block| assert(file == 'settings.json', 'wrong save file'); writes += 1; state = block.call(state); state }
app.define_singleton_method(:run_network_task) { |*| network += 1; raise 'Pong settings loaded network preferences' }
100.times { assert(app.send(:pong_preferences) == defaults, 'cached read differs') }
assert(reads == 1 && writes.zero? && network.zero?, 'personal read causes repeated IO')

driver = nil
old_wait = Form.instance_method(:wait)
old_resume = Form.instance_method(:resume) if Form.method_defined?(:resume)
Form.send(:define_method, :wait) { driver.call(self) }
Form.send(:define_method, :resume) { nil }
dictionary = $rules_dictionary
old_english = $rules_english
old_language = GameRoomTestLocalization.language
begin
  [:pl, :en, :fallback].each do |language|
    GameRoomTestLocalization.use_language(language)
    $rules_english = language == :en
    $rules_dictionary = language == :fallback ? BinaryRuleDictionary.new({}) : dictionary
    expected_labels = language == :pl ? ['Głośność ruchu Twojej paletki', 'Głośność ruchu paletki przeciwnika', 'Głośność lektora'] :
      ['Your paddle volume', 'Opponent paddle volume', 'Announcer volume']
    driver = lambda do |form|
      check, *rest = form.fields
      assert(form.fields.length == 6, 'unexpected local panel fields')
      native_checkbox.new(check.label, checked: check.checked).focus
      assert($spoken_messages.last.encoding == Encoding::UTF_8 && $spoken_messages.last.valid_encoding?, 'native checkbox mixed encoding')
      assert(rest.first(3).map(&:header) == expected_labels, 'panel language mismatch')
      rest.first(3).each do |field|
        assert((field.header + ' Флажок').valid_encoding? && field.options.length == 201, 'volume encoding/range')
      end
      check.checked = true
      rest[0].index, rest[1].index, rest[2].index = 75, 150, 40
      form.accept_button.trigger(:press)
    end
    app.send(:show_pong_settings)
    wanted = {'auto_return'=>true, 'own_volume'=>75, 'opponent_volume'=>150, 'announcer_volume'=>40}
    assert(app.send(:pong_preferences) == wanted && state['pong'] == wanted, 'quick panel not persisted')
    assert(state['unrelated'] == 'keep' && state['table_watch_games'] == ['uno'] && network.zero?, 'local panel altered unrelated data')
    driver = lambda do |form|
      assert(!form.fields.first.options.include?('Axel Pong'), 'Game Room settings still list a Pong category')
      assert(form.fields.none? { |field| expected_labels.include?(field.header.to_s) }, 'Game Room settings still contain Pong controls')
      form.accept_button.trigger(:press)
    end
    edited = GameRoomScreens::Settings.new(app.send(:game_room_settings), games: [], program: app).wait
    assert(edited['pong'] == wanted, 'Game Room settings changed Pong preferences')
    before = Marshal.dump(state)
    driver = lambda do |form|
      form.fields[0].checked = false; form.fields[1].index = 0
      form.cancel_button.trigger(:press)
    end
    app.send(:show_pong_settings)
    assert(Marshal.dump(state) == before && app.send(:pong_preferences) == wanted, 'Cancel changed preferences')
    copy = EltenGameRoom.new
    copy.define_singleton_method(:read_json) { |_, default:| state }
    assert(copy.send(:pong_preferences) == wanted, 'personal settings did not survive a fresh program instance')
  end

  # Ctrl+P is a real context-menu key at a Pong table, not a global host hook.
  [GameRoomGames::AxelPong.new, GameRoomGames::Makao.new].each do |game|
    list = ListBox.new(['Alice'], header: 'Users')
    layout = Struct.new(:form, :users, :back_button).new(Form.new([list]), list, nil)
    called = 0
    GameRoomParticipantMenu.bind(layout, available: -> { [] }, game: game,
      pong_settings: -> { called += 1 }) { raise 'settings resumed or dispatched a game action' }
    found = []
    menu = Object.new
    menu.define_singleton_method(:option) do |label, _unused, key, &action|
      found << key
      action.call if key == 'p'
    end
    layout.form.context(menu)
    assert(called == (game.id == 'axel_pong' ? 1 : 0), 'Ctrl+P scope/callback incorrect')
  end

  # Keep the real client frame running inside this particular dialog. Neither
  # mouse nor keyboard from it may steer or hit; restore them after closing.
  h = PongHarness.new
  begin
    h.advance(220)
    client = h.clients['Alice']
    h.surfaces['Alice'].define_singleton_method(:input_active?) { |_| true }
    app.instance_variable_set(:@game_room_settings, GameRoomPreferences.normalize(state, []))
    app.instance_variable_set(:@pong_preferences, defaults.dup)
    client.instance_variable_set(:@program, app)
    e = client.engine
    e.ball.merge!('x'=>15, 'y'=>8, 'dy'=>1, 'speed'=>0.1)
    start_y = e.ball['y']; start_x = e.paddles[0]
    h.surfaces['Alice'].controls.merge!('move'=>1, 'press'=>10, 'hit'=>true)
    captured = nil
    driver = lambda do |form|
      captured = form
      12.times do
        h.now += 0.016
        form.instance_variable_get(:@timers).each(&:update)
        h.clients.each { |name, c| c.frame unless name == 'Alice' }
      end
      assert(e.ball['y'] > start_y, 'opening local settings froze ball simulation')
      assert(e.paddles[0] == start_x, 'dialog input moved the paddle')
      assert(e.events.none? { |fx| %w[hit serve].include?(fx[1]) }, 'dialog input returned/served')
      form.cancel_button.trigger(:press)
    end
    client.show_settings
    assert(captured.instance_variable_get(:@timers).empty? && !client.instance_variable_get(:@settings_open), 'modal timer/input guard leaked')
    driver = ->(_form) { raise 'simulated UI failure' }
    begin
      client.show_settings
    rescue RuntimeError => error
      raise unless error.message == 'simulated UI failure'
    end
    assert(!client.instance_variable_get(:@settings_open), 'failed dialog retained input guard')
  ensure
    h.close
  end
ensure
  Form.send(:define_method, :wait, old_wait)
  old_resume ? Form.send(:define_method, :resume, old_resume) : Form.send(:remove_method, :resume)
  $rules_dictionary, $rules_english = dictionary, old_english
  GameRoomTestLocalization.use_language(old_language)
end
puts 'PASS local Pong settings: binary PL/EN/fallback, native checkbox, persistence/cancel/cache, shared category, Ctrl+P scope and live modal timer'
