require_relative "../support/card_hand_cursor"

surface = GameSurfaces.build(hand_spec(%w[first second], duplicate_labels: true))
emitted = []
surface.on_action { |action| emitted << action }
surface.fields.first.trigger(:select, [0])
assert(emitted.length == 1 && emitted.last["card_id"] == "first", "ordinary cards changed without confirmation metadata")

spec = hand_spec(%w[first second], duplicate_labels: true)
spec.zones.first.cards.each { |card| card.confirmation = "Confirm #{card.id}" }
surface = GameSurfaces.build(spec)
prompts = []
accepted = false
surface.define_singleton_method(:confirm_card_action) { |message| prompts << message; accepted }
emitted.clear
surface.on_action { |action| emitted << action }
surface.fields.first.index = 1
surface.fields.first.trigger(:select, [1])
assert(emitted.empty? && prompts == ["Confirm second"], "declined card confirmation emitted an action")
accepted = true
surface.fields.first.trigger(:select, [1])
assert(emitted.length == 1 && emitted.last["card_id"] == "second", "confirmed card lost its physical identity")

payload = { "hand_id" => "hand", "confirmation" => "Discard %{card}?", "shortcut" => "j",
  "actions" => %w[first second].to_h { |identifier| [identifier, { "kind" => "card", "action" => "discard", "card" => identifier }] } }
2.times { surface.handle_command("sort_cards", "mode" => "number", "toggle" => true) }
action = surface.handle_command("selected_card_action", payload)
assert(action.is_a?(GameSurfaces::Action) && action["card"] == "second" && action["action"] == "discard", "selected-card command lost sorted physical cursor")
assert(action.source == "shortcut:j" && prompts.last == "Discard same card?", "selected-card command lost its source or accessible label")
assert(emitted.length == 1, "selected-card command both returned and emitted an action")
accepted = false
assert(surface.handle_command("selected_card_action", payload) == true, "cancelled selected-card action was not consumed")
assert(emitted.length == 1, "cancelled selected-card command emitted an action")
assert(surface.handle_command("selected_card_action", payload.merge("hand_id" => "other")) == false, "command handled a different hand")

guard = true
surface.action_guard = -> { guard }
surface.define_singleton_method(:confirm_card_action) { |_message| guard = false; true }
assert(surface.handle_command("selected_card_action", payload) == true, "guard invalidation failed to consume the command")
surface.fields.first.trigger(:select, [0])
assert(emitted.length == 1, "post-dialog action guard was bypassed")

pending = GameSurfaces.build(hand_spec(%w[first second], choices: true))
pending.fields.first.trigger(:select, [0])
pending.define_singleton_method(:confirm_card_action) { |_message| raise "Confirmation opened during target choice" }
assert(pending.handle_command("selected_card_action", payload) == true, "pending target choice did not consume the shortcut")
assert(pending.cancel_pending_action?, "discard shortcut destroyed pending target choice")

program = Object.new
composite = GameSurfaces.build(GameSurfaces::CompositeSpec.new(parts: [
  GameSurfaces::SurfacePart.new(id: "cards", surface: hand_spec(%w[first second]))
]))
composite.program = program
assert(composite.reuse_candidates.first.program.equal?(program), "composite lost the native confirmation's owning program")
puts "PASS shared card actions: optional confirmation, sorted physical IDs, single emission, cancellation, guards, pending choices and program ownership"
