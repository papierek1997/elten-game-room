require_relative 'support/settings_widget'

translations = JSON.parse(File.read(File.expand_path("../locale/settings-widget-after-219-pl.json", __dir__), encoding: "UTF-8"))
mo = File.binread(File.expand_path("../locale/PL.mo", __dir__))
count, originals, localized = mo.byteslice(8, 12).unpack("V3")
catalog = count.times.to_h do |index|
  source_length, source_offset = mo.byteslice(originals + index * 8, 8).unpack("V2")
  value_length, value_offset = mo.byteslice(localized + index * 8, 8).unpack("V2")
  [
    mo.byteslice(source_offset, source_length).force_encoding("UTF-8"),
    mo.byteslice(value_offset, value_length).force_encoding("UTF-8")
  ]
end
translations.each do |source, translation|
  assert(catalog[source] == translation, "uncompiled Game Room setting translation: #{source}")
end

game_ids = %w[uno makao chess]
defaults = GameRoomPreferences.defaults(game_ids)
assert(defaults["lobby_games"] == game_ids, "new settings do not enable lobby games by default")
assert(defaults["widget_games"] == game_ids && defaults["widget_enabled"], "new settings do not enable the main tab by default")
assert(defaults["invitation_notifications"] == "everyone", "invitation compatibility default changed")

migrated = GameRoomPreferences.normalize({ "announce_lobby_changes" => false }, game_ids)
assert(!migrated["announce_table_created"] && !migrated["announce_player_joined"], "legacy disabled lobby setting was not preserved")
assert(migrated["lobby_games"] == game_ids, "legacy settings lost the per-game default")

empty = GameRoomPreferences.normalize({ "lobby_games" => [], "widget_games" => [] }, game_ids)
assert(empty["lobby_games"].empty? && empty["widget_games"].empty?, "an intentionally empty game selection was reset")
selected = defaults.merge("lobby_games" => ["uno"])
assert(GameRoomPreferences.lobby_announcement_enabled?(selected, :created, "uno", game_ids), "selected game lobby message was hidden")
assert(!GameRoomPreferences.lobby_announcement_enabled?(selected, :created, "chess", game_ids), "unselected game lobby message was announced")
assert(!GameRoomPreferences.lobby_announcement_enabled?(selected, :chat, "uno", game_ids), "unsupported lobby event was announced")

sound_settings = defaults.merge(
  "game_sounds" => false,
  "room_membership_sounds" => true,
  "chat_sounds" => false
)
assert(!GameRoomPreferences.sound_enabled?(sound_settings, "roll", game_ids), "game sound switch did not suppress a game cue")
assert(GameRoomPreferences.sound_enabled?(sound_settings, "connect", game_ids), "room sound switch affected the wrong category")
assert(!GameRoomPreferences.sound_enabled?(sound_settings, "chatmsg", game_ids), "chat sound switch affected the wrong category")

# The settings form is one category list followed by the controls belonging to
# the selected category. Saving returns all values in one operation.
captured_form = nil
Form.class_eval do
  alias_method :game_room_original_wait, :wait
  define_method(:resume) { nil } if !method_defined?(:resume)
  define_method(:wait) do
    captured_form = self
    sections = fields[0]
    sections.index = 4
    sections.trigger(:move)
    raise "widget controls were not shown together" if fields[18..21].any? { |control| hidden_controls.include?(control) }
    raise "lobby controls remained visible in the widget category" if fields[5..9].any? { |control| !hidden_controls.include?(control) }
    fields[10].index = 1
    fields[14].index = 0
    fields[19].select_multiselection_indices([1])
    fields[-2].trigger(:press)
  end
end

screen_values = GameRoomPreferences.defaults(game_ids)
screen_values["widget_games"] = ["uno"]
result = GameRoomScreens::Settings.new(
  screen_values,
  games: [
    { id: "uno", name: "UNO" },
    { id: "makao", name: "Makao" },
    { id: "chess", name: "Chess" }
  ]
).wait
assert(captured_form != nil, "settings form did not open")
assert(result["invitation_notifications"] == "nobody", "notification policy was not saved")
assert(result["sound_volumes"]["game"] == 0, "sound setting was not saved")
assert(result["widget_games"].sort == %w[makao uno], "multi-selection of widget games was not saved")

# Restore the shared test form before exercising the main-tab control.
Form.class_eval do
  alias_method :wait, :game_room_original_wait
  remove_method :game_room_original_wait
end

