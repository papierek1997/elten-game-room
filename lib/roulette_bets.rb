module GameRoomRouletteBets
  RED = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36].freeze
  module_function

  def definitions(wheel)
    bets = []
    add = ->(key, numbers, odds, label) { bets << {key: key, numbers: numbers, odds: odds, label: label} }
    numbers = (0..36).to_a + (wheel == 'american' ? [37] : [])
    numbers.each { |n| add.call("n#{n}", [n], 35, display(n)) }
    (1..36).each do |n|
      add.call("s#{n}h", [n, n + 1], 17, "#{n}/#{n + 1}") if n % 3 != 0
      add.call("s#{n}v", [n, n + 3], 17, "#{n}/#{n + 3}") if n <= 33
    end
    (0..11).each do |row|
      n = row * 3 + 1
      add.call("t#{row}", (n..n + 2).to_a, 11, "#{n}-#{n + 2}")
      if row < 11
        add.call("l#{row}", (n..n + 5).to_a, 5, "#{n}-#{n + 5}")
        [n, n + 1].each { |a| add.call("c#{a}", [a, a + 1, a + 3, a + 4], 8, "#{a}/#{a + 1}/#{a + 3}/#{a + 4}") }
      end
    end
    zero_groups = if wheel == 'american'
      [[[0, 1], 17], [[0, 2], 17], [[37, 2], 17], [[37, 3], 17], [[0, 37], 17],
       [[0, 1, 2], 11], [[37, 2, 3], 11], [[0, 37, 2], 11], [[0, 37, 1, 2, 3], 6]]
    else
      [[[0, 1], 17], [[0, 2], 17], [[0, 3], 17], [[0, 1, 2], 11], [[0, 2, 3], 11], [[0, 1, 2, 3], 8]]
    end
    zero_groups.each_with_index { |(ns, odds), i| add.call("z#{i}", ns, odds, ns.map { |n| display(n) }.join('/')) }
    [1, 2, 3].each do |n|
      add.call("dozen#{n}", ((n - 1) * 12 + 1..n * 12).to_a, 2, "dozen#{n}")
      add.call("column#{n}", (n..36).step(3).to_a, 2, "column#{n}")
    end
    {'red' => RED, 'black' => (1..36).to_a - RED, 'odd' => (1..36).select(&:odd?),
      'even' => (1..36).select(&:even?), 'low' => (1..18).to_a, 'high' => (19..36).to_a}.each do |key, ns|
      add.call(key, ns, 1, key)
    end
    bets
  end

  def display(number); number == 37 ? '00' : number.to_s; end

  def payout(bet, amount, number, wheel)
    return amount * (bet[:odds] + 1) if bet[:numbers].include?(number)
    wheel == 'french' && number == 0 && bet[:odds] == 1 ? amount / 2 : 0
  end
end
