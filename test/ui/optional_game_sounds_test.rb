require_relative '../support/volume_and_help'
require_relative '../../lib/game_sounds'
require_relative '../../lib/game_audio'

def assert(value, message); raise message unless value; end
def loop_update(*_args); Thread.pass; end
state = EltenGameRoom::DEFAULT_SETTINGS.dup
app = EltenGameRoom.allocate
app.define_singleton_method(:read_json) { |_path, default:| state }
app.define_singleton_method(:update_json) do |_path, default:, &block|
  block.call(state)
  state
end
app.define_singleton_method(:background_music) { nil }
played = []
app.define_singleton_method(:play_sound_from_asset) do |name, **options|
  played << [name, options]
  Struct.new(:volume).new(options.fetch(:volume, 1.0))
end
app.define_singleton_method(:release) { |_sound, **_| }
app.define_singleton_method(:manage) { |_| }
EltenGameRoom.remember_settings(state)
levels = EltenGameRoom.normalized_settings.fetch('sound_volumes')
field = ListBox.new(['item'], header: 'Game')
form = GameRoomUI::Form.new([field], program: app)
form.instance_variable_set(:@game_room_waiting, true)
$activecontrols = [form, field]
GameRoomUI.install_hotkeys
actions = EltenAPI::QuickActions.hotkey_actions(14)
assert(actions.size == 1, 'Ctrl+F2 is missing from the active application form')
actions.each(&:call)
assert(!app.send(:game_room_optional_sounds?) && state['optional_game_sounds'] == false, 'Ctrl+F2 did not persist the setting')
assert(EltenGameRoom.normalized_settings['sound_volumes'] == levels, 'Optional effects toggle changed audio volumes')
GameRoomSounds.play(app, 'draw')
assert(played.empty?, 'Decorative drawing cue remained audible')
%w[chatmsg connect notice ding].each { |name| GameRoomSounds.play(app, name) }
assert(played.map(&:first) == %w[chatmsg connect notice ding], 'Chat, membership, notification or turn cue was muted')
# Essential audio engines output through SoundOutput, not the optional event
# selector. Muting presentation effects must not gate their streaming samples.
GameRoomSoundOutput.play(app, 'essential-listening-sample', volume: 0.7)
assert(played.last.first == 'essential-listening-sample' && played.last.last[:volume] == 0.7,
  'The optional toggle changed essential realtime/listening output')
actions.each(&:call)
GameRoomSounds.play(app, 'draw')
assert(played.last.first == 'draw' && state['optional_game_sounds'], 'Second Ctrl+F2 did not restore effects')
form.instance_variable_set(:@game_room_waiting, false)
assert(EltenAPI::QuickActions.hotkey_actions(14) != actions, 'Ctrl+F2 leaked into other Elten windows')
EltenGameRoom.instance_variable_get(:@volume_settings)&.close
$activecontrols = []
puts 'PASS optional effects: scoped native Ctrl+F2, persisted toggle, unchanged volumes and essential audio/other cues'
