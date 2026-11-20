require_relative '../support/card_hand_cursor'
require_relative '../support/assertions'
require_relative '../../games/rummy'
include GameRoomTest::Assertions

def mode_spec(packet:, modes:, default_sort: 'colour')
  ids = %w[3C 9S 2H]
  cards = ids.each_with_index.map do |id, index|
    suit = %w[H S D C].index(id[1])
    GameSurfaces::Card.new(id:id, value:id, label:id,
      sort_keys:{'colour'=>[suit,id[0]], 'number'=>[id[0],suit], 'none'=>[index]})
  end
  if packet
    GameSurfaces::PacketCardSpec.new(id:'hand', header:'Cards', cards:cards, action_name:'play', allow_packet:true,
      hand_order:ids, hand_epoch:'one', default_sort:default_sort, sort_modes:modes)
  else
    GameSurfaces::CardTableSpec.new(default_sort:default_sort, sort_modes:modes, zones:[
      GameSurfaces::CardZoneSpec.new(id:'hand', header:'Cards', cards:cards, hand_order:ids, hand_epoch:'one')])
  end
end

# A declared default is already active before the first manual command. Both
# surface families reverse it immediately, without losing a card or packet.
[false, true].each do |packet|
  {'colour'=>%w[2H 9S 3C], 'number'=>%w[2H 3C 9S], 'none'=>%w[3C 9S 2H]}.each do |mode, ascending|
    spec = mode_spec(packet:packet, modes:%w[colour number none], default_sort:mode)
    surface = GameSurfaces.build(spec)
    ids = -> { surface.displayed_hand_cards('hand').map(&:id) }
    assert_equal(ascending, ids.call, "#{packet}/#{mode}: wrong initial order")
    surface.fields.first.index = ids.call.index('9S')
    if packet
      %w[3C 2H].each { |id| surface.send(:toggle_card, surface.displayed_hand_cards('hand').find { |card| card.id == id }) }
    end
    emitted = []
    3.times do |press|
      surface.on_action { |action| emitted << action }
      direction = mode != 'none' && press.even? ? 'descending' : 'ascending'
      expected = direction == 'descending' ? ascending.reverse : ascending
      $spoken_messages.clear
      assert(surface.handle_command('sort_cards', 'mode'=>mode, 'toggle'=>true,
        'ascending_message'=>'Ascending', 'descending_message'=>'Descending'), 'Default sort command was refused')
      assert_equal(expected, ids.call, "#{packet}/#{mode}: wrong order on press #{press + 1}")
      assert_equal([direction.capitalize], $spoken_messages, 'Sort direction was not announced once')
      assert_equal('9S', ids.call[surface.fields.first.index], 'Sort lost the physical cursor')
      assert_equal(%w[3C 2H], surface.state['selected_ids'], 'Sort reordered the prepared packet') if packet
      $spoken_messages.clear
      control = surface.fields.first
      surface.update_spec(spec)
      assert(surface.fields.first.equal?(control), 'Sort refresh rebuilt the control')
      assert_equal(expected, ids.call, 'Refresh lost the sort direction')
      assert($spoken_messages.empty?, 'Quiet refresh repeated sorting speech')
      surface = GameSurfaces.build(spec, state:surface.state)
      assert_equal(expected, ids.call, 'Reconstruction lost the sort direction')
      assert_equal('9S', ids.call[surface.fields.first.index], 'Reconstruction lost the physical cursor')
      assert_equal(%w[3C 2H], surface.state['selected_ids'], 'Reconstruction changed the packet') if packet
    end
    other_mode = mode == 'number' ? 'colour' : 'number'
    expected = other_mode == 'colour' ? %w[2H 9S 3C] : %w[2H 3C 9S]
    surface.handle_command('sort_cards', 'mode'=>other_mode, 'toggle'=>true)
    assert_equal(expected, ids.call, 'A different mode did not start ascending')
    surface.handle_command('sort_cards', 'mode'=>other_mode, 'toggle'=>true)
    assert_equal(expected.reverse, ids.call, 'An explicit sort did not reverse')
    surface.handle_command('sort_cards', 'mode'=>other_mode)
    assert_equal(expected, ids.call, 'A non-toggle command did not set ascending order')
    assert(emitted.empty?, 'Local sorting emitted a game action')
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
puts 'PASS card sort permissions: default/explicit toggles, receipt-order restoration, tables/packets/melds, retained callback refusal, stale local-mode reset, physical focus and prepared-packet preservation'
