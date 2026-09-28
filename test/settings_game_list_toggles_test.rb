require_relative 'support/audio_tutorial_native'
load File.join(EltenTestHost.root, 'src/ui/controls/check_box.rb')
Object.send(:remove_const, :CheckBox) if Object.const_defined?(:CheckBox, false)
Object.const_set(:CheckBox, EltenAPI::Controls.const_get(:CheckBox))
FormTimer = EltenAPI::Controls::FormTimer unless defined?(FormTimer)
require_relative '../lib/game_content'
require_relative '../lib/game_room_preferences'
require_relative '../lib/game_room_screens'
require_relative 'support/localization'

def loop_update(*_args); end

def visible_fields(form)
  hidden = form.instance_variable_get(:@hidden)
  form.fields.each_index.reject { |index| hidden[index] }.map { |index| form.fields[index] }
end

def press_space(list, row)
  list.index = row
  selected = list.instance_variable_get(:@selected)[row]
  selected ? list.deselect_multiselection_indices([row]) : list.select_multiselection_indices([row])
end

def action_rows(list)
  [0, 1].map { |row| list.instance_variable_get(:@selected)[row] == true }
end

def silence(list)
  list.define_singleton_method(:play_sound) { |*_args, **_options| }
  list.define_singleton_method(:alert) { |*_args| }
  list
end

GameRoomTestLocalization.use_language('en')
games = [{ id: 'uno', name: 'UNO' }, { id: 'makao', name: 'Makao' }, { id: 'chess', name: 'Chess' }]
list = silence(GameRoomScreens::GameList.new(games, header: 'Games', selected: ['makao']))
assert(list.instance_of?(GameRoomScreens::GameList) && list.is_a?(EltenAPI::Controls::ListBox), 'Game list is not a native list')
assert(list.options == ['Select all games', 'Deselect all games', 'UNO', 'Makao', 'Chess'],
  'Select all and Deselect all are not the first two rows above the games')
assert(list.game_indices == [1] && action_rows(list) == [false, false], 'Saved selection or action rows are wrong')

press_space(list, 0)
assert(list.game_indices == [0, 1, 2] && action_rows(list) == [true, false], 'Select all games did not check every game')
press_space(list, 1)
assert(list.game_indices.empty? && action_rows(list) == [false, true], 'Deselect all games did not clear every game')
press_space(list, 3)
assert(list.game_indices == [1] && action_rows(list) == [false, false], 'Checking one game left an action row checked')
press_space(list, 2)
press_space(list, 4)
assert(list.game_indices == [0, 1, 2] && action_rows(list) == [true, false], 'Checking the last game did not update Select all games')
press_space(list, 2)
assert(list.game_indices == [1, 2] && action_rows(list) == [false, false], 'Unchecking a game left Select all games checked')
press_space(list, 0)
press_space(list, 0)
assert(list.game_indices.empty? && action_rows(list) == [false, true], 'Unchecking Select all games did not clear the games')
press_space(list, 1)
assert(list.game_indices == [0, 1, 2] && action_rows(list) == [true, false], 'Unchecking Deselect all games did not check the games')
list.send(:deselect_all_multiselection_items)
assert(list.game_indices.empty? && action_rows(list) == [false, true], 'Host Deselect all left inconsistent action rows')
list.send(:select_all_multiselection_items)
assert(list.game_indices == [0, 1, 2] && action_rows(list) == [true, false], 'Host Select all left inconsistent action rows')

empty = GameRoomScreens::GameList.new([], header: 'Games', selected: [])
assert(empty.game_indices.empty? && action_rows(empty) == [false, true], 'Empty game list crashed or checked Select all')

GameRoomTestLocalization.use_language('pl')
polish = GameRoomScreens::GameList.new(games, header: 'Gry', selected: [])
assert(polish.options.first(2) == ['Zaznacz wszystkie gry', 'Odznacz wszystkie gry'], 'Missing Polish action rows')
assert(polish.options.first(2).all? { |label| label.encoding == Encoding::UTF_8 && label.valid_encoding? }, 'Action rows are not UTF-8')
GameRoomTestLocalization.use_language('en')

class Form
  class << self; attr_accessor :toggle_driver; end
  def wait; Form.toggle_driver.call(self); end
end

values = GameRoomPreferences.defaults(games.map { |game| game[:id] }).merge(
  'lobby_games' => ['uno'], 'widget_games' => [], 'invitation_notifications' => 'contacts')
snapshot = { state: :loading, games: [] }
Form.toggle_driver = lambda do |form|
  sections = form.fields.first
  assert(sections.options == ['General', 'Lobby messages', 'Notification settings', 'Sounds', 'Widget'],
    'Settings categories still contain Axel Pong or lost a category')
  visible = lambda do |index|
    sections.index = index
    sections.trigger(:move)
    visible_fields(form)
  end

  lobby = visible.call(1)
  assert(lobby[1].header == 'Games covered by lobby messages' && lobby[1].options.first(2) == ['Select all games', 'Deselect all games'],
    'Lobby game list does not start with the action rows')
  assert(lobby.grep(CheckBox).map(&:label).include?('Announce when a computer is added to or removed from a table'), 'Computer label not updated')
  assert(lobby.grep(CheckBox).none? { |field| field.label.to_s.end_with?('all games') }, 'Separate toggle checkboxes remain')
  press_space(silence(lobby[1]), 0)

  notifications = visible.call(2)
  policy = notifications[1]
  assert(policy.options == ['From everyone', 'From contacts', 'From nobody'] && policy.index == 1,
    'Invitation choices are not ordered from everyone to nobody')
  snapshot = { state: :ready, games: ['makao'] }
  timers = form.instance_variable_get(:@timers)
  assert(timers.length == 1, 'Subscription loader timer was not registered on the native form')
  timers.first.instance_variable_get(:@action).call
  watched = visible.call(2)[2]
  assert(watched.header == 'Notify me about games on public tables' && watched.options.first(2) == ['Select all games', 'Deselect all games'],
    'Loaded subscription list does not start with the action rows')
  assert(watched.game_indices == [1], 'Loaded subscriptions not reflected')
  press_space(silence(watched), 1)
  policy.index = 0

  widget = visible.call(4)
  assert(widget[2].header == 'Games shown on the main screen' && widget[2].options.first(2) == ['Select all games', 'Deselect all games'],
    'Widget game list does not start with the action rows')
  press_space(silence(widget[2]), 0)
  form.accept_button.trigger(:press)
end
saved = GameRoomScreens::Settings.new(values, games: games, table_watch_available: false, table_watch_loader: -> { snapshot }).wait
assert(saved['lobby_games'] == %w[uno makao chess], 'Lobby selection from Select all games was not saved')
assert(saved['widget_games'] == %w[uno makao chess], 'Widget selection from Select all games was not saved')
assert(saved['table_watch_games'] == [], 'Subscription selection from Deselect all games was not saved')
assert(saved['invitation_notifications'] == 'everyone', 'Reordered invitation choice saved the wrong policy')
assert(!saved.key?('pong'), 'Game Room settings returned Pong preferences')

Form.toggle_driver = ->(form) { form.cancel_button.trigger(:press) }
assert(GameRoomScreens::Settings.new(values, games: games, table_watch_available: false).wait.nil?, 'Cancel saved settings')

puts 'PASS settings game lists: Select all and Deselect all rows in native lists, lobby/subscriptions/widget, host select-all, PL labels, reordered invitations, no Pong category'
