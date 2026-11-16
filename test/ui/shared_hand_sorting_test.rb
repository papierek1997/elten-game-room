require_relative "../support/card_hand_cursor"
require_relative "../../games/rummy"
require_relative "../../games/biblios"
require_relative "../../lib/context_help"

def n_(one, many, count); count == 1 ? one : many; end
def sortable_spec(ids, packet: false, epoch: "one")
  cards = ids.map do |id|
    GameSurfaces::Card.new(id: id, label: id, value: id, sort_keys: {
      "colour" => [id[1], id[0]], "number" => [id[0], id[1]], "none" => [ids.index(id)] })
  end
  if packet
    GameSurfaces::PacketCardSpec.new(id: "hand", header: "Your hand", cards: cards, action_name: "play", allow_packet: true, hand_order: ids, hand_epoch: epoch)
  else
    GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(id: "hand", header: "Your hand", cards: cards, hand_order: ids, hand_epoch: epoch)])
  end
end

[false, true].each do |packet|
  ids = %w[9S 2H 9H 2Sa 2Sb]
  spec = sortable_spec(ids, packet: packet)
  surface = GameSurfaces.build(spec)
  field = surface.fields.first
  field.index = 2
  emitted = []
  surface.on_action { |action| emitted << action }
  $spoken_messages.clear
  assert(surface.handle_command("sort_cards", "mode" => "number", "toggle" => true, "ascending_message" => "Sorted"), "sort command not handled")
  assert(field.options == %w[2H 2Sa 2Sb 9H 9S], "rank/suit order #{packet}")
  assert(field.options[field.index] == "9H" && $spoken_messages == ["Sorted"], "sorting lost card or reread hand")
  surface.handle_command("sort_cards", "mode" => "number", "toggle" => true)
  assert(field.options == %w[9S 9H 2Sb 2Sa 2H], "reverse rank #{packet}")
  snapshot = surface.state
  surface = GameSurfaces.build(spec, state: snapshot)
  assert(surface.fields.first.options == field.options, "sort lost across reconstruction")
  surface.handle_command("sort_cards", "mode" => "none")
  assert(surface.fields.first.options == ids, "acquisition order #{packet}")
  surface.handle_command("sort_cards", "mode" => "colour", "toggle" => true)
  assert(surface.fields.first.options == %w[2H 9H 2Sa 2Sb 9S], "suit/rank order #{packet}")
  surface.update_spec(sortable_spec(ids + %w[3S 1H], packet: packet))
  field = surface.fields.first
  assert(field.options[field.index] == "1H" && surface.take_cursor_announcement(0) == "1H", "sorted multi-draw did not focus last new card")
  assert(field.options.first == "1H", "sorting did not apply to new cards")
  assert(emitted.empty?, "sorting sent a game action")
end

# Preparation order is independent of view order, including duplicate ranks.
surface = GameSurfaces.build(sortable_spec(%w[9S 2H 9H], packet: true))
surface.send(:toggle_card, surface.instance_variable_get(:@cards)[2])
surface.send(:toggle_card, surface.instance_variable_get(:@cards)[0])
surface.handle_command("sort_cards", "mode" => "number", "toggle" => true)
assert(surface.state["selected_ids"] == %w[9H 9S], "packet selection reordered")
surface.update_spec(sortable_spec(%w[9S 2H 9H], packet: true))
assert(surface.state["selected_ids"] == %w[9H 9S], "refresh cleared sorted packet")
restored = GameSurfaces.build(sortable_spec(%w[9S 2H 9H], packet: true), state: surface.state)
assert(restored.state["selected_ids"] == %w[9H 9S], "reconstruction cleared sorted packet")
actions = []
restored.on_action { |action| actions << action }
restored.fields.first.index = restored.fields.first.options.index { |label| label.start_with?("9S") }
restored.fields.first.trigger(:select, [restored.fields.first.index])
assert(JSON.parse(actions.first.payload["cards"]) == %w[9H 9S], "packet submission changed order")

# Surface-specific help is present exactly once and survives replacing the
# game's F1 tips. Poker gets exchange wording, not Makao packet wording.
field = surface.fields.first
3.times { GameRoomContextHelp.replace([field], ["Press P for packet."], source: :game) }
assert(field.get_tips.count { |tip| tip.include?("Shift+Enter") } == 1, "missing/duplicate packet help")
no_packet = sortable_spec(%w[AS], packet: true)
no_packet.allow_packet = false
surface.update_spec(no_packet)
assert(field.get_tips.none? { |tip| tip.include?("Shift+Enter") }, "inactive packet help remains")

