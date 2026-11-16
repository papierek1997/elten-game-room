require_relative '../support/room_interface'
require_relative '../support/assertions'
include GameRoomTest::Assertions

order_type = GameRoomGames::CardHandOrder
suits, ranks = %w[H S D C], %w[2 3 4 5 6 7 8 9 T J Q K A]
order = order_type.new(default_sort: 'colour', sort_modes: %w[colour number], suits: suits, ranks: ranks)
suits.first.replace('changed')
ranks.reverse!
assert_equal(%w[H S D C], order.suits, 'Policy retained mutable input')
assert_equal('2', order.ranks.first)
assert(order.frozen? && order.sort_modes.frozen? && order.sort_modes.all?(&:frozen?) && order.suits.frozen? && order.suits.all?(&:frozen?) && order.ranks.frozen? && order.ranks.all?(&:frozen?), 'Policy is not deeply immutable')
assert_raises(FrozenError) { order.default_sort = 'none' }
[
  {default_sort: 'default', suits: %w[H], ranks: %w[A]},
  {default_sort: 'number', suits: [], ranks: %w[A]},
  {default_sort: 'colour', suits: %w[H H], ranks: %w[A]},
  {default_sort: 'none', suits: [''], ranks: []},
  {default_sort: 'none', suits: [], ranks: [1]},
  {default_sort: 'none', suits: nil, ranks: []}
].each { |attributes| assert_raises(ArgumentError) { order_type.new(sort_modes: %w[colour number none], **attributes) } }
[[], %w[colour colour], %w[number], %w[colour default]].each do |modes|
  assert_raises(ArgumentError) { order_type.new(default_sort:'colour', sort_modes:modes, suits:%w[H], ranks:%w[A]) }
end

standard = %w[spades tysiac three_five_eight ninety_nine bouillabaisse belote jass hearts makao poker]
custom = %w[bridge scopa cribbage french_tarot rummy uno scientific_war]
received = %w[blackjack mille_bornes duck_racing war biblios]
expected = standard + custom + received + ['monopoly']
declared = GameRoomGames::CATALOG.ids.select do |id|
  game = GameRoomGames::CATALOG.build(id)
  policy = game.card_hand_order
  next false if policy.nil?

  assert(game.class.const_defined?(:CARD_HAND_ORDER, false), "#{id}: inherits an accidental policy")
  assert(policy.is_a?(order_type) && policy.frozen?, "#{id}: missing immutable order")
  true
end
assert_equal(expected.sort, declared.sort, 'A card game has no declaration or a non-card game gained one')
standard.each do |id|
  policy = GameRoomGames::CATALOG.build(id).card_hand_order
  assert_equal(['colour', %w[colour number], %w[H S D C], %w[2 3 4 5 6 7 8 9 T J Q K A]], policy.to_a, "#{id}: not the agreed Spades presentation order")
end
received.each do |id|
  assert_equal('none', GameRoomGames::CATALOG.build(id).card_hand_order.default_sort, "#{id}: silently sorted acquisition order")
end
assert_equal(nil, GameRoomGames::Ludo.new.card_hand_order, 'Board game needs a card policy')
assert_raises(ArgumentError) { GameRoomGames::Base.new.send(:standard_hand_sort_keys, rank: 'A', suit: 'H', position: 0) }
missing = Class.new(GameRoomGames::CardGame) { def id; 'missing_hand_policy'; end }
assert_raises(ArgumentError) { GameRoomGames::Registry.new([missing]) }
malformed = Class.new(GameRoomGames::CardGame) do
  const_set(:CARD_HAND_ORDER, 'colour')
  def id; 'bad_hand_policy'; end
end
assert_raises(ArgumentError) { GameRoomGames::Registry.new([malformed]) }

uno = GameRoomGames::Uno.new
[false, true].repeated_permutation(3) do |straights, interceptions, super_interceptions|
  options = {'straights'=>straights, 'interceptions'=>interceptions, 'super_interceptions'=>super_interceptions}
  mode = straights || (interceptions && super_interceptions) ? 'number' : 'colour'
  assert_equal(mode, uno.card_hand_order(options: options).default_sort, "UNO #{options}: wrong variant default")
end
puts 'PASS explicit card-order contracts: 22 card games plus Monopoly deck helpers; missing/malformed declarations, immutable semantic keys and UNO variants'
