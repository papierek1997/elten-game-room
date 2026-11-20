require_relative "../support/new_games_fixture"
require_relative "../../lib/game_sounds"

PLAYERS = %w[Alice Bob Carol].freeze
REPOSITORY = NewGames116Repository.new(PLAYERS)
def state_for(game, options = {})
  state = game.send(:initial_state, PLAYERS, game.normalize_options(options))
  if game.id == "poker"
    deck = game.send(:standard_deck)
    count = state[:options]["variant"] == "draw" ? 5 : 2
    state[:hands] = PLAYERS.to_h { |player| [player, deck.shift(count)] }
    state[:deck] = deck
    state[:dealer_index] = 0
    state[:hand_number] = 1
  end
  state
end
def view(state, history = [])
  GameRoomGames::Replay.new(players: state[:players], current_player: state[:current_player],
    state: state, history: history, winner: state[:winner], draw: state[:draw] || false, accepted_events: [])
end
def event(action, value = "", actor = "Alice")
  { "id" => 99, "action" => action, "value" => value, "actor" => actor }
end
def best(game, state, actor = "Alice")
  replay = view(state)
  game.legal_actions(replay, actor).max_by { |action| game.bot_action_score(replay, actor, action) }
end
checks = 0
%w[holdem draw].each do |variant|
  %w[no_limit fixed half_pot pot_limit].each do |structure|
    poker = GameRoomGames::Poker.new
    state = state_for(poker, "variant" => variant, "betting" => structure)
    state.update(phase: :betting, current_player: "Alice", current_bet: 20, min_raise: 10,
      street_bets: { "Alice" => 0, "Bob" => 20, "Carol" => 20 },
      contributions: { "Alice" => 20, "Bob" => 20, "Carol" => 20 })
    shortcut = poker.custom_game_shortcuts(view(state), "Alice").find { |entry| entry.key == "r" }
    expected_max = { "no_limit" => 980, "fixed" => 10, "half_pot" => 40, "pot_limit" => 80 }.fetch(structure)
    assert(shortcut.allowed_values == (10..expected_max), "#{variant}/#{structure}: wrong input bounds #{shortcut.allowed_values}")
    increment = structure == "fixed" ? 10 : 37
    selection = { "kind" => "command", "action" => "raise", "quoted_call" => 20, "raise_by" => increment }
    status, plan = poker.action_for(selection, view(state), "Alice")
    assert(status == :ok && plan.events.first.value == "raise|#{20 + increment}", "Custom raise not converted correctly")
    changed = Marshal.load(Marshal.dump(state))
    assert(poker.send(:apply_bet, changed, event("bet", plan.events.first.value), "Alice", REPOSITORY, []), "Replay rejected custom raise")
    assert(changed[:stacks]["Alice"] == 1000 - 20 - increment && changed[:current_bet] == 20 + increment, "#{variant}/#{structure}: wrong actual payment #{changed.values_at(:stacks, :current_bet, :phase).inspect}")
    [9, expected_max + 1, "10junk", -2].each do |invalid|
      rejected, = poker.action_for(selection.merge("raise_by" => invalid), view(state), "Alice")
      assert(rejected != :ok, "Invalid custom raise accepted: #{invalid}")
    end
    status, = poker.action_for(selection.merge("quoted_call" => 19), view(state), "Alice")
    assert(status != :ok, "A stale quoted call silently changed the payment")
    state[:options].merge!("raise_cap_enabled" => true, "raise_cap" => 1)
    state[:raises] = 1
    assert(poker.action_for(selection, view(state), "Alice").first != :ok, "Custom raise bypasses cap")
    checks += 1
  end
end

