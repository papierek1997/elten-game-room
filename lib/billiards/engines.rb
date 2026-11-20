require_relative 'friendly'

module GameRoomBilliards
  module Rules
    @engines = {'friendly'=>Friendly}.freeze
    module_function
    def engine(options); @engines[options['discipline']]; end
    def advanced?(options); Table::TELEMETRY.include?(options['discipline']); end
    def calls_break?(options); options['discipline'] == 'straight'; end
    def register_engine(id, implementation)
      raise ArgumentError, 'Duplicate billiards engine' if @engines.key?(id) && @engines[id] != implementation
      @engines = @engines.merge(id=>implementation).freeze
    end
    def cue_id(state)
      implementation = engine(state[:options])
      implementation ? implementation.cue_id(state) : 0
    end
    def points_game?(state)
      implementation = engine(state[:options])
      implementation ? implementation.points? : snooker?(state)
    end
    def targets(state)
      implementation = engine(state[:options])
      return implementation.targets(state) if implementation
      snooker?(state) ? snooker_targets(state) : pool_targets(state)
    end
    def resolve_shot(state, before, result, data)
      implementation = engine(state[:options])
      return implementation.resolve(state, before, result, data) if implementation
      snooker?(state) ? snooker_shot(state, before, result, data) : pool_shot(state, before, result, data)
    end
    def concede(state)
      implementation = engine(state[:options])
      return implementation.concede(state) if implementation&.respond_to?(:concede)
      finish_rack(state, (state[:turn] + 1) % state[:racks].length)
    end

    def practice_balls(layout)
      t = Table.new
      balls = [Ball.new(id: 0, x: 0.635, y: 0.635)]
      return balls + [Ball.new(id: 1, x: 1.27, y: 0.635)] if layout == 'single'
      sizes = layout == 'diamond' ? [1, 2, 3, 2, 1] : [1, 2, 3, 4, 5]
      sizes.each_with_index do |count, row|
        count.times do |column|
          balls << Ball.new(id: balls.size, x: 1.905 + row * Math.sqrt(3) * t.radius * 1.0001,
            y: 0.635 + (2 * column - count + 1) * t.radius * 1.0001)
        end
      end
      balls
    end
  end
end
require_relative 'ten_ball'
require_relative 'blackball'
require_relative 'cutthroat'
require_relative 'points_pool'
require_relative 'english_billiards'
require_relative 'carom'
require_relative 'pyramid'
