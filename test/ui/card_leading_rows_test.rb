require_relative '../support/ui'
require_relative '../../lib/game_surfaces'

def leading_spec(ids = %w[a b], rows: [GameSurfaces::CardListRow.new(id:'dealer', label:'Dealer card')], choices:false)
  cards = ids.each_with_index.map do |id, index|
    GameSurfaces::Card.new(id:id, label:id.upcase, value:id, sort_keys:{'colour'=>[id], 'none'=>[index]},
      choices:choices ? [GameSurfaces::CardChoice.new(id:'play', label:'Play', value:id)] : nil)
  end
  GameSurfaces::CardTableSpec.new(default_sort:'none', sort_modes:%w[colour none], zones:[
    GameSurfaces::CardZoneSpec.new(id:'hand', header:'Own hand', cards:cards, hand_order:ids,
      hand_epoch:'one', leading_rows:rows,
      commands:[GameSurfaces::Command.new(id:'draw', label:'Draw')])])
end

def assert(value, message)
  raise message unless value
end

spec = leading_spec
surface = GameSurfaces.build(spec)
field, actions = surface.fields.first, []
surface.on_action { |action| actions << action }
assert(field.options == ['Dealer card', 'A', 'B', 'Draw'] && field.index == 1, 'Leading row displaced the initial own card')
assert(surface.displayed_hand_cards('hand').map(&:id) == %w[a b], 'Leading information became a hand card')
field.trigger(:select, [0])
assert(actions.empty?, 'Informational row emitted a card action')
field.trigger(:select, [1])
assert(actions.last['card_id'] == 'a' && actions.last['index'] == 0, 'Card action contains a list-row offset')
field.trigger(:select, [3])
assert(actions.last.name == 'draw', 'Leading row displaced an appended command')
field.index = 0
remembered = surface.state
assert(remembered['selected_leading_rows'] == {'hand'=>'dealer'} && !remembered.key?('selected_commands'), 'Leading row acquired command state')
assert(remembered['hand_cursors']['hand']['selected_id'].nil?, 'Leading row selected the last physical card')
rebuilt = GameSurfaces.build(spec, state:remembered)
assert(rebuilt.fields.first.index == 0, 'Reconstruction lost the informational selection')
surface.handle_command('sort_cards', 'mode'=>'colour', 'toggle'=>true)
assert(field.index == 0 && field.options.first == 'Dealer card', 'Sorting moved the leading row or its cursor')
assert(surface.handle_command('selected_card_action', 'hand_id'=>'hand', 'actions'=>{'b'=>{'kind'=>'card','action'=>'discard'}}) == true && actions.length == 2,
  'A selected-card shortcut used the last physical card while inspecting the dealer')
updated = leading_spec(rows:[GameSurfaces::CardListRow.new(id:'extra', label:'Public info'), GameSurfaces::CardListRow.new(id:'dealer', label:'Updated dealer')])
surface.update_spec(updated)
assert(field.index == 1 && field.options[1] == 'Updated dealer' && surface.take_cursor_announcement.nil?, 'Updating leading rows moved focus or queued speech')
surface.update_spec(leading_spec(%w[a b c], rows:updated.zones.first.leading_rows))
assert(field.index == 4 && field.options[field.index] == 'C' && surface.take_cursor_announcement(0) == 'C', 'Drawing failed to select the new physical card')
surface.update_spec(leading_spec(%w[a b c], rows:[]))
assert(field.index == 2 && field.options[field.index] == 'C', 'Removing leading rows changed the selected card')

choice = GameSurfaces.build(leading_spec(choices:true))
choice_actions = []
choice.on_action { |action| choice_actions << action }
choice.fields.first.trigger(:select, [2])
assert(choice.cancel_pending_action? && choice.fields.first.options == ['Play'], 'Leading rows broke card choices')
choice.cancel_pending_action!
assert(choice.fields.first.index == 2 && choice.fields.first.options[2] == 'B', 'Cancelling a choice lost the selected card')
choice.fields.first.trigger(:select, [2])
choice.fields.first.trigger(:select, [0])
assert(choice_actions.last['card_id'] == 'b' && choice.fields.first.index == 2, 'Completing a choice used the wrong card or cursor')
choice.fields.first.index = 0
choice.handle_command('navigate_playable_card', 'hand_id'=>'hand', 'card_ids'=>['b'], 'direction'=>1)
assert(choice.fields.first.index == 2, 'Legal-card navigation ignored the leading offset')
empty = GameSurfaces.build(leading_spec([]))
empty.fields.first.index = 0
assert(!empty.state.key?('selected_commands'), 'A leading row on an empty hand became Draw')
begin
  GameSurfaces.build(leading_spec(rows:[GameSurfaces::CardListRow.new(id:'', label:'Invalid')]))
  raise 'Malformed leading rows were accepted'
rescue ArgumentError => error
  assert(error.message.include?('leading card-list'), 'Unexpected validation failure')
end
puts 'PASS card-list leading rows: native labels/offsets, own IDs, read-only rows, commands, sorting, quiet refresh, reconstruction, draws, choices and legal-card navigation'
