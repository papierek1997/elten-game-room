require_relative '../support/game_option_encoding'

GameRoomTestLocalization.use_language('en')
app = EltenGameRoom.allocate
app.define_singleton_method(:read_json) { |_path, default:| default }
app.define_singleton_method(:remember_multiple_choice_options) { |*_arguments| }
app.define_singleton_method(:alert) { |message| raise message }

submit = lambda do |game, initial = nil, &change|
  Form.option_encoding_driver = lambda do |form|
    change&.call(form)
    form.accept_button.trigger(:press)
  end
  app.send(:configure_game_options, game, initial_options: initial)
end
check = ->(value, message) { raise message unless value }

categories = GameRoomGames::Categories.new
fresh = categories.table_creation_options('category_set' => 'custom',
  'custom_categories' => %w[soft_drink unit_of_measurement], 'round_category_count' => 2)
check.call(submit.call(categories) == categories.table_creation_options, 'Creation lost canonical metadata')
check.call(submit.call(categories, fresh) == fresh, 'Editing changed the new category dialect')
legacy = categories.normalize_options('category_set' => 'custom',
  'custom_categories' => 1 << 9, 'round_category_count' => 1)
check.call(submit.call(categories, legacy) == legacy, 'Editing rewrote historical options')
check.call(categories.send(:selected_category_pool, legacy) == ['surname'], 'Legacy mask was reinterpreted')

changed = submit.call(categories, fresh) do |form|
  definition = categories.effective_option_definitions(fresh).find { |item| item.key == 'custom_categories' }
  control = form.fields.grep(ListBox).find { |item| item.header == definition.label }
  control.deselect_multiselection_indices(control.multiselections)
  control.select_multiselection_indices(definition.choices.each_index.select { |index| %w[tool soft_drink].include?(definition.choices[index].value) })
end
check.call(changed['category_version'] == 4, 'Changing a visible field dropped the current category dialect')
check.call(categories.send(:selected_category_pool, changed) == %w[soft_drink tool], 'New custom checklist used legacy choices')
check.call(fresh == categories.table_creation_options('category_set' => 'custom',
  'custom_categories' => %w[soft_drink unit_of_measurement], 'round_category_count' => 2), 'The initial options were mutated')

v2_preferences = 1 << GameRoomGames::Categories::V2_HARD_CATEGORY_IDS.index('tool')
tool_mask = (1 << GameRoomGames::Categories::CATALOG_CATEGORY_IDS.index('tool')).to_s
app.define_singleton_method(:read_json) do |path, default:|
  path == 'game_option_preferences.json' ? { 'categories' => { 'custom_categories' => v2_preferences } } : default
end
remembered = submit.call(categories) do |form|
  definition = categories.effective_option_definitions.find { |item| item.key == 'custom_categories' }
  control = form.fields.grep(ListBox).find { |item| item.header == definition.label }
  selected = control.multiselections.map { |index| definition.choices.fetch(index).value }
  check.call(selected == ['tool'], 'The new-table editor did not show the migrated category preference')
end
check.call(remembered['custom_categories'] == tool_mask, 'Submitting the form rewrote the migrated choice')
check.call(categories.remembered_table_creation_options('custom_categories'=>tool_mask)['custom_categories'] == tool_mask,
  'Reopening the wide checklist lost its saved category')
app.define_singleton_method(:read_json) { |_path, default:| default }

miles = GameRoomGames::MilleBornes.new
initial = miles.normalize_options(GameRoomTeams::OPTION_KEY => [0, 1, 0, 1],
  GameRoomTeams::PLAYERS_KEY => %w[A B C D], 'team_size' => 2)
check.call(submit.call(miles, initial.merge('unknown_option' => 'discard')) == initial,
  'Canonical team metadata was lost or undeclared input was retained')

quiz = GameRoomGames::QuizParty.new
initial = quiz.table_creation_options('content_language_id' => 'pl-PL', 'content_set_id' => 'quiz.wikidata')
changed = submit.call(quiz, initial) do |form|
  definition = quiz.effective_option_definitions(initial).find { |item| item.key == 'content_language_id' }
  control = form.fields.grep(ListBox).find { |item| item.header == definition.label }
  control.index = definition.choices.index { |choice| choice.value == 'en' }
  control.trigger(:move)
end
check.call(changed['content_language_id'] == 'en' && changed['content_set_id'] == 'quiz.general',
  'Dependent content controls retained the previous language')
check.call(quiz.validation_error(changed).nil? && quiz.selected_content_pack(changed)&.language_id == 'en',
  'Preserving metadata retained a stale content-pack identity')
check.call(initial['content_language_id'] == 'pl-PL', 'Language editing mutated the source options')

puts 'PASS option metadata: new/legacy category masks, edits, teams, unknown keys and dependent content packs; no keyboard or network'
