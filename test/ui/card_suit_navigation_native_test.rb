require_relative "../support/duck_challenge_native"
require_relative "../../games/base"
require_relative "../../games/rummy"

GameRoomLocalization.boot(settings: {"interface_language" => "en"}, host_language: "en")

def suit_cards(ids)
  game = GameRoomGames::Base.new
  ids.each_with_index.map do |id, index|
    GameSurfaces::Card.new(id: id, value: id, label: "card #{id}",
      navigation_group: game.__send__(:standard_hand_navigation_group, rank: id[0], suit: id[1]),
      sort_keys: game.__send__(:standard_hand_sort_keys, rank: id[0], suit: id[1], position: index))
  end
end

def suit_hand(ids = %w[2H KH 2S AS 3D 4C], commands: false, marked: true)
  GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(
    id: "hand", header: "Full hand", cards: suit_cards(ids),
    hand_order: marked ? ids.dup : nil, hand_epoch: "deal-1",
    commands: commands ? %w[draw pass].map { |id| GameSurfaces::Command.new(id: id, label: id) } : [])])
end

def native_hand(spec)
  driver = DuckChallengeNativeDriver.new
  surface = GameSurfaces.build(spec)
  form = driver.form(surface)
  events = []
  surface.on_action { |action| events << action.to_h }
  [driver, surface, form, surface.fields.first, events]
end

def arrow(driver, form, key, modifiers: [])
  # ELTEN suppresses the same key in adjacent snapshots, even with a complete
  # tap's press/release pair. Model a separate released frame between taps.
  driver.frame(form)
  SpeechOutput.reset
  driver.frame(form, driver.tap(key, modifiers: modifiers))
  SpeechOutput.calls.map(&:first).join("\n")
end

driver, surface, form, field, events = native_hand(suit_hand)
labels = field.options.dup
%i[expand collapse selectexpand].each { |event| field.on(event) { raise "Arrow activated #{event}" } }
speech = arrow(driver, form, 0x27)
assert(field.index == 2 && speech.include?("Spades") && speech.include?("card 2S"), "Right did not immediately select and announce Spades")
assert(SpeechOutput.calls.count { |entry| entry[0].include?("card 2S") } == 1, "Suit jump repeated the selected card")
assert(!speech.include?("Full hand") && field.options == labels && field.header == "Full hand" && events.empty?, "Suit jump rebuilt/activated/read the whole hand")
arrow(driver, form, 0x28)
assert(field.index == 3, "Down did not reach the next displayed card")
speech = arrow(driver, form, 0x28)
assert(field.index == 4, "Down stopped at the selected suit instead of reaching Diamonds")
assert(speech.include?("card 3D") && !speech.include?("Full hand") && events.empty?, "Vertical navigation repeated the hand caption or submitted a card")
assert(SpeechOutput.calls.count { |entry| entry[0].include?("card 3D") } == 1, "Vertical navigation repeated the selected card")
arrow(driver, form, 0x26)
assert(field.index == 3, "Up did not cross back from Diamonds to Spades")
arrow(driver, form, 0x26)
assert(field.index == 2, "Up did not reach the previous displayed Spade")
arrow(driver, form, 0x26)
assert(field.index == 1, "Up stopped at the selected suit instead of reaching Hearts")
arrow(driver, form, 0x28)
arrow(driver, form, 0x27)
assert(field.index == 4, "Right did not skip straight to Diamonds")
speech = arrow(driver, form, 0x27)
assert(field.index == 5, "Right did not reach Clubs: index=#{field.index}, speech=#{speech.inspect}")
arrow(driver, form, 0x27)
assert(field.index == 0, "Right did not cycle to Hearts")
arrow(driver, form, 0x25)
assert(field.index == 5, "Left did not cycle to Clubs")
driver.frame(form, driver.tap(0x0d))
assert(events.size == 1 && events.first["card_id"] == "4C", "Enter did not use the actual selected physical card")

# Arrow plus Enter in one native frame selects the jumped-to card exactly
# once, in the same order as native vertical movement followed by selection.
driver, surface, form, field, events = native_hand(suit_hand)
driver.frame(form, driver.tap(0x27) + driver.tap(0x0d))
assert(field.index == 2 && events.one? && events.first["card_id"] == "2S", "Arrow/Enter activated the pre-jump card or selected twice")

# Actual held-key repeat, separated by a no-repeat held frame as in the host.
driver, surface, form, field, events = native_hand(suit_hand)
driver.frame(form, [[0x27, true, driver.raw([0x27])]], held: [0x27])
assert(field.index == 2, "Held arrow lost its initial jump")
driver.frame(form, [], held: [0x27])
assert(field.index == 2, "Holding the key moved without a native repeat")
driver.frame(form, [[0x27, :repeat]], held: [0x27])
assert(field.index == 4 && events.empty?, "Native held-key repeat did not jump exactly once")

