require_relative '../support/table_watch_runtime'

class Form
  class << self; attr_accessor :display_name_save_driver; end
  def wait; Form.display_name_save_driver.call(self); end
end

GameRoomLocalization.boot(settings: {}, host_language: 'en')
stored = GameRoomPreferences.normalize(EltenGameRoom::DEFAULT_SETTINGS, EltenGameRoom::GAME_REGISTRY.ids)
app = EltenGameRoom.allocate
app.instance_variable_set(:@server_tables, Struct.new(:available?).new(false))
notices, publications = [], []
fail_save, outcome = false, false
app.define_singleton_method(:game_room_settings) { |**_| Marshal.load(Marshal.dump(stored)) }
app.define_singleton_method(:update_json) do |_, default:, &operation|
  draft = operation.call(Marshal.load(Marshal.dump(stored)))
  raise IOError, 'settings write failed' if fail_save
  stored = draft
end
app.define_singleton_method(:run_network_task) { |_, **_, &operation| operation.call }
app.define_singleton_method(:alert) { |message| notices << message }
music = Object.new
music.define_singleton_method(:update) { |**_| }
music.define_singleton_method(:enter) { }
music.define_singleton_method(:leave) { }
app.define_singleton_method(:background_music) { music }
EltenGameRoom.define_singleton_method(:contacts_settings_changed) { |_| }
transport = Object.new
transport.define_singleton_method(:publish_display_name) do
  assert(stored['display_name'] == GameRoomParticipants.local_display_name, 'profile published before confirmed persistence')
  publications << stored['display_name']
  outcome
end
app.instance_variable_set(:@transport, transport)
draft, cancel = 'Anna Kowalska', false
Form.display_name_save_driver = lambda do |form|
  name = form.fields.find { |field| field.is_a?(EditBox) && field.header == 'Display name' }
  name.text = draft
  (cancel ? form.cancel_button : form.accept_button).trigger(:press)
end
app.send(:show_settings)
assert(stored['display_name'] == 'Anna Kowalska' && publications == ['Anna Kowalska'], 'first Save failed')
assert(notices.last.include?('display name could not be updated'), 'failed profile publication was hidden')
outcome = true
app.send(:show_settings)
assert(publications == ['Anna Kowalska', 'Anna Kowalska'], 'unchanged Save did not retry unconfirmed publication')
assert(notices.last == 'Settings saved.', 'confirmed retry retained an error')
draft, cancel = 'Discarded Name', true
app.send(:show_settings)
assert(stored['display_name'] == 'Anna Kowalska' && publications.length == 2, 'Cancel wrote settings or a profile')
cancel, fail_save = false, true
begin
  app.send(:show_settings)
  raise 'failed persistence was accepted'
rescue IOError
  assert(publications.length == 2 && GameRoomParticipants.local_display_name == 'Anna Kowalska', 'failed persistence published a name')
end
puts 'PASS real General Save flow: confirmed local save precedes publication, failure feedback, unchanged retry, Cancel and failed-persistence isolation'
