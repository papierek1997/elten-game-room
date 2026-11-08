require_relative "../../../games/blackjack"
require_relative "../../../games/blackjack_dice"
require_relative "../../support/blackjack"

include BlackjackChecksSupport
repo = Repository.new(%w[Alice Bob Carol])
[GameRoomGames::Blackjack.new, GameRoomGames::BlackjackDice.new].each do |game|
  options = game.new_game_options("scoring" => "chips", "round_limit" => 2)
  session = {"options" => JSON.generate(options)}
  initial = game.replay(session, [], repo)
  check(initial.state[:phase] == :awaiting_ante, "#{game.id}: missing forced opening contribution")
  check(game.automatic_action(initial, "Alice")["action"] == "ante", "#{game.id}: ante not executed by shared runner")
  events = [event(1, "Alice", "ante")]
  opening = game.replay(session, events, repo)
  unit = game.id == "blackjack" ? 2 : 1
  check(opening.state[:chips].values == [90 * unit] * 3, "#{game.id}: mandatory 10 from every seat")
  check(opening.state[:auction][:contributions].values == [10 * unit] * 3, "#{game.id}: opening contributions missing")
  check(opening.state[:phase] == :betting && opening.current_player == "Alice", "#{game.id}: auction starts after ante")
  check(game.action_for({"action" => "raise", "raise_by" => 7, "quoted_call" => 0}, opening, "Alice").first == :ok, "#{game.id}: custom raise rejected")
  check(game.action_for({"action" => "raise", "raise_by" => 0, "quoted_call" => 0}, opening, "Alice").first == :invalid, "#{game.id}: zero raise accepted")
  check(game.action_for({"action" => "raise", "raise_by" => 91, "quoted_call" => 0}, opening, "Alice").first == :invalid, "#{game.id}: unfunded raise accepted")
  events << event(2, "Alice", "bet", "raise|#{7 * unit}")
  raised = game.replay(session, events, repo)
  check(raised.current_player == "Bob" && raised.state[:auction][:current_bet] == 17 * unit, "#{game.id}: raise failed")
  check(game.action_for({"action" => "raise", "raise_by" => 10, "quoted_call" => 0}, raised, "Bob").first == :invalid, "#{game.id}: stale custom raise accepted")
  check(game.replay(session, events + [events.last], repo).state == raised.state, "#{game.id}: duplicate raise charged twice")
  check(game.replay(session, events + [event(3, "Mallory", "bet", "call|#{7 * unit}")], repo).state == raised.state, "#{game.id}: forged bettor")
  events += [event(3, "Bob", "bet", "call|#{7 * unit}"), event(4, "Carol", "bet", "raise|#{14 * unit}")]
  reraised = game.replay(session, events, repo)
  check(reraised.current_player == "Alice" && reraised.state[:phase] == :betting, "#{game.id}: raise did not reopen prior decisions")
  events += [event(5, "Alice", "bet", "call|#{7 * unit}"), event(6, "Bob", "bet", "call|#{7 * unit}")]
  closed = game.replay(session, events, repo)
  check(closed.state[:phase] == (game.id == "blackjack" ? :awaiting_deal : :playing), "#{game.id}: matching bets did not close auction")
  check(closed.state[:chips].values == [76 * unit] * 3, "#{game.id}: wrong final debit")
  check(closed.state[:auction][:contributions].values == [24 * unit] * 3, "#{game.id}: wrong contribution ledger")
  check(game.game_shortcuts(opening, "Alice").any? { |s| s.key == "b" && s.kind == :number_input }, "#{game.id}: own amount missing")
  check(game.game_shortcuts(opening, "Alice").any? { |s| s.key == "r" && s.kind == :number_input }, "#{game.id}: poker raise shortcut missing")
end

[GameRoomGames::Blackjack.new, GameRoomGames::BlackjackDice.new].each do |game|
  unit = game.id == "blackjack" ? 2 : 1
  options = game.new_game_options("scoring" => "chips", "round_limit" => 2)
  state = game.replay({"options" => JSON.generate(options)}, [], repo).state
  state[:chips] = {"Alice" => 100 * unit, "Bob" => 100 * unit, "Carol" => 25 * unit}
  history = []
  game.send(:start_auction, state, repo.players, 1, history)
  [["Alice", "check", 0], ["Bob", "raise", 10], ["Carol", "all_in", 15], ["Alice", "call", 15]].each_with_index do |(actor, action, paid), index|
    check(game.send(:apply_auction, state, event(index + 2, actor, "bet", "#{action}|#{paid * unit}"), actor, index + 2, history), "Short all-in action rejected")
  end
  replay = GameRoomGames::Replay.new(state: state, players: repo.players, current_player: state[:current_player], draw: false)
  check(state[:current_player] == "Bob" && state[:auction][:current_bet] == 25 * unit, "Short all-in call not required")
  check(game.legal_actions(replay, "Bob").none? { |a| a["action"] == "raise" }, "Short all-in wrongly reopens a full raise")
  check(!game.eliminated_from_game?(replay, "Carol"), "All-in player eliminated before play")
  check(game.send(:apply_auction, state, event(6, "Bob", "bet", "call|#{5 * unit}"), "Bob", 6, history), "Short all-in matching failed")
