require_relative '../support/mille_private'

# Keep the tiny pool (two draws after the opening hands), but enough unused
# distance to reach 1000. A 13 x 25-mile deck now correctly settles an impasse
# instead of remaining available for a many-recycling lifetime test.
options = GameRoomGames::MilleBornes::DECK_COUNTS.keys.to_h do |type|
  ["#{type}_cards", type == '100' ? 13 : (type == 'go' ? 1 : 0)]
end.merge('custom_deck' => true, 'include_safeties' => false, 'recycle_discard' => true)
h, runners = MillePrivateTest.create(options: options)
assert(!h.game.send(:distance_finish_impossible?, h.replay('Alice').state), 'retirement fixture cannot reach 1000 miles')
70.times do
  h.users.each do |user|
    4.times { MillePrivateTest.tick(h, runners) }
    next unless h.replay(user).state[:current_player] == user
    MillePrivateTest.move(h, runners, user, 'draw')
    MillePrivateTest.move(h, runners, user, 'discard')
  end
end
MillePrivateTest.assert_private(h)
replay = h.replay('Alice')
state = replay.state
assert(state[:recycle_count] > 32, 'test did not exceed the lifetime pool limit')
assert(h.view('Alice').pools.length <= 12, 'obsolete native pools accumulated')
assert(state[:private_retired].length > 32, 'retired identities were not recorded')
active_pools = h.view('Alice').pools.map(&:id)
h.users.each do |user|
  store = h.transports.fetch(user).instance_variable_get(:@live_store)
  room = store.instance_variable_get(:@rooms).fetch(h.table.fetch('__id'))
  assert(room.private_draws.keys.none? { |key| !active_pools.include?(key[1]) }, 'obsolete private draw cache accumulated on a reader')
  assert((room.verified_pools.keys - active_pools).empty?, 'obsolete verified pool cache accumulated on a reader')
end

# A genuinely full set of pools with cards still held must stop explicitly,
# without deleting anyone's hand or repeatedly requesting an impossible pool.
state[:phase] = :awaiting_draw
state[:draw_pile] = []
state[:discard] = ['100:1']
state[:private_retired] = []
state[:private_pools] = (1..32).to_h { |i| [i.to_s.rjust(32, '0'), {cards: ['100:1'], remaining: 0}] }
state[:private_draws] = state[:private_pools].keys.to_h { |id| [id, {pool: id, count: 1, used: []}] }
history = []
h.game.send(:finish_private_replay, state, history, 100)
assert(state[:private_error] == :pool_limit, 'pool limit did not stop the game')
assert(history.one? && history.first.kind == :private_error, 'pool limit was not announced')
assert(h.game.automatic_action(replay, 'Alice', context: runners['Alice'].send(:context)).nil?, 'capacity error keeps sending requests')
runners.each_value(&:close)
puts 'PASS private retirement: more than 32 recyclings; held cards retained; real capacity limit announced'
