require_relative '../../support/ui'
require_relative '../../../lib/game_surfaces'
require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions

spades = GameRoomGames::Spades.new
raw = %w[AS 2H AC TC 2S AH AD 2C 2D QS JH KH 3D]
expected = raw.sort_by { |card| spades.send(:card_sort_key, card) }
table = GameRoomTest::DealtCardTable.new('bouillabaisse', seed: 8)
game, viewer = table.game, 'Alice'
table.state[:hands][viewer] = raw.dup
before = Marshal.dump([table.state, table.events, game.legal_actions(table.replay, viewer), game.bot_observation(table.replay, viewer)])
spec = game.surface_spec(table.replay, viewer)
zone = spec.zones.first
assert_equal(expected, zone.cards.map(&:id), 'Default Bouillabaisse hand differs from Spades')
assert_equal(raw, zone.hand_order, 'Presentation changed the actual received order')
assert_equal(raw.each_with_index.to_h, zone.cards.to_h { |card| [card.id, card.sort_keys.fetch('none').first] },
  'Physical receipt metadata changed with the display order')
reminder = game.game_shortcuts(table.replay, viewer).find { |shortcut| shortcut.key == 'h' && shortcut.modifiers.empty? }.message
labels = expected.map { |card| game.send(:playing_card_label, card) }
assert_equal("Your hand: #{labels.join(', ')}.", reminder, 'H reminder differs from the default displayed order')
assert_equal(before, Marshal.dump([table.state, table.events, game.legal_actions(table.replay, viewer), game.bot_observation(table.replay, viewer)]),
  'Display/H sorting changed the deal, legal actions or bot observation')

surface = GameSurfaces.build(spec)
control = surface.fields.first
selected = expected[4]
control.index = 4
surface.handle_command('sort_cards', 'mode' => 'colour', 'toggle' => true)
assert_equal(labels, control.options, 'Manual suit sorting differs from the default hand')
surface.handle_command('sort_cards', 'mode' => 'colour', 'toggle' => true)
assert_equal(labels.reverse, control.options, 'Descending suit sorting is broken')
assert_equal(selected, surface.instance_variable_get(:@cards).fetch('hand')[control.index].id, 'Sorting moved the selected physical card')
surface.update_spec(game.surface_spec(table.replay, viewer))
assert_equal(labels.reverse, control.options, 'Refresh discarded the explicit sort direction')
assert(!surface.handle_command('sort_cards', 'mode' => 'none'), 'Removed acquisition mode is still accepted')
assert_equal(labels.reverse, control.options, 'Refused sorting changed the display')
surface.handle_command('sort_cards', 'mode' => 'number', 'toggle' => true)
numeric = zone.cards.sort_by { |card| card.sort_keys.fetch('number') }.map(&:label)
assert_equal(numeric, control.options, 'Rank sorting is broken')
assert_equal(selected, surface.instance_variable_get(:@cards).fetch('hand')[control.index].id, 'Rank sorting moved the selected physical card')
surface.update_spec(game.surface_spec(table.replay, viewer))
assert_equal(numeric, control.options, 'Refresh discarded explicit rank sorting')

# Each member follows its own declaration; Scopa now intentionally uses values.
scopa = GameRoomTest::DealtCardTable.new('scopa')
scopa_raw = scopa.state[:hands][viewer].dup
scopa_expected = scopa_raw.sort_by { |card| [GameRoomGames::Scopa.card_value(card), %w[H S D C].index(card[1])] }
assert_equal(scopa_expected, scopa.game.surface_spec(scopa.replay, viewer).zones.first.cards.map(&:id), 'Scopa did not use its declared value order')
assert_equal("Your hand: #{scopa.game.send(:cards_text, scopa_expected)}.",
  scopa.game.shortcut_feature_data(:hand, scopa.replay, viewer).fetch(:message), 'Scopa reminder differs from its declared value order')

puts 'PASS Bouillabaisse hand order: Spades default/H parity, raw order and state preserved, manual sorting/cursor/refresh and separate Scopa value policy'
