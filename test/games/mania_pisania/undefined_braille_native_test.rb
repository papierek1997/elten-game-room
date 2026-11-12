# encoding: UTF-8
require_relative '../../support/typing_native_form'
require_relative '../../support/temporary_directory'
NativeOptionSource.load(File.join(NativeOptionSource::ROOT, 'lib/mania_pisania/client.rb'))

def assert(value, message); NativeOptionTest.assert(value, message); end

GameRoomTest::TemporaryDirectory.create('mania-undefined-') do |cache|
  NativeOptionTest.language = 'en'
  echo_mode = 'characters'
  program = NativeOptionTest::Program.new
  program.define_singleton_method(:cache_path) { |path| File.join(cache,path) }
  program.define_singleton_method(:read_json) do |path, default:|
    path == GameRoomTyping::Settings::STORE ? {'typing_echo'=>echo_mode} : default
  end
  program.define_singleton_method(:play_sound_from_asset) { |*_args, **_options| true }
  translator = GameRoomTyping::LibLouis.discover(program:program)
  literal = '\\13457/'
  cells = translator.translate(literal,table:'english_nabcc')
  assert(translator.back_translate(cells,table:'english_nabcc') == literal, 'Literal text was mistaken for undefined braille')
  ["\u2840", "\u2880", "\u289d", "\u28ff"].each do |cell|
    begin
      translator.back_translate(cell,table:'polish_integral')
      raise 'Undefined 7/8-dot cell was accepted by a six-dot table'
    rescue GameRoomTyping::UndefinedBraille => exception
      assert(!exception.patterns.empty?, 'Undefined input lost the native dot numbers')
    end
  end
  mixed = GameRoomTyping::Practice.new(options:{'variant'=>'free','input'=>'braille'},
    word_bank:nil, seed:1, multiplayer:false, translator:translator, table:'polish_integral')
  mixed.start
  (translator.translate('ko',table:'polish_integral') + "\u285d" + translator.translate('t',table:'polish_integral')).each_char { |cell| mixed.input(cell) }
  mixed.input(' ')
  assert(mixed.errors == 1 && mixed.engine.correct_words == 0 && mixed.display_buffer.empty?,
    'Dropping an undefined cell turned the remaining defined letters into a correct word')
  original = translator.instance_variable_get(:@back_translate)
  begin
    [[0,0,false],[1,0,true],[1,-1,false],[1,:overflow,false]].each do |ok, used, partial|
      translator.instance_variable_set(:@back_translate, lambda do |path, input, input_length, output, output_length, typeform, spacing, mode|
        if (mode & 128) == 0
          original.call(path, input, input_length, output, output_length, typeform, spacing, mode)
        else
          capacity = output_length.unpack1('l<')
          input_length.replace([0].pack('l<')) if partial
          output_length.replace([used == :overflow ? capacity + 1 : used].pack('l<'))
          ok
        end
      end)
      begin
        translator.back_translate("\u285d",table:'polish_integral')
        raise 'Invalid secondary provider receipt was accepted'
      rescue GameRoomTyping::BrailleUnavailable
        # Only successful complete native receipts may classify typing input.
      end
    end
  ensure
    translator.instance_variable_set(:@back_translate,original)
  end
  %w[characters words characters_and_words].product(['test more', nil]).each do |mode, text|
    echo_mode = mode
    practice = GameRoomTyping::Practice.new(options:{'variant'=>'free','input'=>'braille'},
      word_bank:nil, seed:1, multiplayer:false, text:text, translator:translator, table:'polish_integral')
    practice.start
    practice.take_notices
    client = GameRoomTyping::Client.new(program, GameRoomGames::ManiaPisania.new)
    client.instance_variable_set(:@practice,practice)
    client.define_singleton_method(:covered?) { false }
    events = []
    client.define_singleton_method(:announce) do |value, stop:true|
      events << [value,stop]
      NativeOptionUI.speak(value)
      true
    end
    surface = GameSurfaces::TypingSurface.new(GameSurfaces::TypingSpec.new(round:1, enabled:true, own_text:text.nil?, commands:[]))
    client.instance_variable_set(:@surface,surface)
    surface.on_character = client.method(:input)
    client.send(:present)
    driver = NativeTypingFormDriver.new(program:program) do
      close = Button.new('Close')
      form = GameRoomUI::Form.new(surface.fields + [close], program:program, quiet:true)
      form.cancel_button = close
      close.on(:press) { form.resume }
      form.wait
    end
    client.instance_variable_set(:@form,driver.form)
    NativeOptionUI.spoken.clear
    driver.press([0x46,0x53,0x4a,0x4b,0x41], 'f') # dots 13457 on a six-dot table
    assert(NativeOptionUI.spoken == ['Dots: 1, 3, 4, 5, 7.'], "#{mode}: undefined cell did not announce its points: #{NativeOptionUI.spoken.inspect}")
    assert(surface.fields.first.text == 'Dots: 1, 3, 4, 5, 7.', 'Native field contains the technical escape instead of points')
    driver.press([9])
    NativeOptionUI.spoken.clear
    driver.press([16,9])
    assert(NativeOptionUI.spoken.one? && NativeOptionUI.spoken.first.end_with?("\nDots: 1, 3, 4, 5, 7."), 'Focus cannot read the undefined points')
    NativeOptionUI.spoken.clear
    driver.press([8])
    expected_delete = mode == 'words' ? [] : ['Dots: 1, 3, 4, 5, 7.']
    assert(NativeOptionUI.spoken == expected_delete, 'Backspace did not respect the configured echo for the removed points')
    assert(practice.buffer.empty? && surface.fields.first.text.empty?, 'Backspace did not remove the raw undefined cell')
    driver.press([0x46,0x53,0x4a,0x4b,0x41], 'f')
    client.input(' ')
    assert(practice.errors == 1 && practice.engine.correct_words == 0, 'Undefined word was accepted or counted more than once')
    assert(client.instance_variable_get(:@practice).equal?(practice) && !practice.finished?, 'Undefined input cancelled the round')
    assert(practice.display_buffer.empty?, 'Rejected undefined word entered the own-text transcript')
    error = events.reverse.find { |message,_stop| message == 'Incorrect word.' }
    assert(error && error.last == (mode == 'characters'), 'Word rejection interrupted the configured word echo')
    practice.pause; practice.resume
    assert(practice.errors == 1, 'Checkpoint lost the undefined-word error')
    translator.translate('more',table:'polish_integral').each_char { |cell| client.input(cell) }
    client.input(' ')
    assert(practice.engine.correct_words == 1 && practice.errors == 1, 'Typing did not continue normally after the error')
    driver.press([27])
  end
  %w[words memory survival].product(%w[characters words characters_and_words]).each do |variant, mode|
    echo_mode = mode
    practice = GameRoomTyping::Practice.new(options:{'variant'=>variant,'input'=>'braille'},
      word_bank:->(_seed,_index) { 'test' }, seed:1, multiplayer:false, translator:translator,
      table:'polish_integral', recording_seconds:100)
    practice.start; practice.prompt_finished; practice.take_notices
    client = GameRoomTyping::Client.new(program, GameRoomGames::ManiaPisania.new)
    client.instance_variable_set(:@practice,practice)
    client.define_singleton_method(:covered?) { false }
    events = []
    client.define_singleton_method(:announce) { |value, stop:true| events << [value,stop]; true }
    client.input("\u285d")
    assert(events == [['Dots: 1, 3, 4, 5, 7.',true],['Errors: 1 of 5.',false]],
      "#{variant}/#{mode}: points and error were missing, repeated or interrupted: #{events.inspect}")
    assert(practice.errors == 1 && practice.buffer.empty? && !practice.finished?, 'Undefined stream key was accepted or cancelled the round')
    translator.translate('test',table:'polish_integral').each_char { |cell| client.input(cell) }
    client.input(' ') unless variant == 'survival'
    assert(practice.engine.correct_words == 1 && practice.errors == 1, 'Stream did not recover after the undefined cell')
  end
  {'en'=>'Dots: 1, 3, 4, 5, 7.', 'pl'=>'Punkty: 1, 3, 4, 5, 7.', 'cs'=>'Body: 1, 3, 4, 5, 7.',
    'es'=>'Puntos: 1, 3, 4, 5, 7.', 'ru'=>'Точки: 1, 3, 4, 5, 7.'}.each do |language, expected|
    NativeOptionTest.language = language
    practice = GameRoomTyping::Practice.new(options:{'variant'=>'free','input'=>'braille'},
      word_bank:nil, seed:1, multiplayer:false, translator:translator, table:'polish_integral')
    practice.start
    assert(practice.echo_text("\u285d",character:"\u285d") == expected, "Missing localized dot speech for #{language}")
    practice.input("\u285d")
    assert(practice.display_buffer == expected, 'Localized field differs from the point echo')
    practice.input(' ')
    assert(practice.errors == 1 && practice.display_buffer.empty?, 'Localized undefined word entered the transcript')
  end
ensure
  translator&.close
end
puts "PASS native undefined input: physical chord, translated dot echo, focus/deletion, every variant, queued errors, checkpoints and literal escapes; #{NativeOptionTest.checks} checks"
