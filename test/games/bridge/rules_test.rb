require_relative "../../support/bridge"
include GameRoomTest::Assertions

R = GameRoomGames::BridgeRules
table = GameRoomTest::BridgeTable.new
game = table.game
assert(game.name == "Bridge" && game.minimum_players == 4 && game.maximum_players == 4, "wrong registration")
assert(game.supports_bots? && game.supports_saved_games? && !game.perfect_information?, "wrong capabilities")
assert_equal("rubber", game.default_options["variant"], "rubber should be the default variant")
assert_equal(8, game.normalize_options({ "variant" => "duplicate", "boards" => 5 })["boards"], "an unsupported board count was kept")
assert(game.options_error({}, player_count: 3), "three players were accepted")
assert_equal(nil, game.options_error({ "variant" => "duplicate", "boards" => 16, "scoring" => "mp" }, player_count: 4))

# Partners sit opposite: the default team assignment pairs roster 0/2 and 1/3.
assert_equal(%w[Alice Bob Carol Dave], table.state[:seats], "wrong seats")
teams = GameRoomTest::BridgeTable.new(%w[Alice Bob Carol Dave], { "team_seats" => [0, 0, 1, 1] })
assert_equal(%w[Alice Carol Bob Dave], teams.state[:seats], "chosen partners do not sit opposite")

state = table.state
assert(state[:phase] == :bidding && state[:hands].map(&:length) == [13] * 4, "the deal did not start the auction")
assert(state[:hands].flatten.uniq.length == 52, "the deal is not a full deck")
dealer = state[:dealer]
assert_equal(table.seat_player(dealer), state[:current_player], "the dealer does not call first")

# Calls must rise; doubles are only for the opponents' last bid.
assert_equal(:invalid_call, table.call("X"), "a double without a bid was accepted")
table.calls("1H")
assert_equal(:invalid_call, table.call("1D"), "a lower bid was accepted")
assert_equal(:invalid_call, table.call("1H"), "an equal bid was accepted")
table.calls("X")
assert_equal(:invalid_call, table.call("X"), "partner of the doubler could double again")
table.calls("XX", "1S", "P", "P")
waiting = table.state[:seats].find { |player| player != table.state[:current_player] }
assert_equal(:not_your_turn, table.act(waiting, { "kind" => "command", "action" => "call", "call" => "P" }), "an out-of-turn call was accepted")
table.calls("2H", "P", "P", "P")
contract = state[:contract] || table.state[:contract]
assert_equal("2H", contract.text, "wrong final contract")
assert_equal(dealer, contract.declarer, "the first to name the strain did not become declarer")
leader = R.next_seat(dealer)
dummy = R.partner_of(dealer)
assert_equal(:playing, table.state[:phase], "play did not start")
assert_equal(leader, table.state[:seat_to_play], "the wrong player leads")

# Dummy is hidden until the opening lead and cannot play its own cards.
dummy_card = table.state[:hands][dummy].first
assert(game.surface_spec(table.replay, table.seat_player(leader)).zones.none? { |zone| zone.id == "dummy" }, "dummy was shown before the lead")
spectator = game.surface_spec(table.replay, "Spectator")
assert(spectator.is_a?(GameSurfaces::QuestionSpec) && spectator.mode == :information, "a spectator got an empty card table")
lead = table.state[:hands][leader].first
assert_equal(:ok, table.play(lead), "the opening lead failed")
assert(table.state[:dummy_visible], "dummy was not exposed after the lead")
assert_equal(%w[dummy], game.surface_spec(table.replay, "Spectator").zones.map(&:id), "a spectator does not see dummy")
assert_equal(table.seat_player(dealer), table.state[:current_player], "declarer does not control dummy")
assert_equal(:not_your_turn, table.play(dummy_card, actor: table.seat_player(dummy)), "dummy played its own card")
declarer = table.seat_player(dealer)
zones = game.surface_spec(table.replay, declarer).zones
assert_equal(%w[hand dummy], zones.map(&:id), "declarer does not see both hands")
navigation = game.playable_card_navigation(table.replay, declarer)
assert_equal("dummy", navigation[:hand_id], "Z navigation does not point at dummy")
led_suit = R.card_suit(lead)
following = table.state[:hands][dummy].select { |card| R.card_suit(card) == led_suit }
if following.any?
  offsuit = table.state[:hands][dummy].find { |card| R.card_suit(card) != led_suit }
  assert_equal(:must_follow_suit, table.play(offsuit, actor: declarer), "revoke was accepted") if offsuit
