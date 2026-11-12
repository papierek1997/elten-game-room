# Executable reference for docs/ADDING_A_GAME.md. This is a local broker test,
# not live accounts, physical input or audible playback. Do not import scenarios.
require_relative '../support/session_runner'
require_relative '../../games/catalog'
require_relative '../support/assertions'
include GameRoomTest::Assertions

assert(GameRoomGames::CATALOG.build('tic_tac_toe').is_a?(GameRoomGames::TicTacToe), 'Reference game is not registered')
registry = GameRoomGames::Registry.new([GameRoomGames::TicTacToe])
game = registry.build('tic_tac_toe')
assert_equal('tic_tac_toe', game.id)
assert_equal([2, 2], [game.minimum_players, game.maximum_players])
assert(!game.short_description.empty? && !game.rule_book.sections.empty?, 'Reference game lacks player content')

room = NativeRoomHarness.new(game: game, users: %w[Alice Bob], options: game.table_creation_options({}))
room.start
runners = room.users.to_h { |user| [user, runner_for(room, user)] }
begin
  assert_equal(nil, room.replay('Alice').current_player, 'A move preceded the start draw')
  room.view('Alice').next_random_values = Array.new(16, 2)
  step(room, runners.fetch('Alice')) # The ordinary executor requests the server recipe.
  room.assert_converged('drawn start', expected_count: 1)
  assert_equal(1, room.view('Alice').calls[:random], 'The start used extra or client-only randomness')
  starter = room.replay('Alice').current_player
  assert(%w[Alice Bob].include?(starter), 'Draw did not choose a participant')

  # Explicit player decisions produce a complete legal game. The winning player
  # takes the bottom row; the opponent uses the row above it.
  fields = [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0]]
  fields.each_with_index do |(column, row), index|
    before = room.replay('Alice')
    actor = before.current_player
    action = {'kind' => 'grid', 'action' => 'select', 'x' => column, 'y' => row}
    view = game.game_view_spec(before, actor)
    assert_equal([:status, :game, :chat, :history, :users], view.sections)
    assert_equal([3, 3, :bottom], [view.surface.width, view.surface.height, view.surface.row_origin])
    assert(game.legal_actions(before, actor).include?(action), 'The surface action is not legal')
    other = (before.players - [actor]).first
    assert_equal([:not_your_turn, nil], game.action_for(action, before, other))

    room.as(actor) do
      status, = runners.fetch(actor).submit(session: room.session, replay: before, selection: action, actor: actor)
      assert_equal(:ok, status, 'The ordinary executor refused the reference move')
    end
    room.assert_converged("move #{index + 1}", expected_count: index + 2)
    after = room.replay('Bob')
    event = after.accepted_events.last
    label = "#{('A'.ord + column).chr}#{row + 1}"
    assert_equal("#{actor} #{label}.", game.describe_event(event, room.repositories.fetch('Bob'), after, 'Bob'))
    assert_equal('play2', game.event_sound_cues(event: event, before_replay: before,
      after_replay: after, history: after.history, viewer: 'Bob', random_variant: 0))

    next unless index.zero?

    accepted = room.events('Bob').dup
    room.as(after.current_player) do
      status, = runners.fetch(after.current_player).submit(session: room.session, replay: after,
        selection: action, actor: after.current_player)
      assert_equal(:occupied, status, 'The executor accepted an occupied field')
    end
    assert_equal(accepted, room.events('Bob'), 'Refusal wrote an event')
    room.assert_converged('refused occupied field', expected_count: 2)
  end

  result = room.replay('Alice')
  assert_equal(starter, result.winner)
  assert(!result.draw && result.finished?, 'The final mark did not finish the game')
  assert_equal(:finished, result.state.fetch(:phase))
  assert_equal([:finished, nil], game.action_for({'kind' => 'grid', 'action' => 'select', 'x' => 2, 'y' => 2}, result, starter))
ensure
  runners.each_value(&:close)
end
puts 'PASS contributor reference: registry, rules, server start, shared view, ordinary executors, two-player moves, refusal, replay convergence, history, cue routing and result (local broker)'
