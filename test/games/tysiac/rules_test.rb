require_relative "../../../lib/game_surfaces/specifications"
def _(text)
  text
end


require "json"
require_relative "../../../games/tysiac"
require_relative "../../../lib/game_simulation"

class TysiacRepository
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

def event(id, actor, action, value = "")
  { "id" => id, "actor" => actor, "action" => action, "value" => value.to_s }
end

players = %w[Alice Bob Carol]
game = GameRoomGames::Tysiac.new
repository = TysiacRepository.new(players)
session = { "options" => JSON.generate(game.default_options) }

assert(game.name == "1000 card game", "English game name should be 1000 card game")
assert(game.option_definitions.first.label == "1000 card game variant", "English variant label should be 1000 card game variant")
assert(game.options_error({ "variant" => "two_players" }, player_count: 3).include?("1000 card game"), "English validation message should mention 1000 card game")

assert(game.minimum_players == 2 && game.maximum_players == 4, "Tysiac player range changed")
assert(game.default_options["variant"] == "three_players", "legacy three-player default changed")
assert(game.supports_bots?, "Tysiac does not expose computer players")
assert(game.default_options["score_limit"] == 1_000, "Tysiac has the wrong target score")

events = [event(1, "Alice", "deal", "1|0|000102030405060708090a0b0c0d0e0f")]
replay = game.replay(session, events, repository)
assert(replay.state[:phase] == :bidding, "the deal did not start the auction")
assert(replay.current_player == "Bob", "the player after the dealer did not open the auction")
assert(replay.state[:hands].values.all? { |hand| hand.length == 7 }, "the deal did not give seven cards to every player")
assert(replay.state[:talon].length == 3, "the talon does not contain three cards")
assert(replay.state[:hands].values.flatten.uniq.length + replay.state[:talon].uniq.length == 24, "the deal duplicated cards")

bid_shortcut = game.game_shortcuts(replay, "Bob").find { |shortcut| shortcut.key == "b" }
assert(bid_shortcut.kind == :announcement, "B should read auction information during bidding")
bid_surface = game.surface_spec(replay, "Bob")
assert(bid_surface.is_a?(GameSurfaces::CardTableSpec), "the auction is still a separate field under Tab")
bid_hand = bid_surface.zones.find { |zone| zone.id == "hand" }
bid_choices = bid_hand.cards.first.choices
assert(bid_choices.first.value == 100, "the opening bid list does not start at 100")
assert(!bid_choices.any? { |choice| choice.value == "pass" }, "the opening bidder can pass before bidding")
assert(bid_choices.map(&:value).grep(Integer).each_cons(2).all? { |a, b| b - a == 5 }, "bids do not advance in steps of five")
status, bid_plan = game.action_for(
  { "kind" => "card", "action" => "select", "zone" => "hand", "card" => 100 },
  replay,
  "Bob"
)
assert(status == :ok && bid_plan.events.first.action == "bid", "a bid selected from the hand was rejected")

events << event(2, "Bob", "bid", 100)
events << event(3, "Carol", "bid", "pass")
events << event(4, "Alice", "bid", "pass")
replay = game.replay(session, events, repository)
assert(replay.state[:phase] == :passing, "two passes did not reveal the talon")
assert(replay.state[:taker] == "Bob", "the final bidder did not become the taker")
assert(replay.state[:hands]["Bob"].length == 10, "the talon was not added to the taker's hand")
assert(replay.state[:talon_visible], "the revealed talon is hidden")
auction_result = replay.history.find { |entry| entry.kind == :auction_won }
talon_result = replay.history.find { |entry| entry.kind == :talon }
assert(auction_result != nil && talon_result != nil, "the auction result and talon are not separate history items")
assert(!auction_result.text.include?("talon"), "the auction result still includes the talon")
assert(talon_result.text.start_with?("The talon is"), "the talon has no separate history announcement")
auction_descriptions = game.describe_event(events.last, repository, replay, "Bob")
assert(auction_descriptions.is_a?(Array), "Tysiac event speech is not split into separate items")
assert(auction_descriptions.include?(auction_result.text), "the auction result is missing from event speech")
assert(auction_descriptions.include?(talon_result.text), "the talon is missing from event speech")
assert(
  game.turn_announcement(replay, "Bob") == "Choose a card to give to Alice.",
  "the taker is not told who should receive the first card"
)
passing_surface = game.surface_spec(replay, "Bob")
passing_cards = if passing_surface.is_a?(GameSurfaces::CompositeSpec)
  passing_surface.parts.find { |part| part.id == "cards" }.surface
