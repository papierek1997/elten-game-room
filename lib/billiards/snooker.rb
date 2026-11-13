require_relative 'visibility'

module GameRoomBilliards
  module Rules
    module_function

    def next_colour(balls); balls.select { |b| b.on_table? && b.id >= 16 }.map(&:id).min; end
    def snooker_targets(state)
      case state[:on]
      when :red then reds(state[:balls]).map(&:id)
      when :colour then state[:balls].select { |b| b.on_table? && b.id >= 16 }.map(&:id)
      else [state[:on]].compact
      end
    end
    def snooker_declaration?(state, data)
      return false unless [0, 3].include?(data['mode'])
      on = snooker_targets(state)
      return on.include?(data['call']) if data['mode'] == 0
      state[:free_ball] && !on.include?(data['call']) && state[:balls].any? { |b| b.id == data['call'] && b.id != 0 && b.on_table? }
    end

    def spot_colours(state, ids)
      t = table(state[:options])
      spots = colour_spots(t)
      ids.sort.reverse_each do |id|
        x, y = ([spots.fetch(id)] + spots.sort.reverse.map(&:last)).find { |a, b| t.placement?(state[:balls], id, a, b) } ||
          line_spot(state[:balls], id, *spots.fetch(id), t) ||
          (id >= 20 ? line_spot(state[:balls], id, *spots.fetch(id), t, forward: false) : nil)
        raise Physics::LimitExceeded, 'No space to spot a colour' unless x
        ball = state[:balls].find { |b| b.id == id }
        ball.x, ball.y, ball.status = x, y, :table
      end
    end

    def remaining_points(state)
      count = reds(state[:balls]).length
      return count * 8 + 27 + (state[:on] == :colour ? 7 : 0) if count > 0 || state[:on] == :colour
      state[:balls].select { |b| b.on_table? && b.id >= 16 }.sum { |b| value(b.id) }
    end

    def snooker_shot(state, before, result, data)
      actor, t = state[:turn], table(state[:options])
      on = snooker_targets(before)
      expected = before[:on] == :colour ? [data['call']] : on
      expected = [data['call']] if data['mode'] == 3
      pots, first = pot_ids(result), first_contacts(result)
      touching = before[:balls].select do |b|
        b.id != 0 && b.on_table? && expected.include?(b.id) &&
          Math.hypot(b.x - before[:balls].first.x, b.y - before[:balls].first.y) <= 2 * t.radius + 1e-7
      end
      dx, dy = Geometry.direction(Physics.launch_angle(data.fetch('shot')))
      push = touching.any? { |b| (b.x - before[:balls].first.x) * dx + (b.y - before[:balls].first.y) * dy > 1e-9 }
      hit = !push && (!touching.empty? || !first.empty? && (first - expected - (data['mode'] == 3 ? on : [])).empty? && !(first & expected).empty?)
      permitted_pots = expected + (data['mode'] == 3 ? on : [])
      bad_pots = (pots - [0]) - permitted_pots
      foul = if push then :push
      elsif pots.include?(0) then :scratch
      elsif !hit then first.empty? ? :no_contact : :wrong_first
      elsif !bad_pots.empty? then :wrong_pot
      end
      if !foul && data['mode'] == 3 && (pots - [0]).empty? && state[:balls].count(&:on_table?) > 3
        free = state[:balls].find { |b| b.id == data['call'] }
        only_blocker = state[:balls].select { |b| b.id == 0 || on.include?(b.id) || b.equal?(free) }
        foul = :free_ball_snooker if Visibility.snookered?(t, only_blocker, on)
      end
      ball_on_value = before[:on] == :red ? 1 : (before[:on] == :colour ? value(data['call']) : value(before[:on]))
      ball_on_value = value(on.first) if data['mode'] == 3
      penalty = ([4, ball_on_value] + (bad_pots + (hit ? [] : first)).map { |id| value(id) }).max
      state[:ruling], state[:hand], state[:free_ball] = {foul: foul, points: foul ? penalty : 0}, nil, false
      state[:breaking] = false
      clear_phase = before[:on].is_a?(Integer)
      colours_to_spot = pots.select { |id| id >= 16 && (foul || !clear_phase || data['mode'] == 3 && id == data['call']) }
      spot_colours(state, colours_to_spot)
      if foul
        state[:scores][1 - actor] += penalty
        state[:hand] = :d if pots.include?(0)
        return snooker_foul_decision(state, before, hit: hit, push: push)
      end
      state[:miss_chain], state[:restore] = 0, nil
      scored_pots = pots - [0]
      points = if data['mode'] == 3
        regular = scored_pots & on
        if before[:on] == :red
          regular.length + (scored_pots.include?(data['call']) ? 1 : 0)
        else
          scored_pots.empty? ? 0 : ball_on_value
        end
      else
        scored_pots.sum { |id| value(id) }
      end
      state[:scores][actor] += points
      state[:break_points] += points
      if before[:on] == 21 && points > 0
        return snooker_frame_end(state)
      end
      if points > 0
        state[:on] = before[:on] == :red ? :colour : (reds(state[:balls]).empty? ? next_colour(state[:balls]) : :red)
        # A free ball replacing a final colour does not remove that colour.
        state[:on] = before[:on] if clear_phase && data['mode'] == 3 && (scored_pots & on).empty?
      else
        state[:turn], state[:break_points] = 1 - actor, 0
        state[:on] = reds(state[:balls]).empty? ? next_colour(state[:balls]) : :red
      end
      snooker_frame_end(state) if state[:on] == 21 && (state[:scores][0] - state[:scores][1]).abs > 7
    end

    def snooker_foul_decision(state, before, hit:, push:)
      actor, t = before[:turn], table(state[:options])
      state[:break_points], state[:turn] = 0, 1 - actor
      state[:on] = reds(state[:balls]).empty? ? next_colour(state[:balls]) : :red
      return snooker_frame_end(state) if before[:on] == 21
      on = snooker_targets(before)
      visible = Visibility.direct?(t, before[:balls], on)
      full = Visibility.direct?(t, before[:balls], on, full: true)
      enough = (before[:scores][0] - before[:scores][1]).abs <= remaining_points(before) &&
        (state[:scores][0] - state[:scores][1]).abs <= remaining_points(state)
      # shortcut: intent on an entirely obstructed shot needs a human referee;
      # award automatic Miss only on a direct path, until referee support exists.
      miss = !hit && !push && visible && (enough || full && before[:miss_chain] > 0)
      state[:ruling][:miss] = miss
      if miss && full && before[:miss_chain] >= 2
        state[:ruling][:foul] = :third_miss
        return finish_rack(state, 1 - actor)
      end
      state[:choices] = %w[accept return] + (miss ? ['restore'] : [])
      state[:decision] = :snooker_foul
      state[:restore] = {balls: before[:balls].map(&:dup), on: before[:on], hand: before[:hand], actor: actor,
        chain: full ? before[:miss_chain] + 1 : 0} if miss
      state[:free_ball] = if state[:hand]
        Visibility.d_snookered?(t, state[:balls], snooker_targets(state))
      else
        Visibility.snookered?(t, state[:balls], snooker_targets(state))
      end
    end

    def restore_snooker(state)
      saved = state.fetch(:restore)
      state[:balls], state[:on], state[:hand], state[:turn] = saved[:balls].map(&:dup), saved[:on], saved[:hand], saved[:actor]
      state[:miss_chain], state[:free_ball] = saved[:chain], false
      state[:restore] = nil
    end

    def snooker_frame_end(state)
      if state[:scores][0] == state[:scores][1]
        spot_colours(state, [21]) unless state[:balls].find { |b| b.id == 21 }.on_table?
        state[:balls].first.status = :potted
        state[:on], state[:hand] = 21, :d
        state[:turn] = Random.new(state[:options].fetch('rack_seed', 0) + state[:rack_number]).rand(2)
        state[:choices], state[:decision], state[:free_ball] = %w[accept return], :respotted_black, false
      else
        finish_rack(state, state[:scores][0] > state[:scores][1] ? 0 : 1)
      end
    end
  end
end
