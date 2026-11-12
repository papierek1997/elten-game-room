require_relative '../../support/tysiac_four_player'
require_relative '../../../lib/game_simulation'

%w[two_players three_players four_players teams].each do |variant|
  game = GameRoomGames::Tysiac.new
  count = { 'two_players' => 2, 'three_players' => 3, 'four_players' => 4, 'teams' => 4 }.fetch(variant)
  players = %w[Alice Bob Carol David].first(count)
  options = game.normalize_options('variant' => variant, 'score_limit' => 10_000)
  options = game.with_team_assignment(options, players: players, seats: [0, 1, 0, 1]) if variant == 'teams'
  environment = GameRoomSimulation::Environment.new_game(game: game, players: players, options: options, seed: 37)
  30.times do
    break if environment.replay.state[:phase] == :contract
    actions = environment.legal_actions
    selected = if environment.replay.state[:phase] == :bidding
      actions.find { |action| action['bid'].to_s == 'pass' } || actions.find { |action| action['bid'].to_s == '100' }
    else
      actions.find { |action| action['action'] != 'surrender' && action['action'] != 'redeal' }
    end
    assert(selected && environment.step(selected) == :ok, "#{variant}: ordinary setup could not advance")
  end
  before = environment.replay
  assert(before.state[:phase] == :contract, "#{variant}: setup never reached contract selection")
  actor = before.current_player
  card = before.state[:hands].fetch(actor).first
  status, plan = game.action_for({ 'kind' => 'card', 'action' => 'select', 'card' => card }, before, actor, context: environment.context)
  assert(status == :ok && plan.events.map(&:action) == %w[contract play], "#{variant}: no ordinary opening card plan")
  compact = game.send(:private_normalize_plan, plan, before.state)
  assert(compact.events.map(&:action) == ['contract_play'], "#{variant}: no real compact opening plan")
  histories = [plan, compact].map do |opening|
    events = environment.events.map(&:dup)
    opening.events.each do |command|
      events << { 'id' => events.size + 1, 'actor' => actor, 'action' => command.action, 'value' => command.value }
    end
    events
  end

  # Keep both accepted histories distinct, while feeding the same legal public
  # plays through a full trick and into the next one. No immutable log rewrite.
  6.times do
    replays = histories.map { |events| game.replay(environment.session, events, environment.repository) }
    replays.zip(histories).each { |replay, events| assert(replay.accepted_events == events, "#{variant}: replay rejected an opening history") }
    assert(replays[0].state == replays[1].state, "#{variant}: compound opening changed the model")
    viewer = replays.first.current_player
    break unless replays.first.state[:phase] == :playing
    randoms = Array.new(2) { GameRoomRandom::SeededSource.new(13) }
    planners = replays.each_with_index.map { |replay, index| TysiacPlanning::Planner.new(game, replay, viewer, randoms[index]) }
    assert(planners[0].send(:public_played_cards) == planners[1].send(:public_played_cards), "#{variant}: opening public card lost")
    assert(planners[0].send(:inferred_void_suits) == planners[1].send(:inferred_void_suits), "#{variant}: compound opening shifts trick inference")
    assert(planners[0].send(:sampled_worlds, 4) == planners[1].send(:sampled_worlds, 4), "#{variant}: histories sample different worlds")
    assert(game.bot_observation(replays[0], viewer) == game.bot_observation(replays[1], viewer), "#{variant}: fallback observations differ")
    actions = game.legal_actions(replays.first, viewer)
    decisions = planners.map { |planner| planner.choose_play(actions, samples: 4) }
    assert(decisions.first && decisions[0] == decisions[1], "#{variant}: compact history forces fallback or changes decision")
    assert(randoms.map { |random| random.roll(count: 4, sides: 1000).values }.uniq.one?, "#{variant}: subsequent RNG diverged")
    action = decisions.first
    status, move = game.action_for(action, replays.first, viewer, context: environment.context)
    assert(status == :ok, "#{variant}: planner selected an illegal move")
    histories.each do |events|
      move.events.each { |command| events << { 'id' => events.size + 1, 'actor' => viewer, 'action' => command.action, 'value' => command.value } }
    end
  end
end
puts 'PASS Thousand compact opening: actual action plans, four variants, public memory, void inference, sampled worlds, choices and subsequent RNG'