else
  passing_surface
end
hand_zone = passing_cards.zones.find { |zone| zone.id == "hand" }
assert(hand_zone.cards.length == 10, "the revealed talon is not shown inside the taker's hand")
assert(!passing_cards.zones.any? { |zone| zone.id == "talon" }, "the revealed talon is duplicated in a separate field")
assert(passing_cards.zones.map(&:id) == ["hand"], "cards on the table still occupy a separate Tab field")
table_card_shortcuts = game.game_shortcuts(replay, "Bob").select { |shortcut| shortcut.key == "c" }
table_cards_announcement = table_card_shortcuts.find { |shortcut| shortcut.modifiers.empty? }
table_cards_list = table_card_shortcuts.find { |shortcut| shortcut.modifiers == [:control] }
assert(table_cards_announcement&.kind == :announcement, "plain C no longer reads the cards on the table")
assert(table_cards_list&.kind == :browse, "Ctrl+C does not open the cards-on-table list")
assert(table_cards_list.choices.map(&:label) == ["No cards have been played in this trick"], "the empty Ctrl+C card list is incorrect")
playroom_hand = %w[AC TC 9H AS 9S TD 9D 9C TH AH].sort_by do |card|
  game.send(:card_sort_key, card)
end
assert(
  playroom_hand == %w[9H TH AH 9S AS 9D TD 9C TC AC],
  "Tysiac does not use the shared Playroom suit and rank order"
)
passing_actions = game.legal_actions(replay, "Bob")
assert(passing_actions.any? { |action| action["action"] == "surrender" }, "a bot cannot consider surrendering")

first_card = replay.state[:hands]["Bob"].first
events << event(5, "Bob", "pass_card", "Alice|#{first_card}")
replay = game.replay(session, events, repository)
first_pass_descriptions = game.describe_event(events.last, repository, replay, "Bob")
assert(
  first_pass_descriptions.last == "Choose a card to give to Carol.",
  "the taker is not told who should receive the second card"
)
first_card_label = game.send(:card_label, first_card)
assert(first_pass_descriptions.first.include?(first_card_label), "the taker cannot see the card they gave away")
alice_first_pass = game.describe_event(events.last, repository, replay, "Alice")
carol_first_pass = game.describe_event(events.last, repository, replay, "Carol")
assert(alice_first_pass.first.include?(first_card_label), "the recipient cannot see the card they received")
assert(!carol_first_pass.first.include?(first_card_label), "an unrelated player can see somebody else's passed card")
second_card = replay.state[:hands]["Bob"].first
events << event(6, "Bob", "pass_card", "Carol|#{second_card}")
replay = game.replay(session, events, repository)
assert(replay.state[:phase] == :contract, "passing two cards did not reach the final contract")
assert(replay.state[:hands].values.all? { |hand| hand.length == 8 }, "players do not have eight cards after passing")
second_card_label = game.send(:card_label, second_card)
pass_history = replay.history.select { |entry| entry.kind == :pass_card }.map(&:text).join(" ")
assert(!pass_history.include?(first_card_label) && !pass_history.include?(second_card_label), "public history exposes passed cards")
bob_history = game.history_entries_for_display(replay, "Bob").select { |entry| entry.kind == :pass_card }.map(&:text).join(" ")
alice_history = game.history_entries_for_display(replay, "Alice").select { |entry| entry.kind == :pass_card }.map(&:text).join(" ")
carol_history = game.history_entries_for_display(replay, "Carol").select { |entry| entry.kind == :pass_card }.map(&:text).join(" ")
assert(bob_history.include?(first_card_label) && bob_history.include?(second_card_label), "the taker lost their passed-card history")
assert(alice_history.include?(first_card_label) && !alice_history.include?(second_card_label), "Alice can see the wrong passed card")
assert(carol_history.include?(second_card_label) && !carol_history.include?(first_card_label), "Carol can see the wrong passed card")
observation = game.bot_observation(replay, "Alice")
assert(!observation.key?("hands"), "a Tysiac bot observation exposed private opponent hands")

