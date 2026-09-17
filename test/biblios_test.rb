require_relative "support/new_games_fixture"

game = GameRoomGames::Biblios.new
klass = GameRoomGames::Biblios

def church_card(game, kind)
  (1..24).map { |index| "k#{index}" }.find { |card| game.church_kind(card) == kind }
end

def blank_state(game, players, options = {})
  game.send(:initial_state, players, game.normalize_options(options))
end

def bluff_board(game, penalty: "bluff", passed: [], gold: %w[o1], high: 1)
  state = game.send(:initial_state, %w[Alice Bob Carol], game.normalize_options("penalty" => penalty))
  state[:phase] = :auction
  state[:dice]["m"] = 6
  state[:card] = "mH"
  state[:current_player] = "Alice"
  state[:hands]["Alice"] = gold
  state[:hands]["Bob"] = %w[mA]
  state[:hands]["Carol"] = []
  state[:passed] = passed
  state[:high] = high
  state
end

def bid_value(game, state, amount)
  game.bot_action_score(replay_of(state), "Alice", { "action" => "bid", "amount" => amount })
end

def replay_of(state)
  GameRoomGames::Replay.new(
    players: state[:players], current_player: state[:current_player],
    winner: state[:winner], draw: state[:tie], state: state,
    accepted_events: [], history: []
  )
end

def play_biblios(game, players, options = {})
  repository = NewGames116Repository.new(players)
  session = { "options" => JSON.generate(game.normalize_options(options)) }
  events = []
  replay = game.replay(session, events, repository)
  context = context_for
  random = NewGames116Random.new
  strategy = game.bot_strategy
  guard = 0
  while !replay.finished?
    guard += 1
    raise "Biblios did not finish" if guard > 20_000

    state = replay.state
    if state[:phase] == :setup
      replay = append_action(game, session, repository, events, replay, players.first,
        game.automatic_action(replay, players.first), context)
      next
    end
    actor = replay.current_player
    raise "no actor in #{state[:phase]}" if actor == nil

    assert(state[:public].length <= players.length - 1, "the public space overflowed")
    assert(state[:hands].values.flatten.none? { |card| game.church?(card) }, "a Church card stayed in a hand")
    actions = game.legal_actions(replay, actor)
    raise "no legal actions for #{actor} in #{state[:phase]}" if actions.empty?

    choice = strategy.choose(actions: actions, actor: actor, random_source: random, game: game, replay: replay)
    replay = append_action(game, session, repository, events, replay, actor, choice, context)
  end
  [replay, events, session, repository]
end

assert(game.id == "biblios", "Biblios has the wrong id")
assert(game.minimum_players == 2 && game.maximum_players == 4, "Biblios exposes the wrong player range")
assert(game.supports_bots?, "Biblios does not support bots")
assert(game.default_options["penalty"] == "bluff", "the medieval bluff is not the default penalty")
assert(!game.perfect_information?, "Biblios must not be a perfect information game")

deck = game.send(:master_deck)
assert(deck.length == 87, "the deck does not hold 87 cards")
assert(deck.uniq.length == 87, "the deck holds duplicate identifiers")
categories = deck.select { |card| game.card_category(card) }
assert(categories.length == 45, "the deck does not hold 45 category cards")
klass::CATEGORIES.each do |category|
  cards = categories.select { |card| game.card_category(card) == category }
  expected = klass::RICH_CATEGORIES.include?(category) ? 25 : 11
  assert(cards.length == 9, "category #{category} does not hold nine cards")
  assert(cards.map { |card| card[1] }.sort == klass::LETTERS, "category #{category} does not use the letters A to I")
  assert(cards.sum { |card| game.card_value(card) } == expected, "category #{category} has the wrong total value")
end
gold = deck.select { |card| game.gold?(card) }
assert(gold.length == 18, "the deck does not hold eighteen Gold cards")
klass::GOLD_VALUES.each do |value|
  assert(gold.count { |card| game.gold_value(card) == value } == 6, "Gold #{value} is not present six times")
end
assert(deck.count { |card| game.church?(card) } == 24, "the deck does not hold 24 Church cards")

{ 2 => 60, 3 => 72, 4 => 80 }.each do |count, size|
  players = %w[Alice Bob Carol Dave].first(count)
  prepared = game.send(:prepared_deck, players, "seed#{count}")
  assert(prepared.length == size, "the #{count} player setup leaves #{prepared.length} cards")
  assert((size % (count + 1)).zero?, "the #{count} player deck does not divide into whole turns")
  removed = 18 - prepared.count { |card| game.gold?(card) }
  assert(removed >= { 2 => 6, 3 => 3, 4 => 0 }.fetch(count), "the #{count} player setup kept too much Gold")
