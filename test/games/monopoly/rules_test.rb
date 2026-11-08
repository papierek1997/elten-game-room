require_relative '../../support/new_games_fixture'

players = %w[Alice Bob Carol]
repository = NewGames116Repository.new(players)

boards = GameRoomContent::MonopolyBoards::BOARD_NAMES.keys
assert(boards.length == 19 && boards.include?("poland"), "Monopoly does not expose all agreed boards")
boards.each do |board_id|
  board = GameRoomContent::MonopolyBoards.build(board_id)
  large = %w[latin_america romania balkans indonesia southeast_asia twelve_nations].include?(board_id)
  assert(board[:squares].length == (large ? 60 : 40), "Monopoly board #{board_id} has the wrong size")
  assert(board[:squares].each_with_index.all? { |square, index| square[:index] == index }, "Monopoly board indices are unstable")
  property_names = board[:squares].select { |square| square[:type] == :property }.map { |square| square[:name] }
  assert(property_names.length == (large ? 34 : 22) && property_names.uniq.length == property_names.length,
    "Monopoly board #{board_id} has missing or repeated property names")
  assert(property_names.none? { |name| name.match?(/property \d+\z/i) },
    "Monopoly board #{board_id} still contains placeholder property names")
end

monopoly = GameRoomGames::Monopoly.new
monopoly_session = { "options" => JSON.generate(monopoly.default_options) }
monopoly_events = []
monopoly_replay = monopoly.replay(monopoly_session, monopoly_events, repository)
assert(monopoly.legal_actions(monopoly_replay, "Alice").any? { |action| action["action"] == "roll" }, "Monopoly does not begin with Roll")
monopoly_replay = append_action(monopoly, monopoly_session, repository, monopoly_events, monopoly_replay,
  "Alice", { "kind" => "command", "action" => "roll" }, context_for)
assert(monopoly_events.first["value"].split(",").length == 3, "Monopoly roll does not contain deterministic dice and card values")
assert(monopoly_replay.state[:positions]["Alice"] > 0, "Monopoly did not move the first player")
assert(monopoly.maximum_players == 8 && monopoly.supports_bots?, "Monopoly multiplayer or bots are missing")
assert(monopoly.default_options.values_at("free_parking_jackpot", "double_salary_on_start", "supplementary_cards", "automatic_rent") == [true, true, true, true],
  "Monopoly agreed enabled defaults changed")
assert(monopoly.default_options.values_at("forbid_first_round_purchase", "no_rent_in_jail", "lucky_double_one", "auction_unsold") == [false, false, false, false],
  "Monopoly agreed disabled defaults changed")

automatic_turn = monopoly.replay(monopoly_session, [
  { "id" => 1, "actor" => "Alice", "action" => "roll", "value" => "1,3,1" }
], repository)
assert(automatic_turn.state[:phase] == :awaiting_roll && automatic_turn.current_player == "Bob",
  "Monopoly did not advance automatically after resolving a square")
assert(monopoly.legal_actions(automatic_turn, "Bob").none? { |action| action["action"] == "end_turn" },
  "Monopoly still exposes End turn")

# Crossing Start on the roll and reaching Start again by Chance are two separate payments.
salary_state = monopoly.send(:initial_state, players, monopoly.default_options)
chance = salary_state[:board].find { |square| square[:type] == :chance }
salary_state[:positions]["Alice"] = salary_state[:board].length + chance[:index] - 9
salary_state[:card_decks] = { chance: [1], community: [] }
salary = salary_state[:board_data].fetch(:salary)
cash_before = salary_state[:cash]["Alice"]
salary_roll = { "id" => 77, "action" => "roll", "value" => "4,5,1" }
salary_history = []
assert(monopoly.send(:apply_roll, salary_state, salary_roll, "Alice", repository, salary_history),
  "Start salary fixture rejected the roll")
assert(salary_state[:positions]["Alice"].zero? && salary_state[:laps]["Alice"] == 2 &&
  salary_state[:cash]["Alice"] == cash_before + salary * 3, "Roll and Chance did not pay both salaries")
salary_entries = salary_history.select { |entry| entry.key.start_with?("salary:") }
assert(salary_entries.map(&:text) == ["Alice collected #{salary} for passing Start.",
  "Alice receives double salary, #{salary * 2}, for landing on Start."],
  "Salary announcements are missing or out of order")
assert(salary_history.map(&:key).uniq.size == salary_history.size, "Separate salary payments share a history key")

purchase_state = monopoly.send(:initial_state, players, monopoly.default_options)
purchase_state[:positions]["Alice"] = 1
purchase_state[:phase] = :property_decision
purchase_label = monopoly.send(:action_label, { "action" => "buy" }, purchase_state, "Alice")
assert(purchase_label == "Buy", "Monopoly purchase action is not concise")
purchase_history = []
monopoly.send(:resolve_square, purchase_state, "Alice", 99, purchase_history)
assert(purchase_history.last.text.include?("pink group"), "Monopoly does not announce the QC property's color before purchase")

