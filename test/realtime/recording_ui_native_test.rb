require_relative '../support/background_help_native'
require_relative '../support/recordings'
require_relative '../../lib/recordings/ui'
require EltenTestHost.file('src/ui/controls/menu.rb')

module GlobalMenu
  class << self
    attr_accessor :form
    def opened?; false; end
    def ctitems
      menu=EltenAPI::Controls.const_get(:Menu).new
      form.fields[form.index].context(menu,false) if form
      menu.items
    end
  end
end

class ReplayNativeDriver
  def initialize; @now=0.0; @previous=[]; end
  def tick(_); sample([]); end
  def sample(keys)
    @now+=0.016
    raw="\0"*256
    keys.each { |key| raw.setbyte(key,0x80) }
    events=(@previous-keys).map { |key| [key,false] }+(keys-@previous).map { |key| [key,true] }
    EltenAPI::KeyboardState.update(raw_state:raw,events:events,now:@now,pressed_implies_held:false,synthesize_repeats:false)
    @previous=keys
    $input_frame_serial=$input_frame_serial.to_i+1
    $keyboard_state_frame_serial=$input_frame_serial
    $keyboard_state_frame_thread=Thread.current
  end
  def frame(form,keys=[])
    sample(keys)
    GlobalMenu.form=form
    $activecontrols=[form,form.fields[form.index]]
    keyprocs
    form.update
  end
end

program=Object.new
program.define_singleton_method(:recording_library) {nil}
ui=GameRoomRecordings::UI.new(program)
driver=ReplayNativeDriver.new
$native_tutorial_driver=driver
GameRoomLocalization.boot(settings:{'interface_language'=>'en','known_languages'=>['en']})
value=RecordingTest.document
value['metadata']['duration_ms']=15000
player=GameRoomRecordings::Player.new(value,clock:-> {0.0},renderer:->(clock) {RecordingTest::Audio.new([],clock)})
form=ui.send(:player_form,player)
field=form.fields.first
assert(field.is_a?(Button) && !field.is_a?(ListBox),'Playback is still a command list')
form.focus
driver.frame(form,[0x20])
assert(player.playing,'Space did not start playback exactly once')
driver.frame(form)
assert(GlobalMenu.ctitems.any? { |item| item[3]=='' && item[0]=='Pause replay (Space)' },'Native menu does not name the working Space key')
assert(GlobalMenu.ctitems.none? { |item| [:p,:b,:f].include?(item[3]) },'Obsolete P/B/F shortcuts remain in the native menu')
driver.frame(form,[0x20])
assert(!player.playing,'Space did not pause exactly once through the native Button')
driver.frame(form)
driver.frame(form,[0x11,0x20])
assert(!player.playing,'Ctrl+Space bypassed the unmodified playback key')
driver.frame(form)
driver.frame(form,[0x50])
assert(!player.playing,'Obsolete P still toggles playback')
driver.frame(form)
driver.frame(form,[0x27])
assert(player.position==5000,'Right arrow did not seek forward five seconds')
driver.frame(form)
assert(GlobalMenu.ctitems.any? { |item| item[0]=='Back 5 seconds (Left arrow)' && item[3]=='' },'Menu lacks the working left-arrow shortcut')
driver.frame(form,[0x11,0x25])
assert(player.position==5000,'Ctrl+Left became an unmodified seek')
driver.frame(form)
driver.frame(form,[0x25])
assert(player.position==0,'Left arrow did not rewind to the beginning')
driver.frame(form)
driver.frame(form,[0x32])
assert(player.seat==1,'Plain 2 did not change the listening perspective')
driver.frame(form)
SpeechOutput.reset
driver.frame(form,[0x53])
assert(SpeechOutput.calls.last[0]=='Alice, 0. Bob, 0','S did not use the game score announcement')
driver.frame(form)
SpeechOutput.reset
driver.frame(form,[0x54])
assert(SpeechOutput.calls.last[0]=='Alice serves.','T did not read the recorded server')
driver.frame(form)
tips=GameRoomContextHelp.field_tips(field)
assert(tips.any? { |tip| tip.start_with?('S,') } && tips.none? { |tip| tip.start_with?('Ctrl+') },'F1 disagrees with the plain native menu bindings')
assert(tips.any? { |tip| tip.start_with?('Space,') } && tips.any? { |tip| tip.start_with?('Right arrow,') },'F1 does not name Space and the available seek arrow')
driver.frame(form,[0x09])
assert(form.index==1,'Native Tab did not leave the player field')
driver.frame(form)
driver.frame(form,[0x50])
assert(!player.playing,'A letter in the perspective list changed playback')
driver.frame(form)
driver.frame(form,[0x27])
assert(player.position==0,'An arrow outside the player field changed playback position')
player.close

# Use the real strict EditBox constructor, not a fixture accepting two
# positional arguments. All text/history paths use this same dialog.
original=GameRoomUI::Form.instance_method(:wait)
opened=[]
GameRoomUI::Form.define_method(:wait) {opened << fields.first}
begin
  %w[en pl cs es ru].each do |language|
    GameRoomLocalization.boot(settings:{'interface_language'=>language,'known_languages'=>[language]})
    bytes=GameRoomRecordings::Document.text_header(game_name:'UNO',players:['Żaneta','Борис'])+"Żółta karta.\n"
    ui.open_bytes(bytes,'.txt')
    text=opened.last
    assert(text.is_a?(GameRoomUI::HelpText),'UNO history did not open a native read-only text field')
    assert((text.flags&EditBox::Flags::ReadOnly)>0 && (text.flags&EditBox::Flags::MultiLine)>0,'History has incorrect native text flags')
    assert(text.text.include?('Żółta karta.') && text.text.include?('Борис'),'History lost Unicode text')
    localized=GameRoomLocalization.translate('Replay player')
    assert(language=='en' || localized!='Replay player',"#{language}: player label is not translated")
    %w[Space Left\ arrow Right\ arrow].each do |key|
      assert(language=='en' || GameRoomLocalization.translate(key)!=key,"#{language}: #{key} is not translated")
    end
  end
ensure
  GameRoomUI::Form.define_method(:wait,original)
end
puts 'PASS native replay UI: playfield, unmodified context shortcuts, focus isolation, dynamic help, score/serve/perspective and strict Unicode history text dialogs'
