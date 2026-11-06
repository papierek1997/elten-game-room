require_relative '../support/private_card_games'
require_relative '../../games/tysiac'

def private_redeal_table(kind)
  game, users = GameRoomGames::Tysiac.new, %w[Alice Bob Carol]
  marker = {'publication_ref'=>{'author'=>'Alice','publication_key'=>'redeal'},'schedule_id'=>'c'*64,'match_id'=>'d'*64,'leg'=>1}
  h = NativeRoomHarness.new(game: game, users: users, tournament: marker,
    options: game.default_options.merge('redeal_talon_nines'=>true,'bot_delay'=>0))
  h.start
  h.view('Alice').next_random_values = Array.new(16, 1)
  runners = users.to_h { |user| [user, runner_for(h, user)] }
  6.times do
    step(h, runners['Alice'], 'Alice')
    break if h.replay('Alice').state[:private_pool]
  end
  state = h.replay('Alice').state
  pool = state.fetch(:private_pool)
  cards = state.fetch(:private_pools).fetch(pool).fetch(:cards)
  nines, others = (1..cards.size).partition { |i| cards[i - 1].start_with?('9') }
  order = if kind == :hand
    others.take(7) + nines + others.drop(7)
  else
    others.take(19) + nines.take(2) + [others.last] + nines.drop(2)
  end
  assert(order.sort == (1..24).to_a, 'Invalid private fixture deck')
  h.view('Alice').pool_data(pool)[:remaining] = order
  16.times { PrivateCardGamesTest.tick(h, runners) }
  assert(h.replay('Alice').state[:phase] == :bidding, 'Private redeal opening stalled')
  [h, runners]
end

h, runners = private_redeal_table(:hand)
begin
  PrivateCardGamesTest.assert_private(h)
  bob = h.replay('Bob')
  assert(bob.state[:hands]['Bob'].count { |card| card.start_with?('9') } == 4, 'Fixture did not deal four nines to Bob')
  # A claim has no authenticated card values and cannot cancel a private deal.
  forged = GameRoomPrivateCards.command('redeal', 'four_nines', operation: 'claim')
  h.write('Alice', [forged])
  assert(h.replay('Alice').state[:phase] == :bidding, 'Unproved four-nines claim cancelled a deal')
  PrivateCardGamesTest.submit(h, runners, 'Bob', {'kind'=>'command','action'=>'redeal','reason'=>'four_nines'})
  h.users.each do |user|
    state = h.replay(user).state
    assert(state[:phase] == :redeal && !state[:private_error], 'Proved four-nines claim was not accepted')
    assert(state[:private_public].sort == %w[9C 9D 9H 9S], 'Redeal exposed more than its four proof cards')
  end
  16.times { PrivateCardGamesTest.tick(h, runners) }
  state = h.replay('Alice').state
  assert(state[:round] == 1 && state[:dealer_index] == 0 && state[:phase] == :bidding, 'Private redeal advanced/stalled the round')
  PrivateCardGamesTest.assert_private(h)
ensure
  runners.each_value(&:close)
end

h, runners = private_redeal_table(:talon)
begin
  %w[100 pass pass].each do |bid|
    user = h.replay('Alice').current_player
    PrivateCardGamesTest.submit(h, runners, user, {'kind'=>'command','action'=>'bid','bid'=>bid})
    8.times { PrivateCardGamesTest.tick(h, runners) }
  end
  state = h.replay('Bob').state
  assert(state[:phase] == :passing && state[:talon].count { |card| card.start_with?('9') } >= 2, 'Fixture did not expose the talon')
  PrivateCardGamesTest.submit(h, runners, 'Bob', {'kind'=>'command','action'=>'redeal','reason'=>'talon_nines'})
  assert(h.users.all? { |user| h.replay(user).state[:phase] == :redeal }, 'Public talon redeal did not converge')
  16.times { PrivateCardGamesTest.tick(h, runners) }
  PrivateCardGamesTest.assert_private(h)
  assert(h.replay('Alice').state[:dealer_index] == 0, 'Private talon redeal changed the dealer')
ensure
  runners.each_value(&:close)
end
puts 'PASS Tysiac private redeals: native proof, forged claim rejection, minimal reveal, fresh pool, talon and preserved dealer'