manual_state = monopoly.send(:initial_state, players, monopoly.normalize_options("automatic_rent" => false))
manual_state[:positions]["Alice"] = 39
manual_state[:owners][1] = "Bob"
manual_history = []
manual_roll = { "id" => 1, "actor" => "Alice", "action" => "roll", "value" => "1,1,1" }
assert(monopoly.send(:apply_roll, manual_state, manual_roll, "Alice", repository, manual_history), "Manual-rent setup roll failed")
assert(manual_state[:phase] == :rent_decision && manual_state[:current_player] == "Bob", "Manual rent was not offered to the owner")
manual_rent = { "id" => 2, "actor" => "Bob", "action" => "request_rent", "value" => "" }
alice_cash = manual_state[:cash]["Alice"]
bob_cash = manual_state[:cash]["Bob"]
assert(monopoly.send(:apply_manual_rent, manual_state, manual_rent, "Bob", repository, manual_history), "Manual rent request failed")
assert(manual_state[:cash]["Alice"] < alice_cash && manual_state[:cash]["Bob"] > bob_cash, "Manual rent did not transfer money")
assert(manual_state[:phase] == :turn_complete && manual_state[:current_player] == "Alice", "Manual rent did not return the turn to the payer")

trade_state = monopoly.send(:initial_state, players, monopoly.default_options)
trade_state[:phase] = :turn_complete
trade_state[:owners][1] = "Alice"
trade_replay = GameRoomGames::Replay.new(players: players, current_player: "Alice", winner: nil,
  draw: false, accepted_events: [], history: [], state: trade_state)
offer = monopoly.legal_actions(trade_replay, "Alice").find do |action|
  next false if action["action"] != "trade_offer"
  parsed = monopoly.send(:parse_trade_offer, trade_state, action["offer"])
  parsed[:target] == "Bob" && parsed[:give_properties] == [1] && parsed[:receive_properties].empty?
end
assert(offer != nil, "Monopoly did not create a property sale proposal")
trade_history = []
offer_event = { "id" => 3, "actor" => "Alice", "action" => "trade_offer", "value" => offer["offer"] }
assert(monopoly.send(:apply_trade, trade_state, offer_event, "Alice", repository, trade_history), "Monopoly rejected a valid trade proposal")
accept_event = { "id" => 4, "actor" => "Bob", "action" => "trade_accept", "value" => "" }
assert(monopoly.send(:apply_trade, trade_state, accept_event, "Bob", repository, trade_history), "Monopoly rejected an accepted trade")
assert(trade_state[:owners][1] == "Bob" && trade_state[:current_player] == "Alice", "Monopoly did not transfer the property and restore the turn")
assert(offer["offer"].length <= 64, "Monopoly trade event exceeds the transport limit")

debt_state = monopoly.send(:initial_state, players, monopoly.default_options)
debt_state[:cash]["Alice"] = -25
debt_replay = GameRoomGames::Replay.new(players: players, current_player: "Alice", winner: nil,
  draw: false, accepted_events: [], history: [], state: debt_state)
debt_surface = monopoly.surface_spec(debt_replay, "Alice")
assert(debt_surface.items.length == 1 && debt_surface.items.first.action.name == "roll",
  "Monopoly debt interface exposes decisions other than the agreed Roll entry")

jackpot_state = monopoly.send(:initial_state, players, monopoly.default_options)
monopoly.send(:pay_and_describe, jackpot_state, "Alice", monopoly.send(:bank_recipient, jackpot_state), 75, "fine")
assert(jackpot_state[:cash]["Alice"] == 1_425 && jackpot_state[:jackpot] == 75,
  "Monopoly did not add a bank fine to the Free Parking jackpot")
jackpot_state[:positions]["Alice"] = 20
monopoly.send(:resolve_square, jackpot_state, "Alice", 30, [])
assert(jackpot_state[:cash]["Alice"] == 1_500 && jackpot_state[:jackpot].zero?,
  "Monopoly did not pay and clear the Free Parking jackpot")

utility_state = monopoly.send(:initial_state, players, monopoly.default_options)
utility_state[:last_roll] = 8
utility_state[:owners][12] = "Alice"
assert(monopoly.send(:rent_for, utility_state, utility_state[:board][12], "Alice") == 32,
  "Monopoly one-utility rent does not use four times the dice roll")
utility_state[:owners][28] = "Alice"
assert(monopoly.send(:rent_for, utility_state, utility_state[:board][12], "Alice") == 80,
  "Monopoly two-utility rent does not use ten times the dice roll")

building_state = monopoly.send(:initial_state, players, monopoly.default_options)
building_state[:owners][1] = building_state[:owners][3] = "Alice"
building_state[:houses][1] = 1
building_state[:houses][3] = 0
assert(!monopoly.send(:can_build?, building_state, "Alice", building_state[:board][1]) &&
  monopoly.send(:can_build?, building_state, "Alice", building_state[:board][3]),
  "Monopoly permits building unevenly across a colour group")
assert(monopoly.send(:can_sell_building?, building_state, "Alice", building_state[:board][1]) &&
  !monopoly.send(:can_sell_building?, building_state, "Alice", building_state[:board][3]),
  "Monopoly permits selling buildings unevenly across a colour group")
assert(!monopoly.send(:can_mortgage?, building_state, "Alice", building_state[:board][3]),
  "Monopoly permits mortgaging a colour-group property while the group has a building")

standard_cards_state = monopoly.send(:initial_state, players,
  monopoly.normalize_options("supplementary_cards" => false))
supplementary_cards_state = monopoly.send(:initial_state, players,
  monopoly.normalize_options("supplementary_cards" => true))
monopoly.send(:initialize_card_decks, standard_cards_state, "standard")
monopoly.send(:initialize_card_decks, supplementary_cards_state, "standard")
assert(standard_cards_state[:card_decks].values.all? { |deck| deck.length == 16 } &&
  supplementary_cards_state[:card_decks].values.all? { |deck| deck.length == 18 },
  "Monopoly supplementary card option does not select the expanded card set")

puts 'PASS monopoly: rules, legal actions and options'
