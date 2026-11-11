# encoding: UTF-8
require_relative '../../support/game_option_editor_native'
NativeOptionSource.load(File.join(NativeOptionSource::ROOT,'lib/mania_pisania/practice.rb'))
def assert(value,message); NativeOptionTest.assert(value,message); end

practice=GameRoomTyping::Practice.new(options:{'variant'=>'free','input'=>'keyboard'},word_bank:nil,seed:1,multiplayer:false)
practice.start
'Ala ma kota'.each_char { |character| practice.input(character) }
assert(practice.display_buffer=='Ala ma kota','Own text loses completed words')
assert(practice.engine.correct_words==2,'Own typing word statistics changed')
practice.finish
assert(practice.display_buffer=='Ala ma kota','Finishing discarded the text')
spec=GameSurfaces::TypingSpec.new(round:1,enabled:true,own_text:true,commands:[])
surface=GameSurfaces::TypingSurface.new(spec)
surface.present(buffer:practice.display_buffer,braille:false)
field=surface.fields.first
field.restore_selection(index:0,check:3)
surface.present(buffer:practice.display_buffer,braille:false)
assert(field.index==0 && field.check==3,'Refresh prevents reading/selection')
assert(field.send(:get_check)=='Ala','Native selection cannot read the own text')
Object.const_set(:Clipboard,Module.new) unless defined?(Clipboard)
Clipboard.singleton_class.class_eval { attr_accessor :text }
field.send(:copy)
assert(Clipboard.text=='Ala','Native copy lost the selected text')
field.display('słowo '*300)
assert(field.text=='słowo '*300,'Own text is truncated at the old per-word field limit')
finished=GameSurfaces::TypingSurface.new(GameSurfaces::TypingSpec.new(round:1,enabled:false,own_text:true,commands:[]))
finished.present(buffer:practice.display_buffer,braille:false)
assert(finished.fields.first.is_a?(GameSurfaces::TypingField),'Result hides the own text')
assert(finished.fields.first.text=='Ala ma kota','Result text differs from typed text')
received=[]
field.on_character=->(character) { received << character }
field.define_singleton_method(:key_pressed?) { |_code| false }
field.define_singleton_method(:held_in_frame?) { |_code| false }
field.send(:update_braille,['q'])
assert(received.empty?,'A non-braille key reached practice')
puts "PASS own-text native reading, selection, copy, completed transcript and ignored non-braille keys; #{NativeOptionTest.checks} checks"
