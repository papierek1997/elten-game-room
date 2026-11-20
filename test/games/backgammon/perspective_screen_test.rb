require_relative '../../support/background_help_game_screen'
require_relative '../../../games/backgammon'

game = GameRoomGames::Backgammon.new
exported, heard = {}, Hash.new { |hash, viewer| hash[viewer] = [] }
harness, alice_screen = screen_fixture(game,
  save_table_history: ->(entries) { exported['Alice'] = entries.map(&:text) })
screens = {'Alice'=>alice_screen}
begin
  harness.as('Bob') do
    transport = harness.transports.fetch('Bob')
    screens['Bob'] = GameScreen.new(program: ProgramDouble.new(harness.broker.endpoint('Bob')),
      repository: harness.repositories.fetch('Bob'), game: game, session: harness.session,
      table: harness.table, table_owner: 'Alice',
      synchronizer: GameRoomSync::Controller.new(transport: transport, table_id: harness.table['__id'],
        session_id: harness.session['__id'], clock: -> { $help_clock }),
      game_services: {transport: transport},
      save_table_history: ->(entries) { exported['Bob'] = entries.map(&:text) },
      room_snapshot_provider: -> { LobbyRepository::TableSnapshot.new(**transport.room_snapshot(harness.table)) })
  end
  screens.each do |viewer, screen|
    screen.define_singleton_method(:speak_table_automatically) { |text| heard[viewer] << text.to_s }
    harness.as(viewer) { screen.send(:process_new_events, harness.replay(viewer)) }
  end

  context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SeededSource.new(87))
  rows = [
    ['Alice', 'opening', '3,6'], ['Bob', 'move', '13,10,3'], ['Bob', 'move', '8,2,6'],
    ['Alice', 'roll', '2,6'], ['Alice', 'move', '24,22,2'], ['Alice', 'move', '22,16,6'],
    ['Bob', 'roll', '2,1'], ['Bob', 'move', '10,9,1']
  ]
  rows.each do |actor, action, value|
    if action == 'move'
      harness.submit(actor, {'kind'=>'pawn', 'action'=>action, 'move'=>value}, context: context)
    else
      harness.view(actor).next_random_values = value.split(',').map(&:to_i)
      harness.submit(actor, {'kind'=>'dice', 'action'=>action}, context: context)
    end
    screens.each do |viewer, screen|
      harness.as(viewer) { screen.send(:process_new_events, harness.replay(viewer)) }
    end
  end
  harness.assert_converged('Reported capture')
  {'Alice'=>[15, 16], 'Bob'=>[10, 9]}.each do |viewer, (from, to)|
    harness.as(viewer) do
      screen = screens.fetch(viewer)
      replay = harness.replay(viewer)
      expected = "Bob moves a checker from point #{from} to point #{to}. The opponent's checker goes to the bar."
      assert(heard.fetch(viewer).count { |text| text == expected } == 1, 'Native event speech uses the wrong perspective')
      layout = screen.send(:prepare_action_view, replay).layout
      assert(layout.history.is_a?(EditBox), 'The history bypassed the native text control')
      assert(layout.history.text.include?(expected), 'Native history differs from the board and speech')
      screen.send(:save_presented_history, replay)
      assert(exported.fetch(viewer).include?(expected), 'TXT export handoff used the actor instead of the viewer')
      count = heard.fetch(viewer).size
      screen.send(:process_new_events, replay)
      screen.send(:prepare_action_view, replay)
      assert(heard.fetch(viewer).size == count, 'Quiet refresh repeats the capture')
    end
  end
ensure
  screens.each_value { |screen| screen.send(:stop_session_runner) }
end
puts 'PASS reported Backgammon capture through both native repositories, actual event speech, native history control and TXT export handoff; quiet refresh stays silent'
