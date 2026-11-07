require_relative '../../support/bridge'
include GameRoomTest::Assertions

R = GameRoomGames::BridgeRules

# Construct the observation from a legal, fully accounted for deal. The
# retained opposing cards verify the fixture, not the input to the bot.
def position(records, hands, trick, level, strain)
  history = records.lines.map do |line|
    leader, *cards = line.split
    cards.each_with_index.map { |card, i| [(leader.to_i + i) % 4, card] }
  end
  original = hands.map(&:dup)
  (history.flatten(1) + trick).each { |seat, card| original[seat] << card }
  assert_equal(R::DECK.sort, original.flatten.sort, 'The fixture must conserve all cards')
  assert(original.all? { |hand| hand.size == 13 })
  turn = 1
  tricks = [0, 0]
  (history + [trick]).each do |plays|
    partial = []
    plays.each do |seat, card|
      assert_equal(turn, seat)
      assert(R.legal_cards(original[seat], partial).include?(card), 'The fixture must follow suit')
      original[seat].delete(card)
      partial << [seat, card]
      turn = (turn + 1) % 4
    end
    if plays.size == 4
      turn = R.trick_winner(plays, strain)
      tricks[turn % 2] += 1
    end
  end
  assert_equal(hands.map(&:sort), original.map(&:sort))
  assert_equal(2, turn)
  {'seat'=>0, 'seat_to_play'=>2, 'hand'=>hands[0], 'dummy'=>hands[2], 'played'=>history.flatten(1),
    'trick'=>trick, 'tricks_won'=>tricks, 'phase'=>'playing', 'calls'=>[[0, "#{level}#{strain}"]],
    'vulnerability'=>'none', 'contract'=>{'level'=>level, 'strain'=>strain, 'doubled'=>0, 'declarer'=>0}}
end

def compare(view, expected, former)
  options = R.legal_cards(view.fetch('dummy'), view.fetch('trick'))
  old = GameRoomGames::BridgeStrategy::Play.new(view).card(options)
  assert_equal(former, old, 'Fixture must expose the old tactical choice')
  actions = options.map { |card| {'card'=>card} }
  before = Marshal.dump(view)
  chosen = GameRoomGames::BridgeStrategy.new.choose(actions: actions, observation: view, actor: 'Alice', random_source: nil)
  assert_equal(expected, chosen.fetch('card'))
  assert_equal(before, Marshal.dump(view), 'Planning must leave the observation immutable')
end

# Ducking with 2C allows West to ruff QH with QS. Ruffing our own winner
# with AS first leaves KS to overruff or take the last trick, making 2S.
ruff = position(<<~CARDS, [%w[KS],%w[6C],%w[AS 2C],%w[QS 3D]], [[0,'QH'],[1,'2H']], 2, 'S')
  1 4C 5C TD 8C
  0 7H 6H 8H JD
  2 KH JS 9H 3H
  3 AD QD 9C 9D
  3 9S 5S 5H 7S
  3 8S TS 3C 2S
  0 AH TH KD 3S
  3 6D JH AC 8D
  2 QC 6S 7C TC
  3 4D 4H JC 7D
  2 2D 5D 4S KC
CARDS
compare(ruff, 'AS', '2C')

# In notrump the winning king would strand two winners in dummy. Overtake
# with AC while there is an entry; AH and the promoted 3C make the game.
entry = position(<<~CARDS, [%w[2D 2S],%w[4D AS],%w[AC 3C AH],%w[4C AD 3D]], [[0,'KC'],[1,'2C']], 3, 'N')
  1 7H QH 4H JH
  2 7D QD 5D TD
  3 3S 8S 9S 6S
  1 2H 9H 6H 8H
  2 KH KD 5H TH
  2 JC 9C 7C 6C
  2 QC 8C TC 5C
  2 8D 6D 9D JD
  1 QS 5S KS 7S
  3 TS JS 4S 3H
CARDS
compare(entry, 'AC', '3C')

weak_two = {'seat'=>2, 'hand'=>%w[AS KS 8S 4S AH 3H QD 7D 3D 2D 9C 6C 5C],
  'calls'=>[[0,'2H'],[1,'P']], 'vulnerability'=>'both'}
assert_equal(R::PASS, GameRoomGames::BridgeStrategy::Bidding.new(weak_two).call,
  'Do not jump to 3NT on 13 HCP opposite a weak two with no fit')
puts 'PASS bridge strategy: ruff against a public void, take a dummy entry and respect the weak-two range'
