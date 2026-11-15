require_relative '../support/table_watch_runtime'

GameRoomLocalization.boot(settings: {}, host_language: 'en')
EltenGameRoom.remember_settings(EltenGameRoom::DEFAULT_SETTINGS)
saved_settings = Marshal.dump(EltenGameRoom.normalized_settings)
app = EltenGameRoom.allocate
responses, prompts, alerts = [], [], []
app.define_singleton_method(:input_text) do |header, **options|
  prompts << [header, options]
  responses.shift
end
app.define_singleton_method(:alert) { |message| alerts << message }
app.define_singleton_method(:update_json) { |*| raise 'Local editing attempted persistence' }
app.define_singleton_method(:run_network_task) { |*| raise 'Local editing attempted network work' }

module EltenAPI
  module KeyboardState
    class << self
      attr_accessor :test_state, :test_pressed
      def first_pressed?(key); test_pressed == key; end
      def state_when_pressed(key); first_pressed?(key) ? test_state : nil; end
      def clear_current_frame; self.test_pressed = nil; end
    end
  end
end
keys = [16,17,18,83,71,75]
form = Struct.new(:game_room_entry_boundary).new(true)
keys.each do |missing|
  EltenAPI::KeyboardState.test_state = keys.to_h { |key| [key, key != missing] }
  EltenAPI::KeyboardState.test_pressed = keys.find { |key| key != missing }
  original_key = EltenAPI::KeyboardState.test_pressed
  assert(!app.handle_main_menu_input(form) && prompts.empty?, 'An incomplete chord opened the field')
  assert(EltenAPI::KeyboardState.test_pressed == original_key, 'Ordinary menu input was consumed')
end
EltenAPI::KeyboardState.test_state = keys.to_h { |key| [key, true] }
EltenAPI::KeyboardState.test_pressed = 75
assert(!app.handle_main_menu_input(Struct.new(:game_room_entry_boundary).new(false)), 'Input escaped the main menu')
responses << '  Local   Person  '
assert(app.handle_main_menu_input(form), 'Complete chord did not open the field')
assert(prompts.last.first == '' && prompts.last.last[:escapable] && prompts.last.last[:max_length] == 64, 'Field has a label or loses native cancellation/limit')
assert(GameRoomParticipants.display_name(Session.name) == 'Local Person' && GameRoomParticipants.public_display_name(Session.name) == Session.name, 'Accepted input changed the account')
assert(Marshal.dump(EltenGameRoom.normalized_settings) == saved_settings, 'Local input changed synchronized preferences')
lobby = Object.new
lobby.define_singleton_method(:table_id) { |row| row['__id'] }
app.instance_variable_set(:@lobby, lobby)
row = {'__id'=>15, '__live_session_id'=>'room', 'name'=>'Room', 'game'=>'four_in_a_row',
  'game_options'=>'{}', 'owner'=>Session.name, 'status'=>'waiting'}
metadata = app.send(:invitation_metadata, row, 9)
assert(metadata['sender'] == Session.name && !metadata.key?('sender_display_name') && !JSON.generate(metadata).include?('Local Person'), 'Application invitation serialized a local value')
sender = GameRoomTableWatch::Sender.new(user: Session.name, repository: Object.new,
  online: -> { [] }, send_notice: ->(*) {}, clock: -> { 2_000_000_000 })
begin
  assert(sender.enqueue(row), 'Notice fixture was refused')
  notice = sender.instance_variable_get(:@queue).first[:metadata]
  assert(!notice.key?('sender_display_name') && !JSON.generate(notice).include?('Local Person'), 'Table notice serialized a local value')
ensure
  sender.close
end
assert(!app.handle_main_menu_input(form) && prompts.length == 1, 'Held chord reopened the field')
EltenAPI::KeyboardState.test_pressed = 71
responses << nil
app.handle_main_menu_input(form)
assert(GameRoomParticipants.display_name(Session.name) == 'Local Person', 'Escape changed the value')
EltenAPI::KeyboardState.test_pressed = 83
responses.concat(["Invalid\nValue", 'Corrected Person'])
app.handle_main_menu_input(form)
assert(alerts.length == 1 && prompts.last.last[:text] == "Invalid\nValue" && GameRoomParticipants.display_name(Session.name) == 'Corrected Person', 'Validation lost the draft or accepted invalid text')
EltenAPI::KeyboardState.test_pressed = 16
responses << ''
app.handle_main_menu_input(form)
assert(GameRoomParticipants.display_name(Session.name) == Session.name, 'Empty value did not restore the account')
puts 'PASS main-menu chord, unlabeled native input contract, Enter/Escape, draft correction and no local/network writes'
