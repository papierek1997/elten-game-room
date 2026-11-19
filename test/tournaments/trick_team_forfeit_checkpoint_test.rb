require_relative '../support/trick_game_checkpoint'

[
  [GameRoomGames::Spades.new, {'team_size'=>2}],
  [GameRoomGames::Tysiac.new, {'variant'=>'teams'}]
].each do |game, options|
  users = %w[Alice Bob Carol Dave]
  options = game.default_options.merge(options).merge('score_limit'=>10_000, 'bot_delay'=>0)
  TournamentForfeitNative.with_fixture(game: game, users: users, options: options,
    clock: ClockEventContract::ManualTime.new) do |f|
    f.candidate.merge!('players_per_match'=>4, 'team_template'=>[0,1,0,1],
      'membership'=>{'version'=>1, 'kind'=>'fixed-teams', 'units'=>[
        {'unit_id'=>'red', 'accounts'=>%w[alice bob]}, {'unit_id'=>'blue', 'accounts'=>%w[carol dave]}]})
    f.match['unit_ids'] = %w[red blue]
    f.start
    h = f.h
    runners = users.to_h { |user| [user, runner_for(h, user)] }
    assert_equal('opponent', f.legacy_preview(loser: 'red')['decision']['basis'])
    expected = TrickGameCheckpointTest.verify_boundary(h, runners)
    before = f.documents.insert_count
    preview = f.legacy_preview(loser: 'red')
    assert_equal(before, f.documents.insert_count, 'Team preview wrote a result')
    assignment = game.prepared_team_assignment(h.replay('Alice').state[:options], players: h.replay('Alice').players)
    mapped = expected['scores'].to_h do |native, points|
      members = assignment.members_for(native).map(&:downcase).sort
      unit = f.candidate['membership']['units'].find { |entry| entry['accounts'].sort == members }
      assert(unit, 'Fixture did not preserve whole native team membership')
      [unit['unit_id'], points]
    end
    assert_equal(mapped, preview['summary']['scores'], 'Team score was duplicated or assigned by native side number')
    assert_equal([['blue'], ['red']], preview['summary']['places'])
    assert_raises(GameRoomTournaments::OrdinaryMatchService::Blocked) { f.preview(loser: 'bob') }
    view = f.insert_historical(preview)
    assert_equal({'blue'=>2, 'red'=>0}, view['standings'].to_h { |row| [row['unit'], row['points']] })
    assert_equal(view, f.services.fetch('Dave').result_view)
  ensure
    runners&.each_value(&:close)
  end
end
puts 'PASS native Spades/Tysiac team checkpoints map exact whole rosters, not duplicated participant totals or native side numbers'
