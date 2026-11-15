require_relative "../../support/private_card_games"
require_relative "../../../games/jass_support/jass_table"

game = GameRoomGames::JassTable.new
h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob Carol Dan])
begin
  PrivateCardGamesTest.assert_private(h)
  37.times do
    actor = h.replay(h.users.first).current_player
    assert(actor, "Missing actor")
    action = game.legal_actions(h.replay(actor), actor).first
    assert(action, "Missing legal action")
    PrivateCardGamesTest.submit(h, runners, actor, action)
  end
  h.users.each do |viewer|
    replay = h.replay(viewer)
    assert(!replay.state[:private_error], "Private round audit failed: #{replay.state[:private_round_actions].map { |e| e[%q[action]] }.tally}; draws #{replay.state[:private_draws].values.map { |d| [d[:initial], d[:used].size, d[:count]] }}; start #{replay.state[:private_round_start].values_at(:phase,:current_player)}")
    assert(replay.state[:phase] == :round_complete, "Round did not finish")
    assert(replay.state[:scores].values.sum == 157, "Incorrect score")
  end
  puts "PASS Jass private deal and complete round"
ensure
  runners.each_value(&:close)
end
