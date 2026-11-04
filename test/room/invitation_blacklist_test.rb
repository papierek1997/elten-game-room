require_relative '../support/invitation_fresh_endpoint'
require_relative '../support/app_notification_models'
require_relative '../support/temporary_directory'
require_relative '../support/tournament_server_plan_table'
require_relative '../../lib/tournaments/ordinary_match_service'
require EltenTestHost.file('src/eapi/notificationgroups.rb')

def p_(_context, text); text; end

class BlacklistInvitationApp < InvitationAppDriver
  class << self
    def read_json(*); raise 'Blacklist filter opened local storage'; end
    def contacts_cache; raise 'Blacklist filter requested contacts'; end
    def play_sound_from_asset(name, volume:); (@played ||= []) << [name, volume]; end
    def played; @played ||= []; end
  end
  attr_reader :entered
  attr_accessor :fixture_service
  def initialize(*args, **options)
    super
    @invitations = nil
    @server_tables = {}
    initialize_services # Exercise the actual factory's callback, not a test-only filter.
  end
  def register_room_presence; end
  def check_server_table_access; end
  def record_statistics_visit; end
  def run_program_interface(row); @entered = row; end
  def select_notification_invitation_action; :accept; end
  def ordinary_tournament_service(*, **); fixture_service; end
end

GameRoomLocalization.boot(settings: {}, host_language: 'en')
program = BlacklistInvitationApp
program.remember_settings('invitation_blacklist' => [' oWnEr '], 'invitation_notifications' => 'everyone')

# Actual host notification model, mapper, receiver and list grouping. Only the
# final audio/speech sinks are captured; no installed profile is involved.
BlacklistHostNotice = Struct.new(:id, :cat, :app_uuid, :date, :update_time, :revoked, :payload, :alert, keyword_init: true)
BLACKLIST_RUNTIME = TestTaskRuntime.new('blacklist-test')
module Programs
  def self.notification_program(_); BlacklistInvitationApp; end
  def self.runtime_for(_); BLACKLIST_RUNTIME; end
end
module EltenAPI::NotificationService
  class << self; attr_accessor :rows; end
  def self.active_notifications; rows || []; end
end
$game_room_test_user = 'Guest'
now = Time.now.to_i
notice = lambda do |id, sender, extra = {}, type = 'game_room.invitation'|
  BlacklistHostNotice.new(id: id, cat: 'app', app_uuid: program.server_app_uuid, date: now,
    revoked: false, alert: '', payload: {'sender' => sender, 'type' => type, 'metadata' => {
      'sender' => sender, 'table_name' => 'Tournament match', 'game' => 'uno', 'game_name' => 'UNO',
      'table_id' => id, 'live_session_id' => "room-#{id}", 'created_at' => now, 'expires_at' => now + 300
    }.merge(extra)})
end
blocked = notice.call(1, 'OWNER')
allowed = notice.call(2, 'Carol')
tournament = notice.call(3, 'Owner', {'tournament_match' => true})
not_tournament = notice.call(4, 'Owner', {'tournament_match' => 'true'})
forged = notice.call(5, 'Owner', {'sender' => 'Carol'})
unblocked_forged = notice.call(7, 'Bob', {'sender' => 'Carol'})
rows = [blocked, allowed, tournament, not_tournament, forged, unblocked_forged]
EltenAPI::NotificationService.rows = rows
GameRoomInvitationReceipts.install(program)
grouping = Object.new.extend(NotificationGroups)
rows.each do |row|
  _, _, presentation = Programs.receive_app_notification(row)
  hidden = [1, 4, 5, 7].include?(row.id)
  assert(presentation.default_suppressed? == hidden, "wrong speech visibility for #{row.id}")
  presentation.sound
