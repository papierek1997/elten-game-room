# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../../support/assertions"
require_relative "../../../games/duck_racing_support/race"

# Independent reducer scenarios. This file intentionally does not load other
# *_test.rb files, call the UI/network, or treat fabricated input as a live trial.
module DuckRaceAdversarial
  extend GameRoomTest::Assertions
  Race = GameRoomDuckRacing::Race
  Board = GameRoomDuckRacing::Board
  Cards = GameRoomDuckRacing::Cards
  Settlement = GameRoomDuckRacing::Settlement
  Feathers = GameRoomDuckRacing::Feathers
  Dice = GameRoomDuckRacing::Dice

  class ScriptRandom
    attr_reader :draws

    def initialize(values, seed: 445)
      @values, @fallback, @draws = values.dup, Random.new(seed), []
    end

    def rand(bound)
      value = @values.empty? ? @fallback.rand(bound) : @values.shift
      raise "Invalid scripted draw #{value.inspect} for #{bound}" unless value.is_a?(Integer) && value.between?(0, bound - 1)
      @draws << [bound, value]
      value
    end
  end

  class << self
    attr_reader :results, :metrics

    def check(name)
      @results ||= []
      @metrics ||= Hash.new(0)
      yield
      @results << {name: name, status: "PASS"}
      puts "PASS #{name}"
    rescue StandardError => error
      @results << {name: name, status: "FAIL", error: "#{error.class}: #{error.message}", backtrace: error.backtrace.first(6)}
      puts "FAIL #{name}: #{error.message}"
    end

    def state(count: 3, laps: 3, positions: nil, seed: 733, feathers: nil)
      value = Race.start(player_count: count, laps: laps, seed: seed,
        enabled_challenges: ["dice_duel"])
      if positions
        value[:occupants] = {}
        positions.each_with_index do |progress, seat|
          value[:racers].fetch(seat)[:progress] = progress
          Board.arrive!(value[:occupants], seat, Board.square(progress))
        end
      end
      value[:racers].each_value { |racer| racer[:feathers] = feathers } unless feathers.nil?
      value
    end

    def copy(value)
      Marshal.load(Marshal.dump(value))
    end

    def semantic(value)
      case value
      when Hash then value.transform_values { |item| semantic(item) }
      when Array then value.map { |item| semantic(item) }
      when Data then [value.class.name, semantic(value.to_h)]
      when Random, ScriptRandom then [value.class.name, Marshal.dump(value)]
      else value
      end
    end

    # Marshal byte streams encode object sharing too: a reloaded card type
    # string need not be the manifest's same String object. Compare values,
    # including each complete RNG state, not those irrelevant object links.
    def same_replay(left, right, message = "Replay differs")
      expected, actual = semantic(left), semantic(right)
      different = expected.keys.select { |key| expected[key] != actual[key] }
      assert(different.empty?, "#{message}; differing fields: #{different.inspect}")
    end

    def add_card(state, type, seat: state[:turn])
      card = Cards::Copy.new("adversarial-#{state[:next_card]}", type)
      state[:next_card] += 1
      state[:racers].fetch(seat)[:hand] << card
      card
    end

    def trap(state, square, type, owner: 1)
      state[:traps][square] = {card: Cards::Copy.new("placed-#{square}-#{type}", type), owner: owner}
    end

    def play(state, type, target: nil)
      card = add_card(state, type)
      action = {kind: :play, card: card.id}
      action[:target] = target unless target.nil?
      assert(Race.new(state).apply(seat: state[:turn], revision: state[:revision], action: action), "Rejected #{type}")
      card
    end

    def roll(state, value = 1)
      state[:random] = ScriptRandom.new([value - 1])
      assert(Race.new(state).apply(seat: state[:turn], revision: state[:revision], action: {kind: :roll}))
    end

    def settle(state, winner: nil, amount: 0, answers: nil)
      challenge = state.fetch(:challenge)
      balances = challenge[:participants].to_h { |seat| [seat, state[:racers].fetch(seat)[:feathers]] }
      result = if answers
        Settlement.quiz(balances: balances, answers: answers)
      else
        Settlement.fixed(balances: balances, winner: winner, amount: amount)
      end
      assert(Race.new(state).complete_challenge(id: challenge[:id], result: result))
      result
    end

    def reject_unchanged(state, seat:, revision:, action:)
      before = Marshal.dump(state)
      assert_equal(false, Race.new(state).apply(seat: seat, revision: revision, action: action))
      assert_equal(before, Marshal.dump(state), "Rejected command changed state or RNG")
    end

    def invariant(state)
      assert([:turn, :challenge, :finished].include?(state[:phase]))
      racers = state.fetch(:racers)
      assert(racers.key?(state[:turn]))
      assert(state[:revision].is_a?(Integer) && state[:revision] >= 0)
      ids = []
      racers.each do |seat, racer|
        assert(racer[:feathers].is_a?(Integer) && racer[:feathers] >= 0, "Negative feather balance for #{seat}")
        assert(racer[:progress].is_a?(Integer) && racer[:progress] >= 0)
        assert(racer[:skip_turns].is_a?(Integer) && racer[:skip_turns] >= 0)
        assert(racer[:frozen_turns].is_a?(Integer) && racer[:frozen_turns].between?(0, 4))
        assert(Dice::SIDES.include?(racer[:die_sides]))
        assert(racer[:die_rolls].is_a?(Integer) && racer[:die_rolls] >= 0)
        assert_equal(racer[:die_sides] == 6, racer[:die_rolls].zero?)
        racer[:hand].each { |card| assert(Cards::BY_ID.key?(card.type)); ids << card.id }
        next if state[:phase] == :finished && seat == state[:winner]
        assert_equal([Board.square(racer[:progress])], state[:occupants].select { |_square, present| present.include?(seat) }.keys)
      end
      state[:traps].each do |square, placed|
        assert(square.between?(1, 30))
        assert(racers.key?(placed[:owner]))
        assert_equal(:square, Cards::BY_ID.fetch(placed[:card].type).target)
        ids << placed[:card].id
      end
      assert_equal(ids.uniq.length, ids.length, "A physical card exists more than once")
      assert_equal(racers.keys.sort, state[:occupants].values.flatten.sort)
      state[:occupants].each_value { |present| assert_equal(present.length, present.uniq.length) }
      if state[:phase] == :challenge
        challenge = state.fetch(:challenge)
        assert(challenge[:participants].length >= 2)
        assert_equal(challenge[:participants].length, challenge[:participants].uniq.length)
        unless challenge[:kind] == "quiz" && [:square_question, :question_card].include?(challenge[:trigger])
          assert(challenge[:participants].all? { |seat| racers.fetch(seat)[:frozen_turns].zero? })
        end
      elsif state[:phase] == :finished
        assert(racers.fetch(state[:winner])[:progress] >= 30 * state[:laps])
        assert_equal([], state[:pending])
      else
        assert_equal(nil, state[:challenge])
        assert_equal([], state[:pending])
      end
    end

    def action_choices(state)
      seat = state[:turn]
      racer = state[:racers].fetch(seat)
      return [{kind: :skip}] if racer[:skip_turns] > 0 || racer[:frozen_turns] > 0
      choices = [{kind: :roll}]
      return choices if state[:card_played]
      racer[:hand].each do |card|
        type = Cards::BY_ID.fetch(card.type)
        next if racer[:feathers] < type.cost
        next if type.target == :square && state[:traps].key?(Board.square(racer[:progress]))
        targets = [:self, :square].include?(type.target) ? [seat] : state[:racers].keys
        targets.each do |target|
          next if type.target == :opponent && target == seat
          next if type.id == "challenge" && state[:racers][target][:frozen_turns] > 0
          choices << {kind: :play, card: card.id, target: target}
        end
      end
      choices
    end
  end
