module GameRoomGames
  module BalutScoring
    module_function

    TARGETS = {fours: 52, fives: 65, sixes: 78, choice: 100}.freeze
    FACES = {fours: 4, fives: 5, sixes: 6}.freeze
    CATEGORIES = %i[fours fives sixes straight full_house balut choice].freeze

    def score(category, dice)
      raise ArgumentError, "Expected five dice" unless dice.length == 5 && dice.all? { |d| (1..6).include?(d) }
      return dice.count(FACES[category]) * FACES[category] if FACES.key?(category)

      case category
      when :choice then dice.sum
      when :straight then dice.uniq.length == 5 && dice.max - dice.min == 4 ? dice.sum : 0
      when :full_house then dice.tally.values.sort == [2, 3] ? dice.sum : 0
      when :balut then dice.uniq.one? ? 50 : 0
      else raise ArgumentError, "Unknown category"
      end
    end

    def record(sheet, category, dice)
      return false unless CATEGORIES.include?(category)
      row = sheet.fetch(category)
      return false if row.length >= 4
      row << score(category, dice)
      true
    end

    def adjustment(raw_total)
      return -2 if raw_total < 300
      [(raw_total - 350).div(50), 6].min
    end

    def row_points(category, row)
      return row.sum >= TARGETS.fetch(category) ? 2 : 0 if TARGETS.key?(category)
      return 2 * row.count(&:positive?) if category == :balut
      return 0 unless row.size == 4 && row.all?(&:positive?)

      {straight: 4, full_house: 3}.fetch(category)
    end

    def current_result(sheet)
      raw = CATEGORIES.sum { |category| sheet.fetch(category).sum }
      points = CATEGORIES.sum { |category| row_points(category, sheet.fetch(category)) }
      {raw: raw, points: points + adjustment(raw)}
    end

    # A read-only hint: no further choice can repair a zero in the four
    # required straights/full houses, or a numeric target beyond remaining dice.
    def row_points_possible?(category, row)
      return true if row_points(category, row).positive?
      remaining = 4 - row.length
      return false unless remaining.positive?
      if TARGETS.key?(category)
        maximum = FACES.key?(category) ? FACES.fetch(category) * 5 : 30
        row.sum + remaining * maximum >= TARGETS.fetch(category)
      else
        category == :balut || row.all?(&:positive?)
      end
    end

    def result(sheet)
      current_result(sheet) if CATEGORIES.all? { |category| sheet.fetch(category).length == 4 }
    end
  end
end
