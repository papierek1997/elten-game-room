def _(text)
  text
end

module GameSurfaces
  CardChoice = Struct.new(:id, :label, :value, keyword_init: true)
  Card = Struct.new(:id, :label, :value, :choices, :shift_choice, :choice_header, :sort_keys, keyword_init: true)
  CardZoneSpec = Struct.new(:id, :header, :cards, :empty_label, :hand_order, :hand_epoch, keyword_init: true)
  CardTableSpec = Struct.new(:zones, keyword_init: true)
  Command = Struct.new(:id, :label, :enabled, :payload, keyword_init: true)
  CommandPanelSpec = Struct.new(:commands, keyword_init: true)
  SurfacePart = Struct.new(:id, :surface, keyword_init: true)
  CompositeSpec = Struct.new(:parts, keyword_init: true)
end

require "json"
require_relative "../lib/game_random"
require_relative "../games/three_five_eight"

class ThreeFiveEightRepository
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

def game_event(id, actor, action, value = "")
  { "id" => id, "actor" => actor, "action" => action, "value" => value.to_s }
end

players = %w[Alice Bob Carol]
game = GameRoomGames::ThreeFiveEight.new
repository = ThreeFiveEightRepository.new(players)
session = { "options" => JSON.generate(game.default_options) }

assert(game.minimum_players == 3 && game.maximum_players == 3, "3-5-8 must require exactly three players")
assert(game.supports_bots?, "3-5-8 does not expose bot support")
assert(game.name == "3-5-8", "the game has the wrong name")
exchange_option = game.option_definitions.find { |definition| definition.key == "card_exchange" }
assert(exchange_option != nil && exchange_option.kind == :boolean && exchange_option.default == true, "card exchange is not an enabled-by-default table option")

bot_players = ["Alice", "bot:1:1:pl20", "Carol"]
bot_repository = ThreeFiveEightRepository.new(bot_players)
bot_replay = game.replay(session, [game_event(1, "Alice", "deal", "1|0|000102030405060708090a0b0c0d0e0f")], bot_repository)
bot_context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SequenceSource.new([1]))
bot_decision = GameRoomBots::Coordinator.new.decide_next(game: game, replay: bot_replay, context: bot_context)
assert(bot_decision != nil && bot_decision.actor == "bot:1:1:pl20", "the chooser bot did not make a decision")
bot_status, = game.action_for(bot_decision.action, bot_replay, bot_decision.actor, context: bot_context)
assert(bot_status == :ok, "the bot selected an action rejected by the normal game path")

events = [game_event(1, "Alice", "deal", "1|0|000102030405060708090a0b0c0d0e0f")]
replay = game.replay(session, events, repository)
assert(replay.state[:phase] == :choosing_contract, "the first deal did not begin contract selection")
assert(replay.current_player == "Bob", "the player to the dealer's left is not choosing")
assert(replay.state[:hands].values.all? { |hand| hand.length == 6 }, "players can see more than the first six cards before selection")
assert(replay.state[:complete_hands].values.all? { |hand| hand.length == 16 }, "the deterministic deal did not prepare 16-card hands")
assert(replay.state[:kitty].length == 4, "the deal did not create a four-card kitty")
assert((replay.state[:complete_hands].values.flatten + replay.state[:kitty]).uniq.length == 52, "the deal contains duplicate or missing cards")
assert(game.legal_actions(replay, "Bob").map { |action| action["contract"] }.sort == %w[C D H MISERE NT S].sort, "the chooser does not have all six contracts")

surface = game.surface_spec(replay, "Bob")
assert(surface.is_a?(GameSurfaces::CompositeSpec), "contract selection does not show both cards and commands")
commands = surface.parts.find { |part| part.id == "commands" }.surface.commands
assert(commands.length == 6 && commands.map(&:id).uniq.length == 6, "contract commands are incomplete or have duplicate IDs")

events << game_event(2, "Bob", "choose_contract", "H")
replay = game.replay(session, events, repository)
assert(replay.state[:phase] == :discarding, "the first deal incorrectly entered card exchange")
assert(replay.state[:hands]["Bob"].length == 20, "the chooser did not receive the kitty")
assert(replay.history.any? { |entry| entry.kind == :kitty && entry.text.include?("The kitty is") }, "the revealed kitty is missing from history")