end

a = DuckRaceAdversarial

a.check("allocation, selected pool and unique cards at 2-8 seats / 1-12 laps") do
  a.assert_equal((1..11).to_a + (23..48).to_a, a::Cards::TYPES.map(&:reference))
  (2..8).each do |count|
    (1..12).each do |laps|
      state = a.state(count: count, laps: laps)
      state[:racers].each_value do |racer|
        a.assert_equal(laps * 6, racer[:feathers])
        a.assert_equal(3, racer[:hand].length)
      end
      a.invariant(state)
    end
  end
end

# Every card executes against a copied replay. This is not a claim about
# undocumented card costs; only Impulsion and Golden sleep were explicitly
# settled in the plan. Other manifest values are exercised, not re-invented.
a::Cards::TYPES.each do |type|
  a.check("card #{type.reference}: #{type.id} legal effect, identities, replay and stale retry") do
    state = a.state(positions: [8, 20, 26], feathers: 100)
    card = a.add_card(state, type.id)
    hand_count = state[:racers].values.sum { |racer| racer[:hand].length }
    target = [:opponent, :any].include?(type.target) ? 1 : 0
    action = {kind: :play, card: card.id, target: target}
    twin = a.copy(state)
    a.assert(a::Race.new(state).apply(seat: 0, revision: 0, action: action))
    a.assert(a::Race.new(twin).apply(seat: 0, revision: 0, action: a.copy(action)))
    a.same_replay(state, twin)
    a.reject_unchanged(state, seat: 0, revision: 0, action: action)
    draws = state[:notices].select { |notice| notice.first == :drew_cards }.sum { |notice| notice[2] }
    a.assert_equal(hand_count - 1 + draws, state[:racers].values.sum { |racer| racer[:hand].length })
    a.assert(!state[:racers].values.any? { |racer| racer[:hand].any? { |held| held.id == card.id } })
    a.assert_equal(0, state[:racers][0][:die_rolls]) unless %w[opportunistic_die winning_die].include?(type.id)
    a.invariant(state)
    if type.target == :square
      a.assert_equal(card, state[:traps].fetch(9)[:card])
      a.assert_equal(100 - type.cost + type.gain, state[:racers][0][:feathers])
      # The first arrival fires the trap, never its initial placement.
      state[:turn] = 1
      state[:card_played] = false
      state[:racers][1][:progress] = 7
      a::Board.arrive!(state[:occupants], 1, 8)
      a.roll(state)
      a.assert(!state[:traps].key?(9), "#{type.id} was not consumed on landing")
      a.assert_equal(1, state[:notices].count { |notice| notice.first == :trap && notice[2] == type.id })
      a.invariant(state)
    end
  end
