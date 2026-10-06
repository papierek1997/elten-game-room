require_relative "../support/game_option_form"
require_relative "../support/manual_form_timer"
require_relative "../support/widget"

game = GameRoomGames::Rummy.new
app = EltenGameRoom.allocate
app.define_singleton_method(:read_json) { |_path, default:| default }
messages, forms = [], []
app.define_singleton_method(:alert) { |message| messages << message }
Form.driver = lambda do |form|
  forms << form
  raise "validation loop" if forms.length > 2
  field = ->(key) { form.fields.find { |control| control.header == game.effective_option_definitions.find { |d| d.key == key }.label } }
  privacy = form.fields.find { |control| control.is_a?(CheckBox) && control.header == "Private table" }
  if forms.length == 1
    privacy.checked = true
    field.call("elimination").checked = true
    field.call("manipulation").checked = true
    field.call("first_meld").set_text("45")
    field.call("score_limit").set_text("0")
    form.index = form.fields.index(field.call("score_limit"))
  else
    assert(form.equal?(forms.first), "validation rebuilt the controls")
    assert(privacy.checked && field.call("elimination").checked && field.call("manipulation").checked, "validation lost checkboxes")
    assert(field.call("first_meld").text == "45" && field.call("score_limit").text == "0", "validation lost typed values")
    assert(form.fields[form.index] == field.call("score_limit"), "validation lost input focus")
    field.call("score_limit").set_text("500")
  end
  form.accept_button.trigger(:press)
end
result = app.send(:configure_game_options, game, creating_table: true)
assert(result[:private_table] && result[:game_options]["first_meld"] == 45 && messages.length == 1, "corrected form did not save")

snapshot = Struct.new(:table).new({"owner"=>"Alice", "game"=>"makao", "__live_session_id"=>"closed", "__id"=>12, "game_options"=>"{}"})
lobby = Object.new
reads = 0
lobby.define_singleton_method(:open_table_snapshots) { |**_| reads += 1; reads <= 1 ? [snapshot] : [] }
lobby.define_singleton_method(:table_id) { |table| table.fetch("__id") }
lobby.define_singleton_method(:discovered_options) do |selected|
  assert(selected.equal?(snapshot), "settings reader used another table")
  {status: :ready, game: selected.table.fetch("game"), options: selected.table.fetch("game_options")}
end
app.instance_variable_set(:@lobby, lobby)
app.define_singleton_method(:run_network_task) { |*_, **_, &block| block.call }
app.define_singleton_method(:table_join_label) { |_| "Alice, 1/8" }
spoken = []
app.define_singleton_method(:speak) { |text| spoken << text }
app.define_singleton_method(:join_table_snapshot) { |_| Struct.new(:status).new(:closed) }
worker = WidgetManualWorker.new
reader_constructor = GameRoomTableOptionsReader.method(:new)
GameRoomTableOptionsReader.define_singleton_method(:new) { |**options| reader_constructor.call(**options, worker: worker) }
Form.driver = lambda do |form|
  menu = Object.new
  menu.define_singleton_method(:option) { |_label, _unused, key, &block| block.call if key == "r" }
  form.context(menu)
  assert(spoken.empty?, "Ctrl+R blocked instead of scheduling a read")
  worker.finish
  form.instance_variable_get(:@timers).each(&:fire)
  form.accept_button.trigger(:press)
end
begin
  assert(app.send(:show_tables_for_game, "makao") == false, "closed table did not return safely")
ensure
  GameRoomTableOptionsReader.singleton_class.remove_method(:new)
end
expected = GameRoomGames::Makao.new.table_options_announcement(GameRoomGames::Makao.new.options_from_json("{}"))
assert(spoken == [expected], "Ctrl+R read another game/table")
assert(messages.include?("This table is no longer available."), "closed-table message missing")
puts "PASS audit UI: validation retains exact controls/focus/privacy, corrected save, list Ctrl+R and closed join"
