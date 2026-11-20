require_relative "game_participants"

module GameRoomBots
  Decision = Struct.new(:actor, :action, :available_actions, keyword_init: true)

  # Expected match outcome first, expected game points only to break ties.
  # Arithmetic lets a finite chance tree preserve this order without a giant
  # arbitrary winning bonus that could distort very small probabilities.
  class ExpectedValue < Struct.new(:outcome, :points)
    include Comparable

    def <=>(other)
      return [outcome, points] <=> [other,0] if other.is_a?(Numeric)
      [outcome, points] <=> [other.outcome, other.points]
    end

    def +(other)
      return self if other.is_a?(Numeric) && other.zero?
      self.class.new(outcome + other.outcome, points + other.points)
    end

    def /(number); self.class.new(outcome / number.to_f, points / number.to_f); end
    def -(penalty); self.class.new(outcome, points - penalty); end
    def coerce(number); [self.class.new(number,0),self]; end
    def to_f; outcome.to_f; end
  end

  # An explicit opt-out for strategies that use only the supplied replay and
  # action context. Unknown/external strategies retain the full environment.
  # A strategy that starts using simulation must override this contract.
  module ReplayOnlyStrategy
    def simulation_required?
      false
    end
  end

  module_function

  # Older game strategies only accepted the original four keywords. Filtering
  # here keeps them compatible while new strategies can receive the game and a
  # forkable simulation environment.
  def choose(strategy, arguments)
    parameters = strategy.method(:choose).parameters
    accepts_all = parameters.any? { |kind, _name| kind == :keyrest }
    accepted = parameters.each_with_object([]) do |(kind, name), names|
      names << name if [:key, :keyreq].include?(kind)
    end
    keywords = accepts_all ? arguments : arguments.select { |key, _value| accepted.include?(key) }
    # Observation can map a long event history. Build it only if the actual
    # keyword contract receives it; unknown **keywords strategies still do.
    if block_given? && !keywords.key?(:observation) && (accepts_all || accepted.include?(:observation))
      keywords = keywords.merge(observation: yield)
    end
    strategy.choose(**keywords)
  end

  def random_choice(choices, random_source)
    values = choices.to_a
    return nil if values.empty?
    return values.first if values.length == 1

    roll = random_source.roll(count: 1, sides: values.length)
    values[roll.values.first.to_i - 1]
  end

  class RandomStrategy
    include ReplayOnlyStrategy

    def choose(actions:, observation:, actor:, random_source:, **_extra)
      GameRoomBots.random_choice(actions, random_source)
    end
  end

  class HeuristicStrategy
    include ReplayOnlyStrategy

    def choose(actions:, actor:, random_source:, game: nil, replay: nil, context: nil, **_extra)
      if game == nil || replay == nil
        draw = actions.to_a.find { |action| action["action"].to_s == "draw" }
        return draw if draw != nil

        return GameRoomBots.random_choice(actions, random_source)
      end

      scored = actions.to_a.map do |action|
        value = game.bot_action_score(replay, actor, action, context: context)
        [action, value.is_a?(ExpectedValue) ? value : value.to_f]
      end
      return nil if scored.empty?

      best_score = scored.map(&:last).max
      GameRoomBots.random_choice(
        scored.select { |_action, score| score == best_score }.map(&:first),
        random_source
      )
    end
  end

  class Coordinator
    def initialize(strategy: RandomStrategy.new)
      @strategy = strategy
    end

    def pending_bot(game, replay, controlled_actors: [])
      return nil if replay == nil || replay.finished?

      game.active_actors(replay).find { |actor| GameRoomParticipants.bot?(actor) || GameRoomParticipants.includes?(controlled_actors, actor) }
    end

    def decide_next(game:, replay:, context:, simulation: nil, simulation_factory: nil, strategy: nil, controlled_actors: [])
      return nil if replay == nil || replay.finished?

      game.active_actors(replay).each do |actor|
        next if !GameRoomParticipants.bot?(actor) && !GameRoomParticipants.includes?(controlled_actors, actor)

        decision = decide(
          game: game,
          replay: replay,
          actor: actor,
          context: context,
          simulation: simulation,
          simulation_factory: simulation_factory,
          strategy: strategy, controlled_actors: controlled_actors
        )
        return decision if decision != nil
      end
      nil
    end

    def decide(game:, replay:, actor:, context:, simulation: nil, simulation_factory: nil, strategy: nil, controlled_actors: [])
      return nil if replay == nil || replay.finished?
      return nil if actor == nil || (!GameRoomParticipants.bot?(actor) && !GameRoomParticipants.includes?(controlled_actors, actor))
      return nil if !game.supports_bots?

      actions = game.legal_actions(replay, actor, context: context).to_a
      return nil if actions.empty?

      selected_strategy = strategy || game.bot_strategy || @strategy
      if simulation == nil && simulation_factory &&
          (!selected_strategy.respond_to?(:simulation_required?) || selected_strategy.simulation_required?)
        simulation = simulation_factory.call
      end
      action = GameRoomBots.choose(selected_strategy, {
        actions: actions,
        actor: actor,
        random_source: context.random_source,
        game: game,
        replay: replay,
        context: context,
        simulation: simulation
      }) { game.bot_observation(replay, actor) }
      return nil if action == nil

      Decision.new(actor: actor.to_s, action: action, available_actions: actions)
    end
  end
end