end

a.check("illegal targets, unaffordable cards and stale revisions never consume RNG") do
  a::Cards::TYPES.each do |type|
    state = a.state(feathers: 100)
    card = a.add_card(state, type.id)
    invalid = ["0", :zero, -1, 8, 999]
    invalid << 0 if type.target == :opponent
    invalid << 1 if [:self, :square].include?(type.target)
    invalid.each do |target|
      a.reject_unchanged(state, seat: 0, revision: 0, action: {kind: :play, card: card.id, target: target})
    end
    if type.cost > 0
      state[:racers][0][:feathers] = type.cost - 1
      target = [:self, :square].include?(type.target) ? 0 : 1
      a.reject_unchanged(state, seat: 0, revision: 0, action: {kind: :play, card: card.id, target: target})
    end
  end
  state = a.state
  [nil, "0", 0.0, -1, 8].each { |seat| a.reject_unchanged(state, seat: seat, revision: 0, action: {kind: :roll}) }
  [nil, "0", 0.0, -1, 1].each { |revision| a.reject_unchanged(state, seat: 0, revision: revision, action: {kind: :roll}) }
  [nil, [], {}, {kind: "roll"}, {kind: :skip}, {kind: :play, card: "absent"}].each do |action|
    a.reject_unchanged(state, seat: 0, revision: 0, action: action)
  end
end

