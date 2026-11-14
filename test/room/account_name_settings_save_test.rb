require_relative '../support/table_watch_runtime'

class Form
  class << self; attr_accessor :account_settings_driver; end
  def wait; Form.account_settings_driver.call(self); end
end
GameRoomLocalization.boot(settings: {}, host_language: 'en')
stored = GameRoomPreferences.normalize(EltenGameRoom::DEFAULT_SETTINGS, EltenGameRoom::GAME_REGISTRY.ids).merge('display_name'=>'Old Name')
app = EltenGameRoom.allocate
app.instance_variable_set(:@server_tables, Struct.new(:available?).new(false))
notices = []
app.define_singleton_method(:game_room_settings) { |**_| Marshal.load(Marshal.dump(stored)) }
app.define_singleton_method(:update_json) do |_, default:, &operation|
  stored = operation.call(Marshal.load(Marshal.dump(stored)))
end
app.define_singleton_method(:run_network_task) { |*| raise 'Saving local settings attempted a profile publication' }
app.define_singleton_method(:alert) { |message| notices << message }
music = Object.new
music.define_singleton_method(:update) { |**_| }
music.define_singleton_method(:enter) { }
music.define_singleton_method(:leave) { }
app.define_singleton_method(:background_music) { music }
EltenGameRoom.define_singleton_method(:contacts_settings_changed) { |_| }
Form.account_settings_driver = ->(form) { form.accept_button.trigger(:press) }
app.send(:show_settings)
assert(!stored.key?('display_name'), 'The real save flow retained the old persisted alias')
assert(notices == ['Settings saved.'], 'Saving retained profile-specific feedback')
puts 'PASS real settings Save removes an old persisted alias without any profile RPC'
