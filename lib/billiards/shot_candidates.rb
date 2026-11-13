# frozen_string_literal: true

module GameRoomBilliards
  # Finite, deterministic geometric proposals. The ordinary strategy still
  # owns power selection and simulation; a proposal is never a legal move.
  module ShotCandidates
    module_function
    LIMIT = 96
    RAILS = [:left, :right, :top, :bottom].freeze

    # [launch angle in degrees, travel distance, first object ID, pocket,
    #  declared ordered rail IDs]. No RNG or simulation is consumed here.
    def build(state, table, cue)
      return [] unless cue && cue.on_table? && state[:choices].to_a.empty?
      ids = if Rules.competition?(state[:options])
        Rules.targets(state)
      else
        state[:balls].select(&:on_table?).map(&:id) - [cue.id]
      end
      ids |= state[:balls].select { |b| b.on_table? && b.id != cue.id }.map(&:id) if Rules.snooker?(state) && state[:free_ball]
      targets = state[:balls].select { |b| b.on_table? && b.id != cue.id && ids.include?(b.id) }
        .sort_by { |b| [Math.hypot(b.x - cue.x, b.y - cue.y), b.id] }
      return caroms(state, table, cue, targets) if table.pockets.empty?
      bank = %w[bank_short bank_full].include?(state[:options]['discipline'])
      pockets = if state[:options]['discipline'] == 'one_pocket'
        [state[:point_pockets][state[:turn]]].compact
      else
        table.pockets.each_index.to_a
      end
      sequences = bank ? rail_sequences(1) + rail_sequences(2) : [[]]
      candidates = []
      sequences.each do |sequence|
        targets.each do |target|
          pockets.sort_by { |i| Math.hypot(target.x - table.pockets[i][0], target.y - table.pockets[i][1]) }.each do |pocket|
            path = reflected_path([target.x, target.y], table.pockets[pocket], sequence, table)
            next unless path && clear_path?(path, table, state[:balls], [cue.id, target.id])
            dx, dy = path[1][0] - target.x, path[1][1] - target.y
            candidate = ghost_candidate(state, table, cue, target, dx, dy)
            next unless candidate
            angle, distance = candidate
            candidates << [angle, distance + path_length(path), target.id, pocket, sequence.dup]
            return ranked(candidates) if candidates.length >= LIMIT
          end
        end
      end
      ranked(candidates)
    end

    def ranked(candidates)
      candidates.uniq { |angle, _, id, pocket, rails| [(angle * 100).round, id, pocket, rails] }
        .sort_by { |angle, distance, id, pocket, rails| [distance, id, pocket, rails, angle] }.first(LIMIT)
    end

    def rail_sequences(length)
      return [[]] if length.zero?
      rail_sequences(length - 1).flat_map { |prefix| (0..3).reject { |rail| rail == prefix.last }.map { |rail| prefix + [rail] } }
    end

    def reflected_end(point, sequence, table)
      x, y = point
      sequence.reverse_each do |rail|
        case rail
        when 0 then x = 2 * table.radius - x
        when 1 then x = 2 * (table.width - table.radius) - x
        when 2 then y = 2 * (table.height - table.radius) - y
        when 3 then y = 2 * table.radius - y
        end
      end
      [x, y]
    end

    # Unfold a rectangular table at cue/object center clearance. Every
    # proposed cushion must be physically present; a pocket gap is not a bank.
    def reflected_path(start, finish, sequence, table)
      return [start, finish] if sequence.empty? && Math.hypot(finish[0] - start[0], finish[1] - start[1]) > 1e-9
      virtual = reflected_end(finish, sequence, table)
      dx, dy = virtual[0] - start[0], virtual[1] - start[1]
      length = Math.hypot(dx, dy)
      return nil if length < 1e-9
      dx, dy = dx / length, dy / length
      x, y = start
      path = [start]
      sequence.each do |rail|
        horizontal = rail >= 2
        boundary = [table.radius, table.width - table.radius, table.height - table.radius, table.radius][rail]
        speed = horizontal ? dy : dx
        return nil if speed.abs < 1e-9
        distance = (boundary - (horizontal ? y : x)) / speed
        return nil if distance <= 1e-7
        nx, ny = x + dx * distance, y + dy * distance
        return nil unless nx.between?(table.radius - 1e-8, table.width - table.radius + 1e-8) &&
          ny.between?(table.radius - 1e-8, table.height - table.radius + 1e-8)
        return nil unless table.rails.any? do |segment|
          segment.last == RAILS[rail] && (Geometry.distance_to_segment(nx, ny, segment).first - table.radius).abs < 1e-7
        end
        path << [nx, ny]
        x, y = nx, ny
        horizontal ? dy = -dy : dx = -dx
      end
      distance = (finish[0] - x) * dx + (finish[1] - y) * dy
      return nil if distance <= 1e-7 || ((finish[0] - x) * dy - (finish[1] - y) * dx).abs > 1e-6
      path + [finish]
    end

    def clear_path?(path, table, balls, ignored)
      path.each_cons(2).all? do |(ax, ay), (bx, by)|
        length = Math.hypot(bx - ax, by - ay)
        next false if length < 1e-9
        dx, dy = (bx - ax) / length, (by - ay) / length
        blocked = balls.any? do |ball|
          ball.on_table? && !ignored.include?(ball.id) && Geometry.distance_to_segment(ball.x, ball.y, [ax, ay, bx, by]).first < 2 * table.radius - 1e-7
        end
        next false if blocked
        table.rails.none? do |segment|
          distance = Geometry.ray_rail(ax + dx * 1e-6, ay + dy * 1e-6, dx, dy, segment, table.radius)
          distance && distance > 1e-5 && distance < length - 1e-5
        end
      end
    end

    def ghost_candidate(state, table, cue, target, dx, dy)
      length = Math.hypot(dx, dy)
      return nil if length < 1e-9
      gx, gy = target.x - 2 * table.radius * dx / length, target.y - 2 * table.radius * dy / length
      cue_contact(state, table, cue, target, gx, gy)
    end

    def cue_contact(state, table, cue, target, gx, gy)
      angle, distance = Geometry.angle(gx - cue.x, gy - cue.y), Math.hypot(gx - cue.x, gy - cue.y)
      return nil if distance < 1e-7
      contact = Geometry.trace(table, state[:balls], cue.id, angle)
      return nil unless contact && contact[:kind] == :ball && contact[:id] == target.id && (contact[:distance] - distance).abs < 1e-5
      [angle, distance]
    end

    def path_length(path); path.each_cons(2).sum { |a, b| Math.hypot(b[0] - a[0], b[1] - a[1]) }; end

    def caroms(state, table, cue, targets)
      count = {'one_cushion'=>1, 'three_cushion'=>3}.fetch(state[:options]['discipline'], 0)
      sequences = rail_sequences(count)
      sequences += rail_sequences(1) if count.zero?
      candidates = []
      targets.each do |first|
        targets.reject { |b| b.id == first.id }.each do |second|
          sequences.each do |sequence|
            image = reflected_end([second.x, second.y], sequence, table)
            dx, dy = image[0] - first.x, image[1] - first.y
            distance, diameter = Math.hypot(dx, dy), 2 * table.radius
            next if distance <= diameter
            bearing, spread = Math.atan2(dy, dx), Math.acos(diameter / distance)
            [-spread, spread].each do |offset|
              gx, gy = first.x + diameter * Math.cos(bearing + offset), first.y + diameter * Math.sin(bearing + offset)
              contact = cue_contact(state, table, cue, first, gx, gy)
              next unless contact
              path = reflected_path([gx, gy], [second.x, second.y], sequence, table)
              next unless path && clear_path?(path, table, state[:balls], [cue.id, first.id, second.id])
              # Equal-mass contact removes the incoming normal component.
              # Reject a tangent whose outgoing direction is the reverse one.
              ix, iy = (gx - cue.x) / contact[1], (gy - cue.y) / contact[1]
              nx, ny = (first.x - gx) / diameter, (first.y - gy) / diameter
              normal = ix * nx + iy * ny
              tx, ty = ix - normal * nx, iy - normal * ny
              next unless normal > 1e-6 && tx * (path[1][0] - gx) + ty * (path[1][1] - gy) > 1e-6
              candidates << [contact[0], contact[1] + path_length(path) - diameter, first.id, 0, sequence.dup]
              return ranked(candidates) if candidates.length >= LIMIT
            end
          end
        end
      end
      ranked(candidates)
    end
  end
end
