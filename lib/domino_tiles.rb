# encoding: UTF-8
require_relative "game_random"

module GameRoomDominoTiles
  module_function

  # The third digit is a physical copy, never the tile's orientation.
  def tile(a, b, copy = 0)
    [*[a, b].sort.map { |v| v.to_s(36) }, copy.to_s(36)].join
  end

  def deck(maximum, copies = 1)
    copies.times.flat_map do |copy|
      (0..maximum).flat_map { |a| (a..maximum).map { |b| tile(a, b, copy) } }
    end
  end

  def faces(id); [id[0].to_i(36), id[1].to_i(36)]; end
  def double?(id); id[0] == id[1]; end
  def label(id); faces(id).join("–"); end
  def pips(id); faces(id).sum; end
  def fits?(id, value); faces(id).include?(value); end
  def other(id, value); a, b = faces(id); a == value ? b : a; end

  # A cheap long-hand connection forecast, not an assumption that every tile
  # can be played immediately. Keep bridge tiles that reach a whole component,
  # rather than valuing only tiles already matching an exposed end.
  def reachable(tiles, ends)
    reached, pending = ends.uniq, tiles.dup
    loop do
      linked, rest = pending.partition { |id| faces(id).any? { |pip| reached.include?(pip) } }
      return tiles.size - rest.size if linked.empty?
      reached |= linked.flat_map { |id| faces(id) }
      pending = rest
    end
  end

  # A connected component can branch in ways a real sequence cannot follow.
  # For a short own hand, extend the exposed ends with each physical tile at
  # most once. This is own connectivity, not a promise that opponents leave
  # those ends unchanged. Mexican Train allows other trains in a double series.
  def playable_count(tiles, ends, limit: 4_096)
    return reachable(tiles,ends) if tiles.size>12
    memo, nodes = {}, 0
    solve = lambda do |mask,exposed|
      key = [mask,exposed]
      return memo[key] if memo.key?(key)
      nodes += 1
      throw :tile_sequence_budget if nodes>limit
      Thread.pass if (nodes % 128).zero?
      best = 0
      targets = exposed.each_index.to_a
      tiles.each_with_index do |id,index|
        next if mask[index].zero?
        targets.each do |target|
          next unless fits?(id,exposed[target])
          after = exposed.dup
          after[target] = other(id,after[target])
          best = [best,1+solve.call(mask ^ (1 << index),after)].max
        end
      end
      memo[key] = best
    end
    exact = catch(:tile_sequence_budget) { solve.call((1 << tiles.size)-1,ends.dup) }
    exact || reachable(tiles,ends)
  end

  def shuffle(deck, seed)
    random = Random.new(seed.to_i(16))
    GameRoomRandom.shuffle(deck, random: random)
  end
end
