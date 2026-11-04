require_relative '../support/audio_tutorial_native'
load File.join(EltenTestHost.root, 'src/ui/controls/check_box.rb')
Object.send(:remove_const, :CheckBox) if Object.const_defined?(:CheckBox, false)
Object.const_set(:CheckBox, EltenAPI::Controls.const_get(:CheckBox))
FormTimer = EltenAPI::Controls::FormTimer unless defined?(FormTimer)
require_relative '../../lib/game_content'
require_relative '../../lib/game_room_preferences'
require_relative '../../lib/game_room_screens'
require_relative '../support/localization'

def loop_update(*_args); end

def visible_fields(form)
  hidden = form.instance_variable_get(:@hidden)
  form.fields.each_index.reject { |index| hidden[index] }.map { |index| form.fields[index] }
end

def press_space(list, row)
  list.define_singleton_method(:play_sound) { |*_args, **_options| }
  list.define_singleton_method(:alert) { |*_args| }
  list.index = row
  selected = list.instance_variable_get(:@selected)[row]
  selected ? list.deselect_multiselection_indices([row]) : list.select_multiselection_indices([row])
end

class Form
  class << self; attr_accessor :hrtf_driver; end
  def wait; Form.hrtf_driver.call(self); end
end

GameRoomTestLocalization.use_language('en')
games = [{ id: 'audio_ball', name: 'Audio Ball', spatial_audio: false }, { id: 'uno', name: 'UNO', spatial_audio: true },
  { id: 'axel_pong', name: 'Axel Pong', spatial_audio: false }, { id: 'chess', name: 'Chess', spatial_audio: true }]
values = GameRoomPreferences.normalize({}, games.map { |game| game[:id] })
drive = lambda do |&edit|
  Form.hrtf_driver = lambda do |form|
    sections = form.fields.first
    sections.index = 3
    sections.trigger(:move)
    sounds = visible_fields(form)
    switch, list = sounds[1], sounds[2]
    assert(switch.is_a?(CheckBox) && switch.label == 'Use 3D sound (HRTF) to hear other players around the table',
      '3D sound check box does not open Sounds, followed by the game list')
    assert(sounds[3].header == 'All Power Games sounds', 'Volume settings do not follow the 3D sound game list')
    assert(list.header == 'Games with 3D sound' &&
      list.options == ['Select all games', 'Deselect all games', 'UNO', 'Chess'],
      'Game list lacks the action rows or lists audio games')
    edit.call(switch, list)
    form.accept_button.trigger(:press)
  end
  GameRoomScreens::Settings.new(values, games: games, table_watch_available: false).wait
end

saved = drive.call do |switch, list|
  assert(switch.checked && list.game_indices == [0, 1], '3D sound is not on with every game checked by default')
  press_space(list, 1)
  press_space(list, 3)
end
assert(saved['hrtf_enabled'] == true && saved['hrtf_games'] == ['chess'], 'Switch or Deselect all/Chess not saved')
assert(saved['hrtf_known_games'].sort == games.map { |game| game[:id] }.sort, 'Known games not remembered')

values = GameRoomPreferences.normalize(saved, games.map { |game| game[:id] })
again = drive.call do |switch, list|
  assert(switch.checked && list.game_indices == [1], 'Saved 3D sound choices not shown again')
  press_space(list, 0)
  switch.checked = false
end
assert(again['hrtf_games'] == %w[uno chess], 'Select all games did not check every listed game')
assert(GameRoomPreferences.normalize(again, games.map { |game| game[:id] })['hrtf_enabled'] == false,
  'Turning 3D sound off did not survive reloading')

GameRoomTestLocalization.use_language('pl')
using GameRoomLocalization::Translations
assert(_('Games with 3D sound') == 'Gry z dźwiękiem 3D' &&
  _('Use 3D sound (HRTF) to hear other players around the table').start_with?('Używaj dźwięku 3D'),
  'Missing Polish 3D sound labels')
GameRoomTestLocalization.use_language('en')

puts 'PASS settings 3D sound: Sounds check box, then a list with Select all/Deselect all and no audio games, saved and reloaded'
