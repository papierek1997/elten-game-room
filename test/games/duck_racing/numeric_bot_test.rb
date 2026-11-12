require "json"
require "fileutils"
require_relative "../../support/assertions"
require_relative "../../support/elten_array_shuffle"
require_relative "../../../games/duck_racing_support/numeric_bot"
require_relative "../../../games/duck_racing_support/challenge_engine"

include GameRoomTest::Assertions
engine = GameRoomDuckRacing::NumericChallenges
bot = GameRoomDuckRacing::NumericBot
adapter = GameRoomDuckRacing::ChallengeEngine
snapshot = {board_length: 30, laps: 3, racers: (0..7).to_h do |seat|
  [seat, {progress: seat * 7, feathers: 18 - seat, card_count: 3 + seat}]
end}
results = []

# These are scheduled MODEL actions, not live ELTEN games or physical input.
# Each bot sees exactly its public projection, plus the frozen public facts.
engine::TYPES.each_key do |type|
  counts = %w[rock_paper_scissors numbered_balls].include?(type) ? [2] : [2, 3, 8]
  counts.each do |count|
    20.times do |seed|
      state = engine.start(type, seats: (0...count).to_a, seed: seed, now_ms: 0, race_snapshot: snapshot)
      streams = state[:participants].to_h { |seat| [seat, Random.new(seed * 100 + seat)] }
      due = state[:participants].to_h do |seat|
        view = engine.public_view(state, viewer: seat)
        [seat, bot.reaction_ms(view) + streams[seat].rand(400)]
      end
      steps, now, first_correct = 0, 0, nil
      until state[:finished]
        eligible = state[:participants].reject { |seat| state[:players][seat][:done] }
        eligible = [state[:participants][state[:turn_index]]] if engine::TURN_TYPES.include?(type)
        seat = eligible.min_by { |candidate| due[candidate] }
        at = [due.fetch(seat), now].max
        if at >= state[:deadline_ms]
          assert(engine.expire(state, now_ms: state[:deadline_ms]))
          now = state[:finished] ? state[:finished_at_ms] : state[:turn_started_at_ms]
        else
          view = engine.public_view(state, viewer: seat)
          action = bot.choose(view, seat: seat, random: streams.fetch(seat), race_snapshot: snapshot)
          assert(action, "#{type} bot did not propose an available action")
          action[:press_id] = state[:players].fetch(seat)[:last_press_id] + 1
          assert(engine.submit(state, seat: seat, action: action, now_ms: at), "#{type} rejected bot action #{action.inspect}")
          first_correct ||= seat if engine::ANSWER_TYPES.include?(type) && state[:players].fetch(seat)[:status] == :correct
          now = at
        end
        due[seat] = now + bot.reaction_ms(engine.public_view(state, viewer: seat)) + streams[seat].rand(400)
        if engine::TURN_TYPES.include?(type) && !state[:finished]
          next_seat = state[:participants][state[:turn_index]]
          due[next_seat] = now + bot.reaction_ms(engine.public_view(state, viewer: next_seat)) + streams[next_seat].rand(400)
        end
        steps += 1
        assert(steps <= 100, "#{type} model did not terminate")
      end
      assert(state[:outcome][:settlement_ready], "#{type} bot outcome cannot settle")
      balances = state[:participants].to_h { |seat| [seat, 1_000] }
      outcome = state[:outcome]
      boundary = {kind: type, participants: state[:participants], model: state}
      verified = state[:participants].to_h { |seat| [seat, adapter.result_for(boundary, seat)] }
      if engine::ANSWER_TYPES.include?(type)
        # The standalone model can finish each attempt; the real session
        # accepts only the first correct result in its ordered history.
        verified.each { |seat, result| result[:correct] = seat == first_correct }
      end
      paid = adapter.settlement(type, balances: balances, results: verified, target: state[:answer])
      expected_winner = engine::ANSWER_TYPES.include?(type) ? first_correct : outcome[:winner]
      assert_equal(expected_winner, paid.winner)
      assert(paid.transfers.all? { |transfer| transfer.amount == 4 }, 'First-answer stake changed') if engine::ANSWER_TYPES.include?(type)
      assert(paid.transfers.all? { |transfer| transfer.amount <= 10 }, 'Ball transfer exceeded its cap') if type == 'numbered_balls'
      assert(paid.balances.values.all? { |balance| balance >= 0 })
      assert_equal(balances.values.sum, paid.balances.values.sum + paid.burned.values.sum)
      results << {type: type, participants: count, seed: seed, steps: steps, status: "PASS"}
    end
  end
