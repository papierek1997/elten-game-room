require_relative '../support/card_hand_cursor'
require_relative '../support/dealt_card_games'

def own_hand_spec(spec)
  case spec
  when GameSurfaces::CompositeSpec
    spec.parts.each do |part|
      hand = own_hand_spec(part.surface)
      return hand if hand
    end
    nil
  when GameSurfaces::PacketCardSpec then spec
  when GameSurfaces::CardTableSpec
    spec if spec.zones.any? { |zone| zone.id == 'hand' }
  end
end

def displayed_ids(surface)
  cards = surface.instance_variable_get(:@cards)
  (cards.is_a?(Hash) ? cards.fetch('hand') : cards).map(&:id)
end

cases = []
%w[hearts belote jass cribbage bouillabaisse french_tarot].each do |id|
  game = GameRoomGames::CATALOG.build(id)
  table = GameRoomTest::DealtCardTable.new(id, count:game.minimum_players)
  table.state[:hands]['Alice'] = %w[AH 9H JS KH QD AC]
  cases << [table.game, table.replay, table.state[:hands]['Alice'], 'TH', '7S']
end
%w[tysiac three_five_eight spades ninety_nine makao poker uno].each do |id|
  game = GameRoomGames::CATALOG.build(id)
  players = %w[Alice Bob Carol]
  args = [players, game.default_options]
  args << Struct.new(:unit_ids).new(players) if id == 'spades'
  state = game.send(:initial_state, *args)
  raw = id == 'uno' ? %w[R5a G1a B3a Y2a] : %w[AH 9H JS KH QD AC]
  raw = raw.map { |card| "0#{card}" } if id == 'ninety_nine'
  state.update(hands:players.to_h { |player| [player, player == 'Alice' ? raw : []] },
    current_player:'Alice', phase:id == 'poker' ? :exchange : :playing)
  state[:discard] = ['Y4a'] if id == 'uno'
  replay = GameRoomGames::Replay.new(players:players, state:state, current_player:'Alice', history:[], accepted_events:[])
  additions = id == 'uno' ? %w[R2a Y3a] : (id == 'ninety_nine' ? %w[0TH 07S] : %w[TH 7S])
  cases << [game, replay, raw, *additions]
end

cases.each do |game, replay, raw, first, second|
  spec = -> { own_hand_spec(game.surface_spec(replay, 'Alice')) }
  surface = GameSurfaces.build(spec.call)
  controls = surface.fields.dup
  initial = displayed_ids(surface)
  raw.concat([first, second])
  before = Marshal.dump(replay)
  current = spec.call
  cards = current.is_a?(GameSurfaces::PacketCardSpec) ? current.cards : current.zones.first.cards
  mode = current.default_sort
  expected = cards.sort_by { |card| [*card.sort_keys.fetch(mode), card.id] }.map(&:id)
  surface.update_spec(current)
  assert(displayed_ids(surface) == expected, "#{game.id}: received cards left the declared default sort")
  index = surface.fields.first.index
  assert(displayed_ids(surface)[index] == second, "#{game.id}: did not select the last received physical card")
  message = cards.find { |card| card.id == second }.label
  assert(surface.take_cursor_announcement(0) == message, "#{game.id}: wrong received-card speech")
  assert(surface.take_cursor_announcement(0).nil?, "#{game.id}: repeated received-card speech")
  assert(surface.fields == controls, "#{game.id}: sorting rebuilt native controls")
  restored = GameSurfaces.build(spec.call, state:surface.state)
  assert(displayed_ids(restored) == expected, "#{game.id}: reconstruction lost the default sort")
  assert(restored.take_cursor_announcement(0).nil?, "#{game.id}: reconstruction spoke a stale receipt")

  surface.handle_command('sort_cards', 'mode'=>'colour', 'toggle'=>true)
  by_suit = cards.sort_by { |card| [*card.sort_keys.fetch('colour'), card.id] }.map(&:id)
  assert(displayed_ids(surface) == by_suit, "#{game.id}: first explicit sort reversed the default")
  surface.handle_command('sort_cards', 'mode'=>'colour', 'toggle'=>true)
  surface.update_spec(spec.call)
  assert(displayed_ids(surface) == by_suit.reverse, "#{game.id}: refresh lost descending sorting")
  surface.handle_command('sort_cards', 'mode'=>'number', 'toggle'=>true)
  numeric = cards.sort_by { |card| [*card.sort_keys.fetch('number'), card.id] }.map(&:id)
  surface.update_spec(spec.call)
  assert(displayed_ids(surface) == numeric, "#{game.id}: the default overrode rank sorting")
  assert(!surface.handle_command('sort_cards', 'mode'=>'none'), "#{game.id}: removed acquisition mode is still accepted")
  surface.update_spec(spec.call)
  assert(displayed_ids(surface) == numeric, "#{game.id}: a refused mode changed the hand")
  assert(Marshal.dump(replay) == before, "#{game.id}: display sorting changed the authoritative replay")
  assert(initial.length + 2 == raw.length, "#{game.id}: the fixture did not receive two cards")
end

# Hearts/default H must also agree with the established Spades order at the
# first deal, not merely after the player explicitly chooses a sort.
spades = GameRoomGames::Spades.new
cases.select { |game, *_| %w[hearts belote jass bouillabaisse].include?(game.id) }.each do |game, replay, raw, *_|
  expected = raw.sort_by { |card| spades.send(:card_sort_key, card) }
  assert(own_hand_spec(game.surface_spec(replay, 'Alice')).zones.first.cards.map(&:id) == expected,
    "#{game.id}: initial default differs from Spades")
  assert(game.shortcut_feature_data(:hand, replay, 'Alice')[:message] == "Your hand: #{game.send(:cards_text, expected)}.",
    "#{game.id}: H disagrees with the displayed default")
end
scopa = GameRoomTest::DealtCardTable.new('scopa')
surface = GameSurfaces.build(scopa.game.surface_spec(scopa.replay, 'Alice'))
raw = scopa.state[:hands]['Alice']
raw << (GameRoomGames::Scopa::DECK - raw).first
surface.update_spec(scopa.game.surface_spec(scopa.replay, 'Alice'))
expected = raw.sort_by { |card| [GameRoomGames::Scopa.card_value(card), %w[H S D C].index(card[1])] }
assert(displayed_ids(surface) == expected, 'Scopa did not keep its value-sorted default after receiving a card')
puts "PASS default sorting: #{cases.length} real games, initial/received cards, stable controls/IDs/speech, reconstruction, manual overrides/H and Scopa values"
