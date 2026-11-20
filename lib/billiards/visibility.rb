require_relative 'geometry'
require 'digest'
require 'thread'

module GameRoomBilliards
  module Visibility
    D_CACHE = {}
    D_CACHE_LOCK = Mutex.new
    module_function

    def blocked?(cue, target, angle, blockers, radius)
      dx, dy = Geometry.direction(angle)
      distance = Geometry.ray_circle(cue.x, cue.y, dx, dy, target.x, target.y, radius)
      return true unless distance
      blockers.any? do |ball|
        hit = Geometry.ray_circle(cue.x, cue.y, dx, dy, ball.x, ball.y, radius)
        hit && hit < distance - 1e-7
      end
    end

    def edges_open?(table, balls, target, on)
      cue = balls.first
      distance = Math.hypot(target.x - cue.x, target.y - cue.y)
      return true if distance <= 2 * table.radius + 1e-7
      bearing = Geometry.angle(target.x - cue.x, target.y - cue.y)
      half = Math.asin([2 * table.radius / distance, 1.0].min) * 180 / Math::PI
      blockers = balls.select { |b| b.on_table? && b.id != 0 && !on.include?(b.id) }
      [-1, 1].all? { |side| !blocked?(cue, target, bearing + side * (half - 1e-7), blockers, 2 * table.radius) }
    end

    def snookered?(table, balls, on)
      balls.first.on_table? && balls.select { |b| b.on_table? && on.include?(b.id) }.none? { |b| edges_open?(table, balls, b, on) }
    end

    def direct?(table, balls, on, full: false)
      cue, objects = balls.first, balls.select { |b| b.on_table? && b.id != 0 }
      return false unless cue.on_table?
      objects.select { |b| on.include?(b.id) }.any? do |target|
        bearing = Geometry.angle(target.x - cue.x, target.y - cue.y)
        blockers = objects.reject { |b| b.id == target.id }
        next !blocked?(cue, target, bearing, blockers, 2 * table.radius) if full
        # Tangencies partition the circle into intervals with constant first
        # contact. Check their interiors as well as a straight centre hit.
        edges = objects.flat_map do |ball|
          distance = Math.hypot(ball.x - cue.x, ball.y - cue.y)
          half = Math.asin([2 * table.radius / distance, 1.0].min) * 180 / Math::PI
          centre = Geometry.angle(ball.x - cue.x, ball.y - cue.y)
          [centre - half, centre + half].map { |angle| Geometry.difference(angle, bearing) }
        end
        blockers.each do |ball|
          dx, dy = ball.x - target.x, ball.y - target.y
          distance, radius = Math.hypot(dx, dy), 2 * table.radius
          next unless distance > 0 && distance < 2 * radius
          height = Math.sqrt(radius ** 2 - distance ** 2 / 4)
          [-1, 1].each do |side|
            px = (target.x + ball.x) / 2 - side * dy / distance * height
            py = (target.y + ball.y) / 2 + side * dx / distance * height
            edges << Geometry.difference(Geometry.angle(px - cue.x, py - cue.y), bearing)
          end
        end
        edges.sort!
        probes = [bearing] + edges.each_cons(2).map { |a, b| bearing + (a + b) / 2 }
        probes.any? { |angle| !blocked?(cue, target, angle, blockers, 2 * table.radius) }
      end
    end

    def silhouette_lines(target, blocker, radius)
      dx, dy = blocker.x - target.x, blocker.y - target.y
      distance = Math.hypot(dx, dy)
      ux, uy = dx / distance, dy / distance
      lines = [-1, 1].map { |side| [-uy, ux, -uy * target.x + ux * target.y + side * radius] }
      if distance >= 2 * radius
        cos = 2 * radius / distance
        sin = Math.sqrt([1 - cos * cos, 0].max)
        [-1, 1].each do |side|
          nx, ny = ux * cos - side * uy * sin, uy * cos + side * ux * sin
          lines << [nx, ny, nx * target.x + ny * target.y + radius]
        end
      else
        # Expanded collision circles overlap even when the physical balls do
        # not. At their intersections, the near/far order of an edge changes.
        reach = Math.sqrt(radius ** 2 - distance ** 2 / 4)
        [-1, 1].each do |side|
          px, py = (target.x + blocker.x) / 2 - side * uy * reach, (target.y + blocker.y) / 2 + side * ux * reach
          nx, ny = (px - target.x) / radius, (py - target.y) / radius
          lines << [nx, ny, nx * px + ny * py]
        end
      end
      lines
    end

    def d_snookered?(table, balls, on)
      key = Digest::SHA256.digest(Marshal.dump([table, balls, on]))
      found, cached = D_CACHE_LOCK.synchronize { [D_CACHE.key?(key), D_CACHE[key]] }
      return cached if found
      value = d_snookered_position?(table, balls, on)
      D_CACHE_LOCK.synchronize do
        D_CACHE.shift if D_CACHE.size >= 16
        D_CACHE[key] = value
      end
    end

    def d_snookered_position?(table, original, on)
      balls = original.map(&:dup)
      cue = balls.first
      cue.status = :table
      objects = balls.select { |b| b.on_table? && b.id != 0 }
      targets, blockers = objects.partition { |b| on.include?(b.id) }
      [[0.55, table.height / 2], [0.737, table.height / 2 - 0.292], [0.737, table.height / 2 + 0.292]].each do |x, y|
        cue.x, cue.y = x.round(4), y.round(4)
        return false if table.in_d?(cue.x, cue.y) && table.placement?(balls, 0, cue.x, cue.y) && !snookered?(table, balls, on)
      end
      targets.each do |target|
        lines = blockers.flat_map { |b| silhouette_lines(target, b, 2 * table.radius) }
        # Placement is recorded in 0.1 mm integers. For every legal X column,
        # tangencies/intersections partition Y into constant-visibility cells.
        # One legal integer in each cell proves existence without a coarse grid.
        (4450..7370).each do |column|
          x = column / 10_000.0
          reach = Math.sqrt([0.292 ** 2 - (x - 0.737) ** 2, 0].max)
          low, high = table.height / 2 - reach, table.height / 2 + reach
          cuts = [low, high]
          lines.each { |a, b, c| cuts << (c - a * x) / b if b.abs > 1e-12 }
          objects.each do |ball|
            radius = 2 * table.radius + 0.00001
            next if (ball.x - x).abs > radius
            height = Math.sqrt([radius ** 2 - (ball.x - x) ** 2, 0].max)
            cuts.concat([ball.y - height, ball.y + height])
          end
          cuts = cuts.select { |y| y.between?(low, high) }.sort.uniq
          probes = cuts.flat_map { |y| [(y * 10_000).floor, (y * 10_000).ceil] }
          cuts.each_cons(2) do |a, b|
            bottom, top = (a * 10_000).ceil, (b * 10_000).floor
            probes << (bottom + top) / 2 if bottom <= top
          end
          probes.uniq.each do |row|
            cue.x, cue.y = x, row / 10_000.0
            next unless table.in_d?(cue.x, cue.y) && table.placement?(balls, 0, cue.x, cue.y)
            return false if edges_open?(table, balls, target, on)
          end
        end
      end
      true
    end
  end
end
