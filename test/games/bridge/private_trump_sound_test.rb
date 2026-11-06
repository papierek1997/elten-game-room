require_relative "../../support/private_card_games"
require_relative "../../../games/bridge"
require_relative "../../../lib/game_sounds"

game = GameRoomGames::Bridge.new
users = %w[Alice Bob Carol Dave]
h, runners = PrivateCardGamesTest.create(game, users: users)
begin
  4.times do |index|
    actor = h.replay("Alice").current_player
    PrivateCardGamesTest.submit(h, runners, actor, {"kind"=>"command", "action"=>"call", "call"=>index.zero? ? "1H" : "P"})
  end
  own_trumps = dummy_trumps = 0
  plays = 0
  loop do
    replay = h.replay("Alice")
    break unless replay.state[:phase] == :playing
    actor = replay.current_player
    before = users.to_h { |user| [user, h.replay(user)] }
    seat = replay.state[:seat_to_play]
    action = game.legal_actions(h.replay(actor), actor).first
    PrivateCardGamesTest.submit(h, runners, actor, action)
    users.each do |user|
      after = h.replay(user)
      entry = after.history.reverse.find { |item| item.kind == :play }
      event = h.events(user).find { |item| h.repositories[user].event_id(item).to_i == entry.event_id.to_i }
      assert(event, "Cannot find the authenticated card-reveal event")
      cue = GameRoomSounds.event_cue(game: game, event: event, before_replay: before[user], after_replay: after,
        repository: h.repositories[user], viewer: user, include_result: false)
      assert(cue == (action["card"].end_with?("H") ? ["play", "draw2"] : "play"),
        "Private receipt/card mismatch or missing trump cue for #{user}")
    end
    if action["card"].end_with?("H")
      if seat == game.send(:dummy_seat, replay.state)
        dummy_trumps += 1
      else
        own_trumps += 1
      end
    end
    plays += 1
    4.times { PrivateCardGamesTest.tick(h, runners) } if h.replay("Alice").state[:phase] == :private_show
    PrivateCardGamesTest.assert_private(h)
  end
  assert(plays == 52 && own_trumps > 0 && dummy_trumps > 0, "Did not cover ordinary and dummy private trumps")
  assert(own_trumps + dummy_trumps == 13, "Private deal did not sound all 13 trumps exactly once")
  puts "PASS Bridge private audio: authenticated card reveals, dummy and own trumps, four viewer projections and privacy"
ensure
  runners.each_value(&:close)
end
