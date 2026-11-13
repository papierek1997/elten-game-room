require_relative '../../../lib/billiards/physics'

module BilliardsAimingTest
  B = GameRoomBilliards
  def self.check(value, message); raise message unless value; end
  def self.run
    table, g = B::Table.new, B::Geometry
    balls = [[0, 0.5, 0.5], [1, 1.0, 0.5], [2, 1.5, 0.5], [3, 1.0, 0.56]].map { |id,x,y| B::Ball.new(id: id, x: x, y: y) }
    first = g.trace(table, balls, 0, 0)
    check(first[:id] == 1 && (first[:distance] - (0.5 - 2 * table.radius)).abs < 1e-9, 'Ray ignored radii/nearest ball')
    check(g.nearby(table, balls, 0, 0).find { |i| i[:id] == 2 }[:blocked_by] == 1, 'Occlusion missing')
    check(g.trace(table, balls, 0, 90)[:kind] == :rail, 'Cushion trace missing')
    check(g.trace(table, [B::Ball.new(id: 0, x: 1.27, y: 0.5)], 0, 90)[:kind] == :pocket, 'Pocket trace missing')
    tangent = Math.asin(2 * table.radius / 0.5) * 180 / Math::PI
    check(g.trace(table, balls.first(2), 0, tangent - 0.005)[:kind] == :ball, 'Grazing ball missed')
    check(g.trace(table, balls.first(2), 0, tangent + 0.005)[:kind] != :ball, '0.01-degree change not resolved')
    close = g.nearby(table, balls, 0, 4, spread: 5)
    check(close.any? { |v| v[:id] == 3 } && g.trace(table, balls, 0, 0)[:id] != 3, 'Nearby confused with direct contact')
    check(!table.placement?(balls, 0, 1, 0.5) && !table.placement?(balls, 0, Float::INFINITY, 0.5), 'Invalid placement')
    thin = [B::Ball.new(id: 0, x: 1.25, y: 0.56), B::Ball.new(id: 1, x: 1.27, y: 0.635)]
    check(g.pocket_aim(table, thin, 0, 1, 5).nil?, 'Impossible cut approached the ghost ball from inside the object ball')
    puts 'Billiards aiming: radii, nearest contact, hidden/nearby balls, rail/pocket and 0.01-degree boundary passed.'
  end
end
BilliardsAimingTest.run if $PROGRAM_NAME == __FILE__
