require_relative "../support/game_option_form"

app = EltenGameRoom.allocate
app.define_singleton_method(:read_json) { |_path, default:| default }
app.define_singleton_method(:alert) { |message| raise message }
game = GameRoomGames::QuizParty.new
polish_set_ids = game.send(:available_content_sets, "pl-PL").map(&:id).sort
assert(
  polish_set_ids == ["quiz.wikidata", "quiz.witcher.books"],
  "the Polish question-set list is incomplete"
)
target_language = game.default_options["content_language_id"] == "en" ? "pl-PL" : "en"
step = 0

Form.driver = lambda do |form|
  definitions = game.effective_option_definitions
  language_definition = definitions.find { |definition| definition.key == "content_language_id" }
  language_control = form.fields.find do |field|
    field.is_a?(ListBox) && field.header == language_definition.label
  end
  raise "language control missing" if language_control == nil

  if step == 0
    form.index = form.fields.index(language_control)
    language_control.index = language_definition.choices.index { |choice| choice.value == target_language }
    step += 1
    language_control.trigger(:move)
  end
  selected_language = language_definition.choices[language_control.index].value
  assert(selected_language == target_language, "updating choices reset the selected language")
  set_control = form.fields.find { |field| field.is_a?(ListBox) && field.header == "Game content set" }
  assert(form.fields[form.index] == language_control, "changing language moved focus from the language list")
  expected_count = target_language == "pl-PL" ? 2 : 1
  assert(set_control != nil && set_control.options.length == expected_count, "changing language did not immediately replace the question sets")
  labels = set_control.options.join(" ")
  if target_language == "pl-PL"
    polish_counts = %w[quiz.wikidata.pl quiz.witcher.books.pl]
      .map { |id| GameRoomContent.registry.pack(id).entry_count.to_s }
    assert(polish_counts.all? { |count| labels.include?(count) } && !labels.include?(GameRoomContent.registry.pack("quiz.general.en").entry_count.to_s), "Polish still shows the English question set")
  else
    assert(labels.include?(GameRoomContent.registry.pack("quiz.general.en").entry_count.to_s), "English does not show the OpenTriviaQA set")
  end
  step += 1
  form.fields.find { |field| field.is_a?(Button) && field.label == "Create table" }.trigger(:press)
end

options = app.send(:configure_game_options, game)
assert(step == 2, "language selection did not finish in the same form")
assert(options["content_language_id"] == target_language, "the option form rejected the selected language")
selected_pack = game.selected_content_pack(options)
assert(selected_pack != nil && selected_pack.language_id == target_language, "the option form did not select a compatible question set")

multiple_choice_game = Class.new(GameRoomGames::QuizParty) do
  def option_definitions
    super + [
      GameRoomGames::OptionDefinition.new(
        key: "topics",
        label: "Topics",
        kind: :multiple_choice,
        default: 1,
        choices: [
          GameRoomGames::OptionChoice.new(value: "alpha", label: "Alpha"),
          GameRoomGames::OptionChoice.new(value: "beta", label: "Beta")
        ]
      )
    ]
  end
end.new
multiple_target_language = multiple_choice_game.default_options["content_language_id"] == "en" ? "pl-PL" : "en"
multiple_step = 0

Form.driver = lambda do |form|
  definitions = multiple_choice_game.effective_option_definitions
  language_definition = definitions.find { |definition| definition.key == "content_language_id" }
  topics_definition = definitions.find { |definition| definition.key == "topics" }
  language_control = form.fields.find { |field| field.is_a?(ListBox) && field.header == language_definition.label }
  topics_control = form.fields.find { |field| field.is_a?(ListBox) && field.header == topics_definition.label }
  raise "multiple-choice controls missing" if language_control == nil || topics_control == nil

  if multiple_step == 0
    language_control.index = language_definition.choices.index { |choice| choice.value == multiple_target_language }
    topics_control.select_multiselection_indices([1])
    multiple_step += 1
    language_control.trigger(:move)
  end
  selected_language = language_definition.choices[language_control.index].value
  assert(selected_language == multiple_target_language, "updating choices reset the language beside a multiple-choice option")
  assert(topics_control.multiselections.sort == [0, 1], "updating choices reset a multiple-choice option")
  multiple_step += 1
  form.fields.find { |field| field.is_a?(Button) && field.label == "Create table" }.trigger(:press)
