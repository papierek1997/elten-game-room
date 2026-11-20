module GameRoomBilliards
  module Rules
    module_function

    def pool_targets(state, call = nil)
      return engine(state[:options]).targets(state) if engine(state[:options])
      ids = state[:balls].select(&:on_table?).map(&:id) - [0]
      return [ids.min].compact if state[:options]['discipline'] == 'nine'
      return ids if state[:breaking]
      if state[:groups]
        remaining = ids.select { |id| group(id) == state[:groups][state[:turn]] }
        remaining.empty? ? [8] : remaining
      else
        empty = [0, 1].any? { |g| ids.none? { |id| group(id) == g } }
        empty && call == 8 ? [8] : ids.reject { |id| id == 8 } + (empty ? [8] : [])
      end
    end

    def valid_declaration?(state, data)
      cue = state[:balls].find { |b| b.id == (data['cue'] || cue_id(state)) }
      return false unless state[:phase] == :playing && state[:choices].empty? && cue&.on_table?
      return false if advanced?(state[:options]) && state[:options]['discipline'] != 'pyramid' && data['cue'] != cue_id(state)
      return false unless %w[call pocket mode].all? { |k| data[k].is_a?(Integer) }
      return false unless data['pocket'].between?(0, 5)
      return false if state[:hand] && !placement?(state, cue.id, cue.x, cue.y)
      return engine(state[:options]).declaration?(state, data) if engine(state[:options])
      return snooker_declaration?(state, data) if snooker?(state)
      if state[:options]['discipline'] == 'nine'
        data['call'] == 0 && (data['mode'] == 0 || data['mode'] == 2 && state[:push_available] && !state[:breaking])
      elsif state[:breaking]
        data['mode'] == 0 && data['call'] == 0
      else
        data['mode'] == 1 && data['call'] == 0 || data['mode'] == 0 && pool_targets(state, data['call']).include?(data['call'])
      end
    end

    def common_pool_foul(state, result, push: false)
      return :scratch if pot_ids(result).include?(0)
      return nil if push
      first = first_contacts(result)
      return :no_contact if first.empty?
      return :wrong_first unless (first & pool_targets(state, state[:declaration]['call'])).any?
      if state[:hand] == :kitchen && !state[:breaking]
        contact = result.events.find { |e| e[:kind] == :ball && (e[:a] == 0 || e[:b] == 0) }
        above = first.all? { |id| state[:balls].find { |b| b.id == id }.x < table(state[:options]).width / 4 }
        return :head_string if above && !contact[:head_crossed]
      end
      if state[:breaking]
        rails = result.events.select { |e| e[:kind] == :rail && e[:a] != 0 }.map { |e| e[:a] }.uniq
        return :break_spread if (pot_ids(result) - [0]).empty? && rails.length < 4
      else
        index = result.events.index { |e| e[:kind] == :ball && (e[:a] == 0 || e[:b] == 0) }
        return :no_rail unless result.events.drop(index + 1).any? { |e| e[:kind] == :rail || e[:kind] == :pocket && e[:a] != 0 }
      end
      nil
    end

    def finish_rack(state, winner)
      return Friendly.finish_round(state, winner) if state[:options]['discipline'] == 'friendly'
      state[:racks] = state[:racks].dup
      state[:racks][winner] += 1
      state[:rack_winner] = winner
      state[:break_points], state[:hand], state[:decision] = 0, nil, nil
      state[:scores] = state[:racks].dup unless points_game?(state)
      if state[:racks][winner] >= state[:options]['race_to']
        state[:winner], state[:phase], state[:choices] = winner, :finished, []
      else
        state[:phase], state[:choices], state[:turn] = :rack_end, ['next'], (state[:breaker] + 1) % state[:racks].length
      end
    end

    def finish_draw_rack(state)
      state[:rack_winner], state[:winner], state[:hand], state[:decision] = nil, nil, nil, nil
      if state[:options]['race_to'] == 1
        state[:phase], state[:choices] = :finished, []
      else
        state[:phase], state[:choices], state[:turn] = :rack_end, ['next'], (state[:breaker] + 1) % state[:racks].length
      end
    end

    def pool_shot(state, before, result, data)
      actor, pots = state[:turn], pot_ids(result)
      state[:declaration] = data
      foul = common_pool_foul(before.merge(declaration: data), result, push: data['mode'] == 2)
      state[:ruling] = {foul: foul}
      state[:hand], state[:push_available] = nil, false
      if state[:options]['discipline'] == 'nine'
        nine_shot(state, before, result, data, pots, foul, actor)
      else
        eight_shot(state, before, result, data, pots, foul, actor)
      end
      state[:breaking] = false
    end

    def eight_shot(state, before, result, data, pots, foul, actor)
      if before[:breaking]
        spot_pool(state, 8) if pots.include?(8)
        if foul == :break_spread
          state[:turn], state[:choices] = 1 - actor, %w[accept rack_self rack_other]
        elsif foul
          state[:turn], state[:choices] = 1 - actor, pots.include?(8) ? %w[hand rack_self] : %w[accept hand]
          state[:hand] = :kitchen unless state[:balls].first.on_table?
        elsif pots.include?(8)
          state[:choices] = %w[accept rack_self]
        else
          state[:turn] = 1 - actor if pots.empty?
        end
        return
      end
      success = result.events.any? { |e| e[:kind] == :pocket && e[:a] == data['call'] && e[:pocket] == data['pocket'] }
      if pots.include?(8)
        win = !foul && data['mode'] == 0 && data['call'] == 8 && pool_targets(before, 8) == [8] && success
        state[:ruling][:foul] ||= :early_eight unless win
        return finish_rack(state, win ? actor : 1 - actor)
      end
      if foul
        state[:turn], state[:hand] = 1 - actor, :any
      elsif data['mode'] == 0 && success
        state[:groups] ||= actor.zero? ? [group(data['call']), 1 - group(data['call'])] : [1 - group(data['call']), group(data['call'])]
      else
        state[:turn] = 1 - actor
      end
    end

    def nine_shot(state, before, result, data, pots, foul, actor)
      if foul
        state[:fouls][actor] += 1
        spot_pool(state, 9) if pots.include?(9)
        state[:turn], state[:hand] = 1 - actor, :any
        return finish_rack(state, 1 - actor) if state[:fouls][actor] >= 3
        return
      end
      state[:fouls][actor] = 0
      if before[:breaking] && (pots + result.head_crossings.to_a).uniq.length < 3
        spot_pool(state, 9) if pots.include?(9)
        state[:turn], state[:choices] = 1 - actor, %w[accept return]
        state[:decision], state[:ruling] = :illegal_nine_break, {notice: :three_ball_break}
      elsif data['mode'] == 2
        spot_pool(state, 9) if pots.include?(9)
        state[:turn], state[:choices], state[:decision] = 1 - actor, %w[accept return], :push_out
      elsif pots.include?(9)
        finish_rack(state, actor)
      else
        state[:turn] = 1 - actor if pots.empty?
        state[:push_available] = true if before[:breaking]
      end
    end

    def choose(state, choice)
      implementation = engine(state[:options])
      return if implementation && implementation.choose(state, choice)
      case choice
      when 'next'
        state[:rack_number] += 1
        state[:scores] = [0, 0] if snooker?(state)
        setup(state, breaker: (state[:breaker] + 1) % state[:racks].length)
        return
      when 'agree'
        if state[:offer_remaining] && state[:offer_remaining].length > 1
          state[:offer_remaining] = state[:offer_remaining].drop(1)
          state[:turn] = state[:offer_remaining].first
          return
        end
        state.delete(:offer_remaining)
        state[:rack_number] += 1
        state[:scores] = [0, 0] if snooker?(state)
        setup(state, breaker: state[:breaker])
        return
      when 'decline'
        state[:turn] = state.delete(:offer_turn)
        state.delete(:offer_remaining)
      when 'rack_self', 'rack_other'
        breaker = choice == 'rack_self' ? state[:turn] : 1 - state[:turn]
        state[:rack_number] += 1
        setup(state, breaker: breaker)
        return
      when 'return'
        state[:turn] = 1 - state[:turn]
        state[:push_available] = true if state[:decision] == :illegal_nine_break
        state[:free_ball] = false
        state[:on] = reds(state[:balls]).empty? ? next_colour(state[:balls]) : :red if snooker?(state)
        state[:miss_chain] = 0
      when 'restore'
        restore_snooker(state)
      when 'hand'
        state[:hand] = :kitchen
      when 'accept'
        state[:miss_chain] = 0
      end
      state[:choices], state[:decision] = [], nil
    end
  end
end
