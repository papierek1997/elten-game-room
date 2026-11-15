require_relative '../../support/assertions'
require_relative '../../../games/cash_auction'
require_relative '../../../lib/table_variant'

include GameRoomTest::Assertions
game = GameRoomGames::CashAuction.new
options = game.table_creation_options('content_language_id'=>'pl-PL').merge(
  '__secret'=>'private', 'player_answer'=>'never advertise', 'arbitrary_title'=>'forged')
payload = GameRoomTableVariant.payload(game, JSON.generate(options))
assert_equal(%w[content_language_id content_pack_ids], payload.fetch('options').keys.sort)
assert_equal(options['content_pack_ids'], payload['options']['content_pack_ids'])
assert_equal(false, payload.to_s.include?('checksum'))
assert_equal(false, payload.to_s.include?('__secret'))
assert_equal(false, payload.to_s.include?('player_answer'))
assert_equal(false, payload.to_s.include?('auction_rules_version'))
description = GameRoomTableVariant.text(game, payload)
language = GameRoomContent.registry.language('pl-PL').label
assert(description.include?(language), 'The recipient lost the question language')
game.auction_content_packs(options).each do |pack|
  assert(description.include?(pack.title), 'The recipient lost a selected pack title')
end
assert_equal(false, description.include?('quiz.'), 'The recipient heard internal pack IDs')
assert_equal(false, description.include?('forged'))
assert_equal(description, GameRoomTableVariant.text(game, JSON.parse(JSON.generate(payload))))

two = game.table_creation_options(options.merge('content_pack_ids'=>options['content_pack_ids'].first(2)))
two_text = GameRoomTableVariant.text(game, GameRoomTableVariant.payload(game, two))
selected = game.auction_content_packs(two)
selected.each { |pack| assert(two_text.include?(pack.title)) }
other = game.auction_content_packs(options).find { |pack| !selected.include?(pack) }
assert_equal(false, two_text.include?(other.title), 'The recipient heard an unselected pack')

[nil, [], ['missing'], [3], 'quiz.wikidata.pl', options['content_pack_ids'] * 2].each do |ids|
  incoming = {'format'=>1, 'options'=>{'content_language_id'=>'pl-PL', 'content_pack_ids'=>ids}}
  assert_equal(language, GameRoomTableVariant.text(game, incoming), 'Malformed or absent choices gained default or arbitrary titles')
end
assert_equal('', GameRoomTableVariant.text(game, {'format'=>1, 'options'=>{}}))
assert_equal('', GameRoomTableVariant.text(game, {'format'=>1, 'options'=>{'content_pack_ids'=>['missing']}}))
assert_equal('', GameRoomTableVariant.text(game, nil))

# The single-pack packet has no new marker and remains readable as before.
legacy = game.normalize_options('content_language_id'=>'pl-PL', 'content_set_id'=>'quiz.witcher.books')
legacy_payload = GameRoomTableVariant.payload(game, legacy)
legacy_text = GameRoomTableVariant.text(game, legacy_payload)
assert(legacy_text.include?(language))
assert(legacy_text.include?(game.selected_content_pack(legacy).title))
assert_equal(false, legacy_payload['options'].key?('content_pack_ids'))

puts 'Cash Auction invitation content: actual bounded semantic payload, recipient-local selected titles, legacy packet, malformed refusal and no private/manifest fields passed.'