a.check("square 19 makes all eight independent probability combinations") do
  (0...8).each do |mask|
    state = a.state(positions: [17, 2, 8])
    state[:random] = a::ScriptRandom.new([0] + (0..2).map { |bit| mask[bit] == 1 ? 59 : 60 })
    a.assert(a::Race.new(state).apply(seat: 0, revision: 0, action: {kind: :roll}))
    a.assert_equal(18 + mask[0], state[:racers][0][:feathers])
    a.assert_equal(3 + mask[1], state[:racers][0][:hand].length)
    a.assert_equal(mask[2], state[:racers][0][:skip_turns])
    a.assert_equal([6, 100, 100, 100], state[:random].draws.first(4).map(&:first))
    a.assert_equal(1, state[:turn])
    a.invariant(state)
  end
end

a.check("question square completes before its trap and then exactly one encounter") do
  state = a.state(positions: [5, 6, 8])
  a.trap(state, 7, "tar_stain", owner: 1)
  a.roll(state)
  first = state[:challenge][:id]
  a.assert_equal("quiz", state[:challenge][:kind])
  a.assert_equal(18, state[:racers][0][:feathers])
  a.assert(state[:traps].key?(7))
  a.settle(state, answers: {0 => true, 1 => false, 2 => false})
  a.assert_equal(18, state[:racers][0][:feathers], "Reward should arrive before the 4-feather trap")
  a.assert_equal(22, state[:racers][1][:feathers])
  a.assert_equal("dice_duel", state[:challenge][:kind])
  a.assert_equal([1, 0], state[:challenge][:participants])
  a.assert_equal(first + 1, state[:challenge][:id])
  a.assert_equal([:challenge_result, :trap, :stole_feathers, :challenge], state[:notices].map(&:first))
  a.settle(state)
  a.assert_equal(:turn, state[:phase])
  a.assert_equal(1, state[:turn])
  a.invariant(state)
end

a.check("a moved destination cancels old trap/encounter but resolves the new trap") do
  state = a.state(positions: [14, 15, 8])
  a.trap(state, 16, "detour", owner: 1)
  a.trap(state, 9, "mine", owner: 2)
  state[:random] = a::ScriptRandom.new([0, 6, 0]) # roll 1; square 16 moves back 7.
  a.assert(a::Race.new(state).apply(seat: 0, revision: 0, action: {kind: :roll}))
  a.assert_equal(0, state[:racers][0][:progress])
  a.assert_equal(19, state[:racers][0][:feathers])
  a.assert_equal([16], state[:traps].keys)
  a.assert_equal(nil, state[:challenge])
  a.assert_equal([:rolled, :moved, :moved, :trap, :moved, :feathers], state[:notices].map(&:first))
  a.invariant(state)
end

a.check("latest arrival pairing is A-B / B-C / C-D regardless of past winners") do
  [[3, 0, 1], [0, 1, 2]].each do |winners|
    state = a.state(count: 4, positions: [1, 31, 61, 2], feathers: 100)
    [[3, 0], [0, 1], [1, 2]].each_with_index do |pair, index|
      a.roll(state)
      a.assert_equal(pair, state[:challenge][:participants])
      a.settle(state, winner: winners[index], amount: 1)
    end
    a.assert_equal([3, 0, 1, 2], state[:occupants][3])
    a.invariant(state)
  end
end

a.check("freeze ignores ordinary skip and uses the most recent nonfrozen occupant") do
  state = a.state(count: 4, positions: [1, 2, 32, 62])
  state[:racers][2][:skip_turns] = 3
  state[:racers][3][:frozen_turns] = 4
  a.roll(state)
  a.assert_equal([2, 0], state[:challenge][:participants])
  a.settle(state)
  a.assert_equal(4, state[:racers][3][:frozen_turns])
end

a.check("Curiosity's final feather is not frozen before the question reward") do
  [true, false].each do |correct|
    state = a.state(count: 2, positions: [2, 8])
    state[:racers][0][:feathers] = 1
    a.play(state, "curiosity")
    a.assert_equal(0, state[:racers][0][:frozen_turns], "The card still has an unresolved question")
    a.settle(state, answers: {0 => correct, 1 => false})
    a.assert_equal(correct ? 4 : 0, state[:racers][0][:feathers])
    a.assert_equal(correct ? 0 : 1, state[:racers][0][:frozen_turns])
  end