end

multiple_options = app.send(:configure_game_options, multiple_choice_game)
assert(multiple_step == 2, "multiple-choice test did not finish in the same form")
assert(multiple_options["topics"] == 3, "updating choices lost the multiple-choice mask")

# Exercise dependent defaults and visibility through the actual shared editor,
# not only by calling each game's normalization method in isolation.
rummy = GameRoomGames::Rummy.new
Form.driver = lambda do |form|
  field = ->(key) { form.fields.find { |control| control.header == rummy.effective_option_definitions.find { |d| d.key == key }.label } }
  assert(form.fields.count { |control| control.is_a?(ListBox) } == 1, "Rummy added a list besides discard mode")
  elimination, limit = field.call("elimination"), field.call("score_limit")
  assert(limit.text == "1000", "normal Rummy limit")
  elimination.checked = true
  elimination.trigger(:change)
  assert(limit.text == "500", "elimination did not update the default limit in the editor")
  limit.set_text("1500")
  elimination.checked = false
  elimination.trigger(:change)
  assert(limit.text == "1500", "variant change overwrote a custom limit")
  form.accept_button.trigger(:press)
end
assert(app.send(:configure_game_options, rummy)["score_limit"] == 1500, "Rummy editor lost customized value")

domino = GameRoomGames::Domino.new
Form.driver = lambda do |form|
  field = ->(key) { form.fields.find { |control| control.header == domino.effective_option_definitions.find { |d| d.key == key }.label } }
  dependencies = %w[allow_playable_draw draw_until].map { |key| field.call(key) }
  assert(dependencies.none? { |control| form.hidden_controls.include?(control) }, "drawing options hidden before prohibition")
  assert(form.hidden_controls.include?(field.call("whole_team")), "whole team visible in individual play")
  field.call("forbid_draw").checked = true
  field.call("forbid_draw").trigger(:change)
  assert(dependencies.all? { |control| form.hidden_controls.include?(control) }, "forbidden drawing leaves dependent options visible")
  field.call("teams").checked = true
  field.call("teams").trigger(:change)
  assert(!form.hidden_controls.include?(field.call("whole_team")), "team variant hides team finish")
  form.accept_button.trigger(:press)
end
domino_options = app.send(:configure_game_options, domino)
assert(domino_options["forbid_draw"] && !domino_options["draw_until"] && !domino_options["allow_playable_draw"], "hidden drawing options affect actual rules")

Form.driver = lambda do |form|
  limit = form.fields.find { |control| control.header == rummy.option_definitions.find { |d| d.key == 'score_limit' }.label }
  assert(limit.text == '1700', 'editing a table starts from its current values')
  assert(form.accept_button.label == 'Save changes', 'editing must not say Create table')
  form.accept_button.trigger(:press)
end
edited = app.send(:configure_game_options, rummy, initial_options: rummy.normalize_options('score_limit' => 1700), submit_label: 'Save changes')
assert(edited['score_limit'] == 1700, 'save replaced the current options with remembered defaults')
mille_bornes = GameRoomGames::MilleBornes.new
[nil, {}, { "include_safeties" => true }, { "include_safeties" => false }].each do |initial|
  [true, false].each do |selected|
    expected = initial == nil ? true : initial.fetch("include_safeties", true)
    Form.driver = lambda do |form|
      definition = mille_bornes.option_definitions.find { |item| item.key == "include_safeties" }
      control = form.fields.find { |field| field.is_a?(CheckBox) && field.header == definition.label }
      assert(control != nil, "Mille Bornes safety checkbox missing")
      assert(control.checked == expected, "sparse normalized safety default lost its declared value")
      control.checked = selected
      control.trigger(:change)
      form.accept_button.trigger(:press)
    end
    options = app.send(:configure_game_options, mille_bornes, initial_options: initial)
    assert(options == mille_bornes.normalize_options("include_safeties" => selected), "safety editor changed the normalized option contract")
    assert(mille_bornes.send(:deck_for, options).length == (selected ? 106 : 102), "safety checkbox did not change the physical deck")
  end
end
puts "Game option form tests passed"
