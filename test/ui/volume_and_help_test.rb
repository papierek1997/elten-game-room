require_relative "../support/translation_reference"
require_relative "../support/volume_and_help"

translations = GameRoomTest::TranslationReference.fetch("volume_and_help")
mo = File.binread(File.expand_path("../../locale/PL.mo", __dir__))
count, originals, localized = mo.byteslice(8, 12).unpack("V3")
catalog = count.times.to_h do |index|
  length, offset = mo.byteslice(originals + index * 8, 8).unpack("V2")
  translated_length, translated_offset = mo.byteslice(localized + index * 8, 8).unpack("V2")
  [mo.byteslice(offset, length).force_encoding("UTF-8"), mo.byteslice(translated_offset, translated_length).force_encoding("UTF-8")]
end
translations.each { |key, value| assert(catalog[key] == value, "uncompiled translation: #{key}") }
GameRoomUI::VOLUME_LABELS.each_value { |label| assert(catalog[label] && !catalog[label].empty?, "untranslated volume group") }
assert(catalog.fetch("%{group}, %{volume}%%") % { group: "Czat", volume: 40 } == "Czat, 40%", "translated percentage interpolation")

legacy = GameRoomPreferences.normalize({ "game_sounds" => false, "chat_sounds" => false }, [])
assert(legacy["sound_volumes"] == { "all" => 100, "game" => 0, "room" => 100, "chat" => 0, "notifications" => 100 }, "legacy migration")
invalid = GameRoomPreferences.sound_volumes("sound_volumes" => { "all" => 500, "room" => -1, "game" => "bad" })
assert(invalid["all"] == 100 && invalid["room"] == 0 && invalid["game"] == 100, "clamping/invalid input")

app = EltenGameRoom.new
state = { "sound_volumes" => { "all" => 50, "game" => 100, "room" => 100, "chat" => 40, "notifications" => 70 }, "unrelated" => "keep" }
writes = 0
volume_caller = Thread.current
first_write = Queue.new
app.define_singleton_method(:read_json) { |_file, default:| state }
app.define_singleton_method(:update_json) do |_file, default:, &block|
  assert(!Thread.current.equal?(volume_caller), 'volume write ran on the caller')
  first_write.pop if writes.zero?
  writes += 1
  block.call(state)
  state
end
played = []
app.define_singleton_method(:play_sound_from_asset) { |name, volume:| played << [name, volume] }
GameRoomSounds.play(app, "chatmsg")
GameRoomSounds.play(app, "roll")
GameRoomSounds.play(app, "notice")
assert(played == [["chatmsg", 0.2], ["roll", 0.5], ["notice", 0.35]], "category/master multiplication")
begin
  app.send(:adjust_game_room_volume, 2)
  assert(app.send(:game_room_sound_volume, 'roll') == 0.4 && writes.zero?, 'volume waited for disk')
ensure
  first_write << true
end
def await_volume(app)
  writer = app.class.instance_variable_get(:@volume_settings)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
  while writer.instance_variable_get(:@thread)&.alive?
    raise 'volume writer did not settle' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    sleep 0.001
  end
end
await_volume(app)
assert(state["sound_volumes"]["all"] == 40 && state["sound_volumes"]["chat"] == 40, "master erased individual volume")
assert(state["unrelated"] == "keep" && writes == 1, "unrelated setting overwritten")
app.send(:adjust_game_room_volume, -2)
assert($spoken_messages.last == "Invitation and Power Games notification sounds, 70%", "previous group wrap")
app.send(:adjust_game_room_volume, -3)
assert($spoken_messages.last == "All Power Games sounds, 40%", "next group wrap")
4.times { app.send(:adjust_game_room_volume, 2) }
before = played.length
GameRoomSounds.play(app, "roll")
GameRoomSounds.play(app, "connect")
assert(played.length == before, "zero master still plays")
await_volume(app)
before = writes
app.send(:adjust_game_room_volume, 2)
await_volume(app)
assert(writes == before, "unchanged bound wrote settings")
app.send(:adjust_game_room_volume, 3)
await_volume(app)
assert(state["sound_volumes"]["all"] == 10, "raise step")
app.instance_variable_set(:@game_room_volume_group, 3)
app.send(:adjust_game_room_volume, 2)
await_volume(app)
assert(state["sound_volumes"]["chat"] == 30, "selected group adjustment")
app.send(:adjust_game_room_volume, 3, reader: -> { { "chat" => 19 } }, writer: ->(group, level) { assert(group == "chat" && level == 29, "staged setting") })
assert(state["sound_volumes"]["chat"] == 30, "staged edit persisted before Save")

