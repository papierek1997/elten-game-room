module GameRoomGoPosition
  module_function

  def neighbors(point, size)
    x, y = point % size, point / size
    result = []
    result << point - 1 if x > 0
    result << point + 1 if x + 1 < size
    result << point - size if y > 0
    result << point + size if y + 1 < size
    result
  end

  def group(board, point, size)
    marker, found, liberties, pending = board[point], {}, {}, [point]
    until pending.empty?
      current = pending.pop
      next if found[current]
      found[current] = true
      neighbors(current, size).each do |other|
        if board[other] == marker
          pending << other unless found[other]
        elsif board[other].nil?
          liberties[other] = true
        end
      end
    end
    [found.keys.sort, liberties.keys.sort]
  end

  def key(board); board.map { |stone| stone.nil? ? '-' : stone.to_s }.join; end

  def place(board, point, marker, size, seen)
    return nil unless point.is_a?(Integer) && point.between?(0, board.size - 1) && board[point].nil?
    next_board = board.dup
    next_board[point] = marker
    captured = []
    neighbors(point, size).each do |other|
      next unless next_board[other] == 1 - marker
      stones, liberties = group(next_board, other, size)
      next unless liberties.empty?
      captured.concat(stones)
      stones.each { |stone| next_board[stone] = nil }
    end
    return nil if group(next_board, point, size).last.empty? || seen.key?(key(next_board))
    [next_board, captured]
  end

  def scoring_board(state)
    board = state[:stones].dup
    state[:dead].each { |point| board[point] = nil }
    board
  end

  def score(state)
    size, board = state[:options]['size'].to_i, scoring_board(state)
    territory, visited = [0, 0], {}
    board.each_index do |point|
      next unless board[point].nil? && !visited[point]
      region = group(board, point, size).first
      region.each { |empty| visited[empty] = true }
      owners = region.flat_map { |empty| neighbors(empty, size).map { |n| board[n] } }.compact.uniq
      territory[owners.first] += region.size if owners.size == 1 && (region & state[:neutral]).empty?
    end
    counts = if state[:options]['variant'] == 'territory'
      [0, 1].map { |marker| territory[marker] + state[:captures][marker] + state[:dead].count { |p| state[:stones][p] == 1 - marker } }
    else
      [0, 1].map { |marker| territory[marker] + board.count(marker) }
    end
    [counts[0] * 2, counts[1] * 2 + (state[:options]['komi'].to_f * 2).to_i]
  end
end
