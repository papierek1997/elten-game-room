require_relative '../game_bots'
require_relative 'physics'
require_relative 'rules'
require_relative 'shot_candidates'

module GameRoomBilliards
  class Strategy
    include GameRoomBots::ReplayOnlyStrategy

    def choose(actions:, replay:)
      state, table = replay.state, Rules.table(replay.state[:options])
      competition = Rules.competition?(state[:options])
      return actions.first if competition && !state[:choices].empty?
      return actions.find { |a| a['action'] == 'head_spot' } if competition && Rules.head_spot(state)
      cue = state[:balls].find { |ball| ball.id == Rules.cue_id(state) }
      if !cue.on_table? || competition && state[:hand] && !Rules.placement?(state, cue.id, cue.x, cue.y)
        return placement(state, table, cue.id) || actions.find { |a| a['action'] == (competition ? 'stalemate' : 'finish') }
      end
      if competition && state[:breaking] && !Rules.snooker?(state) && !table.pockets.empty?
        target = state[:balls].select { |b| b.on_table? && Rules.targets(state).include?(b.id) }.min_by(&:x)
        return selection(state, cue.id, Geometry.angle(target.x - cue.x, target.y - cue.y), 950, target.id, 0, [])
      end
      candidates = ShotCandidates.build(state, table, cue)
      if candidates.empty?
        target = state[:balls].select { |b| b.on_table? && b.id != cue.id && (!competition || Rules.targets(state).include?(b.id)) }
          .min_by { |b| Math.hypot(b.x - cue.x, b.y - cue.y) }
        return actions.find { |a| %w[finish concede].include?(a['action']) } unless target
        candidates = [[Geometry.angle(target.x - cue.x, target.y - cue.y), Math.hypot(target.x - cue.x, target.y - cue.y), target.id, 0, []]]
      end
      limit = {'easy'=>1, 'medium'=>3, 'hard'=>6}.fetch(state[:options]['bot_skill'])
      shots = candidates.first(limit).flat_map do |angle, distance, id, pocket, rails|
        powers = table.pockets.empty? ? [600, 800, 1000] : [(Math.sqrt(2 * 0.15 * (distance + 0.4)) / 6 * 1000 * 1.4).round.clamp(120, 850)]
        powers.map { |power| selection(state, cue.id, angle, power, id, pocket, rails) }
      end
      shots.select! { |move| !competition || Rules.valid_declaration?(state, move) }
      shots.max_by do |move|
        result = Physics.simulate(table, state[:balls], move['shot'], accurate: state[:options]['accurate'], cue_id: cue.id)
        score(state, result, move)
      end || actions.find { |a| %w[concede finish].include?(a['action']) }
    end

    def selection(state, cue, angle, power, id, pocket, rails)
      move = {'kind'=>'billiards', 'action'=>'shot', 'revision'=>state[:revision],
        'shot'=>{'angle'=>(angle * 100).round % 36_000, 'power'=>power, 'top'=>0, 'side'=>0}}
      return move unless Rules.competition?(state[:options])
      implementation = Rules.engine(state[:options])
      no_call = state[:options]['discipline'] == 'nine' || implementation && !implementation.uses_calls? ||
        state[:breaking] && !Rules.snooker?(state) && !Rules.calls_break?(state[:options])
      mode = Rules.snooker?(state) && !Rules.snooker_targets(state).include?(id) ? 3 : 0
      if %w[bank_short bank_full].include?(state[:options]['discipline']) && !state[:breaking] && rails.empty?
        no_call, mode = true, 1
      end
      move.merge!('call'=>no_call ? 0 : id, 'pocket'=>pocket, 'mode'=>mode)
      if Rules.advanced?(state[:options])
        called_rails = %w[bank_short bank_full].include?(state[:options]['discipline']) ? rails.dup : []
        move.merge!('cue'=>cue, 'rails'=>called_rails)
      end
      move
    end

    def placement(state, table, id)
      competition = Rules.competition?(state[:options])
      (1..19).each do |x|
        (1..9).each do |y|
          px, py = (x * table.width / 20 * 10_000).round, (y * table.height / 10 * 10_000).round
          allowed = competition ? Rules.placement?(state, id, px / 10_000.0, py / 10_000.0) : table.placement?(state[:balls], id, px / 10_000.0, py / 10_000.0)
          return place(state, id, [px, py]) if allowed
        end
      end
      position = Rules.find_placement(state) if competition
      place(state, id, position) if position
    end
    def place(state, id, position)
      {'kind'=>'billiards', 'action'=>'place', 'revision'=>state[:revision], 'ball'=>id, 'x'=>position[0], 'y'=>position[1]}
    end

    def score(state, result, move)
      unless Rules.competition?(state[:options])
        return result.events.count { |e| e[:kind] == :pocket && e[:a] != 0 } * 100 -
          (result.balls.first.on_table? ? 0 : 150) + result.events.count { |e| e[:kind] == :ball }
      end
      trial = Marshal.load(Marshal.dump(state))
      trial[:balls] = result.balls.map(&:dup)
      Rules.resolve_shot(trial, state, result, move)
      actor = state[:turn]
      others = state[:racks].each_index.reject { |seat| seat == actor }
      value = (trial[:racks][actor] - state[:racks][actor]) * 100_000 -
        others.sum { |seat| (trial[:racks][seat] - state[:racks][seat]) * 100_000 } +
        (trial[:scores][actor] - state[:scores][actor]) * 100 -
        others.sum { |seat| (trial[:scores][seat] - state[:scores][seat]) * 100 } -
        (trial[:ruling][:foul] ? 500 : 0) + (trial[:turn] == actor ? 50 : 0)
      if state[:options]['discipline'] == 'cutthroat'
        value += Cutthroat.remaining(trial, actor) * 20 - others.sum { |seat| Cutthroat.remaining(trial, seat) * 10 }
      end
      value
    end
  end
end
