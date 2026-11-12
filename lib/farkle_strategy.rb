require_relative "game_bots"

module FarklePlanning
  RollOutcome = Struct.new(:weight, :choices, keyword_init: true)

  # Exact distributions of unordered dice rolls.  A multiset is evaluated once
  # and carries the number of ordered rolls it represents.
  class OutcomeCatalog
    def initialize(game)
      @game = game
      @outcomes = {}
    end

    def for_dice(count)
      @outcomes[count.to_i] ||= build(count.to_i)
    end

    private

    def build(count)
      (1..6).to_a.repeated_combination(count).map do |roll|
        choices = {}
        (1...(1 << count)).each do |mask|
          dice = count.times.filter_map { |index| roll[index] if (mask & (1 << index)) != 0 }
          score = @game.score_selection(dice)
          next if score == nil

          kept = dice.length
          previous = choices[kept]
          choices[kept] = score.to_i if previous == nil || score.to_i > previous
        end
        RollOutcome.new(
          weight: permutation_count(roll),
          choices: choices.map { |kept, score| [score, kept] }
        )
      end
    end

    def permutation_count(values)
      numerator = factorial(values.length)
      denominator = values.tally.values.reduce(1) { |product, count| product * factorial(count) }
      numerator / denominator
    end

    def factorial(value)
      (2..value.to_i).reduce(1, :*)
    end
  end

  # A finite-horizon expectimax player.  Unlike blind self-play it directly
  # computes Farkle probabilities from the six-sided dice and the real scoring
  # function, including hot dice and the configured banking thresholds.
  class Strategy
    include GameRoomBots::ReplayOnlyStrategy

    attr_reader :last_stats

    def initialize(max_future_rolls: 3)
      @max_future_rolls = [max_future_rolls.to_i, 1].max
      @catalogs = {}
      @value_cache = {}
      @last_stats = {}
    end

    def choose(actions:, actor:, random_source:, game:, replay:, **_extra)
      choices = actions.to_a
      return nil if choices.empty?
      return choices.first if choices.length == 1

      state = replay.state
      @value_cache.clear if @value_cache.length > 100_000
      cache_before = @value_cache.length
      @memo = @value_cache
      @evaluations = 0
      @catalog = (@catalogs[game.class.name] ||= OutcomeCatalog.new(game))
      players = game.tournament_remaining_players(state)
      player = players.find { |candidate| game.send(:same_user?, candidate, actor) }
      banked = state[:scores].fetch(player, 0).to_i
      limit = state[:options]["score_limit"].to_i
      minimum = banked.zero? ? state[:options]["entry_minimum"].to_i : state[:options]["turn_minimum"].to_i
      leader = GameRoomParticipants.excluding(players, [player]).map { |candidate| state[:scores].fetch(candidate) }.max.to_i
      @new_rules = state[:options]["farkle_rules_version"].to_i >= 2
      @leader = leader
      @remaining_turns = players.length - players.index(player).to_i - 1
      @last_player = @remaining_turns == 0
      @final_round = state[:final_round] == true
      @terminal_race = @new_rules && @last_player && (@final_round || banked + state[:turn_points].to_i >= limit)
      @race_key = [@new_rules,@leader,@remaining_turns,@final_round,@terminal_race]
      # A small curvature changes risk preference, not the amount of searching.
      # No giant bonus for a remote hypothetical winning roll.
      @risk_exponent = if leader >= limit * 0.8 && leader > banked
        1.1
      elsif banked >= limit * 0.7 && banked > leader
        0.9
      else
        1.0
      end

      selected = if state[:phase] == :selecting
        choose_keep(choices, game, replay, banked, limit, minimum)
      else
        choose_roll_or_bank(choices, state, banked, limit, minimum)
      end
      @last_stats = {
        evaluations: @evaluations,
        memo_entries: @memo.length,
        new_memo_entries: @memo.length - cache_before
      }
      selected || choices.first
    ensure
      @memo = @value_cache
    end

    private

    def choose_keep(actions, game, replay, banked, limit, minimum)
      winning = actions.select do |action|
        details = game.bot_keep_details(replay, action)
        total = details && replay.state[:turn_points].to_i + details[:points]
        total && total >= minimum && guaranteed_win?(banked + total,limit)
      end
      return winning.max_by { |action| game.bot_keep_details(replay, action)[:points] } unless winning.empty?

      actions.max_by do |action|
        details = game.bot_keep_details(replay, action)
        next -Float::INFINITY if details == nil

        total = replay.state[:turn_points].to_i + details[:points]
        value = decision_value(
          details[:dice_to_roll],
          total,
          banked,
          limit,
          minimum,
          @max_future_rolls
        )
        [value, details[:points], details[:dice_to_roll]]
      end
    end

    def choose_roll_or_bank(actions, state, banked, limit, minimum)
      bank = actions.find { |action| action["action"].to_s == "bank" }
      roll = actions.find { |action| action["action"].to_s == "roll" }
      return bank if bank != nil && guaranteed_win?(banked + state[:turn_points].to_i,limit)
      return roll if bank == nil
      return bank if roll == nil
      # Banking a known loss cannot improve on a legal chance to catch up,
      # even when doing so needs more rolls than our finite search horizon.
      return roll if @terminal_race && banked + state[:turn_points].to_i < @leader

      bank_value = bank_payoff(state[:turn_points].to_i, banked, limit)
      roll_value = expected_roll_value(
        state[:dice_to_roll].to_i,
        state[:turn_points].to_i,
        banked,
        limit,
        minimum,
        @max_future_rolls
      )
      roll_value > bank_value ? roll : bank
    end

    def decision_value(dice, turn_points, banked, limit, minimum, depth)
      key = [dice, turn_points, banked, limit, minimum, depth, @risk_exponent, @race_key]
      cached = @memo[key]
      return cached if cached != nil

      can_bank = turn_points >= minimum
      bank_value = can_bank ? bank_payoff(turn_points, banked, limit) : -Float::INFINITY
      return @memo[key] = bank_value if can_bank && guaranteed_win?(banked+turn_points,limit)
      if depth <= 0
        return @memo[key] = (can_bank ? bank_value : 0.0)
      end

      roll_value = expected_roll_value(dice, turn_points, banked, limit, minimum, depth)
      @memo[key] = [bank_value, roll_value].max
    end

    def expected_roll_value(dice, turn_points, banked, limit, minimum, depth)
      @evaluations += 1
      Thread.pass if (@evaluations % 128).zero?
      denominator = 6**dice.to_i
      total_value = @catalog.for_dice(dice).sum do |outcome|
        value = if outcome.choices.empty?
          @terminal_race ? bank_payoff(0,banked,limit) : 0.0
        else
          outcome.choices.map do |points, kept|
            remaining = dice.to_i - kept.to_i
            remaining = 6 if remaining == 0
            decision_value(
              remaining,
              turn_points + points,
              banked,
              limit,
              minimum,
              depth - 1
            )
          end.max
        end
        outcome.weight * value
      end
      total_value.to_f / denominator
    end

    def bank_payoff(turn_points, banked, limit)
      if @terminal_race
        total = banked + turn_points
        return 1.0 if total > @leader
        return 0.5 if total == @leader
        return 0.0
      end
      needed = [limit - banked, 1].max.to_f
      progress = [turn_points / needed, 0.0].max
      progress = [progress,1.0].min unless @new_rules
      value = needed * progress**(@risk_exponent || 1.0)
      # Above the threshold points still protect a lead against players who
      # have not taken their turn yet. This does not add search branches.
      if @new_rules && @final_round
        before = [banked-@leader,0].max
        after = [banked+turn_points-@leader,0].max
        value += (after-before).to_f / (@remaining_turns+1)
      end
      value
    end

    def guaranteed_win?(total,limit)
      total >= limit && (!@new_rules || (@last_player && total > @leader))
    end
  end
end
