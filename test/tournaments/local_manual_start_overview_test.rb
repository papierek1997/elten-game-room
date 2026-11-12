require_relative '../support/tournament_individual_ui'
include GameRoomTest::Assertions

state = TournamentIndividualUI.fixture(names: %w[Alpha Beta])
session = entry = nil
begin
  state[:now] = 150
  owner = -> { TournamentIndividualUI::F::OWNER }
  workspace = GameRoomTournaments::LocalWorkspace.new(program: state[:program], registry: GameRoomGames::CATALOG,
    user: owner, actor: 'Organizator', alert: ->(message) { raise message }, clock: -> { state[:now] })
  draft = {'name'=>'Manual start overview', 'game_id'=>'tic_tac_toe', 'game_options'=>{},
    'format'=>'round_robin', 'rematch'=>false, 'players_per_match'=>2, 'pairing'=>'all_combinations',
    'participants'=>[], 'participant_limit'=>4, 'windows'=>[], 'starts_at'=>0, 'deadline_at'=>0}
  published = workspace.publish(draft: draft, intent_id: 'manual-start-overview', rules: 'Local diagnostic test.',
    registration_opens_at: 100, registration_closes_at: 200, timezone: 'UTC')
  assert_equal('confirmed', published.fetch('status'))
  row = workspace.load.fetch('announcements').find do |item|
    item['publication_key'] == published.fetch('values').fetch('publication_key')
  end
  assert_equal(2, row.fetch('schema_version'))
  assert_equal(nil, GameRoomTournaments::RegistrationProjection.local_start(row))
  %w[Alpha Beta].each do |actor|
    guest = GameRoomTournaments::LocalWorkspace.new(program: state[:program], registry: GameRoomGames::CATALOG,
      user: owner, actor: actor, alert: ->(message) { raise message }, clock: -> { state[:now] })
    assert_equal('confirmed', guest.join(row.fetch('__id')).fetch('status'))
  end

  session = GameRoomTournaments::LocalReadinessSession.new
  session.choose_actor('Organizator')
  entry = GameRoomTournaments::EntryContext.new(program: state[:program], runtime: state[:program].class.app_runtime,
    owner_reader: owner, actor: 'Organizator', account_events: session.actor_events)
  arguments = {publication_ref: row.slice('publication_key').merge('author'=>row.fetch('__insertion_user')),
    context: entry, lease: entry.capture, session: session}
  before = workspace.operations
  assert_equal(false, File.exist?(state[:plans]), 'Fixture already created a plan directory')
  [[150, :registration_open], [201, :tournament_not_started]].each do |now, reason|
    state[:now] = now
    twice = Array.new(2) { workspace.tournament_overview(**arguments) }
    twice.each { |result| assert_equal({state: :blocked, reason: reason}, result) }
    assert_equal(before, workspace.operations, 'Blocked overview changed the operation journal')
    assert_equal(false, File.exist?(state[:plans]), 'Blocked overview created local plans')
    assert_equal(0, GameRoomTournaments::TournamentTiming.schedule(workspace.load.fetch('announcements').find do |item|
      item['publication_key'] == row.fetch('publication_key')
    end).fetch('starts_at'), 'Overview invented a tournament start')
  end
  puts 'PASS manual local overview: normal publication and joins, open/closed controlled reasons, no synthetic start or plan mutation'
ensure
  entry&.close
  session&.close
  state[:program].finalize
  state[:program].class.app_runtime.close
end
