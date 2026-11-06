# encoding: UTF-8
require_relative '../../support/game_option_editor_native'
%w[lib/mania_pisania/practice.rb lib/game_rules_view.rb].each { |path| NativeOptionSource.load(File.join(NativeOptionSource::ROOT,path)) }
%w[en pl cs es ru].zip(%w[Hello ŻÓŁĆ PŘÍLIŠ Niño ПРИВЕТ]).each do |language,word|
  NativeOptionTest.language=language
  game=GameRoomGames::ManiaPisania.new
  book=game.rule_book
  expected_name={'en'=>'Survival mode','pl'=>'Tryb przetrwania','cs'=>'Režim přežití','es'=>'Modo supervivencia','ru'=>'Режим выживания'}.fetch(language)
  choice=game.option_definitions.find { |definition| definition.key=='variant' }.choices.find { |item| item.value=='survival' }
  NativeOptionTest.assert(choice.label==expected_name,'Survival mode label differs from the requested name')
  NativeOptionTest.assert(book.sections.none? { |section| section.id==:main_8 },'Inactivity retained its own section')
  memory=book.sections.find { |section| section.id==:main_9 }
  if language=='ru'
    NativeOptionTest.assert(memory.paragraphs.last=='Смешанный режим здесь — для неисправимых фанатов: приходится вспоминать не только слово, но и то, каким способом его нужно было набрать.',
      'Memory section lost the approved Russian mixed-mode explanation')
  else
    NativeOptionTest.assert(memory.paragraphs.last.match?(/nerd/),'Memory section is missing the final mixed-mode sentence')
  end
  if language=='pl'
    NativeOptionTest.assert(memory.paragraphs.last=='Tryb mieszany w tym przypadku jest dla nieuleczalnych nerdów, ponieważ należy odtworzyć z pamięci zarówno słowo, jak i sposób, w jaki należało je wpisać.','The supplied Polish sentence changed')
  end
  document=book.documents.first
  view=GameRoomRules::View.new('test',document:document)
  text=view.text_range(0,view.text_len-1)
  NativeOptionTest.assert(text.start_with?(document.introduction.first),'Binary intro is not above contents')
  NativeOptionTest.assert(!text.match?(/\n\r?\n/),'Binary help contains blank lines')
  headings=view.instance_variable_get(:@elements).select { |element| element.type==EditBox::Element::Header }
  NativeOptionTest.assert(headings.first.from>0,'Binary intro has a heading')
  NativeOptionTest.assert(view.text_range(headings.first.from,headings.first.to)==document.contents_title,'Binary contents offset is incorrect')
  document.sections.zip(headings.drop(1)).each do |section,heading|
    NativeOptionTest.assert(view.text_range(heading.from,heading.to)==section.title,'Binary heading offset is incorrect')
  end
  %w[free words memory survival].each do |variant|
    practice=GameRoomTyping::Practice.new(options:{'variant'=>variant,'input'=>'keyboard'},word_bank:->(_s,_i) { word },
      text:word,seed:1,multiplayer:false,recording_seconds:100)
    practice.start; practice.prompt_finished
    word.swapcase.each_char { |character| practice.input(character) }
    practice.input(' ') unless variant=='survival'
    NativeOptionTest.assert(practice.engine.correct_words==1 && practice.errors==0,'Binary case-insensitive input failed')
  end
end
puts "PASS binary case-insensitive gameplay and native help: #{NativeOptionTest.checks} checks."