4.times do
  actor = replay.current_player
  action = game.legal_actions(replay, actor).first
  status, plan = game.action_for(action, replay, actor)
  assert(status == :ok, "a legal kitty discard was rejected")
  command = plan.events.first
  events << game_event(events.length + 1, actor, command.action, command.value)
  replay = game.replay(session, events, repository)
end
assert(replay.state[:phase] == :playing, "four discards did not start play")
assert(replay.state[:hands].values.all? { |hand| hand.length == 16 }, "hands do not contain 16 cards after the kitty")

navigation = game.playable_card_navigation(replay, replay.current_player)
assert(navigation[:hand_id] == "hand" && !navigation[:card_actions].empty?, "playable-card navigation is unavailable")
shortcut_keys = game.game_shortcuts(replay, replay.current_player).map { |shortcut| [shortcut.key, shortcut.modifiers] }
assert(shortcut_keys.include?(["z", []]) && shortcut_keys.include?(["z", [:shift]]), "Z or Shift+Z is missing")
assert(shortcut_keys.include?(["c", [:shift]]) && shortcut_keys.include?(["h", [:shift]]) && shortcut_keys.include?(["m", [:shift]]), "shared hand sorting shortcuts are missing")

until replay.state[:phase] == :round_complete
  actor = replay.current_player
  action = game.legal_actions(replay, actor).first
  assert(action != nil, "a player had no legal action during play")
  status, plan = game.action_for(action, replay, actor)
  assert(status == :ok, "a legal card play was rejected")
  command = plan.events.first
  events << game_event(events.length + 1, actor, command.action, command.value)
  replay = game.replay(session, events, repository)
  assert(events.length < 80, "the first deal did not terminate")
end
assert(replay.state[:tricks].values.sum == 16, "the deal did not contain 16 tricks")
assert(replay.state[:previous_deltas].values.sum == 0, "ordinary deal changes do not sum to zero")

follow_state = game.send(:initial_state, players, game.default_options)
follow_state[:phase] = :playing
follow_state[:current_player] = "Bob"
follow_state[:contract] = "H"
follow_state[:hands]["Bob"] = %w[5C KC 2H AH]
follow_state[:current_trick] = [{ player: "Alice", card: "TC" }]
assert(game.send(:legal_cards, follow_state, "Bob").sort == %w[5C KC].sort, "a player was incorrectly forced to beat in the led suit")
follow_state[:hands]["Bob"] = %w[5D 2H AH]
assert(game.send(:legal_cards, follow_state, "Bob").sort == %w[5D 2H AH].sort, "a void player was incorrectly forced to trump")
follow_state[:current_trick] << { player: "Carol", card: "TH" }
assert(game.send(:legal_cards, follow_state, "Bob").sort == %w[5D 2H AH].sort, "a player was incorrectly forced to overtrump")

exchange_state = game.send(:initial_state, players, game.default_options)
exchange_state.update(
  phase: :exchanging, current_player: "Alice", chooser: "Alice", contract: "H", round: 2, kitty: [],
  hands: { "Alice" => %w[2C 2H], "Bob" => %w[AC KH 3D], "Carol" => %w[4S] },
  exchange_queue: ["Alice"], exchange_limits: { "Alice" => 2 }, exchange_used: { "Alice" => 0 },
  exchange_targets: { "Bob" => 2 }
)
exchange_history = []
assert(game.send(:apply_exchange, exchange_state, game_event(500, "Alice", "exchange", "Bob|2C"), "Alice", repository, exchange_history), "a legal non-trump exchange was rejected")
assert(exchange_state[:hands]["Alice"].include?("AC") && exchange_state[:hands]["Bob"].include?("2C"), "a non-trump exchange did not return the highest matching suit")
assert(game.send(:apply_exchange, exchange_state, game_event(501, "Alice", "exchange", "Bob|2H"), "Alice", repository, exchange_history), "a legal trump exchange was rejected")
assert(exchange_state[:phase] == :exchange_return && exchange_state[:current_player] == "Bob", "a trump exchange did not ask the recipient for a return card")
return_cards = game.send(:exchange_return_cards, exchange_state, "Bob")
assert(return_cards.include?("3D") && return_cards.include?("KH") && !return_cards.include?("2H"), "the trump return choices are incorrect")
assert(game.send(:apply_exchange_return, exchange_state, game_event(502, "Bob", "return", "3D"), "Bob", repository, exchange_history), "the chosen trump-exchange return was rejected")
assert(exchange_state[:hands]["Alice"].include?("3D") && exchange_state[:hands]["Bob"].include?("2H"), "the trump exchange did not transfer both cards")

