require_relative "../lib/game_random"

module GameRoomBingo
  module_function

  def size(variant)
    {"30" => [3, 3], "75" => [5, 5], "80" => [4, 4], "90" => [9, 3]}.fetch(variant)
  end

  def ticket(variant, random)
    return ticket90(random) if variant == "90"
    width, height = size(variant)
    step = variant.to_i / width
    columns = width.times.map do |column|
      GameRoomRandom.shuffle(((column * step + 1)..((column + 1) * step)).to_a, random: random).take(height)
    end
    cells = height.times.flat_map { |row| width.times.map { |column| columns[column][row] } }
    cells[12] = 0 if variant == "75"
    cells
  end

  def ticket90(random)
    counts = Array.new(9, 1)
    6.times do
      available = (0...9).select { |column| counts[column] < 3 }
      counts[available[random.rand(available.size)]] += 1
    end
    cells, capacity = Array.new(27), [5, 5, 5]
    # Largest columns first preserve five cells per row without rejection draws.
    columns = GameRoomRandom.shuffle((0...9).to_a, random: random).sort_by { |column| -counts[column] }
    columns.each do |column|
      rows = GameRoomRandom.shuffle((0...3).to_a, random: random).sort_by { |row| -capacity[row] }.take(counts[column]).sort
      first, last = column == 0 ? [1, 9] : column == 8 ? [80, 90] : [column * 10, column * 10 + 9]
      values = GameRoomRandom.shuffle((first..last).to_a, random: random).take(rows.size).sort
      rows.each_with_index { |row, index| cells[row * 9 + column] = values[index]; capacity[row] -= 1 }
    end
    raise "Invalid bingo ticket allocation" unless capacity == [0, 0, 0]
    cells
  end

  def lines(variant)
    width, height = size(variant)
    rows = height.times.map { |row| width.times.map { |column| row * width + column } }
    return rows if variant == "90"
    columns = width.times.map { |column| height.times.map { |row| row * width + column } }
    rows + columns + [width.times.map { |i| i * width + i }, width.times.map { |i| i * width + width - i - 1 }]
  end

  def complete?(cells, positions, marked)
    positions.all? { |index| cells[index].nil? || cells[index] == 0 || marked.include?(cells[index]) }
  end

  def winning?(variant, pattern, cells, marked)
    width, height = size(variant)
    case pattern
    when "line" then lines(variant).any? { |positions| complete?(cells, positions, marked) }
    when "two_lines" then lines(variant).count { |positions| complete?(cells, positions, marked) } >= 2
    when "corners" then complete?(cells, [0, width - 1, width * (height - 1), width * height - 1], marked)
    when "full" then complete?(cells, (0...cells.size).to_a, marked)
    else raise ArgumentError, "Unknown bingo pattern"
    end
  end
end
