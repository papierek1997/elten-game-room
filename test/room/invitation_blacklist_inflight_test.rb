require_relative '../support/invitation_fresh_endpoint'
require_relative '../support/app_notification_models'
require_relative '../support/temporary_directory'
require_relative '../support/tournament_server_plan_table'
require_relative '../../lib/tournaments/ordinary_match_service'

class BlacklistInflightApp < InvitationAppDriver
  attr_accessor :block_at, :fixture_service, :choice
  attr_reader :entered, :membership_attempts
  def initialize(*args, **options)
    super
    @invitations, @server_tables = nil, AvailableTables.new
    @membership_attempts = []
    initialize_services
  end
  def register_room_presence; end
  def record_statistics_visit; end
  def check_server_table_access(announce: true); end
  def run_program_interface(row); @entered = row; end
  def select_notification_invitation_action; choice || :accept; end
  def ordinary_tournament_service(*, **); fixture_service; end
  def block_sender(stage)
    return unless @block_at == stage
    @block_at = nil
    self.class.remember_settings('invitation_blacklist' => ['OWNER'])
  end
  def run_network_task(title, **options, &work)
    block_sender(:loading) if title == 'Loading invitations'
    block_sender(:accepting) if title == 'Accepting invitation'
    block_sender(:rejecting) if title == 'Rejecting invitation'
    result = super
    block_sender(:connected) if title == 'Connecting to Elten'
    block_sender(:lookup) if title == 'Checking invitation'
    block_sender(:delivery) if title == 'Accepting invitation'
    result
  end
  def pending_invitations_for_table(row)
    result = super
    block_sender(:pending)
    result
  end
  def establish_invited_table_transport(row)
    @membership_attempts << row['__id']
    result = super
    block_sender(:established)
    result
  end
end

GameRoomLocalization.boot(settings: {}, host_language: 'en')
BlacklistInflightRaw = Struct.new(:id, :cat, :app_uuid, :date, :update_time, :revoked, :payload, :alert, keyword_init: true)
def native_blacklist_notice(notice)
  Programs.app_notification_from(BlacklistInflightRaw.new(id: notice.id, cat: 'app', app_uuid: notice.app_uuid,
    date: Time.now.to_i, revoked: false, alert: '', payload: {
      'type' => notice.type, 'sender' => notice.sender, 'metadata' => notice.metadata}))
end

def blacklist_inflight_fixture(private_table)
  BlacklistInflightApp.remember_settings('invitation_blacklist' => [])
  broker, gateway = NativeLiveSessionsBroker.new, DurableNoticeGateway.new
  owner, guest = %w[Owner Guest].map { |user| BlacklistInflightApp.new(broker, user, gateway) }
  $game_room_test_user = 'Owner'
  table = owner.transport.create_room(name: 'Tournament match', game: 'uno', owner: 'Owner',
    game_options: '{}', private_table: private_table)
  assert(owner.send(:deliver_table_invitation, table, 'Guest').created?, 'Ordinary invitation delivery failed')
  $game_room_test_user = 'Guest'
  invitation = guest.send(:load_pending_invitations).first.fetch(:invitation)
  [broker, gateway, owner, guest, table, invitation]
end

checks = 0
[false, true].product([:none, :before_open, :connected, :loading, :lookup, :accepting, :pending, :established, :delivery]).each do |private_table, stage|
  broker, gateway, _owner, guest, table, = blacklist_inflight_fixture(private_table)
  notice = gateway.rows['Guest'].first
  guest.block_at = stage
  guest.block_sender(:before_open)
  assert(guest.notification_action(:open_invitation, native_blacklist_notice(notice)), 'Notification was not handled')
  accepted = [:none, :established, :delivery].include?(stage)
  label = [private_table, stage].inspect
  assert(!guest.entered.nil? == accepted, "Entry result disagrees with admission boundary #{label}")
  assert(broker.cores.fetch(table['__live_session_id']).participants.key?('guest') == accepted, "Native membership disagrees #{label}")
  assert(notice.revoked == accepted && guest.sent.size == (accepted ? 1 : 0), "Blocked invitation was answered or revoked #{label}")
  assert(guest.membership_attempts.size == (accepted ? 1 : 0), "Blocked invitation started membership work #{label}")
  assert(guest.alerts.empty? && guest.errors.empty?, "Blacklist produced an availability/network error #{label}: #{guest.alerts} #{guest.errors}")
  unless accepted
    BlacklistInflightApp.remember_settings('invitation_blacklist' => [])
    pending = guest.send(:load_pending_invitations).map { |entry| entry[:invitation].table_id }
    assert(pending.include?(table['__id']), "Local filter consumed offer #{label}")
  end
  checks += 1
end

