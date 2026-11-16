require_relative "../support/room_interface"
require_relative "../support/private_simulation"
require_relative "../support/contract_values"

def assert(value, message); raise message unless value; end

def annotated_hands(spec)
  case spec
  when GameSurfaces::CompositeSpec
    spec.parts.flat_map { |part| annotated_hands(part.surface) }
  when GameSurfaces::CardTableSpec, GameSurfaces::MeldHandSpec
    spec.zones.select { |zone| zone.hand_order != nil && !zone.cards.empty? }.map(&:cards)
  when GameSurfaces::PacketCardSpec
    spec.hand_order != nil && !spec.cards.empty? ? [spec.cards] : []
  else
    []
  end
end

games = %w[makao ninety_nine poker rummy scientific_war spades three_five_eight tysiac uno
  bridge bouillabaisse scopa french_tarot cribbage belote jass hearts]
cases = JSON.parse(File.read(File.join(__dir__, "../fixtures/contracts/v1/histories.json"), encoding: "UTF-8")).fetch("cases")
cases.reject! { |item| item.fetch("game") == "tysiac" || !games.include?(item.fetch("game")) }
%w[v2/tysiac v2/bridge v1/bouillabaisse v1/scopa v1/french_tarot v1/cribbage v1/belote v1/jass v1/hearts].each do |name|
  cases << JSON.parse(File.read(File.join(__dir__, "../fixtures/contracts/#{name}.json"), encoding: "UTF-8"))
end

checks = Hash.new(0)
cases.each do |item|
  game = GameRoomGames::CATALOG.build(item.fetch("game"))
  env = GameRoomTest::PrivateSimulation.new_game(game: game, players: item.fetch("players"),
    options: item.fetch("options"), seed: item.fetch("seed"))
  item.fetch("events").length.succ.times do |length|
    replay = game.replay(env.session, item.fetch("events").first(length), env.repository)
    before = GameRoomTest::ContractValues.digest(replay)
    item.fetch("players").each do |viewer|
      spec = game.game_view_spec(replay, viewer).surface
      annotated_hands(spec).each do |cards|
        assert(cards.all? { |card| card.navigation_group && !card.navigation_group.id.to_s.empty? && !card.navigation_group.label.to_s.empty? },
          "#{game.id}/#{replay.state[:phase]}/#{viewer}: incomplete suit groups")
        checks[game.id] += 1
      end
      surface = GameSurfaces.build(spec) if spec
      # Building the shared view still preserves physical cursors and epochs.
      assert(!surface || GameSurfaces.build(spec, state: surface.state).state == surface.state,
        "#{game.id}: new metadata broke shared surface reconstruction")
    end
    assert(GameRoomTest::ContractValues.digest(replay) == before, "#{game.id}: suit metadata changed the authoritative replay")
  end
end
# The recorded Poker contract is a betting-only variant. Its separate exchange
# hand uses the same actual initial model and PacketCardSurface as the game.
poker = GameRoomGames::Poker.new
state = poker.__send__(:initial_state, %w[Alice Bob], poker.default_options)
state.update(phase: :exchange, current_player: "Alice", hands: {"Alice" => %w[AH JS 2H], "Bob" => []})
replay = GameRoomGames::Replay.new(players: state[:players], state: state, current_player: "Alice", history: [], accepted_events: [])
hand = annotated_hands(poker.surface_spec(replay, "Alice")).fetch(0)
assert(hand.all?(&:navigation_group), "Poker exchange has an ungrouped card")
checks["poker"] += 1
assert(checks.keys.sort == games.sort, "Missing real consumers: #{games - checks.keys}")

# Special cards need their own reachable groups, not a guessed suit based on
# their physical ID. Include all UNO deck families and actual Tarot encoding.
uno = GameRoomGames::Uno.new
%w[classic no_mercy flip].each do |deck|
  state = uno.__send__(:initial_state, %w[Alice Bob], uno.default_options.merge("deck" => deck))
  cards = uno.__send__(:uno_deck, state[:options])
  state.update(phase: :playing, current_player: "Alice", hands: {"Alice" => cards, "Bob" => []}, discard: [])
  replay = GameRoomGames::Replay.new(players: state[:players], state: state, current_player: "Alice", history: [], accepted_events: [])
  hand = uno.surface_spec(replay, "Alice").zones.first.cards
  assert(hand.all? { |card| card.navigation_group && !card.navigation_group.label.empty? }, "UNO #{deck}: ungrouped special card")
  assert(hand.any? { |card| card.navigation_group.id == "wild" }, "UNO #{deck}: missing wild group")
end
tarot = GameRoomGames::FrenchTarotTable.new
spec = tarot.__send__(:card_hand_surface, GameRoomGames::FrenchTarotCards::DECK)
groups = spec.zones.first.cards.map(&:navigation_group)
assert(groups.map(&:id).uniq.sort == %w[C D H S excuse trumps], "Tarot specials were confused with ordinary suits")

# Names are suit names, not the colliding titles of the Hearts/Spades games.
base = GameRoomGames::Spades.new
{"en" => %w[Hearts Spades Diamonds Clubs Jokers Trumps],
 "pl" => %w[Kiery Piki Kara Trefle Jokery Atuty],
 "cs" => %w[Srdce Piky Kára Kříže Žolíci Trumfy],
 "es" => %w[Corazones Picas Diamantes Tréboles Comodines Triunfos],
 "ru" => %w[Червы Пики Бубны Трефы Джокеры Козыри]}.each do |language, expected|
  GameRoomLocalization.boot(settings: {"interface_language" => language}, host_language: language)
  labels = %w[H S D C].map { |suit| base.__send__(:standard_hand_navigation_group, rank: "2", suit: suit).label }
  labels << base.__send__(:standard_hand_navigation_group, rank: "X", suit: "0").label
  labels << tarot.__send__(:standard_hand_navigation_group, rank: 1, suit: "X").label
  assert(labels == expected, "#{language}: suit group labels are not localized: #{labels.inspect}")
end

puts "PASS suit metadata and unchanged/reconstructed views: #{checks.values.sum} hands across #{checks.length} real games; three UNO decks and all Tarot cards"