end

a.check("losing a question at zero freezes before the remaining trap chain; cancellation does not") do
  [false, true].each do |cancel|
    state = a.state(count: 2, positions: [2, 8])
    state[:racers][0][:feathers] = 7
    a.trap(state, 7, "mine", owner: 1)
    a.play(state, "helix", target: 0)
    a.assert_equal("quiz", state[:challenge][:kind])
    a.assert_equal(0, state[:racers][0][:feathers])
    if cancel
      a.assert(a::Race.new(state).cancel_challenge(id: state[:challenge][:id]))
    else
      a.settle(state, answers: {0 => false, 1 => false})
    end
    a.assert_equal(0, state[:racers][0][:progress])
    a.assert_equal(1, state[:racers][0][:feathers])
    a.assert_equal(cancel ? 0 : 1, state[:racers][0][:frozen_turns],
      "A later start-square reward must not undo freezing after a lost challenge")
    a.assert_equal(0, state[:turn])
    a.assert_equal(true, state[:card_played])
    a.assert_equal({}, state[:traps])
    a.invariant(state)
  end
end

a.check("cancellation keeps accepted costs, rejects duplicate IDs and resumes the ordinary roll") do
  state = a.state(count: 2, positions: [2, 8])
  card = a.play(state, "curiosity")
  id = state[:challenge][:id]
  before = Marshal.dump(state)
  a.assert_equal(false, a::Race.new(state).cancel_challenge(id: id + 1))
  a.assert_equal(before, Marshal.dump(state))
  a.assert(a::Race.new(state).cancel_challenge(id: id))
  a.assert_equal(17, state[:racers][0][:feathers])
  a.assert_equal(0, state[:turn])
  a.assert_equal(true, state[:card_played])
  a.assert(!state[:racers][0][:hand].include?(card))
  before = Marshal.dump(state)
  a.assert_equal(false, a::Race.new(state).cancel_challenge(id: id))
  a.assert_equal(before, Marshal.dump(state))
  a.roll(state)
  a.assert_equal(1, state[:turn])
  a.invariant(state)
end

a.check("freeze duration follows absolute gap and is fixed until one thaw grant") do
  (0..120).each do |gap|
    racers = {0 => {progress: 60 + gap, feathers: 0, frozen_turns: 0},
      1 => {progress: 60, feathers: 10, frozen_turns: 0}}
    a.assert_equal([0], a::Feathers.start_freezes!(racers, board_length: 30))
    expected = [1 + gap / 10, 4].min
    a.assert_equal(expected, racers[0][:frozen_turns])
    racers[1][:progress] = 0
    a.assert_equal([], a::Feathers.start_freezes!(racers, board_length: 30))
    a.assert_equal(expected, racers[0][:frozen_turns])
    racers[0][:feathers] = 4 # Quiz is allowed while already frozen.
    expected.times { |index| a.assert_equal(index == expected - 1 ? :thawed : :frozen, a::Feathers.skip_frozen_turn!(racers[0])) }
    a.assert_equal(9, racers[0][:feathers])
    a.assert_equal(nil, a::Feathers.skip_frozen_turn!(racers[0]))
    a.assert_equal(9, racers[0][:feathers])
  end
end

a.check("current pre-roll freeze consumes this turn without a die use or another card") do
  state = a.state(count: 2, positions: [2, 8])
  state[:racers][0][:feathers] = 5
  a.play(state, "opportunistic_die")
  hand = a.copy(state[:racers][0][:hand])
  a.assert_equal([0, 1, 10, 2], state[:racers][0].values_at(:feathers, :frozen_turns, :die_sides, :die_rolls))
  revision = state[:revision]
  a.reject_unchanged(state, seat: 0, revision: revision, action: {kind: :roll})
  a.assert(a::Race.new(state).apply(seat: 0, revision: revision, action: {kind: :skip}))
  a.assert_equal([5, 0, 10, 2, hand], state[:racers][0].values_at(:feathers, :frozen_turns, :die_sides, :die_rolls, :hand))
  a.reject_unchanged(state, seat: 0, revision: revision, action: {kind: :skip})
