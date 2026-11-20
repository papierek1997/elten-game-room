require_relative '../../lib/five_dice_planner'

module GameRoomGames
  # A bounded estimate, not a rollout of opponents or future dice. Each school
  # row is targeted through three rolls; failed attempts can use a remaining
  # combination box. Cross-row lucky outcomes are deliberately not assumed.
  class GeneralSchoolStrategy
    def initialize(match, actor)
      @rows = match.sheet(actor).select { |category, _| category.is_a?(Integer) }.to_h do |category, row|
        [category, [match.columns - row.size, match.reserve(actor, category)].freeze]
      end.freeze
      @flexible = match.sheet(actor).reject { |category, _| category.is_a?(Integer) }.sum do |_, row|
        match.columns - row.size
      end
      @bonuses = match.bonuses(actor).values.sum
      @row_distributions, @survivals = {}, {}
    end

    def value(category, reserve_delta, bonus)
      if category.is_a?(Integer)
        slots, reserve = @rows.fetch(category)
        remaining = slots - 1
        # At least one matching die must come from a future roll, hence at
        # most two reserve dice can ever be spent per future entry.
        capacity = 2 * remaining
        reserve_value = category * ([reserve + reserve_delta, capacity].min - [reserve, capacity].min)
        rows = @rows.merge(category => [remaining, reserve + reserve_delta]).values
      else
        reserve_value = 0
      end
      return reserve_value if @bonuses.zero? && bonus.zero?

      @before ||= survival(@rows.values, @flexible)
      after = survival(rows || @rows.values, category.is_a?(Integer) ? @flexible : @flexible - 1)
      reserve_value + (@bonuses + bonus) * after - @bonuses * @before
    end

    private

    def survival(rows, flexible)
      active = rows.reject { |slots, _| slots.zero? }.sort
      return 1.0 if active.empty?
      key = [active, flexible]
      return @survivals[key] if @survivals.key?(key)

      total = [1.0] + Array.new(flexible, 0.0)
      active.each do |slots, reserve|
        row = failure_distribution(slots, reserve, flexible)
        combined = Array.new(flexible + 1, 0.0)
        total.each_with_index do |weight, used|
          next if weight.zero?
          row.first(flexible - used + 1).each_with_index { |chance, extra| combined[used + extra] += weight * chance }
        end
        total = combined
      end
      @survivals.shift if @survivals.size >= 128
      @survivals[key] = total.sum.clamp(0.0, 1.0)
    end

    def failure_distribution(slots, reserve, flexible)
      return [1.0] + Array.new(flexible, 0.0) if slots.zero?
      key = [slots, reserve, flexible]
      return @row_distributions[key] if @row_distributions.key?(key)

      result = Array.new(flexible + 1, 0.0)
      failure = 0.0
      GameRoomFiveDicePlanner::TARGET_COUNTS.each_with_index do |weight, count|
        if count.zero? || count + reserve < 3
          failure += weight
        else
          child = failure_distribution(slots - 1, reserve + count - 3, flexible)
          child.each_with_index { |chance, extra| result[extra] += weight * chance }
        end
      end
      1.upto(flexible) { |extra| result[extra] += failure * result[extra - 1] }
      @row_distributions.shift if @row_distributions.size >= 512
      @row_distributions[key] = result.freeze
    end
  end
end