contract_shortcut = game.game_shortcuts(replay, "Bob").find { |shortcut| shortcut.key == "b" }
assert(contract_shortcut.kind == :choice, "B does not open the final-contract list")
assert(contract_shortcut.choices.first.value == 100, "the taker cannot keep the current contract")
first_lead = replay.state[:hands]["Bob"].first
status, first_lead_plan = game.action_for(
  { "kind" => "card", "action" => "select", "card" => first_lead },
  replay,
  "Bob"
)
assert(status == :ok && first_lead_plan.events.map(&:action) == %w[contract play], "the first played card did not accept the current contract")
events << event(7, "Bob", "contract", 100)
replay = game.replay(session, events, repository)
assert(replay.state[:phase] == :playing && replay.current_player == "Bob", "the taker did not lead the first trick")

next_event_id = 8
until replay.state[:phase] == :round_complete
  actor = replay.current_player
  action = game.legal_actions(replay, actor).first
  assert(action != nil, "a player had no legal card")
  mode, card = action.fetch("card").split("|", 2)
  events << event(next_event_id, actor, "play", "#{mode}|#{card}")
  next_event_id += 1
  replay = game.replay(session, events, repository)
end
assert(replay.state[:hands].values.all?(&:empty?), "cards remained after eight tricks")
assert(replay.state[:round_points].values.sum == 120, "a deal without marriages did not contain 120 points")
assert(replay.history.any? { |entry| entry.kind == :round_result }, "the round result is missing from history")
round_summaries = replay.history.select { |entry| entry.kind == :round_result }.map(&:text)
assert(round_summaries.length >= players.length, "round summaries are not separate history items")
assert(round_summaries.count { |text| text.include?("collected") } == players.length, "round summaries do not contain raw points")
assert(round_summaries.count { |text| text.include?("awarded") || text.include?("lost") } == players.length, "round summaries do not contain awarded score changes")
assert(game.send(:round_score_text, "Bob", 63, 60) == "Bob, collected 63, awarded 60.", "positive round scoring is not concise")
assert(game.send(:round_score_text, "Bob", 63, -100) == "Bob, collected 63, lost 100.", "negative round scoring is not concise")

auction_state = game.send(:initial_state, players, game.default_options)
auction_state[:phase] = :bidding
auction_state[:current_player] = "Bob"
auction_state[:first_bidder] = "Bob"
auction_state[:hands]["Bob"] = %w[9H JH QD KC AS 9C TD]
assert(game.send(:legal_bid_values, auction_state, "Bob").last == 120, "a hand without a marriage can bid above 120")
auction_state[:hands]["Bob"] = %w[KH QH 9D JC AS 9C TD]
assert(game.send(:legal_bid_values, auction_state, "Bob").last == 220, "the maximum bid does not equal 120 plus held marriages")

follow_state = game.send(:initial_state, players, game.default_options)
follow_state[:phase] = :playing
follow_state[:current_player] = "Bob"
follow_state[:trump] = "H"
follow_state[:current_trick] = [{ player: "Alice", card: "9C" }]
follow_state[:hands]["Bob"] = %w[9D 9H]
assert(game.send(:legal_cards, follow_state, "Bob") == ["9H"], "a void player was not required to play trump")
follow_state[:hands]["Bob"] = %w[JC 9H]
assert(game.send(:legal_cards, follow_state, "Bob") == ["JC"], "following suit did not take priority over trump")

surrender_events = [
  event(101, "Alice", "deal", "1|0|000102030405060708090a0b0c0d0e0f"),
  event(102, "Bob", "bid", 100),
  event(103, "Carol", "bid", "pass"),
  event(104, "Alice", "bid", "pass"),
  event(105, "Bob", "surrender")
]
surrendered = game.replay(session, surrender_events, repository)
assert(surrendered.state[:phase] == :round_complete, "surrender did not end the deal")
assert(surrendered.state[:scores]["Bob"] == 0, "the first surrender penalized the taker")
assert(surrendered.state[:scores]["Alice"] == 60 && surrendered.state[:scores]["Carol"] == 60, "defenders received the wrong surrender award")
assert(surrendered.history.any? { |entry| entry.kind == :round_result && entry.text.include?("Bob: first surrender.") }, "the first surrender was not announced")

