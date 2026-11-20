module GameRoomBots
  # A bounded proof of a finish using only the actor's already known choices.
  # Games provide their real transitions and decide where unknown input starts.
  # Exhaustion means "not proved", never proof that a different root loses.
  class OwnContinuations
    attr_reader :nodes

    def initialize(limit:)
      @limit = limit
    end

    def finishes(state, actions:, next_actions:, transition:, finished:, key:)
      @nodes, @memo = 0, {}
      @next_actions, @transition, @finished, @key = next_actions, transition, finished, key
      actions.select do |action|
        following = step(state, action)
        following && finish?(following)
      end
    ensure
      @memo = @next_actions = @transition = @finished = @key = nil
    end

    private

    def step(state, action)
      return nil if @nodes >= @limit
      @nodes += 1
      Thread.pass if (@nodes % 32).zero?
      @transition.call(state, action)
    end

    def finish?(state)
      return true if @finished.call(state)
      identity = @key.call(state)
      return @memo[identity] if @memo.key?(identity)
      @memo[identity] = false
      @memo[identity] = @next_actions.call(state).any? do |action|
        following = step(state, action)
        following && finish?(following)
      end
    end
  end
end
