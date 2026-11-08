require_relative "../../../games/blackjack"
require_relative "../../../games/blackjack_dice"
require_relative "../../support/blackjack"

include BlackjackChecksSupport
game = GameRoomGames::BlackjackDice.new
repository = BlackjackChecksSupport::Repository.new(%w[Alice Bob])
session = {"options" => JSON.generate(game.default_options.merge("scoring" => "chips", "starting_chips" => 100, "round_limit" => 2))}
initial = game.replay(session, [], repository)
check(initial.state[:phase] == :betting && game.participant_scores(initial) == {"Alice" => 100, "Bob" => 100}, "Initial chip balances")
check(game.action_for({"action" => "roll"}, initial, "Alice").first == :invalid, "Rolling before the stake")
check(game.action_for({"action" => "bet", "amount" => 0}, initial, "Alice").first == :invalid, "Zero stake")
check(game.action_for({"action" => "bet", "amount" => 101}, initial, "Alice").first == :invalid, "Unaffordable stake")
check(game.action_for({"action" => "bet", "amount" => 10}, initial, "Bob").first == :not_your_turn, "Wrong stake setter")
check(game.replay(session, [event(1, "Alice", "bet", "0")], repository).state == initial.state, "Rejected stake changed balances")

events = [event(1, "Alice", "bet", "10")]
paid = game.replay(session, events, repository)
check(paid.state[:pot] == 20 && paid.state[:chips].values == [90, 90], "Stake not deducted exactly once")
check(game.replay(session, events + events, repository).state == paid.state, "Duplicate stake charged twice")
check(game.required_decision_key(nil, "Alice").nil?, "Nil previous decision replay")
check(game.required_decision_key(initial, "Alice") != game.required_decision_key(paid, "Alice"), "Stake and roll share the same decision")
events += [event(2, "Alice", "roll", "6,6"), event(3, "Alice", "stand"), event(4, "Bob", "roll", "5,6"), event(5, "Bob", "stand")]
round = game.replay(session, events, repository)
check(round.state[:chips] == {"Alice" => 110, "Bob" => 90} && round.state[:pot].zero?, "Unique round winner payout")
check(round.state[:phase] == :betting && round.current_player == "Bob", "Next stake or rotating setter missing")
check(game.action_for({"action" => "bet", "amount" => 91}, round, "Bob").first == :invalid, "Stake exceeded poorest bankroll")
events += [event(6, "Bob", "bet", "7"), event(7, "Bob", "roll", "6,6"), event(8, "Bob", "stand"), event(9, "Alice", "roll", "6,6"), event(10, "Alice", "stand")]
finished = game.replay(session, events, repository)
check(finished.finished? && finished.winner == "Alice" && finished.state[:chips] == round.state[:chips], "Tie settlement or match limit")
check(finished.accepted_events.size == 10, "Changed round stake was rejected")

short = {"options" => JSON.generate(game.normalize_options("scoring" => "chips", "starting_chips" => 10, "stake" => 10))}
all_in = game.replay(short, [event(1, "Alice", "bet", "10")], repository)
check(!game.eliminated_from_game?(all_in, "Alice"), "All-in treated as permanent elimination")
busted = [event(1, "Alice", "bet", "10"), event(2, "Alice", "roll", "6,6"), event(3, "Alice", "roll", "6,6"),
  event(4, "Bob", "roll", "6,6"), event(5, "Bob", "roll", "6,6")]
refunded = game.replay(short, busted, repository)
check(refunded.state[:chips].values == [10, 10] && !refunded.finished?, "All-bust round did not refund stakes")
won = game.replay(short, [event(1, "Alice", "bet", "10"), event(2, "Alice", "roll", "6,6"), event(3, "Alice", "stand"),
  event(4, "Bob", "roll", "5,6"), event(5, "Bob", "stand")], repository)
check(won.finished? && won.winner == "Alice" && game.eliminated_from_game?(won, "Bob"), "Bankruptcy did not finish the match")

three = BlackjackChecksSupport::Repository.new(%w[Alice Bob Carol])
odd = [event(1, "Alice", "bet", "1"), event(2, "Alice", "roll", "6,6"), event(3, "Alice", "stand"),
  event(4, "Bob", "roll", "6,6"), event(5, "Bob", "stand"), event(6, "Carol", "roll", "5,6"), event(7, "Carol", "stand")]
split = game.replay(session, odd, three)
check(split.state[:chips] == {"Alice" => 101, "Bob" => 100, "Carol" => 99}, "Odd pot split or deterministic remainder")
check(split.state[:chips].values.sum + split.state[:pot] == 300, "Settlement created or destroyed chips")
check(!game.default_options.key?("scoring"), "Historical point options changed")
check(!game.normalize_options("scoring" => "chips").key?("score_limit"), "Inactive point setting stored in a chip game")
check(game.validation_error({"scoring" => "chips", "score_limit" => 0}).nil?, "Hidden point limit blocked a chip game")
check(game.game_shortcuts(initial, "Alice").any? { |shortcut| shortcut.key == "b" && shortcut.kind == :number_input }, "Custom stake input missing")
check(game.surface_spec(initial, "Alice").zones.first.cards.map(&:value).include?("bet:10"), "Stake presets missing")
puts "Blackjack Dice chips: stakes, balances, refunds, ties, rotation, bankruptcy, replay and UI choices passed"
