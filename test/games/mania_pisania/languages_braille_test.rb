# encoding: UTF-8
require 'tmpdir'
require_relative '../../support/game_option_form'
require_relative '../../../lib/mania_pisania/practice'
require_relative '../../../lib/mania_pisania/braille'
require_relative '../../../lib/mania_pisania/settings'

Dir.mktmpdir('mania-languages-') do |cache|
  app=EltenGameRoom.allocate
  app.define_singleton_method(:cache_path) { |path| File.join(cache,path) }
  app.define_singleton_method(:read_json) { |_path, default:| default }
  translator=GameRoomTyping::LibLouis.discover(program:app)
  mapping={'en'=>['Typoholism','english_g1','hello'], 'pl'=>['Mania pisania','polish_integral','kot'],
    'cs'=>['Psanománie','czech_g1','příliš'], 'es'=>['Teclamanía','spanish_g1','niño'], 'ru'=>['Клавомания','russian_literary','привет']}
  mapping.each do |language,(name,table,word)|
    GameRoomLocalization.boot(host_language:language)
    game=GameRoomGames::ManiaPisania.new
    assert(game.name==name,"Wrong game name for #{language}: #{game.name}")
    expected_id = language == 'pl' ? 'apple_tree' : "apple_tree_#{language}"
    assert(game.default_options['text']==expected_id,'Default story does not match the interface language')
    assert(GameRoomTyping::Settings.new(app)['braille_table']==table,"Wrong default table for #{language}")
    text=translator.translate(word,table:table)
    assert(text.each_char.all? { |c| c.ord.between?(0x2800,0x28ff) },"Not braille for #{language}")
    assert(GameRoomTyping::KeyboardText.unsupported(word).empty?,"Unsupported language #{language}")
    library=GameRoomTyping::TextLibrary.new(app)
    assert(library.entries.all? { |e| language=='pl' ? !e['id'].match?(/_(en|cs|es|ru)\z/) : e['id'].end_with?('_'+language) },'Wrong story language')
    library.entries.each { |entry| GameRoomTyping::Document.new(library.fetch(entry['id'])['text']) }
    book=game.rule_book
    assert(book.documents.map(&:id)==[:rules,:controls,:touch_typing],"Missing third help document: #{language}")
    assert(book.documents[1].paragraphs.all? { |p| p.start_with?('- ') },'Shortcuts are not list items')
    # Both typing variants must accept actual cells produced by the native DLL.
    practice=GameRoomTyping::Practice.new(options:{'variant'=>'memory','input'=>'braille'}, word_bank:->(_s,i) { i==0 ? word : 'test' }, seed:1,multiplayer:false,translator:translator,table:table)
    practice.start
    assert(practice.take_notices.first[1]==GameRoomTyping::WordPrompt.new.announcement(word),'Memory prompt contains extra instructions')
    assert(practice.remaining_word.nil?,'Memory word remainder is exposed')
    replay=Struct.new(:state,:players).new({phase: :active, options: {'variant'=>'memory'}},['Alice'])
    assert(game.custom_game_shortcuts(replay,'Alice').none? { |shortcut| shortcut.key=='semicolon' },'Memory shortcut still exposes the remainder')
    practice.prompt_finished
    text.each_char { |cell| practice.input(cell) }; practice.input(' ')
    assert(practice.engine.correct_words==1,'Memory braille word rejected')
    practice=GameRoomTyping::Practice.new(options:{'variant'=>'free','input'=>'braille'},word_bank:nil,seed:1,multiplayer:false,text:word,translator:translator,table:table)
    practice.start
    text.each_char { |cell| practice.input(cell) }; practice.input(' ')
    assert(practice.finished? && practice.result['words']==1 && practice.result['errors']==0,'Free text braille failed')
    practice=GameRoomTyping::Practice.new(options:{'variant'=>'free','input'=>'braille'},word_bank:nil,seed:1,multiplayer:false,translator:translator,table:table)
    practice.start
    text.each_char { |cell| practice.input(cell) }; practice.input(' ')
    assert(practice.engine.correct_words==1,'Own text braille failed')
  end
ensure
  translator&.instance_variable_get(:@library)&.close
end
puts 'PASS five languages: names, real bundled Liblouis, literary defaults, all stories, three help documents, memory and free braille.'
