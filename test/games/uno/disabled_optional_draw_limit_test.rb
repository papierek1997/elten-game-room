require_relative '../../support/new_games_fixture'

game = GameRoomGames::Uno.new
players = %w[Alice Bob Carol]
repository = NewGames116Repository.new(players)
deal = { 'id' => 1, 'actor' => 'Alice', 'action' => 'deal', 'value' => '1|0|0000000000000000000000000000000b|0' }
[-5, 0, 3].each do |hidden_limit|
  [false, true].each do |draw_until|
    options = game.default_options.merge('allow_optional_draw' => false,
      'maximum_optional_draws' => hidden_limit, 'draw_until_playable' => draw_until)
    assert(game.validation_error(options, player_count: 3).nil?, 'An inactive control became a validation error')
    session = { 'options' => JSON.generate(game.game_start_options(options, players: players)) }
    replay = game.replay(session, [deal], repository)
    actor = replay.current_player
    assert(replay.accepted_events == [deal] && !game.send(:has_playable_card?, replay.state, actor), 'Fixture no longer has a necessary draw')
    assert(game.legal_actions(replay, actor).any? { |action| action['action'] == 'draw' }, 'Hidden optional limit removed the only legal move')
    status, plan = game.action_for({ 'kind' => 'command', 'action' => 'draw' }, replay, actor)
    assert(status == :ok, "Hidden limit #{hidden_limit} blocks necessary draw")
    events = [deal] + plan.events.each_with_index.map do |command, index|
      { 'id' => index + 2, 'actor' => actor, 'action' => command.action, 'value' => command.value }
    end
    continued = game.replay(session, events, repository)
    assert(continued.accepted_events == events && continued.state[:hands][actor].size > replay.state[:hands][actor].size,
      'Allowed necessary draw was not accepted in replay')
  end
end

# Once a player does have an ordinary playable card, disabling optional draw
# still forbids taking another card. Find a bounded deterministic real deal.
session = { 'options' => JSON.generate(game.default_options.merge('allow_optional_draw' => false, 'maximum_optional_draws' => 0)) }
playable = (0...32).filter_map do |seed|
  event = deal.merge('value' => "1|0|#{seed.to_s(16).rjust(32, '0')}|0")
  replay = game.replay(session, [event], repository)
  replay if game.send(:has_playable_card?, replay.state, replay.current_player) && replay.state[:pending_draw].zero?
end.first
assert(playable, 'No bounded ordinary playable fixture')
status, = game.action_for({ 'kind' => 'command', 'action' => 'draw' }, playable, playable.current_player)
assert(status == :cannot_draw, 'Ignoring an inactive limit enabled voluntary drawing')
puts 'PASS UNO inactive optional limit: real deal, zero/negative hidden values, necessary/optional draws, draw-until and accepted replay'