# Holding Down keeps the native repeat behavior across suit boundaries.
driver, surface, form, field, events = native_hand(suit_hand)
field.index = 1
driver.frame(form, [[0x28, true, driver.raw([0x28])]], held: [0x28])
assert(field.index == 2, "Held Down stopped at the suit boundary")
driver.frame(form, [], held: [0x28])
assert(field.index == 2, "Holding Down moved without a native repeat")
driver.frame(form, [[0x28, :repeat]], held: [0x28])
assert(field.index == 3 && events.empty?, "Native Down repeat was lost or emitted a move")

# Group navigation neither sorts nor filters an interleaved acquisition/rank
# order. Vertical movement visits every displayed card, then bottom commands.
driver, surface, form, field, events = native_hand(suit_hand(%w[2H 2S KH AS 3D 4C], commands: true))
labels = field.options.dup
(1..7).each do |index|
  arrow(driver, form, 0x28)
  assert(field.index == index && field.options == labels, "Down skipped displayed card/command #{index}")
end
arrow(driver, form, 0x26)
driver.frame(form, driver.tap(0x0d))
assert(events.last["kind"] == "command" && events.last["action"] == "draw", "Command was treated as a card")
arrow(driver, form, 0x26)
assert(field.index == 5, "Up from commands did not return to the last displayed card")
arrow(driver, form, 0x27)
assert(field.index == 0 && field.options == labels, "Right from Clubs did not cycle to Hearts")
arrow(driver, form, 0x27)
assert(field.index == 1 && field.options == labels, "Right filtered or sorted the interleaved hand")
surface.update_spec(suit_hand(%w[2H 2S KH AS 3D 4C], commands: true))
SpeechOutput.reset
driver.frame(form)
assert(field.index == 1 && SpeechOutput.calls.empty?, "Unchanged refresh moved/spoke the cursor")
surface.handle_command("sort_cards", "mode" => "number")
arrow(driver, form, 0x28)
assert(field.options[field.index] == "card 3D", "Down did not follow the new displayed order after sorting")

# Press snapshots, not end-of-frame modifier state. Modified arrows keep the
# native numbering/reading/selection commands and never jump a suit.
driver, surface, form, field, = native_hand(suit_hand)
[0x10, 0x11, 0x12, 0x2d].each do |modifier|
  field.index = 0
  arrow(driver, form, 0x27, modifiers: [modifier])
  assert(field.index == 0, "Modified arrow jumped a suit (#{modifier})")
end
driver.frame(form)
driver.frame(form, [[0x27, true, driver.raw([0x27])], [0x27, false], [0x10, true]], held: [0x10])
assert(field.index == 2, "Shift pressed after Right retroactively prevented navigation")
driver.frame(form)
driver.frame(form, [[0x27, :repeat]], held: [0x27])
assert(field.index == 4, "Native arrow repeat was lost")

# Native text editing remains native; plain arrows on an unrelated list do not
# acquire suit semantics merely because it happens to use CardTable.
driver, surface, form, field, = native_hand(suit_hand(marked: false))
arrow(driver, form, 0x28)
assert(field.index == 1 && field.get_tips.none? { |tip| tip.include?("jump between suits") }, "Unmarked list acquired hand navigation")
form.index = form.fields.length - 1
form.focus
chat = form.fields.last
chat.index = chat.check = chat.text.length
arrow(driver, form, 0x25)
assert(chat.index == chat.text.length - 1, "Hand navigation consumed an editor's Left key")

# Cards with choices still use ordinary Enter/choice navigation. A choice is
# not a hand; leaving it restores suit movement without new event handlers.
spec = suit_hand
spec.zones.first.cards[2].choices = %w[first second].map { |id| GameSurfaces::CardChoice.new(id: id, label: id, value: id) }
driver, surface, form, field, events = native_hand(spec)
arrow(driver, form, 0x27)
driver.frame(form, driver.tap(0x0d))
assert(field.options == %w[first second] && events.empty?, "Enter did not open the existing card choice")
arrow(driver, form, 0x28)
assert(field.index == 1, "Choice list inherited suit boundaries")
driver.frame(form, driver.tap(0x0d))
assert(events.one? && events.first["card_id"] == "2S" && events.first["choice_id"] == "second", "Choice did not preserve its card/action identity")
arrow(driver, form, 0x27)
assert(field.options[field.index] == "card 3D", "Suit movement did not return after closing a choice")

