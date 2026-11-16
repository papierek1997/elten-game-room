require_relative '../support/duck_challenge_native'
require_relative '../support/dealt_card_games'
require_relative '../support/bridge'
require_relative '../support/blackjack'
require_relative '../../lib/game_screen'

GameRoomLocalization.boot(settings: {'interface_language'=>'en'}, host_language:'en')
Session.name = 'Alice'

def hand_readout(game, replay, surface, shortcut)
  screen = GameScreen.allocate
  screen.instance_variable_set(:@game, game)
  SpeechOutput.reset
  screen.send(:activate_game_shortcut, shortcut, surface, replay:replay)
  SpeechOutput.calls.map(&:first).join("\n")
end

def assert_label_order(text, cards)
  offset = 0
  cards.each do |card|
    position = text.index(card.label, offset)
    assert(position, "Readout lost displayed card #{card.label}: #{text}")
    offset = position + card.label.length
  end
end

[
  ['cribbage', %w[KH AS 2C TH 2H], %w[AS 2H 2C TH KH], %w[AH 7S], %w[AH AS 2H 2C 7S TH KH]],
  ['scopa', %w[TC AH 2S 2H 7D], %w[AH 2H 2S 7D TC], %w[AS 6D], %w[AH AS 2H 2S 6D 7D TC]]
].each do |id, raw, initial, received, after|
  table = GameRoomTest::DealtCardTable.new(id)
  game, replay = table.game, table.replay
  table.state[:hands]['Alice'] = raw.dup
  surface = GameSurfaces.build(game.surface_spec(replay, 'Alice'))
  control = surface.fields.first
  assert(control.is_a?(ListBox), "#{id}: not a native card list")
  assert(surface.displayed_hand_cards('hand').map(&:id) == initial, "#{id}: wrong initial order")
  assert_label_order(game.shortcut_feature_data(:hand, replay, 'Alice')[:message], surface.displayed_hand_cards('hand'))
  table.state[:hands]['Alice'].concat(received)
  before = Marshal.dump(replay)
  driver = DuckChallengeNativeDriver.new
  form = driver.form(surface)
  form.extend(GameRoomLayout::ShortcutFormBehavior)
  updates = []
  surface.on_action { |action| updates << action }
  surface.update_spec(game.surface_spec(replay, 'Alice'))
  assert(surface.fields.first.equal?(control), "#{id}: receiving cards rebuilt the control")
  assert(surface.displayed_hand_cards('hand').map(&:id) == after, "#{id}: received cards stayed at the bottom")
  assert(surface.displayed_hand_cards('hand')[control.index].id == received.last, "#{id}: last received card lost focus")
  shortcut = game.game_shortcuts(replay, 'Alice').find { |item| item.key == 'h' && item.modifiers.empty? }
  bind = -> { GameRoomShortcutBindings.bind(form, surface.fields, [shortcut], consume: ->(*) {}) do |key|
    screen = GameScreen.allocate
    screen.instance_variable_set(:@game, game)
    screen.send(:activate_game_shortcut, key, surface, replay:replay)
  end }
  bind.call
  ['colour', 'number', 'number'].each do |mode|
    surface.handle_command('sort_cards', 'mode'=>mode, 'toggle'=>true)
    cards = surface.displayed_hand_cards('hand')
    index = control.index
    driver.frame(form)
    SpeechOutput.reset
    driver.frame(form, driver.tap('H'.ord))
    assert_label_order(SpeechOutput.calls.map(&:first).join("\n"), cards)
    assert(control.index == index && updates.empty?, "#{id}: reading/sorting changed selection or emitted a move")
    surface.update_spec(game.surface_spec(replay, 'Alice'))
    assert(surface.displayed_hand_cards('hand').map(&:id) == cards.map(&:id), "#{id}: refresh replaced manual sorting")
  end
  assert(!surface.handle_command('sort_cards', 'mode'=>'none'), "#{id}: removed order was accepted")
  assert(Marshal.dump(replay) == before, "#{id}: local order changed the reducer")
end