end
assert_equal(:wrong_hand, table.play(table.state[:hands][dealer].first, actor: declarer, zone: "hand"), "declarer played from hand on dummy's turn")
assert_equal(:ok, table.play_lowest_legal, "declarer could not play from dummy")

# Viewer privacy: a defender sees their own hand and dummy only.
defender = table.seat_player(leader)
defender_cards = game.surface_spec(table.replay, defender).zones.flat_map { |zone| zone.cards.map(&:id) }
hidden = table.state[:hands][dealer] + table.state[:hands][R.partner_of(leader)]
assert((defender_cards & hidden).empty?, "a defender can see a hidden hand")
observation = game.bot_observation(table.replay, defender)
visible = observation["hand"] + observation["dummy"].to_a + observation["trick"].map(&:last) + observation["played"].map(&:last)
assert((visible & hidden).empty?, "bot observation leaks a hidden hand")
assert_equal(table.state[:hands][leader], observation["hand"], "the bot does not see its own hand")

# Shortcuts are unique and include the bridge-specific announcements.
keys = game.game_shortcuts(table.replay, table.state[:current_player]).map { |shortcut| [shortcut.key, shortcut.modifiers.to_a] }
%w[t h s b c f v i d k l p z].each { |key| assert(keys.include?([key, []]), "missing shortcut #{key}") }
assert(keys.include?(["l", [:control]]) && keys.include?(["z", [:shift]]), "missing modified shortcut")
texts = game.game_shortcuts(table.replay, declarer).to_h { |shortcut| [[shortcut.key, shortcut.modifiers.to_a], shortcut.message.to_s] }
assert(texts[["k", []]].include?("2 hearts"), "K does not read the contract: #{texts[['k', []]]}")
assert(texts[["d", []]].include?("Dummy"), "D does not read dummy")

# Play out the deal; it is scored and the next dealer is clockwise.
table.play_lowest_legal until table.state[:phase] != :playing
assert_equal(13, table.state[:completed_tricks].length, "not all tricks were played")
assert_equal(13, table.state[:tricks_won].sum, "trick counts are wrong")
deal = table.state[:deals].last
assert(deal[:contract].text == "2H" && deal[:entries].any?, "the deal was not scored")
table.deal
assert_equal(R.next_seat(dealer), table.state[:dealer], "the deal did not pass clockwise")

# Four passes throw the deal in without score.
table.calls("P", "P", "P", "P")
assert_equal(:round_complete, table.state[:phase], "a passed-out deal was not finished")
assert_equal(nil, table.state[:deals].last[:contract], "a passed-out deal got a contract")

# Deterministic replay from the same events.
again = game.replay(table.session, table.events, table.repository)
assert_equal(table.replay.history.map(&:text), again.history.map(&:text), "replay is not deterministic")
forged = table.events + [{ "id" => 999, "actor" => "Bob", "action" => "call", "value" => "1C" }]
assert_equal(table.events.length, game.replay(table.session, forged, table.repository).accepted_events.length, "an out-of-turn call was accepted")

# Duplicate boards follow the board's dealer and vulnerability.
duplicate = GameRoomTest::BridgeTable.new(%w[Alice Bob Carol Dave], { "variant" => "duplicate", "boards" => 4 })
assert(duplicate.state[:dealer] == 0 && duplicate.state[:vulnerability] == :none, "board 1 is wrong")
duplicate.calls("P", "P", "P", "P")
deal = duplicate.state[:deals].last
assert(deal.key?(:datum) && deal[:ns_points] + deal[:ew_points] == [deal[:ns_points], deal[:ew_points]].max, "a thrown-in board was not compared")
duplicate.deal
assert(duplicate.state[:dealer] == 1 && duplicate.state[:vulnerability] == :ns, "board 2 is wrong")

puts "PASS bridge rules: seats, auction, declarer, dummy control, privacy, shortcuts, scoring, pass-out, replay and boards"
