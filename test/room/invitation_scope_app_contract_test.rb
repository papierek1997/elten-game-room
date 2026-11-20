require_relative '../support/invitation_fresh_endpoint'

class ScopedInvitationApp < InvitationAppDriver
  attr_accessor :decision
  attr_reader :opened
  def initialize_services; end
  def check_server_table_access(announce: true); end
  def select_notification_invitation_action; decision; end
  def run_program_interface(table); @opened = table; end
end

def colliding_send(app, table, user)
  original = SecureRandom.method(:random_number)
  SecureRandom.define_singleton_method(:random_number) { |_limit| 90 }
  app.send(:deliver_table_invitation, table, user)
ensure
  SecureRandom.define_singleton_method(:random_number, original)
end

[false, true].each do |private_table|
  InvitationRepository::SENT_LOCK.synchronize { InvitationRepository::SENT.clear }
  broker, gateway = NativeLiveSessionsBroker.new, DurableNoticeGateway.new
  apps = %w[Alice Carol Bob].to_h { |user| [user, ScopedInvitationApp.new(broker,user,gateway)] }
  rooms = %w[Alice Carol].map do |user|
    $game_room_test_user = user
    table = apps[user].transport.create_room(name: "#{user} room",game:'uno',owner:user,
      game_options:'{}',private_table:private_table)
    assert(colliding_send(apps[user],table,'Bob').created?, 'Invitation was not created')
    table
  end
  $game_room_test_user = 'Bob'
  bob = apps['Bob']
  choices = bob.send(:load_pending_invitations)
  assert(choices.map { |choice| choice[:invitation].table_id }.sort == rooms.map { |row| row['__id'] }.sort,
    'Notification/native merge lost a colliding table')
  assert(choices.size == 2, 'Native and notification copies were not deduplicated by exact scope')
  first_notice, second_notice = gateway.rows['Bob']
  # Open the second notice while the first colliding ID appears first in lists.
  bob.decision = :reject
  assert(bob.notification_action(:open_invitation,second_notice), 'Notice was not handled')
  assert(second_notice.revoked && !first_notice.revoked, 'Rejecting a notice removed a different room')
  assert(bob.send(:load_pending_invitations).map { |choice| choice[:invitation].table_id } == [rooms.first['__id']],
    'Independent invitation was resolved by the other reply')
  remaining = InvitationRepository::SENT.values
  assert(remaining.size == 1 && remaining.first['sender'] == 'Alice', 'Sender reservation was resolved across scopes')
  bob.decision = :accept
  assert(bob.notification_action(:open_invitation,first_notice), 'Remaining notice could not be accepted')
  assert(bob.opened && bob.opened['__live_session_id'] == rooms.first['__live_session_id'], 'Wrong native table joined')
  assert(bob.errors.empty? && bob.alerts.empty?, 'Ordinary collision recovery produced an error')
end

# Same number and same room, but distinct authenticated senders, still identify
# separate invitation decisions. Legacy ID-only entry points must not guess.
InvitationRepository::SENT_LOCK.synchronize { InvitationRepository::SENT.clear }
broker, gateway = NativeLiveSessionsBroker.new, DurableNoticeGateway.new
alice, carol, bob = %w[Alice Carol Bob].map { |user| ScopedInvitationApp.new(broker,user,gateway) }
$game_room_test_user = 'Alice'
table = alice.transport.create_room(name:'Two senders',game:'uno',owner:'Alice',game_options:'{}')
colliding_send(alice,table,'Bob')
$game_room_test_user = 'Carol'
assert(carol.transport.join_room(table,'Carol') == :joined, 'Second sender cannot join')
colliding_send(carol,table,'Bob')
$game_room_test_user = 'Bob'
choices = bob.send(:load_pending_invitations)
assert(choices.map { |item| item[:invitation].sender }.sort == %w[Alice Carol], 'Sender scope lost in UI')
bob.send(:show_pending_invitations,preferred_id:91)
assert(bob.alerts.last == 'This invitation is no longer available.' && gateway.rows['Bob'].none?(&:revoked),
  'Ambiguous old shortcut chose or revoked an invitation')
bob.decision = :reject
bob.notification_action(:open_invitation,gateway.rows['Bob'].last)
assert(gateway.rows['Bob'].map(&:revoked) == [false,true], 'Same-room reply was not scoped by sender')
assert(InvitationRepository::SENT.values.map { |row| row['sender'] } == ['Alice'], 'Receipt unlocked the other sender')

# An old dialog/notice cannot use another account after a runtime change.
selected = bob.send(:load_pending_invitations).first[:invitation]
$game_room_test_user = 'Other'
before = gateway.rows['Bob'].map(&:revoked)
assert(!bob.send(:accept_pending_invitation,selected), 'Stale recipient joined under a different account')
assert(!bob.send(:reject_pending_invitation,selected), 'Stale recipient rejected under a different account')
assert(gateway.rows['Bob'].map(&:revoked) == before, 'Another account revoked the old notice')
assert(broker.cores.fetch(table['__live_session_id']).participants.keys.sort == %w[alice carol], 'Wrong account acquired membership')

$game_room_test_user = 'Bob'
original_task = bob.method(:run_network_task)
bob.define_singleton_method(:run_network_task) do |title, **options, &operation|
  result = original_task.call(title, **options, &operation)
  $game_room_test_user = 'Other' if title == 'Connecting to Elten'
  result
end
bob.decision = :accept
assert(bob.notification_action(:open_invitation,gateway.rows['Bob'].first), 'Account-switched notification was not handled')
assert(!bob.opened && gateway.rows['Bob'].map(&:revoked) == before, 'Connection rebound an old notification to the new account')
puts 'PASS scoped native/application invitation merge, exact notification action, replies, legacy ambiguity and stale account'
