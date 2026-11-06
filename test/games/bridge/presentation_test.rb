require_relative "../../support/bridge"
require_relative "../../../lib/game_layout_spec"
require_relative "../../../lib/game_sounds"
include GameRoomTest::Assertions

table = GameRoomTest::BridgeTable.new
game = table.game
viewer = table.replay.current_player
choice = game.surface_spec(table.replay, viewer).parts.first.surface
assert_equal("Choose your call.", choice.prompt)
assert_equal("pass", choice.options.first.label)
assert_equal("1 heart: 7 tricks", choice.options.find { |option| option.value == "1H" }.label)
assert_equal("7 no trump: 13 tricks", choice.options.find { |option| option.value == "7N" }.label)
assert_equal("auction", game.game_view_spec(table.replay, viewer).decision_focus_part)
assert_equal(nil, game.game_view_spec(table.replay, "Watcher").decision_focus_key)

bidder = viewer
table.calls("1H", "X", "XX")
data = game.shortcut_feature_data(:bidding, table.replay, table.replay.current_player)
assert_equal("Last bid: 1 heart redoubled by #{bidder}.", data[:prompt])
assert_equal(game.surface_spec(table.replay, table.replay.current_player).parts.first.surface.prompt, data[:prompt])
assert(!data[:prompt].include?("Auction:"), "B repeats the entire auction")
assert_equal(game.surface_spec(table.replay, table.replay.current_player).parts.first.surface.options.map(&:value),
  data[:choices].map(&:value), "Inline and shortcut bidding offer different calls")
table.calls("P", "P", "P")
declarer = table.state[:seats][table.state[:contract].declarer]
dummy = table.state[:seats][GameRoomGames::BridgeRules.partner_of(table.state[:contract].declarer)]
speech = game.describe_event_for_display(table.events.last, table.repository, table.replay, declarer)
assert(speech.last.include?("needing 7 tricks"), "Contract does not explain the target")
assert(!speech.join.include?("opening lead"), "Contract repeats the next player's turn")
assert(!game.game_view_spec(table.replay, declarer).surface.zones.any? { |zone| zone.id == "dummy" }, "Hidden dummy leaked into controls")
table.play_lowest_legal
original_history = Marshal.dump(table.replay.history)
speech = game.describe_event_for_display(table.events.last, table.repository, table.replay, declarer)
assert_equal(2, speech.length, "Opening lead should announce the card and expose dummy")
assert_equal("Dummy's hand is exposed: #{dummy}.", speech.last)
assert(!speech.join.include?("clubs:"), "Automatic speech reads dummy's full hand")
assert_equal(original_history, Marshal.dump(table.replay.history), "Concise speech rewrote canonical history")
assert(game.describe_event(table.events.last, table.repository, table.replay, declarer).join.include?("clubs:"), "Detailed dummy vanished from history")
assert_equal("dummy", game.game_view_spec(table.replay, declarer).decision_focus_part)
assert_equal(nil, game.game_view_spec(table.replay, dummy).decision_focus_key, "Dummy got control of the declarer's decision")
table.play_lowest_legal
assert(game.describe_event_for_display(table.events.last, table.repository, table.replay, declarer).first.start_with?("Dummy:"),
  "Dummy's play is confused with declarer's own hand")
assert(game.shortcut_feature_data(:table_cards, table.replay, declarer)[:message].include?(dummy),
  "C uses only compass positions instead of players")

# A player who wins with the fourth card also has a fresh opening decision.
found_consecutive_decision = false
while table.state[:phase] == :playing
  before = table.replay
  table.play_lowest_legal
  after = table.replay
  actor = before.current_player
  if after.state[:completed_tricks].length > before.state[:completed_tricks].length
    speech = game.describe_event_for_display(table.events.last, table.repository, after, actor)
    trick = speech.find { |text| text.include?("wins the trick") }
    assert(trick && !trick.include?("Tricks:"), "Trick repeats the running score")
    if after.current_player == actor
      assert(game.required_decision_key(before, actor) != game.required_decision_key(after, actor), "New lead was mistaken for the previous decision")
      found_consecutive_decision = true
    end
  end
end
assert(found_consecutive_decision, "Fixture did not cover a fourth-card winner leading next")
speech = game.describe_event_for_display(table.events.last, table.repository, table.replay, declarer)
assert(speech.last.include?("Points this deal:"), "Missing concise deal score")
assert(speech.last.length < table.replay.history.find { |entry| entry.kind == :score }.text.length, "Deal score was not shortened")
assert(!speech.last.include?("below the line"), "Automatic score recites accounting details")
assert(game.shortcut_feature_data(:scores, table.replay, declarer)[:message].include?("below"), "Detailed scores are no longer available")

%w[C D H S N].each do |strain|
  table = GameRoomTest::BridgeTable.new
  table.calls("1#{strain}", "P", "P", "P")
  count = 0
  while table.state[:phase] == :playing
    before = table.replay
    table.play_lowest_legal
    after = table.replay
    card = table.events.last.fetch("value")
    cue = GameRoomSounds.event_cue(game: table.game, event: table.events.last, before_replay: before, after_replay: after,
      repository: table.repository, viewer: "Alice", include_result: false)
    trump = strain != "N" && card.end_with?(strain)
    assert_equal(trump ? ["play", "draw2"] : "play", cue, "Wrong cue for #{card} in #{strain}")
    count += 1 if trump
  end
  assert_equal(strain == "N" ? 0 : 13, count, "Did not check the full trump suit including dummy")
  assert_equal(nil, table.game.event_sound_cues(event: {"action"=>"play", "value"=>"AS"}, before_replay: table.replay,
    after_replay: table.replay, history: [], viewer: "Alice", random_variant: nil), "Rejected play sounded")
end
puts "PASS Bridge presentation: concise speech, intact history, bidding context/targets, hand decisions and all four trump suits/no trump"