types = [GameRoomGames::Uno, GameRoomGames::Makao, GameRoomGames::NinetyNine,
  GameRoomGames::Spades, GameRoomGames::Tysiac, GameRoomGames::Poker, GameRoomGames::Rummy]
types.each do |type|
  game = type.new
  args = [%w[Alice Bob Carol], game.default_options]
  args << Struct.new(:unit_ids).new(args.first) if game.id == "spades"
  state = game.send(:initial_state, *args)
  hand = case game.id
  when "uno" then %w[R5a G1a B3a Y2a]
  when "ninety_nine" then %w[0AS 0JS 0KH 0TD]
  else %w[AS JS KH TD]
  end
  state.update(hands: { "Alice" => hand, "Bob" => [], "Carol" => [] }, current_player: "Alice",
    phase: game.id == "poker" ? :exchange : :playing)
  state[:discard] = ["Y4a"] if game.id == "uno"
  view = GameRoomGames::Replay.new(players: state[:players], current_player: "Alice", state: state, history: [], accepted_events: [])
  serialized = Marshal.dump(state)
  shortcuts = game.game_shortcuts(view, "Alice")
  keys = shortcuts.map { |item| [item.key, item.modifiers] }
  assert(keys.uniq == keys, "duplicate shortcut in #{game.id}")
  surface = GameSurfaces.build(game.surface_spec(view, "Alice"))
  if %w[spades tysiac].include?(game.id)
    hand_ids = -> { surface.instance_variable_get(:@cards).fetch("hand").map(&:id) }
    original = hand_ids.call
    assert(original == %w[KH JS AS TD], "existing default hand order changed in #{game.id}")
    surface.handle_command("sort_cards", "mode" => "colour", "toggle" => true)
    assert(hand_ids.call == original.reverse, "first suit sort did not reverse the active default in #{game.id}")
    surface.handle_command("sort_cards", "mode" => "colour", "toggle" => true)
    assert(hand_ids.call == original, "second suit sort did not restore ascending order in #{game.id}")
    surface.handle_command("sort_cards", "mode" => "number", "toggle" => true)
    assert(hand_ids.call == %w[TD JS KH AS], "rank sort incorrectly used card points in #{game.id}")
    surface.handle_command("navigate_playable_card", "hand_id" => "hand", "card_ids" => %w[AS JS KH TD], "direction" => 1)
    selected = surface.state.fetch("zones").fetch("hand")
    assert(hand_ids.call[selected] == "AS", "playable navigation did not follow sorted hand in #{game.id}")
    assert(!surface.handle_command("sort_cards", "mode" => "none"), "removed receipt-order command was accepted in #{game.id}")
  end
  %w[c h].each do |key|
    shortcut = shortcuts.find { |item| item.key == key && item.modifiers == [:shift] }
    assert(shortcut && surface.handle_command("sort_cards", shortcut.payload), "unhandled Shift+#{key} in #{game.id}")
  end
  assert(shortcuts.none? { |s| s.key == 'm' && s.modifiers == [:shift] }, "#{game.id}: removed order still has a shortcut")
  assert(Marshal.dump(state) == serialized, "sorting modified game state #{game.id}")
  if game.id == "uno"
    assert(shortcuts.none? { |s| s.key == "d" && s.modifiers == [:shift] }, "removed UNO Shift+D remains")
    state[:colour_choice_player], state[:colour_choice_card] = "Alice", "WF1"
    assert(game.game_shortcuts(view, "Alice").none? { |s| s.action_name == "sort_cards" }, "colour picker shows unavailable sorting")
  elsif game.id == "rummy"
    assert(shortcuts.any? { |s| s.key == "d" && s.modifiers == [:shift] && s.action_name == "meld_discard_pile" }, "Rummy Shift+D overwritten")
  elsif game.id == "poker"
    assert(surface.fields.any? { |f| f.respond_to?(:get_tips) && f.get_tips.any? { |s| s.include?("for exchange") } }, "Poker help uses packet wording")
  end
end
assert(!GameRoomGames::Biblios.new.hand_sorting_available?(nil, nil), "Biblios Shift+C overwritten")
assert(!GameRoomGames::Base.new.hand_sorting_available?(nil, nil), "non-card games received hand sorting")
puts "PASS shared hand sorting: seven games, both directions, received order, IDs/cursor, duplicate cards, packets, local-only commands and F1"
