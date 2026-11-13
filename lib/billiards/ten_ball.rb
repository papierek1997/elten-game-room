require_relative 'rules'

module GameRoomBilliards
  module TenBall
    module_function
    def rack(options, number)
      t = Rules.table(options)
      random = Random.new(options.fetch('rack_seed', 0) + number)
      ids = GameRoomRandom.shuffle((2..9).to_a, random: random)
      ids.unshift(1); ids.insert(4, 10)
      balls = [Ball.new(id: 0, x: t.width / 4 - 0.1, y: t.height / 2)]
      [1, 2, 3, 4].each_with_index do |count, row|
        count.times do |col|
          balls << Ball.new(id: ids.shift, x: t.width * 0.75 + row * Math.sqrt(3) * t.radius * 1.0003,
            y: t.height / 2 + (2 * col - count + 1) * t.radius * 1.0003)
        end
      end
      balls.sort_by(&:id)
    end
    def setup(_state); end
    def cue_id(_state); 0; end
    def points?; false; end
    def uses_calls?; true; end
    def targets(state); [state[:balls].select { |b| b.on_table? && b.id != 0 }.map(&:id).min].compact; end
    def declaration?(state, data)
      return false unless data['cue'] == 0
      return data['call'] == 0 && data['mode'] == 0 if state[:breaking]
      return data['call'] == 0 && state[:push_available] if data['mode'] == 2
      data['mode'] == 0 && state[:balls].any? { |b| b.id == data['call'] && b.id != 0 && b.on_table? }
    end
    def choose(_state, _choice); false; end
    def resolve(state, before, result, data)
      actor, pots = before[:turn], Rules.pot_ids(result)
      outside = result.events.select { |e| e[:kind] == :off }.map { |e| e[:a] }
      foul = outside.any? ? :off_table : Rules.common_pool_foul(before.merge(declaration: data), result, push: data['mode'] == 2)
      state[:hand], state[:push_available], state[:breaking] = nil, false, false
      state[:ruling] = {foul: foul}
      if foul
        state[:fouls][actor] += 1
        Rules.spot_pool(state, 10) if pots.include?(10) || outside.include?(10)
        state[:turn], state[:hand] = 1 - actor, :any
        return Rules.finish_rack(state, 1 - actor) if state[:fouls][actor] >= 3
        return
      end
      state[:fouls][actor] = 0
      success = result.events.any? { |e| e[:kind] == :pocket && e[:a] == data['call'] && e[:pocket] == data['pocket'] }
      if !before[:breaking] && data['mode'] == 0 && targets(before) == [10] && data['call'] == 10 && success
        return Rules.finish_rack(state, actor)
      end
      Rules.spot_pool(state, 10) if pots.include?(10)
      if data['mode'] == 2 || !before[:breaking] && !success && (pots - [0]).any?
        state[:turn], state[:choices], state[:decision] = 1 - actor, %w[accept return], :ten_option
      elsif before[:breaking]
        state[:push_available] = true
        state[:turn] = 1 - actor if pots.empty?
      elsif !success
        state[:turn] = 1 - actor
      end
    end
  end
  Rules.register_engine('ten', TenBall)
end
