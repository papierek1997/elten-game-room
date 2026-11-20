require_relative '../../support/card_timeouts'

game = GameRoomGames::Poker.new
%w[holdem draw].each do |variant|
  trial = TimedCardCase.new(game, {'variant' => variant}, %w[A B C])
  event = trial.events.first
  replay = trial.replay
  text = game.describe_event(event, trial.repo, replay, 'A')
  cards = replay.state[:hands]['A'].sort_by { |card| game.send(:playing_sort_key, card) }
  assert(text.count { |line| line.start_with?('Cards in hand:') } == 1, 'The dealt own hand is not announced exactly once')
  assert(text.any? { |line| line == "Cards in hand: #{cards.map { |card| game.send(:poker_card_label, card) }.join(', ')}." },
    'The announcement is not the actual own hand')
  assert(text.none? { |line| line.include?('First betting round') }, 'The deal repeats the first-stage heading')
  assert(game.describe_event(event, trial.repo, replay, 'Watcher').none? { |line| line.start_with?('Cards in hand:') },
    'An observer receives a private hand announcement')
  replay.history.select { |entry| %w[small_blind big_blind ante].include?(entry.field) }.each do |entry|
    own = game.describe_event(event, trial.repo, replay, entry.actor)
    assert(own.any? { |line| line.start_with?('You pay') }, 'A forced bet is not personalised for its payer')
    assert(entry.text.start_with?(entry.actor), 'Personal speech polluted the shared history')
  end
  assert(game.turn_announcement(replay, replay.current_player) == 'Your move.', 'The own turn is not concise')
end

trial = TimedCardCase.new(game, {}, %w[A B C])
raising = TimedCardCase.new(game, {}, %w[A B C])
raise_actor = raising.replay.current_player
raise_move = game.legal_actions(raising.replay, raise_actor).find { |item| item['action'] == 'raise' }
before_raise = raising.replay.state[:current_bet]
raising.act(raise_move)
bet = raising.replay.history.reverse.find { |entry| entry.field == 'poker_bet' }
expected_raise = "#{raise_actor} raises by #{raising.replay.state[:street_bets][raise_actor] - before_raise}."
assert(bet.text == expected_raise, 'Raise repeats the total instead of just the increment')
before = trial.replay
actor = before.current_player
choice = game.legal_actions(before, actor).find { |item| item['action'] == 'call' }
trial.act(choice)
assert(GameRoomSounds.event_cue(game: game, event: trial.events.last, before_replay: before,
  after_replay: trial.replay, repository: trial.repo, viewer: actor) == 'poker_call', 'A call has no dedicated cue')
rejected = trial.events.last.merge('id' => 999)
assert(GameRoomSounds.event_cue(game: game, event: rejected, before_replay: trial.replay,
  after_replay: trial.replay, repository: trial.repo, viewer: actor).nil?, 'A rejected packet plays betting audio')

# Side pots follow all disclosed hands, each on its own line. Folded hands
# never participate in the disclosure, even if their chips remain in a pot.
state = game.send(:initial_state, %w[A B C D], game.default_options)
state.update(dealer_index: 0, hands: {'A' => %w[AS AD], 'B' => %w[KS KD], 'C' => %w[QS QD], 'D' => %w[JS JD]},
  community: %w[2C 4D 7H 9S TC], stacks: {'A' => 0, 'B' => 0, 'C' => 0, 'D' => 100},
  contributions: {'A' => 10, 'B' => 20, 'C' => 30, 'D' => 30}, folded: {'D' => true})
history = []
game.send(:showdown, state, 9, history)
hands = history.select { |entry| entry.key.start_with?('showdown_hand:') }
assert(hands.map(&:actor) == %w[A B C], 'Showdown omits a contender or exposes folded cards')
result = history.find { |entry| entry.kind == :round_result }
assert(result && result.text.lines.size >= 3, 'Side-pot recipients are joined into one spoken line')
assert(history.index(hands.last) < history.index(result), 'Pot winners precede the disclosed hands')
assert(state[:stacks].values.sum == 190, 'Presentation changed pot accounting')

puts 'PASS Poker: private own-hand speech, neutral history, concise turns, accepted betting cues and separate side-pot lines'
