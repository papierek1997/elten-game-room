require_relative '../support/tournament_presence_native'

catalog = GameRoomGames::CATALOG
cases = [
  ['blackjack', {'variant'=>'simple', 'round_limit'=>1}],
  ['blackjack', {'variant'=>'extended', 'round_limit'=>1}],
  ['blackjack', {'variant'=>'social', 'round_limit'=>1}],
  ['blackjack_dice', {'scoring'=>'chips', 'round_limit'=>1}],
  ['dice_poker', {'scoring'=>'chips', 'round_limit'=>1}],
  ['roulette', {'mode'=>'social', 'wheel'=>'american', 'round_limit'=>1}],
  ['liars_dice', {'variant'=>'classic', 'starting_dice'=>1}],
  ['bingo', {'variant'=>'30', 'marking'=>'manual'}],
  ['go', {'variant'=>'atari', 'size'=>'9'}]
]
cases.each do |id, options|
  game = catalog.build(id)
  options = game.normalize_options(options)
  TournamentForfeitNative.with_fixture(game: game, options: options) do |fixture|
    fixture.start
    h = fixture.h
    clock = [0.0]
    runners = h.users.to_h { |user| [user, TournamentPresenceNative.runner(fixture, user, clock)] }
    350.times do
      break if h.replay('Alice').finished?
      runners.each { |user, runner| step(h, runner, user) }
      replay = h.replay('Alice')
      break if replay.finished?
      actor = replay.current_player
      runner = runners.fetch(actor)
      actions = game.legal_actions(replay, actor, context: runner.send(:context))
      if id == 'go'
        target = [[0,0], [1,0], [1,1], [8,8], [2,0]].fetch(replay.state[:moves])
        selection = actions.find { |action| action.values_at('x','y') == target }
      else
        preference = %w[claim mark ready check call double stand score challenge]
        selection = preference.filter_map { |verb| actions.find { |action| action['action'] == verb } }.first || actions.first
        next if selection && %w[commit reveal].include?(selection['action'])
      end
      next unless selection
      result = h.as(actor) { runner.submit(session: h.session, replay: h.replay(actor), selection: selection, actor: actor) }
      assert_equal(:ok, result.first, "#{id}/#{options}: #{actor} could not submit #{selection.inspect}")
    end

    final = h.replay('Alice')
    assert(final.finished?, "#{id}/#{options}: game did not finish in the tournament table")
    h.assert_converged("#{id}/#{options}: after the final turn")
    snapshot = TournamentPresenceNative.snapshot(h)
    assert_equal(snapshot.events, final.accepted_events)
    service = fixture.services.fetch('Alice')
    row = service.instance_variable_get(:@bindings).fetch(h.table['__id'])
    captured = GameRoomTournaments::OrdinaryMatchResults.capture(registry: catalog, binding: row.first,
      session: snapshot.session, replay: final, events: snapshot.events)
    assert_equal(%w[alice bob], captured.dig('summary','participants'))
    assert(service.send(:valid_summary?, captured.fetch('summary'), fixture.match))
    h.as('Alice') { service.collect(row + [captured]) }
    result = h.as('Alice') { service.result_view }
    assert_equal(captured.fetch('summary'), result.fetch('results').first.fetch('summary'))
  ensure
    runners&.each_value(&:close)
  end
  puts "PASS bound tournament start, completed game and result: #{id}/#{options['variant'] || options['mode']}"
end
