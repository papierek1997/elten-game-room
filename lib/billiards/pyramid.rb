require_relative 'rules'

module GameRoomBilliards
  # IPC September 2025: General Pyramid 6, 13, 19, 20, 25 and Free Pyramid.
  module Pyramid
    module_function

    def rack(options, _number)
      t = Rules.table(options)
      balls = [Ball.new(id: 0, x: t.width / 4 - 0.1, y: t.height / 2)]
      5.times do |row|
        (row + 1).times do |column|
          balls << Ball.new(id: balls.length, x: t.width * 0.75 + row * Math.sqrt(3) * t.radius * 1.0003,
            y: t.height / 2 + (2 * column - row) * t.radius * 1.0003)
        end
      end
      balls
    end

    def setup(state)
      state.merge!(scores: [0, 0], pyramid_scored: [[], []], pyramid_cue: 0,
        pyramid_foul_break: false, breaking: true, hand: :kitchen)
    end
    def cue_id(state); state.fetch(:pyramid_cue, 0); end
    def targets(state); state[:balls].select { |b| b.on_table? && b.id != cue_id(state) }.map(&:id); end
    def uses_calls?; false; end
    def points?; true; end
    def declaration?(state, data)
      data['mode'] == 0 && data['call'] == 0 &&
        state[:balls].any? { |b| b.id == data['cue'] && b.on_table? } &&
        (!state[:breaking] || data['cue'] == 0)
    end

    def ordered(result)
      result.events.each_with_index.sort_by { |event, i| [event[:t], event.fetch(:order, i)] }.map(&:first)
    end

    def position(event, id, balls)
      ball = balls.find { |b| b.id == id }
      id == event[:a] ? [event.fetch(:x, ball.x), event.fetch(:y, ball.y)] :
        [event.fetch(:bx, ball.x), event.fetch(:by, ball.y)]
    end

    def rail_at(x, y, table)
      {left: x, right: table.width - x, bottom: y, top: table.height - y}.
        select { |_, distance| distance <= table.radius + 1e-6 }.keys
    end

    def legal_completion?(before, events, cue)
      first = events.index { |e| e[:kind] == :ball && [e[:a], e[:b]].include?(cue) }
      return false unless first
      trail = events.drop(first + 1)
      return true if trail.any? { |e| e[:kind] == :pocket }
      t = Rules.table(before[:options])
      marks = before[:balls].to_h { |b| [b.id, {crossed: false, rails: {}}] }
      trail.each do |event|
        mark = marks.fetch(event[:a])
        if event[:kind] == :rail
          name = event.fetch(:cushion, event[:rail])
          return true if mark[:crossed] || mark[:rails].keys.any? { |rail, _half| rail != name }
          half = event.fetch(:x, before[:balls].find { |b| b.id == event[:a] }.x) < t.width / 2 ? :left : :right
          mark[:rails][[name, half]] = true
        elsif event[:kind] == :crossing && event[:line] == :middle
          return true unless mark[:rails].empty?
          mark[:crossed] = true
        elsif event[:kind] == :ball
          return true if collision_completes?(event, marks, before[:balls], t)
          a, b = marks.values_at(event[:a], event[:b])
          shared = {crossed: a[:crossed] || b[:crossed], rails: a[:rails].merge(b[:rails])}
          marks[event[:a]], marks[event[:b]] = Marshal.load(Marshal.dump(shared)), shared
        end
      end
      false
    end

    def collision_completes?(event, marks, balls, table)
      [[event[:a], event[:b]], [event[:b], event[:a]]].any? do |source, target|
        mark, (x, y) = marks.fetch(source), position(event, target, balls)
        rails = rail_at(x, y, table)
        (mark[:crossed] && !rails.empty?) ||
          mark[:rails].keys.any? do |rail, half|
            rails.any? { |other| other != rail } || (half == :left ? x >= table.width / 2 : x <= table.width / 2)
          end
      end
    end

    def foul(before, result, data)
      events, cue = ordered(result), data.fetch('cue')
      return :off_table if events.any? { |e| e[:kind] == :off }
      contacts = Rules.first_contacts(result, cue_id: cue)
      return :no_contact if contacts.empty?
      # The planar cue has no adjustable elevation; a frozen forward push is refused.
      ball, t = before[:balls].find { |b| b.id == cue }, Rules.table(before[:options])
      dx, dy = Geometry.direction(Physics.launch_angle(data.fetch('shot')))
      return :push if before[:balls].any? do |other|
        other.id != cue && other.on_table? && Math.hypot(other.x - ball.x, other.y - ball.y) <= 2 * t.radius + 1e-7 &&
          (other.x - ball.x) * dx + (other.y - ball.y) * dy > 1e-9 && data['shot']['top'] >= 0
      end
      if before[:breaking]
        index = events.index { |e| e[:kind] == :ball && [e[:a], e[:b]].include?(cue) }
        after = events.drop(index + 1)
        rails = after.select { |e| e[:kind] == :rail && e[:a] != cue }.map { |e| e[:a] }.uniq
        crossed = after.any? { |e| e[:kind] == :crossing && e[:a] != cue && e[:line] == :middle }
        return :break_spread unless after.any? { |e| e[:kind] == :pocket } || rails.length >= 3 || rails.length >= 2 && crossed
      else
        return :pyramid_completion unless legal_completion?(before, events, cue)
      end
      nil
    end

    def spot(state, id)
      t = Rules.table(state[:options])
      position = Rules.line_spot(state[:balls], id, t.width * 0.75, t.height / 2, t) ||
        Rules.line_spot(state[:balls], id, t.width * 0.75, t.height / 2, t, forward: false)
      raise Physics::LimitExceeded, 'No space to spot pyramid ball' unless position
      ball = state[:balls].find { |b| b.id == id }
      ball.x, ball.y, ball.status = *position, :table
      ball.vx = ball.vy = ball.wx = ball.wy = ball.wz = 0.0
    end

    def resolve(state, before, result, data)
      actor, pots = before[:turn], Rules.pot_ids(result).uniq
      penalty = foul(before, result, data)
      state[:ruling], state[:hand] = {foul: penalty, points: 0}, nil
      state[:pyramid_cue] = data.fetch('cue')
      state[:pyramid_scored] = before[:pyramid_scored].map(&:dup)
      if penalty
        (pots + result.events.select { |e| e[:kind] == :off }.map { |e| e[:a] }).uniq.sort.each { |id| spot(state, id) }
        state[:turn], state[:pyramid_foul_break] = 1 - actor, before[:breaking]
        state[:decision] = :pyramid_penalty
        state[:choices] = state[:balls].select(&:on_table?).map { |b| "pyramid_penalty_#{b.id}" }
      else
        state[:pyramid_scored][actor].concat(pots)
        state[:scores][actor] += pots.length
        return Rules.finish_rack(state, actor) if state[:scores][actor] >= 8
        state[:turn] = 1 - actor if pots.empty?
      end
      state[:breaking] = false
      select_available_cue(state)
    end

    def select_available_cue(state)
      current = state[:balls].find { |b| b.id == cue_id(state) }
      state[:pyramid_cue] = state[:balls].select(&:on_table?).map(&:id).min unless current&.on_table?
    end

    def partial_rack(state)
      t, balls = Rules.table(state[:options]), state[:balls]
      coloured = balls.find { |b| b.id == 0 }
      unless coloured.on_table?
        replacement = balls.find { |b| b.id != 0 && b.on_table? }
        owner = state[:pyramid_scored].index { |ids| ids.include?(0) }
        raise Physics::LimitExceeded, 'Missing coloured pyramid ball owner' unless replacement && owner
        state[:pyramid_scored][owner] = state[:pyramid_scored][owner].map { |id| id == 0 ? replacement.id : id }
        replacement.status, coloured.status = :potted, :table
      end
      ids = balls.select { |b| b.id != 0 && b.on_table? }.map(&:id).sort
      rows, remaining = [], ids.length
      1.upto(5) do |width|
        count = [width, remaining].min
        rows << [width, count]
        remaining -= count
        break if remaining.zero?
      end
      if rows.last[1] % 2 != rows.last[0] % 2 && rows.length > 1
        rows[0][1] -= 1
        rows[-1][1] += 1
      end
      rows.each_with_index do |(width, count), row|
        slots = (0...width).map { |column| 2 * column - width + 1 }.sort_by { |offset| [offset.abs, offset] }.first(count).sort
        slots.each do |offset|
          id = ids.shift
          ball = balls.find { |b| b.id == id }
          ball.x, ball.y = t.width * 0.75 + row * Math.sqrt(3) * t.radius * 1.0003,
            t.height / 2 + offset * t.radius * 1.0003
        end
      end
      coloured.x, coloured.y = t.width / 4 - 0.1, t.height / 2
      state[:pyramid_cue], state[:breaking], state[:hand] = 0, true, :kitchen
    end

    def choose(state, choice)
      if state[:decision] == :pyramid_penalty && state[:choices].include?(choice)
        id = Integer(choice.delete_prefix('pyramid_penalty_'), 10)
        state[:balls].find { |b| b.id == id }.status = :potted
        state[:pyramid_scored] = state[:pyramid_scored].map(&:dup)
        state[:pyramid_scored][state[:turn]] << id
        state[:scores][state[:turn]] += 1
        state[:ruling][:points] = 1
        return Rules.finish_rack(state, state[:turn]) || true if state[:scores][state[:turn]] >= 8
        state[:decision] = :pyramid_after_foul
        state[:choices] = state[:pyramid_foul_break] ? %w[pyramid_accept pyramid_return pyramid_rack_self pyramid_rack_other] : %w[pyramid_accept pyramid_return]
        select_available_cue(state)
        return true
      end
      return false unless state[:decision] == :pyramid_after_foul && state[:choices].include?(choice)
      state[:turn] = 1 - state[:turn] if %w[pyramid_return pyramid_rack_other].include?(choice)
      partial_rack(state) if %w[pyramid_rack_self pyramid_rack_other].include?(choice)
      state[:choices], state[:decision], state[:pyramid_foul_break] = [], nil, false
      true
    end
  end
  Rules.register_engine('pyramid', Pyramid)
end
