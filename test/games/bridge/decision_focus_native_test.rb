require_relative "../../support/game_option_editor_native"
require_relative "../../support/bridge"
include GameRoomTest::Assertions

def loop_update(*); end

hand_labels = {
  "en" => "Your hand, high card points:",
  "pl" => "Twoja ręka, punkty honorowe:",
  "cs" => "Vaše karty, figurové body:",
  "es" => "Tu mano, puntos de honor:",
  "ru" => "Ваша рука, очки за фигуры:"
}

%w[en pl cs es ru].each do |language|
  NativeOptionTest.language = language
  game = EltenGameRoom::GAME_REGISTRY.build("bridge")
  table = GameRoomTest::BridgeTable.new(game: game)
  declarer = table.replay.current_player
  layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(table.replay, declarer), phase: :active)
  bidding = layout.surface.fields_for_parts(["auction"]).first
  assert_equal(bidding, layout.form.fields[layout.form.index], "#{language}: auction not focused")
  actions = []
  layout.surface.on_action { |action| actions << action }
  assert_equal([], actions, "Focusing submitted a bid")
  bid = game.surface_spec(table.replay, declarer).parts.first.surface.options.index { |option| option.value == "1H" }
  bidding.index = bid
  bidding.trigger(:select, bid)
  assert_equal("1H", actions.last.to_h["answer"])
  assert_equal(:ok, table.act(declarer, actions.last.to_h))
  table.calls("P", "P", "P")
  layout.update(view_spec: game.game_view_spec(table.replay, declarer), history_items: [], user_items: [], users_header: "")
  assert(layout.surface.fields_for_parts(["dummy"]).empty?, "Dummy's hand exposed before the lead")
  table.play_lowest_legal
  view = game.game_view_spec(table.replay, declarer)
  assert_equal("dummy", view.decision_focus_part)
  layout.update(view_spec: view, history_items: [], user_items: [], users_header: "")
  dummy = layout.surface.fields_for_parts(["dummy"]).first
  assert_equal(dummy, layout.form.fields[layout.form.index], "#{language}: declarer still focused on own hand")
  assert(layout.decision_focus_changed?, "New dummy decision did not use the shared focus policy")
  dummy.index = 4
  layout.update(view_spec: view, history_items: [], user_items: [], users_header: "")
  dummy = layout.surface.fields_for_parts(["dummy"]).first
  assert_equal(4, dummy.index, "Refresh lost the selected card")
  assert(!layout.decision_focus_changed?, "Unchanged view refocused the hand")
  own_hand = layout.surface.fields_for_parts(["hand"]).first
  seat = table.state[:contract].declarer
  points = GameRoomGames::BridgeRules.high_card_points(table.state[:initial_hands].fetch(seat))
  expected_header = "#{hand_labels.fetch(language)} #{points}"
  assert_equal(expected_header, own_hand.header)
  assert(!dummy.header.include?(hand_labels.fetch(language)), "Dummy acquired the own-hand readout")
  layout.form.index = layout.form.fields.index(own_hand)
  before = Array(NativeOptionUI.spoken).length
  layout.form.focus
  assert_equal(1, NativeOptionUI.spoken.drop(before).count { |line| line.include?(expected_header) },
    "#{language}: focusing the hand did not read its points once")
  before = NativeOptionUI.spoken.length
  layout.update(view_spec: view, history_items: ["A new history entry"], user_items: [], users_header: "")
  assert_equal(own_hand, layout.form.fields[layout.form.index], "Refresh replaced or refocused the hand")
  assert(NativeOptionUI.spoken.drop(before).none? { |line| line.include?(expected_header) },
    "#{language}: refresh repeated the hand's points")
  all_text = layout.surface.fields.map(&:header).join(" ")
  assert(all_text.valid_encoding?, "#{language}: invalid native labels")
  if language != "en"
    assert(!all_text.include?("Dummy:") && !all_text.include?("Your hand"), "#{language}: English hand labels")
  end

  # Native Enter selection from the dummy uses the same model validation.
  selected = game.surface_spec(table.replay, declarer).zones.find { |zone| zone.id == "dummy" }.cards
  legal = game.legal_actions(table.replay, declarer).map { |action| action["card"] }
  index = selected.index { |card| legal.include?(card.value) }
  actions.clear
  layout.surface.on_action { |action| actions << action }
  dummy.index = index
  dummy.trigger(:select, index)
  assert_equal("dummy", actions.last.to_h["zone"])
  assert_equal(:ok, table.act(declarer, actions.last.to_h), "#{language}: dummy selection rejected")
  before = NativeOptionUI.spoken.length
  layout.update(view_spec: game.game_view_spec(table.replay, declarer),
    history_items: ["Dummy played a card"], user_items: [], users_header: "")
  assert_equal(own_hand, layout.form.fields[layout.form.index], "A live card update moved the own-hand focus")
  assert(NativeOptionUI.spoken.drop(before).none? { |line| line.include?(expected_header) },
    "#{language}: a card update repeated the hand's points")

  layout.form.index = layout.form.fields.index(layout.history)
  table.play_lowest_legal
  layout.update(view_spec: game.game_view_spec(table.replay, declarer), history_items: ["Reviewing a trick"], user_items: [], users_header: "")
  assert_equal(:history, layout.focus_location.first, "New own-hand decision interrupted history")
  assert_equal("hand", game.game_view_spec(table.replay, declarer).decision_focus_part)
  assert_equal(nil, game.game_view_spec(table.replay, "Watcher").decision_focus_key)
end
puts "PASS Bridge native EN/PL/CS/ES/RU: hand points on focus only, bidding Enter, dummy Enter, decision focus and history isolation"
