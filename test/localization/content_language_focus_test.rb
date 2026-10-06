require_relative "../support/game_option_form"

# Actual games, same controls, multiple changes without a second Form#wait.
[GameRoomGames::QuizParty.new, GameRoomGames::Taboo.new].each do |game|
  app = EltenGameRoom.allocate
  app.define_singleton_method(:read_json) { |_, default:| default }
  app.define_singleton_method(:alert) { |message| raise message }
  waits = 0
  initial = game.default_options
  Form.driver = lambda do |form|
    waits += 1
    raise "language rebuilt the form" unless waits == 1
    definitions = game.effective_option_definitions(initial)
    language = definitions.find { |definition| definition.key == "content_language_id" }
    set = definitions.find { |definition| definition.key == "content_set_id" }
    language_control = form.fields.find { |field| field.header == language.label }
    set_control = form.fields.find { |field| field.header == set.label }
    form.index = form.fields.index(language_control)
    ids = language.choices.map(&:value)
    (ids + ids.reverse + ids).each do |id|
      language_control.index = ids.index(id)
      spoken = $spoken_messages.length
      language_control.trigger(:move)
      assert(form.fields[form.index].equal?(language_control), "#{game.id}: language lost focus")
      assert($spoken_messages.length == spoken, "#{game.id}: language change read the whole form/set")
      expected = game.effective_option_definitions("content_language_id" => id).find { |definition| definition.key == "content_set_id" }
      assert(set_control.options == expected.choices.map(&:label), "#{game.id}: stale set choices")
    end
    form.cancel_button.trigger(:press)
  end
  assert(app.send(:configure_game_options, game, initial_options: initial, submit_label: "Save changes").nil?, "cancel saved options")
  assert(initial == game.default_options, "editing mutated original options")
end

# A third language catches assumptions hidden by a two-choice list. Shared
# set IDs survive a change; incompatible ones fall back, other fields remain.
future_game = Class.new(GameRoomGames::Base) do
  def id; "language_fixture"; end

  def default_options
    { "content_language_id" => "one", "content_set_id" => "shared", "seconds" => 30, "flag" => false }
  end

  def sets(language)
    { "one" => %w[shared first], "two" => %w[shared second], "three" => %w[third] }.fetch(language)
  end

  def normalize_options(values = {})
    options = default_options.merge(values)
    options["seconds"] = options["seconds"].to_i
    available = sets(options["content_language_id"])
    options["content_set_id"] = available.first unless available.include?(options["content_set_id"])
    options
  end

  def effective_option_definitions(values = {})
    options = normalize_options(values)
    choice = ->(value) { GameRoomGames::OptionChoice.new(value: value, label: value) }
    [GameRoomGames::OptionDefinition.new(key: "content_language_id", label: "Language", kind: :choice,
       default: "one", choices: %w[one two three].map(&choice)),
     GameRoomGames::OptionDefinition.new(key: "content_set_id", label: "Set", kind: :choice,
       default: "shared", choices: sets(options["content_language_id"]).map(&choice)),
     GameRoomGames::OptionDefinition.new(key: "seconds", label: "Seconds", kind: :integer, default: 30),
     GameRoomGames::OptionDefinition.new(key: "flag", label: "Flag", kind: :boolean, default: false)]
  end
end.new
app = EltenGameRoom.allocate
app.define_singleton_method(:read_json) { |_, default:| default }
app.define_singleton_method(:alert) { |message| raise message }
waits = 0
Form.driver = lambda do |form|
  waits += 1
  assert(waits == 1, "three-language form rebuilt")
  field = ->(header) { form.fields.find { |item| item.header == header } }
  language, sets = field.call("Language"), field.call("Set")
  field.call("Seconds").set_text("75")
  field.call("Flag").checked = true
  form.index = form.fields.index(language)
  [[1, "shared"], [2, "third"], [0, "shared"]].each do |index, selected|
    language.index = index
    language.trigger(:move)
    assert(form.fields[form.index].equal?(language), "third language stole focus")
    assert(sets.options[sets.index] == selected, "compatible set selection/fallback lost")
  end
  # Tab changes the focused control, not the dependent refresh callback.
  form.index = form.fields.index(sets)
  assert(form.fields[form.index].equal?(sets), "set list unavailable for manual focus")
  form.accept_button.trigger(:press)
end
saved = app.send(:configure_game_options, future_game, initial_options: future_game.default_options, submit_label: "Save changes")
assert(saved["seconds"] == 75 && saved["flag"] == true, "language change erased other edits")
puts "Content language focus, in-place choices, silent refresh and cancel: OK"
