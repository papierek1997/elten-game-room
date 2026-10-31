require_relative '../../support/duck_challenge_native'
require_relative '../../../lib/game_layout'
require_relative '../../../lib/game_shortcut_bindings'
require_relative '../../../games/quiz_party'

def assert(value, message); raise message unless value; end

driver = DuckChallengeNativeDriver.new
spec = GameSurfaces::QuestionSpec.new(id:'quiz:one', prompt:'Które miasto leży nad Wisłą?',
  mode: :single_choice, prompt_as_text:true, submit_on_select:true, required:true,
  options:%w[Kraków Poznań Łódź Opole].each_with_index.map { |name,i| GameSurfaces::QuestionOption.new(id:i.to_s,label:name) })
layout = GameRoomLayout::Screen.new(view_spec:GameRoomLayout::ViewSpec.new(surface:spec), user_items:%w[Alice Bob])
form = layout.form
form.game_room_background_help_enabled = true
form.focus
press = lambda do |key, modifiers: []|
  held = modifiers + [key]
  driver.frame(form, modifiers.map { |code| [code,true] } + [[key,true,driver.raw(held)]], held:held)
  # The modifier stays held for keydown; release gets a separate frame.
  driver.frame(form, [[key,false]] + modifiers.reverse.map { |code| [code,false] })
end
question, answers = layout.surface.fields
actions = []
layout.surface.on_action { |action| actions << action }
assert(question.is_a?(EditBox) && (question.flags & EditBox::Flags::ReadOnly) != 0, 'Question is not native read-only text')
assert(question.text == spec.prompt && answers.is_a?(ListBox) && answers.options == spec.options.map(&:label), 'Question was duplicated in the answers')
press.call(0x27,modifiers:[0x11])
assert(question.text[0...question.index].strip == 'Które', 'Native Ctrl+Right cannot read by word')
saved_cursor = [question.index,question.check]
press.call(0x0D)
assert(actions.empty?, 'Enter on the question submitted an unintended answer')
press.call(0x28)
assert(form.fields[form.index].equal?(answers) && answers.index == 0, 'Down does not reach the first answer')
press.call(0x28)
assert(answers.index == 1, 'Down does not navigate the answer list normally')
press.call(0x26)
press.call(0x26)
assert(form.fields[form.index].equal?(question) && [question.index,question.check] == saved_cursor, 'Up from the first answer does not return to text/cursor')

layout.update(view_spec:GameRoomLayout::ViewSpec.new(surface:spec),history_items:[],user_items:%w[Alice Bob],users_header:'Players')
question, answers = layout.surface.fields
assert([question.index,question.check] == saved_cursor && form.fields[form.index].equal?(question), 'Refresh lost question focus or selection')
layout.surface.on_action { |action| actions << action }
press.call(0x28)
press.call(0x0D)
assert(actions.length == 1 && actions.first.kind == 'question' && actions.first.payload['answer'] == '0', 'Enter did not submit exactly the selected answer')
assert(question.text == spec.prompt, 'Read-only question changed')

# This capability is opt-in; category lists and other games retain one list.
legacy = GameSurfaces::QuestionSurface.new(GameSurfaces::QuestionSpec.new(id:'legacy',prompt:'Question',mode: :single_choice,
  options:spec.options,prompt_in_choices:true,submit_on_select:true))
assert(legacy.fields.length == 1 && legacy.fields.first.options.first == 'Question', 'The new Quiz UI changed unrelated question lists')
assert(legacy.submission_action.nil?, 'A legacy prompt row became an answer')
$activecontrols = []
puts 'PASS native Quiz question text: word navigation, Down/Up answers, Enter guard, stable refresh and legacy choice lists'
