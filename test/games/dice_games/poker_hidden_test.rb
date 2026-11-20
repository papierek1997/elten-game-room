require_relative "../../support/dice_games"
include DiceGamesSupport

game = GameRoomGames::DicePoker.new
repo = Repository.new(%w[Alice Bob Carol])
session = dice_session(game, scoring: "chips", starting_chips: 100, stake: 10, round_limit: 1, throws: 2)
events = []
append = lambda do |actor, action, value|
  events << dice_event(events.size + 1, actor, action, value)
  result = game.replay(session, events, repo)
  check(result.accepted_events == events, "Hidden game rejected #{action}")
  result
end
replay = append.call("Alice", "ante", "1")
check(replay.state[:phase] == :playing && replay.current_player == "Alice", "Ante did not lead straight to rolling")
check(game.game_shortcuts(replay, "Alice").none? { |key| %w[c f a r b h].include?(key.key) }, "Opening auction or nonexistent hand is exposed")
replay = append.call("Alice", "roll", "1,2,3,4,6")
roll = events.last
check(game.describe_event(roll, repo, replay, "Alice") == ["Alice rolls 1, 2, 3, 4, 6: High card."], "Own roll was concealed")
%w[Bob Carol Observer].each do |viewer|
  check(game.describe_event(roll, repo, replay, viewer) == ["Alice rolls the dice."], "Other viewer hears the faces or category")
  spec = game.surface_spec(replay, viewer)
  check(spec.is_a?(GameSurfaces::PawnTrackSpec) && spec.items.none? { |item| item.label.include?("High card") }, "Other viewer sees a private hand")
  check(game.game_shortcuts(replay, viewer).none? { |key| %w[h space k].include?(key.key) }, "Other viewer can read or keep Alice's dice")
end
check(replay.history.last.text == "Alice rolls the dice.", "History exports a hidden roll")
replay = append.call("Alice", "stand", "1")
check(replay.history.last.text == "Alice keeps the hand.", "Keeping the hand reveals its category")
hand = game.game_shortcuts(replay, "Alice").find { |key| key.key == "h" }
check(hand&.message == "Your dice: 1, 2, 3, 4, 6. High card.", "Own retained hand cannot be recalled while waiting")
replay = append.call("Bob", "roll", "6,6,6,6,6")
replay = append.call("Bob", "stand", "1")
replay = append.call("Carol", "roll", "5,5,5,5,5")
replay = append.call("Carol", "stand", "1")
check(replay.state[:phase] == :betting && replay.current_player == "Alice", "Final auction did not start in round order")
check(replay.history.none? { |entry| entry.kind == :showdown || entry.text.include?("Five of a kind") }, "Final hands leaked before betting ended")
check(game.game_shortcuts(replay, "Bob").find { |key| key.key == "h" }&.message == "Your dice: 6, 6, 6, 6, 6. Five of a kind.", "Own hand is missing in the final auction")
check(game.game_shortcuts(replay, "Observer").none? { |key| key.key == "h" }, "Spectator can recall a hand")
auction_prefix = events.dup
replay = append.call("Alice", "bet", "check|0")
replay = append.call("Bob", "bet", "check|0")
check(replay.history.none? { |entry| entry.kind == :showdown }, "A partial auction reveals hands")
replay = append.call("Carol", "bet", "check|0")
revealed = replay.history.select { |entry| entry.kind == :showdown }
check(replay.finished? && replay.winner == "Bob" && revealed.map(&:actor) == repo.players, "Contested settlement is missing final hands")
check(revealed[1].text == "Bob reveals 6, 6, 6, 6, 6: Five of a kind.", "Showdown does not identify the complete hand")
check(replay.history.index(revealed.last) < replay.history.index { |entry| entry.kind == :pot }, "Payout precedes the hand comparison")
check(game.replay(session, events, repo) == replay, "Cold hidden-game replay differs")

