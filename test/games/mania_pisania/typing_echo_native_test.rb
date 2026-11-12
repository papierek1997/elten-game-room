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
    %w[words characters_and_words].product(['test more', nil]).each do |echo, text|
      practice = GameRoomTyping::Practice.new(
        options: {'variant' => 'free', 'input' => 'braille'}, word_bank: nil,
        seed: 1, multiplayer: false, text: text, translator: translator, table: table)
      practice.start
      client = GameRoomTyping::Client.allocate
      client.instance_variable_set(:@practice, practice)
      client.instance_variable_set(:@settings, Struct.new(:typing_echo).new(echo))
      client.instance_variable_set(:@replay, Struct.new(:state).new({round: 1}))
      client.define_singleton_method(:announce) { |_text, **_options| true }
      client.define_singleton_method(:prompt_speech_pending?) { false }
      client.define_singleton_method(:present) {}
      client.define_singleton_method(:alert) { |message| raise "Unexpected round cancellation: #{message}" }
      client.input(marker)
      client.input(' ')
      assert(client.instance_variable_get(:@practice).equal?(practice), 'Echo retired a valid braille practice')
      assert(practice.errors == 1 && !practice.finished?, 'Incomplete word did not use ordinary error handling')
      translator.translate((practice.current_word || 'more').downcase, table: table).each_char { |cell| client.input(cell) }
      client.input(' ')
      if text.nil?
        assert(practice.engine.correct_words == 1 && practice.buffer.empty?, 'Own-text typing accepted the marker as a word or lost the following word')
        practice.pause
        practice.resume
        assert(practice.errors == 1, 'Own-text pause lost the incomplete word error')
        practice.finish
      end
      assert(practice.finished? && practice.result.values_at('words', 'errors') == [1, 1],
        'Typing could not continue normally after the incomplete word')
    end
  end
  # Negative receipt shapes are controlled FFI returns, separate from the
  # real DLL cases above. Do not turn provider failure into an empty word.
  original = translator.instance_variable_get(:@back_translate)
  begin
    [[0, 0, false], [1, 0, true], [1, -1, false], [1, :overflow, false]].each do |ok, used, partial|
      translator.instance_variable_set(:@back_translate, lambda do |_path, _input, input_length, _output, output_length, *_rest|
        capacity = output_length.unpack1('l<')
        input_length.replace([0].pack('l<')) if partial
        output_length.replace([used == :overflow ? capacity + 1 : used].pack('l<'))
        ok
      end)
      begin
        translator.back_translate('⠁', table: 'polish_integral')
        raise 'A failed or incomplete provider receipt became an empty word'
      rescue GameRoomTyping::BrailleUnavailable
        # Expected: actual provider errors retain their exception boundary.
      end
    end
  ensure
    translator.instance_variable_set(:@back_translate, original)
  end
  assert(translator.back_translate('⠁', table: 'polish_integral') == 'a', 'Native translator was not restored')
ensure
  translator&.instance_variable_get(:@library)&.close
end
puts 'PASS native braille echo: incomplete markers count as word errors and do not abort typing'