end

state = blank_state(game, %w[Alice Bob Carol])
assert(game.send(:allocation_size, state) == 4, "three players do not allocate four cards")
assert(game.send(:public_capacity, state) == 2, "three players do not leave two public cards")
assert(game.send(:allocation_places, state).sort == %w[auction public self], "the first card has no free place")
state[:placed]["self"] = 1
state[:placed]["auction"] = 1
assert(game.send(:allocation_places, state) == ["public"], "the public space is not forced once the limits are used")

state = blank_state(game, %w[Alice Bob Carol])
state[:church] = { "player" => "Alice", "card" => church_card(game, "up2"), "resume" => "allocate" }
plans = game.send(:church_plans, state)
assert(plans.include?("skip"), "a Church card cannot be declined")
pairs = plans - ["skip"]
assert(pairs.length == 10, "a two dice card does not offer every pair of categories")
assert(pairs.all? { |plan| plan.split(",").map { |part| part.split(":").last }.uniq.length == 2 },
  "a two dice card may modify one category twice")
klass::CATEGORIES.each { |category| state[:dice][category] = 6 }
assert(game.send(:church_plans, state) == ["skip"], "dice may be raised above six")
state[:church] = { "player" => "Alice", "card" => church_card(game, "down1"), "resume" => "allocate" }
klass::CATEGORIES.each { |category| state[:dice][category] = 1 }
assert(game.send(:church_plans, state) == ["skip"], "dice may be lowered below one")
state[:dice]["m"] = 3
assert(game.send(:church_plans, state) == ["down:m", "skip"], "only the movable die is offered")

state = blank_state(game, %w[Alice Bob])
state[:hands]["Alice"] = %w[mE mF]
state[:hands]["Bob"] = %w[mH mB]
assert(game.send(:category_total, state, "Alice", "m") == 6, "Alice does not total six Monks")
assert(game.send(:category_total, state, "Bob", "m") == 6, "Bob does not total six Monks")
assert(game.send(:category_winner, state, "m") == "Bob", "the tie did not go to the letter closest to A")
assert(game.send(:category_winner, state, "p") == nil, "an empty category has a winner")
state[:hands]["Bob"] = %w[mH]
assert(game.send(:category_winner, state, "m") == "Alice", "the higher total did not win the category")

state = blank_state(game, %w[Alice Bob])
state[:hands]["Alice"] = %w[o1]
state[:hands]["Bob"] = %w[o7]
assert(game.send(:victory_points, state, "Alice") == game.send(:victory_points, state, "Bob"), "the Gold tie needs equal points")
assert(game.send(:gold_total, state, "Alice") == 1, "Gold 1 is not worth one")
assert(game.send(:gold_total, state, "Bob") == 2, "Gold 2 is not worth two")
assert((game.send(:final_key, state, "Bob") <=> game.send(:final_key, state, "Alice")) == 1, "more Gold did not break the tie")

state = blank_state(game, %w[Alice Bob])
state[:card] = "mA"
state[:high] = 4
state[:hands]["Alice"] = %w[o1 o7 o13]
assert(game.send(:payment_capacity, state, "Alice") == 6, "the payment capacity ignores Gold values")
assert(game.send(:valid_payment?, state, "Alice", %w[o7 o13]), "two Gold cards worth five did not pay four")
assert(!game.send(:valid_payment?, state, "Alice", %w[o1 o7]), "three Gold paid a bid of four")
assert(!game.send(:valid_payment?, state, "Alice", %w[o1 o7 o13]), "a redundant card was accepted")
assert(game.send(:payments, state, "Alice").all? { |packet| game.send(:valid_payment?, state, "Alice", packet) },
  "an invalid payment was offered")
state[:card] = "o1"
state[:high] = 2
state[:hands]["Alice"] = %w[mA mB o7]
assert(game.send(:valid_payment?, state, "Alice", %w[mA mB]), "a Gold card is not paid with two cards")
assert(!game.send(:valid_payment?, state, "Alice", %w[mA]), "a Gold card was paid with too few cards")
assert(!game.send(:valid_payment?, state, "Alice", %w[mA mB o7]), "a Gold card was paid with too many cards")

