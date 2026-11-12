module GameRoomGames
  class MilleBornes
    def bot_allied?(replay, first, second)
      first_unit = unit_for(replay.state, first)
      second_unit = unit_for(replay.state, second)
      first_unit != nil && first_unit == second_unit
    end

    def bot_reward(replay, actor)
      return 0.0 unless replay.finished? && !replay.draw
      unit = unit_for(replay.state, actor)
      return 0.0 if unit == nil
      return super unless replay.state[:teams]

      replay.winner == "team:#{unit}" ? 1.0 : -1.0
    end

    def bot_observation(replay, actor)
      state = replay.state
      observation = {
        "players" => state[:players], "seats" => state[:seats], "tracks" => state[:tracks],
        "scores" => state[:scores], "round" => state[:round], "phase" => state[:phase],
        "current_player" => state[:current_player], "hand" => hand_for(state, actor),
        "card_counts" => state[:hands].transform_values(&:length), "draw_count" => state[:draw_pile].length,
        "discard" => state[:discard], "reaction" => state[:reaction]&.reject { |key, _value| key == :before },
        "own_unit" => unit_for(state, actor)
      }
      Marshal.load(Marshal.dump(observation))
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      return 50_000 if action["action"] == "dirty_trick"
      return 10_000 if action["action"] == "draw"
      type = card_type(action["card"])
      track = state[:tracks][unit_for(state, actor)]
      recycling = state[:options]["recycle_discard"]
      if action["action"] == "discard"
        copies = hand_for(state, actor).count { |card| card_type(card) == type }
        value = if SAFETIES.include?(type)
          track[:safeties].include?(type) ? 0 : 3000
        elsif DISTANCES.include?(type)
          track[:counterflow] || track[:miles] + type.to_i > 1000 || (type == "200" && track[:two_hundreds] >= 2) ? 0 : type.to_i
        elsif type == "go"
          track[:safeties].include?("right_of_way") ? 0 : 700
        elsif type == "instant_repair"
          (SAFETIES - track[:safeties]).empty? ? 0 : 800
        elsif REMEDIES.key?(type)
          track[:safeties].include?(PROTECTION[REMEDIES[type]]) ? 0 : 350
        else
          250
        end
        value = 0 if recycling && copies > 1 && (type == "go" || REMEDIES.key?(type))
        return -1000 - value + copies
      end
      return -100_000 unless action["action"] == "play"
      if DISTANCES.include?(type)
        if track[:counterflow]
          return 2000 - type.to_i if bot_reverse_finish_possible?(state, actor, track, action["card"])
          return -10_000 - [track[:miles], type.to_i].min
        end
        if recycling && !replay.state[:options]["counterflow"] && !bot_finish_possible?(replay, track, type)
          return -20_000
        end
        return 20_000 if track[:miles] + type.to_i == 1000
        return 400 + type.to_i
      end
      return type == "right_of_way" ? 3000 : 1500 if SAFETIES.include?(type)
      return 1200 if type == "go" || REMEDIES.key?(type)
      if type == "instant_repair"
        return 1150 if action["problem"] == "counterflow" && track[:moving]
        return action["problem"] == "speed_limit" ? 1000 : 1100
      end
      target = state[:tracks][state[:seats][action["target"].to_i]]
      300 + target[:miles] + (target[:moving] ? 150 : 0)
    end

    private

    # Only a held cure and a different held mileage card can justify reversing
    # before curing. This bounded three-card plan does not simulate foreign
    # hands or future draws, and the normal reducer still validates each turn.
    def bot_reverse_finish_possible?(state, actor, track, card)
      hand = hand_for(state, actor)
      return false if bot_held_finish?(hand, track, track[:miles], track[:two_hundreds])

      miles = [track[:miles] - card_type(card).to_i, 0].max
      used_two_hundreds = track[:two_hundreds] + (card_type(card) == "200" ? 1 : 0)
      return false unless bot_held_finish?(hand, track, miles, used_two_hundreds, except: card)

      hand.any? do |candidate|
        type = card_type(candidate)
        type == "end_counterflow" ||
          (type == "instant_repair" && state[:options]["include_instant_repairs"]) ||
          (type == "driving_ace" && !track[:safeties].include?(type))
      end
    end

    def bot_held_finish?(hand, track, miles, used_two_hundreds, except: nil)
      finish = 1000 - miles
      return false unless DISTANCES.include?(finish.to_s)
      return false if track[:speed_limit] && finish > 50
      return false if finish == 200 && used_two_hundreds >= 2

      hand.any? { |candidate| candidate != except && card_type(candidate) == finish.to_s }
    end

    def bot_finish_possible?(replay, track, type)
      remaining = 1000 - track[:miles] - type.to_i
      return false if remaining < 0

      effective_counts = deck_counts_for(replay.state[:options])
      counts = DISTANCES.to_h { |distance| [distance, effective_counts.fetch(distance, 0)] }
      replay.state[:spent].each do |card|
        played = card_type(card)
        counts[played] -= 1 if counts.key?(played)
      end
      counts[type] -= 1
      counts["200"] = [counts["200"], 2 - track[:two_hundreds] - (type == "200" ? 1 : 0)].min
      reachable = 1
      counts.each do |distance, count|
        count.times { reachable |= reachable << (distance.to_i / 25) }
      end
      reachable[remaining / 25] == 1
    end
  end
end
