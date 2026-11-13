require_relative '../../../lib/billiards/physics'

module BilliardsPhysicsTest
  B = GameRoomBilliards
  def self.check(value, message); raise message unless value; end
  def self.shot(**values); {'angle'=>0, 'power'=>180, 'top'=>0, 'side'=>0}.merge(values.transform_keys(&:to_s)); end
  def self.ball(id, x, y); B::Ball.new(id: id, x: x, y: y); end

  def self.run
    table = B::Table.new
    physics = B::Physics.new(table)
    original = [ball(0, 0.5, 0.5), ball(1, 0.85, 0.5)]
    serialized = Marshal.dump(original)
    hit = physics.shoot(original, shot)
    check(Marshal.dump(original) == serialized, 'Physics mutated its input')
    check(hit.events.find { |e| e[:kind] == :ball }&.values_at(:a, :b) == [0, 1], 'Central collision missing')
    check(hit.balls[1].x > 0.9 && hit.balls.all? { |b| b.speed.zero? }, 'Momentum or friction missing')
    check(hit == physics.shoot(original, shot), 'Identical shots differ')
    draw = physics.shoot([ball(0, 0.5, 0.5), ball(1, 0.6, 0.5)], shot(top: -100, power: 250))
    follow = physics.shoot([ball(0, 0.5, 0.5), ball(1, 0.6, 0.5)], shot(top: 100, power: 250))
    check(draw.balls[0].x < 0.5 && follow.balls[0].x > 0.6, 'Draw/follow are not produced by angular momentum')
    cut = physics.shoot([ball(0, 0.5, 0.5), ball(1, 0.85, 0.525)], shot)
    check(cut.balls[1].y > 0.525 && cut.balls[0].y < 0.5, 'Oblique collision direction')
    rail = physics.shoot([ball(0, 2.3, 0.5)], shot(power: 300))
    check(rail.events.any? { |e| e[:kind] == :rail && e[:rail] == :right }, 'Cushion contact missing')
    pot = physics.shoot([ball(0, 1.27, 0.3)], shot(angle: 27000, power: 170))
    check(pot.balls[0].status == :potted && pot.events.last[:pocket] == 1, 'Side pocket mouth failed')
    jaw = physics.shoot([ball(0, 1.21, 0.15)], shot(angle: 27000, power: 150))
    check(jaw.events.any? { |e| e[:rail] == :jaw } && jaw.balls[0].on_table?, "Jaw did not rebound: #{jaw.events.inspect}; #{jaw.balls.inspect}")
    no_pockets = B::Physics.new(B::Table.new(pockets: false)).shoot([ball(0, 1.27, 0.3)], shot(angle: 27000, power: 170))
    check(no_pockets.balls[0].on_table?, 'Carom table has a pocket')
    rack = [ball(0, 0.635, 0.635)]
    5.times do |row|
      (row + 1).times { |col| rack << ball(rack.length, 1.905 + row * Math.sqrt(3) * table.radius, 0.635 + (2 * col - row) * table.radius * 1.0001) }
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    broken = physics.shoot(rack, shot(power: 1000))
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    broken.balls.select(&:on_table?).combination(2) do |a, b|
      check(Math.hypot(a.x - b.x, a.y - b.y) >= 2 * table.radius - 0.0002, 'Overlapping balls after break')
    end
    check(broken.events.any? { |e| e[:a] == 15 || e[:b] == 15 }, 'Fast break tunneled through rack')
    check(!B::Physics.valid_shot?(shot(angle: Float::NAN)) && !B::Physics.valid_shot?(shot(top: 100, side: 100)), 'Invalid shot accepted')
    puts "Billiards physics: central/cut, follow/draw, cushions/jaws/pocket, deterministic 15-ball break; #{broken.steps} steps in #{elapsed.round(3)}s."
  end
end
BilliardsPhysicsTest.run if $PROGRAM_NAME == __FILE__
