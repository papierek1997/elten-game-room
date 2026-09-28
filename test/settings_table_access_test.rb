require_relative 'support/ui'

class Program
  def self.server_app(**_options); end
  def self.app_runtime; nil; end
end
module Session
  def self.name; 'Alice'; end
end
class CheckBox < FakeControl
  attr_accessor :checked
  attr_reader :label
  def initialize(label, checked: false)
    super()
    @label, @checked = label, checked
  end
end
class Form
  class << self; attr_accessor :settings_access_driver; end
  def wait; Form.settings_access_driver.call(self); end
  def resume; end
end
class FormTimer
  def initialize(*_args, **_kwargs, &block); @callback = block; end
  def update; @callback.call; end
end

require_relative '../__app'

def assert(condition, message)
  raise message unless condition
end

GameRoomLocalization.boot(settings: { 'interface_language' => 'en' }, host_language: 'en')
provider = Struct.new(:available?).new(false)
stored = GameRoomPreferences.defaults(EltenGameRoom::GAME_REGISTRY.ids).merge('sentinel' => 'keep')
repository = Object.new
reads, writes, cache_updates, notices, local_writes, tasks = [], [], [], [], [], []
loaded, save_result, mode = ['uno'], ['makao'], :load_failure
repository.define_singleton_method(:load) { |user| reads << user; loaded }
repository.define_singleton_method(:save) { |user, games| writes << [user, games]; save_result }
EltenGameRoom.define_singleton_method(:table_watch_repository) { repository }
EltenGameRoom.define_singleton_method(:table_watch_set_games) { |games| cache_updates << games }
EltenGameRoom.define_singleton_method(:table_watch_start) do |refresh:|
  raise 'Settings must explicitly refresh' unless refresh
  reads << 'Alice'
  cache_updates << loaded unless mode == :load_failure
end
EltenGameRoom.define_singleton_method(:table_watch_preferences_snapshot) do
  { state: mode == :load_failure ? :unavailable : :ready, games: loaded }
end
EltenGameRoom.define_singleton_method(:contacts_settings_changed) { |_settings| }

app = EltenGameRoom.allocate
app.instance_variable_set(:@server_tables, provider)
app.define_singleton_method(:game_room_settings) { |**_options| Marshal.load(Marshal.dump(stored)) }
app.define_singleton_method(:run_network_task) do |title, **_options, &operation|
  tasks << title
  next nil if mode == :load_failure && title == 'Loading notification settings'
  next nil if mode == :save_failure && title == 'Saving notification settings'
  operation.call
end
app.define_singleton_method(:alert) { |message| notices << message }
app.define_singleton_method(:update_json) do |path, default:, &operation|
  raise 'Unexpected local destination' unless path == 'settings.json'
  stored = operation.call(Marshal.load(Marshal.dump(stored)))
  local_writes << Marshal.load(Marshal.dump(stored))
end

opened = 0
available = false
cancel = false
select_games = nil
select_language = nil
Form.settings_access_driver = lambda do |form|
  opened += 1
  form.instance_variable_get(:@timers).to_a.each(&:update)
  sections = form.fields.first
  assert(sections.options.length == 5, 'Some local settings categories disappeared')
  sections.options.each_index do |index|
    sections.index = index
    sections.trigger(:move)
    assert((form.fields - form.hidden_controls).size > 3, 'A settings category is empty')
  end
  sections.index = 2
  sections.trigger(:move)
  controls = form.fields - form.hidden_controls
  watched = controls.find { |control| control.header.to_s.start_with?('Notify me about games on public tables') }
  assert(watched, 'Missing subscriptions field or explanation')
  if available
    assert(watched.is_a?(ListBox), 'Available subscriptions cannot be edited')
    if select_games
      offset = GameRoomScreens::GameList::ACTION_ROWS
      watched.deselect_multiselection_indices(watched.game_indices.map { |index| index + offset })
      ids = EltenGameRoom::GAME_REGISTRY.ids
      watched.select_multiselection_indices(select_games.map { |id| ids.index(id) + offset })
    end
  else
    assert(watched.is_a?(EditBox) && watched.flags & EditBox::Flags::ReadOnly != 0,
      'Unavailable subscriptions look editable')
    assert(watched.text.include?('Other settings'), 'No explanation of partial availability')
  end
  controls.find { |control| control.header == 'Show invitation notifications from' }.index = 1
  if select_language
    primary = form.fields.find { |control| control.header == 'Primary interface language' }
    primary.index = GameRoomLocalization.available_languages.index { |language| language[:id] == select_language }
    primary.trigger(:move)
  end
  form.fields.find { |control| control.header == 'Game sounds' }.index = 35
  form.fields.find { |control| control.is_a?(CheckBox) && control.label == 'Read table messages outside the table window' }.checked = false
  cancel ? form.cancel_button.trigger(:press) : form.accept_button.trigger(:press)
end

app.send(:show_settings)
assert(opened == 1, 'Denied tables prevent opening the local settings dialog')
assert(tasks.empty? && reads.empty? && writes.empty?, 'Known table denial still causes server operations')
assert(cache_updates.empty?, 'Unknown subscriptions replaced the in-memory subscription selection')
assert(stored['sound_volumes']['game'] == 35 && !stored['background_table_speech'] &&
  stored['invitation_notifications'] == 'contacts' && stored['sentinel'] == 'keep', 'Local settings were not saved')
assert(!stored.key?('table_watch_games'), 'Unavailable server preferences were copied into local settings')

cancel = true
before = Marshal.dump(stored)
app.send(:show_settings)
assert(local_writes.size == 1 && before == Marshal.dump(stored), 'Cancel saved settings')
cancel = false

provider[0], mode = true, :load_failure
app.send(:show_settings)
assert(opened == 3 && local_writes.size == 2, 'Read failure/cancellation blocks local settings')
assert(cache_updates.empty? && writes.empty?, 'Failed read cleared or overwrote subscriptions')

mode, available, loaded = :normal, true, []
select_games = ['makao']
app.send(:show_settings)
assert(writes.last == ['Alice', ['makao']] && cache_updates.last == ['makao'], 'Successful first subscription was not saved')

loaded, select_games, mode = ['uno'], ['makao'], :save_failure
app.send(:show_settings)
assert(local_writes.size == 4 && cache_updates.last == ['uno'], 'Failed server save blocked locals or claimed unconfirmed preferences')
assert(notices.last.start_with?('Local settings saved.') && notices.last.include?('could not be saved'), 'Partial save was reported as complete success')

mode, select_games = :normal, nil
app.send(:show_settings)
assert(opened == 6 && local_writes.size == 5 && cache_updates.last == ['uno'], 'Access did not recover on a later opening')
assert(writes.size == 1, 'An unchanged or inaccessible selection triggered an unwanted server write')
mode, select_games, select_language = :save_failure, ['makao'], 'pl'
app.send(:show_settings)
assert(stored['interface_language'] == 'pl' && notices.last.include?('could not be saved.') &&
  notices.last.include?('Restart ELTEN'), 'Partial server save lost the language choice or its restart notice')
puts 'Settings: restricted/read failure/cancel/recovery, all local categories, no subscription loss and partial save: OK'
