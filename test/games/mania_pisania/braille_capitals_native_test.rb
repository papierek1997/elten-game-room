# encoding: UTF-8
require 'tmpdir'
require_relative '../../support/typing_native_form'
NativeOptionSource.load(File.join(NativeOptionSource::ROOT, 'lib/mania_pisania/client.rb'))

def assert(value, message); NativeOptionTest.assert(value, message); end

Dir.mktmpdir('mania-capitals-') do |cache|
  program = NativeOptionTest::Program.new
  program.define_singleton_method(:cache_path) { |path| File.join(cache, path) }
  program.define_singleton_method(:write_json) { |path, values| writes << [path, values]; true }
  program.define_singleton_method(:play_sound_from_asset) { |*_arguments, **_options| true }
  translator = GameRoomTyping::LibLouis.discover(program:program)
  examples = {'polish_integral'=>'Natalia', 'polish_g1'=>'Żółć', 'polish_computer'=>'Natalia',
    'english_g1'=>'Hello', 'czech_g1'=>'Příliš', 'spanish_g1'=>'Niño', 'russian_detailed'=>'Привет'}
  examples.each do |table, word|
    %w[free words memory survival].each do |variant|
      [word, word.downcase, word.upcase].uniq.each do |typed|
        practice = GameRoomTyping::Practice.new(options:{'variant'=>variant, 'input'=>'braille'},
          word_bank:->(_seed,_index) { word }, seed:1, multiplayer:false, text:word,
          translator:translator, table:table, recording_seconds:100)
        practice.start
        practice.prompt_finished
        cells = translator.translate(typed, table:table)
        # A capital indicator is a valid saved prefix too.
        practice.input(cells[0])
        checkpoint = practice.snapshot
        practice.pause
        practice.restore(checkpoint)
        practice.resume
        practice.prompt_finished
        cells[1..].each_char { |cell| practice.input(cell) }
        practice.input(' ') unless variant == 'survival'
        assert(practice.engine.correct_words == 1 && practice.errors == 0,
          "Rejected capitals for #{table}/#{variant}/#{typed}")
      end
    end
  end
  GameRoomTyping::BrailleCatalog::FILES.each_key do |table|
    word = table.start_with?('russian') ? 'привет' : 'test'
    practice = GameRoomTyping::Practice.new(options:{'variant'=>'free', 'input'=>'braille'},
      word_bank:nil, seed:1, multiplayer:false, text:word, translator:translator, table:table)
    practice.start
    translator.translate(word, table:table).each_char { |cell| practice.input(cell) }
    practice.input(' ')
    assert(practice.engine.correct_words == 1 && practice.errors == 0, "Lowercase broke for #{table}")
  end
  practice = GameRoomTyping::Practice.new(options:{'variant'=>'free','input'=>'braille'},
    word_bank:nil, seed:1, multiplayer:false, text:'Natalia', translator:translator)
  practice.start
  translator.translate('Natalia', table:'polish_integral')[0,3].each_char { |cell| practice.input(cell) }
  assert(practice.remaining_word == 'talia', 'Capital marker advances remaining-word help by an extra letter')
  practice.select_braille_table('polish_computer')
  assert(practice.snapshot['table'] == 'polish_integral', 'Changing table reinterpreted unfinished cells')
  practice.buffer.length.times { practice.input("\b") }
  assert(practice.snapshot['table'] == 'polish_computer', 'Clearing the word did not apply the selected table')
  practice = GameRoomTyping::Practice.new(options:{'variant'=>'words','input'=>'braille'},
    word_bank:->(_seed,_index) { 'Natalia' }, seed:1, multiplayer:false, translator:translator)
  practice.start
  practice.prompt_finished
  practice.engine.current_expected # Prime the old-table cache before changing it.
  practice.select_braille_table('polish_computer')
  translator.translate('Natalia', table:'polish_computer').each_char { |cell| practice.input(cell) }
  practice.input(' ')
  assert(practice.engine.correct_words == 1 && practice.errors == 0, 'Table change retained cached literary targets')

  %w[free words memory survival].each do |variant|
    practice = GameRoomTyping::Practice.new(options:{'variant'=>variant,'input'=>'braille'},
      word_bank:->(_seed,_index) { 'Natalia' }, seed:1, multiplayer:false, text:'Natalia Natalia',
      translator:translator, recording_seconds:100)
    practice.start
    practice.prompt_finished
    cells = translator.translate('Natalia', table:'polish_integral')
    practice.input(cells[0])
    practice.select_braille_table('polish_computer')
    cells[1..].each_char { |cell| practice.input(cell) }
    practice.input(' ') unless variant == 'survival'
    assert(practice.snapshot['table'] == 'polish_computer', "#{variant}: table change was not applied at the word boundary")
    practice.prompt_finished
    translator.translate('Natalia', table:'polish_computer').each_char { |cell| practice.input(cell) }
    practice.input(' ') unless variant == 'survival'
    assert(practice.engine.correct_words == 2 && practice.errors == 0, "#{variant}: table change corrupted the next word")
  end
  %w[words memory survival].each do |variant|
    practice = GameRoomTyping::Practice.new(options:{'variant'=>variant,'input'=>'braille'},
      word_bank:->(_seed,_index) { 'Natalia' }, seed:1, multiplayer:false,
      translator:translator, recording_seconds:100)
    practice.start
    practice.prompt_finished
    practice.input("\u28ff")
    assert(practice.errors == 1 && practice.buffer.empty?, "#{variant}: optional capitals accepted an unrelated cell")
    translator.translate('Natalia', table:'polish_integral').each_char { |cell| practice.input(cell) }
    practice.input(' ') unless variant == 'survival'
    assert(practice.engine.correct_words == 1 && practice.errors == 1, "#{variant}: typing did not recover after a wrong cell")
  end

  NativeOptionTest.language = 'pl'
  practice = GameRoomTyping::Practice.new(options:{'variant'=>'free','input'=>'braille'},
    word_bank:nil, seed:1, multiplayer:false, text:'kot Natalia', translator:translator)
  practice.start
  practice.take_notices
  client = GameRoomTyping::Client.new(program, GameRoomGames::ManiaPisania.new)
  client.instance_variable_set(:@practice, practice)
  client.define_singleton_method(:covered?) { false }
  client.define_singleton_method(:announce) { |text, **_options| NativeOptionUI.speak(text); true }
  client.instance_variable_get(:@settings).save('typing_echo'=>'characters')
  translator.translate('k', table:'polish_integral').each_char { |cell| client.input(cell) }
  driver = NativeTypingFormDriver.new(program:program) { client.show_settings }
  list = driver.form.fields.first
  computer = list.options.index(GameRoomTyping::BrailleCatalog.labels.fetch('polish_computer'))
  assert(computer, 'Computer table is missing from the native picker')
  computer.times { driver.press([40]) }
  driver.press([13])
  assert(!driver.instance_variable_get(:@fiber).alive?, 'Enter did not save and close the native settings')
  assert(client.instance_variable_get(:@settings)['braille_table'] == 'polish_computer', 'Picker did not save computer braille')
  assert(practice.snapshot['table'] == 'polish_integral', 'Picker changed the table halfway through a word')
  translator.translate('ot', table:'polish_integral').each_char { |cell| client.input(cell) }
  client.input(' ')
  assert(practice.snapshot['table'] == 'polish_computer', 'The next word still uses the old table')
  practice.take_notices
  surface = GameSurfaces::TypingSurface.new(GameSurfaces::TypingSpec.new(round:1, enabled:true, commands:[]))
  surface.on_character = client.method(:input)
  client.instance_variable_set(:@surface, surface)
  client.send(:present)
  driver = NativeTypingFormDriver.new(program:program) do
    close = Button.new('Close')
    form = GameRoomUI::Form.new(surface.fields + [close], program:program, quiet:true)
    form.cancel_button = close
    close.on(:press) { form.resume }
    form.wait
  end
  client.instance_variable_set(:@form, driver.form)
  NativeOptionUI.spoken.clear
  # N = dots 13457: F S J K A, through real keyboard frames and chord handling.
  driver.press([0x46,0x53,0x4a,0x4b,0x41], 'f')
  assert(practice.buffer == "\u285d" && surface.fields.first.text == 'N', 'Physical capital N was not decoded with the selected table')
  assert(NativeOptionUI.spoken == ['N'], "Computer N was not echoed as N: #{NativeOptionUI.spoken.inspect}")
  driver.press([9])
  NativeOptionUI.spoken.clear
  driver.press([16,9])
  assert(NativeOptionUI.spoken.one? && NativeOptionUI.spoken.first.end_with?("\nN"), 'Focus did not read computer N')
  translator.translate('atalia', table:'polish_computer').each_char { |cell| client.input(cell) }
  client.input(' ')
  assert(practice.engine.correct_words == 2 && practice.errors == 0, 'A correctly capitalized computer word was rejected')
  driver.press([27])
ensure
  translator&.instance_variable_get(:@library)&.close
end
puts "PASS native literary/computer capitals, optional indicators, saved prefixes, help, table selection and physical 13457 chord; #{NativeOptionTest.checks} checks"
