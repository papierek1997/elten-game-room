# encoding: UTF-8
require 'tmpdir'
require_relative '../../support/game_option_editor_native'
%w[practice settings].each do |name|
  NativeOptionSource.load(File.join(NativeOptionSource::ROOT,"lib/mania_pisania/#{name}.rb"))
end
def assert(condition,message); NativeOptionTest.assert(condition,message); end
Dir.mktmpdir('mania-package-languages-') do |cache|
  app=NativeOptionTest::Program.new
  app.define_singleton_method(:cache_path) { |path| File.join(cache,path) }
  translator=GameRoomTyping::LibLouis.discover(program:app)
  %w[en pl cs es ru].zip(['Typoholism','Mania pisania','Psanománie','Teclamanía','Клавомания']).each do |language,name|
    NativeOptionTest.language=language
    game=GameRoomGames::ManiaPisania.new
    assert(game.name==name,"Packaged name is wrong for #{language}")
    table=GameRoomTyping::Settings.new(app)['braille_table']
    cells=translator.translate('test',table:table)
    assert(cells.each_char.all? { |cell| cell.ord.between?(0x2800,0x28ff) },'Packaged Liblouis failed')
    assert(game.rule_book.documents.map(&:id)==[:rules,:controls,:touch_typing],'Packaged help is incomplete')
    options=game.table_creation_options
    assert(options['word_language']==language,'Packaged default word language is wrong')
    bank=GameRoomTyping::WordBank.for_options(options)
    assert(GameRoomTyping::KeyboardText.unsupported(bank.call(42,0)).empty?,'Packaged dictionary did not load')
    item=GameRoomTyping::TextLibrary.new(app).fetch(options['text_id'])
    assert(item && item['text'].valid_encoding?,'Packaged story is unavailable')
    driver=NativeOptionTest::Driver.new(game,initial_options:options.merge('variant'=>'memory','input'=>'braille'))
    assert(driver.visible?('input'),'Braille selector is hidden in Memory Chain')
    assert(!driver.visible?('word_language'),'Single-language word selector must be hidden')
    driver.focus(driver.form.cancel_button)
    driver.press([13])
    assert(driver.finished.nil?,'Cancel changed options')
  end
  assert(translator.tables.length==32,'Packaged braille catalogue is incomplete')
  translator.tables.each { |id,_,_| assert(!translator.translate('test',table:id).empty?,"Packaged table #{id} failed") }
ensure
  translator&.instance_variable_get(:@library)&.close
end
puts "PASS binary-loaded Mania: five language catalogs, native Liblouis, stories, three help documents and native braille selector; #{NativeOptionTest.checks} checks"
