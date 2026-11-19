require_relative '../support/trick_game_checkpoint'

specs = [
  [GameRoomGames::Spades.new, %w[Alice Bob Carol], {}],
  [GameRoomGames::Tysiac.new, %w[Alice Bob Carol], {}],
  [GameRoomGames::Tysiac.new, %w[Alice Bob Carol Dave], {'variant'=>'four_players'}]
]
specs.each do |game, users, options|
  options = game.default_options.merge(options).merge('score_limit'=>10_000, 'bot_delay'=>0)
  TournamentForfeitNative.with_fixture(game: game, users: users, options: options,
    clock: ClockEventContract::ManualTime.new) do |f|
    f.start
    h = f.h
    runners = users.to_h { |user| [user, runner_for(h, user)] }
    assert_equal('no_scored_round', f.legacy_preview['decision']['basis'])
    expected = TrickGameCheckpointTest.verify_boundary(h, runners)
    # Changing native host is not changing the organizer, scoring units or seats.
    h.view(users.first).transfer_ownership(h.view(users.first).participants.find { |person| person.user == users.last })
    2.times { PrivateCardGamesTest.tick(h, runners) }
    assert_equal(expected, TrickGameCheckpointTest.checkpoint(h))
    loser = expected['scores'].max_by { |_name, score| score }.first.downcase
    preview = f.legacy_preview(loser: loser)
    assert_equal('scored_round', preview['decision']['basis'])
    assert_equal(expected['scores'].transform_keys(&:downcase), preview['summary']['scores'])
    assert_equal([loser], preview['summary']['places'].last, 'The withdrawn leader must remain last')
    assert_equal(users.sort, h.replay(users.first).players.sort, 'Administrative preview changed original roster')
    view = f.insert_historical(preview)
    count = f.documents.insert_count
    assert_raises(GameRoomTournaments::OrdinaryMatchService::Blocked) { f.confirm(preview) }
    assert_equal(count, f.documents.insert_count, 'Same consent wrote a duplicate receipt')
    assert_equal(view, f.services.fetch(users.last).result_view)
  ensure
    runners&.each_value(&:close)
  end
end

# Ordinary games retain their rules, public randomness and complete deal scores.
[
  [GameRoomGames::Spades.new, %w[Alice Bob Carol Dave Eve Frank], {'team_size'=>2}],
  [GameRoomGames::Tysiac.new, %w[Alice Bob Carol], {}],
  [GameRoomGames::Tysiac.new, %w[Alice Bob], {'variant'=>'two_players'}]
].each do |game, users, options|
  h = NativeRoomHarness.new(game: game, users: users,
    options: game.default_options.merge(options).merge('score_limit'=>10_000, 'bot_delay'=>0),
    clock: ClockEventContract::ManualTime.new)
  h.start
  runners = users.to_h { |user| [user, runner_for(h, user)] }
  expected = TrickGameCheckpointTest.verify_boundary(h, runners, surrender: game.id == 'tysiac')
  assert(!h.replay(users.first).state[:private_cards], 'Ordinary game became a private tournament')
  assert_equal(game.id == 'spades' ? 3 : users.size, expected['scores'].size)
ensure
  runners&.each_value(&:close)
end
puts 'PASS native Spades/Tysiac full deal checkpoints: private/ordinary, 3/4/resting/teams, next deal, surrender, host transfer, organizer receipt, loser last and retry'
