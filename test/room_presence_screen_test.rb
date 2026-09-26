require_relative "support/background_help_native"

path = File.expand_path("../lib/game_room_presence_screen.rb", __dir__)
TOPLEVEL_BINDING.eval(File.binread(path), path) if File.file?(path)
assert(defined?(GameRoomPresenceScreen), "Current room activity screen is missing")
GameRoomLocalization.boot(host_language: "en", settings: { "interface_language" => "en" })

def loop_update(*_args); end

class Form
  class << self
    attr_accessor :presence_driver
  end
  def wait
    @wait = true
    Form.presence_driver.call(self)
    assert(@wait == false, "Room activity screen did not resume its native form")
  end
end

program = Object.new
reads = 0
data = { "public_rooms" => 3, "private_rooms" => 2, "people" => 12,
  "nickname" => "DO_NOT_DISCLOSE_PERSON", "private_room_name" => "DO_NOT_DISCLOSE_ROOM" }
Form.presence_driver = lambda do |form|
  assert(form.is_a?(GameRoomUI::Form) && form.game_room_program.equal?(program), "Room activity lost the application-aware native form")
  summary = form.fields.first
  assert(summary.is_a?(EditBox) && summary.flags & EditBox::Flags::ReadOnly != 0 &&
    summary.flags & EditBox::Flags::MultiLine != 0, "Room activity must start with read-only multiline text")
  assert(summary.header == "Current room activity", "Room activity uses a misleading screen title")
  ["Public rooms: 3", "Private rooms: 2", "People in rooms: 12"].each do |line|
    assert(summary.text.include?(line), "Room activity summary lost #{line}")
  end
  ["recent reports", "about two minutes", "updated clients", "includes observers", "excludes bots",
    "The people count is the sum of room membership counts", "not a global online count"].each do |explanation|
    assert(summary.text.include?(explanation), "Room activity does not explain #{explanation}")
  end
  assert(!summary.text.include?("DO_NOT_DISCLOSE"), "Room activity exposed a nickname or private room name")
  assert(reads == 1, "Opening room activity did not read exactly once")
  assert(form.instance_variable_get(:@timers).empty?, "Room activity installed a polling timer")
  assert(form.cancel_button.is_a?(Button) && form.cancel_button.label == "Back", "Room activity has no Back/Escape action")
  form.cancel_button.press
end
GameRoomPresenceScreen.new(program: program, reader: -> { reads += 1; data }).run
refresh_reads = 0
Form.presence_driver = lambda do |form|
  summary = form.fields.first
  refresh = form.fields.find { |field| field.is_a?(Button) && field.label == "Refresh" }
  assert(refresh, "Room activity has no explicit Refresh button")
  assert(form.fields.length == 3 && form.fields.last.equal?(form.cancel_button), "Room activity added unnecessary focus fields")
  assert(form.accept_button.nil?, "Enter while reading implicitly performs a network refresh")
  driver = BackgroundHelpNativeDriver.new
  driver.root = form
  [[], [], []].each do |keys|
    driver.keys = [keys]
    driver.tick(form)
    form.update
  end
  assert(refresh_reads == 1, "Idle native form updates polled room activity")
  driver.keys = [[9]]
  driver.tick(form)
  form.update
  assert(form.fields[form.index].equal?(refresh), "Native Tab does not reach Refresh")
  driver.keys = [[13]]
  driver.tick(form)
  form.update
  assert(refresh_reads == 2 && summary.text.include?("People in rooms: 14"), "Native Enter did not refresh the count exactly once")
  assert(form.fields[form.index].equal?(refresh), "Refreshing stole keyboard focus")
  assert(form.instance_variable_get(:@wait), "Refresh closed the screen")
  driver.keys = [[27]]
  driver.tick(form)
  form.update
  assert(form.instance_variable_get(:@wait) == false, "Native Escape does not leave room activity")
end
GameRoomPresenceScreen.new(program: program,
  reader: -> { refresh_reads += 1; data.merge("people" => 12 + refresh_reads) }).run
Form.presence_driver = lambda do |form|
  summary = form.fields.first.text
  assert(summary.include?("Room activity is unavailable. Try Refresh."), "Unavailable counts are not explained")
  assert(!summary.include?("rooms: 0") && !summary.include?("People in rooms:"), "A failed read was presented as measured zero activity")
  assert(summary.include?("recent reports"), "Unavailable view lost the coverage explanation")
  form.cancel_button.press
end
GameRoomPresenceScreen.new(program: program, reader: -> { nil }).run
module Log
  class << self
    attr_accessor :presence_warnings
    def warning(message)
      (@presence_warnings ||= []) << message
    end
  end
end
GameRoomPresenceScreen.new(program: program, reader: -> { raise IOError, "offline" }).run
assert(Log.presence_warnings.to_a.any? { |message| message.include?("IOError") }, "Reader exception lost its diagnostic")
responses = [data, nil, IOError.new("connection lost"), data.merge("people" => 0, "public_rooms" => 0, "private_rooms" => 0)]
Form.presence_driver = lambda do |form|
  summary, refresh = form.fields
  form.index = refresh
  2.times do
    refresh.press
    assert(summary.text.include?("unavailable") && !summary.text.include?("People in rooms:"), "Failed refresh left stale counts or invented zeros")
    assert(form.fields[form.index].equal?(refresh), "Failed refresh stole focus")
  end
  refresh.press
  ["Public rooms: 0", "Private rooms: 0", "People in rooms: 0"].each do |line|
    assert(summary.text.include?(line), "A successful zero result was not rendered: #{line}")
  end
  assert(!summary.text.include?("unavailable") && responses.empty?, "Refresh did not recover or made extra reader calls")
  form.cancel_button.press
end
GameRoomPresenceScreen.new(program: program, reader: -> do
  value = responses.shift
  raise value if value.is_a?(Exception)
  value
end).run
catalog = Object.new
catalog.define_singleton_method(:translate) do |source, **_options|
  { "Current room activity" => "Obecnie w pokojach".b, "Refresh" => "Odśwież".b,
    "Back" => "Wróć".b, "People in rooms: %{count}" => "Osoby w pokojach: %{count}".b }[source]
end
GameRoomLocalization.instance_variable_set(:@translator,
  GameRoomLocalization::Translator.new(catalogs: { "pl" => catalog }, primary: "pl", known: []))
Form.presence_driver = lambda do |form|
  summary = form.fields.first
  assert(summary.header == "Obecnie w pokojach" && summary.text.include?("Osoby w pokojach: 12"),
    "Binary-loaded room activity bypassed local translations")
  assert(summary.text.include?("Public rooms: 3"), "Partial translation lost the English fallback")
  form.fields.each do |field|
    strings = field.is_a?(EditBox) ? [field.header, field.text] : [field.label]
    strings.each do |text|
      assert(text.encoding == Encoding::UTF_8 && text.valid_encoding? && (text + " — выбранное поле").valid_encoding?,
        "Binary-loaded summary or button breaks native role speech")
    end
    field.focus
  end
  refresh = form.fields.find { |field| field.is_a?(Button) && field.label == "Odśwież" }
  assert(refresh, "Refresh bypassed local translations")
  refresh.press
  assert(summary.text.include?("Osoby w pokojach: 12"), "Refresh changed the translation language")
  form.cancel_button.press
end
GameRoomPresenceScreen.new(program: program, reader: -> { data }).run
puts "PASS room presence screen"
