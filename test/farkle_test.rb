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
require_relative "../games/farkle"

class FarkleRepository
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

def farkle_event(id, actor, action, value = "")
  { "id" => id, "actor" => actor, "action" => action, "value" => value.to_s }
end

game = GameRoomGames::Farkle.new
repository = FarkleRepository.new(["Alice", "Bob"])
session = { "options" => JSON.generate(game.default_options) }

assert(game.minimum_players == 2 && game.maximum_players == 8, "Farkle exposes the wrong player range")
assert(game.supports_bots?, "Farkle does not support shared bots")
assert(game.default_options["score_limit"] == 1_000, "Farkle has the wrong default score limit")
assert(game.default_options["turn_minimum"] == 30, "Farkle has the wrong minimum bank score")
assert(game.default_options["entry_minimum"] == 50, "Farkle has the wrong entry score")

scores = {
  [5] => 5,
  [1] => 10,
  [2, 2, 2] => 20,
  [1, 1, 1] => 75,
  [1, 1, 1, 1] => 110,
  [6, 6, 6, 6, 6] => 420,
  [6, 6, 6, 6, 6, 6] => 750,
  [1, 2, 3, 4, 5] => 100,
  [2, 3, 4, 5, 6] => 100,
  [1, 2, 3, 4, 5, 6] => 200,
  [1, 1, 2, 2, 3, 3] => 150,
  [2, 2, 2, 3, 3, 3] => 250,
  [4, 4, 4, 4, 2, 2] => 250,
  [1, 1, 1, 5] => 80
}
scores.each do |dice, expected|
  assert(game.score_selection(dice) == expected, "Farkle scored #{dice.inspect} incorrectly")
end
assert(game.score_selection([2, 3]) == nil, "Farkle accepted non-scoring dice")

events = [
  farkle_event(1, "Alice", "roll", "1,2,3,4,5,6"),
  farkle_event(2, "Alice", "keep", "0,1,2,3,4,5")
]
hot = game.replay(session, events, repository)
assert(hot.state[:phase] == :awaiting_roll, "hot dice did not return to rolling")
assert(hot.state[:dice_to_roll] == 6, "hot dice did not restore all six dice")
assert(hot.state[:turn_points] == 200, "large straight has the wrong turn score")
assert(game.legal_actions(hot, "Alice").any? { |action| action["action"] == "bank" }, "banking was not offered")

events << farkle_event(3, "Alice", "bank")
banked = game.replay(session, events, repository)
assert(banked.state[:scores]["Alice"] == 200, "banking did not save the score")
assert(banked.current_player == "Bob", "banking did not pass the turn")

events << farkle_event(4, "Bob", "roll", "2,2,3,3,4,6")
farkled = game.replay(session, events, repository)
assert(farkled.current_player == "Alice", "a farkle did not pass the turn")
assert(farkled.state[:turn_points] == 0, "a farkle retained turn points")
assert(farkled.history.last.text.include?("Farkle"), "a farkle is missing from history")

selection = game.replay(session, [farkle_event(1, "Alice", "roll", "1,2,3,4,5,6")], repository)
status, = game.action_for(
  { "kind" => "command", "action" => "keep", "indices" => "1" },
  selection,
  "Alice"
)
assert(status == :invalid_selection, "a non-scoring selection was accepted")

context = GameRoomGames::ActionContext.new(
  random_source: GameRoomRandom::SequenceSource.new([1, 2, 3, 4, 5, 6])
)
empty = game.replay(session, [], repository)
status, plan = game.action_for({ "kind" => "dice", "action" => "roll" }, empty, "Alice", context: context)
assert(status == :ok && plan.events.first.value == "1,2,3,4,5,6", "Farkle ignored the shared random source")

shortcuts = game.game_shortcuts(hot, "Alice").each_with_object({}) { |shortcut, result| result[shortcut.key] = shortcut }
assert(shortcuts["c"].message.include?("200"), "C does not announce the current turn score")
assert(shortcuts["d"].message.include?("1, 2, 3, 4, 5, 6"), "D does not announce the last roll")
assert(shortcuts["s"].message.include?("Alice"), "S does not announce Farkle scores")
assert(shortcuts["t"] != nil, "T is missing from Farkle")

