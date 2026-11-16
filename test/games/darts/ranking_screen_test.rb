require_relative '../../support/ui'
require_relative '../../support/native_tasks'
require_relative '../../../lib/darts/rankings/screen'

def assert(value, message); raise message unless value; end
def _(text); text; end
def loop_update(*); Thread.pass; end
def alert(message); raise "Unexpected ranking failure dialog: #{message}"; end

received = nil
store = Object.new
store.define_singleton_method(:ranking) do |**options|
  received = options[:cancellation_token]
  received&.cancel
  raise EltenAPI::Tasks::Cancelled, 'Cancelled test ranking read'
end
service = Struct.new(:store).new(store)
screen = GameRoomDartsRankings::Screen.new(program:Object.new, game:Object.new, service:service)
screen.send(:show_ranking, 'normal', 'triple')
assert(received.is_a?(EltenAPI::Tasks::CancellationToken), 'The ranking read did not receive the native task cancellation token')
assert(received.cancelled?, 'The native ranking task did not preserve cancellation')
puts 'PASS Darts ranking screen: native task cancellation reaches the store without a failure dialog'
