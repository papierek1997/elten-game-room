require_relative '../../support/dice_games'
require_relative '../../../games/blackjack'
require_relative '../../../games/blackjack_dice'

class SidePotBotFixture
  include DiceGamesSupport
  attr_reader :game, :events, :session, :repository, :replay

  def initialize(game, options)
    @game, @events = game, []
    @repository = Repository.new(%w[Alice Bob Carol])
    @session = { '__id' => 19, 'options' => JSON.generate(game.new_game_options(options)) }
  end

  def append(player, action, value = '')
    event = dice_event(events.size + 1, player, action, value)
    result = game.replay(session, events + [event], repository)
    check(result.accepted_events.last == event, "Rejected fixture event #{event.inspect}")
    @events << event
    @replay = result
  end

  def choice(replay = @replay)
    GameRoomBots.choose(game.bot_strategy, actions: game.legal_actions(replay, 'Alice'), actor: 'Alice',
      random_source: GameRoomRandom::SeededSource.new(31), game: game, replay: replay)
  end

  def branch(*actions)
    extra = actions.each_with_index.map { |(action, value), index| dice_event(events.size + index + 1, 'Alice', action, value.to_s) }
    result = game.replay(session, events + extra, repository)
    check(result.accepted_events == events + extra, 'A settlement branch rejected ordinary events')
    result
  end
end

def dice_side_pot(other_total: 18)
  fixture = SidePotBotFixture.new(GameRoomGames::BlackjackDice.new,
    'scoring' => 'chips', 'variant' => 'two_dice', 'starting_chips' => 100, 'stake' => 1, 'round_limit' => 2)
  [ ['Alice', 'ante'], ['Alice', 'bet', 'raise|98'], ['Bob', 'bet', 'call|98'], ['Carol', 'bet', 'call|98'],
    ['Alice', 'roll', '6,6'], ['Alice', 'roll', '3,3'], ['Alice', 'stand'],
    ['Bob', 'roll', '6,6'], ['Bob', 'roll', '6,6'],
    ['Carol', 'roll', '6,6'], ['Carol', 'roll', '3,3'], ['Carol', 'stand'],
    ['Alice', 'ante'], ['Carol', 'bet', 'raise|99'], ['Alice', 'bet', 'call|99'],
    ['Bob', 'roll', '6,6'], ['Bob', 'roll', '3,3'], ['Bob', 'roll', '3'],
    ['Carol', 'roll', '6,6'], ['Carol', 'roll', other_total == 18 ? '3,3' : '4,4'], ['Carol', 'stand'],
    ['Alice', 'roll', '6,6'], ['Alice', 'roll', '3,4'] ].each { |event| fixture.append(*event) }
  fixture
end

fixture = dice_side_pot
raise 'Dice bot risks the guaranteed side pot' unless fixture.choice['action'] == 'stand'
stand, bust = fixture.branch(['stand']), fixture.branch(['roll', '6'])
raise 'Standing did not preserve the demonstrated match win' unless stand.winner == 'Alice' && stand.state[:chips]['Alice'] == 248
raise 'The avoided roll did not risk that side pot' unless bust.winner == 'Carol' && bust.state[:chips]['Alice'] == 50
raise 'Bot refuses to draw against an eligible higher total' unless dice_side_pot(other_total: 20).choice['action'] == 'roll'

fixture = SidePotBotFixture.new(GameRoomGames::Blackjack.new,
  'variant' => 'social', 'starting_chips' => 100, 'stake' => 1, 'round_limit' => 2)
# Ordinary deterministic deals: no injected deck, hand, chip or pot state.
first_seed, second_seed = '28a'.rjust(32, '0'), '17db'.rjust(32, '0')
[ ['Alice', 'ante'], ['Alice', 'bet', 'raise|196'], ['Bob', 'bet', 'call|196'], ['Carol', 'bet', 'call|196'],
  ['Alice', 'deal', "1|#{first_seed}"], ['Bob', 'hit'], ['Carol', 'stand'], ['Alice', 'stand'], ['Alice', 'dealer'],
  ['Alice', 'ante'], ['Alice', 'bet', 'raise|198'], ['Carol', 'bet', 'call|198'],
  ['Bob', 'deal', "2|#{second_seed}"], ['Carol', 'stand'] ].each { |event| fixture.append(*event) }
raise 'Social bot risks the guaranteed side pot' unless fixture.choice['action'] == 'stand'
stand, bust = fixture.branch(['stand'], ['dealer']), fixture.branch(['hit'], ['dealer'])
raise 'Social standing no longer wins the demonstrated match' unless stand.winner == 'Alice' && stand.state[:chips]['Alice'] == 495
raise 'Social bust branch did not expose the avoided risk' unless bust.winner == 'Carol' && bust.state[:chips]['Alice'] == 99
masked = Marshal.load(Marshal.dump(fixture.replay))
masked.state[:deck].reverse!
raise 'Social side-pot bot inspected future cards' unless fixture.choice(masked) == fixture.choice

strategy = GameRoomTwentyOneStrategy
pot = { amount: 30, slice: 10, contributors: %w[A B C], eligible: %w[A B C] }
opponent = { 18 => 0.5, strategy::BUST => 0.5 }
stand, bust = strategy.pot_values([pot], 'A', { 'B' => 22 }, opponent)
raise 'Pending opponent changed the eligible pot' unless stand.call(19) == 30
raise 'All-bust refund probability is missing' unless bust == 5
stand, bust = strategy.pot_values([pot], 'A', { 'B' => 22, 'C' => 22 }, opponent)
raise 'Known all-bust refund differs from settlement' unless stand.call(19) == 30 && bust == 10
stand, bust = strategy.pot_values([pot], 'A', { 'B' => 21 }, opponent)
raise 'A completed eligible 21 can be ignored' unless stand.call(19).zero? && bust.zero?
stand, bust = strategy.pot_values([pot], 'A', {}, opponent)
raise 'Multiple pending all-bust probability is wrong' unless bust == 2.5
raise 'Expected share of tied pending opponents is wrong' unless (stand.call(18) - 17.5).abs < 1e-9
single = { amount: 10, slice: 10, contributors: ['A'], eligible: ['A'] }
stand, bust = strategy.pot_values([single], 'A', {}, opponent)
raise 'Single-contributor refund must not reward drawing' unless stand.call(19) == 10 && bust == 10
ineligible = pot.merge(eligible: %w[B C])
stand, bust = strategy.pot_values([ineligible], 'A', {}, opponent)
raise 'Bot values a pot it cannot win' unless stand.call(21).zero? && bust.zero?

puts 'PASS blackjack side-pot strategy: real replay counterexamples, eligible threats, pending ties/refunds and hidden-deck independence'
