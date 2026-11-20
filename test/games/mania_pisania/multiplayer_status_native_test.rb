# encoding: UTF-8
require_relative '../../support/typing_native_form'

def assert(value, message); NativeOptionTest.assert(value, message); end

unless defined?(Session)
  module Session
    def self.name; 'Bob'; end
  end
end

NativeOptionTest.language = 'en'
game = GameRoomGames::ManiaPisania.new
players = %w[Alice Bob Carol]
repo = Object.new
repo.define_singleton_method(:players_for) { |_session| players }
repo.define_singleton_method(:actor_of) { |event, _session| event['actor'] }
repo.define_singleton_method(:event_id) { |event| event['id'] }
session = {'options'=>JSON.generate(game.normalize_options('variant'=>'free', 'text'=>'apple_tree')), '__table_owner'=>'Alice'}
events = []
append = lambda do |actor, action|
  commands = GameRoomActionPayload.commands(game.id, action)
  commands.each do |command|
    events << {'id'=>events.length + 1, 'actor'=>actor, 'action'=>command.action, 'value'=>command.value}
  end
  game.replay(session, events, repo)
end
waiting = game.replay(session, events, repo)
assert(game.surface_spec(waiting,'Bob').status.lines.length == players.length + 1, 'The waiting field omitted a player')
replay = append.call('Alice', {'action'=>'start', 'round'=>0, 'seed'=>12, 'scoring'=>1})
program = NativeOptionTest::Program.new
layout = nil
driver = NativeTypingFormDriver.new(program:program) do
  layout = GameRoomLayout::Screen.new(view_spec:game.game_view_spec(replay,'Bob'))
  layout.form.game_room_program = program
  layout.back_button.on(:press) { layout.form.resume }
  layout.form.wait
end
surface = layout.surface
field = surface.fields.find { |control| control.is_a?(EditBox) && control.header == 'Typing status' }
assert(field && field.text.lines.map(&:strip) == players.map { |name| "#{name}: typing" }, 'Active typing status omitted a player')
driver.focus(field)
field.restore_selection(index:7, check:5)
assert(NativeOptionUI.spoken.last.include?('Alice: typing') && NativeOptionUI.spoken.last.include?('Carol: typing'), 'Native focus did not read the full roster')

result = lambda do |actor, words, errors, wpm|
  append.call(actor, {'action'=>'result','round'=>1,'result'=>{'words'=>words,'errors'=>errors,
    'wpm'=>wpm,'levels'=>0,'elapsed_ms'=>30_000,'assisted'=>false}})
end
update = lambda do |snapshot, phase = :active|
  layout.update(view_spec:game.game_view_spec(snapshot,'Bob'), history_items:[], user_items:[],
    users_header:'Users', phase:phase, own_table:false)
end
speech_count = NativeOptionUI.spoken.length
replay = result.call('Carol',8,2,16.0)
update.call(replay)
assert(layout.surface.equal?(surface) && layout.form.fields[layout.form.index].equal?(field), 'A new result rebuilt the status field or moved focus')
assert(field.index == 7 && field.check == 5, 'A new result reset the selection')
assert(field.text.include?('Carol: 8 words, 2 errors, 16.0 WPM.') && field.text.include?('Bob: typing'), 'The partial results are incorrect')
generation = field.game_room_edit_generation
3.times { update.call(replay) }
assert(generation == field.game_room_edit_generation, 'An unchanged replay rewrote the native field')
replay = result.call('Alice',12,0,24.0)
update.call(replay)
assert(field.text.include?('Alice: 12 words, 0 errors, 24.0 WPM.') && field.text.include?('Carol: 8 words, 2 errors, 16.0 WPM.'), 'An arriving result erased a previous result')
assert(NativeOptionUI.spoken.length == speech_count, 'Refreshing results reread the native status or changed focus')
replay = result.call('Bob',10,1,20.0)
update.call(replay,:finished)
final = layout.surface.fields.find { |control| control.is_a?(EditBox) && control.header == 'Typing status' }
assert(replay.finished? && final && ['Alice: 12 words','Bob: 10 words','Carol: 8 words'].all? { |text| final.text.include?(text) },
  'Finishing the round hid some of the players’ results')
assert(final.text.include?('Alice won the game.'), 'Final status lost the match outcome')
driver.press([27])
driver.finished
puts "PASS multiplayer typing status, arrival-order independent results, retained controls/selection and quiet unchanged refresh; #{NativeOptionTest.checks} checks"