barrel_state = game.send(:initial_state, players, game.default_options)
barrel_state[:phase] = :playing
barrel_state[:taker] = "Bob"
barrel_state[:contract] = 120
barrel_state[:scores]["Bob"] = 880
barrel_state[:barrels]["Bob"] = { active: true, deals_left: 3 }
barrel_state[:round_points]["Bob"] = 120
game.send(:complete_round, barrel_state, 150, [], surrendered: false)
assert(barrel_state[:winner] == "Bob" && barrel_state[:scores]["Bob"] == 1_000, "a successful barrel contract did not win the game")

barrel_defender = game.send(:initial_state, players, game.default_options)
barrel_defender[:phase] = :playing
barrel_defender[:taker] = "Alice"
barrel_defender[:contract] = 100
barrel_defender[:scores]["Bob"] = 880
barrel_defender[:barrels]["Bob"] = { active: true, deals_left: 3 }
barrel_defender[:round_points] = { "Alice" => 100, "Bob" => 20, "Carol" => 0 }
game.send(:complete_round, barrel_defender, 151, [], surrendered: false)
assert(barrel_defender[:scores]["Bob"] == 880, "defender points were added on the barrel")
assert(barrel_defender[:barrels]["Bob"][:deals_left] == 2, "a barrel deal was not counted")

barrel_surrender = game.send(:initial_state, players, game.default_options)
barrel_surrender[:phase] = :passing
barrel_surrender[:current_player] = "Alice"
barrel_surrender[:taker] = "Alice"
barrel_surrender[:contract] = 100
barrel_surrender[:scores]["Bob"] = 880
barrel_surrender[:barrels]["Bob"] = { active: true, deals_left: 2 }
game.send(:complete_round, barrel_surrender, 1511, [], surrendered: true)
assert(barrel_surrender[:barrels]["Bob"][:deals_left] == 2, "another player's surrender consumed a barrel deal")

barrel_taker = game.send(:initial_state, players, game.default_options)
barrel_taker[:phase] = :passing
barrel_taker[:current_player] = "Bob"
barrel_taker[:taker] = "Bob"
barrel_taker[:barrels]["Bob"] = { active: true, deals_left: 2 }
assert(!game.send(:surrender_available?, barrel_taker, "Bob"), "a player on the barrel may surrender")

zero_state = game.send(:initial_state, players, game.default_options)
zero_state[:phase] = :playing
zero_state[:taker] = "Alice"
zero_state[:contract] = 100
zero_state[:round_points] = { "Alice" => 100, "Bob" => 20, "Carol" => 0 }
zero_state[:zero_rounds]["Carol"] = 2
zero_history = []
game.send(:complete_round, zero_state, 152, zero_history, surrendered: false)
assert(zero_state[:scores]["Carol"] == -120 && zero_state[:zero_rounds]["Carol"] == 0, "the third exact zero did not cost 120")
assert(zero_history.any? { |entry| entry.text.include?("Carol: third zero.") }, "the third exact zero was not announced")

third_surrender = game.send(:initial_state, players, game.default_options)
third_surrender[:phase] = :passing
third_surrender[:taker] = "Bob"
third_surrender[:contract] = 125
third_surrender[:surrender_uses]["Bob"] = 2
third_surrender_history = []
game.send(:complete_round, third_surrender, 153, third_surrender_history, surrendered: true)
assert(third_surrender[:scores]["Bob"] == -120, "the third surrender did not cost 120")
assert(third_surrender[:scores]["Alice"] == 65 && third_surrender[:scores]["Carol"] == 65, "half-contract surrender points were not rounded upward")
assert(third_surrender_history.any? { |entry| entry.text.include?("Bob: third surrender.") }, "the third surrender was not announced")

counter_state = game.send(:initial_state, players, game.default_options)
counter_state[:scores]["Bob"] = 245
counter_state[:zero_rounds]["Bob"] = 2
counter_state[:surrender_uses]["Bob"] = 1
counter_text = game.send(:scores_text, counter_state)
statistics_text = game.send(:statistics_text, counter_state)
assert(counter_text.include?("Bob: 245"), "S does not announce the score")
assert(statistics_text.include?("Bob: zeros 2/3, surrenders 1/3"), "Shift+S does not announce zero and surrender counters")

