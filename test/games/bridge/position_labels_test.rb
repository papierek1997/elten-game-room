require_relative "../../support/bridge"
require_relative "../../support/localization"
include GameRoomTest::Assertions

%w[en pl cs es ru].each do |language|
  GameRoomTestLocalization.use_language(language)
  %w[rubber duplicate].each do |variant|
    table = GameRoomTest::BridgeTable.new(%w[Alice Bob Carol Dave], {"variant"=>variant, "boards"=>4})
    game = table.game
    original = Marshal.dump(table.replay)
    dealer = table.state[:dealer]
    viewer = table.state[:seats][dealer]
    positional_dealer = GameRoomContent.utf8(game.send(:seated_name, table.state, dealer))
    spoken = game.describe_event_for_display(table.events.last, table.repository, table.replay, viewer).join("\n")
    assert(spoken.include?(viewer), "#{language}/#{variant}: dealer's name disappeared")
    assert(!spoken.include?(positional_dealer), "#{language}/#{variant}: automatic deal repeats the dealer's position")
    assert(table.replay.history.last.text.include?(positional_dealer), "Canonical deal history was rewritten")

    # Pair identity matters for vulnerability; shortening the dealer must not
    # drop or replace any of the four vulnerability states.
    %i[none ns ew both].each do |vulnerability|
      copy = Marshal.load(original)
      copy.state[:vulnerability] = vulnerability
      text = game.describe_event_for_display(table.events.last, table.repository, copy, viewer).join("\n")
      expected = game.send(:capitalize_text, game.send(:vulnerability_text, vulnerability))
      assert(text.include?(expected), "#{language}/#{variant}: missing vulnerability #{vulnerability}")
    end
    assert_equal(original, Marshal.dump(table.replay), "Short readouts mutated the model")

    table.calls("1H", "P", "P", "P")
    declarer_seat = table.state[:contract].declarer
    declarer = table.state[:seats][declarer_seat]
    full_declarer = game.send(:seated_name, table.state, declarer_seat)
    status = game.game_shortcuts(table.replay, viewer).find { |shortcut| shortcut.key == "k" }.message
    assert(status.include?(declarer) && !status.include?(full_declarer), "#{language}: contract readout repeats the declarer's position")
    table.play_lowest_legal
    dummy_seat = game.send(:dummy_seat, table.state)
    dummy = table.state[:seats][dummy_seat]
    hand = game.game_shortcuts(table.replay, viewer).find { |shortcut| shortcut.key == "d" }.message
    assert(hand.include?(dummy) && !hand.include?(game.send(:seated_name, table.state, dummy_seat)),
      "#{language}: dummy's hand repeats its owner's position")
    cards = game.shortcut_feature_data(:table_cards_list, table.replay, viewer).fetch(:choices)
    assert(cards.all? { |choice| table.state[:seats].any? { |player| choice.label.start_with?("#{player}:") } },
      "#{language}: browsable trick still repeats compass positions")

    # Explicit orientation and pair scoring remain fully available.
    table.state[:seats].each_with_index do |player, seat|
      personal = game.shortcut_feature_data(:round_information, table.replay, player).fetch(:message)
      assert(personal.include?(game.send(:seat_name, seat)), "#{language}: I no longer identifies the player's seat")
      assert(personal.include?(game.send(:seated_name, table.state, GameRoomGames::BridgeRules.partner_of(seat))),
        "#{language}: I no longer identifies the partner's seat")
    end
    scores = game.shortcut_feature_data(:scores, table.replay, viewer).fetch(:message)
    [0, 1].each do |side|
      assert(scores.include?(game.send(:side_name, side)), "#{language}: score lost its pair label")
    end
  end
end
puts "PASS Bridge positions EN/PL/CS/ES/RU and rubber/duplicate: compact dealer/contract/dummy/cards; seats, partners, vulnerability, scores and history preserved"
