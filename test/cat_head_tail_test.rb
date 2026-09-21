def _(text)
  text
end

module GameSurfaces
  CardChoice = Struct.new(:id, :label, :value, keyword_init: true)
  Card = Struct.new(:id, :label, :value, :choices, keyword_init: true)
  CardZoneSpec = Struct.new(:id, :header, :cards, :empty_label, :hand_order, :hand_epoch, keyword_init: true)
  CardTableSpec = Struct.new(:zones, keyword_init: true)
end

require "json"
require_relative "../lib/game_random"
require_relative "../games/base"
require_relative "../games/cat_head_tail"

class CatHeadTailRepository
  def initialize(players)
    @players = players
  end

  def players_for(_session)
    @players
  end

  def actor_of(event, _session = nil)
    event.fetch("actor")
  end

  def event_id(event)
    event.fetch("id")
  end
end

def assert(condition, message)
  raise message if !condition
end

def cht_event(id, actor, action, value = "")
  { "id" => id, "actor" => actor, "action" => action, "value" => value.to_s }
end

def cht_replay(game, players, events, score_limit: 100)
  repository = CatHeadTailRepository.new(players)
  session = { "options" => JSON.generate(game.normalize_options("score_limit" => score_limit)) }
  [game.replay(session, events, repository), repository, session]
end

game = GameRoomGames::CatHeadTail.new
players = ["Alice", "Bob"]

assert(game.id == "cat_head_tail", "the game has the wrong id")
assert(game.name == "Cat, head, tail", "the game has the wrong name")
assert(game.minimum_players == 2 && game.maximum_players == 8, "the game exposes the wrong player range")
assert(game.supports_bots?, "the game does not support shared bots")
assert(game.default_options["score_limit"] == 100, "the default score limit is wrong")
assert(game.options_error({ "score_limit" => 0 }) != nil, "a zero score limit was accepted")
assert(game.options_error({ "score_limit" => -1 }) != nil, "a negative score limit was accepted")
assert(game.options_error({ "score_limit" => 1 }) == nil, "a positive score limit was rejected")

empty, repository, = cht_replay(game, players, [])
assert(empty.current_player == "Alice", "the first seated player did not start")
assert(empty.state[:scores] == { "Alice" => 0, "Bob" => 0 }, "the initial scores are wrong")
assert(game.legal_actions(empty, "Alice").map { |action| action["action"] } == %w[roll bank], "the action order is wrong")
assert(game.legal_actions(empty, "Bob").empty?, "the inactive player received legal actions")

surface = game.surface_spec(empty, "Alice")
assert(surface.zones.first.cards.map(&:id) == %w[roll bank], "the surface does not expose Roll and Bank")
waiting_surface = game.surface_spec(empty, "Bob")
assert(waiting_surface.zones.first.cards.empty?, "the waiting player received active controls")

shortcuts = game.game_shortcuts(empty, "Alice").each_with_object({}) { |shortcut, result| result[shortcut.key] = shortcut }
assert(shortcuts["c"].message.include?("0"), "C does not announce the current turn total")
assert(shortcuts["s"].message.include?("Alice"), "S does not announce scores")
assert(shortcuts["t"] != nil, "T is missing")
assert(shortcuts["d"] == nil, "the game unexpectedly exposes a last-roll shortcut")

context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SequenceSource.new([8, 1]))
status, plan = game.action_for({ "kind" => "card", "action" => "select", "zone" => "actions", "card" => "roll" }, empty, "Alice", context: context)
assert(status == :ok && plan.events.first.value == "8|minus", "the negative cat tail was not recorded deterministically")
context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SequenceSource.new([8, 2]))
status, plan = game.action_for({ "action" => "roll" }, empty, "Alice", context: context)
assert(status == :ok && plan.events.first.value == "8|plus", "the positive cat tail was not recorded deterministically")
status, plan = game.action_for({ "kind" => "card", "action" => "select", "zone" => "actions", "card" => "bank" }, empty, "Alice")
assert(status == :ok && plan.events.first.action == "bank", "Enter on Bank did not create a bank event")

replay, = cht_replay(game, players, [
  cht_event(1, "Alice", "roll", "3"),
  cht_event(2, "Alice", "roll", "8|minus")
])
assert(replay.state[:turn_points] == -5, "the cat tail did not allow a negative turn total")
replay, = cht_replay(game, players, replay.accepted_events + [cht_event(3, "Alice", "roll", "1")])
assert(replay.current_player == "Bob" && replay.state[:turn_points] == 0, "one did not clear a negative total and end the turn")
assert(replay.history.any? { |entry| entry.kind == :lost_points && entry.text.include?("negative") }, "clearing a negative total is missing from history")

replay, = cht_replay(game, players, [cht_event(1, "Alice", "roll", "2")])
assert(replay.state[:scores]["Alice"] == 2, "two was not added directly to the bank")
assert(replay.current_player == "Alice", "two incorrectly ended the turn")

replay, = cht_replay(game, players, [cht_event(1, "Alice", "roll", "2")], score_limit: 2)
assert(!replay.state[:final_round] && replay.current_player == "Alice", "reaching the limit with two interrupted the turn")

