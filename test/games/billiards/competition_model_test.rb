require_relative '../../support/billiards'

module BilliardsCompetitionModelTest
  extend GameRoomTest::Assertions
  def self.run
    match = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'nine', 'rack_seed'=>12})
    start = match.replay
    assert_equal(nil, match.game.options_error(start.state[:options], player_count: 2))
    assert(match.game.options_error(start.state[:options], player_count: 1))
    assert(!match.game.private_table_required?(start.state[:options]))
    assert_equal(:invalid, match.game.action_for(match.selection('place', 'ball'=>1, 'x'=>300, 'y'=>300), start, 'Alice').first)
    match.submit('place', {'ball'=>0, 'x'=>300, 'y'=>300})
    objects = Marshal.dump(match.replay.state[:balls].drop(1))
    after = match.submit('shot', {'shot'=>match.shot.merge('angle'=>22500, 'power'=>200), 'call'=>0, 'pocket'=>0, 'mode'=>0})
    assert_equal(:scratch, after.state[:ruling][:foul])
    assert_equal('Bob', after.current_player)
    assert(!after.state[:balls].first.on_table?)
    assert_equal(objects, Marshal.dump(after.state[:balls].drop(1)), 'Scratch replaced the rack')
    %w[reset undo pass finish].each { |action| assert_equal(:invalid, match.game.action_for(match.selection(action), after, 'Bob').first) }
    after = match.submit('place', {'ball'=>0, 'x'=>5000, 'y'=>5000})
    assert_equal(objects, Marshal.dump(after.state[:balls].drop(1)), 'Placing white moved other balls')
    assert(match.events.all? { |e| e['value'].bytesize <= 64 })
    cold = GameRoomGames::Billiards.new.replay(match.session, match.events, match.repository)
    assert_equal(after, cold)
    old = match.events + [{'id'=>99, 'actor'=>'Bob', 'action'=>'shot', 'value'=>JSON.generate([1, after.state[:revision], 0, 200, 0, 0])}]
    assert_equal(after.accepted_events, match.game.replay(match.session, old, match.repository).accepted_events)
    ended = match.submit('concede')
    assert_equal('Alice', ended.winner)
    assert(ended.finished?)
    assert(!ended.draw)
    assert(match.game.result_text(ended).include?('Alice'))
    %w[eight nine snooker].each do |discipline|
      game = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>discipline})
      replay = game.replay
      game.game.legal_actions(replay, 'Alice').each do |selection|
        assert_equal(:ok, game.game.action_for(selection, replay, 'Alice').first)
      end
      game.submit('concede')
      assert_equal('Bob', game.replay.winner)
    end
    series = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'eight', 'race_to'=>2})
    frame = series.submit('concede')
    assert_equal(:rack_end, frame.state[:phase])
    assert(frame.history.last.text.include?('Bob wins'), 'Interim winner announcement used the wrong seat')
    next_frame = series.submit('choice', {'choice'=>0})
    assert_equal([0, 1], next_frame.state[:racks])
    assert_equal('Bob', next_frame.current_player)
    assert(next_frame.state[:breaking])
    offer = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'eight'})
    original = Marshal.dump(offer.replay.state[:balls])
    pending = offer.submit('stalemate')
    assert_equal('Bob', pending.current_player)
    assert_equal(%w[agree decline], pending.state[:choices])
    declined = offer.submit('choice', {'choice'=>1})
    assert_equal('Alice', declined.current_player)
    assert_equal(original, Marshal.dump(declined.state[:balls]))
    offer.submit('stalemate')
    agreed = offer.submit('choice', {'choice'=>0})
    assert_equal([0, 0], agreed.state[:racks])
    assert_equal(0, agreed.state[:breaker])
    assert(agreed.state[:breaking])
    assert_equal(1, agreed.state[:rack_number])
    puts 'Competitive billiards model: real scratch/white-only placement, authenticated compact actions, practice commands rejected, cold replay, declared legal actions and match winner passed.'
  end
end
BilliardsCompetitionModelTest.run if $PROGRAM_NAME == __FILE__