state = game.send(:initial_state, players, game.default_options)
state[:phase] = :playing
state[:current_player] = "Bob"
state[:taker] = "Bob"
state[:contract] = 100
state[:trick_number] = 1
state[:hands]["Bob"] = %w[KH QH]
assert(game.send(:marriage_available?, state, "Bob", "KH"), "a valid marriage was not available")
marriage_card = game.send(:surface_card, state, "Bob", "KH")
assert(marriage_card.shift_choice == "marriage", "Shift+Enter does not select the marriage play")
history = []
applied = game.send(:apply_play, state, event(200, "Bob", "play", "marriage|KH"), "Bob", repository, history)
assert(applied, "a valid marriage was rejected")
assert(state[:trump] == "H" && state[:round_points]["Bob"] == 100, "the hearts marriage did not establish trump and score 100")

unavailable_state = game.send(:initial_state, players, game.default_options)
unavailable_state[:phase] = :playing
unavailable_state[:current_player] = "Bob"
unavailable_state[:taker] = "Bob"
unavailable_state[:contract] = 100
unavailable_state[:trick_number] = 1
unavailable_state[:hands]["Bob"] = %w[KH 9H]
unavailable_replay = GameRoomGames::Replay.new(
  board: nil,
  players: players,
  current_player: "Bob",
  winner: nil,
  draw: false,
  accepted_events: [],
  history: [],
  state: unavailable_state
)
unavailable_card = game.send(:surface_card, unavailable_state, "Bob", "KH")
assert(unavailable_card.shift_choice == "marriage", "an unavailable marriage did not retain its Shift action")
unavailable_status, = game.action_for(
  { "kind" => "card", "action" => "select", "card" => "normal|KH", "choice_id" => "marriage" },
  unavailable_replay,
  "Bob"
)
assert(unavailable_status == :marriage_not_available, "Shift+Enter played a card when marriage was unavailable")

planning_state = game.send(:initial_state, players, game.default_options)
planning_state[:phase] = :playing
planning_state[:current_player] = "Bob"
planning_state[:taker] = "Bob"
planning_state[:contract] = 100
planning_state[:trick_number] = 1
planning_state[:hands]["Bob"] = %w[KH QH]
planning_replay = GameRoomGames::Replay.new(
  board: nil,
  players: players,
  current_player: "Bob",
  winner: nil,
  draw: false,
  accepted_events: [],
  history: [],
  state: planning_state
)
normal_marriage_card = { "kind" => "card", "action" => "select", "card" => "normal|QH" }
declared_marriage_card = { "kind" => "card", "action" => "select", "card" => "marriage|QH" }
assert(
  game.bot_action_score(planning_replay, "Bob", declared_marriage_card) >
    game.bot_action_score(planning_replay, "Bob", normal_marriage_card),
  "the bot does not prefer declaring an available marriage"
)

def bidding_replay(game, players, hand)
  state = game.send(:initial_state, players, game.default_options)
  remaining = game.send(:deck) - hand
  state[:phase] = :bidding
  state[:current_player] = "Bob"
  state[:first_bidder] = "Alice"
  state[:current_bid] = 100
  state[:current_bidder] = "Alice"
  state[:bids]["Alice"] = 100
  state[:hands]["Bob"] = hand
  state[:hands]["Alice"] = remaining.shift(7)
  state[:hands]["Carol"] = remaining.shift(7)
  GameRoomGames::Replay.new(
    board: nil,
    players: players,
    current_player: "Bob",
    winner: nil,
    draw: false,
    accepted_events: [
      event(300, "Alice", "deal", "1|2|000102030405060708090a0b0c0d0e0f"),
      event(301, "Alice", "bid", 100)
    ],
    history: [],
    state: state
  )
end

strong_bidding = bidding_replay(game, players, %w[AH TH KH QH AD TD 9C])
strong_actions = game.legal_actions(strong_bidding, "Bob")
strong_choice = game.bot_strategy.choose(
  actions: strong_actions,
  actor: "Bob",
  random_source: GameRoomRandom::SeededSource.new(44),
  game: game,
  replay: strong_bidding
)
assert(strong_choice["bid"].to_i > 100, "the simulated auction did not raise with a strong hand")