events = auction_prefix.dup
append.call("Alice", "bet", "check|0")
append.call("Bob", "bet", "fold|0")
replay = append.call("Carol", "bet", "check|0")
check(replay.finished? && replay.winner == "Carol", "A folded strongest hand still wins")
check(replay.history.select { |entry| entry.kind == :showdown }.map(&:actor) == %w[Alice Carol], "A folded hand is shown")
check(replay.history.none? { |entry| entry.actor == "Bob" && entry.text.include?("Five of a kind") }, "Folded dice leaked into history")
events = auction_prefix.dup
append.call("Alice", "bet", "fold|0")
replay = append.call("Bob", "bet", "fold|0")
check(replay.finished? && replay.winner == "Carol" && replay.history.none? { |entry| entry.kind == :showdown }, "Uncontested pot forces a reveal")

# Identical permitted information must give identical values, choices and RNG
# consumption, irrespective of opponents' concealed faces, in both phases.
choice_signature = lambda do |position|
  actor = position.current_player
  actions = game.legal_actions(position, actor)
  scores = actions.map { |action| game.bot_action_score(position, actor, action) }
  random = GameRoomRandom::SeededSource.new(246)
  picked = GameRoomBots.choose(game.bot_strategy, actions: actions, actor: actor, random_source: random, game: game, replay: position)
  [scores, picked, random.roll(count: 8, sides: 1000).values]
end
%w[classic no_straights aces_high].each do |variant|
  session = dice_session(game, scoring: "chips", round_limit: 1, throws: 2, variant: variant)
  signatures = %w[1,1,1,1,1 6,6,6,6,6].map do |other|
    moves = [["Alice", "ante", "1"], ["Alice", "roll", other], ["Alice", "stand", "1"],
      ["Bob", "roll", other], ["Bob", "stand", "1"], ["Carol", "roll", "1,1,3,4,6"]]
    events = moves.each_with_index.map { |args, i| dice_event(i + 1, *args) }
    playing = game.replay(session, events, repo)
    check(playing.accepted_events == events, "Privacy comparison contains a rejected move")
    in_play = choice_signature.call(playing)
    events << dice_event(7, "Carol", "stand", "1")
    events << dice_event(8, "Alice", "bet", "raise|10")
    events << dice_event(9, "Bob", "bet", "call|10")
    betting = game.replay(session, events, repo)
    check(betting.accepted_events == events && betting.current_player == "Carol", "Privacy betting fixture is not Carol's decision")
    [in_play, choice_signature.call(betting)]
  end
  check(signatures[0] == signatures[1], "#{variant}: bot reads opponents' hidden dice or varies its RNG consumption")
end

check(game.option_definitions.none? { |definition| definition.key == 'scoring' }, 'Removed public-dice variant is still selectable')
check(game.notification_option_keys({}) == ['variant'], 'Table summary still exposes the removed scoring selector')

# A single full throw has an independent exact weighted-outcome oracle.
rank = GameRoomDicePokerHands.rank([3, 3, 3, 5, 6], "classic")
lower = equal = 0
GameRoomDicePokerStrategy::OUTCOMES.fetch(5).each do |dice, weight|
  comparison = GameRoomDicePokerHands.rank(dice, "classic") <=> rank
  lower += weight if comparison < 0
  equal += weight if comparison == 0
end
utility = GameRoomDicePokerStrategy.contest_value("classic", [], 1, split_ties: true, attempts: 1)
check((utility.call(rank) - (lower + equal / 2.0).fdiv(6**5)).abs < 1e-12,
  "Hidden-opponent equity miscounts single-throw ties")

# Further throws retain dice rather than take the best independent full roll.
# The model's distribution is checked in poker_opponent_model_test; here compare
# the utility against separately settling every possible final opponent rank,
# not another copy of contest_value's CDF/binomial formula.
[2, 3].each do |attempts|
  distribution = GameRoomDicePokerStrategy.modeled_outcomes('classic', attempts)
  expected = distribution.sum do |opponent, (_below, probability)|
    comparison = rank <=> opponent
    comparison.positive? ? probability : comparison.zero? ? probability / 2.0 : 0.0
  end
  utility = GameRoomDicePokerStrategy.contest_value('classic', [], 1, split_ties:true, attempts:attempts)
  check((utility.call(rank) - expected).abs < 1e-12,
    "Hidden-opponent equity miscounts retained-dice ties with #{attempts} throws")
end
puts "PASS Dice Poker ante-only opening, owner/opponent/spectator presentation, hidden history, contested/folded showdown, cold replay and bot information invariance"
