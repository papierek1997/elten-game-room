require 'tmpdir'
require_relative '../../support/room_interface'
require_relative '../../../lib/mania_pisania/client'

# The original mock prefix test cannot establish how the bundled tables
# handle incomplete number/capital markers. Exercise the real DLL and the
# actual Client#input exception boundary, without speech or a live account.
Dir.mktmpdir('typing-echo-') do |cache|
  program = EltenGameRoom.allocate
  program.define_singleton_method(:cache_path) { |path| File.join(cache, path) }
  program.define_singleton_method(:read_json) { |_path, default:| default }
  translator = GameRoomTyping::LibLouis.discover(program: program)
  [['polish_integral', "\u283c"], ['english_g1', "\u2820"], ['english_g1', "\u283c"]].each do |table, marker|
    %w[characters words characters_and_words].each do |echo|
      practice = GameRoomTyping::Practice.new(
        options: {'variant' => 'free', 'input' => 'braille'}, word_bank: nil,
        seed: 1, multiplayer: false, text: 'test more', translator: translator, table: table)
      practice.start
      client = GameRoomTyping::Client.allocate
      client.instance_variable_set(:@practice, practice)
      client.instance_variable_set(:@settings, Struct.new(:typing_echo).new(echo))
      client.instance_variable_set(:@replay, Struct.new(:state).new({round: 1}))
      spoken=[]
      client.define_singleton_method(:announce) { |text, **_options| spoken << text; true }
      client.define_singleton_method(:prompt_speech_pending?) { false }
      client.define_singleton_method(:present) {}
      client.define_singleton_method(:alert) { |message| raise "Unexpected round cancellation: #{message}" }
      client.input('q')
      assert(spoken.empty? && practice.buffer.empty? && practice.errors==0,'A non-braille key was spoken or entered')
      client.input(marker)
      client.input(' ')
      assert(client.instance_variable_get(:@practice).equal?(practice), 'Echo retired a valid braille practice')
      assert(practice.errors == 1 && !practice.finished?, 'Incomplete word did not use ordinary error handling')
      translator.translate(practice.current_word.downcase, table: table).each_char { |cell| client.input(cell) }
      client.input(' ')
      assert(practice.finished? && practice.result.values_at('words', 'errors') == [1, 1],
        'Typing could not continue normally after the incomplete word')
    end
  end
ensure
  translator&.instance_variable_get(:@library)&.close
end
puts 'PASS native braille echo: incomplete markers count as word errors and do not abort typing'
