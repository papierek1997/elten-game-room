require_relative '../../support/private_card_games'
require_relative '../../../games/bridge'

users = %w[Alice Bob Carol Dave]
%w[imp mp].each do |scoring|
  game = GameRoomGames::Bridge.new
  h, runners = PrivateCardGamesTest.create(game, users: users,
    options: {'variant'=>'duplicate', 'boards'=>4, 'scoring'=>scoring}, clock: ClockEventContract::ManualTime.new)
  begin
    4.times do |index|
      16.times { PrivateCardGamesTest.tick(h, runners) }
      state = h.replay('Alice').state
      assert(state[:phase] == :bidding && state[:round] == index + 1, "fresh board stalled: #{state[:phase]}")
      assert(state[:dummy_visible] == false, 'previous dummy stayed visible')
      assert(state[:initial_hands].flatten.empty?, 'new board exposes previous initial hands')
      assert(state[:hands].values.map(&:size) == [13, 13, 13, 13], 'wrong fresh hand counts')
      PrivateCardGamesTest.assert_private(h)

      if index == 1
        h.view('Alice').transfer_ownership(h.view('Alice').participants.find { |part| part.user == 'Dave' })
        PrivateCardGamesTest.tick(h, runners)
        hand = h.replay('Bob').state[:hands]['Bob'].dup
        takes = h.core.entries.count { |entry| entry.dig('pool', 'operation') == 'take' }
        runners['Bob'].close
        h.view('Bob').leave
        h.add_client('Bob')
        assert(h.join('Bob'), 'cold return after retired board failed')
        runners['Bob'] = runner_for(h, 'Bob')
        PrivateCardGamesTest.tick(h, runners)
        assert(h.replay('Bob').state[:hands]['Bob'] == hand, 'return after retirement lost current cards')
        assert(h.core.entries.count { |entry| entry.dig('pool', 'operation') == 'take' } == takes, 'cold return redrew')
      end

      4.times do
        actor = h.replay('Alice').current_player
        PrivateCardGamesTest.submit(h, runners, actor, {'kind'=>'command', 'action'=>'call', 'call'=>'P'})
      end
      # Do not run the host again after the last disclosure: inspect this
      # exact completed board before the next ordinary automatic deal.
      users.each { |user| step(h, runners[user], user) }
      state = h.replay('Alice').state
      assert(state[:deals].size == index + 1, 'board did not finish exactly once')
      assert(state[:phase] == (index == 3 ? :finished : :round_complete), "bad board boundary: #{state[:phase]}")
      assert(state[:initial_hands].flatten.uniq.size == 52, 'audit skipped a hand')
      assert(h.replay('Alice').history.count { |entry| entry.kind == :score } == index + 1, 'score history duplicated')
      PrivateCardGamesTest.assert_private(h)
      assert(h.view('Dave').pools.size <= 1, 'old native pools accumulated between deals')
    end
    assert(h.replay('Alice').finished?, 'fixed series did not finish')
    assert(h.replay('Alice').history.count { |entry| entry.kind == :result } == 1, 'match result missing or repeated')
    assert(users.map { |user| h.replay(user).state[:scores] }.uniq.size == 1, 'cold/current clients disagree on final points')
    puts "PASS Bridge private #{scoring}: four boards, retirement, cold return, host handover and one final result"
  ensure
    runners.each_value(&:close)
  end
end
