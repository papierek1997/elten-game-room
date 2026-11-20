require_relative '../support/private_card_games'
require_relative '../../games/ninety_nine'

[2, 4, 8].each do |count|
  game = GameRoomGames::NinetyNine.new
  h, runners = PrivateCardGamesTest.create(game, users: Array.new(count) { |i| "Player#{i}" },
    options: {'starting_tokens'=>2, 'thinking_time'=>600}, clock: ClockEventContract::ManualTime.new)
  assert(h.replay(h.users.first).state[:phase] == :playing, 'private deal stalled')
  draws = 0
  300.times do
    replay = h.replay(h.users.first)
    break if replay.finished?
    if replay.state[:phase].to_s.start_with?('private_') || [:awaiting_deal, :round_complete].include?(replay.state[:phase])
      PrivateCardGamesTest.tick(h, runners)
      next
    end
    user = replay.current_player
    mine = h.replay(user)
    actions = game.legal_actions(mine, user)
    selection = actions.max_by { |action| game.bot_action_score(mine, user, action) }
    assert(selection, "no action: #{mine.state[:phase]}")
    PrivateCardGamesTest.submit(h, runners, user, selection)
    PrivateCardGamesTest.assert_private(h)
    draws += 1
  end
  rep = h.replay(h.users.first)
  assert(rep.finished?, "99 did not finish: #{rep.state[:phase]} #{rep.state[:private_error]}")
  assert(draws > 2, 'no actual play')
  assert(rep.accepted_events.size == h.events(h.users.first).size, 'rejected normal event')
  assert(h.events(h.users.first).any? { |event| event['action'] == 'private_draw' }, 'no private replacement draw')
  assert(h.users.map { |user| h.replay(user).winner }.uniq.size == 1, 'winner differs')
  runners.each_value(&:close)
end
puts 'PASS 99 private hands: two/four/eight players, replacement draws, clock, rounds, elimination and final result'