# Reconnect already has a native membership. A local refusal must leave both
# it and its offer untouched; an RPC that already completed must finish normally.
[false, true].product([:accepting, :pending, :established, :delivery]).each do |private_table, stage|
  broker, gateway, _owner, guest, table, invitation = blacklist_inflight_fixture(private_table)
  guest.send(:establish_invited_table_transport, invitation.table)
  guest.membership_attempts.clear
  guest.block_at = stage
  result = guest.send(:accept_pending_invitation, invitation)
  accepted = [:established, :delivery].include?(stage)
  assert(result.nil? && broker.cores.fetch(table['__live_session_id']).participants.key?('guest'), 'Reconnect lost existing membership')
  assert(guest.membership_attempts.length == (accepted ? 1 : 0), "Reconnect admission failed #{stage}")
  assert(gateway.rows['Guest'].first.revoked == accepted, "Reconnect consumed locally blocked offer #{stage}")
  assert(guest.alerts == (accepted ? ['You are already at this table.'] : []) && guest.errors.empty?, 'Reconnect lied about its completion')
  checks += 1
end

# A retained Reject action is also only admitted before its first mutation.
[false, true].each do |private_table|
  broker, gateway, _owner, guest, table, invitation = blacklist_inflight_fixture(private_table)
  guest.block_at = :rejecting
  assert(!guest.send(:reject_pending_invitation, invitation), 'Blocked retained rejection succeeded')
  assert(!gateway.rows['Guest'].first.revoked && guest.sent.empty? && guest.alerts.empty?, 'Blocked rejection changed its offer')
  BlacklistInflightApp.remember_settings('invitation_blacklist' => [])
  assert(guest.send(:load_pending_invitations).any? { |entry| entry[:invitation].table_id == table['__id'] }, 'Blocked rejection reached the server')
  checks += 1
end

# Real bound tables exercise the exception throughout the same admission path.
# Neither the ordinary table's name above nor a fake flag grants this binding.
[:loading, :accepting, :pending].each do |stage|
  GameRoomTest::TemporaryDirectory.create('blacklist-inflight-tournament-') do |directory|
    BlacklistInflightApp.remember_settings('invitation_blacklist' => [])
    broker, gateway = NativeLiveSessionsBroker.new, DurableNoticeGateway.new
    owner, guest = %w[Owner Guest].map { |user| BlacklistInflightApp.new(broker, user, gateway) }
    docs = TournamentServerPlanTableSupport::Table.new(user: -> { 'Owner' })
    game = GameRoomGames::TicTacToe.new
    candidate = {'format' => 'round_robin', 'schedule_id' => 'a' * 64, 'publication_digest' => 'b' * 64,
      'roster_generation' => 'c' * 64, 'game_id' => game.id, 'game_options' => game.default_options,
      'publication_ref' => {'author' => 'owner', 'publication_key' => 'blacklist-inflight'}, 'roster' => %w[owner guest],
      'matches' => [{'match_id' => 'd' * 64, 'leg' => 1, 'number' => 1, 'players' => %w[owner guest]}]}
    [owner, guest].zip(%w[Owner Guest]).each do |app, user|
      app.fixture_service = GameRoomTournaments::OrdinaryMatchService.new(program: ProgramDouble.new(broker.endpoint(user)),
        registry: EltenGameRoom::GAME_REGISTRY, lobby: app.instance_variable_get(:@lobby),
        games: app.instance_variable_get(:@games), transport: app.transport, table: docs.for_user(user),
        journal: GameRoomTournaments::OperationJournal.new(directory: File.join(directory, user), owner: user.downcase,
          backend_identity: 'blacklist-inflight'), source: -> { {'candidate' => candidate, 'tournament_id' => 1} }, user: -> { user })
      app.instance_variable_set(:@ordinary_tournament_services, {JSON.generate(candidate['publication_ref']) => app.fixture_service})
    end
    $game_room_test_user = 'Owner'
    table = owner.fixture_service.open_match(match_id: 'd' * 64, leg: 1)
    assert(owner.send(:deliver_table_invitation, table, 'Guest').created?, 'Tournament invitation not delivered')
    $game_room_test_user = 'Guest'
    guest.block_at = stage
    notice = gateway.rows['Guest'].first
    guest.notification_action(:open_invitation, native_blacklist_notice(notice))
    assert(guest.entered && guest.fixture_service.attached_table?(guest.entered), "Tournament exception refused #{stage}")
    assert(guest.membership_attempts.length == 1 && notice.revoked && guest.errors.empty?, 'Tournament admission did not complete normally')
    assert(BlacklistInflightApp.normalized_settings['invitation_blacklist'] == ['OWNER'], 'Tournament test did not publish the concurrent block')
    checks += 1
  ensure
    [owner, guest].each { |app| app&.fixture_service&.close }
  end
end
puts "PASS blacklist in-flight admission: #{checks} public/private read/write/reconnect/reject and real tournament boundaries"
