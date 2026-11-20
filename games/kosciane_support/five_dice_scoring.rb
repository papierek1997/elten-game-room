module GameRoomGames
  module FiveDiceScoring
    SCHOOL = (1..6).to_a.freeze
    COMBINATIONS = %i[pair two_pairs triple four small_straight large_straight full_house poker chance].freeze
    FIXED = {triple: 20, small_straight: 25, large_straight: 30, full_house: 35, four: 40, poker: 50}.freeze

    def self.categories(parity: false)
      SCHOOL + COMBINATIONS + (parity ? %i[even odd] : [])
    end

    def self.bonuses_enabled?(columns)
      columns >= 3
    end

    # Returns [points, change to the reserve for this number], or nil.
    def self.score(category, dice, reserve: 0, fixed: false, double_first: false, rolls: 1)
      return unless dice.size == 5 && dice.all? { |die| SCHOOL.include?(die) }
      counts = dice.tally
      if SCHOOL.include?(category)
        count = counts.fetch(category, 0)
        return if count.zero? || count + reserve < 3
        return [count * category, count - 3]
      end
      pairs = counts.keys.select { |face| counts[face] >= 2 }.sort.reverse
      groups = ->(size) { counts.keys.select { |face| counts[face] >= size }.max }
      points = case category
      when :pair then pairs.first && pairs.first * 2
      when :two_pairs then pairs.size >= 2 ? pairs.first(2).sum * 2 : nil
      when :triple then groups.call(3)&.*(3)
      when :four then groups.call(4)&.*(4)
      when :poker then groups.call(5)&.*(5)
      when :small_straight, :large_straight
        length = category == :small_straight ? 4 : 5
        (1..(7 - length)).reverse_each.lazy.map { |start| start...(start + length) }
          .find { |run| run.all? { |face| counts.key?(face) } }&.sum
      when :full_house then counts.values.sort == [2, 3] ? dice.sum : nil
      when :even then dice.all?(&:even?) ? dice.sum : nil
      when :odd then dice.all?(&:odd?) ? dice.sum : nil
      when :chance then dice.sum
      end
      return unless points
      points = FIXED.fetch(category, points) if fixed
      points *= 2 if double_first && rolls == 1
      [points, 0]
    end
  end
end
