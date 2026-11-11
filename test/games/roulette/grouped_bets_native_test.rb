require_relative '../../support/duck_challenge_native'
require_relative '../../../games/roulette'
require_relative '../../../lib/game_screen'

driver = DuckChallengeNativeDriver.new
Session.define_singleton_method(:name) { 'Alice' }

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
SpeechOutput.reset
control.trigger(:select, group)
assert(actions.empty? && surface.state['menu'] == 'bets:colours', 'Native category Enter submitted a move')
assert(control.options.first.start_with?('Red'), 'Native category did not show its bets')
assert(SpeechOutput.calls.one? && SpeechOutput.calls.first.first.strip.start_with?('Red') &&
  SpeechOutput.calls.none? { |call| call.first.include?('Spin ') || call.first.include?('Your chips:') },
  "Opening bets repeats the full table status: #{SpeechOutput.calls.inspect}")
control.trigger(:select, 0)
assert(actions.size == 1 && actions.first['bet'] == 'red', 'Native bet Enter did not emit one ordinary bet')
restored = GameSurfaces::PawnTrackSurface.new(spec, state: surface.state)
assert(restored.cancel_pending_action!, 'Native category cannot close')
assert(restored.fields.first.index == group, 'Native category lost parent selection')

# The real screen callback must complete the selected action locally before
# admitting a move. No synthetic bet is submitted from the default list item.
screen = GameScreen.allocate
screen.instance_variable_set(:@game, game)
screen.instance_variable_set(:@session, {})
screen.define_singleton_method(:event_presentation_busy?) { false }
responses, inputs = ['17'], []
screen.define_singleton_method(:number_shortcut_input) do |prompt, **options|
  inputs << [prompt, options]
  responses.shift
end
layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(replay, 'Alice'), user_items: %w[Alice Bob])
wait = GameScreen::WaitState.new(replay: replay)
screen.send(:bind_wait_surface, wait, layout, -> {})
control = layout.surface.fields.first
control.index = group
control.trigger(:select, group)
assert(inputs.empty? && wait.action.nil?, 'Opening a category entered the stake or resumed the screen')
control.trigger(:select, 0)
chosen = screen.instance_variable_get(:@selected_surface_action)
assert(inputs.size == 1 && inputs.first.first.start_with?('Red.') && inputs.first.last[:text] == '10', "Enter did not open one editor for the selected bet: #{inputs.inspect}; viewer=#{Session.name}; wait=#{wait.action.inspect}")
assert(chosen.to_h.values_at('bet', 'amount') == ['red', 17] && wait.action == :game_action, 'Screen did not capture the completed stake')
wait.action = nil
screen.instance_variable_set(:@selected_surface_action, nil)
responses << nil
control.index = 1
control.trigger(:select, 1)
assert(wait.action.nil? && screen.instance_variable_get(:@selected_surface_action).nil?, 'Cancel captured a default bet')
assert(layout.surface.state['menu'] == 'bets:colours' && control.index == 1, 'Cancel moved the selected bet')
# A nested dialog can be invalidated by a refresh. It must not replace that
# refresh with a move from the former view.
screen.define_singleton_method(:number_shortcut_input) { |*_args, **_options| wait.action = :refresh; '21' }
control.trigger(:select, 1)
assert(wait.action == :refresh && screen.instance_variable_get(:@selected_surface_action).nil?, 'Changed view accepted stale dialog input')
wait.action = nil
rejected = 0
pending = Object.new
pending.define_singleton_method(:admits_move?) { true }
pending.define_singleton_method(:reject_action) { rejected += 1 }
layout.form.game_room_pending_operation = pending
control.trigger(:select, 1)
assert(rejected == 1 && wait.action.nil?, 'Pending operation opened a dialog or captured the default bet')
layout.form.game_room_pending_operation = nil
layout.surface.cancel_pending_action!
screen.define_singleton_method(:number_shortcut_input) { |*_args, **_options| raise 'Ordinary action opened the stake editor' }
ready = spec.items.index { |item| item.action&.name == 'ready' }
control.trigger(:select, ready)
assert(wait.action == :game_action && screen.instance_variable_get(:@selected_surface_action)['action'] == 'ready',
  'Ordinary finish-betting action was intercepted')
$activecontrols = []
puts 'PASS native roulette: category navigation, one Enter stake dialog, completed input, cancel and invalidated view'
