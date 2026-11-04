require_relative '../support/ui'
require_relative '../support/recordings'
require_relative '../../lib/recordings/delivery'
include RecordingTest
R=GameRoomRecordings

class RecordingMailbox
  Message=Struct.new(:id,:sender,:receiver,:subject,:text,:attachments,:attachments_names,:date,:owner,keyword_init:true)
  Page=Struct.new(:messages,:more,keyword_init:true)
  Info=Struct.new(:id,:name,:size,keyword_init:true)
  attr_reader :sent,:deleted,:rows,:files
  attr_accessor :lose_reply,:fail_upload
  def initialize(account)
    @account=account;@rows=[];@files={};@sent=0;@deleted=[];@id=0
  end
  def send_text(client,to:,subject:,text:,attachments:)
    raise IOError,'Upload failed before sending the message' if @fail_upload
    client.api_data('POST','/api/v1/messages',{})
    @sent+=1
    key="attachment#{@sent}"
    @files[key]={name:File.basename(attachments[0]),bytes:File.binread(attachments[0])}
    [@account.call,to].uniq.each do |owner|
      @id+=1
      @rows << Message.new(id:@id,sender:@account.call,receiver:to,subject:subject,text:text,
        attachments:[key],attachments_names:[@files[key][:name]],date:1_800_000_000,owner:owner)
    end
    raise IOError,'Lost message acknowledgement' if @lose_reply
    true
  end
  def messages(_client,user:,subject:,limit:)
    Page.new(messages:@rows.select { |row| row.owner==@account.call && row.subject==subject &&
      (row.sender.casecmp?(user) || row.receiver.casecmp?(user)) }.first(limit),more:false)
  end
  def search_messages(_client,query)
    Page.new(messages:@rows.select { |row| row.owner==@account.call && row.text.include?(query) },more:false)
  end
  def delete_message(_client,id)
    row=@rows.find { |item| item.owner==@account.call && item.id==id }
    raise 'Tried to delete a foreign message' unless row
    @rows.delete(row);@deleted << [row.owner,id]
    true
  end
  def info(_client,id)
    file=@files.fetch(id)
    Info.new(id:id,name:file[:name],size:file[:bytes].bytesize)
  end
  def download_url(id); "https://recordings.invalid/#{id}"; end
end

Dir.mktmpdir('pg-recording-messages-') do |temporary|
  account='Alice'
  program=RecordingTest::Program.new(temporary)
  mailbox=RecordingMailbox.new(-> {account})
  client=Object.new
  client.define_singleton_method(:api_data) { |*args,**| true }
  client.define_singleton_method(:api_download) { |path,**| mailbox.files.fetch(path.delete_prefix('/'))[:bytes] }
  alice=R::Library.new(program,account:'Alice',current_account:-> {account})
  source=alice.save_document(document)
  delivery=R::Delivery.new(alice,client:client,messages:mailbox,attachments:mailbox)
  result=delivery.send_file(source,recipient:'Bob')
  assert(result=={sent:true,removed:true})
  assert(mailbox.rows.size==1 && mailbox.rows[0].owner=='Bob','Sender cleanup affected the recipient copy')
  assert(alice.list.size==1,'Sending removed the library game')
  account='Bob'
  bob=R::Library.new(program,account:'Bob',current_account:-> {account})
  received=R::Delivery.new(bob,client:client,messages:mailbox,attachments:mailbox)
  refs=received.incoming
  assert(refs.size==1)
  packet=received.receive(refs[0])
  assert(bob.list.empty? && mailbox.rows.size==1,'Preview imported or removed a message automatically')
  kept=bob.import_bytes(packet[:bytes],extension:packet[:extension])
  assert(bob.list.size==1 && R::Document.parse(bob.read(kept))['metadata']['game']=='axel_pong')
  assert(bob.import_bytes(packet[:bytes],extension:packet[:extension])==kept,'Repeated import created a duplicate recording')
  assert(mailbox.rows.size==1,'Persistent import removed a message without the separate choice')
  received.remove_received(refs[0])
  assert(mailbox.rows.empty? && bob.list.size==1)
  refuses(R::Unavailable) { received.remove_received(refs[0]) }

  account='Alice'
  other=alice.save_text(['Another match'],game_name:'Scopa',players:%w[Alice Bob])
  mailbox.lose_reply=true
  refuses(IOError) {delivery.send_file(other,recipient:'Bob')}
  assert(mailbox.sent==2)
  mailbox.lose_reply=false
  result=delivery.send_file(other,recipient:'Bob')
  assert(mailbox.sent==2 && result[:sent],'Uncertain delivery was resent instead of reconciled')
  assert(mailbox.rows.none? { |row| row.owner=='Alice' })

  upload_trial=alice.save_text(['Upload retry'],game_name:'Retry test',players:%w[Alice Bob])
  mailbox.fail_upload=true
  refuses(IOError) {delivery.send_file(upload_trial,recipient:'Bob')}
  sent_before=mailbox.sent
  mailbox.fail_upload=false
  delivery.send_file(upload_trial,recipient:'Bob')
  assert(mailbox.sent==sent_before+1,'Failure before message POST incorrectly prevented retry')

  large=alice.save_text(['x'*(R::Delivery::MAX_ATTACHMENT+100)],game_name:'Long match',players:%w[Alice Bob])
  delivery.send_file(large,recipient:'Bob')
  assert(mailbox.files.values.last[:name].end_with?('.txt.zip'),'Large compressible history was not packaged')
  account='Bob'
  ref=received.incoming.find { |row| row['description']=='Long match' }
  imported=received.receive(ref)
  assert(imported[:extension]=='.txt' && imported[:bytes].bytesize>R::Delivery::MAX_ATTACHMENT)
  mailbox.files[ref['attachment']][:bytes]='corrupt'
  refuses {received.receive(ref)}
  assert(mailbox.rows.any? { |row| row.id==ref['message_id'] },'Failed import deleted its source message')
end
puts 'PASS recording messages: native-shaped attachments, exact sender cleanup, preview/import separation, optional recipient deletion, deduplication, lost acknowledgements and bounded compressed sharing'
