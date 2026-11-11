require_relative '../support/mille_private'
require_relative '../../games/catalog'
require_relative '../../lib/tournaments/ordinary_match_results'

[[2, 0], [4, 2], [8, 4]].each do |count, teams|
  users = Array.new(count) { |i| "Player#{i}" }
  options = {'team_count' => teams, 'target_score' => 100, 'bot_delay' => 0}
  if teams.positive?
    options = GameRoomGames::MilleBornes.new.with_team_assignment(options, players: users,
      seats: Array.new(count) { |i| i % teams })
  end
  h, runners = MillePrivateTest.create(users: users, options: options)
  hands = h.users.flat_map { |user| h.replay(user).state[:hands][user] }
  assert(hands.size == count * 6 && hands.uniq.size == hands.size, 'duplicate physical card in initial hands')
  MillePrivateTest.assert_private(h)
  450.times do
    MillePrivateTest.tick(h, runners)
    break if h.replay(h.users.first).finished?
    h.users.each do |user|
      replay = h.replay(user)
      actions = h.game.legal_actions(replay, user)
      next if actions.empty?
      action = actions.max_by { |a| h.game.bot_action_score(replay, user, a) }
      h.as(user) do
        result = runners[user].submit(session: h.session, replay: replay, selection: action, actor: user)
        assert(result.first == :ok, 'private round move rejected')
      end
    end
    MillePrivateTest.assert_private(h)
  end
  assert(h.replay(h.users.first).finished?, "#{count}-player private game did not finish")
  assert(h.replay(h.users.first).accepted_events.size == h.events(h.users.first).size, 'normal game rejected a persisted action')
  state = h.replay(h.users.first).state
  players = h.users.each_with_index.map do |user, seat|
    person = {'account' => user.downcase, 'username' => user, 'seat' => seat}
    person['team'] = "team-#{state[:seats][seat]}" if teams.positive?
    person
  end
  binding = {'match_id' => 'private-result', 'leg' => 1, 'table' => h.table.slice('__id', '__live_session_id'),
    'session_id' => h.session['__id'], 'game_id' => h.game.id,
    'options' => h.game.options_from_json(h.session['options']), 'players' => players}
  exports = h.users.map do |user|
    h.as(user) do
      GameRoomTournaments::OrdinaryMatchResults.read(repository: h.repositories[user],
        registry: GameRoomGames::CATALOG, transport: h.transports[user], table: h.table, binding: binding)
    end
  end
  assert(exports.uniq.size == 1 && exports.first, 'private views produced different tournament results')
  assert(exports.first['summary']['participants'].size == (teams.positive? ? teams : count), 'wrong tournament scoring units')
  assert(!JSON.generate(exports.first).match?(/private_draws|hidden:|hands/), 'result exports private state')
  runners.each_value(&:close)
  puts "PASS private full game: #{count} players, #{teams} teams"
end

# Keep a tiny, finishable custom deck alive by discarding; it must recycle
# without making the old private cards public, including after a fresh local
# reconstruction. An unfinishable deck now ends through the impasse rule.
types = GameRoomGames::MilleBornes::DECK_COUNTS.keys
options = types.to_h { |type| ["#{type}_cards", type == '100' ? 13 : (type == 'go' ? 1 : 0)] }.merge(
  'custom_deck' => true, 'include_safeties' => false, 'recycle_discard' => true)
h, runners = MillePrivateTest.create(options: options)
12.times do
  h.users.each do |user|
    5.times { MillePrivateTest.tick(h, runners) }
    actions = h.game.legal_actions(h.replay(user), user)
    next if actions.empty?
    action = actions.find { |a| a['action'] == 'draw' } || actions.find { |a| a['action'] == 'discard' }
    h.as(user) { assert(runners[user].submit(session: h.session, replay: h.replay(user), selection: action, actor: user).first == :ok, 'custom move failed') }
    MillePrivateTest.assert_private(h)
  end
end
assert(h.replay('Alice').state[:recycle_count] >= 3, 'custom deck did not recycle repeatedly')
runners.each_value(&:close)
puts 'PASS private custom deck: repeated recycling and private hands'

options = types.to_h { |type| ["#{type}_cards", type == '25' ? 24 : (type == 'go' ? 6 : 0)] }.merge(
  'custom_deck' => true, 'include_safeties' => false, 'target_score' => 600)
h, runners = MillePrivateTest.create(options: options)
400.times do
  MillePrivateTest.tick(h, runners)
  break if h.replay('Alice').finished?
  h.users.each do |user|
    replay = h.replay(user)
    actions = h.game.legal_actions(replay, user)
    next if actions.empty?
    action = actions.max_by { |candidate| h.game.bot_action_score(replay, user, candidate) }
    h.as(user) { assert(runners[user].submit(session: h.session, replay: replay, selection: action, actor: user).first == :ok, 'multi-round move rejected') }
  end
  MillePrivateTest.assert_private(h)
  assert(h.view('Alice').pools.size == 1, 'previous round left native pools behind')
  active_pools = h.view('Alice').pools.map(&:id)
  h.users.each do |user|
    store = h.transports.fetch(user).instance_variable_get(:@live_store)
    room = store.instance_variable_get(:@rooms).fetch(h.table.fetch('__id'))
    assert((room.verified_pools.keys - active_pools).empty?, 'fresh round retained obsolete reader validation cache')
    assert(room.private_draws.keys.all? { |key| active_pools.include?(key[1]) }, 'fresh round retained obsolete reader draw cache')
  end
end
assert(h.replay('Alice').finished? && h.replay('Alice').state[:round] > 1, 'private match did not cross a round boundary')
runners.each_value(&:close)
puts 'PASS private multi-round match: old pools retired, fresh hands and complete game'