# Bridge retains its own descending ranks, dummy visibility and honor points.
table = GameRoomTest::BridgeTable.new
game = table.game
table.state[:hands]['Alice'] = %w[2S AH KS 3D QC AS 2H]
surface = GameSurfaces.build(game.surface_spec(table.replay, 'Alice'))
assert(surface.displayed_hand_cards('hand').map(&:id) == %w[AS KS 2S AH 2H 3D QC], 'Bridge lost its default order')
shortcut = game.game_shortcuts(table.replay, 'Alice').find { |item| item.key == 'h' && item.modifiers.empty? }
text = hand_readout(game, table.replay, surface, shortcut)
assert(text == game.shortcut_feature_data(:hand, table.replay, 'Alice')[:message] && text.include?('13 high card points'), 'Bridge default readout lost suit grouping/honor points')
surface.handle_command('sort_cards', 'mode'=>'colour', 'toggle'=>true)
assert(surface.displayed_hand_cards('hand').map(&:id) == %w[AS KS 2S AH 2H 3D QC], 'Manual suit sorting abandoned Bridge order')
surface.handle_command('sort_cards', 'mode'=>'number', 'toggle'=>true)
assert(surface.displayed_hand_cards('hand').map(&:id) == %w[AS AH KS QC 3D 2S 2H], "Bridge rank sorting was not applied: #{surface.displayed_hand_cards('hand').map(&:id).inspect}")
assert(shortcut.payload == {'hand_id'=>'hand'}, "Bridge lost its reminder hand metadata: #{shortcut.payload.inspect}")
text = hand_readout(game, table.replay, surface, shortcut)
assert_label_order(text, surface.displayed_hand_cards('hand'))
assert(text.include?('13 high card points'), 'Manual sorting removed honor points')
assert(surface.displayed_hand_cards('dummy').nil?, 'Hidden dummy was exposed')
table.calls('1H', 'P', 'P', 'P')
table.play_lowest_legal
surface = GameSurfaces.build(game.surface_spec(table.replay, 'Alice'))
dummy = surface.displayed_hand_cards('dummy')
assert(dummy && !dummy.empty?, 'Public dummy missing from actual view')
surface.handle_command('sort_cards', 'mode'=>'number')
shortcut = game.game_shortcuts(table.replay, 'Alice').find { |item| item.key == 'd' && item.modifiers.empty? }
assert_label_order(hand_readout(game, table.replay, surface, shortcut), surface.displayed_hand_cards('dummy'))

# A real blackjack replay keeps its dealt sequence, then appends a hit. H
# retains the total instead of being replaced by the generic card reminder.
game = BlackjackChecksSupport::FixedDeck.new
game.first_cards = %w[9S 2C 3H 7D 4C]
repo = BlackjackChecksSupport::Repository.new(['Alice'])
session = {'options'=>JSON.generate(game.default_options)}
events = [BlackjackChecksSupport.event(1, 'Alice', 'deal', "1|#{'0' * 32}")]
replay = game.replay(session, events, repo)
surface = GameSurfaces.build(game.surface_spec(replay, 'Alice'))
raw = replay.state[:hands]['Alice'].first[:cards]
assert(surface.displayed_hand_cards('hand').map(&:id) == raw && raw.length == 2, 'Blackjack sorted the initial deal')
events << BlackjackChecksSupport.event(2, 'Alice', 'hit')
replay = game.replay(session, events, repo)
surface.update_spec(game.surface_spec(replay, 'Alice'))
assert(surface.displayed_hand_cards('hand').map(&:id) == replay.state[:hands]['Alice'].first[:cards], 'Blackjack did not append a hit')
shortcut = game.game_shortcuts(replay, 'Alice').find { |item| item.key == 'h' && item.modifiers.empty? }
assert(hand_readout(game, replay, surface, shortcut) == game.shortcut_feature_data(:hand, replay, 'Alice')[:message], 'Blackjack lost its hand-total readout')

puts 'PASS native hand policies: Cribbage/Scopa values, received cards, real H/ordered speech, manual override/refresh, Bridge/dummy/honor points and Blackjack chronology; no live accounts or physical keyboard'
