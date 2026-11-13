require_relative 'rules'

module GameRoomBilliards
  # WPBSA September 2024, English Billiards sections 2 and 3.
  module EnglishBilliards
    module_function

    def rack(options, _number)
      t = Rules.table(options)
      [Ball.new(id: 0, x: 0.55, y: t.height / 2),
       Ball.new(id: 1, x: 0.55, y: t.height / 2, status: :potted),
       Ball.new(id: 2, x: t.width - 0.324, y: t.height / 2)]
    end

    def setup(state)
      t, actor = Rules.table(state[:options]), state[:turn]
      state[:balls].each do |ball|
        if ball.id < 2
          ball.x, ball.y, ball.status = 0.55, t.height / 2, ball.id == actor ? :table : :potted
        end
      end
      state.merge!(scores: [0, 0], hand: :d, breaking: false, break_points: 0,
        english_cannons: 0, english_hazards: 0, english_red_run: 0,
        english_red_spot: :spot, english_off_by: [nil, nil], english_baulk_window: 0,
        english_baulk_crossed: false, english_expired: false)
    end

    def cue_id(state); state[:turn]; end
    def targets(state); state[:balls].select { |b| b.on_table? && b.id != cue_id(state) }.map(&:id); end
    def uses_calls?; false; end
    def points?; true; end
    def declaration?(state, data)
      state[:choices].empty? && data['call'] == 0 && data['mode'] == 0 && data['cue'] == cue_id(state)
    end

    def ordered(result)
      result.events.each_with_index.sort_by { |(event, index)| [event[:t], event.fetch(:order, index)] }.map(&:first)
    end

    def place(ball, x, y)
      ball.x, ball.y, ball.status = x, y, :table
      ball.vx = ball.vy = ball.wx = ball.wy = ball.wz = 0.0
    end

    def spot_red(state, preferred = :spot)
      t = Rules.table(state[:options])
      spots = {spot: [t.width - 0.324, t.height / 2], pyramid: [t.width * 0.75, t.height / 2],
        centre: [t.width / 2, t.height / 2]}
      order = preferred == :centre ? %i[centre pyramid spot] : %i[spot pyramid centre]
      key = order.find { |name| t.placement?(state[:balls], 2, *spots.fetch(name)) }
      raise Physics::LimitExceeded, 'No available English billiards red spot' unless key
      place(state[:balls].find { |b| b.id == 2 }, *spots.fetch(key))
      state[:english_red_spot] = preferred == :centre && key == :spot ? nil : key
    end

    def reset_objects(state, force_opponent: false)
      actor, t = cue_id(state), Rules.table(state[:options])
      cue = state[:balls].find { |b| b.id == actor }
      opponent = state[:balls].find { |b| b.id == 1 - actor }
      present = force_opponent || opponent.on_table?
      cue.status = :potted
      opponent.status = :potted
      spot_red(state)
      place(opponent, t.width / 2, t.height / 2) if present
      state[:hand], state[:english_red_run] = :d, 0
      state[:english_off_by][actor] = actor
    end

    def choose(state, choice)
      return false unless state[:decision] == :english_foul
      case choice
      when 'english_accept' then prepare_next(state)
      when 'english_reset' then reset_objects(state, force_opponent: true)
      else return false
      end
      state[:decision], state[:choices] = nil, []
      true
    end

    def target_x(event, actor, before)
      return event[:bx] || before[:balls].find { |b| b.id == event[:b] }.x if event[:a] == actor
      event[:x] || before[:balls].find { |b| b.id == event[:a] }.x
    end

    def in_hand_foul(before, events)
      return nil unless before[:hand] == :d
      t, actor = Rules.table(before[:options]), cue_id(before)
      line = t.baulk_line
      cue = before[:balls].find { |b| b.id == actor }
      return :baulk_play unless t.in_d?(cue.x, cue.y)
      out_contact = false
      events.each do |event|
        if event[:kind] == :rail && event[:a] == actor
          out_contact = true if event.fetch(:x, cue.x) > line
        elsif event[:kind] == :ball && [event[:a], event[:b]].include?(actor)
          if target_x(event, actor, before) > line
            out_contact = true
          elsif !out_contact
            return :baulk_play
          end
        end
      end
      out_contact
    end

    def running_coup?(before, events, cue_pot)
      return false unless before[:hand] == :d && cue_pot
      t, actor = Rules.table(before[:options]), cue_id(before)
      return false unless targets(before).all? { |id| before[:balls].find { |b| b.id == id }.x <= t.baulk_line }
      events.select { |e| e[:kind] == :rail && e[:a] == actor }.all? do |event|
        next false unless event[:rail] == :jaw
        nearest = t.pockets.each_index.min_by do |index|
          Math.hypot(t.pockets[index][0] - event.fetch(:x), t.pockets[index][1] - event.fetch(:y))
        end
        nearest == cue_pot[:pocket]
      end
    end

    def resolve(state, before, result, data)
      state[:english_off_by] = state[:english_off_by].dup
      actor, events = cue_id(before), ordered(result)
      contacts = events.select { |e| e[:kind] == :ball && [e[:a], e[:b]].include?(actor) }
      ids = contacts.map { |e| e[:a] == actor ? e[:b] : e[:a] }.uniq
      pots = Rules.pot_ids(result)
      cue_pot = events.find { |e| e[:kind] == :pocket && e[:a] == actor }
      cannon = ids.include?(2) && ids.include?(1 - actor)
      # shortcut: substep-equal contacts are unresolved simultaneous evidence;
      # refine this only with a solver that measures their distinct impact times.
      first = contacts.take_while { |e| e[:t] == contacts.first[:t] }.map { |e| e[:a] == actor ? e[:b] : e[:a] }
      in_off = cue_pot && !contacts.empty? ? (first == [2] ? 3 : 2) : 0
      points = (cannon ? 2 : 0) + (pots.include?(2) ? 3 : 0) + (pots.include?(1 - actor) ? 2 : 0) + in_off
      all_baulk = targets(before).all? { |id| before[:balls].find { |b| b.id == id }.x <= Rules.table(before[:options]).baulk_line }
      out_contact = in_hand_foul(before, events)
      cue = state[:balls].find { |b| b.id == actor }
      legal_miss = contacts.empty? && before[:hand] == :d && all_baulk
      foul = if events.any? { |e| e[:kind] == :off } then :off_table
      elsif out_contact == :baulk_play then :baulk_play
      elsif running_coup?(before, events, cue_pot) then :running_coup
      elsif contacts.empty? && !legal_miss then :no_contact
      elsif before[:hand] == :d && !out_contact && cue.on_table? && cue.x <= Rules.table(before[:options]).baulk_line then :baulk_play
      elsif cannon && pots.empty? && before[:english_cannons] >= 75 then :cannon_limit
      elsif !cannon && points > 0 && before[:english_hazards] >= 15 then :hazard_limit
      end
      foul ||= baulk_limit_foul(before, state, events, points) if points > 0
      state[:ruling], state[:hand] = {foul: foul, points: 0}, nil
      events.select { |e| [:pocket, :off].include?(e[:kind]) && e[:a] < 2 }.each { |e| state[:english_off_by][e[:a]] = actor }
      if foul || legal_miss
        state[:scores][1 - actor] += 2
        state[:turn], state[:break_points] = 1 - actor, 0
        state[:english_cannons], state[:english_hazards], state[:english_red_run] = 0, 0, 0
        state[:english_baulk_window], state[:english_baulk_crossed] = 0, false
        state[:ruling][:points] = 2
        state[:ruling][:notice] = :english_miss unless foul
        if !state[:balls].find { |b| b.id == 2 }.on_table?
          spot_red(state)
        elsif events.any? { |e| e[:kind] == :ball && [e[:a], e[:b]].include?(2) }
          state[:english_red_spot] = nil
        end
        return if target_end(state)
        if foul
          state[:decision], state[:choices] = :english_foul, %w[english_accept english_reset]
        else
          prepare_next(state)
        end
        return
      end
      state[:scores][actor] += points
      state[:break_points] += points
      state[:ruling][:points] = points
      state[:english_cannons] = cannon && pots.empty? ? before[:english_cannons] + 1 : 0
      state[:english_hazards] = !cannon && points > 0 ? before[:english_hazards] + 1 : 0
      state[:ruling][:notice] = :seventy_cannons if state[:english_cannons] == 70
      state[:ruling][:notice] = :ten_hazards if state[:english_hazards] == 10
      red_contact = events.any? { |e| e[:kind] == :ball && [e[:a], e[:b]].include?(2) }
      plain_red = points == 3 && pots == [2] && before[:english_red_spot] && %i[spot pyramid].include?(before[:english_red_spot])
      state[:english_red_run] = plain_red ? before[:english_red_run] + 1 : 0
      if pots.include?(2)
        spot_red(state, state[:english_red_run] >= 2 ? :centre : :spot)
      elsif red_contact
        state[:english_red_spot], state[:english_red_run] = nil, 0
      end
      return if target_end(state)
      if points.zero?
        state[:turn], state[:break_points] = 1 - actor, 0
        state[:english_baulk_window], state[:english_baulk_crossed] = 0, false
      elsif state[:english_hazards] == 15
        opponent = state[:balls].find { |b| b.id == 1 - actor }
        if !opponent.on_table? && state[:english_off_by][opponent.id] == opponent.id
          t = Rules.table(state[:options])
          position = [[t.baulk_line, t.height / 2], [t.baulk_line, t.height / 2 - 0.292]].find do |x, y|
            t.placement?(state[:balls], opponent.id, x, y)
          end
          raise Physics::LimitExceeded, 'No available fifteenth-hazard opponent spot' unless position
          place(opponent, *position)
        end
      end
      prepare_next(state)
    end

    def baulk_limit_foul(before, state, events, points)
      return nil unless before[:options]['baulk_crossing']
      window = before[:english_baulk_window]
      start, finish = window * 100 + 80, (window + 1) * 100
      crossed = before[:english_baulk_crossed]
      if before[:break_points] >= start
        actor = cue_id(before)
        outside = before[:balls].find { |b| b.id == actor }.x > Rules.table(before[:options]).baulk_line
        events.each do |e|
          next unless e[:kind] == :crossing && e[:line] == :baulk && e[:a] == actor
          crossed ||= outside && e[:direction] == :left
          outside = true if e[:direction] == :right
        end
      end
      if before[:break_points] + points >= finish
        return :baulk_crossing unless crossed
        state[:english_baulk_window], state[:english_baulk_crossed] = window + 1, false
      else
        state[:english_baulk_crossed] = crossed
      end
      nil
    end

    def prepare_next(state)
      cue = state[:balls].find { |b| b.id == cue_id(state) }
      state[:hand] = cue.on_table? ? nil : :d
      return unless cue.on_table?
      radius = Rules.table(state[:options]).radius
      touching = state[:balls].any? { |b| b.id != cue.id && b.on_table? && Math.hypot(b.x - cue.x, b.y - cue.y) <= 2 * radius + 1e-7 }
      reset_objects(state) if touching
    end

    def target_end(state)
      return false if state[:options].fetch('english_limit', 'points') == 'time'
      target = state[:options].fetch('point_target', 100)
      winner = state[:scores].index { |score| score >= target }
      return false unless winner
      state[:scores][winner] = target
      finish(state, winner)
      true
    end

    def finish(state, winner)
      full_break = state[:break_points]
      winner.nil? ? Rules.finish_draw_rack(state) : Rules.finish_rack(state, winner)
      state[:break_points] = full_break
    end

    # The host supplies one authenticated elapsed boundary after any in-flight
    # shot has settled. The reducer neither reads a clock nor schedules work.
    def expire(state, elapsed_ms:)
      return false unless state[:phase] == :playing && state[:options]['english_limit'] == 'time' &&
        elapsed_ms.is_a?(Integer) && elapsed_ms >= state[:options].fetch('time_limit_minutes', 1) * 60_000
      state[:english_expired], state[:ruling] = true, {notice: :time}
      winner = state[:scores][0] == state[:scores][1] ? nil : (state[:scores][0] > state[:scores][1] ? 0 : 1)
      finish(state, winner)
      true
    end
  end
  Rules.register_engine('english', EnglishBilliards)
end
