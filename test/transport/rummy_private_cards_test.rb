require_relative '../support/private_card_games'
require_relative '../../games/rummy'

game = GameRoomGames::Rummy.new
[[2, false], [3, true]].each do |count, elimination|
  users = Array.new(count) { |index| "Player#{index}" }
  h, runners = PrivateCardGamesTest.create(game, users: users,
    options: {'elimination'=>elimination, 'score_limit'=>50, 'first_meld'=>15, 'manipulation'=>true},
    clock: ClockEventContract::ManualTime.new)
  PrivateCardGamesTest.assert_private(h)
  moves = []
  450.times do |index|
    PrivateCardGamesTest.tick(h, runners)
    replay = h.replay(users.first)
    break if replay.finished?
    if index == 20
      h.view(users.first).transfer_ownership(h.view(users.first).participants.find { |entry| entry.user == users.last })
      expected = h.replay(users[1]).state[:hands][users[1]].sort
      runners[users[1]].close
      h.view(users[1]).leave
      h.add_client(users[1])
      assert(h.join(users[1]), 'return failed')
      runners[users[1]] = runner_for(h, users[1])
      assert(h.replay(users[1]).state[:hands][users[1]].sort == expected, 'returned hand changed')
      next # Rebuild runner/UI revisions after membership and owner changes.
    end
    next if replay.state[:phase].to_s.start_with?('private_')
    actor = replay.current_player
    next unless actor
    mine = h.replay(actor)
    choices = game.legal_actions(mine, actor)
    assert(choices.any?, "no move in #{mine.state[:phase]}")
    choice = choices.max_by { |action| game.bot_action_score(mine, actor, action) }
    moves << choice['action']
    PrivateCardGamesTest.submit(h, runners, actor, choice)
    PrivateCardGamesTest.assert_private(h)
  end
  final = h.replay(users.first)
  assert(final.finished?, 'private Rummy did not finish')
  assert(moves.include?('meld') && moves.include?('draw'), 'draws and melds not covered')
  assert(final.accepted_events.size == h.events(users.first).size, 'payload fragment or proof rejected')
  PrivateCardGamesTest.assert_private(h)
  runners.each_value(&:close)
end
puts 'PASS private Rummy: payload melds, draws, disclosure/scoring, ordinary rules, host change and cold return'