poker = GameRoomGames::Poker.new
%w[holdem draw].each do |variant|
  state = state_for(poker, "variant" => variant)
  state.update(phase: :betting, current_player: "Alice")
  shortcut = poker.custom_game_shortcuts(view(state), "Alice").find { |entry| entry.key == "r" }
  assert(shortcut.payload["quoted_call"] == 0, "Opening bet incorrectly includes a call")
  status, plan = poker.action_for({ "action" => "raise", "kind" => "command", "raise_by" => 37, "quoted_call" => 0 }, view(state), "Alice")
  assert(status == :ok && plan.events.first.value == "raise|37", "Opening bet rejected in #{variant}")
  assert(poker.send(:apply_bet, state, event("bet", plan.events.first.value), "Alice", REPOSITORY, []), "Opening bet replay rejected")
  assert(state[:current_bet] == 37 && state[:stacks]["Alice"] == 963, "Opening bet charged the wrong amount")
  checks += 1
end
state = state_for(poker)
state.update(phase: :betting, current_player: "Alice", current_bet: 30, min_raise: 20,
  acted: { "Alice" => true }, acted_at_bet: { "Alice" => 20 },
  street_bets: { "Alice" => 20, "Bob" => 30, "Carol" => 20 })
assert(poker.send(:raise_limits, state, "Alice") == nil, "A short all-in reopened raising")
state[:current_bet] = 40
assert(poker.send(:raise_limits, state, "Alice") != nil, "Cumulative full increase did not reopen raising")
state.update(acted: {}, acted_at_bet: {}, current_bet: 20)
state[:street_bets]["Alice"] = 0
state[:stacks]["Alice"] = 25
assert(poker.send(:raise_limits, state, "Alice") == (25..25), "Short all-in below minimum is unavailable")
assert(poker.send(:bet_candidate, state, "Alice", "raise", 24) == nil, "A short non-all-in raise was accepted")
checks += 1

# Bot choices use only visible information. A made hand is not discarded, and
# a weak draw hand no longer receives an unconditional 'keep all' preference.
state = state_for(poker, "variant" => "draw")
state.update(phase: :exchange, current_player: "Alice")
state[:hands]["Alice"] = %w[TH JH QH KH AH]
assert(JSON.parse(best(poker, state)["cards"]).empty?, "Poker bot breaks a royal flush")
state[:hands]["Alice"] = %w[3H 4C 7D 9S KC]
assert(!JSON.parse(best(poker, state)["cards"]).empty?, "Poker bot keeps a weak unrelated hand")
state.update(phase: :betting, current_bet: 20, min_raise: 10)
state[:street_bets]["Bob"] = 20
state[:contributions]["Bob"] = 20
own_choice = best(poker, state)
state[:hands]["Bob"] = %w[AH AD AC AS KH]
state[:deck] = %w[KH QH JH TH]
assert(best(GameRoomGames::Poker.new, state) == own_choice, "Poker strategy depends on hidden opponent cards/deck")
checks += 1

yahtzee = GameRoomGames::Yahtzee.new
state = state_for(yahtzee)
state.update(dice: [1, 6, 6, 6, 6], turn_rolls: 1)
assert(best(yahtzee, state).values_at("action", "die_ids") == ["roll", "d0"], "Yahtzee bot does not pursue four sixes")
state.update(dice: [2, 3, 4, 5, 6], turn_rolls: 2)
assert(best(yahtzee, state).values_at("action", "category") == ["score", "large_straight"], "Yahtzee bot discards a large straight")
state.update(dice: [6, 6, 6, 6, 6], turn_rolls: 1)
assert(best(yahtzee, state).values_at("action", "category") == ["score", "yahtzee"], "Yahtzee bot discards Yahtzee")
checks += 1

makao = GameRoomGames::Makao.new
state = state_for(makao, "profile" => "joker")
state.update(phase: :playing, current_player: "Alice", discard: %w[9H], declared_suit: "H",
  hands: { "Alice" => %w[7H 7C 7D 5S], "Bob" => %w[8C 9C], "Carol" => %w[6C 8S] })
choice = best(makao, state)
assert(JSON.parse(choice["cards"]).length == 3, "Makao bot ignores its legal packet")
checks += 1

