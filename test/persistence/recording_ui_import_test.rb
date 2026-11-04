require_relative '../support/ui'
require_relative '../support/recordings'
require_relative '../../lib/recordings/ui'

module RecordingImportFixture
  class Delivery
    attr_reader :removed
    def incoming; [{'description'=>'Test','sender'=>'Alice','date'=>1_800_000_000}]; end
    def receive(_); {bytes:GameRoomRecordings::Document.text_header(game_name:'Scopa',players:%w[Alice Bob])+"History\n",extension:'.txt'}; end
    def remove_received(ref); @removed=ref; true; end
  end
end

Dir.mktmpdir('pg-recording-ui-') do |directory|
  [[:preview,false],[:keep,false],[:keep,true],[:failure,true]].each_with_index do |(scenario,answer),index|
    library=GameRoomRecordings::Library.new(RecordingTest::Program.new(File.join(directory,index.to_s)),account:'Bob',current_account:-> {'Bob'})
    program=Object.new
    program.define_singleton_method(:recording_library) {library}
    delivery=RecordingImportFixture::Delivery.new
    ui=GameRoomRecordings::UI.new(program,delivery:delivery)
    choices=[[:open,0],[:open,scenario==:preview ? 0 : 1]]
    asked=[];viewed=[]
    ui.define_singleton_method(:select) { |*args,**| choices.shift }
    ui.define_singleton_method(:task) { |*args,&operation| scenario==:failure && args[0]=='Importing history or replay' ? nil : operation.call }
    ui.define_singleton_method(:open_bytes) { |*packet| viewed << packet }
    ui.define_singleton_method(:confirm) { |message| asked << message; answer }
    ui.define_singleton_method(:alert) { |*| }
    ui.import_messages
    if scenario==:preview || scenario==:failure
      raise 'Preview or failed import offered deletion' unless asked.empty? && !delivery.removed && library.list.empty?
    else
      raise 'Successful import did not ask exactly once' unless asked.size==1 && library.list.size==1
      raise 'Recipient choice was ignored' unless !!delivery.removed==answer
    end
    raise 'Preview did not open the recording' if scenario==:preview && viewed.empty?
  end
end
puts 'PASS recording import UI: preview/failure never delete; persistent import asks once and honours Yes/No'