field = ListBox.new(["red 1", "blue 3"], header: "Hand", index: 1)
field.define_singleton_method(:add_tip) { |tip| (@test_tips ||= []) << tip }
field.define_singleton_method(:get_tips) { @test_tips.to_a }
field.add_tip("Native field tip")
GameRoomContextHelp.replace([field], ["Room action", "Duplicate"], source: :context)
GameRoomContextHelp.replace([field], ["Game action", "Duplicate"], source: :game)
form = GameRoomUI::Form.new([field], program: app)
form.game_room_table_controls = true
form.game_room_general_help_tips = ["History action"]
native = EltenAPI::QuickActions.hotkey_actions(1)
driver = nil
Form.class_eval do
  define_method(:resume) { @wait = false }
  define_method(:wait) { driver&.call(self) }
end
driver = lambda do |current|
  $activecontrols = [current, current.fields.first]
  assert(EltenAPI::QuickActions.hotkey_actions(13).first.label == "Ctrl+F1", "Ctrl+F1 intercepted")
  if current.equal?(form)
    assert(EltenAPI::QuickActions.hotkey_actions(1) != native, "native F1 not replaced")
    original_index = current.index
    EltenAPI::QuickActions.hotkey_actions(1).each(&:call)
    assert(current.index == original_index && field.index == 1, "modal help changed cursor")
    assert(field.last_focus_spoken, "focus not restored")
  else
    list = current.fields.first
    assert(current.fields.length == 2 && current.hidden_controls == [current.accept_button], "F1 has extra tab stops")
    assert(list.is_a?(EditBox) && (list.flags & EditBox::Flags::ReadOnly) != 0 && (list.flags & EditBox::Flags::MultiLine) != 0, "help is not read-only multiline text")
    lines = list.text.split("\n")
    assert(lines.first(4) == ["Game action", "Duplicate", "Room action", "Native field tip"], "help order/deduplication")
    assert(lines[4] == "History action" && lines.uniq == lines, "general order/duplicates")
    assert(lines[5].start_with?("Ctrl+Shift+M") && lines[5].include?("conference microphone"), "table conference help missing or out of order")
    assert(lines[6].start_with?("Ctrl+J") && lines[6].include?("Accept invitation"), "global invitation help missing or out of order")
    assert(list.key_processed(:key_enter) == false, "Enter cannot close help")
    EltenAPI::QuickActions.hotkey_actions(1).each(&:call)
    EltenAPI::QuickActions.hotkey_actions(1).each(&:call)
    assert(current.instance_variable_get(:@game_room_help_open), "repeated F1 permits recursive help")
    current.accept_button.trigger(:press)
  end
end
form.wait
assert(!form.game_room_hotkeys_active?, "scope leaked after wait")
assert(EltenAPI::QuickActions.hotkey_actions(1) == native, "native help not restored after exit")
form.instance_variable_set(:@game_room_waiting, true)
$activecontrols = [Form.new([field]), field]
assert(EltenAPI::QuickActions.hotkey_actions(1) == native, "forum/native form help overridden")
$activecontrols = [form, field]
before = state["sound_volumes"]["chat"]
EltenAPI::QuickActions.hotkey_actions(2).each(&:call)
await_volume(app)
assert(state["sound_volumes"]["chat"] == before - 10, "real F2 dispatch did not adjust")
bridge_count = EltenAPI::QuickActions.singleton_class.ancestors.length
3.times { GameRoomUI.install_hotkeys }
assert(EltenAPI::QuickActions.singleton_class.ancestors.length == bridge_count, "dispatch bridge installed repeatedly")
GameRoomContextHelp.replace([field], ["New phase"], source: :game)
assert(!field.get_tips.include?("Game action"), "old phase help retained")

