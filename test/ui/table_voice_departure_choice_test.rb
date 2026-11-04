require_relative '../support/room_interface'
require_relative '../../lib/table_voice_membership'

module Conference
  class << self
    attr_accessor :channel, :leaves
    def opened?; !channel.nil?; end
    def leave; self.leaves+=1; self.channel=nil; true; end
  end
end

GameRoomLocalization.boot(settings:{'interface_language'=>'en','known_languages'=>['en']})
voice={'status'=>'ready','head'=>'voice-head','channel_id'=>555,'name'=>'Our table','creator'=>'Bob','password'=>''}
table={'__id'=>20,'owner'=>'Bob','game'=>'four_in_a_row','game_options'=>'{}','voice'=>voice}
klass=Class.new(EltenGameRoom)
klass.define_singleton_method(:cancel_new_table_notice) { |_| }

def departure_app(klass,table,result)
  app=klass.allocate
  lobby=Object.new
  lobby.define_singleton_method(:owner_of) { |row| row['owner'] }
  lobby.define_singleton_method(:table_id) { |row| row['__id'] }
  app.instance_variable_set(:@lobby,lobby)
  app.instance_variable_set(:@room_membership_trackers,{20=>:own,21=>:other})
  app.define_singleton_method(:game_definition) { |_| nil }
  app.define_singleton_method(:run_network_task) { |*,&operation| operation.call }
  app.define_singleton_method(:leave_current_table) { |_| @test_leaves=@test_leaves.to_i+1; result }
  app.define_singleton_method(:play_game_sound) { |_| }
  app.define_singleton_method(:alert) { |message| raise message }
  app.define_singleton_method(:confirm) { |_| raise 'Connected table used the two-option dialog' }
  app.send(:remember_table_voice,table)
  app
end

[0,1,2,:escape].each do |answer|
  [true,nil,false].each do |result|
    Conference.channel=Struct.new(:id,:name).new(555,'Our table')
    Conference.leaves=0
    app=departure_app(klass,table,result)
    shown=[]
    Form.driver=->(form) do
      list=form.fields.first
      shown << list.options
      assert(list.options==['No','Yes','Leave only the table'],'Incorrect order of departure options')
      assert(list.index==0,'Departure no longer defaults to No')
      if answer==:escape
        form.cancel_button.trigger(:press)
      else
        list.index=answer
        form.accept_button.trigger(:press)
      end
    end
    left=app.send(:leave_table_from_screen,table)
    selected=answer==1 || answer==2
    successful=selected && result==true
    assert(left==successful,'Departure choice bypassed cancellation or the confirmed leave result')
    assert(app.instance_variable_get(:@test_leaves).to_i==(selected ? 1 : 0),'Wrong number of table departure attempts')
    assert(Conference.leaves==(successful && answer==1 ? 1 : 0),'Conference disconnected for cancellation, failure or table-only departure')
    trackers=app.instance_variable_get(:@room_membership_trackers)
    assert(trackers.key?(20)!=successful && trackers[21]==:other,'Table cleanup happened early or removed another table')
    assert(shown.size==1,'Confirmation was repeated')
  end
end

# A withdrawn invitation still belongs to the user's connected table channel.
Conference.channel=Struct.new(:id,:name).new(555,'Our table')
Conference.leaves=0
app=departure_app(klass,table,true)
Form.driver=->(form) {form.fields.first.index=2;form.accept_button.trigger(:press)}
assert(app.send(:leave_table_from_screen,table.merge('voice'=>GameRoomTableVoice.empty)),'Cleared invitation hid table-only departure')
assert(Conference.leaves==0,'Cleared invitation disconnected the retained conference')

# The extra choice is not offered merely because some other conference is open.
Conference.channel=Struct.new(:id,:name).new(555,'Different conference with a reused ID')
Conference.leaves=0
app=departure_app(klass,table,true)
questions=[]
app.define_singleton_method(:confirm) { |question| questions<<question;true }
Form.driver=->(_) {raise 'An unrelated conference enabled the three-option dialog'}
assert(app.send(:leave_table_from_screen,table),'Ordinary confirmation failed')
assert(questions==['Do you want to leave the table?'] && Conference.leaves==0,'Ordinary departure changed an unrelated conference')
%w[pl cs es ru].each do |language|
  GameRoomLocalization.boot(settings:{'interface_language'=>language,'known_languages'=>[language]})
  Conference.channel=Struct.new(:id,:name).new(555,'Our table')
  app=departure_app(klass,table,true)
  Form.driver=->(form) do
    labels=form.fields.first.options
    expected=['No','Yes','Leave only the table'].map { |label| GameRoomLocalization.translate(label) }
    assert(labels==expected && labels.last!='Leave only the table',"#{language}: departure choices are not translated")
    assert(labels.all? { |label| label.encoding==Encoding::UTF_8 },"#{language}: departure labels have mixed encoding")
    form.cancel_button.trigger(:press)
  end
  assert(app.send(:leave_table_from_screen,table)==false,"#{language}: Escape confirmed a departure")
end
puts 'PASS leave choices: No/Yes/table-only order, Escape, nil/false rejection, confirmed cleanup, retained channel identity and unrelated-conference isolation'
