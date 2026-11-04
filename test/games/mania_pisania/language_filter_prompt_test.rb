# encoding: UTF-8
require_relative '../../support/game_option_editor_native'
%w[practice settings].each { |name| NativeOptionSource.load(File.join(NativeOptionSource::ROOT,"lib/mania_pisania/#{name}.rb")) }
def assert(value,message); NativeOptionTest.assert(value,message); end
game=GameRoomGames::ManiaPisania.new
%w[en pl cs es ru].each do |primary|
  [[],[primary],%w[cs es],%w[en pl cs es ru]].each do |known|
    GameRoomLocalization.boot(host_language:primary,known_languages:known)
    expected=known.empty? ? [primary] : known
    definitions=game.option_editor_definitions
    words=definitions.find { |d| d.key=='word_language' }
    assert(words.choices.map(&:value).sort==expected.sort,'Wrong word languages')
    text=definitions.find { |d| d.key=='text' }
    ids=text.choices.map(&:value).select { |id| GameRoomTyping::TextLibrary::BUILTIN.key?(id) }
    assert(ids.length==expected.length*5,'Wrong story count')
    assert(ids.all? { |id| expected.include?(GameRoomTyping::Languages.text_language(id)) },'Unexpected story language')
    tables=GameRoomTyping::BrailleCatalog::FILES.keys.select { |id| GameRoomTyping::BrailleCatalog.visible?(id) }
    assert(tables.map { |id| GameRoomTyping::BrailleCatalog.language(id) }.uniq.sort==expected.sort,'Wrong braille languages')
    defaults=game.table_creation_options('variant'=>'words')
    assert(expected.include?(defaults['word_language']),'Hidden dictionary remains the default')
    assert(game.options_from_json('{"variant":"words","word_language":"ru"}')['word_language']=='ru','Viewer changed canonical dictionary')
  end
end
NativeOptionTest.language='cs'
driver=NativeOptionTest::Driver.new(game,initial_options:game.table_creation_options('variant'=>'memory'))
assert(!driver.visible?('word_language'),'Single-language picker is visible')
driver.focus(driver.form.cancel_button); driver.press([13]); driver.finished
GameRoomLocalization.boot(host_language:'cs',known_languages:%w[cs es])
driver=NativeOptionTest::Driver.new(game,initial_options:game.table_creation_options('variant'=>'memory'))
assert(driver.visible?('word_language'),'Multiple-language picker is hidden')
assert(driver.control('word_language').options.length==2,'Native dictionary list is not filtered')
assert(driver.control('text').options.length==13,'Native story list is not filtered')
driver.focus(driver.form.cancel_button); driver.press([13]); driver.finished
imports=NativeOptionTest::Program.new
imports.define_singleton_method(:read_json) do |_path, default:|
  {'texts'=>%w[en cs es].to_h { |language| ["local:#{language}",{'title'=>language,'text'=>'test','language'=>language}] }}
end
library=GameRoomTyping::TextLibrary.new(imports)
assert(library.entries.select { |entry| entry['imported'] }.map { |entry| entry['title'] }.sort==%w[cs es],'Imported text language is ignored')
assert(library.fetch('local:en')['text']=='test','Filtered imported text was lost')
GameRoomLocalization.boot(host_language:'en')
program=NativeOptionTest::Program.new
program.define_singleton_method(:read_json) { |_path, default:| {'braille_table'=>'polish_integral'} }
assert(GameRoomTyping::Settings.new(program)['braille_table']=='english_g1','Old foreign-language default was retained')
%w[free words memory survival].each do |variant|
  translator=Object.new
  translator.define_singleton_method(:translate) { |word, table:| word }
  practice=GameRoomTyping::Practice.new(options:{'variant'=>variant,'input'=>'mixed'},word_bank:->(_s,i) { i==0 ? 'one' : 'two' },
    text:variant=='free' ? 'One two. Three four.' : nil,seed:3,multiplayer:false,recording_seconds:100,translator:translator)
  practice.start
  notice=practice.take_notices.first[1]
  repeat=practice.repeat
  assert(repeat.start_with?('Keyboard. ','Braille. '),'Repeat omits input method')
  if variant=='free'
    assert(notice.start_with?('One two. '),'Method precedes the full sentence')
    assert(notice=='One two. '+repeat,'Wrong sentence, method, word order')
    %w[One two.].each do |word|
      word.each_char { |character| practice.input(character) }; practice.input(' ')
    end
    assert(practice.take_notices.last[1]=='Three four. '+practice.repeat,'Next sentence has wrong announcement order')
  else
    assert(notice==repeat,'Prompt and repeated word disagree')
    if variant=='memory'
      practice.prompt_finished
      'one'.each_char { |character| practice.input(character) }; practice.input(' ')
      expected=Digest::SHA256.digest('3:1').getbyte(0).odd? ? 'Braille. ' : 'Keyboard. '
      assert(practice.take_notices.last[1]==expected+'two','New memory word announces the earlier word input method')
      assert(practice.repeat==expected+'two','Memory repeat announces the wrong input method')
    end
  end
end
puts 'PASS known-language filters, native hidden picker, literary default migration and mixed prompt ordering.'