weak_bidding = bidding_replay(game, players, %w[9H JH QD KS 9S JD QC])
weak_actions = game.legal_actions(weak_bidding, "Bob")
weak_choice = game.bot_strategy.choose(
  actions: weak_actions,
  actor: "Bob",
  random_source: GameRoomRandom::SeededSource.new(44),
  game: game,
  replay: weak_bidding
)
assert(weak_choice["bid"].to_s == "pass", "the simulated auction overbid a weak hand")

hidden_swap = bidding_replay(game, players, %w[AH TH KH QH AD TD 9C])
hidden_swap.state[:hands]["Alice"], hidden_swap.state[:hands]["Carol"] =
  hidden_swap.state[:hands]["Carol"], hidden_swap.state[:hands]["Alice"]
hidden_choice = game.bot_strategy.choose(
  actions: game.legal_actions(hidden_swap, "Bob"),
  actor: "Bob",
  random_source: GameRoomRandom::SeededSource.new(44),
  game: game,
  replay: hidden_swap
)
assert(hidden_choice == strong_choice, "the auction decision depended on hidden opponent cards")

barrel_bidding = bidding_replay(game, players, %w[AH TH KH 9H AD JD 9C])
barrel_bidding.state[:barrels]["Alice"] = { active: true, deals_left: 1 }
barrel_bidding.state[:scores]["Alice"] = 880
barrel_bidding.state[:passed]["Carol"] = true
barrel_planner = TysiacPlanning::Planner.new(
  game,
  barrel_bidding,
  "Bob",
  GameRoomRandom::SeededSource.new(4_400)
)
denial_action = game.legal_actions(barrel_bidding, "Bob").find { |action| action["bid"].to_i == 105 }
denial_statistics = [[denial_action, 105, 0.40, -8.0]]
assert(
  barrel_planner.send(
    :select_barrel_denial,
    denial_statistics,
    threatened: "Alice",
    threat_probability: 0.60,
    blocker: nil,
    blocker_capacity: 0.0
  ) == denial_action,
  "the last available bidder did not make a controlled final-barrel denial bid"
)

barrel_bidding.state[:passed]["Carol"] = false
assert(
  barrel_planner.send(
    :select_barrel_denial,
    denial_statistics,
    threatened: "Alice",
    threat_probability: 0.60,
    blocker: "Carol",
    blocker_capacity: 0.80
  ) == nil,
  "the bot took needless auction risk despite a capable active player acting next"
)

barrel_bidding.state[:barrels]["Carol"] = { active: true, deals_left: 2 }
assert(
  barrel_planner.send(
    :select_barrel_denial,
    denial_statistics,
    threatened: "Alice",
    threat_probability: 0.60,
    blocker: "Carol",
    blocker_capacity: 0.60
  ) == nil,
  "the bot did not delegate denial to another capable barrel player"
)

barrel_bidding.state[:barrels]["Carol"] = { active: false, deals_left: 0 }
barrel_bidding.state[:passed]["Carol"] = true
barrel_bidding.state[:surrender_uses]["Bob"] = 2
third_surrender_planner = TysiacPlanning::Planner.new(
  game,
  barrel_bidding,
  "Bob",
  GameRoomRandom::SeededSource.new(4_401)
)
assert(
  third_surrender_planner.send(
    :select_barrel_denial,
    denial_statistics,
    threatened: "Alice",
    threat_probability: 0.60,
    blocker: nil,
    blocker_capacity: 0.0
  ) == nil,
  "the bot ignored the imminent 120-point cost of a third surrender"
)

barrel_bidding.state[:surrender_uses]["Bob"] = 0
barrel_bidding.state[:scores]["Carol"] = 950
gift_win_planner = TysiacPlanning::Planner.new(
  game,
  barrel_bidding,
  "Bob",
  GameRoomRandom::SeededSource.new(4_402)
)
assert(
  gift_win_planner.send(
    :select_barrel_denial,
    denial_statistics,
    threatened: "Alice",
    threat_probability: 0.60,
    blocker: nil,
    blocker_capacity: 0.0
  ) == nil,
  "the bot made a sacrifice whose surrender award could immediately crown another opponent"
)

