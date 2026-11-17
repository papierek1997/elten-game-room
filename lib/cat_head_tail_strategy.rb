require_relative "game_bots"
require_relative "game_participants"

module CatHeadTailPlanning
  # Value iteration over the actual eight-sided outcomes: 2 is banked
  # immediately, 7 repeats, and 8 changes the turn total by +/-8. No RNG or
  # game state is consumed while constructing this small reusable table.
  def self.turn_values
    @turn_values ||= begin
      low, high = -128, 128
      values = (low..high).map { |points| [points.to_f, 2.0].max }
      300.times do
        difference = 0.0
        next_values = (low..high).map do |points|
          at = ->(value) { value < low ? 2.0 : value > high ? value.to_f : values[value - low] }
          roll = (2 + 2 * at.call(points) + (3..6).sum { |face| at.call(points + face) } +
            (at.call(points - 8) + at.call(points + 8)) / 2) / 8.0
          value = [points.to_f, roll].max
          difference = [difference, (value - values[points - low]).abs].max
          value
        end
        values = next_values
        Thread.pass
        break if difference < 1e-9
      end
      values.freeze
    end
  end

  class Strategy
    include GameRoomBots::ReplayOnlyStrategy

    def choose(actions:, actor:, random_source:, replay:, **_extra)
      choices = actions.to_a
      return nil if choices.empty?
      return choices.first if choices.length == 1

      roll = choices.find { |action| action["action"].to_s == "roll" }
      bank = choices.find { |action| action["action"].to_s == "bank" }
      return roll || bank || choices.first if roll == nil || bank == nil

      state = replay.state
      players = GameRoomParticipants.excluding(state[:players], state.fetch(:tournament_eliminations, []).flatten)
      player = players.find { |candidate| GameRoomParticipants.same?(candidate, actor) }
      score = state[:scores].fetch(player, 0).to_i
      turn_points = state[:turn_points].to_i
      banked_total = score + turn_points

      if state[:final_round]
        leader = GameRoomParticipants.excluding(players, [actor]).map { |candidate| state[:scores].fetch(candidate) }.max.to_i
        # Only the last seat settles the final result now. If the bank already
        # secures at least a tie, a bust cannot lose it; a positive roll can win.
        # A tie made from still-unbanked points is different and stays bankable.
        if GameRoomParticipants.same?(players.last, actor) && score >= leader && banked_total == leader
          return roll
        end
        return bank if banked_total >= leader
        return roll
      end

      return bank if banked_total >= state[:options]["score_limit"].to_i
      return roll if turn_points < -128
      return bank if turn_points > 128
      CatHeadTailPlanning.turn_values[turn_points + 128] > turn_points + 1e-8 ? roll : bank
    end
  end
end
