require_relative '../lib/five_dice_score_tail'
require_relative '../lib/game_snapshot'

module GameRoomGames
  module FiveDiceTail
    private

    def bot_tail_eligible?(_state, _actor); true; end

    def bot_tail_value(state, actor, action)
      return nil unless state[:turn_rolls].to_i.positive? && bot_tail_eligible?(state,actor)
      position = bot_tail_position(state, actor)
      slots = bot_tail_slots(position, actor)
      return nil unless slots.between?(1, 2)
      target = bot_tail_target(state, actor)
      key = [actor, bot_tail_identity(position,actor), target]
      if @bot_tail_key != key
        owned = GameRoomSnapshot.copy(position)
        tail = GameRoomFiveDiceScoreTail.new(position:owned,
          choices: ->(p,dice,rolls) { bot_tail_choices(p,actor,dice,rolls) },
          record: ->(p,choice,dice,rolls) { bot_tail_record(p,actor,choice,dice,rolls) },
          slots: ->(p) { bot_tail_slots(p,actor) }, identity: ->(p) { bot_tail_identity(p,actor) },
          value: ->(p) { score = bot_tail_total(p,actor); target ? GameRoomBots::ExpectedValue.new(score <=> target,score) : score.to_f })
        @bot_tail_key, @bot_tail = key, tail
      end
      if action['action'] == 'score'
        @bot_tail.score_value(action['category'],state[:dice],state[:turn_rolls])
      elsif action['action'] == 'roll'
        indices = parse_die_ids(action['die_ids'])
        kept = state[:dice].each_with_index.filter_map { |face,index| face unless indices.include?(index) }
        @bot_tail.roll_value(kept.sort,3-state[:turn_rolls]) - 0.0000001
      end
    end
  end
end
