require_relative 'bots_helpers'

# Model-only real action_for/Session/ChallengeEngine transitions. The fixture
# supplies a challenge card; no clock, turn or engine result is patched.
include DuckBotFixture

def memory_turn_fixture
  fixture = DuckBotFixture::Fixture.new(kind: 'sound_memory', flow: 2)
  fixture.challenge
  fixture.state[:options]['bot_delay'] = 1
  fixture
end

def expire_memory_turn(fixture)
  round = fixture.state.fetch(:round)
  deadline = round.fetch(:started_at) + round.fetch(:engine).fetch(:model).fetch(:public).fetch(:turn_deadline_ms)
  assert_equal('advance', LOGIC::Session.automatic(fixture.state, now_ms: deadline))
  fixture.apply({'kind' => 'duck', 'action' => 'advance', 'challenge' => round.fetch(:challenge).fetch(:id)}, at: deadline)
  deadline
end

cases = []
check = lambda do |name, &operation|
  operation.call
  cases << [name, nil]
rescue StandardError => error
  cases << [name, "#{error.class}: #{error.message}"]
end

check.call('timeout after first reveal starts the next bot delay at its actual turn') do
  fixture = memory_turn_fixture
  round = fixture.state.fetch(:round)
  engine = round.fetch(:engine)
  first = LOGIC::ChallengeEngine.current_turn(engine)
  fixture.apply({'kind' => 'duck', 'action' => 'input', 'challenge' => round.fetch(:challenge).fetch(:id),
    'input' => {'kind' => 'reveal', 'value' => 1, 'press_id' => 1}}, seat: first, at: round.fetch(:started_at) + 200)
  before_times = fixture.state.fetch(:round).fetch(:engine).fetch(:last_time).dup
  deadline = expire_memory_turn(fixture)
  current = fixture.state.fetch(:round).fetch(:engine)
  next_seat = LOGIC::ChallengeEngine.current_turn(current)
  assert_equal(1 - first, next_seat)
  assert_equal(before_times, current.fetch(:last_time), 'Expiry must not invent a player input')
  view = LOGIC::ChallengeEngine.view(current, seat: next_seat)
  assert_equal(15_000, view.fetch(:public).fetch(:turn_started_ms))
  assert(!view.key?(:turn_started_at_ms), 'Audio memory must exercise its own public turn boundary')
  snapshot = Marshal.dump(fixture.state)
  entry = fixture.game.plan_duck_bot(fixture.replay, fixture.players.fetch(next_seat), context: fixture.context(deadline))
  assert_equal(snapshot, Marshal.dump(fixture.state), 'Planning changed the accepted session')
  assert(entry.fetch(:ready_ms) >= deadline + 1_000,
    "Bot ready at #{entry.fetch(:ready_ms)} before new turn #{deadline} plus configured delay")
  assert(!fixture.game.duck_bot_ready?(entry, fixture.replay, fixture.context(deadline)))
  assert(!fixture.game.duck_bot_ready?(entry, fixture.replay, fixture.context(entry.fetch(:ready_ms) - 1)))
  assert(fixture.game.duck_bot_ready?(entry, fixture.replay, fixture.context(entry.fetch(:ready_ms))))
  fixture.apply({'kind' => 'duck', 'action' => 'input', 'challenge' => round.fetch(:challenge).fetch(:id),
    'input' => entry.fetch(:input)}, seat: next_seat, at: entry.fetch(:ready_ms))
  assert_equal(entry.fetch(:input).fetch('press_id'), fixture.state.fetch(:round).fetch(:engine).fetch(:last_press).fetch(next_seat))
end

check.call('timeout-only turn change renews the scheduler decision identity') do
  fixture = memory_turn_fixture
  previous = fixture.game.bot_delay_revision(fixture.replay, [0, 0])
  expire_memory_turn(fixture)
  current = fixture.game.bot_delay_revision(fixture.replay, [0, 0])
  assert(previous != current, 'Memory turn expiry reused the previous scheduler decision identity')
end

check.call('same bot after two empty turns cannot reuse an expired cached plan') do
  fixture = memory_turn_fixture
  round = fixture.state.fetch(:round)
  seat = LOGIC::ChallengeEngine.current_turn(round.fetch(:engine))
  actor = fixture.players.fetch(seat)
  first = fixture.game.plan_duck_bot(fixture.replay, actor, context: fixture.context(round.fetch(:started_at)))
  expire_memory_turn(fixture)
  deadline = expire_memory_turn(fixture)
  assert_equal(seat, LOGIC::ChallengeEngine.current_turn(fixture.state.fetch(:round).fetch(:engine)))
  second = fixture.game.plan_duck_bot(fixture.replay, actor, context: fixture.context(deadline))
  assert(!second.equal?(first), 'Memory returned the cached plan from this bot\'s previous turn')
  assert(second.fetch(:ready_ms) >= deadline + 1_000, 'Renewed plan ignored the current memory turn')
  assert_equal(second, fixture.game.plan_duck_bot(fixture.replay, actor, context: fixture.context(deadline + 1)),
    'An unchanged memory turn must retain the same plan')
end

cases.each { |name, error| (error ? warn("FAIL #{name}: #{error}") : puts("PASS #{name}")) }
raise "#{cases.count { |_, error| error }} memory bot turn-delay checks failed" if cases.any? { |_, error| error }
puts "PASS Duck memory turn delay: #{cases.length} legal session scenarios"
