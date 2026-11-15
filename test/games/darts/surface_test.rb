# encoding: UTF-8
require_relative '../../support/ui'
require_relative '../../../lib/game_content'
require_relative '../../../lib/game_surfaces'

def assert(value, message)
  raise message unless value
end

spec = GameSurfaces::DartsSpec.new(
  game_id: 'darts', header: 'Darts playfield', players: ['Alice'], viewer: 0,
  current_player: 0, throw_index: 0, round: 1, dart: 1,
  difficulty: 'normal', scores: [0], active: true, finished: false,
  training: false
)
surface = GameSurfaces.build(spec)
field = surface.fields.first

assert(field.is_a?(GameSurfaces::DartsField), 'Darts has no keyboard playfield')
assert(!GameSurfaces::DartsField.private_instance_methods(false).include?(:modifier_held?),
  "Darts shadows Elten's modifier_held?(modifier) input helper")
assert(GameSurfaces::DartsField.private_instance_methods(false).include?(:game_modifier_held?),
  'Darts lost its game-specific modifier guard')

pressed, held = [], []
field.define_singleton_method(:key_pressed?) { |key| pressed.include?(key) }
field.define_singleton_method(:key_held?) { |key| held.include?(key) }
form = Form.new([field, EditBox.new('Chat')])
$activecontrols = [form, field]

pressed << :key_right
field.update
assert(surface.input(form) == [:right], 'right arrow did not reach the Darts client')
assert(surface.input(form).empty?, 'one Darts arrow press was consumed twice')

pressed.replace([:key_space])
field.update
assert(surface.input(form) == [:throw], 'Space did not create a Darts throw')

surface.update_spec(spec.dup.tap { |copy| copy.header = 'Throw 2 round 8' })
assert(field.label == 'Throw 2 round 8', 'Darts playfield did not retain the current throw and round for speech or Braille')

held << 0x11
pressed.replace([:key_left])
field.update
assert(surface.input(form).empty?, 'Ctrl+Left became a Darts movement')

form.index = 1
held.clear
pressed.replace([:key_up])
field.update
assert(surface.input(form).empty?, 'chat navigation became a Darts movement')

$activecontrols = nil
puts 'PASS Darts surface: host modifier helper preserved, arrows/Space routed, shortcuts and chat isolated'
