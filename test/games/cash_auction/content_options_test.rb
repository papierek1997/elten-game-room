require_relative '../../support/assertions'
require_relative '../../../games/cash_auction'

include GameRoomTest::Assertions
GameRoomLocalization.boot(settings: {'interface_language'=>'en', 'known_languages'=>['en']})
game = GameRoomGames::CashAuction.new
catalog = GameRoomContent.registry.packs_for(game_id: 'quiz', kind: 'quiz')
loaded = catalog.to_h { |pack| [pack.id, pack.verified?] }
pl_ids = catalog.select { |pack| pack.language_id == 'pl-PL' }.map(&:id).sort
assert_equal(3, pl_ids.length)

options = game.table_creation_options('content_language_id'=>'pl-PL')
assert_equal(3, options['auction_rules_version'])
assert_equal(10_000, options['starting_points'])
assert_equal(3, options['count_interval'])
assert_equal(10, options['black_chest_chance'])
assert_equal(pl_ids, options['content_pack_ids'])
assert_equal(false, options.key?('content_pack_id'))
assert_equal(false, options.key?('content_set_id'))
assert_equal(pl_ids, options['content_pack_manifest'].map { |entry| entry['id'] })
assert_equal(nil, game.validation_error(options, player_count: 3))
assert_equal(options, game.options_from_json(JSON.generate(options)))
assert_equal(JSON.generate(options), JSON.generate(game.normalize_options(options)), 'Normalization reordered the serialized new options')
assert_equal(options, game.game_start_options(options, players: %w[Alice Bob], fixed: true))
definition = game.effective_option_definitions(options).find { |item| item.key == 'content_pack_ids' }
assert_equal(:multiple_values, definition.kind)
assert_equal(pl_ids, definition.choices.map(&:value).sort)
remembered_keys = game.remembered_option_definitions(game.effective_option_definitions(options), options: options).map(&:key)
assert(remembered_keys.include?('content_language_id') && remembered_keys.include?('content_pack_ids'), 'Remembered pack IDs lost their language')
assert_equal(loaded, catalog.to_h { |pack| [pack.id, pack.verified?] }, 'Option metadata loaded the question databases')

two_ids = pl_ids.first(2)
changed = game.table_creation_options(options.merge('content_pack_ids'=>two_ids.reverse))
assert_equal(two_ids, changed['content_pack_ids'])
assert_equal(two_ids, changed['content_pack_manifest'].map { |entry| entry['id'] })
assert_equal(nil, game.validation_error(changed))
assert_equal(changed, game.new_game_options(changed))
assert_equal(two_ids, game.auction_content_packs(changed).map(&:id))
summary = game.notification_variant(changed)
assert(summary.include?(GameRoomContent.registry.language('pl-PL').label), 'The invitation lost its content language')
game.auction_content_packs(changed).each { |pack| assert(summary.include?(pack.title), 'The invitation lost a selected question set') }
assert_equal(false, summary.include?('quiz.'), 'The invitation exposed internal pack IDs')

[[], [pl_ids.first], pl_ids + ['missing'], ['missing'], 'all', [3]].each do |ids|
  invalid = game.normalize_options(options.merge('content_pack_ids'=>ids))
  assert(game.validation_error(invalid), "Accepted invalid pack selection #{ids.inspect}")
end
empty = game.normalize_options(options.merge('content_pack_ids'=>[]))
assert_equal([], empty['content_pack_ids'], 'The empty checklist regained the default selection')
remembered_empty = game.remembered_table_creation_options('content_language_id'=>'pl-PL', 'content_pack_ids'=>[])
assert_equal([], remembered_empty['content_pack_ids'], 'Remembered empty choices fell back to all packs')
remembered_missing = game.remembered_table_creation_options('content_language_id'=>'pl-PL', 'content_pack_ids'=>['missing'])
assert_equal(['missing'], remembered_missing['content_pack_ids'], 'An unavailable remembered choice was silently replaced')
extension = game.build_option_editor_extension(nil, options)
assert_equal([], extension.fields)
assert_raises(ArgumentError) { extension.prepare(empty) }
rebound = extension.prepare(game.normalize_options(options.merge('content_pack_ids'=>two_ids)))
assert_equal(changed, rebound, 'Saving the changed checklist retained the old manifest')
assert_equal(pl_ids, options['content_pack_manifest'].map { |entry| entry['id'] }, 'Editing changed the previous table options')

