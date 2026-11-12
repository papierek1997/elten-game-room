require 'json'
require_relative "../../support/ui"
require_relative "../../../lib/game_content"
require_relative "../../../lib/game_surfaces"

def assert(value, message); raise message unless value; end

assert(defined?(GameSurfaces::AudioBallSpec), 'Audio Ball has no surface specification')
class GameSurfaces::AudioBallField
  attr_reader :recorded_tips
  def add_tip(text); (@recorded_tips ||= []) << text; end
end
spec = GameSurfaces::AudioBallSpec.new(game_id: 'audio_ball', header: 'Audio Ball playfield',
  players: ['Alice', 'Bob'], viewer: 0, scores: [0, 0], sets: [0, 0], set_number: 1, finished: false)
surface = GameSurfaces.build(spec)
assert(surface.fields.length == 1 && surface.fields.first.is_a?(Button), 'Audio Ball has no keyboard playfield')
field = surface.fields.first
field.model_keyboard_input!
assert(field.recorded_tips.map { |tip| tip.split(': ', 2).first } == ['Up arrow', 'W', 'Left arrow', 'D', 'Down arrow', 'S', 'Right arrow', 'A'], 'F1 does not expose each gameplay key as its own help row')
rules = JSON.parse(File.read(File.expand_path("../../../tools/data/rulebooks/audio_ball.json", __dir__)))
controls = rules.fetch('sections').find { |section| section['id'] == 'controls' }.fetch('paragraphs')
assert(field.recorded_tips == controls.first(8).map { |row| row['en'] }, 'playfield tips do not match the single-flight defense controls')
pressed, held = [], []
field.define_singleton_method(:key_pressed?) { |key| pressed.include?(key) }
field.define_singleton_method(:key_held?) { |key| held.include?(key) }
form = Form.new([field, EditBox.new('Chat')])
$activecontrols = [form, field]
assert(surface.respond_to?(:input), 'Audio Ball cannot receive playfield input')
{0x26 => 'up', 0x57 => 'up', 0x25 => 'left', 0x44 => 'left',
  0x28 => 'down', 0x53 => 'down', 0x27 => 'prepare', 0x41 => 'prepare'}.each do |code, action|
  pressed.replace([code]); held.replace([code]); field.update
  assert(surface.input(form) == [action], "wrong Audio Ball mapping for #{code}")
  assert(surface.input(form).empty?, 'a brief press was performed twice')
  pressed.clear; held.clear; field.update
end
[0x10, 0x11, 0x12].each do |modifier|
  pressed.replace([0x53, 0x57]); held.replace([modifier]); field.update
  assert(surface.input(form).empty?, 'Shift+S or Ctrl+W became a game hit')
end
held.clear; pressed.replace([0x26]); field.update
form.index = 1
assert(surface.input(form).empty?, 'chat input became a game hit')
form.index = 0
assert(surface.input(form).empty?, 'chat press was delayed until returning to the field')
field.update; $activecontrols = []
assert(surface.input(form).empty?, 'background input became a game hit')
$activecontrols = [form, field]
held.replace([0x26]); field.focus; field.update
assert(surface.input(form).empty?, 'held key struck on refocusing')
held.clear; pressed.clear; field.update
pressed.replace([0x26]); held.replace([0x26]); field.update
assert(surface.input(form) == ['up'], 'fresh press after refocusing did not work')
assert(surface.respond_to?(:handle_command), 'Audio Ball readouts are not connected')
updated = GameSurfaces::AudioBallSpec.new(**spec.to_h.merge(scores: [12, 10], sets: [1, 0], set_number: 2))
assert(surface.reusable_for?(updated), 'score refresh would replace the focused playfield')
assert(surface.update_spec(updated).equal?(surface) && surface.fields.first.equal?(field), 'score refresh lost focus or field identity')
surface.present({'server' => 1}, 'Match in progress.')
$spoken_messages.clear
surface.handle_command('scores')
assert($spoken_messages.length == 1 && $spoken_messages.first.include?('Alice') &&
  $spoken_messages.first.include?('12') && $spoken_messages.first.include?('10') &&
  $spoken_messages.first.include?('Sets: 1'), 'Shift+S did not read both points and sets')
surface.handle_command('server')
assert($spoken_messages.last == 'Bob serves. Match in progress.', 'singles readout names the receiver or loses connection status')
commands = []
surface.on_audio_ball_command = ->(command) { commands << command }
surface.handle_command('hurry')
assert(commands == ['hurry'], 'Ctrl+W did not reach the Audio Ball client')
observer = GameSurfaces.build(GameSurfaces::AudioBallSpec.new(**spec.to_h.merge(viewer: nil)))
observer_field = observer.fields.first
observer_field.model_keyboard_input!
observer_field.define_singleton_method(:key_pressed?) { |code| code == 0x26 }
observer_field.define_singleton_method(:key_held?) { |_code| false }
$activecontrols = [observer_field]
observer_field.update
assert(observer.input(Form.new(observer.fields)).empty?, 'spectator can hit the ball')
assert(surface.state == {}, 'surface stores authoritative game state')
$activecontrols = nil
puts 'PASS Audio Ball surface: registration, eight keys, modifiers, focus/chat, observer, readouts and reuse'

pressed.clear; held.clear; field.update; field.take_input
pressed.replace([0x28, 0x26]); field.update
assert(field.take_input.empty?, 'UI double without host chronology invented the last lane from KEYS order')
pressed.replace([0x26]); field.update
assert(field.take_input == ['up'], 'UI double fallback rejected a single released press')
puts 'PASS Audio Ball UI-double fallback: single key accepted, ambiguous simultaneous input ignored'

# T uses the same concise singles wording for both players and observers.
# Doubles still needs the actual service pair, including non-interleaved seats.
[0, 1, nil].each do |viewer|
  single = GameSurfaces.build(GameSurfaces::AudioBallSpec.new(**spec.to_h.merge(viewer: viewer)))
  [0, 1].each do |server|
    single.present({'server' => server}, '')
    single.handle_command('server')
    assert($spoken_messages.last == "#{spec.players[server]} serves.", 'T adds a redundant singles receiver')
  end
  single.present({'server' => 1}, 'Game paused.')
  single.handle_command('server')
  assert($spoken_messages.last == 'Bob serves. Game paused.', 'T lost pause status')
end
doubles = GameSurfaces.build(GameSurfaces::AudioBallSpec.new(**spec.to_h.merge(
  players: %w[Alice Bob Carol Dave], teams: [0, 0, 1, 1], viewer: nil)))
['Alice serves to Carol.', 'Bob serves to Dave.', 'Carol serves to Bob.', 'Dave serves to Alice.'].each_with_index do |expected, server|
  doubles.present({'server' => server}, '')
  doubles.handle_command('server')
  assert($spoken_messages.last == expected, 'T lost the doubles receiver or used the wrong rotation')
end
doubles.present({}, 'Waiting for players.')
doubles.handle_command('server')
assert($spoken_messages.last == 'Waiting for players.', 'T invents a server before the draw')
puts 'PASS Audio Ball T readout: singles players/observer, pause/connection status, every doubles service pair'