# Packet marking must survive jumps. No intermediate write, duplicate card or
# replacement list is permitted merely to navigate to another suit.
ids = %w[2H KH 2S AS 3D]
spec = GameSurfaces::PacketCardSpec.new(id: "hand", header: "Packet", cards: suit_cards(ids),
  hand_order: ids, hand_epoch: "deal-1", allow_packet: true, action_name: "play")
driver, surface, form, field, events = native_hand(spec)
driver.frame(form, driver.tap(0x0d, modifiers: [0x10]))
arrow(driver, form, 0x27)
driver.frame(form, driver.tap(0x0d, modifiers: [0x10]))
assert(surface.state["selected_ids"] == %w[2H 2S] && events.empty?, "Navigation lost or submitted a prepared packet")
arrow(driver, form, 0x28)
assert(field.index == 3, "Packet hand did not use the shared vertical navigation")
arrow(driver, form, 0x28)
assert(field.index == 4 && surface.state["selected_ids"] == %w[2H 2S] && events.empty?, "Packet Down stopped at a suit boundary or changed the prepared packet")

# Rummy's hand shares arrows during a draft, but public-meld inspection in
# that same native control must immediately regain ordinary list navigation.
game = GameRoomGames::Rummy.new
state = game.initial_state(%w[Alice Bob], game.default_options)
state.update(phase: :playing, round: 1, turn: 1, current_player: "Alice", drawn: true,
  hands: {"Alice" => %w[2S0 3S0 4H0], "Bob" => %w[KC0]},
  melds: [GameRoomRummyRules.validate(%w[TS1 JS1 QS1]).merge(id: 1),
          GameRoomRummyRules.validate(%w[2C1 3C1 4C1]).merge(id: 2)])
replay = GameRoomGames::Replay.new(players: state[:players], state: state, current_player: "Alice", history: [])
driver, surface, form, field, events = native_hand(game.surface_spec(replay, "Alice"))
surface.handle_command("meld_new")
driver.frame(form, driver.tap(0x0d))
arrow(driver, form, 0x27)
assert(field.options[field.index].include?("4 of hearts") && surface.state["meld_selection"] == ["2S0"], "Suit movement changed the prepared meld")
surface.handle_command("meld_table")
assert(field.get_tips.none? { |tip| tip.include?("jump between suits") }, "Public meld inspection still advertises suit arrows")
arrow(driver, form, 0x28)
assert(field.index == 1 && events.empty?, "Public meld list kept hand suit boundaries")
surface.cancel_pending_action!
surface.update_spec(game.surface_spec(replay, "Alice"))
arrow(driver, form, 0x25)
assert(field.options[field.index].include?("2 of spades") && events.empty?, "Closing inspection did not restore suit navigation")

# Quiet-refresh suppression must never swallow a deliberate navigation press.
field.suppress_next_focus!
speech = arrow(driver, form, 0x27)
assert(speech.include?("Hearts") && speech.include?("4 of hearts"), "Quiet refresh silenced the next deliberate suit jump")
field.suppress_next_focus!
speech = arrow(driver, form, 0x26)
assert(speech.include?("3 of spades") && !speech.include?("Full hand"), "Quiet refresh silenced native vertical navigation or repeated the hand caption")

# Empty, single-suit and incomplete metadata cannot create an inaccessible
# option or invent a second group.
driver, surface, form, field, events = native_hand(suit_hand(%w[2H KH]))
arrow(driver, form, 0x28)
speech = arrow(driver, form, 0x27)
assert(field.index == 0 && speech.include?("Hearts"), "Single-suit hand did not jump to its first card")
driver, surface, form, field, = native_hand(suit_hand([]))
arrow(driver, form, 0x27)
assert(field.options.empty?, "Empty-hand navigation invented a card")
spec = suit_hand
spec.zones.first.cards[1].navigation_group = nil
driver, surface, form, field, = native_hand(spec)
arrow(driver, form, 0x28)
assert(field.index == 1, "Incomplete metadata stranded an ungrouped card")

# Group discovery is lazy: an idle hand performs no repeated source scan and
# never resolves account storage, sorts the hand or makes a network request.
reads = 0
source = field.instance_variable_get(:@card_navigation_source)
field.card_navigation_source = -> { reads += 1; source.call }
20.times { driver.frame(form) }
assert(reads.zero?, "Idle input frames repeatedly scanned the hand")

puts "PASS native card-suit navigation: immediate horizontal jumps, native whole-hand vertical navigation, one announcement, commands, sorting, refresh, modifiers, repeats, editors, choices, packets, melds and edge cases"
