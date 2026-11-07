require_relative "../support/private_table_creation"

announcements = []
original_announcement = EltenGameRoom.method(:announce_new_public_table)
EltenGameRoom.define_singleton_method(:announce_new_public_table) { |table| announcements << table }
begin
  # Reproduce the reported extra dialog through the actual creation entry,
  # not by testing only the checkbox or the lower-level editor.
  [false, true].each do |private_table|
    game = GameRoomGames::Uno.new
    app = CreationFormApp.new(game)
    forms = 0
    Form.driver = lambda do |form|
      forms += 1
      assert(forms == 1, "creating a table opened another dialog after game settings")
      privacy = privacy_field(form)
      assert(form.index == 0 && form.fields.first.is_a?(Static), "creation must focus the opening instructions")
      assert(form.fields.first.text.start_with?("Choose game options"), "opening instructions were replaced")
      assert(form.fields[1].equal?(privacy), "first Tab must still lead from instructions to privacy")
      assert(privacy.checked == false, "new tables should default to public")
      assert(form.fields.length > 5, "privacy was displayed without the game options")
      privacy.checked = private_table
      form.accept_button.trigger(:press)
    end
    before = announcements.length
    app.send(:show_create_table)
    assert(forms == 1 && app.network_calls.length == 1, "creation needs one form and one creation task")
    assert(app.lobby.creations.length == 1, "table was not created exactly once")
    request = app.lobby.creations.first
    assert(request[:private_table] == private_table, "wrong privacy sent to the lobby")
    assert(JSON.parse(request[:game_options]) == game.default_options, "privacy leaked into game options or changed defaults")
    assert(announcements.length - before == (private_table ? 0 : 1), "private table was announced or public announcement was lost")
    assert(app.opened_tables.length == 1, "created table was not opened")
  end

  [false, true].each do |private_table|
    app = CreationFormApp.new(GameRoomGames::Uno.new)
    Form.driver = lambda do |form|
      privacy_field(form).checked = private_table
      form.cancel_button.trigger(:press)
    end
    before = announcements.length
    app.send(:show_create_table)
    assert(app.lobby.creations.empty? && app.network_calls.empty? && app.opened_tables.empty?, "Cancel created/opened a table")
    assert(app.remembered.empty? && announcements.length == before, "Cancel saved options or announced a room")
  end
ensure
  EltenGameRoom.define_singleton_method(:announce_new_public_table, original_announcement)
end

# All registered games share the creation path. Privacy is never part of
# rules, remembered game profiles or Ctrl+X's editable options.
ids = EltenGameRoom::GAME_REGISTRY.ids
ids.each do |id|
  game = EltenGameRoom::GAME_REGISTRY.build(id)
  app = CreationFormApp.new(game)
  [false, true].each do |private_table|
    waits = 0
    Form.driver = lambda do |form|
      waits += 1
      assert(waits == 1, "#{id}: extra creation window")
      privacy = privacy_field(form)
      assert(form.index == 0 && form.fields.first.is_a?(Static), "#{id}: creation skipped the opening instructions")
      assert(privacy.checked == false, "#{id}: remembered privacy changed the next table")
      privacy.checked = private_table
      form.accept_button.trigger(:press)
    end
    result = app.send(:configure_game_options, game, creating_table: true)
    assert(result == { game_options: game.table_creation_options, private_table: private_table }, "#{id}: inconsistent creation result")
    assert(app.remembered.last[2] == game.table_creation_options, "#{id}: privacy entered remembered game rules")
  end
  Form.driver = lambda do |form|
    assert(form.fields.none? { |field| field.is_a?(CheckBox) && field.header == "Private table" }, "#{id}: Ctrl+X offered privacy changes")
    assert(form.accept_button.label == "Save changes", "#{id}: editing says Create table")
    form.accept_button.trigger(:press)
  end
  # Edit the options actually stored on a new table. A replay's defaults
  # may omit fields that the creation and editing forms explicitly store.
  initial_options = game.table_creation_options
  result = app.send(:configure_game_options, game, initial_options: initial_options, submit_label: "Save changes")
  assert(result == initial_options, "#{id}: Ctrl+X did not preserve the table's rules")
