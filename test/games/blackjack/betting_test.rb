require_relative "../../../games/blackjack"
require_relative "../../support/blackjack"

include BlackjackChecksSupport
game = BlackjackChecksSupport::FixedDeck.new
game.first_cards = %w[TC 9C 6C 8D 8H 9D]
repo = Repository.new(%w[Alice Bob])
options = game.new_game_options("round_limit" => 2, "stake" => 10, "variant" => "extended").merge("blackjack_betting_version" => 1)
session = {"options" => JSON.generate(options)}
initial = game.replay(session, [], repo)
check(initial.state[:phase] == :betting, "Cards were dealt before betting")
check(initial.state[:hands].empty? && initial.state[:deck].empty? && initial.state[:dealer].empty?, "Betting exposes cards")
check(game.automatic_action(initial, "Alice").nil?, "Automatic deal bypasses bets")
check(game.required_decision_key(nil, "Alice").nil? && game.required_decision_key(initial, "Alice"), "Initial betting decision missing")
check(game.action_for({"action" => "hit"}, initial, "Alice").first == :invalid, "Hit before betting")
[0, -1, 101, 1.5, "01", "7x"].each do |amount|
  check(game.action_for({"action" => "bet", "amount" => amount}, initial, "Alice").first == :invalid, "Invalid stake #{amount.inspect}")
end
check(game.action_for({"action" => "bet", "amount" => 7}, initial, "Bob").first == :not_your_turn, "Out-of-turn stake")
status, plan = game.action_for({"action" => "bet", "amount" => 7}, initial, "Alice")
check(status == :ok && plan, "Custom stake rejected")
events = [event(1, "Alice", "bet", "7")]
first = game.replay(session, events, repo)
check(first.state[:chips] == {"Alice" => 186, "Bob" => 200} && first.current_player == "Bob", "Individual stake or next bettor")
check(game.replay(session, events + events, repo).state == first.state, "Duplicate stake charged twice")
early = game.replay(session, events + [event(2, "Alice", "deal", "1|#{'a' * 32}")], repo)
check(early.state == first.state, "Deal accepted before all bets")
events << event(2, "Bob", "bet", "13")
ready = game.replay(session, events, repo)
check(ready.state[:phase] == :awaiting_deal && ready.state[:hands].empty?, "Ready phase after all bets")
check(game.automatic_action(ready, "Alice")["action"] == "deal", "Standard executor cannot deal")
events << event(3, "Alice", "deal", "1|#{'a' * 32}")
dealt = game.replay(session, events, repo)
check(dealt.state[:hands]["Alice"].first[:bet] == 14 && dealt.state[:hands]["Bob"].first[:bet] == 26, "Deal lost individual stakes")
check(dealt.state[:chips] == ready.state[:chips], "Deal deducted stakes twice")
check(game.required_decision_key(initial, "Alice") != game.required_decision_key(dealt, "Alice"), "Betting and play share decision identity")
events += [event(4, "Alice", "stand"), event(5, "Bob", "stand"), event(6, "Alice", "dealer")]
settled = game.replay(session, events, repo)
check(settled.state[:phase] == :betting && settled.state[:chips] == {"Alice" => 186, "Bob" => 174}, "Individual losing-stake settlement")
check(settled.state[:hands].empty? && settled.state[:dealer].empty?, "Old cards remain during next bets")
check(game.action_for({"kind" => "card", "zone" => "actions", "action" => "select", "card" => "bet:5"}, settled, "Alice").first == :ok, "Preset surface cannot bet")
check(game.game_shortcuts(settled, "Alice").any? { |s| s.key == "b" && s.kind == :number_input }, "Stake shortcut missing")
check(game.game_shortcuts(settled, "Bob").none? { |s| s.key == "b" }, "Another bettor can set a stake")
check(game.surface_spec(initial, "Alice").zones.none? { |z| z.hand_order }, "Bet choices marked as a card hand")
check(game.replay(session, events + [event(7, "Alice", "bet", "0")], repo).state == settled.state, "Rejected next-round bet changed the model")