state = blank_state(game, %w[Alice Bob Carol])
state[:card] = "mA"
state[:high] = 2
state[:hands]["Alice"] = %w[o1 o2 o3]
assert(game.send(:legal_bids, state, "Alice").first == 3, "a bid may repeat the current one")
assert(game.send(:offered_bids, state, "Alice") == [3, 4, 5, 6, 7], "the bid list does not offer bluffs above the current bid")

[2, 3, 4].each do |count|
  players = %w[Alice Bob Carol Dave].first(count)
  replay, events, session, repository = play_biblios(game, players)
  state = replay.state
  assert(replay.finished?, "the #{count} player game did not finish")
  assert(state[:winner] != nil || replay.draw, "the #{count} player game has no result")
  assert(state[:deck].length == state[:pointer], "the #{count} player auction pile was not exhausted")
  assert(state[:hands].values.flatten.none? { |card| game.church?(card) }, "a Church card survived in a hand")
  assert(game.participant_scores(replay).values.sum >= 0, "the scores are not readable")
  again = game.replay(session, events, repository)
  assert(again.winner == replay.winner && again.draw == replay.draw, "the replay is not deterministic")
  assert(again.state[:dice] == state[:dice], "the Scriptorium is not reproduced by a replay")
end

players = %w[Alice Bob Carol]
replay, events, session, repository = play_biblios(game, players)
assert(game.supports_saved_games?, "Biblios does not support saved games")
assert(game.saved_game_schema_version.to_i > 0, "Biblios has no saved game schema version")
[events.length / 4, events.length / 2].each do |cut|
  partial = game.replay(session, events.first(cut), repository)
  assert(!partial.finished?, "a saved game cut at #{cut} was already finished")
  assert(game.save_game_error(partial) == nil, "a saved game cut at #{cut} was refused")
  assert(partial.current_player != nil, "a saved game cut at #{cut} has no player to move")
  assert(game.legal_actions(partial, partial.current_player).length.positive? || partial.state[:phase] == :setup,
    "a saved game cut at #{cut} cannot continue")
end
assert(replay.history.any? { |entry| entry.kind == :phase }, "the Auction phase was never announced")
assert(replay.history.any? { |entry| entry.kind == :bid }, "no bid reached the history")
assert(game.result_text(replay).to_s != "", "the game has no result text")

state = blank_state(game, players)
state[:phase] = :allocate
state[:seed] = "abc"
state[:deck] = game.send(:prepared_deck, players, "abc")
surface = game.surface_spec(
  GameRoomGames::Replay.new(players: players, current_player: "Alice", winner: nil, draw: false,
    state: state, accepted_events: [], history: []), "Alice"
)
assert(surface.is_a?(GameSurfaces::CardTableSpec), "the allocation surface is not one list")
assert(surface.zones.first.cards.map(&:value).sort == %w[auction public self], "the allocation list is incomplete")

shortcuts = game.game_shortcuts(replay, "Alice").each_with_object({}) do |shortcut, result|
  result[[shortcut.key, shortcut.modifiers.to_a]] = shortcut
end
assert(shortcuts[["t", []]] != nil, "T is missing")
assert(shortcuts[["l", []]] != nil, "L does not read the library")
assert(shortcuts[["l", [:control]]] != nil, "Ctrl+L does not browse the library")
assert(shortcuts[["c", []]] != nil, "C does not read the Scriptorium")
assert(shortcuts[["c", [:shift]]] != nil, "Shift+C does not read the leaders")
assert(shortcuts[["g", []]] != nil, "G does not read your Gold")
assert(shortcuts[["p", []]] != nil, "P does not read the public space")
assert(shortcuts[["h", []]] == nil, "H is reserved for help and must not be used")
assert(shortcuts[["c", []]].message.include?("Pigments"), "C does not name the categories")

repository = NewGames116Repository.new(%w[Alice Bob Carol])
session = { "options" => JSON.generate(game.normalize_options({})) }
events = []
replay = game.replay(session, events, repository)
context = context_for
replay = append_action(game, session, repository, events, replay, "Alice",
  game.automatic_action(replay, "Alice"), context)

kept = nil
keeper = nil
60.times do
  break if replay.finished? || kept != nil

  state = replay.state
  actor = replay.current_player
  actions = game.legal_actions(replay, actor)
  if state[:phase] == :allocate && !game.church?(state[:deck][state[:pointer]]) &&
     actions.any? { |action| action["place"] == "self" }
    kept = state[:deck][state[:pointer]]
    keeper = actor
    replay = append_action(game, session, repository, events, replay, actor,
      { "kind" => "command", "action" => "allocate", "place" => "self" }, context)
  else
    replay = append_action(game, session, repository, events, replay, actor, actions.first, context)
  end
