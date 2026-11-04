require_relative '../support/settings_widget'
require_relative '../support/assertions'
include GameRoomTest::Assertions

reads=0
contacts=Object.new
contacts.define_singleton_method(:include?) { |_sender| reads+=1;false }
app=Class.new(EltenGameRoom)
app.define_singleton_method(:contacts_cache) { contacts }
notice=Struct.new(:type,:sender,:metadata).new('game_room.invitation','Blocked',{'sender'=>'Blocked','tournament_match'=>true})
%w[everyone contacts nobody].each do |policy|
  [[],['Blocked']].each do |blocked|
    settings=EltenGameRoom::DEFAULT_SETTINGS.merge('invitation_notifications'=>policy,'invitation_blacklist'=>blocked)
    before=reads
    assert_equal(true,app.contact_notification_allowed?(notice,settings:settings),"Tournament invitation blocked by #{policy}/#{blocked}")
    assert_equal(before,reads,'Tournament exception fetched contacts')
    ordinary=notice.dup
    ordinary.metadata=notice.metadata.merge('tournament_match'=>false)
    expected=policy=='everyone' && blocked.empty?
    assert_equal(expected,app.contact_notification_allowed?(ordinary,settings:settings),'Ordinary invitation policy was changed')
  end
end
forged=notice.dup
forged.metadata=notice.metadata.merge('sender'=>'SomeoneElse')
assert_equal(false,app.contact_notification_allowed?(forged,settings:EltenGameRoom::DEFAULT_SETTINGS),'Tournament exception accepted a forged sender')
puts 'PASS tournament invitation exception: all contact policies and blacklist bypassed without a lookup; ordinary invitations and authenticated sender unchanged'