end

# A bot must not be able to discover the secret or inspect future cards by
# receiving a copied public projection. Poisoned unrelated keys are ignored.
state = engine.start("guess_number", seats: [0, 1], seed: 543, now_ms: 0)
view = engine.public_view(state, viewer: 0)
view[:answer] = 1
view[:answer_digits] = 2 # Keep the public width consistent with the 60..90 feedback fixture.
view[:own][:attempts] = [{value: 60, feedback: :higher}, {value: 90, feedback: :lower}]
before = Marshal.dump(view)
100.times do |seed|
  choice = bot.choose(view, seat: 0, random: Random.new(seed))
  assert([75].include?(choice[:value]), "guess must follow higher/lower feedback, not a secret key")
end
assert_equal(before, Marshal.dump(view), "bot modified its public input")
assert_equal(nil, bot.choose(view, seat: 99, random: Random.new(0)))
view[:finished] = true
assert_equal(nil, bot.choose(view, seat: 0, random: Random.new(0)))

state = engine.start("blackjack", seats: [0, 1], seed: 42, now_ms: 0)
view = engine.public_view(state, viewer: 0)
view[:own].merge!(done: false, total: 16)
view[:turn_seat] = 0
low = bot.choose(view, seat: 0, random: Random.new(0))
view[:deck] = [0]
view[:answer] = "stand"
assert_equal(low, bot.choose(view, seat: 0, random: Random.new(0)))
assert_equal(:hit, low[:kind])
view[:own][:total] = 17
assert_equal(:stand, bot.choose(view, seat: 0, random: Random.new(0))[:kind])

# Off-turn decisions must return before touching the bot's random stream.
engine::TURN_TYPES.each do |type|
  state = engine.start(type, seats: [5, 7], seed: 123, now_ms: 0)
  current = engine.public_view(state, viewer: nil).fetch(:turn_seat)
  other = ([5, 7] - [current]).first
  random = Random.new(99)
  view = engine.public_view(state, viewer: other)
  original_view, original_random = Marshal.dump(view), Marshal.dump(random)
  assert_equal(nil, bot.choose(view, seat: other, random: random), "#{type} bot acted outside its turn")
  assert_equal(original_view, Marshal.dump(view))
  assert_equal(original_random, Marshal.dump(random))
  view = engine.public_view(state, viewer: current)
  action = bot.choose(view, seat: current, random: random)
  assert(action, "#{type} bot did not act during its turn")
  assert(engine.submit(state, seat: current, action: action.merge(press_id: 1), now_ms: 1))
end

# The small ball planner is checked against a separate exhaustive search.
exhaustive = lambda do |balls|
  next 0 if balls.empty?
  (1..[3, balls.length].min).map do |count|
    balls.first(count).sum - exhaustive.call(balls.drop(count))
  end.max
end
[-3, 1, 7].repeated_permutation(6) do |balls|
  view = {type: "numbered_balls", participants: [0, 1], finished: false,
    own: {done: false}, turn_seat: 0, remaining: balls}
  choice = bot.choose(view, seat: 0, random: Random.new(1))
  count = choice.fetch(:value)
  achieved = balls.first(count).sum - exhaustive.call(balls.drop(count))
  assert_equal(exhaustive.call(balls), achieved)
end

report_dir = File.expand_path("../../../tmp/duck-racing", __dir__)
FileUtils.mkdir_p(report_dir)
File.write(File.join(report_dir, "numeric-bot-local.json"), JSON.pretty_generate({
  scope: "Model-only bot decisions and numeric settlement; no live accounts",
  completed_challenges: results.size, results: results,
  exhaustive_ball_positions: 729, privacy_checks: "PASS"
}) + "\n")
puts "PASS #{results.size} numeric bot model challenges; 729 exhaustive ball positions; public-input privacy checks"
