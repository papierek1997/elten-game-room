require_relative '../support/background_help_game_screen'

[:empty, :finished].each do |mode|
  h, screen = screen_fixture(GameRoomGames::FourInARow.new)
  old_id = h.session['__id']
  if mode == :finished
    7.times do |move|
      h.write(move.even? ? 'Alice' : 'Bob', [GameRoomGames::EventCommand.new(action: 'drop', value: move.even? ? '1' : '2')])
    end
    assert(h.replay('Alice').winner == 'Alice', 'The old game did not finish')
  end
  h.start
  current_id = h.session['__id']
  # Model a newly opened/covered old screen whose rematch wake-up was already
  # consumed. The normal snapshot path, not another fabricated notification,
  # must select the current game and rebuild the client before its first move.
  h.transports['Alice'].consume_game_start(h.table['__id'])
  displayed = []
  screen.singleton_class.prepend(Module.new do
    define_method(:prepare_action_view) do |replay|
      displayed << instance_variable_get(:@session)['__id']
      super(replay)
    end
  end)
  stage = :wait_current
  Form.driver = lambda do |_form|
    layout = screen.instance_variable_get(:@layout)
    case stage
    when :wait_current
      next unless screen.instance_variable_get(:@session)['__id'] == current_id && layout.surface
      assert(displayed.none? { |id| id == old_id }, 'The retired screen displayed an empty old replay')
      stage = :move
      layout.surface.fields.first.trigger(:select, [0, 0])
    when :move
      next unless h.events('Alice').size == 1
      h.assert_converged('first current gesture after missed rematch', expected_count: 1)
      stage = :exit
      layout.back_button.trigger(:press)
    when :exit
      layout.back_button.trigger(:press)
    end
  end
  h.as('Alice') { assert(screen.run == :back, 'The screen did not leave normally') }
  assert(stage == :exit && displayed.include?(current_id), 'The current game did not become interactive')
  puts "PASS actual GameScreen: retired #{mode} game, missed wake-up, complete switch and first current move"
ensure
  Form.driver = nil
  h&.users&.each { |user| h.as(user) { h.view(user)&.close } }
end
