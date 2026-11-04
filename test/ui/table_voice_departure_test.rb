require_relative '../support/table_voice_controller'
require_relative '../../lib/table_voice_membership'
device=LocalConferenceDevice.new
voice={'status'=>'ready','head'=>'voice-head','channel_id'=>555,'name'=>'Our table','creator'=>'Alice','password'=>''}
table={'__id'=>20,'voice'=>voice}
device.channel=Struct.new(:id,:name).new(555,'Our table')
membership=GameRoomTableVoiceMembership.new(conference:device)
membership.remember(table)
assert(membership.connected?(table.merge('voice'=>GameRoomTableVoice.empty)),'Cleared invitation lost the connected conference identity')
assert(membership.depart(table.merge('voice'=>GameRoomTableVoice.empty)),'Departure failed')
assert_equal(1,device.leaves,'Cleared published invitation lost the local channel')
device.channel=Struct.new(:id,:name).new(555,'Unrelated recycled channel')
assert(!membership.connected?(table),'An unrelated conference enabled the table-only departure choice')
assert(membership.depart(table),'Unrelated-channel departure failed')
assert_equal(1,device.leaves,'Departure disconnected an unrelated conference')
device.channel=Struct.new(:id,:name).new(555,'Our table')
device.leave_success=false
membership.remember(table)
assert_equal(false,membership.depart(table),'Failed native leave reported success')
device.leave_success=true
assert(membership.depart(table.merge('voice'=>GameRoomTableVoice.empty)),'Failed leave discarded retry identity')
assert_equal(3,device.leaves)

room=NativeRoomHarness.new(users:%w[Alice Bob])
host,guest=room.transports.values_at('Alice','Bob')
claim=room.as('Alice'){host.change_table_voice(room.table,{'operation'=>'claim','previous'=>''},actor:'Alice')}
room.as('Alice'){host.change_table_voice(room.table,{'operation'=>'publish','previous'=>claim[:voice]['head'],'channel_id'=>555,'name'=>'Our table','password'=>''},actor:'Alice')}
room.as('Alice'){host.append_activity(table:room.table,kind:'left',actor:'Alice')}
current=room.as('Bob'){guest.table_voice(room.table,force:true)}
assert_equal('none',current['status'],'Creator departure retained a joinable invitation')
new_claim=room.as('Bob'){guest.change_table_voice(room.table,{'operation'=>'claim','previous'=>current['head']},actor:'Bob')}
assert_equal(true,new_claim[:accepted],'Departure head was not shared by validator and projection')
puts 'PASS confirmed table departure: retained native identity, failed leave retry, unrelated channel isolation and authenticated creator invitation withdrawal'

delayed=LocalConferenceDevice.new
delayed.channel=Struct.new(:id).new(0)
pending=GameRoomTableVoiceMembership.new(conference:delayed)
pending.remember(table)
delayed.channel=Struct.new(:id,:name).new(555,'Our table')
assert(pending.depart(table.merge('voice'=>GameRoomTableVoice.empty)),'Asynchronous join lost its table identity')
assert_equal(1,delayed.leaves,'The native update arrived after remember and was not disconnected')

kept=LocalConferenceDevice.new
kept.channel=Struct.new(:id,:name).new(555,'Our table')
retained=GameRoomTableVoiceMembership.new(conference:kept)
retained.remember(table)
assert(retained.depart(table,disconnect:false),'Table-only departure failed')
assert_equal(0,kept.leaves,'Table-only departure called Conference.leave')
assert_equal(555,kept.channel.id,'Table-only departure changed the conference')
assert(!retained.connected?(table.merge('voice'=>GameRoomTableVoice.empty)),'Table-only departure retained an obsolete table tracker')
