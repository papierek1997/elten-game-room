require_relative '../../support/billiards'

module BilliardsModelTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  def self.run
    match = BilliardsFixture::Match.new
    start = match.replay
    assert_equal([], match.game.tournament_capabilities[:player_counts], 'Practice offered as a competition')
    assert_equal('billiards-test', match.game.surface_spec(start, 'Alice').game_id)
    after = match.submit('shot', {'shot'=>match.shot})
    assert_equal(1, after.state[:shots])
    assert_equal(1, after.accepted_events.size)
    assert(after.state[:last].events.any? { |e| e[:kind] == :ball })
    assert_equal(start.state[:balls], match.submit('undo').state[:balls])
    assert_equal(0, match.replay.state[:shots])
    after = match.submit('shot', {'shot'=>match.shot})
    remembered = Marshal.dump(after)
    cached = B::Physics.simulate(B::Table.new, start.state[:balls], match.shot)
    cached.balls.first.x = 99
    cached.events.clear
    assert_equal(remembered, Marshal.dump(match.replay), 'Mutable physics or replay cache escaped')
    cold = GameRoomGames::Billiards.new.replay(match.session, match.events, match.repository)
    assert_equal(after, cold, 'Cold/incremental replay differs')
    assert_equal(:invalid, match.game.action_for({'kind'=>'billiards', 'action'=>'shot', 'revision'=>0, 'shot'=>match.shot}, after, 'Alice').first)
    assert_equal(:invalid, match.game.action_for(match.selection('finish').merge('revision'=>after.state[:revision].to_f), after, 'Alice').first)
    assert_equal(:invalid, match.game.action_for(match.selection('place', 'ball'=>0, 'x'=>after.state[:balls][1].x * 10_000, 'y'=>6350), after, 'Alice').first)
    forged = match.events + [{'id'=>99, 'actor'=>'Mallory', 'action'=>'finish', 'value'=>JSON.generate('revision'=>after.state[:revision])},
      {'id'=>100, 'actor'=>'Alice', 'action'=>'shot', 'value'=>JSON.generate('revision'=>after.state[:revision], 'shot'=>match.shot.merge('power'=>Float::INFINITY.to_s))}]
    assert_equal(after.accepted_events, match.game.replay(match.session, forged, match.repository).accepted_events)
    # Authentication and earlier bytes are rechecked even after caching a prefix.
    altered = Marshal.load(Marshal.dump(match.events))
    altered[0]['actor'] = 'Mallory'
    assert_equal(0, match.game.replay(match.session, altered, match.repository).accepted_events.size)
    assert_equal(after, match.replay, 'A shorter or rejected history poisoned the latest replay')
    placed = match.submit('place', {'ball'=>0, 'x'=>12700, 'y'=>3000})
    assert_equal(1.27, placed.state[:balls].first.x)
    potted = match.submit('shot', {'shot'=>match.shot.merge('angle'=>27000, 'power'=>170)})
    assert(!potted.state[:balls].first.on_table?)
    assert(match.game.legal_actions(potted, 'Alice').all? { |a| match.game.action_for(a, potted, 'Alice').first == :ok }, 'Offered a shot with a potted cue ball')
    assert_equal(:invalid, match.game.action_for(match.selection('shot', 'shot'=>match.shot), potted, 'Alice').first)
    match.submit('place', {'ball'=>0, 'x'=>5000, 'y'=>3000})
    assert(match.replay.state[:balls].first.on_table?)
    assert(match.submit('finish').finished?)

    shared = BilliardsFixture::Match.new(players: ['Alice', 'Bob'], options: {'shots'=>2, 'layout'=>'triangle'})
    assert_equal(16, shared.replay.state[:balls].length)
    assert(!shared.game.surface_spec(shared.replay, 'Spectator').enabled)
    assert_equal(:not_your_turn, shared.game.action_for(shared.selection('finish'), shared.replay, 'Spectator').first)
    turn = shared.submit('shot', {'shot'=>shared.shot.merge('power'=>1000)})
    assert_equal('Bob', turn.current_player)
    assert_equal(:invalid, shared.game.action_for(shared.selection('undo'), turn, 'Bob').first)
    assert(shared.submit('shot', {'shot'=>shared.shot}).finished?)
    stages = shared.game.event_presentation_stages(shared.events.first, shared.repository, nil,
      shared.game.replay(shared.session, shared.events.first(1), shared.repository), 'Alice')
    assert(stages.any? { |s| s[:history].any? { |h| GameRoomBilliards::Presentation.cue(h.value) == 'billiards_cue' } })
    assert(stages.any? { |s| s[:history].any? { |h| GameRoomBilliards::Presentation.cue(h.value) == 'billiards_collision' } })
    assert(stages.all? { |s| s[:delay].between?(0, 1.5) })
    assert(stages[0...-1].all? { |s| s[:wait_for_sounds] == false }, 'Contact timing waits for a whole pocket recording')
    puts 'Billiards model: shots, undo, placement, scratch, stale/forged input, cache isolation, cold replay, turn rotation, finish and contact cues passed.'
  end
end
BilliardsModelTest.run if $PROGRAM_NAME == __FILE__
