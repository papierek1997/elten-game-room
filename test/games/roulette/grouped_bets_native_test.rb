require_relative '../../support/duck_challenge_native'
require_relative '../../../games/roulette'

game = GameRoomGames::Roulette.new
repository = Struct.new(:players) do
  def players_for(_session); players; end
end.new(%w[Alice Bob])
replay = game.replay({'options' => JSON.generate(game.default_options)}, [], repository)
spec = game.surface_spec(replay, 'Alice')
surface = GameSurfaces::PawnTrackSurface.new(spec)
actions = []
surface.on_action { |action| actions << action.to_h }
control = surface.fields.first
group = spec.items.index { |item| item.id == 'bets:colours' }
control.index = group
control.trigger(:select, group)
assert(actions.empty? && surface.state['menu'] == 'bets:colours', 'Native category Enter submitted a move')
assert(control.options.first.start_with?('Red'), 'Native category did not show its bets')
control.trigger(:select, 0)
assert(actions.size == 1 && actions.first['bet'] == 'red', 'Native bet Enter did not emit one ordinary bet')
restored = GameSurfaces::PawnTrackSurface.new(spec, state: surface.state)
assert(restored.cancel_pending_action!, 'Native category cannot close')
assert(restored.fields.first.index == group, 'Native category lost parent selection')
$activecontrols = []
puts 'PASS native roulette category/selection callbacks, one move, replay restore and Escape'
