require_relative "../../support/private_card_games"
require_relative "../../../games/belote_support/belote_table"

game = GameRoomGames::BeloteTable.new
[["classic", false], ["coinchee", false], ["coinchee", true]].each do |variant, two_stage|
h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob Carol Dan], options: {"variant" => variant, "coinchee_two_stage" => two_stage})
begin
  12.times { PrivateCardGamesTest.tick(h, runners) }
  PrivateCardGamesTest.assert_private(h)
  replay = h.replay(h.users.first)
  assert(replay.state[:phase] == :bidding, "Expected bidding, got #{replay.state[:phase]}")
  assert(replay.state[:hands].values.all? { |hand| hand.size == (variant == "classic" || two_stage ? 5 : 8) }, "Expected five cards before bidding")
  actor = replay.current_player
  bid = game.legal_actions(h.replay(actor), actor).find { |action| action["choice"] != "pass" }
  PrivateCardGamesTest.submit(h, runners, actor, bid)
  if variant == "coinchee"
    %w[double redouble pass pass pass].each do |choice|
      actor = h.replay(h.users.first).current_player
      action = game.legal_actions(h.replay(actor), actor).find { |candidate| candidate["choice"] == choice }
      assert(action, "Missing Coinchée choice #{choice}")
      PrivateCardGamesTest.submit(h, runners, actor, action)
    end
    assert(h.replay(h.users.first).state[:multiplier] == 4, "Recontra did not quadruple stake")
  end
  12.times { PrivateCardGamesTest.tick(h, runners) }
  PrivateCardGamesTest.assert_private(h)
  assert(h.replay(h.users.first).state[:hands].values.all? { |hand| hand.size == 8 }, "Expected eight cards after bidding")
  36.times do
    break if h.replay(h.users.first).state[:phase] == :round_complete
    actor = h.replay(h.users.first).current_player
    assert(actor, "Missing player during trick play")
    action = game.legal_actions(h.replay(actor), actor).first
    assert(action, "Missing card action for #{actor}: #{h.replay(actor).state.slice(:phase,:private_error,:pending_meld,:play_count,:current_player)}")
    PrivateCardGamesTest.submit(h, runners, actor, action)
  end
  scores = h.users.map do |viewer|
    replay = h.replay(viewer)
    assert(replay.state[:phase] == :round_complete, "Wrong final phase for #{viewer}")
    results = replay.history.select { |entry| entry.kind == :round_result }
    assert(results.size == 3, "Missing contract and team results")
    tricks = replay.history.select { |entry| entry.kind == :trick }
    assert(tricks.size == 8 && tricks.all? { |entry| entry.text.include?("bierze") }, "Missing trick announcements")
    assert(tricks.first.text.include?("wychodzi") && !tricks.last.text.include?("wychodzi"), "Wrong next lead announcement")
    assert(replay.state[:trick_points].values.sum == 162, "Wrong trick total for #{viewer}")
    replay.state[:scores]
  end
  assert(scores.uniq.one?, "Viewers disagree on contract settlement")
  puts "PASS Belote private deal, bidding and eight tricks"
ensure
  runners.each_value(&:close)
end

end
