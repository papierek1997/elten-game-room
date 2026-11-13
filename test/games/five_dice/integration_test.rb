require_relative "../../support/cat_head_tail"
require_relative "../../../games/kosciane"

game = GameRoomGames::Kosciane.new
repo = CatHeadTailRepository.new(%w[Alice Bob])
session = {"options" => JSON.generate(game.default_options)}
events = [cht_event(1, "Bob", "roll", "2,2,5,5,5"),
          cht_event(2, "Alice", "roll", "2,2,5,5,5")]
replay = game.replay(session, events, repo)
assert(replay.accepted_events.size == 1, "Out-of-turn roll was accepted")
assert(game.custom_game_shortcuts(replay, "Alice").find { |shortcut| shortcut.key == "b" }.default_value.score_categories.include?("full_house"), "Full house is missing")
assert(game.action_for({"action" => "score", "category" => "full_house"}, replay, "Alice").first == :ok, "Score action was refused")
assert(game.action_for({"action" => "score", "category" => "cross:1"}, replay, "Alice").first != :ok, "Early cross was accepted")
events << cht_event(3, "Alice", "score", "full_house")
replay = game.replay(session, events, repo)
assert(replay.current_player == "Bob", "Turn did not advance")
assert(game.participant_scores(replay) == {"Alice" => 19, "Bob" => 0}, "Public totals differ")
assert(game.custom_game_shortcuts(replay, "Alice").any? { |shortcut| shortcut.key == "v" }, "Score sheet is inaccessible")
puts "PASS Kościane: replay, score selection, turn and shortcuts"

actions = game.legal_actions(replay, "Bob")
strategy = game.bot_strategy
choice = strategy.choose(actions: actions, actor: "Bob", game: game, replay: replay, random_source: Random.new(1))
assert(game.supports_bots? && choice["action"] == "roll", "Bot cannot begin its turn")
3.times { |i| events << cht_event(4 + i, "Bob", "roll", "2,2,5,5,5") }
replay = game.replay(session, events, repo)
actions = game.legal_actions(replay, "Bob")
choice = strategy.choose(actions: actions, actor: "Bob", game: game, replay: replay, random_source: Random.new(1))
assert(choice["category"] == "full_house", "Bot did not take the strongest available score")
assert(game.action_for(choice, replay, "Bob").first == :ok, "Bot choice is not executable")
puts "PASS Kościane: shared bot strategy"
