# frozen_string_literal: true

module GameRoomBilliards
  # Metres, with +Y towards the top cushion. Angles grow anticlockwise.
  class Table
    attr_reader :width, :height, :radius, :mass, :rails, :pockets, :discipline

    CAROMS = %w[carom one_cushion three_cushion].freeze
    TELEMETRY = %w[ten straight one_pocket bank_short bank_full cutthroat blackball english carom one_cushion three_cushion pyramid].freeze

    def initialize(pockets: nil, discipline: 'practice')
      @discipline = discipline
      @width, @height, @radius, @mass = 2.54, 1.27, 0.028575, 0.17
      @width, @height, @radius, @mass = 3.569, 1.778, 0.02625, 0.142 if %w[snooker english].include?(discipline)
      @width, @height, @radius, @mass = 2.84, 1.42, 0.03075, 0.21 if CAROMS.include?(discipline)
      @width, @height, @radius, @mass = 3.55, 1.775, 0.034, 0.285 if discipline == 'pyramid'
      @corner_gap, @side_gap, @corner_outer, @side_outer, @jaw_depth = 0.085, 0.07, 0.04, 0.05, 0.06
      @corner_depth, @side_depth, @side_capture = 0.025, 0.035, 0.05
      if discipline == 'pyramid'
        # IPC training profile: 72.8 mm corner mouths and 83 mm middle mouths.
        @corner_gap, @side_gap = 0.0515, 0.0415
        @corner_outer, @side_outer, @jaw_depth = 0.0615, 0.0515, 0.05
        @corner_depth, @side_depth, @side_capture = 0.05, 0.04, 0.0515
      end
      pockets = !CAROMS.include?(discipline) if pockets.nil?
      @pockets = pockets ? [[0.0, 0.0], [@width / 2, 0.0], [@width, 0.0],
        [0.0, @height], [@width / 2, @height], [@width, @height]] : []
      @rails = []
      if pockets
        [0.0, @height].each_with_index do |y, side|
          inward = side.zero? ? -1 : 1
          [[@corner_gap, @width / 2 - @side_gap], [@width / 2 + @side_gap, @width - @corner_gap]].each do |a, b|
            @rails << [a, y, b, y, side.zero? ? :bottom : :top]
          end
          [[@corner_gap, @corner_outer], [@width / 2 - @side_gap, @width / 2 - @side_outer],
            [@width / 2 + @side_gap, @width / 2 + @side_outer], [@width - @corner_gap, @width - @corner_outer]].each do |a, b|
            @rails << [a, y, b, y + inward * @jaw_depth, :jaw]
          end
        end
        [0.0, @width].each_with_index do |x, side|
          outward = side.zero? ? -1 : 1
          @rails << [x, @corner_gap, x, @height - @corner_gap, side.zero? ? :left : :right]
          @rails << [x, @corner_gap, x + outward * @jaw_depth, @corner_outer, :jaw]
          @rails << [x, @height - @corner_gap, x + outward * @jaw_depth, @height - @corner_outer, :jaw]
        end
      else
        @rails = [[0, 0, @width, 0, :bottom], [0, @height, @width, @height, :top],
          [0, 0, 0, @height, :left], [@width, 0, @width, @height, :right]]
      end
      @rails.each(&:freeze).freeze
      @pockets.each(&:freeze).freeze
    end

    def pocket_planes
      [[1, 1, -@corner_depth], [0, 1, -@side_depth], [-1, 1, -@width - @corner_depth],
        [1, -1, -@height - @corner_depth], [0, -1, -@height - @side_depth], [-1, -1, -@width - @height - @corner_depth]]
    end

    def telemetry?; TELEMETRY.include?(@discipline); end
    def head_string; @width / 4; end
    def baulk_line; %w[snooker english].include?(@discipline) ? 0.737 : (@discipline == 'blackball' ? @width / 5 : head_string); end
    def inside_zone?(x, y, zone)
      dx = [0, 2].include?(zone) ? x : @width - x
      dy = zone < 2 ? y : @height - y
      dx / 0.71 + dy / 0.355 <= 1 + 1e-9
    end

    def in_d?(x, y)
      x <= 0.737 + 1e-9 && Math.hypot(x - 0.737, y - @height / 2) <= 0.292 + 1e-9
    end

    def pocket_at(x, y)
      return nil if @pockets.empty?
      # The centre must cross the mouth, beyond the playing bed; proximity
      # alone never pots a ball. Rounded noses and jaws collide separately.
      return 0 if x + y < -@corner_depth && x < @corner_gap && y < @corner_gap
      return 2 if @width - x + y < -@corner_depth && x > @width - @corner_gap && y < @corner_gap
      return 3 if x + @height - y < -@corner_depth && x < @corner_gap && y > @height - @corner_gap
      return 5 if @width - x + @height - y < -@corner_depth && x > @width - @corner_gap && y > @height - @corner_gap
      return 1 if y < -@side_depth && (x - @width / 2).abs < @side_capture
      return 4 if y > @height + @side_depth && (x - @width / 2).abs < @side_capture
      nil
    end

    def placement?(balls, id, x, y, kitchen: false)
      return false unless [x, y].all? { |v| v.is_a?(Numeric) && v.finite? }
      return false unless x.between?(@radius, @width - @radius) && y.between?(@radius, @height - @radius)
      return false if kitchen && x > @width / 4
      balls.none? { |b| b.id != id && b.on_table? && Math.hypot(b.x - x, b.y - y) < 2 * @radius + 0.00001 } &&
        @rails.none? { |rail| Geometry.distance_to_segment(x, y, rail).first < @radius - 1e-8 }
    end
  end

  module Geometry
    module_function

    def angle(x, y); (Math.atan2(y, x) * 180 / Math::PI) % 360; end
    def difference(a, b); (a - b + 180) % 360 - 180; end
    def direction(degrees)
      radians = degrees * Math::PI / 180
      [Math.cos(radians), Math.sin(radians)]
    end

    def distance_to_segment(x, y, rail)
      ax, ay, bx, by = rail
      dx, dy = bx - ax, by - ay
      part = (((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0)
      px, py = ax + part * dx, ay + part * dy
      [Math.hypot(x - px, y - py), px, py]
    end

    def ray_circle(x, y, dx, dy, cx, cy, radius)
      rx, ry = cx - x, cy - y
      along = rx * dx + ry * dy
      perpendicular = rx * dy - ry * dx
      discriminant = radius * radius - perpendicular * perpendicular
      return nil if discriminant < 0 || along < 0
      distance = along - Math.sqrt(discriminant)
      distance >= -1e-7 ? [distance, 0.0].max : nil
    end

    def ray_rail(x, y, dx, dy, rail, radius)
      ax, ay, bx, by = rail
      length = Math.hypot(bx - ax, by - ay)
      tx, ty = (bx - ax) / length, (by - ay) / length
      nx, ny = -ty, tx
      candidates = [[ax, ay], [bx, by]].filter_map { |cx, cy| ray_circle(x, y, dx, dy, cx, cy, radius) }
      velocity = dx * nx + dy * ny
      if velocity.abs > 1e-10
        [-radius, radius].each do |offset|
          distance = (offset - (x - ax) * nx - (y - ay) * ny) / velocity
          next if distance < 0
          projection = (x + distance * dx - ax) * tx + (y + distance * dy - ay) * ty
          candidates << distance if projection.between?(0.0, length)
        end
      end
      candidates.min
    end

    def trace(table, balls, cue_id, degrees)
      cue = balls.find { |b| b.id == cue_id && b.on_table? }
      return nil unless cue
      dx, dy = direction(degrees)
      contacts = balls.filter_map do |ball|
        next if ball.id == cue_id || !ball.on_table?
        distance = ray_circle(cue.x, cue.y, dx, dy, ball.x, ball.y, 2 * table.radius)
        next unless distance
        offset = ((ball.x - cue.x) * dy - (ball.y - cue.y) * dx) / (2 * table.radius)
        {kind: :ball, id: ball.id, distance: distance, offset: offset, x: cue.x + dx * distance, y: cue.y + dy * distance}
      end
      table.rails.each do |rail|
        distance = ray_rail(cue.x, cue.y, dx, dy, rail, table.radius)
        contacts << {kind: :rail, id: rail.last, distance: distance} if distance
      end
      # Follow openings through the solver's admission planes: an outside jaw
      # may still block a ray after it crosses the edge of the playing bed.
      mouths = table.pocket_planes
      mouths.each_with_index do |(nx, ny, boundary), id|
        next if table.pockets.empty?
        speed = dx * nx + dy * ny
        next unless speed < -1e-10
        distance = (boundary - cue.x * nx - cue.y * ny) / speed
        next if distance < 0
        px, py = cue.x + dx * distance, cue.y + dy * distance
        next unless table.pocket_at(px + dx * 1e-7, py + dy * 1e-7) == id
        contacts << {kind: :pocket, id: id, distance: distance}
      end
      contacts.min_by { |contact| contact[:distance] }
    end

    def nearby(table, balls, cue_id, degrees, spread: 5.0)
      cue = balls.find { |b| b.id == cue_id && b.on_table? }
      return [] unless cue
      balls.filter_map do |ball|
        next unless ball.on_table? && ball.id != cue_id
        bearing = angle(ball.x - cue.x, ball.y - cue.y)
        delta = difference(bearing, degrees)
        next if delta.abs > spread
        first = trace(table, balls, cue_id, bearing)
        {id: ball.id, distance: Math.hypot(ball.x - cue.x, ball.y - cue.y), angle: bearing,
          delta: delta, blocked_by: first && first[:kind] == :ball && first[:id] != ball.id ? first[:id] : nil}
      end.sort_by { |item| [item[:distance], item[:id]] }
    end

    # Read-only continuation of the aiming ray through each intersected ball.
    # Real post-collision paths are calculated separately by Physics.simulate.
    def through(table, balls, cue_id, degrees)
      remaining, contacts = balls.dup, []
      balls.length.times do
        contact = trace(table, remaining, cue_id, degrees)
        break unless contact
        contacts << contact
        break unless contact[:kind] == :ball
        remaining.reject! { |ball| ball.id == contact[:id] }
      end
      contacts
    end

    def pocket_aim(table, balls, cue_id, target_id, pocket_id)
      cue, target = [cue_id, target_id].map { |id| balls.find { |b| b.id == id && b.on_table? } }
      pocket = table.pockets[pocket_id] if pocket_id.is_a?(Integer) && pocket_id >= 0
      return nil unless cue && target && pocket && cue != target
      dx, dy = target.x - pocket[0], target.y - pocket[1]
      distance = Math.hypot(dx, dy)
      return nil if distance.zero?
      x, y = target.x + dx / distance * 2 * table.radius, target.y + dy / distance * 2 * table.radius
      return nil if ((target.x - cue.x) * (-dx) + (target.y - cue.y) * (-dy)) / distance <= 2 * table.radius
      angle(x - cue.x, y - cue.y)
    end
  end
end
