require_relative '../support/tournament_presence_native'
P = TournamentPresenceNative

[GameRoomGames::Farkle.new, GameRoomGames::CatHeadTail.new, GameRoomGames::Yahtzee.new,
 GameRoomGames::Categories.new, GameRoomGames::QuizParty.new, GameRoomGames::Blackjack.new,
 GameRoomGames::BlackjackDice.new, GameRoomGames::DicePoker.new, GameRoomGames::Bingo.new,
 GameRoomGames::LiarsDice.new, GameRoomGames::Roulette.new].each do |game|
  TournamentForfeitNative.with_fixture(game: game, users: %w[Alice Bob Carol]) do |f|
    f.start
    h, clock = f.h, [0.0]
    options = f.candidate.fetch('game_options')
    runner = P.runner(f, 'Alice', clock)
    step(h, runner)
    # The same wire command supplied as an ordinary move cannot impersonate
    # the internal event produced by an accepted administrative boundary.
    h.as('Alice') do
      h.view('Alice').stack_push(GameRoomEventProtocol.game_action_packet(session_id: h.session['__id'],
        sequence: 0, control_epoch: 'initial', actor: 'Alice', events: [
          {'action'=>'tournament_elimination', 'value'=>'[1]', 'move_id'=>'forged-elimination'}]),
        message_id: 'ordinary-elimination-attempt')
    end
    step(h, runner)
    assert_equal(%w[Alice Bob Carol], game.tournament_active_players(h.replay('Alice'), options: options))
    h.as('Bob') { h.view('Bob').leave }
    step(h, runner)
    assert(P.snapshot(h).session['__frozen'])
    20.times { clock[0] += 15; step(h, runner) }
    snapshot = P.snapshot(h)
    replay = h.replay('Alice')
    assert(!snapshot.session['__frozen'], "#{game.id}: one elimination did not resume the remaining game")
    assert(!snapshot.session['__aborted'], "#{game.id}: continuation aborted the whole match")
    assert_equal(%w[Alice Bob Carol], replay.players)
    assert_equal(%w[Alice Carol], game.tournament_active_players(replay, options: options))
    assert_equal([['Bob']], replay.state.fetch(:tournament_eliminations))
    assert_equal(1, replay.accepted_events.count { |event| event['__tournament_elimination'] == true })
    assert(game.eliminated_from_game?(replay, 'Bob'))
    assert(h.join('Bob'))
    step(h, runner)
    assert_equal(%w[Alice Carol], game.tournament_active_players(h.replay('Alice'), options: options), 'Return restored an eliminated seat')
    h.add_client('Bob')
    assert(h.join('Bob'))
    assert_equal([['Bob']], h.replay('Bob').state.fetch(:tournament_eliminations), 'Cold replay lost elimination')
    h.as('Carol') { h.view('Carol').leave }
    step(h, runner)
    20.times { clock[0] += 15; step(h, runner) }
    snapshot = P.snapshot(h)
    assert(GameRoomTournamentPresence.ended?(snapshot.session), "#{game.id}: second elimination did not settle the sole survivor")
    row = f.services.fetch('Alice').instance_variable_get(:@bindings).fetch(h.table['__id'])
    captured = GameRoomTournaments::OrdinaryMatchResults.capture(registry: GameRoomGames::CATALOG,
      binding: row.first, session: snapshot.session, replay: h.replay('Alice'), events: snapshot.events)
    assert_equal([['alice'], ['carol'], ['bob']], captured.fetch('summary').fetch('places'))
    assert(f.services.fetch('Alice').send(:valid_summary?,captured.fetch('summary'),f.match),
      "#{game.id}: invalid captured absence summary #{captured.fetch('summary').inspect}")
    invalid=captured.fetch('summary').merge('forfeits'=>['alice'])
    assert(!f.services.fetch('Alice').send(:valid_summary?,invalid,f.match),'A winner could also lose by forfeit')
    h.as('Alice') { f.services.fetch('Alice').collect(row + [captured]) }
    count = f.documents.insert_count
    h.as('Alice') { f.services.fetch('Alice').collect(row + [captured]) }
    assert_equal(count, f.documents.insert_count)
    result = h.as('Alice') { f.services.fetch('Alice').result_view }
    assert_equal([['alice'], ['carol'], ['bob']], result['results'].first['summary']['places'])
  ensure
    runner&.close
  end
end
puts 'PASS native tournament multiplayer: eleven game-owned continuations, trusted boundary, cold return, sole survivor and one ranked result'