monopoly = GameRoomGames::Monopoly.new
state = state_for(monopoly)
state[:cash]["Alice"] = 1
state[:owners][1] = "Alice"
monopoly.send(:pay_money, state, "Alice", "Bob", 100)
assert(state[:cash].values_at("Alice", "Bob") == [-99, 1501], "Unpaid debt was credited to owner")
state[:cash]["Alice"] += 60
monopoly.send(:settle_debts, state)
assert(state[:cash].values_at("Alice", "Bob") == [-39, 1561], "Partial debt settlement is incorrect")
monopoly.send(:apply_bankruptcy, state, event("bankrupt"), "Alice", REPOSITORY, [])
assert(state[:owners][1] == "Bob" && state[:cash]["Bob"] == 1561, "Bankruptcy loses assets or creates cash")
checks += 1

state = state_for(monopoly)
state.update(current_player: "Alice", phase: :turn_complete, extra_turn: true)
state[:cash]["Bob"] = 0
monopoly.send(:pay_money, state, "Bob", "Alice", 10)
monopoly.send(:advance_completed_turn, state)
assert(state[:current_player] == "Alice" && state[:phase] == :awaiting_roll, "Birthday debt stole the original extra roll")
state[:cash]["Bob"] += 20
monopoly.send(:settle_debts, state)
monopoly.send(:advance_completed_turn, state)
assert(state[:current_player] == "Alice" && state[:phase] == :awaiting_roll, "Debt settlement interrupted the current turn")
state.update(winner: "Alice", phase: :finished, current_player: nil)
monopoly.send(:advance_completed_turn, state)
assert(state[:phase] == :finished, "Debt resume reopened a finished match")
checks += 1

state = state_for(monopoly)
monopoly.send(:initialize_card_decks, state, "cards")
state[:card_decks][:chance].delete(8)
state[:card_decks][:chance].unshift(8)
monopoly.send(:draw_event_card, state, "Alice", :chance, 99, [])
assert(state[:jail_cards]["Alice"] == 1 && !state[:card_decks][:chance].include?(8), "Held jail card is still in deck")
state[:jail]["Alice"] = 3
assert(monopoly.send(:apply_jail_action, state, event("use_jail_card"), "Alice", REPOSITORY, []), "Could not use jail card")
assert(state[:card_decks][:chance].count(8) == 1 && state[:jail_cards]["Alice"] == 0, "Jail card was not returned once")
checks += 1

state = state_for(monopoly)
state[:owners].merge!(1 => "Alice", 3 => "Alice")
state[:houses].merge!(1 => 1, 3 => 1, 6 => 30)
assert(!monopoly.send(:can_build?, state, "Alice", state[:board][1]), "Building ignores 32-house supply")
state[:houses] = Hash.new(0).merge(1 => 4, 3 => 4)
state[:board].select { |square| square[:type] == :property && ![1, 3].include?(square[:index]) }.first(12).each { |square| state[:houses][square[:index]] = 5 }
assert(!monopoly.send(:can_build?, state, "Alice", state[:board][1]), "Building ignores 12-hotel supply")
checks += 1

state = state_for(monopoly)
state[:owners].merge!(1 => "Alice", 3 => "Alice", 6 => "Bob")
offer = JSON.generate(target: 1, give_properties: [1, 3], receive_properties: [6], give_cash: 13, receive_cash: 87)
assert(monopoly.send(:apply_trade, state, event("trade_offer", offer), "Alice", REPOSITORY, []), "Custom package trade rejected")
assert(monopoly.send(:apply_trade, state, event("trade_accept", "", "Bob"), "Bob", REPOSITORY, []), "Custom package acceptance rejected")
assert(state[:owners].values_at(1, 3, 6) == %w[Bob Bob Alice] && state[:cash].values_at("Alice", "Bob") == [1574, 1426], "Custom trade transferred wrong cash/assets")
checks += 1

