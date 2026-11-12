require_relative '../support/game_option_editor_native'

class AppChoiceNativeDriver < NativeOptionTest::Driver
  def initialize(program, &operation)
    @program, @raw_keys, @frames = program, [], 0
    NativeOptionUI.driver = self
    NativeOptionUI.instance_variable_set(:@spoken, [])
    EltenAPI::KeyboardState.reset
    @fiber = Fiber.new(&operation)
    @form = @fiber.resume
    NativeOptionTest.assert(@fiber.alive? && @form.instance_of?(GameRoomUI::Form), 'App picker did not open its native form')
    NativeOptionTest.assert(@form.game_room_program.equal?(program), 'App picker lost its Program owner')
    NativeOptionTest.assert(@form.fields.first.instance_of?(ListBox), 'App picker replaced the native list')
    NativeOptionTest.assert(NativeOptionUI.spoken.one?, 'App picker spoke its opening caption more than once')
  end
end

NativeOptionTest.native_method(ListBox, :initialize, 'src/ui/controls/list_box.rb')
NativeOptionTest.native_method(Form, :update, 'src/ui/form.rb')

%w[en pl cs es ru].each do |language|
  NativeOptionTest.language = language
  program = NativeOptionTest::Program.new
  invitations = [{label: 'First invitation'}, {label: 'Żółta invitation'}]
  program.define_singleton_method(:pending_invitation_label) { |choice| choice.fetch(:label) }
  users = ['Alice', 'Żaneta']
  assignment = Struct.new(:team_count).new(3)
  cases = [
    [:game, -> { program.send(:select_game, 'Games', %w[monopoly uno], descriptions: true) }, 0, true, 'uno'],
    [:saved, -> { program.send(:select_saved_game_item, %w[First Second], 'Saved') }, 0, false, 0],
    [:participant, -> { program.send(:choose_table_participant, ['Alice', :new_bot], 'Replacement') }, 0, true, :new_bot],
    [:recipient, -> { program.send(:select_invitation_recipient, users, 'Invite') }, 0, true, users.last],
    [:pending_accept, -> { program.send(:select_pending_invitation, invitations) }, 0, true, invitations.last],
    [:pending_reject, -> { program.send(:select_pending_invitation, invitations, mode: :reject) }, 0, true, invitations.last],
    [:notification, -> { program.send(:select_notification_invitation_action) }, 0, true, :reject],
    [:team, -> { program.send(:choose_team, assignment, 2) }, 2, false, 2]
  ]
  cases.each do |name, operation, initial, move, expected|
    driver = AppChoiceNativeDriver.new(program, &operation)
    NativeOptionTest.assert(driver.form.fields.first.index == initial, "#{language}/#{name}: wrong selected default")
    driver.press([0x28]) if move
    driver.press([0x0d])
    result = driver.finished
    NativeOptionTest.assert(result == expected, "#{language}/#{name}: Enter returned another value")
    if [:recipient, :pending_accept, :pending_reject].include?(name)
      NativeOptionTest.assert(result.equal?(expected), "#{name}: selection replaced the original object")
    end
    NativeOptionTest.assert(NativeOptionUI.spoken.length == (move ? 2 : 1), "#{language}/#{name}: closing duplicated its caption")
    NativeOptionTest.assert(program.writes.empty? && program.remembers.empty?, "#{name}: choosing performed persistence")

    cancelled = AppChoiceNativeDriver.new(program, &operation)
    cancelled.press([0x1b])
    NativeOptionTest.assert(cancelled.finished.nil?, "#{language}/#{name}: Escape returned a selection")
    NativeOptionTest.assert(NativeOptionUI.spoken.one?, "#{language}/#{name}: Escape repeated its caption")
  end
  NativeOptionTest.assert(program.send(:select_game, 'Empty', []).nil?, 'Empty game list invented an entry')
  NativeOptionTest.assert(program.send(:select_saved_game_item, [], 'Empty').nil?, 'Empty saved list invented an entry')
  NativeOptionTest.assert(program.send(:choose_table_participant, [], 'Empty').nil?, 'Empty participant list invented a person')
  NativeOptionTest.assert(program.send(:select_invitation_recipient, [], 'Empty').nil?, 'Empty recipient list invented a person')
  NativeOptionTest.assert(program.send(:select_pending_invitation, []).nil?, 'Empty invitation list invented an invitation')
  NativeOptionTest.assert(program.send(:select_pending_invitation, invitations, mode: :unknown).nil?, 'Unknown invitation mode opened admission')
end
puts 'PASS seven shared app pickers: five binary languages, native Enter/arrows/Escape, defaults, original objects, one opening caption, key cleanup and no writes'
