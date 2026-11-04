require_relative '../support/recordings'
include RecordingTest
R=GameRoomRecordings
Dir.mktmpdir('pg-recording-library-') do |temporary|
  program=RecordingTest::Program.new(temporary)
  account='Alice'
  library=R::Library.new(program,account:account,current_account:-> {account})
  assert(library.list.empty?)
  original=document
  name=library.save_document(original)
  assert(library.list.size==1 && library.list[0]['game']=='axel_pong')
  assert(R::Document.parse(library.read(name))==original)
  library.rename(name,'Mecz próbny')
  assert(library.list.first['title']=='Mecz próbny')
  export=File.join(temporary,'export');Dir.mkdir(export)
  external=library.export(name,export)
  assert(File.binread(external)==library.read(name))
  refuses(Errno::EEXIST) {library.export(name,export)}
  library.delete(name)
  assert(library.list.empty? && File.file?(external),'Deleting library file removed an exported copy')
  imported=library.import(external)
  assert(library.list.map { |row| row['filename'] }==[imported])
  File.delete(File.join(library.root,imported))
  assert(library.list.empty?,'A missing file remained indexed')
  FileUtils.cp(external,File.join(library.root,'copied.json'))
  assert(library.list.first['filename']=='copied.json','A manually added recording was not discovered')
  text_name=library.save_text(['Pierwszy ruch.','Zażółć gęślą jaźń.'],game_name:'Tysiąc',players:%w[Alice Bob],now:Time.at(1_800_000_000))
  assert(library.read(text_name).force_encoding('UTF-8').include?('Zażółć'))
  assert(library.list.find { |row| row['filename']==text_name }['kind']=='text')
  library.rename(text_name,'Dobre rozdanie')
  assert(library.list.find { |row| row['filename']==text_name }['title']=='Dobre rozdanie')
  refuses {library.read('../outside.txt')}
  refuses {library.delete('..')}
  account='Bob'
  refuses(R::Unavailable) {library.list}
  other=R::Library.new(program,account:account,current_account:-> {account})
  assert(other.list.empty?,'Another account inherited the recording library')
end
bad=R::Document.copy(document);bad['timeline'][1]['data']['method']='instance_eval'
refuses {R::Document.validate(bad)}
bad=R::Document.copy(document);bad['timeline'][1]['t']=-1
refuses {R::Document.validate(bad)}
bad=R::Document.copy(document);bad['timeline'][0]['data']['snapshot']['p']=[1]
refuses {R::Document.validate(bad)}
puts 'PASS recording library: directory authority, TXT/JSON, copy export, import, rename, exact deletion, UTF-8, account isolation and invalid-file rejection'