end
assert(kept != nil, "no ordinary card was kept during the Gift phase")

label = game.send(:card_label, kept)
onlooker = %w[Alice Bob Carol].find { |player| player != keeper }
spoken = Array(game.describe_event(events.last, repository, replay, keeper)).join(" ")
overheard = Array(game.describe_event(events.last, repository, replay, onlooker)).join(" ")
assert(spoken.include?(label), "the player who picked the card up was not told which card it is")
assert(!overheard.include?(label), "a kept card was revealed to another player")
assert(!overheard.include?("You pick up"), "another player was told about picking a card up")

if replay.state[:phase] == :allocate && replay.current_player == keeper
  drawn = game.send(:card_label, replay.state[:deck][replay.state[:pointer]])
  assert(spoken.include?(drawn), "the next drawn card is not read to the active player")
  assert(!overheard.include?("You draw"), "another player was told about the drawn card")
end

state = blank_state(game, %w[Alice Bob])
state[:hands]["Alice"] = %w[mH mI]
state[:revealed]["Alice"] = %w[mH]
state[:hands]["Bob"] = %w[mE]
state[:revealed]["Bob"] = %w[mE]
assert(game.send(:category_winner, state, "m") == "Alice", "the true leader is not counted from the whole hand")
assert(game.send(:category_total, state, "Alice", "m") == 8, "the true total ignores a hidden card")
open_text = game.send(:leaders_text, state)
assert(open_text.include?("Monks: Alice with 4"), "the open standing does not count the cards taken openly")
assert(!open_text.include?("with 8"), "a face down card was counted into the open standing")

secret = nil
seen = nil
repository = NewGames116Repository.new(%w[Alice Bob Carol])
session = { "options" => JSON.generate(game.normalize_options({})) }
events = []
replay = game.replay(session, events, repository)
context = context_for
replay = append_action(game, session, repository, events, replay, "Alice",
  game.automatic_action(replay, "Alice"), context)
60.times do
  break if replay.finished? || (secret != nil && seen != nil)

  state = replay.state
  actor = replay.current_player
  actions = game.legal_actions(replay, actor)
  card = state[:deck][state[:pointer]]
  if state[:phase] == :allocate && secret == nil && !game.church?(card) &&
     actions.any? { |action| action["place"] == "self" }
    secret = [actor, card]
    replay = append_action(game, session, repository, events, replay, actor,
      { "kind" => "command", "action" => "allocate", "place" => "self" }, context)
  elsif state[:phase] == :take && seen == nil && !game.church?(actions.first["card"])
    seen = [actor, actions.first["card"]]
    replay = append_action(game, session, repository, events, replay, actor, actions.first, context)
  else
    replay = append_action(game, session, repository, events, replay, actor, actions.first, context)
  end
end
assert(secret != nil && seen != nil, "the Gift phase produced no hidden and open pair to compare")
assert(replay.state[:hands][secret[0]].include?(secret[1]), "a kept card never reached the hand")
assert(!replay.state[:revealed][secret[0]].include?(secret[1]), "a card kept face down was recorded as seen")
assert(replay.state[:revealed][seen[0]].include?(seen[1]), "a card taken from the public space was not recorded as seen")

players = %w[Alice Bob Carol]
finished, events, session, repository = play_biblios(game, players)
midpoint = game.replay(session, events.first(events.length / 2), repository)
assert(!midpoint.finished?, "the midpoint replay is already over")
assert(game.participant_scores(midpoint) == nil, "the scores are published while the game is running")
assert(game.participant_scores(finished).is_a?(Hash), "the final scores are not published")
running = game.game_shortcuts(midpoint, "Alice").map { |shortcut| [shortcut.key, shortcut.modifiers.to_a] }
over = game.game_shortcuts(finished, "Alice").map { |shortcut| [shortcut.key, shortcut.modifiers.to_a] }
assert(!running.include?(["s", []]), "S reads the scores before the game is over")
assert(over.include?(["s", []]), "S does not read the scores once the game is over")