presentation = Object.new
presentation.extend(GameRoomUI::NotificationSound)
notice_calls = 0
presentation.game_room_notice_player = -> { notice_calls += 1 }
assert(notice_calls == 0, "notice played while mapping")
2.times { assert(presentation.sound == nil, "host notification would double-play") }
assert(notice_calls == 1, "notice playback repeated")

# The same staged controls support keys and arrows, with true Cancel semantics.
class CheckBox < FakeControl
  attr_accessor :checked
  def initialize(_label, checked: false); super(); @checked = checked; end
end
settings_before = Marshal.load(Marshal.dump(state))
driver = lambda do |current|
  $activecontrols = [current, current.fields.first]
  app.instance_variable_set(:@game_room_volume_group, 0)
  current.fields[0].index = current.fields[0].options.index("Sounds") || raise("Missing Sounds category")
  current.fields[0].trigger(:move)
  sound_fields = GameRoomPreferences::SOUND_GROUPS.map do |group|
    current.fields.find { |control| control.header == GameRoomUI::VOLUME_LABELS.fetch(group) }
  end
  assert(sound_fields.all? { |control| control.is_a?(ListBox) && !current.hidden_controls.include?(control) }, "sound levels are not five lists")
  EltenAPI::QuickActions.hotkey_actions(3).each(&:call)
  assert(sound_fields.first.index == settings_before["sound_volumes"]["all"] + 10, "settings keys/list disagree")
  current.cancel_button.trigger(:press)
end
assert(GameRoomScreens::Settings.new(state, games: [], program: app).wait == nil, "Cancel did not close settings")
assert(state == settings_before, "Cancel persisted staged key changes")

# Editable chat is the same object, with its text/caret/selection intact. Help
# must not advertise history shortcuts which retain their editing meaning.
chat = EditBox.new("Chat", text: "tekst ąęż")
chat.index, chat.check = 3, 7
chat.define_singleton_method(:get_tips) { ["Chat editing"] }
chat_form = GameRoomUI::Form.new([chat], program: app)
chat_form.game_room_general_help_tips = ["History action"]
chat_form.game_room_text_help_tips = ["Chat history punctuation"]
driver = lambda do |current|
  $activecontrols = [current, current.fields.first]
  if current.equal?(chat_form)
    EltenAPI::QuickActions.hotkey_actions(1).each(&:call)
  else
    assert(current.fields.first.text.split("\n").first == "Chat editing", "chat help missing")
    assert(!current.fields.first.text.include?("History action"), "history advertised inside editable chat")
    assert(current.fields.first.text.include?("Chat history punctuation"), "punctuation shortcuts missing from chat help")
    current.cancel_button.trigger(:press)
  end
end
chat_form.wait
assert(chat_form.fields.first.equal?(chat) && [chat.text, chat.index, chat.check] == ["tekst ąęż", 3, 7], "F1 altered chat control/text/selection")

# All newly delivered app notices use the app SoundPool, only on delivery and
# once per presentation. Muting the master between map/delivery stays silent.
class Notice
  attr_reader :metadata, :type, :sender
  def initialize
    @metadata = { "sender" => "Bob", "table_name" => "Test", "game_name" => "Makao" }
    @type, @sender = "game_room.invitation", "Bob"
  end
  def presentation(**_options)
    Object.new
  end
end
EltenGameRoom.define_singleton_method(:normalized_settings) { state.merge("invitation_notifications" => "everyone", "invitation_sounds" => true) }
EltenGameRoom.define_singleton_method(:play_sound_from_asset) { |name, volume:| played << [name, volume] }
before = played.length
mapped = EltenGameRoom.map_notification(Notice.new)
assert(played.length == before, "mapping played notification")
2.times { mapped.sound }
assert(played.length == before + 1 && played.last == ["notice", 0.07], "notification scaled/deduplicated incorrectly")
mapped = EltenGameRoom.map_notification(Notice.new)
state["sound_volumes"]["all"] = 0
before = played.length
mapped.sound
assert(played.length == before, "master mute ignored at delivery")

puts "Game Room volume, migration, scoped native F1 dispatch and read-only help passed"
