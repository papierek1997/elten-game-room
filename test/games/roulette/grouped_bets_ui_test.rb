require_relative '../../support/game_option_form'
require_relative '../../../games/roulette'

game = GameRoomGames::Roulette.new
repo = Struct.new(:players) do
  def players_for(_session); players; end
  def actor_of(event, _session); event['actor']; end
  def event_id(event); event['id']; end
end.new(%w[Alice Bob])
%w[european american french].each do |wheel|
  replay = game.replay({'options' => JSON.generate(game.normalize_options('wheel' => wheel))}, [], repo)
  definition_reads = 0
  original = game.method(:bet_definitions)
  game.define_singleton_method(:bet_definitions) { |state| definition_reads += 1; original.call(state) }
  spec = game.surface_spec(replay, 'Alice')
  assert(definition_reads <= 2, 'Grouped presentation repeatedly searches/rebuilds the bet catalog')
  game.singleton_class.send(:remove_method, :bet_definitions)
  assert(spec.items.size == 12 && spec.menus.size == 11, 'Bet types are still a flat action list')
  actual = spec.menus.values.flatten.map { |item| item.action.payload['bet'] }
  assert(actual.uniq == actual && actual.sort == GameRoomRouletteBets.definitions(wheel).map { |bet| bet[:key] }.sort,
    'Grouping dropped, duplicated or invented a bet')
  numbers = spec.menus.fetch('bets:numbers').map { |item| item.action.payload['bet'] }
  assert(numbers == (0..(wheel == 'american' ? 37 : 36)).map { |n| "n#{n}" }, 'Numbers are not in numeric order')
  surface = GameSurfaces::PawnTrackSurface.new(spec)
  emitted = []
  surface.on_action { |action| emitted << action }
  root = surface.fields.first
  colours = spec.items.index { |item| item.id == 'bets:colours' }
  root.index = colours
  root.trigger(:select, [colours])
  assert(emitted.empty? && surface.state['menu'] == 'bets:colours', 'Opening a category submitted a game move')
  root.trigger(:select, [0])
  assert(emitted.last.to_h.values_at('action', 'bet') == ['bet', 'red'], 'Quick bet lost its normal action')
  restored = GameSurfaces::PawnTrackSurface.new(spec, state: surface.state)
  assert(restored.cancel_pending_action!, 'Escape cannot leave the bet category')
  assert(restored.fields.first.index == colours, 'Returning from a category moved the root cursor')
  assert(!restored.cancel_pending_action?, 'Category still traps the next Escape')

  screen = GameScreen.allocate
  screen.instance_variable_set(:@game, game)
  screen.instance_variable_set(:@program, EltenGameRoom.allocate)
  assert(game.custom_game_shortcuts(replay, 'Alice').none? { |entry| entry.key == 'b' }, 'Redundant B shortcut remains')
  shortcut = game.surface_action_shortcut(emitted.last.to_h, replay, 'Alice')
  screen.define_singleton_method(:number_shortcut_input) do |prompt, **options|
    assert(prompt.start_with?('Red.') && options[:text] == '10' && options[:select_all], 'Amount editor lost selected bet or suggested stake')
    assert(options[:flags] == EditBox::Flags::Numbers, 'Stake is not a numeric editor')
    '17'
  end
  selection = screen.send(:activate_game_shortcut, shortcut, surface, replay: replay)
  status, plan = game.action_for(selection.to_h, replay, 'Alice')
  assert(status == :ok && plan.events.first.value == '1|red|17', 'Enter editor changed selected bet, wire action or stake')
  assert(game.surface_action_shortcut(emitted.last.to_h, replay, 'Bob').nil?, 'Waiting player can open an amount editor')
  assert(game.surface_action_shortcut(spec.items[colours].action.to_h, replay, 'Alice').nil?, 'Category opens an amount editor')
  screen.define_singleton_method(:number_shortcut_input) { |*_args, **_options| nil }
  assert(screen.send(:activate_game_shortcut, shortcut, surface, replay: replay).nil?, 'Escape places a bet')
  poor = game.replay({'options' => JSON.generate(game.normalize_options('wheel' => wheel, 'starting_chips' => 10))},
    [{'id' => 1, 'actor' => 'Alice', 'action' => 'bet', 'value' => '1|red|5'}], repo)
  poor_shortcut = game.surface_action_shortcut(game.legal_actions(poor, 'Alice').first, poor, 'Alice')
  assert(poor_shortcut.default_value == 5 && poor_shortcut.allowed_values == (1..5), 'Suggested amount exceeds the balance')
  forged = selection.to_h.merge('bet' => 'unknown')
  assert(game.action_for(forged, replay, 'Alice').first == :invalid_bet, 'Unknown bet accepted')
  assert(game.surface_spec(replay, 'Bob').menus.empty?, 'Waiting player has active betting menus')
end
Form.driver = nil
puts 'PASS grouped roulette: complete bets, local menus, Enter amount editor, cancel, limited balance and unchanged wire on all wheels'
