# encoding: UTF-8
require_relative '../../support/game_option_form'
require_relative '../../../lib/mania_pisania/practice'

%w[Hello PŘÍLIŠ Niño ПРИВЕТ ŻÓŁĆ].each do |word|
  %w[free words memory survival].each do |variant|
    practice=GameRoomTyping::Practice.new(options:{'variant'=>variant,'input'=>'keyboard'},
      word_bank:->(_seed,_index) { word },seed:1,multiplayer:false,text:word,recording_seconds:100)
    practice.start
    practice.prompt_finished
    word.swapcase.each_char { |character| practice.input(character) }
    practice.input(' ') unless variant=='survival'
    assert(practice.engine.correct_words==1 && practice.errors==0,"Case rejected for #{word}/#{variant}")
  end
end
translator=Object.new
seen=[]
translator.define_singleton_method(:translate) { |word,table:| seen << word; word.each_char.map { |c| (0x2800+c.ord%255).chr(Encoding::UTF_8) }.join }
%w[free words memory survival].each do |variant|
  practice=GameRoomTyping::Practice.new(options:{'variant'=>variant,'input'=>'braille'},word_bank:->(_s,_i) { 'Hello' },
    text:'Hello',seed:1,multiplayer:false,translator:translator,recording_seconds:100)
  practice.start; practice.prompt_finished
  translator.translate('hello',table:'test').each_char { |cell| practice.input(cell) }
  practice.input(' ') unless variant=='survival'
  assert(practice.engine.correct_words==1 && practice.errors==0,'Braille required capital indicators')
end
assert(seen.none? { |word| word != word.downcase },'Braille source retains capitals')
puts 'PASS case-insensitive keyboard and lowercase braille targets across all variants and five alphabets.'
