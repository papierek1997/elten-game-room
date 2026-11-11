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
  shortcut = game.custom_game_shortcuts(replay, 'Alice').find { |entry| entry.key == 'b' }
  Form.driver = lambda do |form|
    category = form.fields.find { |field| field.header == 'Bet type' }
    category.index = GameRoomRouletteBets::CATEGORIES.index('colours')
    category.trigger(:move)
    visible = form.fields.reject { |field| form.hidden_controls.include?(field) }
    choices = visible.select { |field| field.header == 'Roulette bet' }
    assert(choices.size == 1 && choices.first.options.first.start_with?('Red'), 'Own-amount form exposes other categories')
    form.fields.find { |field| field.header == 'Number of chips to bet' }.set_text('17')
    assert(form.accept_button.label == 'Place bet', 'Roulette still says Send proposal')
    form.accept_button.trigger(:press)
  end
  selection = screen.send(:form_shortcut_action, shortcut)
  status, plan = game.action_for(selection.to_h, replay, 'Alice')
  assert(status == :ok && plan.events.first.value == '1|red|17', 'Grouped form changed the wire action or stake')
  forged = selection.to_h.merge('bet_category' => 'numbers', 'bet_numbers' => 'red')
  assert(game.action_for(forged, replay, 'Alice').first == :invalid_bet, 'Mismatched category accepted')
  assert(game.surface_spec(replay, 'Bob').menus.empty?, 'Waiting player has active betting menus')
end
Form.driver = nil
puts 'PASS grouped roulette: complete bets, numeric order, local categories/back/refresh and own-stake form on all wheels'
