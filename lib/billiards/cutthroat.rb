require_relative 'rules'

module GameRoomBilliards
  # Power Games club rules: fixed seat groups, every foul revives opponents.
  module Cutthroat
    module_function
    def rack(options, number)
      balls = Rules.rack(options.merge('discipline'=>'eight'), number)
      # One ball of each group at the three corners.
      objects = balls.reject { |b| b.id == 0 }
      back = objects.select { |b| (b.x - objects.map(&:x).max).abs < 1e-8 }
      corners = [objects.min_by(&:x), back.min_by(&:y), back.max_by(&:y)].map { |b| [b.x, b.y] }
      [1, 6, 11].zip(corners).each do |id, position|
        a, b = balls.find { |v| v.id == id }, balls.find { |v| [v.x, v.y] == position }
        a.x, b.x, a.y, b.y = b.x, a.x, b.y, a.y
      end
      balls
    end
    def setup(state)
      state[:groups], state[:cutthroat_conceded] = [0, 1, 2], [false, false, false]
    end
    def cue_id(_state); 0; end
    def points?; false; end
    def uses_calls?; false; end
    def choose(state, choice)
      return false unless choice == 'agree' && state[:decision] == :stalemate && state[:offer_remaining].length == 1
      conceded = state[:cutthroat_conceded].dup
      breaker = state[:breaker]
      breaker = (1..3).map { |offset| (breaker + offset) % 3 }.find { |seat| !conceded[seat] } if conceded[breaker]
      state[:rack_number] += 1
      Rules.setup(state, breaker: breaker)
      state[:cutthroat_conceded] = conceded
      state[:balls].each { |ball| ball.status = :potted if owner(ball.id) && conceded[owner(ball.id)] }
      state.delete(:offer_remaining)
      state.delete(:offer_turn)
      true
    end
    def owner(id); id.zero? ? nil : (id - 1) / 5; end
    def targets(state); state[:balls].select { |b| b.id != 0 && b.on_table? }.map(&:id); end
    def declaration?(_state, data); data['cue'] == 0 && data['call'] == 0 && data['mode'] == 0; end
    def remaining(state, seat); state[:balls].count { |b| b.on_table? && owner(b.id) == seat }; end
    def next_player(state, actor)
      (1..3).map { |n| (actor + n) % 3 }.find { |seat| remaining(state, seat) > 0 }
    end
    def concede(state)
      actor = state[:turn]
      state[:cutthroat_conceded] = state[:cutthroat_conceded].dup
      state[:cutthroat_conceded][actor] = true
      state[:balls].each { |b| b.status = :potted if owner(b.id) == actor }
      alive = (0..2).select { |seat| remaining(state, seat) > 0 }
      return Rules.finish_rack(state, alive.first) if alive.length == 1
      state[:turn], state[:hand], state[:choices], state[:decision] = next_player(state, actor), nil, [], nil
    end
    def resolve(state, before, result, data)
      actor, pots = before[:turn], Rules.pot_ids(result)
      foul = Rules.common_pool_foul(before.merge(declaration: data), result)
      state[:ruling], state[:hand], state[:breaking] = {foul: foul}, nil, false
      if foul
        # Opponents recover one ball even after a temporary elimination.
        (0..2).reject { |seat| seat == actor || state[:cutthroat_conceded][seat] }.each do |seat|
          ball = state[:balls].find { |b| !b.on_table? && owner(b.id) == seat }
          Rules.spot_pool(state, ball.id) if ball
        end
        state[:hand] = :any
      end
      alive = (0..2).select { |seat| remaining(state, seat) > 0 }
      return Rules.finish_draw_rack(state) if alive.empty?
      return Rules.finish_rack(state, alive.first) if alive.length == 1
      # A legal self-pot is allowed as a deliberate sacrifice, but ends a
      # visit when the shooter's last ball disappears.
      state[:turn] = next_player(state, actor) if foul || pots.empty? || remaining(state, actor).zero?
    end
  end
  Rules.register_engine('cutthroat', Cutthroat)
end