worker = WidgetManualWorker.new
now = 0.0
active = true
loads = 0
opened = []
rows = [
  WidgetSnapshot.new(table: { "__id" => 1, "owner" => "Alice", "game" => "uno" }, members: ["Alice"]),
  WidgetSnapshot.new(table: { "__id" => 2, "owner" => "Bob", "game" => "makao" }, members: ["Bob"])
]
widget = GameRoomWidget::TableList.new(
  loader: -> { loads += 1; rows },
  opener: ->(snapshot) { opened << snapshot.table["__id"] },
  labeler: ->(snapshot) { "#{snapshot.table["game"]}, #{snapshot.table["owner"]}" },
  id_for: ->(snapshot) { snapshot.table["__id"] },
  worker: worker, clock: -> { now }, active: -> { active }
)
widget.focus
assert(loads == 1 && !worker.busy?, "focus did not fetch through its foreground task before reading")
widget.update
assert(loads == 1 && widget.options == ["uno, Alice", "makao, Bob"], "main tab did not load concise rows on focus")
widget.update
assert(loads == 1, "main tab polled tables while it was merely being updated")
$game_room_widget_arrow = true
100.times { widget.update }
$game_room_widget_arrow = false
assert(!worker.busy? && loads == 1, "arrow focus caused extra requests")
widget.index = 1
rows = rows.reverse
widget.refresh
worker.finish
widget.update
assert(widget.index == 0 && widget.options.first == "makao, Bob", "main tab did not preserve the selected table across refresh")
widget.trigger(:select)
worker.finish
widget.update
assert(opened == [2], "Enter did not open the selected main-tab table")
$game_room_widget_r = true
widget.update
$game_room_widget_r = false
worker.finish
widget.update
assert(loads >= 4 && widget.sayoption_count.to_i == 1, "R did not announce the main-tab row once, or focus was announced twice")
before = loads
active = false
now = 20.0
widget.update
widget.focus
assert(!worker.busy? && loads == before, "an inactive widget fetched data")
active = true
widget.focus
widget.refresh
widget.index = 1
rows = rows.reverse
worker.finish
widget.update
assert(widget.index == 0 && widget.options.first == "uno, Alice", "slow response restored an obsolete cursor")
assert(widget.sayoption_count == 1, "background refresh interrupted speech")
now += 4.9
widget.update
assert(!worker.busy?, "timer polled earlier than five seconds")
now += 0.1
widget.update
assert(worker.busy?, "focused five-second refresh did not start")
worker.finish
widget.update

lobby = Object.new
lobby.define_singleton_method(:owner_of) { |row| row["owner"] }
lobby.define_singleton_method(:table_id) { |row| row["__id"] }
lobby.define_singleton_method(:capacity_of) { |_row| 8 }
lobby.define_singleton_method(:playing?) { |row| row["status"] == "playing" }
app = EltenGameRoom.allocate
app.instance_variable_set(:@lobby, lobby)
app.define_singleton_method(:game_name) { |id| id == "uno" ? "UNO" : "Makao" }
available = WidgetSnapshot.new(table: { "__id" => 3, "owner" => "Bob", "game" => "uno" }, members: ["Bob"])
assert(app.send(:table_join_label, available) == "Bob, 1/8, open", "the per-game join list lost occupancy/status")
assert(app.send(:game_lobby_label, "uno") == "UNO", "the game picker still exposes an unreliable table count")
assert(app.send(:widget_table_label, available) == "UNO, Bob, 1/8, open", "the main-tab row lost occupancy/status")

# Tab entry must use the same host task as before the asynchronous-widget
# changes, then allow native focus to read the fresh list exactly once.
entry_tasks = []
app.define_singleton_method(:initialize_services) {}
app.define_singleton_method(:widget_active?) { true }
app.define_singleton_method(:load_widget_table_snapshots) { [available] }
app.define_singleton_method(:run_network_task) do |title, **options, &operation|
  entry_tasks << [title, options]
  operation.call
end
entry_widget = app.send(:build_widget_control)
entry_widget.focus
assert(entry_tasks == [["Loading Game Room tables", { silent: true }]], "entry bypassed the host task")
assert(entry_widget.options == ["UNO, Bob, 1/8, open"] && entry_widget.sayoption_count.to_i == 0, "entry did not read current rows through native focus")
entry_widget.close
unavailable_session = Object.new
unavailable_session.define_singleton_method(:can_join?) { false }
unavailable = WidgetSnapshot.new(
  table: { "__id" => 4, "owner" => "Eve", "game" => "uno", "__discovered_session" => unavailable_session },
  members: ["Eve"]
)
assert(!app.send(:widget_table_available?, unavailable), "a natively unavailable table was treated as open")
assert(app.send(:widget_table_label, unavailable) == "UNO, Eve, 1/8, open, unavailable", "unavailable main-tab row has an unclear label")

transport = Object.new
transport.define_singleton_method(:start) { true }
widget_lobby = Object.new
widget_lobby.define_singleton_method(:owner_of) { |row| row["owner"] }
widget_lobby.define_singleton_method(:open_table_snapshots) do
  [available, unavailable, rows.find { |snapshot| snapshot.table["game"] == "makao" }]
