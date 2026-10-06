require_relative "../../support/mille_bornes"
require_relative "../../../lib/game_sounds"
include MilleBornesTest

test("each winning teammate gets a positive reward and victory sound") do
  { 4 => [2], 6 => [2, 3], 8 => [2, 4] }.each do |count, team_counts|
    team_counts.each do |team_count|
      players = Array.new(count) { |seat| "Player#{seat + 1}" }
      seats = players.each_index.map { |seat| (count - 1 - seat) % team_count }
      fixture = Fixture.new(players: players, options: {
        "team_count" => team_count, "target_score" => 100,
        "team_seats" => seats, "team_players" => players
      })
      state = fixture.scenario
      game = fixture.game
      actor = players.first
      unit = seats.first
      state[:hands][actor] = %w[100:1 50:1]
      state[:tracks][unit][:miles] = 900
      state[:tracks][unit][:moving] = true
      before = fixture.snapshot(Marshal.load(Marshal.dump(state)))
      equal(:ok, fixture.play(state, actor, "play", "100:1"), "finish team race")
      after = fixture.snapshot(state)
      equal("team:#{unit}", after.winner, "winning team ID")
      players.each_with_index do |player, seat|
        winning = seats[seat] == unit
        equal(winning ? 1.0 : -1.0, game.bot_reward(after, player), "#{count}/#{team_count}: reward for #{player}")
        equal(winning ? "win_party" : "lose_party", GameRoomSounds.result_cue(game, before, after, player),
          "#{count}/#{team_count}: result sound for #{player}")
        equal(0.0, game.bot_reward(before, player), "unfinished race has no terminal reward")
        players.each_with_index do |other, other_seat|
          equal(seats[seat] == seats[other_seat], game.bot_allied?(after, player, other), "alliance follows assigned seats")
        end
      end
      equal(nil, GameRoomSounds.result_cue(game, before, after, "Observer"), "observer gets no result sound")
      equal(0.0, game.bot_reward(after, "Observer"), "observer has no team reward")
      assert(!game.bot_allied?(after, "Observer", "Observer"), "outsiders are not a team")
      assert(!game.bot_allied?(after, actor, "Observer"), "participant and outsider are not allied")
      assert(!game.bot_allied?(after, nil, nil), "missing identities are not a team")
      assert(game.bot_allied?(after, actor.downcase, actor.upcase), "participant lookup is case insensitive")
      tied = fixture.snapshot(Marshal.load(Marshal.dump(state)))
      tied.winner = nil
      tied.draw = true
      players.each { |player| equal(0.0, game.bot_reward(tied, player), "draw is neutral for all teams") }
    end
  end
end

test("individual winners and losers retain their ordinary rewards") do
  fixture = Fixture.new(options: { "target_score" => 100 })
  state = fixture.scenario
  state[:hands]["Alice"] = %w[100:1 50:1]
  state[:tracks][0][:miles] = 900
  state[:tracks][0][:moving] = true
  before = fixture.snapshot(Marshal.load(Marshal.dump(state)))
  fixture.play(state, "Alice", "play", "100:1")
  after = fixture.snapshot(state)
  equal("Alice", after.winner, "individual winner remains a participant")
  fixture.players.each do |player|
    equal(player == "Alice" ? 1.0 : -1.0, fixture.game.bot_reward(after, player), "individual reward")
    equal(player == "Alice" ? "win_party" : "lose_party", GameRoomSounds.result_cue(fixture.game, before, after, player), "individual result sound")
    equal(player == "Alice", fixture.game.bot_allied?(after, "Alice", player), "individual alliance")
  end
end