state = state_for(monopoly)
state[:owners].merge!(1 => "Alice", 3 => "Alice")
state[:houses].merge!(1 => 5, 3 => 5)
state[:board].select { |square| square[:type] == :property && ![1, 3].include?(square[:index]) }.first(8).each { |square| state[:houses][square[:index]] = 4 }
sell = monopoly.custom_game_shortcuts(view(state), "Alice").find { |shortcut| shortcut.key == "h" && shortcut.modifiers == [:shift] }
assert(sell.kind == :surface && monopoly.surface_spec(view(state), "Alice").menus["sell"].first.label.include?("Sell all buildings"), "Hotel liquidation was not clearly labelled")
assert(monopoly.send(:apply_property_action, state, event("sell", "1"), "Alice", REPOSITORY, []), "Unable to liquidate hotel group")
assert(state[:houses].values_at(1, 3) == [0, 0] && state[:cash]["Alice"] == 1750, "Hotel liquidation gives incorrect refund")
checks += 1

state = state_for(monopoly)
state[:cash]["Alice"] = -10
state[:owners][1] = "Alice"
assert(best(monopoly, state)["action"] != "roll", "Insolvent Monopoly bot keeps attempting to roll")
checks += 1

# A rejected rescue offer must rank below bankruptcy when no other rescue
# exists; otherwise the debtor can keep making the same proposal forever.
state[:mortgaged][1] = true
offer = "1|1|-1|0|60"
state[:rejected_trades]["Alice|#{offer}"] = true
rejected = monopoly.bot_action_score(view(state), "Alice", { "action" => "trade_offer", "offer" => offer })
bankrupt = monopoly.bot_action_score(view(state), "Alice", { "action" => "bankrupt" })
assert(rejected < bankrupt, "Rejected trade still wins over the only remaining exit")
checks += 1

uno = GameRoomGames::Uno.new
state = state_for(uno)
state.update(phase: :playing, round: 1, current_player: "Alice", discard: %w[R5a], colour: "R",
  hands: { "Alice" => %w[R6a B1a G2a], "Bob" => %w[Y3a B4a], "Carol" => %w[G5a R7a] })
assert(best(uno, state)["action"] == "play", "UNO bot draws instead of making a regular legal play")
state[:hands]["Alice"] = %w[R6a]
assert(best(uno, state)["action"] == "play", "UNO bot postpones a certain immediate win")
state[:hands]["Alice"] = %w[Y6a]
assert(best(uno, state)["action"] == "uno", "UNO bot forgets its available declaration")
checks += 1

# Mappings exercise existing sound assets, without changing any other game.
sound_cases = [
  [GameRoomGames::Uno.new, "play", "R6a||0", "play"],
  [GameRoomGames::Uno.new, "draw", "0", "draw"],
  [makao, "play", "7H|", "play"], [makao, "draw", "", "draw"],
  # Poker's accepted state transitions, including private exchange receipts,
  # have separate coverage in poker/accepted_sounds_contract_test.rb.
  [yahtzee, "roll", "2,3,4,4,4", "roll"], [yahtzee, "score", "chance", "five_dice_record"],
  [monopoly, "roll", "1,2,seed", "roll"], [monopoly, "buy", "", "play2"]
]
sound_cases.each do |game, action, value, expected|
  state = state_for(game)
  actual = GameRoomSounds.event_cue(game: game, event: event(action, value), before_replay: view(state),
    after_replay: view(state), repository: REPOSITORY, viewer: "Alice")
  assert(actual == expected, "#{game.id}/#{action}: missing or wrong sound #{actual}")
  assert(File.file?(File.expand_path("../../Audio/#{expected}.opus", __dir__)), "Missing sound asset #{expected}")
  checks += 1
end
uno = GameRoomGames::Uno.new
state = state_for(uno)
history = [GameRoomGames::HistoryEntry.new(key: "round:99", event_id: 99, kind: :round_result, actor: "Bob")]
{ "Alice" => "lose1", "Bob" => "win1", "Carol" => "lose1" }.each do |viewer, expected|
  actual = GameRoomSounds.event_cue(game: uno, event: event("play"), before_replay: view(state),
    after_replay: view(state, history), repository: REPOSITORY, viewer: viewer)
  assert(actual == ["play", expected], "UNO round sound incorrect for #{viewer}: #{actual}")
  checks += 1
end
puts "Five-game follow-up checks passed: #{checks}"
