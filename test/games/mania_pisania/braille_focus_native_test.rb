# encoding: UTF-8
require 'tmpdir'
require_relative '../../support/typing_native_form'
NativeOptionSource.load(File.join(NativeOptionSource::ROOT, 'lib/mania_pisania/client.rb'))

def assert(value, message); NativeOptionTest.assert(value, message); end

Dir.mktmpdir('mania-braille-focus-') do |cache|
  program = NativeOptionTest::Program.new
  program.define_singleton_method(:cache_path) { |path| File.join(cache, path) }
  translator = GameRoomTyping::LibLouis.discover(program: program)
  cases = [['keyboard', 1], ['braille', 1]] + [false, true].map do |braille|
    ['mixed', (1..100).find { |seed| Digest::SHA256.digest("#{seed}:0").getbyte(0).odd? == braille }]
  end
  cases.each do |mode, seed|
    practice = GameRoomTyping::Practice.new(options: {'variant'=>'free', 'input'=>mode},
      word_bank:nil, seed:seed, multiplayer:false, text:'kot dom', translator:translator)
    practice.start
    practice.take_notices
    surface = GameSurfaces::TypingSurface.new(GameSurfaces::TypingSpec.new(round:1, enabled:true, commands:[]))
    client = GameRoomTyping::Client.new(program, GameRoomGames::ManiaPisania.new)
    client.instance_variable_set(:@practice, practice)
    client.instance_variable_set(:@surface, surface)
    client.instance_variable_set(:@settings, Struct.new(:typing_echo).new('characters'))
    client.define_singleton_method(:covered?) { false }
    client.define_singleton_method(:announce) { |text, **_options| NativeOptionUI.speak(text); true }
    surface.on_character = client.method(:input)
    client.send(:present)
    driver = NativeTypingFormDriver.new(program:program) do
      close = Button.new('Close')
      form = GameRoomUI::Form.new(surface.fields + [close], program:program, quiet:true)
      form.cancel_button = close
      close.on(:press) { form.resume }
      form.wait
    end
    client.instance_variable_set(:@form, driver.form)
    field = surface.fields.first
    cells = practice.braille? ? translator.translate('ko', table:'polish_integral') : 'ko'
    cells.each_char { |character| client.input(character) }
    raw_buffer = practice.buffer.dup
    driver.press([9])
    NativeOptionUI.spoken.clear
    driver.press([16,9])
    assert(driver.form.fields[driver.form.index].equal?(field), 'Tab did not return to the typing field')
    assert(NativeOptionUI.spoken == [field.header + "... Text field: \nko"],
      "#{mode}: focus must read the entered prefix exactly once: #{NativeOptionUI.spoken.inspect}")
    assert(practice.buffer == raw_buffer, 'Focus changed the raw input')
    assert(practice.engine.correct_words == 0 && practice.errors == 0, 'Focus submitted or rejected the word')
    NativeOptionUI.spoken.clear
    driver.press([8])
    assert(NativeOptionUI.spoken == ['o'], "#{mode}: deleting must still announce the removed letter")
    assert(field.text == 'k', "#{mode}: deletion did not update the readable prefix")
    driver.press([9])
    NativeOptionUI.spoken.clear
    driver.press([16,9])
    assert(NativeOptionUI.spoken == [field.header + "... Text field: \nk"], 'Returning read stale or expected text')
    last = practice.braille? ? translator.translate('ot', table:'polish_integral') : 'ot'
    last.each_char { |character| client.input(character) }
    client.input(' ')
    assert(practice.engine.correct_words == 1 && practice.errors == 0, 'Readable display corrupted braille word validation')
    driver.press([27])
    assert(!driver.instance_variable_get(:@fiber).alive?, 'Native typing form did not close')
  end
ensure
  translator&.instance_variable_get(:@library)&.close
end
puts "PASS native Tab/Shift+Tab prefix reading, Backspace echo and continued typing in keyboard, braille and mixed modes; #{NativeOptionTest.checks} checks"
