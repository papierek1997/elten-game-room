require_relative '../../support/card_hand_cursor'
require_relative '../../../games/three_five_eight'

game = GameRoomGames::ThreeFiveEight.new
spades = GameRoomGames::Spades.new
%i[choosing_contract discarding exchanging exchange_return playing].each do |phase|
  state = game.send(:initial_state, %w[Alice Bob Carol], game.default_options)
  state.update(round: 2, phase: phase, current_player: 'Bob', chooser: 'Bob', contract: 'H')
  state[:hands]['Alice'] = %w[AH 9H JS KH]
  replay = GameRoomGames::Replay.new(players: state[:players], state: state,
    current_player: 'Bob', accepted_events: [], history: [])
  spec = -> { game.surface_spec(replay, 'Alice') }
  surface = GameSurfaces.build(spec.call)
  ids = ->(view=surface) { view.instance_variable_get(:@cards).fetch('hand').map(&:id) }
  expected = -> { state[:hands]['Alice'].sort_by { |card| spades.send(:card_sort_key, card) } }
  assert(ids.call == expected.call, "#{phase}: initial hand differs from Spades")

  state[:hands]['Alice'] << 'QH'
  before = Marshal.dump(state)
  surface.update_spec(spec.call)
  assert(ids.call == expected.call, "#{phase}: received heart was appended instead of joining its suit")
  assert(ids.call[surface.fields.first.index] == 'QH', "#{phase}: cursor lost the received card")
  assert(surface.take_cursor_announcement(0) == game.send(:card_label, 'QH'), "#{phase}: received-card announcement lost")
  assert(Marshal.dump(state) == before, "#{phase}: sorting changed the authoritative state")
  reminder = game.shortcut_feature_data(:hand, replay, 'Alice').fetch(:message)
  assert(reminder == "Your hand: #{expected.call.map { |card| game.send(:card_label, card) }.join('; ')}.",
    "#{phase}: H differs from the default display order")
  restored = GameSurfaces.build(spec.call, state: surface.state)
  assert(ids.call(restored) == expected.call, "#{phase}: reconstruction lost suit sorting")

  surface.handle_command('sort_cards', 'mode'=>'colour', 'toggle'=>true)
  assert(ids.call == expected.call, "#{phase}: the first explicit suit sort reversed the default")
  surface.handle_command('sort_cards', 'mode'=>'colour', 'toggle'=>true)
  state[:hands]['Alice'] << 'JH'
  surface.update_spec(spec.call)
  assert(ids.call == expected.call.reverse, "#{phase}: a received card discarded explicit descending sorting")
  surface.handle_command('sort_cards', 'mode'=>'none')
  state[:hands]['Alice'] << 'TH'
  surface.update_spec(spec.call)
  assert(ids.call == state[:hands]['Alice'], "#{phase}: the default overrode explicit acquisition order")
end
puts 'PASS 3-5-8 suit sorting: Spades/H parity, received cards in five phases, cursor/cue, reconstruction and manual overrides'
