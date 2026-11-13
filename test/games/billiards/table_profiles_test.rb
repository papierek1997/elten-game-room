require_relative '../../support/billiards'

module BilliardsTableProfilesTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  def self.run
    snooker, english = %w[snooker english].map { |discipline| B::Table.new(discipline: discipline) }
    assert_equal([snooker.width, snooker.height, snooker.radius], [english.width, english.height, english.radius])
    blackball = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'blackball'})
    move = blackball.game.legal_actions(blackball.replay, 'Alice').first
    assert_equal('shot', move['action'], 'Blackball did not offer an initially playable break')
    assert_equal(:ok, blackball.game.action_for(move, blackball.replay, 'Alice').first)
    %w[carom one_cushion three_cushion].each do |discipline|
      table = B::Table.new(discipline: discipline)
      assert_equal([2.84, 1.42, 0.03075], [table.width, table.height, table.radius])
      assert_equal([], table.pockets)
      balls = [B::Ball.new(id: 0, x: 1.0, y: 0.2)]
      result = B::Physics.simulate(table, balls, {'angle'=>27000, 'power'=>250, 'top'=>0, 'side'=>0})
      assert(result.events.any? { |event| event[:kind] == :rail && event[:rail] == :bottom })
      assert(result.balls.first.on_table?)
      assert(result.events.each_with_index.all? { |event, index| event[:order] == index })
    end
    table = B::Table.new(discipline: 'pyramid')
    assert_equal([3.55, 1.775, 0.034], [table.width, table.height, table.radius])
    middle = B::Ball.new(id: 0, x: table.width / 2, y: 0.2)
    shot = {'angle'=>27000, 'power'=>200, 'top'=>0, 'side'=>0}
    direct = B::Geometry.trace(table, [middle], 0, 270)
    assert_equal([:pocket, 1], direct.values_at(:kind, :id))
    result = B::Physics.simulate(table, [middle], shot)
    assert_equal(1, result.events.find { |event| event[:kind] == :pocket }&.dig(:pocket), 'A centered Pyramid ball could not pass its middle mouth')
    middle.x += 0.03
    assert_equal(:rail, B::Geometry.trace(table, [middle], 0, 270)[:kind], 'A Pyramid jaw admitted an off-centre ball')
    corner = B::Ball.new(id: 0, x: 0.15, y: 0.15)
    result = B::Physics.simulate(table, [corner], shot.merge('angle'=>22500))
    assert_equal(0, result.events.find { |event| event[:kind] == :pocket }&.dig(:pocket), 'A centered Pyramid ball could not pass its corner mouth')
    balls = [B::Ball.new(id: 1, x: 0.5, y: 0.3), B::Ball.new(id: 0, x: 2.5, y: 1.0)]
    result = B::Physics.simulate(B::Table.new(discipline: 'english'), balls, shot.merge('angle'=>0, 'power'=>900), cue_id: 1)
    assert_equal([1, 0], result.balls.map(&:id), 'Dynamic cue simulation reordered physical IDs')
    assert(result.events.any? { |e| e[:kind] == :crossing && e[:line] == :baulk && e[:a] == 1 })
    assert(result.events.each_cons(2).all? { |a, b| a[:t] <= b[:t] }, 'Telemetry broke chronological event order')
    puts 'Billiards table profiles: pocketless caroms, English/snooker dimensions, actual tight Pyramid corner/middle admission and blocked jaws, stable cue IDs and chronological telemetry passed.'
  end
end
BilliardsTableProfilesTest.run if $PROGRAM_NAME == __FILE__
