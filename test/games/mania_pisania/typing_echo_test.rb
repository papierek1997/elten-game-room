require_relative '../../support/room_interface'
require_relative '../../../lib/mania_pisania/client'

class TypingEchoTranslator
  attr_reader :calls

  def initialize
    @calls = []
  end

  def back_translate(text, table:)
    @calls << [text, table]
    raise GameRoomTyping::BrailleUnavailable, 'incomplete prefix' if text == '⠠'
    {'⠁' => 'a', '⠁⠃' => 'ab', '⠠⠁' => 'A'}.fetch(text)
  end
end

class TypingEchoSettings
  attr_accessor :typing_echo
end

translator = TypingEchoTranslator.new
practice = GameRoomTyping::Practice.allocate
practice.instance_variable_set(:@options, {'variant' => 'free', 'input' => 'braille'})
practice.instance_variable_set(:@engine, Struct.new(:correct_words, :mistakes).new(0, 0))
practice.instance_variable_set(:@translator, translator)
practice.instance_variable_set(:@table, 'polish_integral')
practice.instance_variable_set(:@buffer, '')

settings = TypingEchoSettings.new
client = GameRoomTyping::Client.allocate
client.instance_variable_set(:@practice, practice)
client.instance_variable_set(:@settings, settings)
spoken = []
client.define_singleton_method(:prompt_speech_pending?) { false }
client.define_singleton_method(:announce) { |text, stop:| spoken << [text, stop]; true }

settings.typing_echo = 'characters'
assert(!client.send(:echo_input, '⠠'), 'Incomplete capital prefix was announced')
practice.instance_variable_set(:@buffer, '⠠')
assert(client.send(:echo_input, '⠁'), 'Braille capital letter echo was not announced')
settings.typing_echo = 'words'
practice.instance_variable_set(:@buffer, '⠁⠃')
assert(client.send(:echo_input, ' '), 'Braille word echo was not announced')

assert(spoken == [['A', true], ['ab', true]], 'Braille echo did not use back-translated text')
assert(translator.calls.all? { |_text, table| table == 'polish_integral' }, 'Braille echo did not use the selected table')
puts 'PASS Mania Pisania braille typing echo: incomplete prefixes, capital letters and words use the selected Liblouis table'
