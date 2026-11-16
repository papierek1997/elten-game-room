require_relative "../support/new_games_fixture"

players = %w[Alice Bob Carol]
repository = NewGames116Repository.new(players)
event = { "id" => 1, "actor" => "Alice", "value" => "" }
checks = 0
check = lambda do |name, &block|
  block.call
  checks += 1
  puts "OK: #{name}"
end

check.call("Poker: R, G and draw-poker card numbers") do
  game = GameRoomGames::Poker.new
  state = game.send(:initial_state, players, game.default_options.merge("variant" => "draw"))
  state.update(phase: :betting, current_player: "Alice")
  state[:hands]["Alice"] = %w[2C 3D 5H 7S 9C]
  view = GameRoomGames::Replay.new(players: players, state: state, current_player: "Alice")
  shortcuts = game.custom_game_shortcuts(view, "Alice")
  assert(shortcuts.find { |s| s.key == "r" }.prompt == "Raise by:", "Raise prompt is verbose")
  assert(shortcuts.find { |s| s.key == "g" }.message == "You have no combination.", "G reads high card")
  displayed_cards = %w[5H 7S 3D 2C 9C]
  1.upto(5) do |n|
    assert(shortcuts.find { |s| s.key == n.to_s }.message == game.send(:poker_card_label, displayed_cards[n - 1]), "Wrong displayed draw card #{n}")
  end
  state[:hands]["Alice"] = %w[2C 2D]
  assert(game.send(:best_combination_text, state[:hands]["Alice"]) == "one pair: 2.", "Pair of twos lost")
  state[:contributions]["Alice"] = 300
  assert(game.send(:betting_history, "Alice", "all_in", 100, state) == "Alice is all in for 100.", "All-in reads cumulative payment")
end

check.call("UNO: roulette and buzzer status") do
  game = GameRoomGames::Uno.new
  state = game.send(:initial_state, players, game.default_options)
  state.update(phase: :playing, current_player: "Bob", pending_type: "C", pending_colour: "R", pending_draw: 0)
  message = game.send(:penalty_text, state)
  assert(message.include?("Bob") && message.include?("red"), "Roulette is hidden")
  state[:buzzer_active] = true
  assert(game.send(:status_text, state, "Alice").include?("B"), "Buzzer says ordinary turn")
end

check.call("Yahtzee: special score and upper bonus announcements") do
  game = GameRoomGames::Yahtzee.new
  state = game.send(:initial_state, players, game.default_options)
  state.update(current_player: "Alice", dice: [2, 2, 2, 2, 2], turn_rolls: 1)
  state[:sheets]["Alice"]["yahtzee"] = 50
  before = game.send(:sheet_total, state, "Alice")
  history = []
  assert(game.send(:apply_score, state, event.merge("value" => "twos"), "Alice", repository, history), "Score refused")
  assert(game.send(:sheet_total, state, "Alice") - before == 10, "Yahtzee must not add a separate bonus")
  assert(history.none? { |h| h.text.include?("100") }, "Retired bonus was announced")
  state = game.send(:initial_state, players, game.default_options.merge("upper_bonus" => true))
  state[:sheets]["Alice"].merge!("ones" => 3, "twos" => 6, "threes" => 9, "fours" => 12, "fives" => 15)
  state.update(current_player: "Alice", dice: [1, 2, 6, 6, 6], turn_rolls: 1)
  history = []
  game.send(:apply_score, state, event.merge("value" => "sixes"), "Alice", repository, history)
  assert(history.count { |h| h.text.include?("35") } == 1, "Upper bonus missing or repeated")
  state.update(current_player: "Alice", dice: [1, 2, 3, 4, 5], turn_rolls: 1)
  game.send(:apply_score, state, event.merge("id" => 2, "value" => "chance"), "Alice", repository, history)
  assert(history.count { |h| h.text.include?("35") } == 1, "Upper bonus repeated on later score")
end

check.call("Makao: accepted wait and first-card rejection") do
  game = GameRoomGames::Makao.new
  state = game.send(:initial_state, players, game.default_options)
  state.update(phase: :playing, current_player: "Alice", skip_penalty: 3)
  history = []
  assert(game.send(:apply_accept_skip, state, event, "Alice", repository, history), "Wait refused")
  assert(state[:skip_turns]["Alice"] == 2, "Wait rules changed")
  assert(game.send(:penalty_text, state, "Alice").include?("2"), "Accepted wait disappeared from G")
  assert(game.move_error(:illegal_card).include?("first card"), "Packet rejection is misleading")
end

check.call("Monopoly: actual rent and remaining debt") do
  game = GameRoomGames::Monopoly.new
  state = game.send(:initial_state, players, game.default_options)
  state[:owners][1] = "Bob"
  state[:houses][1] = 4
  state[:positions]["Alice"] = 1
  state[:cash]["Alice"] = 20
  state[:options]["automatic_rent"] = true
  history = []
  bob_before = state[:cash]["Bob"]
  game.send(:resolve_square, state, "Alice", 1, history)
  assert(state[:cash]["Bob"] == bob_before + 20, "Actual rent transfer changed")
  text = history.map(&:text).join(" ")
  assert(text.include?("pays Bob 20") && text.include?("140") && text.include?(state[:board][1][:name]), "Rent hides partial payment: #{text}")
  assert(!text.include?("Cash:"), "Automatic cash survived")
  state[:cash]["Alice"] += 200
  history = []
  game.send(:settle_debts, state, 2, history)
  assert(history.any? { |h| h.text.include?("Alice") && h.text.include?("Bob") && h.text.include?("140") }, "Debt repayment is silent")
end

puts "#{checks} message regression groups passed"
