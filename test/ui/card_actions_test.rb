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

# A passive hand can use Enter for a game-owned decision without another
# action list or a form-wide Enter shortcut. Other card selections stay native.
spec = hand_spec(%w[first second])
zone = spec.zones.first
zone.activation_action = GameSurfaces::Action.new(kind:'command', name:'stand', payload:{'round'=>1}, source:'hand')
zone.activation_tip = 'Enter, keep your total.'
surface = GameSurfaces.build(spec)
field = surface.fields.first
emitted = []
surface.on_action { |action| emitted << action }
3.times { assert(field.get_tips.count { |tip| tip == zone.activation_tip } == 1, 'Activation help accumulated or disappeared') }
field.trigger(:select, [1])
assert(emitted.length == 1 && emitted.first.to_h == {'kind'=>'command','action'=>'stand','round'=>1,'source'=>'hand'},
  'Hand activation lost its payload/source or also emitted card selection')
surface.action_guard = -> { false }
field.trigger(:select, [0])
assert(emitted.length == 1, 'Hand activation bypassed the shared action guard')
surface.action_guard = nil
surface.update_spec(hand_spec(%w[first second]))
assert(surface.fields.first.equal?(field) && !field.get_tips.include?(zone.activation_tip), 'Removing activation rebuilt the field or left stale help')
field.trigger(:select, [0])
assert(emitted.length == 2 && emitted.last['kind'] == 'card' && emitted.last['card_id'] == 'first',
  'Removing activation did not restore ordinary card selection')
choice_spec = hand_spec(%w[first second], choices:true)
choice_spec.zones.first.activation_action = zone.activation_action
choice_spec.zones.first.activation_tip = zone.activation_tip
choice_spec.zones.first.commands = [GameSurfaces::Command.new(id:'other', label:'Other command')]
choice_surface = GameSurfaces.build(choice_spec)
chosen = []
choice_surface.on_action { |action| chosen << action }
choice_field = choice_surface.fields.first
choice_field.trigger(:select, [0])
assert(choice_surface.cancel_pending_action? && !choice_field.get_tips.include?(zone.activation_tip),
  'Default activation replaced an explicit card choice or left misleading help')
choice_field.trigger(:select, [0])
assert(chosen.map(&:name) == ['select'] && choice_field.get_tips.include?(zone.activation_tip),
  'Finishing a choice used the default action or lost its restored help')
choice_field.trigger(:select, [2])
assert(chosen.map(&:name) == %w[select other], 'Default activation replaced an appended command')
zone.activation_action = {'kind'=>'command','action'=>'stand'}
begin
  GameSurfaces.build(spec)
  raise 'Malformed hand activation was accepted'
rescue ArgumentError => error
  assert(error.message == 'card zone activation must be a surface action', 'Unexpected activation validation failure')
end
puts "PASS shared card actions: optional confirmation, sorted physical IDs, single emission, cancellation, guards, pending choices, program ownership and field-scoped activation/help"