no_exchange_state = game.send(:initial_state, players, game.normalize_options("card_exchange" => false))
no_exchange_state.update(
  round: 2, dealer_index: 0, chooser: "Bob", phase: :choosing_contract, current_player: "Bob",
  complete_hands: players.to_h { |player| [player, GameRoomGames::ThreeFiveEight::SUITS.product(GameRoomGames::ThreeFiveEight::RANKS).first(16).map { |suit, rank| "#{rank}#{suit}" }] },
  kitty: %w[2C 3C 4C 5C], previous_deltas: { "Alice" => 1, "Bob" => -1, "Carol" => 0 }
)
assert(game.send(:apply_choose_contract, no_exchange_state, game_event(503, "Bob", "choose_contract", "H"), "Bob", repository, []), "a contract was rejected with exchange disabled")
assert(no_exchange_state[:phase] == :discarding, "exchange-disabled play did not go directly to the kitty")

misere_state = game.send(:initial_state, players, game.default_options)
misere_state[:round] = 18
misere_state[:phase] = :playing
misere_state[:dealer_index] = 0
misere_state[:chooser] = "Bob"
misere_state[:contract] = "MISERE"
misere_state[:targets] = game.send(:misere_targets, misere_state)
misere_state[:tricks] = { "Alice" => 6, "Bob" => 4, "Carol" => 6 }
misere_state[:hands] = players.to_h { |player| [player, []] }
game.send(:complete_round, misere_state, 900, [])
assert(misere_state[:previous_deltas] == { "Alice" => 2, "Bob" => -1, "Carol" => -1 }, "misere scoring is incorrect")

dealer_misere_state = game.send(:initial_state, players, game.default_options)
dealer_misere_state.update(
  round: 3, phase: :playing, dealer_index: 0, chooser: "Bob", contract: "MISERE",
  tricks: { "Alice" => 3, "Bob" => 8, "Carol" => 5 },
  hands: players.to_h { |player| [player, []] }
)
dealer_misere_state[:targets] = game.send(:misere_targets, dealer_misere_state)
dealer_misere_history = []
game.send(:complete_round, dealer_misere_state, 901, dealer_misere_history)
assert(dealer_misere_state[:targets]["Alice"] == 8, "the misere dealer did not receive the 8-trick limit")
assert(dealer_misere_state[:previous_deltas]["Alice"] == 5, "a misere dealer with 3 of 8 tricks did not gain 5 points")
assert(dealer_misere_history.first.text.include?("points this deal +5, total score 5"), "the round result uses unclear or incorrect score labels")

# Play a complete deterministic 18-deal game. We deliberately finish every
# exchange early so the loop covers the optional path without making strategy
# choices part of this model test.
events = []
event_id = 1
replay = game.replay(session, events, repository)
while !replay.finished?
  state = replay.state
  actor = replay.current_player
  action = case state[:phase]
  when :awaiting_deal, :round_complete
    dealer = state[:dealer_index] == nil ? 0 : (state[:dealer_index] + 1) % 3
    round = state[:round] + 1
    seed = round.to_s(16).rjust(32, "0")
    { "kind" => "command", "action" => "deal", "round" => round, "dealer" => dealer, "seed" => seed }
  when :choosing_contract
    game.legal_actions(replay, actor).first
  when :exchanging
    { "kind" => "command", "action" => "stop_exchange" }
  else
    game.legal_actions(replay, actor).first
  end
  assert(action != nil, "the 18-deal simulation found no legal action in #{state[:phase]}")
  status, plan = game.action_for(action, replay, actor || players.first)
  assert(status == :ok, "the 18-deal simulation rejected a legal action in #{state[:phase]}: #{status}")
  plan.events.each do |command|
    events << game_event(event_id, actor || players.first, command.action, command.value)
    event_id += 1
  end
  replay = game.replay(session, events, repository)
  assert(event_id < 2_000, "the 18-deal game did not terminate")
end
assert(replay.state[:round] == 18, "the game ended before the eighteenth deal")
assert(replay.state[:used_contracts].values.all? { |contracts| contracts.sort == %w[C D H MISERE NT S].sort }, "not every player used every contract once")
assert(replay.state[:scores].values.sum == 0, "the final scores do not sum to zero")
assert(replay.state[:winners].length >= 1, "the completed game has no winner or tied winners")

puts "3-5-8 model tests passed"
