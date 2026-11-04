require_relative '../support/table_watch_runtime'
require_relative '../support/app_notification_models'
require_relative '../support/assertions'
require EltenTestHost.file('src/eapi/program_notifications.rb')
require EltenTestHost.file('src/eapi/notificationgroups.rb')
include GameRoomTest::Assertions

Log.define_singleton_method(:error) { |message| raise message }

runtime = TestTaskRuntime.new('native-notification-lifecycle')
module Session
  def self.logged?; true; end
  def self.token; 'offline-test-session'; end
end
class EltenLink::Client
  def self.session_auth_params; {'name'=>Session.name, 'token'=>Session.token}; end
end
module Programs
  class << self
    attr_accessor :lifecycle_runtime
    def notification_programs; [EltenGameRoom]; end
    def runtime_for(_owner); lifecycle_runtime; end
  end
end
Programs.lifecycle_runtime = runtime
module EltenLink
  def self.client(_owner); :offline_client; end
  module Notifications
    class << self
      attr_accessor :writes
      def revoke(client, id, **_options)
        self.writes << [client, id, Thread.current]
        true
      end
    end
  end
end
module EltenAPI::NotificationService
  class << self
    attr_accessor :rows, :revoked_ids
    def active_notifications; rows; end
    def revoke_active_notifications(ids)
      self.revoked_ids.concat(ids)
      self.rows = rows.reject { |row| ids.include?(row.id) }
    end
  end
end
EltenLink::Notifications.writes = []
EltenAPI::NotificationService.revoked_ids = []
metadata = {'invitation_id'=>7,'table_id'=>12,'live_session_id'=>'native-12','expires_in'=>300}
row = Struct.new(:id,:app_uuid,:date,:payload,:cat, keyword_init:true).new(id:81, date:1000, cat:'app',
  app_uuid:EltenGameRoom.server_app_uuid, payload:{'type'=>'game_room.invitation','sender'=>'Bob','metadata'=>metadata})
EltenAPI::NotificationService.rows = [row]
GameRoomClock.define_singleton_method(:synchronized?) { true }
GameRoomClock.define_singleton_method(:now) { 1400.0 }
ui_thread = Thread.current
manager = Programs::NotificationLifecycles
begin
  manager.tick
  entry = manager.instance_variable_get(:@entries).fetch(row.id)
  assert(EltenLink::Notifications.writes.empty?, 'Declaring a lifecycle performed network I/O on the UI thread')
  entry.check_at = 0
  manager.instance_variable_set(:@next_tick, 0)
  manager.tick
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
  until entry.definition.nil?
    raise 'Native lifecycle worker did not complete' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    manager.instance_variable_set(:@next_tick, 0)
    manager.tick
    sleep(0.005)
  end
  assert_equal([81], EltenAPI::NotificationService.revoked_ids, 'Native host did not remove the confirmed stale notification')
  writes = EltenLink::Notifications.writes
  assert_equal([[:offline_client,81]], writes.map { |client,id,_thread| [client,id] }, 'Native lifecycle repeated or misrouted revocation')
  assert(writes.all? { |_client,_id,thread| thread != ui_thread }, 'Native network work blocked the UI owner')

  # A resolved tournament invitation disappears from grouping immediately,
  # but stays in the native store until the host confirms remote revocation.
  inbox=GameRoomTournaments::ProposalNoticeInbox.new(service:Object.new,worker:GameRoomBackground::Work.new(runtime:runtime))
  old_inboxes=EltenGameRoom.instance_variable_get(:@tournament_event_inboxes)
  EltenGameRoom.instance_variable_set(:@tournament_event_inboxes,{'registration'=>inbox})
  event={'version'=>2,'kind'=>'registration','issued_at'=>1000,'backend_identity'=>"elten-tournaments:#{EltenGameRoom.server_app_uuid}",
    'publication_ref'=>{'author'=>'bob','publication_key'=>'notice-fixture'},'recipient'=>Session.name.downcase,
    'title'=>'Tournament','game'=>'uno','invitation_key'=>'invite-one'}
  event['event_id']=GameRoomTournaments::TournamentEventNotice.event_id(event)
  event=GameRoomTournaments::TournamentEventNotice.metadata(event)
  invitation=row.dup
  invitation.id=82
  invitation.payload={'type'=>'game_room.tournament_registration','sender'=>'Bob','metadata'=>event}
  EltenAPI::NotificationService.rows=[invitation]
  inbox.forget(event['event_id'])
  GameRoomInvitationReceipts.install(EltenGameRoom)
  groups=Object.new.extend(NotificationGroups)
  assert(groups.build_notification_groups([invitation]).empty?,'Resolved invitation remained in the native list')
  assert_equal([82],EltenAPI::NotificationService.active_notifications.map(&:id),'List grouping removed the lifecycle entry prematurely')
  manager.instance_variable_set(:@next_tick,0)
  manager.tick
  entry=manager.instance_variable_get(:@entries).fetch(82)
  entry.check_at=0
  manager.instance_variable_set(:@next_tick,0)
  manager.tick
  deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+3
  until entry.definition.nil?
    raise 'Resolved notice lifecycle did not finish' if Process.clock_gettime(Process::CLOCK_MONOTONIC)>=deadline
    manager.instance_variable_set(:@next_tick,0)
    manager.tick
    sleep(0.005)
  end
  assert_equal([81,82],EltenAPI::NotificationService.revoked_ids)
  assert_equal([81,82],EltenLink::Notifications.writes.map { |_,id,_| id },'Tournament cleanup repeated a revocation')
  assert(EltenLink::Notifications.writes.all? { |_,_,thread| thread!=ui_thread },'Tournament cleanup used UI-thread networking')
ensure
  inbox&.close
  EltenGameRoom.instance_variable_set(:@tournament_event_inboxes,old_inboxes) if defined?(old_inboxes)
  runtime.close
end
puts 'PASS real native notification lifecycle: delayed worker, one exact revocation, no UI-thread I/O or receipt-relative expiry request'
