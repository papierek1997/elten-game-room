require_relative '../support/settings_widget'
require_relative '../support/assertions'
include GameRoomTest::Assertions

class NativeNoticeDepartureDriver < EltenGameRoom
  attr_accessor :confirmation
  attr_reader :lobby, :forgotten, :in_worker

  def initialize(lobby)
    @lobby, @confirmation, @forgotten = lobby, true, []
  end

  def table_departure_guard(_row); nil; end
  def load_room_state(row, **_options)
    Struct.new(:room).new(Struct.new(:table).new(row))
  end
  def confirm(_text); confirmation; end
  def forget_room_membership(row); @forgotten << row; end
  def run_network_task(*_arguments)
    @in_worker = true
    yield
  ensure
    @in_worker = false
  end
end

row = {'__id'=>17, '__live_session_id'=>'native-17'}
lobby = Object.new
result = nil
lobby.define_singleton_method(:table_id) { |table| table.fetch('__id') }
lobby.define_singleton_method(:owner_of) { |_table| Session.name }
lobby.define_singleton_method(:leave_table) do |_table, _viewer, **_options|
  raise result if result.is_a?(Exception)
  result
end
lobby.define_singleton_method(:close_table) do |_table|
  raise result if result.is_a?(Exception)
  result
end
program = NativeNoticeDepartureDriver.new(lobby)
revocations = []
cleanup_error = nil
GameRoomNotifications.define_singleton_method(:revoke_closed_table) do |owner, table|
  revocations << [owner, table, owner.in_worker]
  raise cleanup_error if cleanup_error
end

[nil, false, :left].each do |value|
  result = value
  assert_equal(value, program.send(:leave_current_table, row), 'Ordinary leave outcome changed')
end
assert(revocations.empty?, 'Transfer, failure or uncertain departure cancelled table invitations')
result = :closed
assert_equal(:closed, program.send(:leave_current_table, row), 'Confirmed closure was lost')
assert_equal([[program, row, nil]], revocations, 'Leaving the last seat did not cancel the exact table')

cleanup_error = IOError.new('revocation unavailable')
assert_equal(:closed, program.send(:leave_current_table, row), 'Cleanup failure undid a confirmed departure')
result = IOError.new('leave unavailable')
before = revocations.length
begin
  program.send(:leave_current_table, row)
  raise 'Failed leave unexpectedly succeeded'
rescue IOError => error
  assert_equal(result, error, 'Departure hid the original failure')
end
assert_equal(before, revocations.length, 'Failed leave revoked an active invitation')

cleanup_error = nil
revocations.clear
[nil, false].each do |value|
  result = value
  assert(program.send(:change_table_control, row, :close_table).nil?, 'Unconfirmed close was reported as successful')
end
assert(revocations.empty? && program.forgotten.empty?, 'Unconfirmed close forgot the live membership')
result = true
program.confirmation = false
assert(program.send(:change_table_control, row, :close_table).nil?, 'Cancelled close was performed')
assert(revocations.empty?, 'Cancelled close revoked invitations')
program.confirmation = true
assert_equal(:closed, program.send(:change_table_control, row, :close_table), 'Explicit close did not complete')
assert_equal([[program, row, true]], revocations, 'Explicit close cleanup escaped the network worker')
assert_equal([row], program.forgotten, 'Successful close did not release the local membership')
cleanup_error = IOError.new('revocation unavailable')
assert_equal(:closed, program.send(:change_table_control, row, :close_table), 'Cleanup failure undid explicit close')
assert_equal([row, row], program.forgotten, 'Cleanup failure retained a closed membership')
puts 'PASS native notification departure boundaries: confirmed closure only, host transfer retained, worker cleanup, errors isolated'