one = Repository.new(["Alice"])
all_in_session = {"options" => JSON.generate(game.new_game_options("starting_chips" => 10, "stake" => 10, "round_limit" => 1, "variant" => "extended").merge("blackjack_betting_version" => 1))}
game.first_cards = %w[AS 9C KD 8D]
all_in_events = [event(1, "Alice", "bet", "3"), event(2, "Alice", "deal", "1|#{'a' * 32}"), event(3, "Alice", "dealer")]
natural = game.replay(all_in_session, all_in_events, one)
check(natural.finished? && natural.state[:chips]["Alice"] == 29, "Odd custom stake natural payout")
game.first_cards = %w[8C 9D 8D 7H 2C 3C]
all_in_events = [event(1, "Alice", "bet", "10"), event(2, "Alice", "deal", "1|#{'a' * 32}")]
all_in = game.replay(all_in_session, all_in_events, one)
check(!game.eliminated_from_game?(all_in, "Alice") && game.legal_actions(all_in, "Alice").map { |a| a["action"] } == %w[hit stand], "All-in elimination or unfunded extra bet")
game.first_cards = %w[5C 6D 6C TH TD 2S]
double_events = [event(1, "Alice", "bet", "3"), event(2, "Alice", "deal", "1|#{'a' * 32}"), event(3, "Alice", "double"), event(4, "Alice", "dealer")]
doubled = game.replay(all_in_session, double_events, one)
check(doubled.state[:hands]["Alice"].first[:bet] == 12 && doubled.state[:chips]["Alice"] == 32, "Double ignores individual stake")
game.first_cards = %w[AS 9D AC 7H TC KD 2S]
split_events = [event(1, "Alice", "bet", "3"), event(2, "Alice", "deal", "1|#{'a' * 32}"), event(3, "Alice", "split"), event(4, "Alice", "dealer")]
split = game.replay(all_in_session, split_events, one)
check(split.state[:hands]["Alice"].map { |h| h[:bet] } == [6, 6] && split.state[:chips]["Alice"] == 32, "Split ignores individual stake")
game.first_cards = %w[TC 9C 6D 8D 8H 9D]
low_session = {"options" => JSON.generate(game.new_game_options("starting_chips" => 10, "stake" => 10, "round_limit" => 2).merge("blackjack_betting_version" => 1))}
low_events = [event(1, "Alice", "bet", "7"), event(2, "Alice", "deal", "1|#{'a' * 32}"), event(3, "Alice", "stand"), event(4, "Alice", "dealer")]
low = game.replay(low_session, low_events, one)
check(low.state[:phase] == :betting && low.state[:chips]["Alice"] == 6 && !game.eliminated_from_game?(low, "Alice"), "Balance below table default wrongly eliminated")
check(game.legal_actions(low, "Alice").map { |a| a["amount"] }.max == 3, "Bet presets exceed remaining bankroll")
check(game.action_for({"action" => "bet", "amount" => 4}, low, "Alice").first == :invalid, "Next stake exceeds reduced balance")
check(game.action_for({"action" => "bet", "amount" => 1}, low, "Alice").first == :ok, "Player cannot reduce the next stake")
legacy = {"options" => JSON.generate(game.default_options)}
check(game.replay(legacy, [], repo).state[:phase] == :awaiting_deal, "Legacy starts changed")
check(!game.normalize_options({}).key?("blackjack_betting_version"), "Legacy canonical options changed")
check(!game.game_start_options({}, players: repo.players, fixed: true).key?("blackjack_betting_version"), "Bound match upgraded")
check(game.game_start_options({}, players: repo.players)["blackjack_betting_version"] == 2, "Ordinary start lacks ante and raises")
rich = Marshal.load(Marshal.dump(initial))
rich.state[:chips]["Alice"] = 2_000_002
check(game.action_for({"action" => "bet", "amount" => 1_000_001}, rich, "Alice").first == :ok, "Large earned bankroll cannot be wagered")
check(game.action_for({"action" => "bet", "amount" => "9" * 1000}, initial, "Alice").first == :invalid, "Oversized amount accepted")
puts "Blackjack betting: individual stakes, validation, deal boundary, payouts, all-in, UI and legacy replay passed"
