require_relative '../../support/billiards'

module BilliardsScoresTest
  extend GameRoomTest::Assertions
  def self.arrange(match)
    match.submit('place', {'ball'=>0, 'x'=>12700, 'y'=>4000})
    match.submit('place', {'ball'=>1, 'x'=>12700, 'y'=>1600})
  end
  def self.run
    match = BilliardsFixture::Match.new
    arrange(match)
    shot = match.shot.merge('angle'=>27000, 'power'=>180)
    result = match.submit('shot', {'shot'=>shot})
    assert(!result.state[:balls][1].on_table?, 'Scoring fixture did not pot its object ball')
    assert_equal([1], result.state[:scores])
    scores = match.game.game_shortcuts(result, 'Alice').find { |s| s.key == 's' }
    assert_equal(:announcement, scores.kind)
    assert_equal('Alice; points: 1', scores.message)
    assert_equal([0], match.submit('undo').state[:scores])
    match.submit('shot', {'shot'=>shot})
    match.submit('place', {'ball'=>0, 'x'=>12700, 'y'=>3000})
    assert_equal([1], match.submit('shot', {'shot'=>shot}).state[:scores], 'Pocketed cue ball earned a point')
    assert_equal([1], match.submit('reset').state[:scores], 'Reset erased practice points')
    replayed = GameRoomGames::Billiards.new.replay(match.session, match.events, match.repository)
    assert_equal(match.replay, replayed, 'Cold replay changed scores')

    group = BilliardsFixture::Match.new(players: ['Alice', 'Bob'])
    arrange(group)
    result = group.submit('shot', {'shot'=>shot})
    assert_equal([1,0], result.state[:scores])
    assert_equal('Bob', result.current_player)
    scores = group.game.shortcut_feature_data(:scores, result, 'Observer')
    assert_equal('Alice; points: 1; Bob; points: 0', scores[:message])
    puts 'Billiards practice scores: object pots, scratches, solo undo, reset retention, shared S list, cold replay and seat ownership passed.'
  end
end
BilliardsScoresTest.run if $PROGRAM_NAME == __FILE__
