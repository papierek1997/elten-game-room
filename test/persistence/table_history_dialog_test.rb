require 'tmpdir'
require_relative '../support/binary_rules_load'
require EltenTestHost.file('src/bootstrap.rb')
require_relative '../support/recordings'

GameRoomTestLocalization.use_language('pl')
app=EltenGameRoom.allocate
messages=[]
tasks=[]
app.define_singleton_method(:get_file) { |*| raise 'Saving history must not ask for an external folder' }
app.define_singleton_method(:alert) { |text| messages << text }
app.define_singleton_method(:run_network_task) do |title,ui: nil,**,&operation|
  raise 'Local library save must use a passive task' unless ui==:none
  tasks << title
  operation.call
end
entries=[GameRoomHistory::Entry.new(text:'Łukasz: Cześć!'.b,category: :chat)]
Dir.mktmpdir('historia-żółć-') do |directory|
  library=GameRoomRecordings::Library.new(RecordingTest::Program.new(directory),account:'Alice',current_account:-> {'Alice'})
  app.define_singleton_method(:recording_library) { library }
  raise 'Saving did not succeed' unless app.send(:save_table_history,entries)
  rows=library.list
  raise 'History was not added to the default library' unless rows.size==1
  bytes=library.read(rows[0]['filename']).force_encoding('UTF-8')
  raise 'Binary Polish chat was damaged' unless bytes.end_with?("Łukasz: Cześć!\r\n")
  raise 'History was not identified as Power Games text' unless bytes.start_with?("Power Games\r\n")
  raise 'Passive save was not announced' unless messages.size==1 && tasks.size==1
  library.define_singleton_method(:save_text) { |*args,**| raise IOError,'Disk full' }
  raise 'A failed write claimed success' unless app.send(:save_table_history,entries)==false
  raise 'Failure damaged an existing recording' unless library.list==rows
end
puts 'PASS binary history save: default account library, passive background task, Polish UTF-8, no folder picker, exact failure handling and preserved previous file'