end

a.check("a post-roll skip starts next turn; ordinary and frozen counters decrease together") do
  state = a.state(count: 2, positions: [9, 2])
  a.roll(state)
  a.assert_equal(1, state[:racers][0][:skip_turns])
  a.assert_equal(1, state[:turn])
  a.roll(state)
  state[:racers][0].merge!(feathers: 4, frozen_turns: 1)
  a.assert(a::Race.new(state).apply(seat: 0, revision: state[:revision], action: {kind: :skip}))
  a.assert_equal([9, 0, 0], state[:racers][0].values_at(:feathers, :frozen_turns, :skip_turns))
  a.assert_equal(1, state[:turn])
end

a.check("spending and stealing can recover before freeze; transfers never create missing feathers") do
  state = a.state(positions: [8, 2, 11])
  state[:racers][0][:feathers] = 1
  state[:racers][1][:feathers] = 2
  a.play(state, "interested_help", target: 1)
  a.assert_equal([2, 1, 18], state[:racers].values.map { |racer| racer[:feathers] })
  a.assert_equal([0, 0, 0], state[:racers].values.map { |racer| racer[:frozen_turns] })
  a.assert_equal([:stole_feathers, 0, 1, 2], state[:notices].find { |notice| notice.first == :stole_feathers })
  state = a.state(positions: [2, 5, 14])
  state[:racers][0][:feathers] = 2
  state[:racers][1][:feathers] = 4
  a.play(state, "paid_service", target: 1)
  a.assert_equal([4, 0, 18], state[:racers].values.map { |racer| racer[:feathers] })
  a.assert_equal([0, 1, 0], state[:racers].values.map { |racer| racer[:frozen_turns] })
end

a.check("backtracking every lap boundary and finish crossing do not allocate lap feathers") do
  (1..5).each do |laps|
    (0...(laps * 30)).each do |progress|
      [-150, -61, -31, -30, -15, -1, 0, 1, 15, 30, 31, 150].each do |distance|
        movement = a::Board.advance(progress, by: distance, laps: laps)
        expected = [progress + distance, 0].max
        a.assert_equal([expected, expected % 30 + 1, expected / 30 + 1, expected >= 30 * laps],
          [movement.progress, movement.square, movement.lap, movement.finished])
      end
    end
  end
  state = a.state(count: 2, positions: [28, 8])
  a.play(state, "impulsion", target: 0)
  a.assert_equal(30, state[:racers][0][:progress])
  a.assert_equal(16, state[:racers][0][:feathers]) # 18 - cost3 + square1, no new lap allocation.
  state = a.state(count: 2, laps: 1, positions: [28, 8])
  a.trap(state, 1, "mine", owner: 1)
  a.play(state, "impulsion", target: 0)
  a.assert_equal(:finished, state[:phase])
  a.assert_equal(3, state[:racers][0][:feathers]) # Finish before the square bonus/trap.
  a.assert(state[:traps].key?(1))
  a.assert_equal([], state[:pending])
end

a.check("independent difference and fixed-stake oracles, including busts, ties and no winner") do
  random = Random.new(1975)
  2_000.times do |index|
    count = random.rand(2..8)
    balances = (0...count).to_h { |seat| [seat, random.rand(0..40)] }
    scores = balances.transform_values { random.rand(-30..60) }
    ceiling = [nil, 21, 25].fetch(index % 3)
    eligible = scores.select { |_seat, score| ceiling.nil? || score <= ceiling }
    leaders = eligible.select { |_seat, score| score == eligible.values.max }.keys
    winner = leaders.one? ? leaders.first : nil
    expected = balances.dup
    if winner
      expected.each_key do |loser|
        next if loser == winner
        transfer = [(scores[winner] - scores[loser]).abs, balances[loser]].min
        expected[loser] -= transfer
        expected[winner] += transfer
      end
    end
    expected.each_key { |seat| expected[seat] = [expected[seat] - [scores[seat] - ceiling, 0].max, 0].max } if ceiling
    before = Marshal.dump([balances, scores])
    result = a::Settlement.difference(balances: balances, scores: scores, ceiling: ceiling)
    a.assert_equal(winner, result.winner)
    a.assert_equal(expected, result.balances)
    a.assert_equal(balances.values.sum - result.burned.values.sum, result.balances.values.sum)
    a.assert_equal(before, Marshal.dump([balances, scores]))
    winner = balances.keys[random.rand(count + 1)]
    expected = balances.dup
    if winner
      expected.each_key do |loser|
        next if loser == winner
        amount = [4, balances[loser]].min
        expected[loser] -= amount
        expected[winner] += amount
      end
    end
    result = a::Settlement.fixed(balances: balances, winner: winner, amount: 4)
    a.assert_equal(winner, result.winner)
    a.assert_equal(expected, result.balances)
    a.metrics[:settlement_oracle_cases] += 2
  end
