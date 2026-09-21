require_relative "game_bots"
require_relative "game_participants"

module CatHeadTailPlanning
  class Strategy
    def choose(actions:, actor:, random_source:, replay:, **_extra)
      choices = actions.to_a
      return nil if choices.empty?
      return choices.first if choices.length == 1

      roll = choices.find { |action| action["action"].to_s == "roll" }
      bank = choices.find { |action| action["action"].to_s == "bank" }
      return roll || bank || choices.first if roll == nil || bank == nil

      state = replay.state
      player = state[:players].find { |candidate| GameRoomParticipants.same?(candidate, actor) }
      score = state[:scores].fetch(player, 0).to_i
      turn_points = state[:turn_points].to_i
      banked_total = score + turn_points

      if state[:final_round]
        leader = state[:scores].reject { |candidate, _score| GameRoomParticipants.same?(candidate, actor) }.values.max.to_i
        return bank if banked_total >= leader
        return roll
      end

      return bank if banked_total >= state[:options]["score_limit"].to_i
      return roll if turn_points < 19

      chance = {
        19 => 30,
        20 => 42,
        21 => 66,
        22 => 70,
        23 => 78,
        24 => 84
      }.fetch(turn_points) { [88 + (turn_points - 25) * 3, 99].min }
      random_source.roll(count: 1, sides: 100).values.first.to_i <= chance ? bank : roll
    end
  end
end
