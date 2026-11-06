require_relative '../../support/game_option_editor_native'

%w[en pl cs es ru].each_with_index do |language, index|
  NativeOptionTest.language = language
  GameRoomLocalization.boot(host_language:language,known_languages:[language])
  game = GameRoomGames::ManiaPisania.new
  foreign = %w[en pl cs es ru][(index + 1) % 5]
  story = GameRoomTyping::TextLibrary::BUILTIN.keys.find { |id| GameRoomTyping::Languages.text_language(id) == foreign }
  [
    {'variant'=>'words','word_language'=>foreign},
    {'variant'=>'free','word_language'=>foreign,'text'=>story}
  ].each do |values|
    initial = game.normalize_options(values)
    driver = NativeOptionTest::Driver.new(game,initial_options:initial)
    if values['variant'] == 'words'
      NativeOptionTest.assert(driver.visible?('word_language'), 'Recorded foreign dictionary is hidden')
      choices = game.option_editor_definitions(initial).find { |item| item.key == 'word_language' }.choices.map(&:value)
      NativeOptionTest.assert(choices.sort == [language,foreign].sort, 'Existing dictionary was filtered out or unrelated languages added')
    end
    driver.focus(driver.form.accept_button)
    driver.press([13])
    NativeOptionTest.assert(driver.finished == initial, 'Saving unchanged settings changed the dictionary or story')

    driver = NativeOptionTest::Driver.new(game,initial_options:initial)
    key = values['variant'] == 'words' ? 'rounds' : 'minutes'
    control = driver.control(key)
    control.index = 1
    control.trigger(:move)
    driver.focus(driver.form.accept_button)
    driver.press([13])
    changed = driver.finished
    NativeOptionTest.assert(changed['word_language'] == foreign && changed['text'] == initial['text'],
      'Editing an unrelated setting changed the recorded language or text')
    NativeOptionTest.assert(changed[key] != initial[key], 'The unrelated setting was not changed')
  end
  fresh = game.table_creation_options('variant'=>'words')
  NativeOptionTest.assert(fresh['word_language'] == language, 'Preserving an existing choice changed new-table language defaults')
end
puts 'PASS existing typing selections: unchanged saves and unrelated edits retain dictionaries/stories in five interface languages; new-table defaults remain local'
