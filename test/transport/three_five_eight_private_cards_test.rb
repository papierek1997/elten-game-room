require_relative '../support/private_card_games'
require_relative '../../games/three_five_eight'

[true, false].each do |exchange|
  game = GameRoomGames::ThreeFiveEight.new
  # Fix the server recipe as well as the private-pool shuffle. An arbitrary
  # first dealer can produce a balanced round with no exchange entitlement;
  # that is legal play, but it must not randomly skip this test's subject.
  server_values = Array.new(16, 1)
  h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob Carol],
    options: {'card_exchange'=>exchange}, random_values: server_values.dup, clock: ClockEventContract::ManualTime.new)
  h.view('Alice').transfer_ownership(h.view('Alice').participants.find { |player| player.user == 'Carol' })
  PrivateCardGamesTest.tick(h, runners)
  3.times do |round|
    state = h.replay('Alice').state
    assert(state[:phase] == :choosing_contract, "opening failed: #{state[:phase]}")
    assert(state[:hands].values.all? { |hand| hand.size == 6 }, 'not six opening cards')
    assert(state[:complete_hands].empty? && state[:kitty].empty?, 'future cards leaked')
    assert(state[:private_draws].values.all? { |draw| draw[:count] == 6 }, 'client can request unseen ten cards')
    140.times do
      state = h.replay('Alice').state
      break if [:round_complete, :finished].include?(state[:phase])
      if state[:phase].to_s.start_with?('private_')
        PrivateCardGamesTest.tick(h, runners)
        next
      end
      user = state[:current_player]
      mine = h.replay(user)
      selection = game.legal_actions(mine, user).first
      assert(selection, "no move in #{state[:phase]} for #{user}")
      PrivateCardGamesTest.submit(h, runners, user, selection)
      PrivateCardGamesTest.assert_private(h)
      h.users.each { |viewer| game.surface_spec(h.replay(viewer), viewer) }
    end
    state = h.replay('Alice').state
    assert(state[:phase] == :round_complete, "round failed: #{state[:phase]} #{state[:private_error]}")
    previous_owner = h.replay('Alice')
    assert(game.legal_actions(previous_owner, 'Alice').none? { |action| action['action'] == 'deal' },
      'old owner offered next deal')
    context = GameRoomGames::ActionContext.new(server_random: true, table_owner: 'Carol')
    assert(game.action_for({'action'=>'deal'}, previous_owner, 'Alice', context: context).first == :not_your_turn,
      'old owner can submit next deal')
    assert(h.events('Alice').size == h.replay('Alice').accepted_events.size, 'rejected event')
    assert(h.events('Alice').any? { |event| event['action'] == 'exchange' }, 'exchange not exercised') if exchange && round > 0
    if round < 2
      h.view('Carol').next_random_values = server_values.dup
      12.times { PrivateCardGamesTest.tick(h, runners) }
    end
  end
  runners.each_value(&:close)
end
puts 'PASS 3-5-8 private cards: first six, next ten, kitty, exchanged cards, three deals, both options'