end
filter_app = EltenGameRoom.allocate
filter_app.instance_variable_set(:@transport, transport)
filter_app.instance_variable_set(:@lobby, widget_lobby)
filter_app.define_singleton_method(:initialize_services) { nil }
filter_app.define_singleton_method(:run_network_task) { |_title, **_options, &operation| operation.call }
filter_app.define_singleton_method(:game_room_settings) do |reload: false|
  defaults.merge("widget_games" => ["uno"], "widget_show_unavailable" => false)
end
assert(filter_app.send(:load_widget_table_snapshots) == [available], "main tab did not filter games and unavailable tables")
filter_app.define_singleton_method(:game_room_settings) do |reload: false|
  defaults.merge("widget_games" => ["uno"], "widget_show_unavailable" => true)
end
assert(filter_app.send(:load_widget_table_snapshots) == [available, unavailable], "main tab could not include unavailable tables on request")

# Registration uses the host's main-tab extension point and reuses the control
# supplied by the main scene instead of creating a new list on every update.
captured_tab = nil
extension_builder = Object.new
extension_builder.define_singleton_method(:every) { |_key, **_options, &_block| }
extension_builder.define_singleton_method(:start) { |&_block| }
extension_builder.define_singleton_method(:tick) { |**_options, &_block| }
extension_builder.define_singleton_method(:stop) { |&_block| }
extension_builder.define_singleton_method(:main_tab) do |key, label:, visible:, &callback|
  captured_tab = { key: key, label: label, visible: visible, callback: callback }
end
EltenGameRoom.singleton_class.class_eval do
  define_method(:app_runtime) { Object.new }
  define_method(:extension) do |name, &block|
    raise "unexpected extension name" if name != "game_room_main_tab"
    block.call(extension_builder)
  end
end
EltenGameRoom.instance_variable_set(:@game_room_extension_registered, nil)
EltenGameRoom.activate
assert(captured_tab&.fetch(:key) == "tables", "Game Room main tab was not registered")
context = Struct.new(:current_control).new(widget)
assert(captured_tab.fetch(:callback).call(context).equal?(widget), "main scene control was not reused")

EltenLink::Contacts.users = ["Bob"]
EltenLink::Contacts.calls = 0
EltenGameRoom.contacts_stop
EltenGameRoom.define_singleton_method(:read_json) do |_path, default:|
  default.merge("invitation_notifications" => "contacts", "invitation_sounds" => false)
end
EltenGameRoom.remember_settings(EltenGameRoom.read_json("settings.json", default: EltenGameRoom::DEFAULT_SETTINGS))
bob = EltenGameRoom.map_notification(FakeNotification.new("Bob"))
cache = EltenGameRoom.contacts_cache
assert(cache.instance_variable_get(:@worker).instance_variable_get(:@thread).join(3), "contact read did not finish")
bob = EltenGameRoom.map_notification(FakeNotification.new("Bob"))
eve = EltenGameRoom.map_notification(FakeNotification.new("Eve"))
assert(!bob.default_suppressed && eve.default_suppressed, "contact-only invitation notifications were filtered incorrectly")
assert(bob.sound == nil && eve.sound == nil, "notification sound setting was ignored")
assert(EltenLink::Contacts.calls == 1, "contact filter queried the server for every notification")

EltenGameRoom.define_singleton_method(:read_json) do |_path, default:|
  default.merge("invitation_notifications" => "everyone", "invitation_sounds" => true)
end
EltenGameRoom.remember_settings(EltenGameRoom.read_json("settings.json", default: EltenGameRoom::DEFAULT_SETTINGS))
EltenGameRoom.define_singleton_method(:sound_asset_path) { |name| %w[notice table_notice].include?(name) ? "C:/program-assets/#{name}.opus" : nil }
audible = EltenGameRoom.map_notification(FakeNotification.new("Bob"))
assert(audible.sound == "C:/program-assets/notice.opus", "Game Room notification did not use notice.opus")
assert(File.file?(File.expand_path("../Audio/notice.opus", __dir__)), "notice.opus is missing from packaged assets")
manifest = JSON.parse(File.read(File.expand_path("../manifest.json", __dir__), encoding: "UTF-8"))
assert(manifest.dig("required_assets", "sounds").include?("notice"), "notice.opus is missing from manifest assets")
app_source = File.read(File.expand_path("../__app.rb", __dir__), encoding: "UTF-8")
embedded_manifest = JSON.parse(app_source[/\A=begin Elten3AppInfo\s+(\{.*?\})\s+=end Elten3AppInfo/m, 1])
assert(embedded_manifest.dig("required_assets", "sounds").include?("notice"), "notice.opus is missing from the embedded manifest")

puts "Game Room settings, sounds, invitation filter and main-tab tests passed"
