require_relative 'private_simulation'
require_relative '../../lib/server_random'

module GameRoomTest
  # For protocols which require native draw evidence and a wall clock. Keep
  # this separate from the historical event-count fixtures: their RNG streams
  # and serialized histories must not change when a new game is registered.
  class NativeSimulation < PrivateSimulation
    def initialize(**arguments)
      super
      @native_now = [100, *@events.map { |event| event['created_at'].to_i }].max
    end

    def context
      super.tap { |value| value.now = @native_now; value.server_random = true }
    end

    def stabilize!
      120.times do
        super
        break if finished? || @game.active_actors(replay).any?
        @native_now += 1
      end
      self
    end

    private

    def append_plan(plan, actor)
      start = @events.length
      # Preserve the production action and native recipe. The fixture supplies
      # only entropy/time; it never substitutes a game-owned rule or decision.
      commands = plan.events.map do |command|
        request = GameRoomServerRandom.request_from([command])
        next command unless request
        values = @random_source.roll(count: request['count'], sides: request['sides']).values
        value = if request['format'] == 'recipe'
          GameRoomServerRandomRendering.render(request.fetch('recipe'), values)
        elsif request['format'] == 'seed'
          request['prefix'] + values.map { |number| (number - 1).to_s(16).rjust(2, '0') }.join
        else
          dice = request['keep'] + values
          dice.sort! if request['sort']
          dice.join(',')
        end
        GameRoomGames::EventCommand.new(action: command.action, value: value).tap do |result|
          result.instance_variable_set(:@native_request, request)
        end
      end
      # The ordinary append hook may reduce immediately; invalidate its cache
      # again after attaching evidence, exactly as a native readback would.
      super(GameRoomGames::ActionPlan.new(events: commands), actor)
      @events.drop(start).zip(commands).each do |event, command|
        event['created_at'] = @native_now
        request = command.instance_variable_get(:@native_request)
        event['__server_random'] = request if request
      end
      @replay = nil
      @legal_actions_cache = {}
    end
  end
end
