module GameRoomBilliards
  module Friendly
    module_function

    def rack(options, _number); Rules.practice_balls(options['layout']); end
    def setup(state)
      state[:breaking], state[:hand] = false, nil
      state[:final_ball] = state[:balls].map(&:id).max
    end
    def targets(state)
      ids = state[:balls].select { |b| b.id != 0 && b.on_table? }.map(&:id)
      others = ids - [state[:final_ball]]
      others.empty? ? [state[:final_ball]] : others
    end
    def uses_calls?; false; end
    def points?; true; end
    def cue_id(_state); 0; end
    def choose(_state, _choice); false; end
    def declaration?(state, data); data['call'] == 0 && data['mode'] == 0; end

    def resolve(state, before, result, data)
      pots, actor = Rules.pot_ids(result), state[:turn]
      foul = Rules.common_pool_foul(before.merge(declaration: data), result)
      early = pots.include?(state[:final_ball]) && targets(before) != [state[:final_ball]]
      state[:ruling], state[:hand] = {foul: foul}, nil
      state[:scores] = state[:scores].dup
      state[:scores][actor] += (pots - [0]).length unless foul || early
      if pots.include?(state[:final_ball])
        legal = !foul && targets(before) == [state[:final_ball]]
        state[:ruling][:foul] ||= :early_final unless legal
        finish_round(state, legal ? actor : (actor + 1) % state[:racks].length)
      elsif foul
        state[:turn], state[:hand] = (actor + 1) % state[:racks].length, :any
      elsif (pots - [0]).empty?
        state[:turn] = (actor + 1) % state[:racks].length
      end
    end

    def finish_round(state, winner)
      state[:racks] = state[:racks].dup
      state[:racks][winner] += 1
      state[:rack_winner], state[:hand] = winner, nil
      if state[:racks].sum >= state[:options]['rounds']
        best = state[:racks].max
        winners = state[:racks].each_index.select { |i| state[:racks][i] == best }
        state[:winner] = winners.one? ? winners.first : nil
        state[:phase], state[:choices] = :finished, []
      else
        state[:phase], state[:choices], state[:turn] = :rack_end, ['next'], (state[:breaker] + 1) % state[:racks].length
      end
    end
  end
end
