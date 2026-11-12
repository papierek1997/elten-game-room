require_relative '../../support/assertions'
require_relative '../../support/elten_array_shuffle'
require_relative '../../../games/duck_racing_support/challenge_bot'

include GameRoomTest::Assertions
engine = GameRoomDuckRacing::NumericChallenges
bot = GameRoomDuckRacing::NumericBot

# Natural original challenge: the public one-digit hint must inform the bot
# just as it limits the human's ordinary numeric input field.
state = engine.start('guess_number', seats: [0, 1], seed: 67, now_ms: 0)
view = engine.public_view(state, viewer: 0)
assert_equal(1, view.fetch(:answer_digits), 'Natural one-digit fixture changed')
choice = bot.choose(view, seat: 0, random: Random.new(71))
assert_equal(1, choice.fetch(:value).to_s.length, 'Bot ignored the public digit hint and guessed outside the human input width')
[0, 4, '1', nil].each do |width|
  assert_raises(ArgumentError) { bot.choose(view.merge(answer_digits: width), seat: 0, random: Random.new(71)) }
end

# Targets are local oracle fixtures, never inputs to the selector. Every
# proposal goes through the actual public projection and normal reducer.
maximum = Hash.new(0)
(1..999).each do |target|
  state = engine.start('guess_number', seats: [0, 1], seed: 67, now_ms: 0)
  state[:answer] = target
  random = Random.new(target + 71)
  digits = target.to_s.length
  until state[:players].fetch(0)[:done]
    view = engine.public_view(state, viewer: 0)
    before = Marshal.dump(view)
    rng_before = Marshal.dump(random)
    choice = bot.choose(view, seat: 0, random: random)
    assert_equal(before, Marshal.dump(view), 'Selector changed its public input')
    assert_equal(digits, choice.fetch(:value).to_s.length, 'An intermediate guess escaped the advertised width')
    poisoned = Marshal.load(before)
    poisoned[:answer] = 1_000_000
    poisoned[:seed] = -1
    poisoned[:private_values] = {target: target}
    assert_equal(choice, bot.choose(poisoned, seat: 0, random: Marshal.load(rng_before)), 'Bot used an unrelated secret/future key')
    player = state[:players].fetch(0)
    press = player.fetch(:last_press_id) + 1
    assert(engine.submit(state, seat: 0, action: choice.merge(press_id: press), now_ms: press * 1_300), 'Normal reducer rejected the width-aware proposal')
  end
  player = state[:players].fetch(0)
  attempts = player.fetch(:attempts).size
  assert_equal(0, player.fetch(:best).fetch(:distance), 'Bot failed to find an available target exactly')
  maximum[digits] = [maximum[digits], attempts].max
  assert(attempts <= {1=>4, 2=>7, 3=>10}.fetch(digits), 'Width-aware interval search exceeded its bounded information search')
end

challenge = {id: 17, kind: 'guess_number', participants: [0, 1], seed: 67,
  race_snapshot: {board_length: 30, laps: 3, racers: [0, 1].to_h do |seat|
    [seat, {progress: seat * 4, feathers: 18, card_count: 3, die_sides: 6, die_rolls: 0}]
  end}}
trace = GameRoomDuckRacing::ChallengeBot.plan(challenge, seat: 0, seed: 71)
guesses = trace.fetch('actions').select { |row| row.fetch('input').fetch('kind') == 'answer' }
assert(guesses.all? { |row| row.fetch('input').fetch('value').between?(1, 9) }, 'Private bot planner discarded the public width')
verifier = GameRoomDuckRacing::TraceVerifier.new(challenge: challenge, balances: {0=>100, 1=>100})
verified = verifier.replay(traces: {0=>trace}, forfeits: [1])
assert_equal(0, verified.results.fetch(0).fetch(:best).fetch(:distance), 'Actual private verifier rejected the improved trace')

puts "PASS guess bot public width: 999 oracle targets through projection/reducer; max attempts #{maximum.sort.to_h}; private planner/verifier and hidden-key isolation"