state = blank_state(game, %w[Alice Bob Carol])
state[:phase] = :auction
state[:card] = "mA"
state[:current_player] = "Alice"
state[:hands]["Alice"] = %w[mB mC]
offered = game.send(:offered_bids, state, "Alice")
assert(!offered.empty?, "a player holding no Gold cannot bid at all")
assert(offered.first == 1, "the bid list does not start just above the current bid")
assert(game.send(:legal_bids, state, "Alice").include?(3), "the rules allow bidding more Gold than you hold")
bids = game.surface_spec(replay_of(state), "Alice").zones.first.cards
assert(bids.first.value == "pass", "Pass is not the first choice in an auction")
assert(bids.length > 1, "an auction offers nothing but Pass")
assert(bids.any? { |card| card.label.include?("more than you can pay") }, "a bid beyond your Gold is not marked")
assert(bids.none? { |card| card.value == "0" }, "a bid may repeat the current one")
status, plan = game.action_for({ "kind" => "command", "action" => "bid", "amount" => 3 }, replay_of(state), "Alice")
assert(status == :ok && plan.events.first.value == "3", "a bluff bid was rejected")

state[:phase] = :pay
state[:high] = 3
payment = game.surface_spec(replay_of(state), "Alice")
assert(payment.is_a?(GameSurfaces::PacketCardSpec), "the payment is not a single list")
assert(payment.cards.last.value == "decline", "Do not pay is not the last entry of the payment list")
status, = game.action_for(
  { "kind" => "card_packet", "action" => "pay", "cards" => JSON.generate(["decline"]) },
  replay_of(state), "Alice"
)
assert(status == :ok, "Do not pay was rejected from the payment list")

%w[bluff full].each do |variant|
  state = blank_state(game, %w[Alice Bob Carol], "penalty" => variant)
  state[:seed] = "penalty-seed"
  state[:phase] = :pay
  state[:card] = "mA"
  state[:high] = 4
  state[:leader] = "Alice"
  state[:current_player] = "Alice"
  state[:hands]["Alice"] = %w[mB mC mD]
  state[:passed] = %w[Bob Carol]
  history = []
  game.send(:penalise, state, "Alice", 7, history)
  assert(state[:barred].include?("Alice"), "the penalised player may bid again (#{variant})")
  assert(state[:high].zero? && state[:bidder] == nil, "the bid survived the penalty (#{variant})")
  assert(state[:passed].empty?, "the passes were not cleared for the new auction (#{variant})")
  assert(state[:card] == "mA", "the card was not auctioned again (#{variant})")
  assert(state[:phase] == :auction, "the auction did not resume (#{variant})")
  assert(state[:current_player] != "Alice", "the penalised player was asked to bid (#{variant})")
  assert(history.any? { |entry| entry.kind == :penalty }, "the penalty is missing from the history (#{variant})")
  if variant == "bluff"
    assert(state[:hands]["Alice"].length == 2, "the medieval bluff did not discard exactly one card")
    assert(state[:hands]["Bob"].empty? && state[:hands]["Carol"].empty?, "the medieval bluff handed cards to opponents")
  else
    assert(state[:hands]["Alice"].length == 1, "the full penalty did not take one card per opponent")
    assert(state[:hands]["Bob"].length == 1 && state[:hands]["Carol"].length == 1,
      "the opponents did not each take a card under the full penalty")
  end
end

refusal = bid_value(game, bluff_board(game), "pass")
assert(bid_value(game, bluff_board(game), 2) > refusal,
  "the bot never bluffs, even for a valuable card with rivals still bidding")
assert(bid_value(game, bluff_board(game, passed: %w[Carol]), 2) < refusal,
  "the bot bluffs against a single rival who can simply pass")
assert(bid_value(game, bluff_board(game, passed: %w[Bob Carol]), 2) < refusal,
  "the bot bluffs when nobody is left to outbid it")
assert(bid_value(game, bluff_board(game), 4) < refusal, "the bot bluffs far beyond its Gold")
assert(bid_value(game, bluff_board(game, penalty: "full"), 2) < bid_value(game, bluff_board(game), 2),
  "the full penalty does not make the bot more careful about bluffing")
solvent = bluff_board(game, gold: %w[o13], high: 0)
assert(bid_value(game, solvent, 3) > bid_value(game, solvent, 4), "the bot prefers a bluff to a bid it can pay")
trifle = bluff_board(game)
trifle[:dice]["m"] = 3
trifle[:card] = "mA"
assert(bid_value(game, trifle, 2) < refusal, "the bot bluffs for a card that is not worth the penalty")

puts "Biblios model tests passed"
