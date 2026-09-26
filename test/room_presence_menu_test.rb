require_relative "support/background_help_native"
require File.join(EltenTestHost.root, "src/ui/controls/grid_box")
require File.join(EltenTestHost.root, "src/ui/controls/menu")
require File.join(EltenTestHost.root, "src/eapi/mainmenu")
require_relative "../lib/game_surfaces"
require_relative "../lib/game_layout"
require_relative "../lib/game_history_navigation"

# Load the application source as the packaged host does, not as UTF-8 Ruby input.
path = File.expand_path("../lib/game_room_screens.rb", __dir__)
TOPLEVEL_BINDING.eval(File.binread(path), path)
GameRoomLocalization.boot(host_language: "en", settings: { "interface_language" => "en" })

def loop_update(*_args); end

class Form
  class << self
    attr_accessor :presence_driver
  end
  def wait
    @wait = true
    Form.presence_driver.call(self)
    assert(@wait == false, "Main menu did not resume its native form")
  end
end

program = Object.new
Form.presence_driver = lambda do |form|
  assert(form.is_a?(GameRoomUI::Form) && form.game_room_program.equal?(program), "Main menu lost its application-aware form")
  options, history = form.fields
  assert(options.index == 1 && form.index == 0, "Opening menu lost the selected row or options focus")
  assert(history.items == ["Earlier room message"], "Opening menu changed the history")
  options.index = 2
  menu = Menu.new
  options.context(menu, false)
  entry = menu.items.find { |item| item[0] == "Current room activity" }
  assert(entry && entry[3] == "w", "Main menu lacks the always-available native Ctrl+W context entry")
  assert(menu.items.none? { |item| %w[j J].include?(item[3]) }, "Unavailable invitations leaked into the menu")
  assert(options.get_tips.include?("Ctrl+W, Current room activity."), "Context help does not advertise the bound Ctrl+W action")
  assert(history.get_tips.include?("Ctrl+W, Current room activity."), "Main-menu history help lost the room activity hint")
  entry[1].call(entry[2])
  assert(history.items == ["Earlier room message"] && form.index == 0, "Room activity action changed focus or history")
end
result = GameRoomScreens::MainMenu.new(options: %w[Create Join Settings], history_items: ["Earlier room message"],
  index: 1, program: program).wait
assert(result.action == :room_activity && result.index == 2, "Room activity result lost the action or current row")
class RoomPresenceNativeInput
  def process_quick_action_hotkeys; end
  def speech_stop(*_args); end
end

[[false, [17, 87], :room_activity], [true, [17, 87], :room_activity],
 [true, [17, 74], :invitations], [true, [17, 16, 74], :reject_invitation]].each do |invitations, keys, expected|
  Form.presence_driver = lambda do |form|
    options, history = form.fields
    options.index = 1
    previous_history = [history.text, history.index, history.check]
    driver = BackgroundHelpNativeDriver.new
    driver.root = form
    input = RoomPresenceNativeInput.new
    [[], keys].each do |frame|
      driver.keys = [frame]
      driver.tick(form)
      form.update
      input.send(:keyprocs)
    end
    assert(form.instance_variable_get(:@wait) == false, "Native keyprocs did not dispatch #{keys.inspect}")
    assert([history.text, history.index, history.check] == previous_history && form.index == 0,
      "Native room menu shortcut disturbed history or focus")
    if invitations
      assert(options.get_tips.include?("Ctrl+J, Accept invitation.") &&
        options.get_tips.include?("Ctrl+Shift+J, Reject invitation."), "Invitation help was displaced by Ctrl+W")
    end
  end
  result = GameRoomScreens::MainMenu.new(options: %w[Create Join Settings], history_items: ["Earlier room message"],
    invitations: invitations, program: program).wait
  assert(result.action == expected && result.index == 1, "Native shortcut returned the wrong action or row")
end

Form.presence_driver = lambda do |form|
  options, history = form.fields
  driver = BackgroundHelpNativeDriver.new
  driver.root = form
  input = RoomPresenceNativeInput.new
  form.index = history
  [[], [17, 87], [], [17, 74]].each do |keys|
    driver.keys = [keys]
    driver.tick(form)
    form.update
    input.send(:keyprocs)
    assert(form.instance_variable_get(:@wait), "Room options shortcut leaked into the history field")
  end
  assert(!options.contextinglobal_enabled?, "Room options leaked into the global submenu")
  form.cancel_button.press
end
assert(GameRoomScreens::MainMenu.new(options: %w[Create Join], program: program).wait.action == :exit,
  "History focus no longer permits normal Back/Exit")
catalog = Object.new
catalog.define_singleton_method(:translate) do |source, **_options|
  { "Current room activity" => "Obecnie w pokojach".b,
    "Accept invitation" => "Przyjmij zaproszenie".b, "Reject invitation" => "Odrzuć zaproszenie".b }[source]
end
GameRoomLocalization.instance_variable_set(:@translator,
  GameRoomLocalization::Translator.new(catalogs: { "pl" => catalog }, primary: "pl", known: []))
Form.presence_driver = lambda do |form|
  options = form.fields.first
  menu = Menu.new
  options.context(menu, false)
  assert(menu.items.first[0] == "Obecnie w pokojach", "Context entry bypassed the local translation refinement")
  menu.items.each do |item|
    assert(item[0].encoding == Encoding::UTF_8 && (item[0] + " — выбранное поле").valid_encoding?,
      "Binary-loaded menu label breaks native role speech")
  end
  assert(options.get_tips.include?("Ctrl+W, Obecnie w pokojach."), "Translated help disagrees with the menu action")
  menu.items.first[1].call
end
assert(GameRoomScreens::MainMenu.new(options: %w[Create Join], invitations: true, program: program).wait.action == :room_activity,
  "Translated context entry changed its action")
puts "PASS room presence menu"
