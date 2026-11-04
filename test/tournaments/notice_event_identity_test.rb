require_relative '../support/native_room_harness'
require_relative '../../lib/tournaments/proposal_notice_inbox'
include GameRoomTest::Assertions

# Current tournament notifications use event_id, while proposal notices use
# token. Both families share one inbox, without treating every event as nil.
class EventIdentityWorker
  def start(&operation); return false if busy?; @operation = operation; true; end
  def busy?; @operation != nil; end
  def take
    return unless @operation
    operation, @operation = @operation, nil
    [operation.call, nil]
  rescue StandardError => error
    [nil, error]
  end
  def close; @operation = nil; end
end
service = Object.new
stale = false
service.define_singleton_method(:inspect) do |metadata:, sender:|
  raise GameRoomTournaments::ProposalNotice::Stale, 'Cancelled' if stale
  {'metadata'=>metadata, 'players'=>[sender, 'alice']}
end
service.define_singleton_method(:presentable?) { |_proof| true }
service.define_singleton_method(:refresh_on_change?) { |_metadata,proof:nil| true }
service.define_singleton_method(:retain_stale_notice?) { |_metadata,sender:| false }
inbox = GameRoomTournaments::ProposalNoticeInbox.new(service:service, worker:EventIdentityWorker.new, metadata:->(value) {value})
first = {'event_id'=>'first-event', 'publication_ref'=>{'author'=>'owner','publication_key'=>'first'}}
second = {'event_id'=>'second-event', 'publication_ref'=>{'author'=>'owner','publication_key'=>'second'}}
begin
  [[1,first],[2,second]].each do |id, metadata|
    assert(inbox.receive(id:id, metadata:metadata, sender:'owner'))
    2.times { inbox.tick }
  end
  assert_equal(2, inbox.pending.size, 'Distinct current tournament events collided')
  assert_equal([1], inbox.forget(first.fetch('event_id')), 'Forgetting an event did not identify its native notification')
  assert(inbox.dismissed?(first.fetch('event_id')) && !inbox.dismissed?(second.fetch('event_id')), 'Dismissal leaked between event identities')
  assert_equal(false, inbox.receive(id:3, metadata:first, sender:'owner'), 'A dismissed event was revived by redelivery')
  stale = true
  inbox.refresh(second.fetch('publication_ref'))
  2.times { inbox.tick }
  assert_equal([2], inbox.take_revoked, 'A newly cancelled event was not revoked')
  assert(inbox.dismissed?(second.fetch('event_id')), 'Native lifecycle cannot observe the confirmed stale event')
  assert_equal([], inbox.pending, 'Cancelled events remained actionable')
ensure
  inbox.close
end
puts 'PASS shared notification inbox: distinct event IDs, exact dismissal, redelivery and stale-proof invalidation'
