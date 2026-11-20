require 'tmpdir'
require_relative '../../support/private_card_games'
require_relative '../../support/tournament_server_plan_table'
require_relative '../../../games/catalog'
require_relative '../../../lib/tournaments/ordinary_match_service'

users = %w[Alice Bob Carol Dave]
game = GameRoomGames::Bridge.new
options = game.normalize_options('variant'=>'duplicate', 'boards'=>4, 'scoring'=>'imp')
h = NativeRoomHarness.new(game: game, users: users, options: options, clock: ClockEventContract::ManualTime.new)
programs = users.to_h { |user| [user, ProgramDouble.new(h.broker.endpoint(user))] }
lobbies = users.to_h do |user|
  [user, LobbyRepository.new(programs[user], transport: h.transports[user], server_tables: Object.new)]
end
h.as('Alice') { lobbies['Alice'].close_table(h.table) }
t = GameRoomTournaments
documents = TournamentServerPlanTableSupport::Table.new(user: -> { 'Alice' })
candidate = {
  'schedule_id'=>'a'*64, 'publication_digest'=>'b'*64, 'roster_generation'=>'c'*64,
  'game_id'=>game.id, 'publication_ref'=>{'author'=>'alice', 'publication_key'=>'bridge'},
  'format'=>'round_robin', 'players_per_match'=>4, 'game_options'=>options,
  'roster'=>users.map(&:downcase), 'team_template'=>[0, 1, 0, 1],
  'membership'=>{'version'=>1, 'kind'=>'fixed-teams', 'units'=>[
    {'unit_id'=>'red', 'accounts'=>%w[alice bob]},
    {'unit_id'=>'blue', 'accounts'=>%w[carol dave]}
  ]},
  'matches'=>[{'match_id'=>'d'*64, 'leg'=>1, 'number'=>1,
    'players'=>users.map(&:downcase), 'unit_ids'=>%w[red blue]}]
}

Dir.mktmpdir('bridge-team-') do |directory|
  services = users.to_h do |user|
    journal = t::OperationJournal.new(directory: File.join(directory, user), owner: user.downcase,
      backend_identity: 'bridge-local-native')
    [user, t::OrdinaryMatchService.new(program: programs[user], registry: GameRoomGames::CATALOG,
      lobby: lobbies[user], games: h.repositories[user], transport: h.transports[user],
      table: documents.for_user(user), journal: journal,
      source: -> { {'candidate'=>candidate, 'tournament_id'=>5} }, user: -> { user })]
  end
  runners = {}
  begin
    room = h.as('Alice') { services['Alice'].open_match(match_id: 'd'*64, leg: 1) }
    h.instance_variable_set(:@table, room)
    users.drop(1).each do |user|
      h.as(user) { services[user].open_match(match_id: 'd'*64, leg: 1) }
    end
    native_options = JSON.parse(room['game_options'])
    parameters = services['Alice'].start_parameters(room, players: users, options: native_options)
    assert_equal(%w[Alice Carol Bob Dave], parameters[:players], 'fixed partners do not sit opposite')
    users.permutation.each do |arrivals|
      displayed = game.options_for_team_roster(game.new_game_options(native_options), players: arrivals)
      assert_equal(parameters, services['Alice'].start_parameters(room, players: arrivals, options: displayed),
        'arrival order changed fixed partnerships')
    end
    h.as('Alice') do
      session = h.repositories['Alice'].start_session(table: room, game: game.id, players: users,
        options: JSON.generate(native_options), **parameters)
      h.instance_variable_set(:@session, session)
    end
    assert_equal(GameRoomPrivateCards::VERSION, h.view('Alice').metadata['private_cards'],
      'ordinary tournament start did not enable private hands')
    contexts = users.to_h do |user|
      [user, GameRoomGames::ActionContext.new(hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
        random_source: GameRoomRandom::LocalSecureSource.new)]
    end
    runners = users.to_h do |user|
      [user, h.as(user) do
        runner = GameRoomSessionRunner.new(program: programs[user], transport: h.transports[user],
          repository: h.repositories[user], game: game, session: h.session, table: room,
          owner: 'Alice', viewer: user, room_snapshot_provider: -> { lobbies[user].snapshot_for(room) },
          covered: -> { true }, context: contexts[user],
          completion_observer: ->(session, replay, events) { services[user].observe(room, session, replay, events) })
        runner.instance_variable_set(:@clock, h.clock.session_clock)
        runner
      end]
    end
    100.times do
      PrivateCardGamesTest.tick(h, runners)
      replay = h.replay('Alice')
      break if replay.finished?
      next unless replay.state[:phase] == :bidding

      PrivateCardGamesTest.assert_private(h)
      actor = replay.current_player
      PrivateCardGamesTest.submit(h, runners, actor, {'kind'=>'command', 'action'=>'call', 'call'=>'P'})
    end
    assert(h.replay('Alice').finished?, 'four-board tournament did not finish')
    PrivateCardGamesTest.tick(h, runners)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    view = nil
    loop do
      services.each_value do |service|
        error = service.take_error
        raise error if error
      end
      view = services['Dave'].result_view
      break if view['results'].size == 1
      raise 'Bridge tournament result was not published' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
    summary = view['results'].first['summary']
    assert_equal(%w[blue red], summary['participants'], 'native team IDs were not mapped to tournament teams')
    assert_equal(%w[blue red], view['standings'].map { |row| row['unit'] }.sort)
    assert(view['standings'].all? { |row| row['played'] == 1 }, 'result counted more than once')
    assert(users.map { |user| services[user].result_view }.uniq.size == 1, 'team result differs among clients')
    assert_equal(4, h.replay('Alice').state[:deals].size, 'result bypassed a board audit')
    assert(!h.replay('Alice').state[:private_error], 'invalid private round published a result')
    puts 'PASS Bridge local native tournament: fixed teams, all arrival orders, private four-board game, one shared team result'
  ensure
    runners.each_value(&:close)
    services.each_value(&:close)
  end
end
