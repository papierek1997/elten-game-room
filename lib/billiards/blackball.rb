require_relative 'rules'
require_relative 'visibility'

module GameRoomBilliards
  module Blackball
    module_function
    def rack(options, number)
      t = Rules.table(options)
      random = Random.new(options.fetch('rack_seed', 0) + number)
      groups = [(1..7).to_a, (9..15).to_a].map { |ids| GameRoomRandom.shuffle(ids, random: random) }
      # WPA8.4 diagram, read from apex to base; the black is on the Foot Spot.
      pattern = [[0], [1, 0], [0, nil, 1], [1, 0, 1, 0], [0, 1, 1, 0, 1]]
      balls = [Ball.new(id: 0, x: t.baulk_line - 0.1, y: t.height / 2)]
      pattern.each_with_index do |row, depth|
        row.each_with_index do |group, column|
          balls << Ball.new(id: group.nil? ? 8 : groups[group].shift,
            x: t.width * 0.75 + (depth - 2) * Math.sqrt(3) * t.radius * 1.0003,
            y: t.height / 2 + (2 * column - row.length + 1) * t.radius * 1.0003)
        end
      end
      balls.sort_by(&:id)
    end
    def setup(state); state[:hand], state[:blackball_free] = :baulk, false; end
    def cue_id(_state); 0; end
    def points?; false; end
    def uses_calls?; false; end
    def choose(_state, _choice); false; end
    def targets(state)
      ids = state[:balls].select { |b| b.on_table? && b.id != 0 }.map(&:id)
      return ids if state[:blackball_free]
      return ids - [8] unless state[:groups]
      own = ids.select { |id| Rules.group(id) == state[:groups][state[:turn]] }
      own.empty? ? [8] : own
    end
    def declaration?(_state, data); data['cue'] == 0 && data['call'] == 0 && data['mode'] == 0; end
    def touching(state)
      cue, r = state[:balls].first, Rules.table(state[:options]).radius
      state[:balls].select { |b| b.id != 0 && b.on_table? && Math.hypot(b.x - cue.x, b.y - cue.y) <= 2 * r + 1e-7 }
    end
    def foul(before, result, data)
      return :scratch if Rules.pot_ids(result).include?(0)
      return :off_table if result.events.any? { |e| e[:kind] == :off }
      cue, on = before[:balls].first, targets(before)
      dx, dy = Geometry.direction(Physics.launch_angle(data['shot']))
      frozen = touching(before)
      return :push if frozen.any? { |b| (b.x - cue.x) * dx + (b.y - cue.y) * dy > 1e-9 }
      first = frozen.select { |b| on.include?(b.id) }.map(&:id)
      first = Rules.first_contacts(result) if first.empty?
      return :no_contact if first.empty?
      return :wrong_first if (first & on).empty?
      if before[:breaking]
        crossed = result.events.select { |e| e[:kind] == :crossing && e[:line] == :middle && e[:a] != 0 }.map { |e| e[:a] }.uniq
        return :break_spread if (Rules.pot_ids(result) - [0]).empty? && crossed.length < 2
      else
        index = if frozen.any? { |b| on.include?(b.id) }
          -1
        else
          result.events.index { |e| e[:kind] == :ball && [e[:a], e[:b]].include?(0) } || -1
        end
        rail = result.events.drop(index + 1).any? { |e| e[:kind] == :rail || e[:kind] == :pocket && e[:a] != 0 }
        return :no_rail unless rail || !Visibility.direct?(Rules.table(before[:options]), before[:balls], on)
        if before[:groups]
          groups = (Rules.pot_ids(result) - [0, 8]).map { |id| Rules.group(id) }
          own = before[:groups][before[:turn]]
          return :wrong_pot if groups.include?(1 - own) && !groups.include?(own)
        end
      end
      nil
    end
    def resolve(state, before, result, data)
      actor, pots = before[:turn], Rules.pot_ids(result)
      if before[:breaking] && pots.include?(8)
        Rules.setup(state, breaker: actor)
        state[:ruling] = {notice: :black_break}
        return
      end
      fault = foul(before, result, data)
      state[:ruling], state[:hand], state[:breaking] = {foul: fault}, nil, false
      if pots.include?(8)
        left = state[:balls].any? { |b| b.on_table? && before[:groups] && Rules.group(b.id) == before[:groups][actor] }
        win = !fault && before[:groups] && !left
        state[:ruling][:foul] ||= :early_eight unless win
        return Rules.finish_rack(state, win ? actor : 1 - actor)
      end
      if fault
        state[:turn], state[:hand], state[:blackball_free] = 1 - actor, state[:balls].first.on_table? ? nil : :baulk, true
      else
        state[:blackball_free] = false
        unless before[:breaking] || before[:blackball_free] || state[:groups]
          groups = (pots - [0, 8]).map { |id| Rules.group(id) }.uniq
          state[:groups] = actor.zero? ? [groups.first, 1 - groups.first] : [1 - groups.first, groups.first] if groups.length == 1
        end
        state[:turn] = 1 - actor if pots.empty? && !before[:blackball_free]
      end
      outside = result.events.select { |e| e[:kind] == :off && e[:a] != 0 }.map { |e| e[:a] }.uniq
      group = state[:groups] && state[:groups][state[:turn]]
      outside.sort_by { |id| [id == 8 ? 0 : Rules.group(id) == (group || 0) ? 1 : 2, id] }.each { |id| Rules.spot_pool(state, id) }
    end
  end
  Rules.register_engine('blackball', Blackball)
end
