require_relative '../../support/session_runner'
require_relative '../../../games/monopoly'

# The real executor, repository and native-session broker, not the headless
# simulation alone. Only the human seat is driven by the fixture; the seven
# computers must be scheduled and authenticated by the ordinary runner.
game = GameRoomGames::Monopoly.new
h = NativeRoomHarness.new(game:game, users:['Alice'], bots:7, options:{'bot_delay'=>0})
h.start
runner = runner_for(h)
runner.instance_variable_get(:@context_template).random_source = GameRoomRandom::SeededSource.new(137)
clock = 0.0
runner.instance_variable_get(:@turn).instance_variable_set(:@clock, -> { clock })
begin
  120.times do
    clock += 2
    step(h, runner)
    replay = h.replay('Alice')
    break if replay.finished?
    actions = game.legal_actions(replay, 'Alice')
    next if actions.empty?
    context = runner.send(:context)
    selected = game.bot_strategy.choose(actions:actions, actor:'Alice', game:game, replay:replay,
      context:context, random_source:context.random_source)
    h.as('Alice') do
      status, = runner.submit(session:h.session, replay:replay, selection:selected, actor:'Alice')
      assert(status == :ok, "Native human action rejected: #{status}")
    end
  end
  events = h.events('Alice')
  replay = h.replay('Alice')
  assert(events.size > 50, 'Eight-seat executor fixture did not progress')
  assert(replay.accepted_events.size == events.size, 'Executor wrote a rejected action')
  actors = events.map { |event| h.repositories['Alice'].actor_of(event, h.session) }.uniq
  assert(actors.size == 8, 'Not all seven computers and the human played')
  assert(replay.state[:owners].size > 10, 'Native match never reached a developed ownership state')
  assert(replay.history.map(&:key).uniq.size == replay.history.size, 'Cached native history duplicated messages')
  puts "PASS Monopoly eight-seat native executor: #{events.size} accepted actions, all seven bots, ordinary human commits and stable history"
ensure
  runner.close
end
