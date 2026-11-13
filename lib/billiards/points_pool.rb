# frozen_string_literal: true

module GameRoomBilliards
  # WPA Rules of Play (2026-10-21), chapters 7, 12 and 13. These helpers
  # belong to the point-pool engines, not to the historical 8/9-ball reducer.
  module PointPool
    module_function

    def rack(options, number, count = 15)
      t = Rules.table(options)
      ids = GameRoomRandom.shuffle((1..count).to_a, random: Random.new(options.fetch('rack_seed', 0) + number))
      balls = [Ball.new(id: 0, x: t.width / 4 - 0.1, y: t.height / 2)]
      rows = count == 9 ? [1, 2, 3, 2, 1] : [1, 2, 3, 4, 5]
      rows.each_with_index do |size, row|
        size.times do |column|
          balls << Ball.new(id: ids.shift, x: (t.width * 0.75 + row * Math.sqrt(3) * t.radius * 1.0003).round(9),
            y: (t.height / 2 + (2 * column - size + 1) * t.radius * 1.0003).round(9))
        end
      end
      balls.sort_by(&:id)
    end

    def setup(state)
      state[:scores] = Array.new(state[:racks].length, 0)
      state[:point_scored] = Array.new(state[:racks].length) { [] }
      state[:point_owed] = Array.new(state[:racks].length, 0)
      state[:point_pending], state[:point_rack] = [], 0
    end

    def copy_ledgers(state)
      state[:point_scored] = state[:point_scored].map(&:dup)
      state[:point_owed] = state[:point_owed].dup
      state[:point_pending] = state[:point_pending].dup
    end

    def targets(state); state[:balls].select { |b| b.id != 0 && b.on_table? }.map(&:id); end
    def ordered(result); result.events.each_with_index.sort_by { |e, i| [e[:t], e.fetch(:order, i)] }.map(&:first); end
    def pockets(result); ordered(result).select { |e| e[:kind] == :pocket && e[:a] != 0 }; end
    def off_ids(result); result.events.select { |e| e[:kind] == :off }.map { |e| e[:a] }; end
    def removed(result); (Rules.pot_ids(result) + off_ids(result)).uniq - [0]; end
    def called?(result, data)
      data['mode'] == 0 && pockets(result).any? { |e| e[:a] == data['call'] && e[:pocket] == data['pocket'] }
    end

    # All object balls are legal first contacts in these three disciplines.
    # Keep the scratch separate so One Pocket can apply its scratch-only exception.
    def fouls(before, result)
      events = ordered(result)
      reasons = []
      reasons << :scratch if Rules.pot_ids(result).include?(0) || off_ids(result).include?(0)
      reasons << :off_table unless (off_ids(result) - [0]).empty?
      contact = events.find { |e| e[:kind] == :ball && (e[:a] == 0 || e[:b] == 0) }
      crossed = events.any? { |e| e[:kind] == :crossing && e[:a] == 0 && e[:line] == :head }
      if before[:hand] == :kitchen
        first = Rules.first_contacts(result)
        beyond = first.any? { |id| before[:balls].find { |b| b.id == id }.x >= Rules.table(before[:options]).width / 4 }
        crossed_before = contact && (contact[:head_crossed] || events.any? do |e|
          e[:kind] == :crossing && e[:a] == 0 && e[:line] == :head && e[:t] <= contact[:t] + 1e-8
        end)
        reasons << :head_string_hand unless crossed || beyond || crossed_before
        reasons << :head_string if contact && !beyond && !crossed_before
      end
      reasons << :no_contact unless contact
      if contact && !events.any? { |e| e[:t] >= contact[:t] - 1e-8 && [:rail, :pocket, :off].include?(e[:kind]) }
        reasons << :no_rail
      end
      reasons.uniq
    end

    def scratch_hand?(reasons); (reasons & [:scratch, :head_string_hand]).any?; end
    def queue(state, id); state[:point_pending] |= [id]; end
    def spot_pending(state)
      state[:point_pending].sort.each { |id| Rules.spot_pool(state, id) }
      state[:point_pending] = []
    end
    def score(state, actor, id)
      state[:scores][actor] += 1
      if state[:point_owed][actor] > 0
        state[:point_owed][actor] -= 1
        queue(state, id)
      else
        state[:point_scored][actor] << id
      end
    end
    def penalty(state, actor)
      state[:scores][actor] -= 1
      id = state[:point_scored][actor].pop
      id ? queue(state, id) : state[:point_owed][actor] += 1
      state[:fouls][actor] += 1
      state[:ruling][:notice] = :two_fouls if state[:fouls][actor] == 2
    end
    def finish_turn(state, actor, continuing)
      spot_pending(state) if !continuing || targets(state).empty?
      state[:turn] = 1 - actor unless continuing
    end

    def rerack(state, breaker, preserve: true)
      scores, owed, fouls = state[:scores].dup, state[:point_owed].dup, state[:fouls].dup
      number = state[:point_rack] + 1
      state[:point_rack] = number
      state[:balls] = Rules.engine(state[:options]).rack(state[:options], state[:rack_number] + number)
      state.merge!(turn: breaker, breaker: breaker, breaking: true, hand: :kitchen, choices: [], decision: nil,
        point_scored: Array.new(state[:racks].length) { [] }, point_pending: [])
      state[:scores], state[:point_owed], state[:fouls] = scores, owed, fouls if preserve
    end

    # The native game has no physical lag. After both players accept a
    # stalemate they explicitly choose the new breaker instead of guessing it.
    def choose(state, choice)
      if choice == 'agree' && state[:decision] == :stalemate
        state[:choices], state[:decision] = %w[rack_self rack_other], :points_stalemate
        state.delete(:offer_turn)
        return true
      end
      return false unless state[:decision] == :points_stalemate && %w[rack_self rack_other].include?(choice)
      rerack(state, choice == 'rack_self' ? state[:turn] : 1 - state[:turn])
      # Fouls in rack-scored games must belong to a single rack (WPA3.13).
      state[:fouls] = [0, 0] unless state[:options]['discipline'] == 'straight'
      OnePocket.select_pocket(state) if state[:options]['discipline'] == 'one_pocket'
      true
    end
  end

  module StraightPool
    module_function
    def rack(options, number); PointPool.rack(options, number); end
    def setup(state); PointPool.setup(state); end
    def targets(state); PointPool.targets(state); end
    def cue_id(_state); 0; end
    def uses_calls?; true; end
    def points?; true; end
    def declaration?(state, data)
      data['mode'] == 1 && data['call'] == 0 || data['mode'] == 0 && targets(state).include?(data['call'])
    end

    def choose(state, choice)
      if state[:decision] == :straight_break && choice == 'rack_other'
        PointPool.rerack(state, 1 - state[:turn])
        return true
      end
      PointPool.choose(state, choice)
    end

    def resolve(state, before, result, data)
      actor, pots = before[:turn], PointPool.removed(result)
      reasons = PointPool.fouls(before, result)
      called = PointPool.called?(result, data)
      breaking_foul = before[:breaking] && !called && !legal_break_rails?(result)
      state[:hand], state[:breaking], state[:ruling] = nil, false, {foul: reasons.first, points: 0}
      if breaking_foul
        state[:scores][actor] -= 2
        pots.sort.each { |id| Rules.spot_pool(state, id) }
        state[:turn], state[:choices], state[:decision] = 1 - actor, %w[accept rack_other], :straight_break
        state[:hand] = :kitchen if PointPool.scratch_hand?(reasons)
        state[:ruling] = {foul: :break_spread, points: -2}
      elsif reasons.any?
        state[:scores][actor] -= 1
        state[:fouls][actor] += 1
        state[:ruling][:points] = -1
        state[:ruling][:notice] = :two_fouls if state[:fouls][actor] == 2
        pots.sort.each { |id| Rules.spot_pool(state, id) }
        state[:turn] = 1 - actor
        state[:hand] = :kitchen if PointPool.scratch_hand?(reasons)
        if state[:fouls][actor] >= 3
          state[:scores][actor] -= 15
          state[:fouls][actor] = 0
          PointPool.rerack(state, actor)
          state[:ruling] = {foul: :three_fouls, points: -16}
        end
      else
        state[:fouls][actor] = 0
        if called
          state[:scores][actor] += pots.length
          state[:ruling][:points] = pots.length
          if state[:scores][actor] >= state[:options].fetch('point_target', 100)
            Rules.finish_rack(state, actor)
          elsif targets(state).length <= 1
            continuation_rack(state)
          end
        else
          pots.sort.each { |id| Rules.spot_pool(state, id) }
          state[:turn] = 1 - actor
        end
      end
    end

    def legal_break_rails?(result)
      contact = PointPool.ordered(result).find { |e| e[:kind] == :ball && (e[:a] == 0 || e[:b] == 0) }
      return false unless contact
      rails = result.events.select { |e| e[:t] >= contact[:t] - 1e-8 && [:rail, :pocket, :off].include?(e[:kind]) }.map { |e| e[:a] }.uniq
      rails.include?(0) && (rails - [0]).length >= 2
    end

    def rack_interference?(ball, t)
      r, foot, middle = t.radius, t.width * 0.75, t.height / 2
      vertices = [[foot - 2 * r, middle], [foot + (4 * Math.sqrt(3) * 1.0003 + 1) * r, middle - (4 * 1.0003 + Math.sqrt(3)) * r],
        [foot + (4 * Math.sqrt(3) * 1.0003 + 1) * r, middle + (4 * 1.0003 + Math.sqrt(3)) * r]]
      signs = vertices.each_with_index.map do |(x, y), i|
        nx, ny = vertices[(i + 1) % 3]
        (nx - x) * (ball.y - y) - (ny - y) * (ball.x - x)
      end
      signs.all? { |v| v >= 0 } || signs.all? { |v| v <= 0 } || vertices.each_with_index.any? do |(x, y), i|
        nx, ny = vertices[(i + 1) % 3]
        Geometry.distance_to_segment(ball.x, ball.y, [x, y, nx, ny]).first <= r + 1e-9
      end
    end

    def move_to_spot(state, ball, fraction)
      t = Rules.table(state[:options])
      x, y = t.width * fraction, t.height / 2
      if !t.placement?(state[:balls], ball.id, x, y)
        x = t.width / 2
      end
      raise Physics::LimitExceeded, 'Occupied straight-pool relocation spot' unless t.placement?(state[:balls], ball.id, x, y)
      ball.x, ball.y, ball.status = x, y, :table
    end

    def continuation_rack(state)
      t = Rules.table(state[:options])
      cue = state[:balls].find { |b| b.id == 0 }
      remaining = state[:balls].find { |b| b.id != 0 && b.on_table? }
      cue_in = rack_interference?(cue, t)
      object_in = remaining && rack_interference?(remaining, t)
      state[:point_rack] += 1
      fresh = rack(state[:options], state[:rack_number] + state[:point_rack])
      if remaining && !(cue_in && object_in)
        ids = fresh.reject { |b| b.id == 0 }.sort_by { |b| [b.x, b.y] }.drop(1)
        retired = state[:balls].reject { |b| b.id == 0 || b.id == remaining.id }.sort_by(&:id)
        retired.zip(ids).each { |b, position| b.x, b.y, b.status = position.x, position.y, :table }
        if object_in
          move_to_spot(state, remaining, 0.25)
        elsif cue_in
          if remaining.x >= t.width / 4
            state[:hand] = :kitchen
            cue.status = :potted
          else
            move_to_spot(state, cue, 0.25)
          end
        end
      else
        state[:balls] = fresh.reject { |b| b.id == 0 } + [cue]
        state[:balls].sort_by!(&:id)
        if cue_in
          state[:hand], cue.status = :kitchen, :potted
        end
      end
      state[:ruling][:notice] = :straight_rerack
    end
  end

  module OnePocket
    module_function
    def rack(options, number); PointPool.rack(options, number); end
    def setup(state); PointPool.setup(state); select_pocket(state); end
    def select_pocket(state)
      state[:point_pockets] = [nil, nil]
      state[:choices], state[:decision] = %w[pocket_2 pocket_5], :one_pocket_select
    end
    def targets(state); PointPool.targets(state); end
    def cue_id(_state); 0; end
    def uses_calls?; false; end
    def points?; true; end
    def declaration?(_state, data); data['call'] == 0 && data['mode'] == 0; end
    def choose(state, choice)
      if state[:decision] == :one_pocket_select && %w[pocket_2 pocket_5].include?(choice)
        pocket = choice == 'pocket_2' ? 2 : 5
        state[:point_pockets][state[:breaker]] = pocket
        state[:point_pockets][1 - state[:breaker]] = 7 - pocket
        state[:choices], state[:decision] = [], nil
        return true
      end
      PointPool.choose(state, choice)
    end

    def resolve(state, before, result, _data)
      PointPool.copy_ledgers(state)
      actor = before[:turn]
      reasons = PointPool.fouls(before, result)
      state[:ruling], state[:hand], state[:breaking] = {foul: reasons.first, points: 0}, nil, false
      own_pot = false
      scratch_only = reasons == [:scratch] && Rules.pot_ids(result).include?(0)
      PointPool.pockets(result).each do |event|
        owner = state[:point_pockets].index(event[:pocket])
        counts = owner && (reasons.empty? || owner != actor && !scratch_only)
        if counts
          PointPool.score(state, owner, event[:a])
          own_pot = true if owner == actor
          state[:ruling][:points] += 1 if owner == actor
        else
          PointPool.queue(state, event[:a])
        end
      end
      (PointPool.off_ids(result) - [0]).each { |id| PointPool.queue(state, id) }
      if reasons.any?
        PointPool.penalty(state, actor)
        state[:ruling][:points] = -1
        state[:hand] = :kitchen if PointPool.scratch_hand?(reasons)
        PointPool.spot_pending(state)
        return Rules.finish_rack(state, 1 - actor) if state[:fouls][actor] >= 3
      else
        state[:fouls][actor] = 0
      end
      # The shooter's win has priority when both winning balls fall (12.11).
      winner = [actor, 1 - actor].find { |seat| state[:scores][seat] >= 8 }
      return Rules.finish_rack(state, winner) if winner
      PointPool.finish_turn(state, actor, reasons.empty? && own_pot)
    end
  end

  module BankPool
    module_function
    RAILS = [:left, :right, :top, :bottom].freeze
    def rack(options, number); PointPool.rack(options, number, options['discipline'] == 'bank_short' ? 9 : 15); end
    def setup(state); PointPool.setup(state); end
    def targets(state); PointPool.targets(state); end
    def cue_id(_state); 0; end
    def uses_calls?; true; end
    def points?; true; end
    def declaration?(state, data)
      rails = data['rails']
      return data['call'] == 0 && data['mode'] == 0 && rails == [] if state[:breaking]
      return data['call'] == 0 && rails == [] if data['mode'] == 1
      data['mode'] == 0 && targets(state).include?(data['call']) && rails.is_a?(Array) && rails.length.between?(1, 12) &&
        rails.all? { |rail| rail.is_a?(Integer) && rail.between?(0, 3) }
    end
    def choose(state, choice)
      if state[:decision] == :bank_break && choice == 'rack_other'
        PointPool.rerack(state, 1 - state[:turn])
        return true
      end
      PointPool.choose(state, choice)
    end

    def resolve(state, before, result, data)
      PointPool.copy_ledgers(state)
      actor, pots = before[:turn], PointPool.removed(result)
      reasons = PointPool.fouls(before, result)
      state[:ruling], state[:hand], state[:breaking] = {foul: reasons.first, points: 0}, nil, false
      if before[:breaking] && PointPool.pockets(result).empty? && break_rails(result) < 4
        pots.each { |id| PointPool.queue(state, id) }
        PointPool.spot_pending(state)
        # An illegal spread itself is a choice, not a standard one-point foul.
        if reasons.any?
          PointPool.penalty(state, actor)
          PointPool.spot_pending(state)
          state[:hand] = :kitchen if PointPool.scratch_hand?(reasons)
          return Rules.finish_rack(state, 1 - actor) if state[:fouls][actor] >= 3
        end
        state[:turn], state[:choices], state[:decision] = 1 - actor, %w[accept rack_other], :bank_break
        state[:ruling][:foul] ||= :break_spread
        return
      end
      valid = reasons.empty? && !before[:breaking] && valid_bank?(result, data, Rules.table(state[:options]))
      PointPool.score(state, actor, data['call']) if valid
      (pots - (valid ? [data['call']] : [])).each { |id| PointPool.queue(state, id) }
      if reasons.any?
        PointPool.penalty(state, actor)
        state[:ruling][:points] = -1
        state[:hand] = :kitchen if PointPool.scratch_hand?(reasons)
        PointPool.spot_pending(state)
        return Rules.finish_rack(state, 1 - actor) if state[:fouls][actor] >= 3
      else
        state[:fouls][actor] = 0
        state[:ruling][:points] = 1 if valid
      end
      goal = state[:options]['discipline'] == 'bank_short' ? 5 : 8
      return Rules.finish_rack(state, actor) if state[:scores][actor] >= goal
      continuing = reasons.empty? && (before[:breaking] ? !PointPool.pockets(result).empty? : valid)
      PointPool.finish_turn(state, actor, continuing)
    end

    def break_rails(result)
      first = PointPool.ordered(result).find { |e| e[:kind] == :ball && (e[:a] == 0 || e[:b] == 0) }
      return 0 unless first
      result.events.select { |e| e[:kind] == :rail && e[:a] != 0 && e[:t] >= first[:t] - 1e-8 }.map { |e| e[:a] }.uniq.length
    end

    def valid_bank?(result, data, table)
      return false unless PointPool.called?(result, data) && data['rails'].is_a?(Array) && !data['rails'].empty?
      events, id = PointPool.ordered(result), data['call']
      first = events.find { |e| e[:kind] == :ball && [e[:a], e[:b]].sort == [0, id] }
      return false unless first
      return false if events.any? do |e|
        e[:t] < first[:t] - 1e-8 && (e[:kind] == :rail && e[:a] == 0 || e[:kind] == :ball && (e[:a] == 0 || e[:b] == 0))
      end
      contacts = events.select { |e| e[:kind] == :ball && (e[:a] == id || e[:b] == id) }
      return false unless contacts == [first]
      pot_index = events.index { |e| e[:kind] == :pocket && e[:a] == id }
      rails = events.take(pot_index).select { |e| e[:kind] == :rail && e[:a] == id }
      # A jaw at the destination can neither create nor invalidate a bank.
      # A jaw elsewhere is a real uncalled contact and therefore invalidates it.
      # Only contacts at the end of the path are incidental to entering the
      # pocket. A visit to its jaw before a later bank is not exempt.
      rails.pop while rails.any? && incidental?(rails.last, data['pocket'], table)
      rails.map { |e| RAILS.index(e[:rail]) } == data['rails']
    end

    def incidental?(event, pocket, table)
      return false unless event[:rail] == :jaw && event[:x].is_a?(Numeric) && event[:y].is_a?(Numeric)
      px, py = table.pockets.fetch(pocket)
      (event[:x] - px).abs <= 0.085 + table.radius && (event[:y] - py).abs <= 0.085 + table.radius
    end
  end

  Rules.register_engine('straight', StraightPool)
  Rules.register_engine('one_pocket', OnePocket)
  Rules.register_engine('bank_short', BankPool)
  Rules.register_engine('bank_full', BankPool)
end
