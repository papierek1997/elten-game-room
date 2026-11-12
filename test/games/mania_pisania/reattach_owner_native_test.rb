require_relative '../../support/game_option_editor_native'
require_relative '../../support/assertions'
require_relative '../../../lib/mania_pisania/client'
include GameRoomTest::Assertions
NativeOptionTest.language = 'en'

# Native Form and the actual Client/Practice. The finite progress fixture owns
# no thread or account and deliberately cannot repair Client's coverage policy.
class ReattachTypingProgress
  def attach(form); @form = form; end
  def detach; @form = nil; end
  def close; detach; end
end
program = NativeOptionTest::Program.new
game = GameRoomGames::ManiaPisania.new
client = Thread.new do
  GameRoomTyping::Client.new(program, game,
    progress_factory: ->(**_options, &_block) { ReattachTypingProgress.new })
end.value
NativeOptionUI.driver = Object.new
NativeOptionUI.driver.define_singleton_method(:tick) { |*_arguments| }
form = GameRoomUI::Form.new([], program: program, quiet: true)
surface = GameSurfaces::TypingSurface.allocate
client.bind_screen(session_id: 1, table_id: 1, owner: 'Alice', viewer: 'Alice', members: -> { ['Alice'] })
$currentthread = Thread.current
$lastactivecontrols = [form]
client.attach_view(form, surface)
assert(!client.send(:covered?), 'The visible reattached client retained the thread which created it in the background')
updates = []
surface.define_singleton_method(:present) { |**data| updates << data }
practice = GameRoomTyping::Practice.new(options: {'variant' => 'words', 'input' => 'keyboard'},
  word_bank: ->(_seed, _index) { 'cat' }, seed: 1, multiplayer: false)
practice.start
practice.prompt_finished
client.instance_variable_set(:@practice, practice)
client.input('c')
assert_equal('c', practice.buffer)
assert_equal(1, updates.length, 'Accepted input did not update the actual visible surface')
assert_equal('c', updates.last[:buffer])

cover = GameRoomUI::Form.new([], program: program, quiet: true)
$lastactivecontrols = [cover]
assert(client.send(:covered?), 'A different active native form must still cover the game')
client.send(:present)
assert_equal(1, updates.length, 'Covered presentation leaked an update into the game surface')
$lastactivecontrols = [form]
client.attach_view(form, surface)
assert(!client.send(:covered?))
assert_equal('c', updates.last[:buffer], 'Returning replaced the ongoing practice')
client.detach_view
assert_equal(nil, surface.on_character)
assert_equal(nil, surface.on_command)
client.close
puts 'PASS native typing: attach adopts the active UI owner, preserves input and still respects a covering form'
