require_relative '../support/duck_challenge_native'
require_relative '../support/assertions'
include GameRoomTest::Assertions

begin
  driver = DuckChallengeNativeDriver.new
  press = lambda do |form, key|
    driver.frame(form, [[key, true, driver.raw([key])]], held: [key])
    driver.frame(form, [[key, false]])
  end
  [{}, {prompt_in_choices: true}, {prompt_as_text: true}].each do |presentation|
    [false, true].each do |read_only|
      spec = GameSurfaces::QuestionSpec.new(id: 'inspect-or-answer', prompt: 'Which answer?',
        mode: :single_choice, read_only: read_only, submit_on_select: true, required: true,
        options: [GameSurfaces::QuestionOption.new(id: 'first', label: 'First', value: 'A'),
          GameSurfaces::QuestionOption.new(id: 'second', label: 'Second', value: 'B')], **presentation)
      surface = GameSurfaces::QuestionSurface.new(spec)
      actions = []
      surface.on_action { |action| actions << action.to_h }
      form = driver.form(surface)
      surface.attach_form(form)
      press.call(form, 0x28) if presentation[:prompt_as_text] || presentation[:prompt_in_choices]
      press.call(form, 0x28)
      press.call(form, 0x0d)
      assert_equal(read_only ? 0 : 1, actions.size,
        "Native Enter violated read-only=#{read_only}, presentation=#{presentation.inspect}")
      assert_equal(read_only, surface.submission_action.nil?, 'Direct and native submission disagree')
      unless read_only
        assert_equal({'kind' => 'question', 'action' => 'submit', 'question_id' => 'inspect-or-answer',
          'answer' => 'B', 'required' => true}, actions.first)
        surface.action_guard = -> { false }
        press.call(form, 0x0d)
        assert_equal(1, actions.size, 'Canonical immediate submission bypassed the ordinary action guard')
      end
      assert(surface.fields.none? { |field| field.is_a?(Button) }, 'Immediate choices invented a submit button')
    end
  end
  puts 'PASS native read-only questions: ordinary/prompt-row/text presentations browse without submitting; writable choices submit once through the ordinary guard'
ensure
  $activecontrols = []
end