end

dice = GameRoomGames::BlackjackDice.new
options = dice.new_game_options("scoring" => "chips", "round_limit" => 1)
build_short = lambda do
  state = dice.replay({"options" => JSON.generate(options)}, [], repo).state
  state[:chips] = {"Alice" => 5, "Bob" => 15, "Carol" => 25}
  history = []
  dice.send(:start_auction, state, repo.players, 1, history)
  check(state[:chips].values == [0, 5, 15] && state[:auction][:contributions].values == [5, 10, 10], "Ante must accept the whole short stack")
  check(state[:current_player] == "Bob", "All-in ante should skip bidding, not play")
  dice.send(:apply_auction, state, event(2, "Bob", "bet", "check|0"), "Bob", 2, history)
  dice.send(:apply_auction, state, event(3, "Carol", "bet", "raise|10"), "Carol", 3, history)
  dice.send(:apply_auction, state, event(4, "Bob", "bet", "all_in|5"), "Bob", 4, history)
  check(state[:phase] == :playing && state[:order] == repo.players, "All-in seats lost their dice turns")
  [state, history]
end
state, history = build_short.call
state[:totals] = {"Alice" => 21, "Bob" => 20, "Carol" => 22}
dice.send(:finish_chip_round, state, 5, history)
check(state[:chips] == {"Alice" => 15, "Bob" => 20, "Carol" => 10} && state[:pot] == 0, "Main pot, side pot or uncalled refund is wrong")
check(state[:chips].values.sum == 45, "Side pots changed chip supply")
state, history = build_short.call
state[:totals] = repo.players.to_h { |player| [player, 22] }
dice.send(:finish_chip_round, state, 5, history)
check(state[:chips] == {"Alice" => 5, "Bob" => 15, "Carol" => 25}, "All-bust did not refund individual contributions")
state = dice.replay({"options" => JSON.generate(options)}, [event(1, "Alice", "ante"), event(2, "Alice", "bet", "fold|0"), event(3, "Bob", "bet", "fold|0")], repo).state
check(state[:phase] == :finished && state[:chips] == {"Alice" => 90, "Bob" => 90, "Carol" => 120}, "Uncontested pot did not settle without rolling")

card = BlackjackChecksSupport::FixedDeck.new
card.first_cards = %w[AS 9C KD 8D]
one = Repository.new(["Alice"])
options = card.new_game_options("round_limit" => 1)
state = card.replay({"options" => JSON.generate(options)}, [], one).state
state[:chips]["Alice"] = 1
history = []
card.send(:start_auction, state, one.players, 1, history)
check(state[:phase] == :awaiting_deal && state[:auction][:contributions]["Alice"] == 1, "Half-chip balance must enter all-in")
card.send(:apply_event, state, event(2, "Alice", "deal", "1|#{'a' * 32}"), "Alice", 2, history)
card.send(:apply_event, state, event(3, "Alice", "dealer"), "Alice", 3, history)
check(state[:chips]["Alice"] == Rational(5, 2), "Short natural payout lost a quarter chip")
state[:options]["round_limit"] = 2
state[:options]["stake"] = 1
state[:chips]["Alice"] = Rational(1, 2)
state[:hands]["Alice"] = [{cards: %w[0:TC 0:6D], bet: 2, split: false, done: true}]
state[:dealer] = %w[0:9C 0:8D]
card.send(:settle, state, 4, [])
check(state[:phase] == :awaiting_ante && state[:eliminated].empty?, "Positive quarter-chip balance wrongly eliminated")
card.send(:start_auction, state, one.players, 5, [])
check(state[:auction][:contributions]["Alice"] == Rational(1, 2), "Positive quarter-chip balance cannot fund the next ante")
two = Repository.new(%w[Alice Bob])
state = card.replay({"options" => JSON.generate(card.new_game_options({}))}, [], two).state
state[:chips]["Alice"] = Rational(41, 2)
card.send(:start_auction, state, two.players, 1, [])
check(card.send(:apply_auction, state, event(2, "Alice", "bet", "all_in|1~1"), "Alice", 2, []), "Fractional all-in rejected")
check(card.send(:apply_auction, state, event(3, "Bob", "bet", "call|1~1"), "Bob", 3, []), "Fractional all-in matching rejected")
check(state[:auction][:contributions].values == [Rational(41, 2)] * 2 && state[:phase] == :awaiting_deal, "Fractional matching changed the ledger")
tiny = Rational(5 ** 100, 2 ** 100)
wire = card.send(:auction_wire, tiny)
check(wire.length + 'all_in|'.length <= GameRoomEventProtocol::MAX_VALUE_LENGTH, "Exact fractional wager exceeds the native wire limit")
state[:chips]["Alice"] = tiny
state[:current_player] = "Alice"
check(card.send(:auction_payment, wire, state) == tiny, "Compact fractional payment changed value")
check(card.send(:auction_payment, '1~zzzzzz', state).nil?, "Unbounded fractional exponent accepted")
puts "Both blackjack auctions: forced ante, custom raises, matching, reopening, replay and shortcut boundaries passed"
