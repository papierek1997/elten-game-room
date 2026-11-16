require_relative '../support/card_hand_cursor'
require_relative '../support/assertions'
require_relative '../../games/rummy'
include GameRoomTest::Assertions

def mode_spec(packet:, modes:)
  ids = %w[3C 9S 2H]
  cards = ids.each_with_index.map do |id, index|
    suit = %w[H S D C].index(id[1])
    GameSurfaces::Card.new(id:id, value:id, label:id,
      sort_keys:{'colour'=>[suit,id[0]], 'number'=>[id[0],suit], 'none'=>[index]})
  end
  if packet
    GameSurfaces::PacketCardSpec.new(id:'hand', header:'Cards', cards:cards, action_name:'play', allow_packet:true,
      hand_order:ids, hand_epoch:'one', default_sort:'colour', sort_modes:modes)
  else
    GameSurfaces::CardTableSpec.new(default_sort:'colour', sort_modes:modes, zones:[
      GameSurfaces::CardZoneSpec.new(id:'hand', header:'Cards', cards:cards, hand_order:ids, hand_epoch:'one')])
  end
end

[false, true].each do |packet|
  old = GameSurfaces.build(mode_spec(packet:packet, modes:nil))
  old.handle_command('sort_cards', 'mode'=>'none')
  old.fields.first.index = 1
  old.send(:toggle_card, old.displayed_hand_cards('hand').first) if packet
  spec = mode_spec(packet:packet, modes:%w[colour number])
  surface = GameSurfaces.build(spec, state:old.state)
  control = surface.fields.first
  assert_equal(%w[2H 9S 3C], surface.displayed_hand_cards('hand').map(&:id), 'A removed remembered mode overrode the declaration')
  assert_equal('9S', surface.displayed_hand_cards('hand')[control.index].id, 'Removing a mode lost the physical cursor')
  assert_equal(['3C'], surface.state['selected_ids']) if packet
  assert(surface.state['card_sort_mode'].to_s.empty?, 'Removed mode remained in local state')
  emitted = []
  surface.on_action { |action| emitted << action }
  before = Marshal.dump(surface.state)
  $spoken_messages.clear
  assert(!surface.handle_command('sort_cards', 'mode'=>'none', 'message'=>'Wrong'), 'A retained forbidden callback was accepted')
  assert_equal(before, Marshal.dump(surface.state), 'A refused mode changed local preparation')
  assert($spoken_messages.empty? && emitted.empty?, 'A refused mode emitted success speech or a move')
  assert(surface.handle_command('sort_cards', 'mode'=>'number'), 'Allowed rank sorting was refused')
  assert_equal(%w[2H 3C 9S], surface.displayed_hand_cards('hand').map(&:id))
  reduced = mode_spec(packet:packet, modes:%w[colour])
  surface.update_spec(reduced)
  assert(surface.fields.first.equal?(control), 'Updating allowed modes rebuilt the native control')
  assert_equal(%w[2H 9S 3C], surface.displayed_hand_cards('hand').map(&:id), 'Refresh retained a mode no longer allowed')
  assert_equal('9S', surface.displayed_hand_cards('hand')[control.index].id, 'Mode refresh lost the cursor')
  assert_equal(['3C'], surface.state['selected_ids']) if packet
  assert(emitted.empty?, 'Changing presentation modes emitted a move')
end

game = GameRoomGames::Rummy.new
state = game.initial_state(%w[Alice Bob], game.default_options)
state.update(phase: :playing, round:1, turn:1, current_player:'Alice', drawn:true,
  hands:{'Alice'=>%w[2S0 3S0 4S0 9H0], 'Bob'=>%w[KC0]})
replay = GameRoomGames::Replay.new(players:state[:players], state:state, current_player:'Alice', history:[])
surface = GameSurfaces.build(game.surface_spec(replay, 'Alice'))
surface.handle_command('meld_new')
control = surface.fields.first
%w[2S0 3S0].each do |id|
  control.index = surface.displayed_hand_cards('hand').index { |card| card.id == id }
  control.trigger(:select, [control.index])
end
saved = surface.state.merge('card_sort_mode'=>'none')
surface = GameSurfaces.build(game.surface_spec(replay, 'Alice'), state:saved)
assert_equal(%w[2S0 3S0], surface.state['meld_selection'], 'Dropping a disabled mode changed a prepared meld')
before = Marshal.dump(surface.state)
assert(!surface.handle_command('sort_cards', 'mode'=>'none'), 'Meld hand accepted the removed mode')
assert_equal(before, Marshal.dump(surface.state), 'A refused meld sort changed preparation')
puts 'PASS card sort permissions: tables/packets/melds, retained callback refusal, stale local-mode reset, physical focus and prepared-packet preservation'