end
assert(program.played.length == 2, 'Blocked sender produced sound, or tournament/allowed notice was muted')
100.times { assert(grouping.build_notification_groups(rows).flat_map(&:ids).sort == [2, 3], 'Host notification list ignored blacklist') }
rows.each { |row| row.revoked = true }
assert(grouping.build_notification_groups(rows, include_revoked: true).flat_map(&:ids).sort == [2, 3], 'Read history revealed blocked invitations')
assert(!program.invitation_sender_allowed?('Owner') && program.invitation_sender_allowed?('Owner', tournament_match: true), 'Tournament exception inconsistent')
['game_room.table_created', GameRoomTournaments::TournamentStartNotice::TYPE,
  *GameRoomTournaments::TournamentEventNotice::TYPES.values].each do |type|
  native = Programs.app_notification_from(notice.call(10, 'Owner', {}, type))
  assert(program.contact_notification_allowed?(native), "Blacklist filtered a non-invitation #{type}")
end
program.remember_settings('invitation_blacklist' => ['Owner'], 'invitation_notifications' => 'nobody')
assert(program.contact_notification_allowed?(Programs.app_notification_from(tournament)), 'Tournament match invitations must bypass ordinary contact filters too')

# A notice queued while the ordinary contact cache is unresolved must consult
# the committed blacklist again before its delayed speech/audio delivery.
queue = GameRoomContacts::Pending.new
known = nil
cache = Object.new
cache.define_singleton_method(:include?) { |_| known }
cache.define_singleton_method(:revision) { 0 }
original_cache = program.method(:contacts_cache)
program.define_singleton_method(:contacts_cache) { cache }
program.instance_variable_set(:@contacts_cache, cache)
program.instance_variable_set(:@contact_pending, queue)
program.instance_variable_set(:@contact_revision, 0)
program.remember_settings('invitation_blacklist' => [], 'invitation_notifications' => 'contacts')
queued = notice.call(6, 'Owner')
EltenAPI::NotificationService.rows = [queued]
assert(Programs.receive_app_notification(queued).last.default_suppressed? && queue.entries.size == 1, 'Unknown contact was not deferred')
program.remember_settings('invitation_blacklist' => ['Owner'], 'invitation_notifications' => 'contacts')
known = true
sounds = program.played.length
program.contacts_tick
assert(queue.entries.empty? && program.played.length == sounds, 'Queued notice escaped a newly saved blacklist')
program.define_singleton_method(:contacts_cache, original_cache)
program.instance_variable_set(:@contacts_cache, nil)
program.instance_variable_set(:@contact_pending, nil)
program.remember_settings('invitation_blacklist' => ['Owner'], 'invitation_notifications' => 'everyone')

[false, true].each do |private_table|
  broker, gateway = NativeLiveSessionsBroker.new, DurableNoticeGateway.new
  owner = BlacklistInvitationApp.new(broker, 'Owner', gateway)
  $game_room_test_user = 'Owner'
  table = owner.transport.create_room(name: 'Tournament match', game: 'uno', owner: 'Owner',
    game_options: '{}', private_table: private_table)
  result = owner.send(:deliver_table_invitation, table, 'Guest')
  assert(result.created? && gateway.rows['Guest'].length == 1, 'Sender did not see normal delivery')
  guest = BlacklistInvitationApp.new(broker, 'Guest', gateway)
  $game_room_test_user = 'Guest'
  program.remember_settings('invitation_blacklist' => [])
  retained = guest.send(:load_pending_invitations).first.fetch(:invitation)
  program.remember_settings('invitation_blacklist' => ['owner'])
  assert(guest.send(:load_pending_invitations).empty?, 'Pending list ignored blacklist')
  assert(guest.send(:show_pending_invitations).nil?, 'Common Ctrl+J picker accepted blocked invitation')
  guest.define_singleton_method(:prepare_widget_program) {}
  guest.send(:accept_invitation_from_widget)
  assert(!guest.entered, 'Widget bypassed the common blacklist')
  assert(guest.send(:accept_pending_invitation, retained).nil?, 'Retained Accept bypassed blacklist')
  assert(guest.send(:reject_pending_invitation, retained) == false, 'Blacklist automatically rejected a retained invitation')
  captured = gateway.rows['Guest'].first
  assert(guest.notification_action(:open_invitation, captured), 'Old notification action was unhandled')
  assert(!guest.entered && !captured.revoked && guest.sent.empty?, 'Blacklist joined/responded/revoked instead of filtering')
  assert(broker.cores.fetch(table['__live_session_id']).participants.keys == ['owner'], 'Blocked invitation changed membership')
  program.remember_settings('invitation_blacklist' => [])
  row = guest.send(:accept_pending_invitation, retained)
  assert(row && row['__id'] == table['__id'], "Removal did not restore normal acceptance: #{guest.alerts} #{guest.errors}")
  assert(captured.revoked, 'Actual acceptance no longer cleans its notice')
