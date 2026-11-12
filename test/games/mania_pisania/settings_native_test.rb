# encoding: UTF-8
require 'tmpdir'
require_relative '../../support/typing_native_form'
NativeOptionSource.load(File.join(NativeOptionSource::ROOT, 'lib/mania_pisania/client.rb'))

def assert(value, message); NativeOptionTest.assert(value, message); end

Dir.mktmpdir('mania-settings-') do |cache|
  NativeOptionTest.language = 'pl'
  make = lambda do |initial = {}|
    program = NativeOptionTest::Program.new
    saved = initial.dup
    program.define_singleton_method(:cache_path) { |path| File.join(cache,path) }
    program.define_singleton_method(:read_json) { |path, default:| path == GameRoomTyping::Settings::STORE ? saved : default }
    program.singleton_class.attr_accessor :fail_write
    program.define_singleton_method(:write_json) do |path, values|
      writes << [path, values]
      next false if fail_write
      saved.replace(values)
      true
    end
    client = GameRoomTyping::Client.new(program, GameRoomGames::ManiaPisania.new)
    [program, client, saved]
  end
  [0,1,2,3,4,6].each do |focus|
    program, client, saved = make.call
    driver = NativeTypingFormDriver.new(program:program) { client.show_settings }
    fields = driver.form.fields.dup
    table, speech, sounds, volume, echo = fields
    assert(table.is_a?(ListBox), 'Braille table must be an inline list, not a button')
    assert(fields.none? { |field| field.is_a?(Button) && field.label == table.header }, 'A separate table-picker button remains')
    assert(driver.form.accept_button.equal?(fields[6]), 'Enter is not bound to Save')
    expected = GameRoomTyping::BrailleCatalog.labels.select { |id,_label| GameRoomTyping::BrailleCatalog.visible?(id) }.values
    assert(table.options[0...-1] == expected, 'Inline table list lost its known-language filter')
    computer = table.options.index(GameRoomTyping::BrailleCatalog.labels.fetch('polish_computer'))
    computer.times { driver.press([40]) }
    driver.focus(speech); driver.press([32])
    driver.focus(volume); driver.press([40])
    driver.focus(echo); 2.times { driver.press([40]) }
    assert(program.writes.empty?, 'Navigation saved draft settings')
    driver.focus(fields[focus]); driver.press([13])
    assert(!driver.instance_variable_get(:@fiber).alive?, 'Enter did not save and close settings')
    assert(program.writes.length == 1, 'Enter saved twice or skipped saving')
    assert(saved['braille_table'] == 'polish_computer' && saved['error_speech'] == false && saved['error_sounds'] == true &&
      saved['music_volume'] == 99 && saved['typing_echo'] == 'characters', 'Enter did not save the whole form')
  end
  [false,true].each do |button|
    program, client, saved = make.call
    driver = NativeTypingFormDriver.new(program:program) { client.show_settings }
    driver.press([40])
    if button
      driver.focus(driver.form.cancel_button); driver.press([13])
    else
      driver.press([27])
    end
    assert(!driver.instance_variable_get(:@fiber).alive? && program.writes.empty? && saved.empty?, 'Cancel persisted the table draft')
  end
  program, client, saved = make.call
  program.fail_write = true
  driver = NativeTypingFormDriver.new(program:program) { client.show_settings }
  table = driver.form.fields.first
  driver.press([40])
  NativeOptionUI.spoken.clear
  driver.press([13])
  assert(driver.instance_variable_get(:@fiber).alive? && saved.empty?, 'A failed save closed the settings or changed persistent values')
  assert(driver.form.fields.first.equal?(table) && table.index == 1, 'A failed save discarded the draft or focus')
  assert(NativeOptionUI.spoken.one?, 'A failed save did not announce exactly one error')
  program.fail_write = false
  driver.press([13])
  assert(!driver.instance_variable_get(:@fiber).alive? && saved['braille_table'] == 'polish_g1', 'A failed save could not be retried')

  # The unchanged file browser is tested separately. Exercise its result/cancel
  # boundary here while keeping native navigation, confirmation and validation.
  program, client, saved = make.call
  selected = nil
  calls = 0
  client.define_singleton_method(:choose_local_braille_table) { calls += 1; selected }
  driver = NativeTypingFormDriver.new(program:program) { client.show_settings }
  driver.press([35]) # Local Liblouis table, last list entry.
  driver.press([13])
  assert(calls == 1 && driver.instance_variable_get(:@fiber).alive? && program.writes.empty?, 'Cancelling the file browser saved settings')
  assert(driver.form.index == 0, 'Cancelling the file browser did not return to the table list')
  translator = GameRoomTyping::LibLouis.discover(program:program)
  selected = translator.table_path('polish_computer')
  driver.press([13])
  assert(saved['braille_table'] == selected && calls == 2, 'Selected local table was not saved')
  driver = NativeTypingFormDriver.new(program:program) { client.show_settings }
  assert(driver.form.fields.first.options[driver.form.fields.first.index].include?(File.basename(selected)), 'Current custom table is not selected and identified')
  driver.press([13])
  assert(calls == 2, 'Saving an unchanged custom table reopened the file browser')
ensure
  translator&.close
end
puts "PASS native inline braille settings, Enter from lists/checkboxes/Save, Escape/Cancel, failed save retry and local-table preservation; #{NativeOptionTest.checks} checks"
