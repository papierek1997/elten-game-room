require_relative "../../support/ui"
require_relative "../../../lib/game_surfaces"
require_relative "../../../games/uno"

def assert(value, message)
  raise message unless value
end

game = GameRoomGames::Uno.new
state = game.send(:initial_state, %w[Alice Bob], game.default_options)
deck = game.send(:classic_deck).dup
hand = deck.reverse
state.update(phase: :playing, current_player: "Alice", colour: "R", discard: [],
  hands: { "Alice" => hand.dup, "Bob" => [] })
view = GameRoomGames::Replay.new(players: state[:players], current_player: "Alice",
  history: [], accepted_events: [], state: state)
spec = game.surface_spec(view, "Alice")
shortcuts = game.custom_game_shortcuts(view, "Alice")

# Independent expected order, including duplicate cards, not the game's sort keys.
colours = %w[Y R B G]
faces = %w[0 1 2 3 4 5 6 7 8 9 V S D]
copies = lambda { |colour, face| face == "0" ? ["#{colour}0a"] : %w[a b].map { |copy| "#{colour}#{face}#{copy}" } }
wilds = %w[NW0 NW1 NW2 NW3 NF0 NF1 NF2 NF3]
by_colour = colours.flat_map { |colour| faces.flat_map { |face| copies.call(colour, face) } } + wilds
by_number = faces.flat_map { |face| colours.flat_map { |colour| copies.call(colour, face) } } + wilds

[["c", by_colour], ["h", by_number]].each do |key, expected|
  surface = GameSurfaces::CardTable.new(spec)
  surface.fields.first.index = 7
  focused_label = surface.fields.first.options[7]
  shortcut = shortcuts.find { |item| item.key == key && item.modifiers == [:shift] }
  3.times do |press|
    assert(surface.handle_command("sort_cards", shortcut.payload), "Shift+#{key} refused")
    descending = key == 'c' ? press.even? : press.odd?
    order = descending ? expected.reverse : expected
    labels = order.map { |card| game.send(:uno_label, card, state) }
    assert(surface.fields.first.options == labels, "Wrong Shift+#{key} order on press #{press + 1}")
    assert(surface.fields.first.options[surface.fields.first.index] == focused_label, "Focus changed after sorting")
    surface = GameSurfaces::CardTable.new(spec, state: surface.state)
    assert(surface.fields.first.options == labels, "Sort order lost on refresh")
  end
  assert(shortcuts.none? { |item| %w[d m].include?(item.key) && item.modifiers == [:shift] }, 'UNO retains the removed acquisition shortcut')
  assert(!surface.handle_command('sort_cards', 'mode'=>'none'), 'UNO accepts the removed acquisition order')
end

assert(state[:hands]["Alice"] == hand, "Sorting changed the actual hand")
assert(game.send(:classic_deck) == deck, "Sorting changed the deck")
assert(GameRoomGames::Uno::COLORS == %w[R Y G B], "Deck colour order changed")
assert(game.send(:available_colors, state) == %w[R Y G B], "Colour choice order changed")
assert(game.send(:all_colors).last(4) == %w[O P T U], "Dark colour order changed")

# All combinations, not just a super option that is inactive without ordinary
# interceptions. Use all real deck families, including dark Flip faces.
%w[classic no_mercy flip].each do |deck_id|
  [false, true].repeated_permutation(3) do |straights, interceptions, super_interceptions|
    options = game.default_options.merge('deck'=>deck_id, 'straights'=>straights,
      'interceptions'=>interceptions, 'super_interceptions'=>super_interceptions)
    position = game.send(:initial_state, %w[Alice Bob], options)
    hand = game.send(:uno_deck, options).reverse
    position.update(phase: :playing, current_player:'Alice', hands:{'Alice'=>hand, 'Bob'=>[]}, discard:[])
    replay = GameRoomGames::Replay.new(players: position[:players], state:position, current_player:'Alice', history:[], accepted_events:[])
    mode = straights || (interceptions && super_interceptions) ? 'number' : 'colour'
    initial = game.surface_spec(replay, 'Alice')
    assert(initial.default_sort == mode, "#{deck_id}/#{options}: wrong default sort")
    assert(initial.zones.first.hand_order == hand, 'Variant sorting changed the physical receipt order')
    face_order = %w[0 1 2 3 4 5 6 7 8 9 V S I D X H E A L W F R T C B]
    colour_order = %w[Y R B G O P T U]
    expected = hand.sort_by do |card|
      face = face_order.index(game.send(:card_face, card))
      colour = colour_order.index(game.send(:card_color, card)) || 99
      mode == 'number' ? [face, colour, card] : [colour, face, card]
    end
    assert(initial.zones.first.cards.map(&:id) == expected, "#{deck_id}: variant surface and declaration disagree")
    surface = GameSurfaces.build(initial)
    original = Marshal.dump(position)
    %w[colour number].each do |manual|
      surface.handle_command('sort_cards', 'mode'=>manual, 'toggle'=>true)
      before = surface.displayed_hand_cards('hand').map(&:id)
      surface.update_spec(game.surface_spec(replay, 'Alice'))
      assert(surface.displayed_hand_cards('hand').map(&:id) == before, 'Variant default overwrote explicit sorting')
    end
    assert(!surface.handle_command('sort_cards', 'mode'=>'none'), 'Variant accepted a disabled mode')
    assert(Marshal.dump(position) == original, 'Presentation changed a variant replay')
  end
end
puts "PASS UNO colour/value order, variant defaults for all three decks, both directions, refresh, focus and deal order"