planner_replay = bidding_replay(game, players, %w[AH TH KH QH AD TD 9C])
planner = TysiacPlanning::Planner.new(
  game,
  planner_replay,
  "Bob",
  GameRoomRandom::SeededSource.new(9)
)
denial_world = {
  players: players,
  hands: { "Alice" => [], "Bob" => %w[AC 9C], "Carol" => %w[JC] },
  current_player: "Bob",
  taker: "Bob",
  contract: 100,
  trump: nil,
  current_trick: [{ player: "Alice", card: "TC" }],
  trick_number: 3,
  round_points: { "Alice" => 0, "Bob" => 100, "Carol" => 0 },
  scores: { "Alice" => 0, "Bob" => 0, "Carol" => 0 },
  barrels: players.to_h { |player| [player, { active: false, deals_left: 0 }] },
  zero_rounds: players.to_h { |player| [player, 0] },
  surrender_uses: players.to_h { |player| [player, 0] },
  score_limit: 1_000
}
_mode, denial_card = planner.send(:rollout_choice, denial_world, "Bob")
assert(denial_card == "AC", "the taker donated a valuable trick after completing the contract")

marriage_world = denial_world.merge(
  hands: { "Alice" => [], "Bob" => %w[KH QH 9C], "Carol" => [] },
  current_trick: [],
  trick_number: 0,
  round_points: { "Alice" => 0, "Bob" => 0, "Carol" => 0 }
)
_mode, opening_card = planner.send(:rollout_choice, marriage_world, "Bob")
assert(opening_card == "9C", "the opening lead broke a marriage before it could be declared")

marriage_state = game.send(:initial_state, players, game.default_options)
marriage_state[:phase] = :playing
marriage_state[:current_player] = "Bob"
marriage_state[:taker] = "Bob"
marriage_state[:contract] = 100
marriage_state[:hands]["Bob"] = %w[KH QH 9C]
marriage_replay = GameRoomGames::Replay.new(
  board: nil,
  players: players,
  current_player: "Bob",
  winner: nil,
  draw: false,
  accepted_events: [],
  history: [],
  state: marriage_state
)
assert(
  game.bot_action_score(marriage_replay, "Bob", { "card" => "normal|9C" }) >
    game.bot_action_score(marriage_replay, "Bob", { "card" => "normal|KH" }),
  "the fallback heuristic prefers breaking an undeclared marriage"
)

control_state = game.send(:initial_state, players, game.default_options)
control_state[:phase] = :playing
control_state[:current_player] = "Bob"
control_state[:taker] = "Bob"
control_state[:contract] = 120
control_state[:trick_number] = 0
control_state[:hands] = {
  "Alice" => %w[JH JD QH QS QD KD AC KS],
  "Bob" => %w[JS TC 9S KC QC AH AD TH],
  "Carol" => %w[TD 9D TS 9C AS KH JC 9H]
}
control_replay = GameRoomGames::Replay.new(
  board: nil,
  players: players,
  current_player: "Bob",
  winner: nil,
  draw: false,
  accepted_events: [],
  history: [],
  state: control_state
)
5.times do |seed|
  control_choice = game.bot_strategy.choose(
    actions: game.legal_actions(control_replay, "Bob"),
    actor: "Bob",
    random_source: GameRoomRandom::SeededSource.new(7_600 + seed),
    game: game,
    replay: control_replay
  )
  assert(
    %w[normal|AH normal|AD].include?(control_choice["card"]),
    "the taker did not secure the lead before declaring a marriage"
  )
end

passing_state = control_state.merge(
  phase: :passing,
  hands: {
    "Alice" => %w[JH JD QH QS QD KD AC],
    "Bob" => %w[JS TC 9S KC QC AH AD 9H TH KS],
    "Carol" => %w[TD 9D TS 9C AS KH JC]
  }
)
passing_replay = control_replay.dup
passing_replay.state = passing_state
passing_planner = TysiacPlanning::Planner.new(
  game,
  passing_replay,
  "Bob",
  GameRoomRandom::SeededSource.new(7_601)
)
assert(
  passing_planner.send(:pass_marriage_risk_penalty, "KS", hand: passing_state[:hands]["Bob"]) >
    passing_planner.send(:pass_marriage_risk_penalty, "JS", hand: passing_state[:hands]["Bob"]),
  "passing a king does not account for creating an opponent marriage"
)
10.times do |seed|
  passing_choice = game.bot_strategy.choose(
    actions: game.legal_actions(passing_replay, "Bob"),
    actor: "Bob",
    random_source: GameRoomRandom::SeededSource.new(7_700 + seed),
    game: game,
    replay: passing_replay
  )
  assert(
    passing_choice["card"] != "KS",
    "the taker needlessly gave a king which could complete an opponent marriage"
  )
