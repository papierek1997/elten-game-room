require_relative 'game_option_editor_native'

# Drives ordinary native forms with the same keyboard snapshots as the editor.
class NativeTypingFormDriver < NativeOptionTest::Driver
  def initialize(program: NativeOptionTest::Program.new, &run)
    @raw_keys, @frames = [], 0
    @program = program
    NativeOptionUI.driver = self
    @fiber = Fiber.new(&run)
    @form = @fiber.resume
    NativeOptionTest.assert(@fiber.alive? && @form.is_a?(GameRoomUI::Form), 'Native typing form did not start')
  end
end