end

a.check("seeded whole-race fuzz: replay after every action, stale delivery and cancellation") do
  chooser = Random.new(84_429)
  (2..8).each do |count|
    8.times do |example|
      seed = 913_000 + count * 100 + example
      state = a.state(count: count, laps: example % 3 + 1, seed: seed)
      3_000.times do |step|
        break if state[:phase] == :finished
        twin = a.copy(state)
        if state[:phase] == :challenge
          id = state[:challenge][:id]
          if chooser.rand(5).zero?
            a.assert(a::Race.new(state).cancel_challenge(id: id))
            a.assert(a::Race.new(twin).cancel_challenge(id: id))
            a.metrics[:fuzz_cancellations] += 1
          else
            seats = state[:challenge][:participants]
            balances = seats.to_h { |seat| [seat, state[:racers][seat][:feathers]] }
            result = if state[:challenge][:kind] == "quiz"
              a::Settlement.quiz(balances: balances, answers: seats.to_h { |seat| [seat, chooser.rand(2).zero?] })
            else
              a::Settlement.difference(balances: balances, scores: seats.to_h { |seat| [seat, chooser.rand(1..12)] })
            end
            a.assert(a::Race.new(state).complete_challenge(id: id, result: result))
            a.assert(a::Race.new(twin).complete_challenge(id: id, result: result))
          end
          before = Marshal.dump(state)
          a.assert_equal(false, a::Race.new(state).cancel_challenge(id: id))
          a.assert_equal(before, Marshal.dump(state))
        else
          choices = a.action_choices(state)
          action = choices.fetch(chooser.rand(choices.length))
          seat, revision = state.values_at(:turn, :revision)
          a.reject_unchanged(state, seat: seat, revision: revision + 1, action: action)
          a.assert(a::Race.new(state).apply(seat: seat, revision: revision, action: action), "Rejected generated legal action seed=#{seed} step=#{step}: #{action}")
          a.assert(a::Race.new(twin).apply(seat: seat, revision: revision, action: a.copy(action)))
          a.reject_unchanged(state, seat: seat, revision: revision, action: action)
        end
        a.same_replay(state, twin, "Replay divergence seed=#{seed} step=#{step}")
        a.invariant(state)
        a.metrics[:fuzz_actions] += 1
      end
      a.assert_equal(:finished, state[:phase], "Race did not finish seed=#{seed}; this deterministic trial is incomplete")
      a.metrics[:fuzz_completed_races] += 1
    end
  end
end

summary = {scope: "local models only; no live accounts, UI or audio", results: a.results, metrics: a.metrics}
if ARGV[0]
  report = File.expand_path(ARGV[0])
  FileUtils.mkdir_p(File.dirname(report))
  previous = File.file?(report) ? JSON.parse(File.read(report)) : {"runs" => []}
  previous.fetch("runs") << summary
  File.write(report, JSON.pretty_generate(previous))
end
puts JSON.generate({scenarios: a.results.length, passed: a.results.count { |result| result[:status] == "PASS" }, metrics: a.metrics})
exit(a.results.all? { |result| result[:status] == "PASS" } ? 0 : 1)
