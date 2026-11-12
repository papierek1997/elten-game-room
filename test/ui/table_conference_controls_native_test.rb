require_relative '../support/tournament_context_native'
require EltenTestHost.file('src/ui/controls/static.rb')
require EltenTestHost.file('src/ui/controls/grid_box.rb')
Object.const_set(:Static, EltenAPI::Controls.const_get(:Static))
Object.const_set(:GridBox, EltenAPI::Controls.const_get(:GridBox))
require_relative '../../lib/game_surfaces'
require_relative '../../lib/game_history_navigation'
require_relative '../../lib/game_layout'

module Conference
  class << self
    attr_accessor :channel, :muted
    attr_reader :moves, :turns
    def opened?; channel != nil; end
    def move(x,y); (@moves ||= []) << [x,y]; end
    def turn(degrees); (@turns ||= []) << degrees; end
    def get_coordinates; [8,9]; end
  end
end
Channel = Struct.new(:id,:width,:height)
Conference.channel=Channel.new(5,30,20)
Conference.muted=false
calls=[]
program=Object.new
program.define_singleton_method(:toggle_conference_microphone) do
  calls << :microphone
  GameRoomConferenceControls.toggle_microphone
end
driver=TournamentNativeDriver.new

field=ListBox.new(['Person'],header:'Table',quiet:true)
close=Button.new('Close')
form=GameRoomUI::Form.new([field,close],program:program,quiet:true)
form.game_room_table_controls=true
form.cancel_button=close
form.hide(close)
close.on(:press) { form.resume }
driver.step('Table',[17,16,77])
driver.step('Table',[17,16,77]) do
  assert(Conference.muted && calls.size==1,'First native frame with cleared active controls lost microphone shortcut')
  assert(SpeechOutput.calls.any? { |call|call.first=='Microphone muted' },'Muting was not announced')
end
driver.step('Table') { assert(calls.size==1,'Held microphone shortcut toggled more than once') }
driver.step('Table',[17,16,77])
driver.step('Table') do
  assert(!Conference.muted && calls.size==2,'Second microphone press did not unmute')
  assert(SpeechOutput.calls.any? { |call|call.first=='Microphone unmuted' },'Unmuting was not announced')
  item=TournamentNativeContext.items(form).find { |row|row.first=='Mute microphone' }
  assert(item && item.last=='M','Table context omits the shared microphone command or shortcut')
  item[1].call
  assert(Conference.muted && calls.size==3,'Menu does not use the same native microphone state')
  assert(TournamentNativeContext.items(form).any? { |row|row.first=='Unmute microphone' },'Menu label did not follow native mute state')
end
driver.step('Table',[27])
form.wait
driver.finish

outside=GameRoomUI::Form.new([field],program:program,quiet:true)
assert(!TournamentNativeContext.items(outside).any? { |row|row.first.include?('microphone') },'Microphone action leaked outside a table')
Conference.channel=nil
assert(!TournamentNativeContext.items(form).any? { |row|row.first.include?('microphone') },'Disconnected conference still offers a mute action')

layout=GameRoomLayout::Screen.new(view_spec:GameRoomLayout::ViewSpec.new,user_items:['Alice'],phase: :waiting)
layout.form.game_room_program=program
layout.chat.set_text('unfinished draft')
layout.form.index=layout.form.fields.index(layout.chat)
assert(layout.channel_space.nil?,'Channel space exists before a conference is connected')
Conference.channel=Channel.new(6,30,20)
layout.refresh_conference_controls
space=layout.channel_space
assert(space.is_a?(Static),'Channel space is not the native Static control')
assert(layout.form.fields.index(space)==layout.form.fields.index(layout.voice_button)+1,'Channel space is not immediately after voice conversation')
assert(layout.form.instance_variable_get(:@hidden)[layout.form.fields.index(layout.back_button)],'Inserting space exposed the hidden Leave control')
assert(!layout.form.instance_variable_get(:@hidden)[layout.form.fields.index(layout.chat)],'Inserting space hid the chat instead of shifting native hidden flags')
assert(layout.form.fields[layout.form.index].equal?(layout.chat) && layout.chat.text=='unfinished draft','Connecting lost focus or chat draft')
space.trigger(:key_up)
space.trigger(:key_right)
assert(Conference.moves==[[0,-1],[1,0]],'Space control does not delegate movement to native Conference')
state="\0"*256
state.setbyte(16,0x80)
EltenAPI::KeyboardState.update(raw_state:state,events:[[16,true]],now:99,pressed_implies_held:false,synthesize_repeats:false)
space.trigger(:key_left)
assert(Conference.turns==[-45],'Shift+arrow does not delegate native rotation')
# The Shift state attached to the arrow press survives release in that frame.
released="\0"*256
held=released.dup
held.setbyte(16,0x80)
held.setbyte(37,0x80)
EltenAPI::KeyboardState.update(raw_state:released,events:[],now:100,pressed_implies_held:false,synthesize_repeats:false)
EltenAPI::KeyboardState.update(raw_state:released,
  events:[[16,true,held],[37,true,held],[37,false,released],[16,false,released]],
  now:101,pressed_implies_held:false,synthesize_repeats:false)
space.trigger(:key_left)
assert(Conference.turns==[-45,-45] && Conference.moves==[[0,-1],[1,0]],
  'Releasing Shift before dispatch changed a native rotation into movement')
menu=Menu.new
space.context(menu,false)
position=menu.items.find { |row|row.first=='Read current position' }
assert(position,'Space context omits position')
position[1].call
assert(SpeechOutput.calls.any? { |call|call.first=='8, 9' },'Position does not use native conference coordinates')
Conference.channel=nil
layout.refresh_conference_controls
assert(layout.form.instance_variable_get(:@hidden)[layout.form.fields.index(space)],'Channel space remains visible after disconnect')
assert(layout.form.fields[layout.form.index].equal?(layout.chat),'Disconnect stole unrelated focus')
Conference.channel=Channel.new(7,30,20)
layout.refresh_conference_controls
assert(layout.channel_space.equal?(space),'Reconnecting replaced the native space control')
layout.form.index=layout.form.fields.index(space)
Conference.channel=nil
layout.refresh_conference_controls
assert(layout.form.fields[layout.form.index].equal?(layout.voice_button),'Disconnect left focus on an invisible channel space')
puts 'PASS native table conference controls: first-frame shortcut, no held-key repeats, shared mute state and speech/menu, scope, native movement/rotation, membership visibility and preserved draft/focus'
