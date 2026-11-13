require_relative "../../support/private_card_games"
require_relative "../../../games/french_tarot_support/french_tarot_table"

contract = ARGV.fetch(0, "petite")
game = GameRoomGames::FrenchTarotTable.new
rounds = Integer(ARGV.fetch(1, "1"))
points = Integer(ARGV.fetch(2, "0"))
h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob Carol Dan],
  options: {"round_limit" => rounds, "score_limit" => points})
begin
  PrivateCardGamesTest.assert_private(h)
  300.times do
    replay = h.replay(h.users.first)
    break if replay.finished?
    phase = replay.state[:phase]
    if %i[private_draw private_show private_prepare private_wait private_dealing round_complete].include?(phase)
      PrivateCardGamesTest.tick(h, runners)
      next
    end
    actor = replay.current_player
    assert(actor, "Missing actor in #{phase}")
    actions = game.legal_actions(h.replay(actor), actor)
    action = if phase == :bidding
      choice = replay.state[:bid_count].zero? ? contract : "pass"
      actions.find { |candidate| candidate["choice"] == choice }
    else
      actions.first
    end
    assert(action, "Missing action for #{actor} in #{phase}")
    PrivateCardGamesTest.submit(h, runners, actor, action)
  end
  scores = h.users.map do |viewer|
    replay = h.replay(viewer)
    assert(replay.finished?, "#{viewer} did not finish: #{replay.state[:phase]}")
    assert(replay.state[:play_count] == 72, "Incomplete trick play")
    assert(replay.state[:completed_deals] == (rounds.zero? ? 1 : rounds), "Wrong number of completed deals")
    replay.state[:scores]
  end
  assert(scores.uniq.one? && scores.first.values.sum.zero?, "Inconsistent settlement")
  puts "PASS French Tarot private #{contract} contract"
ensure
  runners.each_value(&:close)
end


