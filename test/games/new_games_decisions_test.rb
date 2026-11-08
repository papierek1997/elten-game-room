require_relative "../support/dice_games"
require_relative "../../games/blackjack"
require_relative "../support/blackjack"
require_relative "../../games/blackjack_dice"
require_relative "../../games/go"
require_relative "../../games/liars_dice"
require_relative "../../games/roulette"

include DiceGamesSupport

def choice(game, replay, actor)
  legal = game.legal_actions(replay, actor)
  selected = GameRoomBots.choose(game.bot_strategy, game: game, replay: replay, actor: actor,
    actions: legal, random_source: GameRoomRandom::SeededSource.new(19))
  check(legal.include?(selected), "Bot did not pick a legal action")
  selected
end

repo = DiceGamesSupport::Repository.new(%w[Alice Bob])
game = BlackjackChecksSupport::FixedDeck.new
session = dice_session(game, variant: "simple")
deal = dice_event(1, "Alice", "deal", "1|#{'0' * 32}")
game.first_cards = %w[AS 9C 9D 6H TH 7H 2C]
soft = game.replay(session, [deal], repo)
check(game.hand_total(soft.state[:hands]["Alice"].first[:cards]) == 17, "Expected soft 17")
check(choice(game, soft, "Alice")["action"] == "hit", "Soft 17 against 9 must not stand")
game.first_cards = %w[TC 9C 6D 6H TH 7H 2C]
hard = game.replay(session, [deal], repo)
check(game.hand_total(hard.state[:hands]["Alice"].first[:cards]) == 16, "Expected hard 16")
check(choice(game, hard, "Alice")["action"] == "stand", "Hard 16 against 6 took an avoidable risk")

game = GameRoomGames::BlackjackDice.new
session = dice_session(game, variant: "one_die")
{17 => "stand", 19 => "roll"}.each do |target, expected|
  events = [6, 6, target == 17 ? 5 : 6, *(target == 19 ? [1] : [])].map.with_index do |roll, i|
    dice_event(i + 1, "Alice", "roll", roll.to_s)
  end
  events << dice_event(events.size + 1, "Alice", "stand", "")
  3.times { events << dice_event(events.size + 1, "Bob", "roll", "6") }
  replay = game.replay(session, events, repo)
  check(replay.state[:totals]["Alice"] == target && replay.state[:total] == 18, "Wrong dice scenario")
  check(choice(game, replay, "Bob")["action"] == expected, "Dice bot ignored the score to beat")
end

game = GameRoomGames::DicePoker.new
session = dice_session(game, throws: 2)
events = [dice_event(1, "Alice", "roll", "1,2,3,4,5"), dice_event(2, "Alice", "stand", "1")]
winning = game.replay(session, events + [dice_event(3, "Bob", "roll", "2,3,4,5,6")], repo)
check(choice(game, winning, "Bob")["action"] == "score", "Bot rerolled a guaranteed winning straight")
losing = game.replay(session, events + [dice_event(3, "Bob", "roll", "2,3,4,5,5")], repo)
reroll = choice(game, losing, "Bob")
check(reroll["action"] == "roll" && %w[d3 d4].include?(reroll["die_ids"]), "Bot broke an open straight to keep a pair")

game = GameRoomGames::Go.new
session = dice_session(game, variant: "atari")
events = [[0, 0], [1, 0], [1, 1]].map.with_index do |(x, y), index|
  dice_event(index + 1, repo.players[index % 2], "place", (y * 9 + x).to_s)
end
events << dice_event(4, "Bob", "pass", "")
replay = game.replay(session, events, repo)
move = choice(game, replay, "Alice")
check(move.values_at("action", "x", "y") == ["select", 2, 0], "Go bot passed up a winning capture after a pass")
check(game.game_shortcuts(replay, "Alice").find { |s| s.key == "s" }.message.include?("Stones captured"),
  "Atari Go announces a territory score")

game = GameRoomGames::LiarsDice.new
bot = "bot:1:1:pl01"
liar_repo = DiceGamesSupport::Repository.new(["Alice", "Bob", "Carol", bot])
replay = game.replay(dice_session(game, variant: "perudo", calza: true), [], liar_repo)
replay.state.merge!(phase: :bidding, current_player: "Bob", bid: {quantity: 3, face: 6, actor: "Alice"})
check(game.active_actors(replay) == ["Bob", "Carol"], "Optional Calza forced a bot action or disappeared for a human")
check(game.legal_actions(replay, "Carol").map { |action| action["action"] } == ["exact"], "Human Calza not available out of turn")

game = GameRoomGames::Roulette.new
session = dice_session(game, round_limit: 2)
replay = game.replay(session, [], repo)
bet = choice(game, replay, "Alice")["bet"]
check(GameRoomRouletteBets.definitions("european").find { |item| item[:key] == bet }[:numbers].size == 18,
  "Roulette bot defaulted to an arbitrary high-risk number")
replay.state[:round] = 2
replay.state[:chips]["Bob"] += 400
bet = choice(game, replay, "Alice")["bet"]
check(GameRoomRouletteBets.definitions("european").find { |item| item[:key] == bet }[:odds] == 35,
  "Roulette bot did not take a calculated risk on the last spin")
replay = game.replay(dice_session(game, round_limit: 1), [], repo)
replay.state[:chips]["Alice"] += 400
check(choice(game, replay, "Alice")["action"] == "ready", "Roulette bot risked an unassailable public lead")
puts "New game bot decisions: soft 17, dice scores, straight selection, Atari capture, optional Calza and roulette risk."
