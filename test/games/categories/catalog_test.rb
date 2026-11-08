# encoding: UTF-8
require_relative '../../support/categories'
require_relative '../../support/sequence_random'
require_relative '../../../lib/live_session_store'
require_relative '../../../lib/tournaments/publication'

game = GameRoomGames::Categories.new
klass = GameRoomGames::Categories
custom_definition = -> { game.effective_option_definitions.find { |item| item.key == 'custom_categories' } }
ids = klass::CATALOG_CATEGORY_IDS
assert(ids.size == 86 && ids.uniq == ids, 'The new catalogue must have 86 different categories')
sizes = {'easy'=>29, 'medium'=>29, 'hard'=>28}
pools = sizes.to_h do |tier, count|
  options = game.table_creation_options('category_set'=>tier, 'round_category_count'=>9)
  pool = game.send(:selected_category_pool, options)
  assert(pool.size == count, "Wrong number of categories in #{tier}")
  drawn = game.send(:draw_categories, options, 8, 2)
  assert(drawn.size == 9 && drawn.uniq == drawn && (drawn - pool).empty?, "Wrong draw for #{tier}")
  [tier, pool]
end
assert(pools.values.flatten.sort == ids.sort, 'The three difficulty pools must partition all 86 categories exactly once')

GameRoomLocalization.boot(settings: {'interface_language'=>'en', 'known_languages'=>[]})
english = custom_definition.call.choices.map(&:label)
pool_labels = ['Easy, 29 categories', 'Medium, 29 categories', 'Hard, 28 categories']
pool_definition = -> { game.effective_option_definitions.find { |item| item.key == 'category_set' } }
assert(pool_definition.call.choices.first(3).map(&:label) == pool_labels, 'English difficulty labels have stale counts')
%w[pl cs es ru].each do |language|
  GameRoomLocalization.boot(settings: {'interface_language'=>language, 'known_languages'=>[]})
  choices = custom_definition.call.choices
  assert(choices.map(&:value) == ids, "#{language}: translation reordered or replaced category IDs")
  catalog_path = File.expand_path("../../../locale/#{language.upcase}.mo", __dir__)
  catalog = GameRoomLocalization::Catalog.new(File.binread(catalog_path))
  labels = pool_definition.call.choices.first(3).map(&:label)
  assert(pool_labels.map { |label| catalog.translate(label) } == labels, "#{language}: difficulty labels are untranslated")
  english.zip(choices.map(&:label)).each do |source, actual|
    expected = catalog.translate(source, context:'categories') || catalog.translate(source)
    assert(expected && actual == expected, "#{language}: no matching translation for #{source}")
  end
  assert(choices.map(&:label).uniq.size == ids.size, "#{language}: two categories use the same label")
end
GameRoomLocalization.boot(settings: {'interface_language'=>'pl', 'known_languages'=>[]})
expected = File.readlines(File.expand_path('../../fixtures/categories/catalog_pl.txt', __dir__), chomp:true, encoding:'UTF-8')
assert(custom_definition.call.choices.map(&:label) == expected, 'Polish categories must match the supplied list, in order')

options = game.table_creation_options('category_set'=>'custom', 'custom_categories'=>ids.reverse, 'round_category_count'=>9)
assert(game.validation_error(options, player_count:8).nil?, 'Selecting all 86 categories is invalid')
assert(game.send(:selected_category_pool, options) == ids, 'The custom pool changed the catalogue order')
mask = options.fetch('custom_categories')
definition = custom_definition.call
assert(mask == ((1 << ids.size) - 1).to_s && GameRoomOptionValues.valid?(definition, mask),
  'The full checklist does not have a canonical compact mask')
['00', 'invalid', '-1', (1 << ids.size).to_s, 1 << (ids.size - 1)].each do |invalid|
  assert(!GameRoomOptionValues.valid?(definition, invalid), 'An invalid wide mask was accepted for publication')
end

encoded = JSON.generate(options)
store = GameRoomLiveSessionStore.allocate
owner = 'A' * 64
metadata = store.send(:compact_discovery, {
  'kind'=>GameRoomLiveSessionStore::KIND, 'protocol'=>GameRoomLiveSessionStore::SERVER_RANDOM_DISCOVERY_PROTOCOL,
  'table_id'=>2_000_000_000, 'name'=>'T'*128, 'game'=>'categories', 'game_options'=>encoded, 'owner'=>owner,
  'status'=>'playing', 'bot_count'=>0, 'player_count'=>8, 'max_players'=>8,
  'created_at'=>2_000_000_000, 'last_activity_at'=>2_000_000_100, 'private'=>true, 'resume_save_id'=>'',
  'tournament_match'=>{'publication_ref'=>{'author'=>owner, 'publication_key'=>'p'*64},
    'schedule_id'=>'1'*64, 'match_id'=>'2'*64, 'leg'=>1}
})
assert(JSON.generate(metadata).bytesize <= GameRoomLiveSessionStore::DISCOVERY_BYTES,
  'A full custom pool does not fit table discovery with a long name and a tournament match')
assert(store.send(:discovery_options, metadata) == encoded, 'Discovery changed the custom options')
registry = Object.new
registry.define_singleton_method(:build) { |id| game if id == game.id }
settings = {'players_per_match'=>8, 'game_options'=>options}
GameRoomTournaments::Publication.send(:validate_game, game.id, settings, registry)
assert(settings.fetch('game_options') == options, 'Tournament validation changed the full custom pool')

# An existing bit (river) comes before an appended bit (capital city) on the
# wire, but the category and letter pairing must follow the supplied order.
pair = %w[capital_city river]
separate = game.table_creation_options('category_set'=>'custom', 'custom_categories'=>pair.reverse,
  'round_category_count'=>2, 'separate_letters'=>true)
session = {'options'=>JSON.generate(separate)}
repository = CategoriesRepository.new(%w[Alice Bob])
context = GameRoomGames::ActionContext.new(now:2_000_000_000, random_source:GameRoomRandom::SequenceSource.new([1, 1]))
opening = game.replay(session, [], repository)
action = game.automatic_action(opening, 'Alice', context:context)
status, plan = game.action_for(action, opening, 'Alice', context:context)
assert(status == :ok, 'The local round did not open')
events = []
append_plan(events, plan, 'Alice', now:context.now)
state = klass.new.replay(session, events, repository).state
assert(state.fetch(:category_letters) == {'capital_city'=>'A', 'river'=>'B'}, 'Local round moved a letter to another category')

last = ids.last(9)
full_round = [9_999, 9_999, 7, ('A'..'I').to_a.join('.'), 2_000_000_000,
  game.send(:encode_round_categories, last)].join(',')
assert(full_round.bytesize <= GameRoomEventProtocol::MAX_VALUE_LENGTH, 'A late round with nine separate letters exceeds the event limit')
assert(game.send(:parse_round, full_round, options).fetch(:categories) == last, 'High category bits were lost on replay')
puts 'PASS 86 exact Polish labels; disjoint 29/29/28 pools, all translations, full custom checklist and compact tournament options'