end

# An actual bound tournament table from the ordinary service, not its name or
# a forged invitation flag. The unchanged attach/role guards still run.
GameRoomTest::TemporaryDirectory.create('blacklist-tournament-') do |directory|
  broker, gateway = NativeLiveSessionsBroker.new, DurableNoticeGateway.new
  owner = BlacklistInvitationApp.new(broker, 'Owner', gateway)
  guest = BlacklistInvitationApp.new(broker, 'Guest', gateway)
  docs = TournamentServerPlanTableSupport::Table.new(user: -> { 'Owner' })
  candidate = {'format' => 'round_robin', 'schedule_id' => 'a' * 64, 'publication_digest' => 'b' * 64,
    'roster_generation' => 'c' * 64, 'game_id' => GameRoomGames::TicTacToe.new.id, 'game_options' => GameRoomGames::TicTacToe.new.default_options,
    'publication_ref' => {'author' => 'owner', 'publication_key' => 'blacklist'}, 'roster' => %w[owner guest],
    'matches' => [{'match_id' => 'd' * 64, 'leg' => 1, 'number' => 1, 'players' => %w[owner guest]}]}
  [owner, guest].zip(%w[Owner Guest]).each do |app, user|
    app.fixture_service = GameRoomTournaments::OrdinaryMatchService.new(program: ProgramDouble.new(broker.endpoint(user)),
      registry: EltenGameRoom::GAME_REGISTRY, lobby: app.instance_variable_get(:@lobby),
      games: app.instance_variable_get(:@games), transport: app.transport, table: docs.for_user(user),
      journal: GameRoomTournaments::OperationJournal.new(directory: File.join(directory, user), owner: user.downcase,
        backend_identity: 'blacklist-tournament'), source: -> { {'candidate' => candidate, 'tournament_id' => 1} }, user: -> { user })
    app.instance_variable_set(:@ordinary_tournament_services, {JSON.generate(candidate['publication_ref']) => app.fixture_service})
  end
  $game_room_test_user = 'Owner'
  table = owner.fixture_service.open_match(match_id: 'd' * 64, leg: 1)
  owner.send(:deliver_table_invitation, table, 'Guest')
  $game_room_test_user = 'Guest'
  program.remember_settings('invitation_blacklist' => ['Owner'])
  pending = guest.send(:load_pending_invitations)
  assert(pending.length == 1 && pending.first[:invitation].table['tournament_match'].is_a?(Hash), 'Bound tournament invitation disappeared')
  assert(guest.send(:invitation_account_guard, pending.first[:invitation]).call, 'Retained tournament invitation was blocked')
  captured = gateway.rows['Guest'].first
  assert(captured.metadata['tournament_match'] == true, 'Normal sender did not publish tournament metadata')
  guest.notification_action(:open_invitation, captured)
  assert(guest.entered && guest.entered['__id'] == table['__id'], "Tournament exception failed normal entry: #{guest.errors} #{guest.alerts}")
  assert(guest.fixture_service.attached_table?(guest.entered), 'Tournament exception bypassed authoritative attachment')
ensure
  [owner, guest].each { |app| app&.fixture_service&.close }
end
puts 'PASS blacklist: native notification mapping/list/audio, ordinary public/private pending and retained/widget actions, no rejection, unblock, real bound tournament acceptance'
