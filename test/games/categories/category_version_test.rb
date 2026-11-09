require_relative '../../support/categories'
require_relative '../../support/sequence_random'

game = GameRoomGames::Categories.new
klass = GameRoomGames::Categories
removed = %w[surname famous_person building invention chemical_element]
version_two = %w[drink known_athlete tool known_actor known_writer]
historical_wire = klass::LEGACY_HARD_CATEGORY_IDS + version_two
assert(klass::CATEGORY_IDS.first(historical_wire.size) == historical_wire, 'Historical category mask positions moved')
assert((klass::CATALOG_CATEGORY_IDS & removed).empty?, 'A retired category is still offered')
assert(game.default_options['category_version'] == 4, 'New default options did not select the cumulative pools')

legacy = {'category_set'=>'custom', 'custom_categories'=>1 << 9, 'round_category_count'=>1}
old_options = game.normalize_options(legacy)
assert(!old_options.key?('category_version'), 'Historical options acquired a new hashed field')
assert(game.send(:selected_category_pool, old_options) == ['surname'], 'Old custom mask became Drink')
old_def = game.effective_option_definitions(old_options).find { |item| item.key == 'custom_categories' }
assert(old_def.choices[9].value == 'surname', 'Historical option reader reinterpreted a custom bit')
assert(game.options_from_json(JSON.generate(old_options)) == old_options, 'Historical options changed on reload')
legacy_array = game.normalize_options('category_set'=>'custom', 'custom_categories'=>%w[surname building], 'round_category_count'=>2)
assert(game.send(:selected_category_pool, legacy_array) == %w[surname building], 'Legacy string selections were discarded')

old_v2 = game.normalize_options('category_version'=>2, 'category_set'=>'custom', 'custom_categories'=>version_two, 'round_category_count'=>5)
v2_def = game.effective_option_definitions(old_v2).find { |item| item.key == 'custom_categories' }
assert(v2_def.kind == :multiple_choice && v2_def.choices.map(&:value) == klass::V2_HARD_CATEGORY_IDS, 'Version 2 checklist changed')
assert(game.send(:selected_category_pool, old_v2) == version_two, 'Version 2 selections changed')
assert(game.options_from_json(JSON.generate(old_v2)) == old_v2, 'Version 2 options changed on reload')
converted = game.table_creation_options(old_v2.merge('round_category_count'=>1))
assert(game.send(:selected_category_pool, converted) == ['tool'], 'Reusing old options reinterpreted a retired category')
remembered = game.remembered_table_creation_options('custom_categories'=>old_v2.fetch('custom_categories'))
assert(game.send(:selected_category_pool, remembered.merge('category_set'=>'custom')) == ['tool'], 'The old local preference was not migrated')

fresh = game.table_creation_options('category_set'=>'custom', 'custom_categories'=>%w[tool medical_equipment unit_of_measurement], 'round_category_count'=>3)
fresh_def = game.effective_option_definitions(fresh).find { |item| item.key == 'custom_categories' }
assert(fresh_def.kind == :multiple_choice && fresh_def.choices.map(&:value) == klass::CATALOG_CATEGORY_IDS,
  'New custom choices do not use the complete current checklist')
assert(game.send(:selected_category_pool, fresh) == %w[tool medical_equipment unit_of_measurement], 'New custom selections changed')
assert(game.validation_error(fresh).nil?, 'New category selections are invalid')
assert(JSON.generate(game.default_options).bytesize <= 256, 'New defaults exceed the option size budget')
assert(game.options_from_json(JSON.generate(fresh)) == fresh, 'New selections changed on reload')
old_v3 = fresh.merge('category_version'=>3)
assert(game.options_from_json(JSON.generate(old_v3)) == old_v3, 'Version 3 options changed on reload')
assert(game.send(:selected_category_pool, old_v3) == %w[tool medical_equipment unit_of_measurement], 'Version 3 wide custom mask changed')
assert(game.table_creation_options(old_v3) == fresh, 'Creating a new table reinterpreted the previous wide custom mask')
assert(game.send(:decode_round_categories, game.send(:encode_round_categories, removed)) == removed,
  'Old round categories no longer decode faithfully')
assert(game.send(:decode_round_categories, game.send(:encode_round_categories, version_two)) == version_two,
  'Version 2 round categories did not retain their physical wire identities')

players = %w[Alice Bob]
repo = CategoriesRepository.new(players)
[old_options, old_v2, old_v3, fresh].each do |options|
  context = GameRoomGames::ActionContext.new(session_id: 7, table_id: 4, now: 100,
    hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
    random_source: GameRoomRandom::SequenceSource.new([1]))
  session = {'options'=>JSON.generate(options)}
  replay = game.replay(session, [], repo)
  selection = game.automatic_action(replay, 'Alice', context: context)
  status, plan = game.action_for(selection, replay, 'Alice', context: context)
  assert(status == :ok, 'Could not start a category-version round')
  events = []
  append_plan(events, plan, 'Alice', now: context.now)
  actual = GameRoomGames::Categories.new.replay(session, events, repo)
  assert(actual.accepted_events.size == events.size, 'Versioned round was rejected on cold replay')
  assert(actual.state[:round_categories] == game.send(:selected_category_pool, options), 'Round used another category dialect')
end

puts 'PASS Categories versions: new choices/pools, append-only round IDs, old options/masks/rounds and new cold replay'