%w[en ru-RU].each do |language|
  single = game.table_creation_options('content_language_id'=>language)
  assert_equal(1, single['content_pack_ids'].length)
  assert_equal(nil, game.validation_error(single))
  assert_equal([single['content_pack_ids'].first], game.auction_content_packs(single).map(&:id))
  assert_equal(definition.label, game.effective_option_definitions(single).find { |item| item.key == 'content_pack_ids' }.label,
    'Changing language would leave a stale native checklist header')
end
english = game.table_creation_options('content_language_id'=>'en')
changes = game.option_editor_changes(english, english.merge('content_language_id'=>'pl-PL'))
assert_equal(pl_ids, changes['content_pack_ids'])

%w[id set language version checksum].each do |key|
  forged = Marshal.load(Marshal.dump(options))
  forged['content_pack_manifest'][0][key] = key == 'version' ? 999 : 'changed'
  normalized = game.normalize_options(forged)
  assert_equal(forged['content_pack_manifest'], normalized['content_pack_manifest'], 'Normalization repaired an unauthenticated manifest')
  assert(game.validation_error(normalized), "Accepted a forged manifest #{key}")
  assert_equal(game.auction_content_packs(options).map(&:title).join(', '), game.notification_choice(normalized, 'content_pack_ids'),
    'An invitation used untrusted manifest text instead of registered pack titles')
end
[nil, [], {}, Array.new(4) { options['content_pack_manifest'].first }, [{1=>'mixed', 'id'=>'keys'}]].each do |manifest|
  invalid = game.normalize_options(options.merge('content_pack_manifest'=>manifest))
  assert(game.validation_error(invalid), 'Accepted a malformed manifest')
end
[nil, 0, 4, '2', '3', false, 2.0, 3.0, [2]].each do |version|
  invalid = game.normalize_options(options.merge('auction_rules_version'=>version))
  assert_equal(version, invalid['auction_rules_version'])
  assert(game.validation_error(invalid), 'An invalid rules marker silently selected legacy rules')
end

# Single-pack histories and already fixed bindings retain exactly their old
# options and defaults. Only an ordinary new game opts into the new controls.
legacy = game.normalize_options('content_language_id'=>'pl-PL', 'content_set_id'=>'quiz.witcher.books')
assert_equal(false, legacy.key?('auction_rules_version'))
assert_equal(false, legacy.key?('content_pack_ids'))
assert_equal(1000, legacy['starting_points'])
assert_equal(2, legacy['count_interval'])
assert_equal(5, legacy['black_chest_chance'])
assert_equal(3210, game.normalize_options(starting_points: 3210)['starting_points'], 'Historical defaults hid an explicit symbol-keyed setting')
assert_equal('quiz.witcher.books.pl', legacy['content_pack_id'])
assert_equal(nil, game.validation_error(legacy))
assert_equal(legacy, game.game_start_options(legacy, players: %w[Alice Bob], fixed: true))
assert_equal(legacy, game.options_from_json(JSON.generate(legacy)))
contract = JSON.parse(File.read(File.expand_path('../../fixtures/contracts/v1/cash_auction.json', __dir__), encoding: 'UTF-8'))
contract_options = game.normalize_options(GameRoomCashAuction::Rules::DEFAULT_OPTIONS.merge('starting_points'=>2000))
assert_equal(contract.fetch('session').fetch('options'), JSON.generate(contract_options), 'The immutable single-pack option JSON changed its key order')
assert_equal('quiz.witcher.books.pl', game.auction_content_packs(legacy).first.id)
upgraded = game.new_game_options(legacy)
assert_equal(3, upgraded['auction_rules_version'])
assert_equal(pl_ids, upgraded['content_pack_ids'])
assert_equal(false, upgraded.key?('content_pack_id'))
assert_equal(nil, game.validation_error(upgraded))
assert_equal(legacy, game.normalize_options(legacy), 'Preparing a new game mutated its historical options')

puts 'Cash Auction content options: language checklist, exact selection counts, pinned manifests, explicit new-game upgrade and unchanged fixed single-pack histories passed.'