end

declaration_state = control_state.merge(
  trick_number: 1,
  hands: {
    "Alice" => %w[JH JD QH QS QD KD AC],
    "Bob" => %w[KC QC AH TS 9S JC AD],
    "Carol" => %w[TD 9D TC 9C AS KH 9H]
  }
)
declaration_replay = control_replay.dup
declaration_replay.state = declaration_state
late_control_state = declaration_state.merge(
  contract: 120,
  trick_number: 6,
  round_points: { "Alice" => 17, "Bob" => 103, "Carol" => 20 },
  hands: {
    "Alice" => %w[9H JS],
    "Bob" => %w[AH KD],
    "Carol" => %w[TC QS]
  }
)
late_control_replay = declaration_replay.dup
late_control_replay.state = late_control_state
late_control_planner = TysiacPlanning::Planner.new(
  game,
  late_control_replay,
  "Bob",
  GameRoomRandom::SeededSource.new(7_999)
)
late_control_actions = game.legal_actions(late_control_replay, "Bob")
assert(
  late_control_planner.send(:late_contract_control_actions, late_control_actions).map { |action| action["card"] } == ["normal|AH"],
  "the taker can still lead a weaker last card while an unfinished contract and an ace remain"
)

zero_world = denial_world.merge(
  hands: players.to_h { |player| [player, []] },
  current_trick: [],
  taker: "Bob",
  round_points: { "Alice" => 0, "Bob" => 100, "Carol" => 20 }
)
ordinary_zero = planner.send(:evaluate, zero_world, "Alice")
third_zero_world = zero_world.merge(zero_rounds: zero_world[:zero_rounds].merge("Alice" => 2))
third_zero = planner.send(:evaluate, third_zero_world, "Alice")
assert(third_zero < ordinary_zero, "the planner ignores an imminent third-zero penalty")

bot_contract_seen = false
bot_play_seen = false
bot_surrender_seen = false
5.times do |index|
  environment = GameRoomSimulation::Environment.new_game(
    game: game,
    players: GameRoomParticipants.bots_for(index + 1, 3),
    options: game.default_options,
    seed: index + 1
  )
  first_round = environment.replay.state[:round]
  actions = 0
  while environment.replay.state[:round] == first_round && !environment.finished? && actions < 100
    actor = environment.active_actor
    choices = environment.legal_actions(actor)
    choice = GameRoomBots.choose(game.bot_strategy, {
      actions: choices,
      observation: environment.observation(actor),
      actor: actor,
      random_source: environment.random_source,
      game: game,
      replay: environment.replay,
      context: environment.context,
      simulation: environment
    })
    assert(choice != nil, "bot deal #{index + 1} did not choose an action")
    assert(environment.step(choice, actor: actor) == :ok, "bot deal #{index + 1} chose an invalid action")
    actions += 1
  end
  assert(environment.replay.state[:round] > first_round || environment.finished?, "bot deal #{index + 1} did not finish")
  bot_contract_seen ||= environment.events.any? { |item| item["action"] == "contract" }
  bot_play_seen ||= environment.events.any? { |item| item["action"] == "play" }
  bot_surrender_seen ||= environment.events.any? { |item| item["action"] == "surrender" }
end
assert(bot_contract_seen, "the bots never set a contract")
assert(bot_play_seen, "the bots never played a card")
assert(bot_surrender_seen, "the bots never surrendered a clearly weak forced contract")

planner = TysiacPlanning::Planner.allocate
first_shuffle = planner.send(:deterministic_shuffle, [1, 2, 3, 4, 5], Random.new(1234))
second_shuffle = planner.send(:deterministic_shuffle, [1, 2, 3, 4, 5], Random.new(1234))
assert(first_shuffle.sort == [1, 2, 3, 4, 5], "the portable shuffle lost or duplicated values")
assert(first_shuffle == second_shuffle, "the portable shuffle is not reproducible from a seed")

puts "Tysiac model tests passed"