end

tysiac = EltenGameRoom::GAME_REGISTRY.build("tysiac")
app = CreationFormApp.new(tysiac)
Form.driver = ->(form) { form.accept_button.trigger(:press) }
legacy = app.send(:configure_game_options, tysiac, initial_options: tysiac.default_options, submit_label: "Save changes")
assert(legacy == tysiac.default_options.merge("redeal_four_nines" => true, "redeal_talon_nines" => false),
  "Editing a table without redeal options did not fill in the correct defaults")

[GameRoomGames::QuizParty.new, GameRoomGames::Taboo.new].each do |game|
  app = CreationFormApp.new(game)
  waits = 0
  Form.driver = lambda do |form|
    waits += 1
    assert(waits == 1, "language change opened a new creation form")
    privacy = privacy_field(form)
    privacy.checked = true
    definition = game.effective_option_definitions.find { |item| item.key == "content_language_id" }
    language = form.fields.find { |field| field.header == definition.label }
    form.index = form.fields.index(language)
    definition.choices.each_index do |index|
      language.index = index
      language.trigger(:move)
      assert(form.fields[form.index].equal?(language) && privacy.checked == true, "language change lost privacy or focus")
      assert(!form.hidden_controls.include?(privacy), "dependent options hid privacy")
    end
    form.accept_button.trigger(:press)
  end
  assert(app.send(:configure_game_options, game, creating_table: true)[:private_table], "language changes lost private table")
end

# An index changed without a :move callback uses the editor's fallback
# rebuild. Carry privacy over that rebuild, not just in-place refreshes.
game = GameRoomGames::QuizParty.new
app = CreationFormApp.new(game)
definition = game.effective_option_definitions.find { |item| item.key == "content_language_id" }
target = definition.choices.find { |choice| choice.value != game.default_options["content_language_id"] }.value
waits = 0
Form.driver = lambda do |form|
  waits += 1
  assert(waits <= 2, "language fallback did not finish")
  privacy = privacy_field(form)
  language = form.fields.find { |field| field.header == definition.label }
  if waits == 1
    privacy.checked = true
    language.index = definition.choices.index { |choice| choice.value == target }
  else
    assert(privacy.checked, "language fallback reset privacy")
    assert(definition.choices[language.index].value == target, "language fallback reset selected language")
  end
  form.accept_button.trigger(:press)
end
result = app.send(:configure_game_options, game, creating_table: true)
assert(waits == 2 && result[:private_table] && result[:game_options]["content_language_id"] == target, "invalid fallback result")

no_options = Class.new(GameRoomGames::Base) do
  def id; "no_options"; end
  def effective_option_definitions(*); []; end
  def default_options; {}; end
  def normalize_options(*); {}; end
end.new
app = CreationFormApp.new(no_options)
Form.driver = lambda do |form|
  privacy_field(form).checked = true
  form.accept_button.trigger(:press)
end
assert(app.send(:configure_game_options, no_options, creating_table: true) == { game_options: {}, private_table: true }, "game without options skipped privacy")
Form.driver = ->(_) { raise "empty options editor should not open a form outside creation" }
assert(app.send(:configure_game_options, no_options) == {}, "empty options editor changed")

invalid_once = GameRoomGames::Reversi.new
validation_calls = 0
invalid_once.define_singleton_method(:validation_error) do |*|
  validation_calls += 1
  validation_calls == 1 ? "Invalid test setting" : nil
end
app = CreationFormApp.new(invalid_once)
waits = 0
Form.driver = lambda do |form|
  waits += 1
  assert(waits <= 2, "validation failed to finish")
  privacy = privacy_field(form)
  assert(privacy.checked == (waits > 1), "validation reset selected privacy")
  privacy.checked = true
  form.accept_button.trigger(:press)
end
assert(app.send(:configure_game_options, invalid_once, creating_table: true)[:private_table], "validation lost privacy")
assert(app.notices == ["Invalid test setting"], "unexpected validation flow")
puts "PASS private table creation: one shared form, #{ids.length} games, public/private, Cancel, Ctrl+X, language, validation and no-option games"
