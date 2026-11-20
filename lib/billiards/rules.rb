require_relative 'physics'
require_relative '../game_random'

module GameRoomBilliards
  # Game-owned rules. Inputs are copied simulation results, never controls or I/O.
  module Rules
    module_function

    def competition?(options); options['discipline'] != 'practice' && !options['discipline'].nil?; end
    def snooker?(state); state[:options]['discipline'] == 'snooker'; end
    def table(options); Table.new(discipline: options.fetch('discipline', 'practice')); end
    def group(id); id.between?(1, 7) ? 0 : (id.between?(9, 15) ? 1 : nil); end
    def reds(balls); balls.select { |b| b.on_table? && b.id.between?(1, 15) }; end
    def value(id); id.between?(1, 15) ? 1 : id - 14; end
    def colour_spots(table)
      {16=>[0.737, table.height / 2 - 0.292], 17=>[0.737, table.height / 2 + 0.292],
        18=>[0.737, table.height / 2], 19=>[table.width / 2, table.height / 2],
        20=>[table.width * 0.75, table.height / 2], 21=>[table.width - 0.324, table.height / 2]}
    end

    def rack(options, number)
      return engine(options).rack(options, number) if engine(options)
      t = table(options)
      balls = [Ball.new(id: 0, x: t.width / 4 - 0.1, y: t.height / 2)]
      if options['discipline'] == 'snooker'
        balls.first.x = 0.55
        colour_spots(t).each { |id, (x, y)| balls << Ball.new(id: id, x: x, y: y) }
        ids, rows, apex = (1..15).to_a, [1, 2, 3, 4, 5], t.width * 0.75 + 2 * t.radius + 0.0001
      else
        random = Random.new(options.fetch('rack_seed', 0) + number)
        if options['discipline'] == 'eight'
          ids = GameRoomRandom.shuffle((1..15).to_a - [8], random: random)
          ids.insert(4, 8)
          corner = ids.index { |id| id != 8 && group(id) != group(ids[10]) }
          ids[14], ids[corner] = ids[corner], ids[14]
          rows, apex = [1, 2, 3, 4, 5], t.width * 0.75
        else
          ids = GameRoomRandom.shuffle((2..8).to_a, random: random)
          ids.unshift(1)
          ids.insert(4, 9)
          rows, apex = [1, 2, 3, 2, 1], t.width * 0.75 - 2 * Math.sqrt(3) * t.radius * 1.0003
        end
      end
      rows.each_with_index do |count, row|
        count.times do |column|
          balls << Ball.new(id: ids.shift, x: apex + row * Math.sqrt(3) * t.radius * 1.0003,
            y: t.height / 2 + (2 * column - count + 1) * t.radius * 1.0003)
        end
      end
      balls.each { |b| b.x = b.x.round(9); b.y = b.y.round(9) }.sort_by(&:id)
    end

    def setup(state, breaker: 0)
      state.merge!(balls: rack(state[:options], state[:rack_number] || 0), turn: breaker, breaker: breaker,
        phase: :playing, breaking: true, hand: snooker?(state) ? :d : :kitchen, groups: nil,
        fouls: Array.new(state[:racks].length, 0), choices: [], push_available: false, on: :red, break_points: 0,
        free_ball: false, decision: nil, miss_chain: 0, last: nil, last_shot: nil, undo: nil, ruling: {})
      engine(state[:options])&.setup(state)
    end

    def placement?(state, id, x, y)
      hand = state[:blackball_free] ? :baulk : state[:hand]
      return false unless id == cue_id(state) && hand && state[:choices].empty?
      t = table(state[:options])
      return false if state[:hand] == :d && !t.in_d?(x, y)
      return false if state[:hand] == :kitchen && x >= t.width / 4
      return false if hand == :baulk && x > t.baulk_line
      t.placement?(state[:balls], id, x, y, kitchen: state[:hand] == :kitchen)
    end

    def find_placement(state)
      t = table(state[:options])
      lower = state[:hand] == :d ? 4450 : (t.radius * 10_000).ceil
      upper = case state[:hand]
      when :d then 7370
      when :kitchen then (t.width / 4 * 10_000).ceil - 1
      when :baulk then (t.baulk_line * 10_000).floor
      else ((t.width - t.radius) * 10_000).floor
      end
      (lower..upper).each do |column|
        x = column / 10_000.0
        low, high = t.radius, t.height - t.radius
        if state[:hand] == :d
          half = Math.sqrt([0.292 ** 2 - (x - 0.737) ** 2, 0].max)
          low, high = t.height / 2 - half, t.height / 2 + half
        end
        cuts = [low, high]
        state[:balls].each do |b|
          radius = 2 * t.radius + 0.00001
          next unless b.id != cue_id(state) && b.on_table? && (b.x - x).abs <= radius
          half = Math.sqrt([radius ** 2 - (b.x - x) ** 2, 0].max)
          cuts.concat([b.y - half, b.y + half])
        end
        cuts.select { |y| y.between?(low, high) }.sort.each_cons(2) do |a, b|
          bottom, top = (a * 10_000).ceil, (b * 10_000).floor
          next if bottom > top
          row = (bottom + top) / 2
          return [column, row] if placement?(state, cue_id(state), x, row / 10_000.0)
        end
      end
      nil
    end

    def pot_ids(result); result.events.select { |e| e[:kind] == :pocket }.map { |e| e[:a] }; end
    def head_spot(state)
      return nil unless state[:hand] == :kitchen && !state[:breaking] && state[:choices].empty?
      targets = state[:balls].select { |b| b.on_table? && pool_targets(state).include?(b.id) }
      return nil if targets.empty? || targets.any? { |b| b.x >= table(state[:options]).width / 4 }
      targets.max_by { |b| [b.x, -b.id] }.id
    end
    def first_contacts(result, cue_id: 0)
      contacts = result.events.select { |e| e[:kind] == :ball && (e[:a] == cue_id || e[:b] == cue_id) }
      return [] if contacts.empty?
      contacts.take_while { |e| (e[:t] - contacts.first[:t]).abs < 1e-8 }.map { |e| e[:a] == cue_id ? e[:b] : e[:a] }.uniq
    end

    # Spot along the centre line without moving an existing ball. Use circle
    # intersections rather than an arbitrary grid which may miss a narrow gap.
    def line_spot(balls, id, x, y, t, forward: true, touching: false)
      radius = 2 * t.radius + (touching ? 1e-8 : 0.00002)
      blocked = balls.select { |b| b.on_table? && b.id != id && (b.y - y).abs < radius }.map do |b|
        reach = Math.sqrt(radius ** 2 - (b.y - y) ** 2)
        [b.x - reach, b.x + reach]
      end
      candidate = x
      blocked.sort_by { |a, b| forward ? a : -b }.each do |a, b|
        candidate = forward ? b + 1e-8 : a - 1e-8 if candidate.between?(a, b)
      end
      return nil unless candidate.between?(t.radius, t.width - t.radius)
      [candidate, y]
    end

    def spot_pool(state, id)
      t = table(state[:options])
      x, y = line_spot(state[:balls], id, t.width * 0.75, t.height / 2, t, touching: true) ||
        line_spot(state[:balls], id, t.width * 0.75, t.height / 2, t, forward: false, touching: true)
      raise Physics::LimitExceeded, 'No space to spot the ball' unless x
      b = state[:balls].find { |ball| ball.id == id }
      b.x, b.y, b.status = x, y, :table
    end
  end
end

require_relative 'pool'
require_relative 'snooker'
require_relative 'engines'
