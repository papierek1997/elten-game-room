# encoding: UTF-8
require_relative '../../support/ui'
require_relative '../../support/log'

class Program
  def self.server_app(**_options); end
end

require_relative '../../../__app'
require_relative '../../support/session_runner'

def assert(value, message)
  raise message unless value
end

game = GameRoomGames::Darts.new
options = game.default_options.merge('rounds' => 1, 'bot_delay' => 0)
bot_count = game.maximum_players
harness = NativeRoomHarness.new(game: game, users: ['Host'], bots: bot_count, options: options)
harness.as('Host') do
  harness.transports['Host'].set_observer(harness.table, true, actor: 'Host')
end
bots = harness.transports['Host'].room_snapshot(harness.table)[:bots]
assert(bots.length == bot_count, 'the observer table did not retain the maximum number of computer seats')

session = harness.as('Host') do
  harness.repositories['Host'].start_session(table: harness.table, game: game.id,
    players: bots, options: JSON.generate(options))
end
harness.instance_variable_set(:@session, session)

runner = runner_for(harness, 'Host')
runner.instance_variable_get(:@context_template).random_source = GameRoomRandom::SeededSource.new(137)
tick = 0.0
runner.instance_variable_get(:@turn).instance_variable_set(:@clock, -> { tick })

60.times do
  tick += 2.0
  snapshot = harness.repositories['Host'].snapshot_for(harness.session)
  replay = game.replay(snapshot.session, snapshot.events, harness.repositories['Host'])
  runner.publish_view(session: snapshot.session, replay: replay, busy: false, context: runner.send(:context))
  step(harness, runner, 'Host')
  break if harness.replay('Host').finished?
end

replay = harness.replay('Host')
events = harness.events('Host')
assert(replay.finished?, 'a host observing an all-computer Darts game left it without an active turn')
assert(events.count { |event| event['action'] == 'darts_start' } == 1,
  'the all-computer game did not start exactly once')
assert(events.count { |event| event['action'] == 'darts_throw' } == bot_count * 3,
  'the full computer table did not finish all three darts per player')
assert(events.all? { |event| replay.accepted_events.include?(event) },
  'the all-computer game wrote an event rejected by replay')

runner.close
puts 'PASS Darts observer host: a full computer table starts and finishes its game'
