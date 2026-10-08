require_relative "../support/ui"
require_relative "../../lib/game_surfaces"
require_relative "../../lib/game_layout"
require_relative "../../lib/game_history_navigation"
require_relative "../../lib/game_room_screens"

def assert(condition, message)
  raise message if !condition
end

class Form
  class << self
    attr_accessor :driver
  end

  def wait
    Form.driver.call(self)
  end

  def resume; end
end

# Rejection remains specific to the options list. Accepting an invitation is
# now the shared Ctrl+J action of the currently active Game Room form.
[["J", :reject_invitation]].each do |key, expected|
  Form.driver = lambda do |form|
    options = form.fields.first
    options.index = 2
    assert_invitation_menu_scope(form, list: options, keys: %w[J])
    menu = FakeMenu.new
    options.context(menu, false)
    menu.options.find { |option| option[2] == key }[3].call
  end
  result = GameRoomScreens::MainMenu.new(options: %w[Create Join Saved], invitations: true).wait
  assert(result.action == expected && result.index == 2, "main-menu invitation action or list position was lost")
end

accepted = []
program = Object.new
program.define_singleton_method(:switch_to_invited_table) { accepted << :shared_picker }
[0, 1].each do |field_index|
  Form.driver = lambda do |form|
    $activecontrols = [form]
    form.index = field_index
    menu = FakeMenu.new
    form.context(menu, true)
    assert(menu.options.count { |option| option[2] == 'j' } == 1, 'Shared invitation menu missing or duplicated')
    menu.options.find { |option| option[2] == 'j' }[3].call
    assert(form.index == field_index, 'Shared invitation action moved the current field')
    form.cancel_button.trigger(:press)
  ensure
    $activecontrols = []
  end
  GameRoomScreens::MainMenu.new(options: %w[Create Join Saved], invitations: true, program: program).wait
end
assert(accepted == [:shared_picker, :shared_picker], 'Options/history do not use the same invitation route')

# Ordinary entries still open; accepting invitations needs no list entry.
Form.driver = lambda do |form|
  form.fields.first.index = 2
  form.accept_button.trigger(:press)
end
result = GameRoomScreens::MainMenu.new(options: %w[Create Join Saved], invitations: true).wait
assert(result.action == :open && result.index == 2, "the selected menu item no longer opens normally")

Form.driver = lambda do |form|
  assert_invitation_menu_scope(form, list: form.fields.first, keys: [])
  form.cancel_button.trigger(:press)
end
assert(GameRoomScreens::MainMenu.new(options: ["Exit"]).wait.action == :exit, "disabled invitations retained their shortcuts")
Form.driver = nil
puts "Native invitation menu shortcut tests passed"
