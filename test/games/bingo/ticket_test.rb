require_relative "../../support/elten_array_shuffle"
require_relative "../../../games/bingo_ticket"

%w[30 75 80 90].each do |variant|
  200.times do |seed|
    random = Random.new(seed)
    cells = GameRoomBingo.ticket(variant, random)
    reference = Random.new(seed)
    raise "Ticket replay changed" unless cells == GameRoomBingo.ticket(variant, reference) && random.rand(10000) == reference.rand(10000)
    width, height = GameRoomBingo.size(variant)
    numbers = cells.compact.reject(&:zero?)
    expected = {"30" => 9, "75" => 24, "80" => 16, "90" => 15}.fetch(variant)
    raise "Ticket shape or duplicate number" unless cells.size == width * height && numbers.size == expected && numbers.uniq == numbers
    raise "Number outside pool" unless numbers.all? { |number| number.between?(1, variant.to_i) }
    width.times do |column|
      values = height.times.map { |row| cells[row * width + column] }.compact.reject(&:zero?)
      first, last = if variant == "90"
        column == 0 ? [1, 9] : column == 8 ? [80, 90] : [column * 10, column * 10 + 9]
      else
        step = variant.to_i / width
        [column * step + 1, (column + 1) * step]
      end
      raise "Wrong column range" unless values.all? { |number| number.between?(first, last) }
      raise "Unsorted/empty 90-ball column" if variant == "90" && (values.empty? || values != values.sort)
    end
    if variant == "90"
      raise "90-ball row must contain five numbers" unless cells.each_slice(9).all? { |row| row.compact.size == 5 }
    elsif variant == "75"
      raise "Missing free centre" unless cells[12] == 0 && cells.count(0) == 1
    end
    raise "Full card not recognized" unless GameRoomBingo.winning?(variant, "full", cells, numbers)
    raise "Empty card wins" if GameRoomBingo.winning?(variant, "full", cells, [])
  end
end
cells = GameRoomBingo.ticket("75", Random.new(8))
raise "Free-centre diagonal failed" unless GameRoomBingo.winning?("75", "line", cells, [0, 6, 18, 24].map { |i| cells[i] })
cells = GameRoomBingo.ticket("90", Random.new(8))
raise "90-ball two rows failed" unless GameRoomBingo.winning?("90", "two_lines", cells, cells.take(18).compact)
raise "90-ball columns counted as lines" if GameRoomBingo.winning?("90", "line", cells, [0, 9, 18].map { |i| cells[i] }.compact)
puts "Bingo tickets: 800 valid deterministic tickets, host shuffle API, ranges, free centre and patterns passed"
