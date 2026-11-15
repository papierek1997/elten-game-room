require_relative "../../support/cat_head_tail"
require_relative "../../../games/jass_support/jass_table"
game = GameRoomGames::JassTable.new
state = {phase: :playing, current_player: "A", trump: :hearts,
         players: %w[A B C D], hands: {"A" => %w[AC 6H JH 7S], "B" => [nil]},
         trick: [["C", "8C"], ["D", "9H"]]}
raise unless game.legal_actions(GameRoomGames::Replay.new(state: state, current_player: "A"), "A").map { |a| a["card"] } == %w[AC JH]
puts "PASS Jass table card actions"

state.merge!(seats: %w[A B C D], unit_for: {"A"=>0,"B"=>1,"C"=>0,"D"=>1}, scores: [0,0],
  trick: [["A","AC"],["B","9H"],["C","JH"]], current_player: "D", play_count: 36)
game.send(:play_card, state, "D", "TC", nil, nil, [])
raise unless state[:phase] == :round_complete && state[:current_player].nil? && state[:scores] == [60,0]
state.merge!(phase: :playing, current_player: "D", play_count: 4, scores: [0,0],
  trick: [["A","AC"],["B","9H"],["C","JH"]])
game.send(:play_card, state, "D", "TC", nil, nil, [])
raise unless state[:current_player] == "C" && state[:trick].empty? && state[:scores] == [55,0]
puts "PASS Jass table trick settlement"

repo = CatHeadTailRepository.new(%w[A B C D])
state = {phase: :choosing_trump, seats: %w[A B C D], dealer: 3, current_player: "A"}
replay = GameRoomGames::Replay.new(state: state, current_player: "A")
choice = game.legal_actions(replay, "A").find { |action| action["choice"] == "pass" }
raise unless game.action_for(choice, replay, "A").first == :ok
raise if game.send(:apply_replay_event, state, cht_event(1, "B", "choose_trump", "pass"), {}, repo, [])
raise unless game.send(:apply_replay_event, state, cht_event(2, "A", "choose_trump", "pass"), {}, repo, [])
raise unless state[:current_player] == "C" && game.legal_actions(replay, "C").none? { |action| action["choice"] == "pass" }
raise unless game.send(:apply_replay_event, state, cht_event(3, "C", "choose_trump", "hearts"), {}, repo, [])
raise unless state.values_at(:phase, :trump, :current_player) == [:playing, :hearts, "A"]
puts "PASS Jass trump commands"

state.merge!(phase: :choosing_trump, current_player: "A")
state.merge!(players: %w[A B C D], units: [0, 1], hands: {"A" => %w[JH 9H]})
raise unless game.surface_spec(replay, "A").is_a?(GameSurfaces::CardTableSpec)
menu = game.custom_game_shortcuts(replay, "A").find { |shortcut| shortcut.key == "enter" }
raise unless menu.choices.map(&:value) == %w[clubs diamonds hearts spades pass]
selection = GameSurfaces::Action.new(kind: "command", name: "choose_trump", payload: {"choice" => "hearts"})
raise unless game.action_for(selection, replay, "A").first == :ok
puts "PASS Jass Polish trump selector"

state[:players] = %w[A B C D]
state[:hands] = {"A" => %w[JH 9H AH KH QH 6C 7C 8S 7D], "B" => [nil]}
context = Struct.new(:random_source).new(Random.new(13))
bot = GameRoomBots::Coordinator.new
decision = bot.decide_next(game: game, replay: replay, context: context, controlled_actors: ["A"])
raise unless decision && decision.action["choice"] == "hearts"
raise unless game.action_for(decision.action, replay, "A").first == :ok
puts "PASS Jass bot uses the shared table coordinator"

raise unless game.team_size({}, player_count: 4) == 2
state.merge!(phase: :playing, players: %w[A B C D], current_player: "D", play_count: 36,
  units: %w[team:0 team:1], unit_for: {"A"=>"team:0","B"=>"team:1","C"=>"team:0","D"=>"team:1"},
  scores: {"team:0"=>950,"team:1"=>500}, trick: [["A","AC"],["B","9H"],["C","JH"]])
history = []
game.send(:play_card, state, "D", "TC", cht_event(9, "D", "play", "TC"), repo, history)
raise unless state[:phase] == :finished && state[:winner] == "team:0" && state[:scores]["team:0"] == 1010
raise unless history.any? { |entry| entry.kind == :result }
puts "PASS Jass team result"

raise unless game.private_table_required?({})
raise unless ([:play, :controls] - game.rule_book.sections.map(&:id)).empty?
puts "PASS Jass requires a private table and supplies Polish help"