surface = game.surface_spec(selection, "Alice")
assert(surface.is_a?(GameSurfaces::CardTableSpec), "Farkle does not expose scoring combinations as a list")
combinations = surface.zones.first.cards
assert(combinations.first.label.include?("200 points"), "the best scoring combination is not first")
assert(combinations.map(&:label).uniq.length == combinations.length, "duplicate scoring combinations are visible")
status, keep_plan = game.action_for(
  {
    "kind" => "card",
    "action" => "select",
    "zone" => "combinations",
    "card" => combinations.first.value
  },
  selection,
  "Alice"
)
assert(status == :ok && keep_plan.events.first.action == "keep", "Enter on a combination did not keep it immediately")

commands = game.surface_spec(hot, "Alice")
assert(commands.is_a?(GameSurfaces::CardTableSpec), "Farkle actions are not exposed as one arrow-key list")
actions = commands.zones.first.cards
assert(actions.map(&:id) == ["roll", "bank"], "the Farkle actions have the wrong order")
status, roll_plan = game.action_for(
  { "kind" => "card", "action" => "select", "zone" => "actions", "card" => "roll" },
  hot,
  "Alice",
  context: GameRoomGames::ActionContext.new(
    random_source: GameRoomRandom::SequenceSource.new([1, 2, 3, 4, 5, 6])
  )
)
assert(status == :ok && roll_plan.events.first.action == "roll", "Enter on Roll did not roll the dice")
status, bank_plan = game.action_for(
  { "kind" => "card", "action" => "select", "zone" => "actions", "card" => "bank" },
  hot,
  "Alice"
)
assert(status == :ok && bank_plan.events.first.action == "bank", "Enter on Bank did not bank the points")

final_session = {
  "options" => JSON.generate(game.normalize_options("score_limit" => 100, "turn_minimum" => 0, "entry_minimum" => 0))
}
three = FarkleRepository.new(["Alice", "Bob", "Carol"])
round = [
  farkle_event(1, "Alice", "roll", "2,2,3,3,4,6"),
  farkle_event(2, "Bob", "roll", "1,2,3,4,5,6"),
  farkle_event(3, "Bob", "keep", "0,1,2,3,4,5"),
  farkle_event(4, "Bob", "bank")
]
pending = game.replay(final_session, round, three)
assert(!pending.finished?, "reaching the score limit ended the game immediately")
assert(pending.current_player == "Carol", "the rest of the round did not continue")
assert(pending.state[:scores]["Bob"] == 200, "the bank that reached the limit was not saved")

closed = game.replay(final_session, round + [farkle_event(5, "Carol", "roll", "2,2,3,3,4,6")], three)
assert(closed.winner == "Bob", "the game did not end once the round was complete")
assert(closed.current_player == nil, "a player took a turn after the round was complete")

assert(game.replay(final_session, round, repository).winner == "Bob", "the last player of the round did not end the game")

opening = [
  farkle_event(1, "Alice", "roll", "1,2,3,4,5,6"),
  farkle_event(2, "Alice", "keep", "0,1,2,3,4,5"),
  farkle_event(3, "Alice", "bank")
]
assert(game.replay(final_session, opening, repository).current_player == "Bob", "the opening player ended the round too early")
overtake = game.replay(final_session, opening + [
  farkle_event(4, "Bob", "roll", "1,1,1,1,1,1"),
  farkle_event(5, "Bob", "keep", "0,1,2,3,4,5"),
  farkle_event(6, "Bob", "bank")
], repository)
assert(overtake.winner == "Bob" && !overtake.draw, "the rest of the round did not let a trailing player win")
tie = game.replay(final_session, opening + [
  farkle_event(4, "Bob", "roll", "1,2,3,4,5,6"),
  farkle_event(5, "Bob", "keep", "0,1,2,3,4,5"),
  farkle_event(6, "Bob", "bank")
], repository)
assert(tie.draw && tie.winner == nil, "equal totals did not end the game in a draw")

puts "Farkle model tests passed"
