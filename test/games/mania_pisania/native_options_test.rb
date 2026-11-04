# encoding: UTF-8
require_relative '../../support/game_option_editor_native'

%w[en pl].each do |language|
  NativeOptionTest.language = language
  game = GameRoomGames::ManiaPisania.new
  options = game.default_options.merge('variant' => 'free', 'text' => 'pasted')
  driver = NativeOptionTest::Driver.new(game, initial_options: options)
  driver.program.define_singleton_method(:write_json) do |path, value|
    writes << [path, value]
    true
  end
  extension = driver.form.fields.select { |field| field.instance_of?(EditBox) }
  title, input = extension.last(2)
  NativeOptionTest.assert(extension.length == 2, 'Pasted text has a redundant information field')
  NativeOptionTest.assert(driver.visible?(title) && driver.visible?(input), 'Pasted text fields are hidden')
  title.set_text('Retry title')
  oversized = 'a' * (GameRoomTyping::TextLibrary::MAX_BYTES + 1)
  input.set_text(oversized)
  driver.focus(driver.form.accept_button)
  driver.press([13])
  alerts = driver.program.alerts
  NativeOptionTest.assert(alerts.one? && alerts.first.include?('1000000') && alerts.first.include?('1000 kB'), 'Native import failure omits the limit')
  NativeOptionTest.assert(alerts.first.include?('Maksymaln'), 'Polish failure is not translated') if language == 'pl'
  NativeOptionTest.assert(input.text == oversized && title.text == 'Retry title', 'Native validation discarded the draft')
  driver.pristine
  input.set_text('Corrected text.')
  driver.press([13])
  result = driver.finished
  NativeOptionTest.assert(result['text_title'] == 'Retry title' && result['text_characters'] == 15, 'Native retry lost the text descriptor')
  NativeOptionTest.assert(!driver.program.writes.empty?, 'Native retry did not save the corrected text')
end
puts "PASS Typing Mania native options: #{NativeOptionTest.checks} checks; English and Polish import failure, retained draft and successful retry."
