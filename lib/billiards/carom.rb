require_relative 'rules'

module GameRoomBilliards
  # UMB World Rules, articles 23–29, 51–61 and 82–83; appendix A/B/F.
  module Carom
    module_function

    def rack(options, _number)
      t = Rules.table(options)
      [Ball.new(id: 0, x: t.width / 4, y: t.height / 2 - 0.1825),
       Ball.new(id: 1, x: t.width / 4, y: t.height / 2),
       Ball.new(id: 2, x: t.width * 0.75, y: t.height / 2)]
    end

    def setup(state)
      state.merge!(scores: [0, 0], hand: nil, break_points: 0,
        carom_innings: [0, 0], carom_visit_started: false, carom_equalizing: false,
        carom_zone: nil, carom_zone_state: nil)
      initial_position(state)
    end

    def cue_id(state); state[:turn]; end
    def targets(state); state[:balls].select { |b| b.on_table? && b.id != cue_id(state) }.map(&:id); end
    def uses_calls?; false; end
    def points?; true; end
    def declaration?(state, data)
      state[:choices].empty? && data['mode'] == 0 && data['call'] == 0 && data['cue'] == cue_id(state)
    end

    def ordered(result)
      result.events.each_with_index.sort_by { |(event, index)| [event[:t], event.fetch(:order, index)] }.map(&:first)
    end

    def place(ball, x, y)
      ball.x, ball.y, ball.status = x, y, :table
      ball.vx = ball.vy = ball.wx = ball.wy = ball.wz = 0.0
    end

    def initial_position(state)
      t, actor = Rules.table(state[:options]), state[:turn]
      place(state[:balls].find { |b| b.id == 2 }, t.width * 0.75, t.height / 2)
      place(state[:balls].find { |b| b.id == 1 - actor }, t.width / 4, t.height / 2)
      place(state[:balls].find { |b| b.id == actor }, t.width / 4, t.height / 2 - 0.1825)
      state[:breaking], state[:hand] = true, nil
      state[:carom_zone], state[:carom_zone_state] = nil, nil
      state[:decision], state[:choices] = :carom_start, %w[carom_start_left carom_start_right]
    end

    def replace_three_cushion(state, ids)
      t, actor = Rules.table(state[:options]), state[:turn]
      spots = {2=>[t.width * 0.75, t.height / 2], actor=>[t.width / 4, t.height / 2],
        (1 - actor)=>[t.width / 2, t.height / 2]}
      # Remove affected balls first, so none obstructs another ball's own spot.
      state[:balls].each { |ball| ball.status = :potted if ids.include?(ball.id) }
      ids.each do |id|
        destination = id
        visited = []
        loop do
          raise Physics::LimitExceeded, 'Cyclic carom replacement spots' if visited.include?(destination)
          visited << destination
          x, y = spots.fetch(destination)
          blocker = state[:balls].find do |ball|
            ball.on_table? && Math.hypot(ball.x - x, ball.y - y) <= 2 * t.radius + 1e-8
          end
          unless blocker
            place(state[:balls].find { |ball| ball.id == id }, x, y)
            break
          end
          destination = blocker.id
        end
      end
    end

    def choose(state, choice)
      case choice
      when 'carom_start_left', 'carom_start_right'
        return false unless state[:decision] == :carom_start
        t = Rules.table(state[:options])
        ball = state[:balls].find { |b| b.id == cue_id(state) }
        place(ball, t.width / 4, t.height / 2 + (choice == 'carom_start_left' ? -0.1825 : 0.1825))
      when 'carom_play_away'
        return false unless state[:decision] == :carom_touching
      when 'carom_respot'
        return false unless state[:decision] == :carom_touching
        ids = [cue_id(state)] + touching(state)
        if state[:options]['discipline'] == 'three_cushion'
          replace_three_cushion(state, ids)
        else
          initial_position(state)
          return true
        end
      else return false
      end
      state[:decision], state[:choices] = nil, []
      true
    end

    def touching(state)
      cue = state[:balls].find { |b| b.id == cue_id(state) }
      radius = Rules.table(state[:options]).radius
      state[:balls].select do |ball|
        ball.id != cue.id && ball.on_table? && Math.hypot(ball.x - cue.x, ball.y - cue.y) <= 2 * radius + 1e-7
      end.map(&:id)
    end

    def zone(state)
      t, objects = Rules.table(state[:options]), state[:balls].reject { |b| b.id == cue_id(state) }
      (0..3).find { |area| objects.all? { |b| t.inside_zone?(b.x, b.y, area) } }
    end

    def foul(before, events, data)
      actor, t = cue_id(before), Rules.table(before[:options])
      return :off_table if events.any? { |e| e[:kind] == :off }
      cue = before[:balls].find { |b| b.id == actor }
      dx, dy = Geometry.direction(Physics.launch_angle(data.fetch('shot')))
      return :push if touching(before).any? do |id|
        ball = before[:balls].find { |b| b.id == id }
        (ball.x - cue.x) * dx + (ball.y - cue.y) * dy > 1e-9
      end
      return :frozen_cushion if (cue.x <= t.radius + 1e-7 && dx < -1e-9) ||
        (cue.x >= t.width - t.radius - 1e-7 && dx > 1e-9) ||
        (cue.y <= t.radius + 1e-7 && dy < -1e-9) ||
        (cue.y >= t.height - t.radius - 1e-7 && dy > 1e-9)
      if before[:breaking]
        first = events.find { |e| (e[:kind] == :ball || e[:kind] == :rail) && (e[:a] == actor || e[:b] == actor) }
        return :opening_contact unless first && first[:kind] == :ball && [first[:a], first[:b]].include?(2)
      end
      nil
    end

    def resolve(state, before, result, data)
      state[:carom_innings] = state[:carom_innings].dup
      actor, events = cue_id(before), ordered(result)
      unless state[:carom_visit_started]
        state[:carom_innings][actor] += 1
        state[:carom_visit_started] = true
      end
      foul = foul(before, events, data)
      rails, contacts = 0, []
      events.each do |event|
        rails += 1 if event[:kind] == :rail && event[:a] == actor
        next unless event[:kind] == :ball && [event[:a], event[:b]].include?(actor)
        contacts |= [event[:a] == actor ? event[:b] : event[:a]]
        break if contacts.length == 2
      end
      required = {'carom'=>0, 'one_cushion'=>1, 'three_cushion'=>3}.fetch(state[:options]['discipline'])
      point = contacts.length == 2 && rails >= required
      foul ||= :insufficient_cushions if contacts.length == 2 && rails < required
      old_zone = before[:carom_zone] || (zone(before) if state[:options]['discipline'] == 'carom')
      escaped = events.any? { |e| e[:kind] == :zone_exit && e[:zone] == old_zone && e[:a] != actor }
      if state[:options]['discipline'] == 'carom' && old_zone && before[:carom_zone_state] == :inside && !escaped && point
        foul ||= :zone_limit
      end
      state[:ruling], state[:breaking], state[:hand] = {foul: foul, points: 0}, false, nil
      if !foul && point
        state[:scores][actor] += 1
        state[:break_points] += 1
        state[:ruling][:points] = 1
        if state[:scores][actor] >= state[:options].fetch('point_target', 30)
          return finish_or_equalize(state, actor)
        end
        if state[:options]['discipline'] == 'carom'
          area = zone(state)
          state[:carom_zone], state[:carom_zone_state] = area,
            (area ? (area == old_zone && !escaped ? :inside : :entered) : nil)
        end
      else
        return Rules.finish_rack(state, state.fetch(:carom_equalizing_winner)) if state[:carom_equalizing]
        state[:turn], state[:break_points], state[:carom_visit_started] = 1 - actor, 0, false
        state[:carom_zone], state[:carom_zone_state] = nil, nil
      end
      outside = events.select { |e| e[:kind] == :off }.map { |e| e[:a] }.uniq
      unless outside.empty?
        return initial_position(state) unless state[:options]['discipline'] == 'three_cushion'
        replace_three_cushion(state, outside)
      end
      prepare_touching(state)
    end

    def finish_or_equalize(state, actor)
      return Rules.finish_draw_rack(state) if state[:carom_equalizing]
      opponent = 1 - actor
      if state[:options].fetch('equalizing', true) && actor == state[:breaker] &&
          state[:carom_innings][actor] > state[:carom_innings][opponent]
        state[:carom_equalizing], state[:carom_equalizing_winner] = true, actor
        state[:turn], state[:break_points], state[:carom_visit_started] = opponent, 0, false
        state[:ruling][:notice] = :equalizing_inning
        initial_position(state)
      else
        Rules.finish_rack(state, actor)
      end
    end

    def prepare_touching(state)
      return if touching(state).empty?
      if state[:options]['discipline'] == 'carom'
        initial_position(state)
      else
        state[:decision], state[:choices] = :carom_touching, %w[carom_play_away carom_respot]
      end
    end
  end
  %w[carom one_cushion three_cushion].each { |id| Rules.register_engine(id, Carom) }
end