replay, = cht_replay(game, players, [cht_event(1, "Alice", "roll", "7")])
assert(replay.state[:turn_points] == 0 && replay.current_player == "Alice", "the cat head changed the state")
assert(replay.history.any? { |entry| entry.kind == :cat_head }, "the cat head is missing from history")

replay, = cht_replay(game, players, [
  cht_event(1, "Alice", "roll", "8|plus"),
  cht_event(2, "Alice", "bank")
])
assert(replay.state[:scores]["Alice"] == 8 && replay.current_player == "Bob", "positive points were not banked")

replay, = cht_replay(game, players, [
  cht_event(1, "Alice", "roll", "8|minus"),
  cht_event(2, "Alice", "bank")
])
assert(replay.state[:scores]["Alice"] == -8 && replay.current_player == "Bob", "negative points were not banked")

replay, = cht_replay(game, players, [cht_event(1, "Alice", "bank")])
assert(replay.state[:scores]["Alice"] == 0 && replay.current_player == "Bob", "banking zero did not pass the turn")

replay, = cht_replay(game, players, [cht_event(1, "Alice", "roll", "8")])
assert(replay.accepted_events.empty?, "an eight without a cat-tail result was accepted")

replay, = cht_replay(game, players, [
  cht_event(1, "Alice", "roll", "2"),
  cht_event(2, "Alice", "roll", "2"),
  cht_event(3, "Alice", "roll", "2"),
  cht_event(4, "Alice", "roll", "8|minus"),
  cht_event(5, "Alice", "bank")
], score_limit: 5)
assert(replay.state[:scores]["Alice"] == -2, "negative banking after automatic points has the wrong score")
assert(!replay.state[:final_round] && replay.current_player == "Bob", "falling below the limit incorrectly started the final round")

replay, = cht_replay(game, players, [
  cht_event(1, "Alice", "roll", "2"),
  cht_event(2, "Alice", "bank"),
  cht_event(3, "Bob", "roll", "2"),
  cht_event(4, "Bob", "bank")
], score_limit: 2)
assert(replay.finished? && replay.draw && replay.winner == nil, "equal final scores did not produce a draw")
assert(replay.accepted_events[0..0].length == 1, "the direct bank roll was not retained")

three_players = ["Alice", "Bob", "Carol"]
replay, = cht_replay(game, three_players, [
  cht_event(1, "Alice", "roll", "5"),
  cht_event(2, "Alice", "bank"),
  cht_event(3, "Bob", "roll", "6"),
  cht_event(4, "Bob", "bank"),
  cht_event(5, "Carol", "bank")
], score_limit: 5)
assert(replay.finished? && replay.winner == "Bob", "a later player could not overtake the first player to reach the limit")
assert(replay.state[:scores]["Alice"] == 5 && replay.state[:scores]["Bob"] == 6, "the final circuit changed scores")

strategy = game.bot_strategy
state = game.send(:initial_state, players, game.normalize_options("score_limit" => 100))
state[:turn_points] = 18
bot_replay = GameRoomGames::Replay.new(players: players, current_player: "Alice", winner: nil, draw: false, state: state, accepted_events: [], history: [])
actions = game.legal_actions(bot_replay, "Alice")
choice = strategy.choose(actions: actions, actor: "Alice", random_source: GameRoomRandom::SequenceSource.new([1]), replay: bot_replay)
assert(choice["action"] == "roll", "the bot banked below 19 points")

state[:turn_points] = 19
choice = strategy.choose(actions: actions, actor: "Alice", random_source: GameRoomRandom::SequenceSource.new([100]), replay: bot_replay)
assert(choice["action"] == "roll", "the bot never risks at 19 points")
choice = strategy.choose(actions: actions, actor: "Alice", random_source: GameRoomRandom::SequenceSource.new([1]), replay: bot_replay)
assert(choice["action"] == "bank", "the bot cannot bank at 19 points")

state[:turn_points] = 24
choice = strategy.choose(actions: actions, actor: "Alice", random_source: GameRoomRandom::SequenceSource.new([100]), replay: bot_replay)
assert(choice["action"] == "roll", "the bot never risks at 24 points")
choice = strategy.choose(actions: actions, actor: "Alice", random_source: GameRoomRandom::SequenceSource.new([1]), replay: bot_replay)
assert(choice["action"] == "bank", "the bot does not usually bank at 24 points")

state[:scores]["Alice"] = 90
state[:turn_points] = 10
choice = strategy.choose(actions: actions, actor: "Alice", random_source: GameRoomRandom::SequenceSource.new([]), replay: bot_replay)
assert(choice["action"] == "bank", "the bot risked points that already reached the score limit")

state[:scores]["Bob"] = 40
state[:scores]["Alice"] = 0
state[:turn_points] = 20
state[:final_round] = true
choice = strategy.choose(actions: actions, actor: "Alice", random_source: GameRoomRandom::SequenceSource.new([]), replay: bot_replay)
assert(choice["action"] == "roll", "the bot banked a guaranteed losing final score")
state[:scores]["Alice"] = 21
choice = strategy.choose(actions: actions, actor: "Alice", random_source: GameRoomRandom::SequenceSource.new([]), replay: bot_replay)
assert(choice["action"] == "bank", "the bot did not bank a leading final score")

puts "Cat, head, tail tests passed"
