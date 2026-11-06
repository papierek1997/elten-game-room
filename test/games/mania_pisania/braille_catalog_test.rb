# encoding: UTF-8
require 'tmpdir'
require_relative '../../support/game_option_form'
require_relative '../../../lib/mania_pisania/braille'
require_relative '../../../lib/mania_pisania/settings'

Dir.mktmpdir('mania-catalog-') do |cache|
  program = EltenGameRoom.allocate
  program.define_singleton_method(:cache_path) { |path| File.join(cache,path) }
  program.define_singleton_method(:read_json) { |_path, default:| default }
  louis = GameRoomTyping::LibLouis.discover(program:program)
  expected = GameRoomTyping::BrailleCatalog::FILES.keys
  assert(expected.length == 32 && louis.tables.map(&:first) == expected, 'Incomplete table list')
  louis.tables.each do |id, label, path|
    assert(!label.empty? && File.file?(path), "Missing table #{id}")
    sample = id.start_with?('russian') ? 'привет' : id.start_with?('czech') ? 'příliš' : id.start_with?('spanish') ? 'niño' : 'test'
    cells = louis.translate(sample, table:id)
    assert(!cells.empty? && cells.each_char.all? { |cell| cell.ord.between?(0x2800,0x28ff) }, "Cannot use #{id}")
    assert(GameRoomTyping::Checkpoint::TABLES.include?(id), "Checkpoint discards #{id}")
  end
  %w[en pl cs es ru].each do |language|
    GameRoomLocalization.boot(host_language:language)
    assert(GameRoomTyping::Settings.new(program)['braille_table'] == GameRoomTyping::BrailleCatalog::DEFAULTS.fetch(language), 'Wrong literary default')
    GameRoomLocalization.boot(host_language:language, known_languages:%w[en pl cs es ru])
    program.define_singleton_method(:read_json) { |_path, default:| {'braille_table'=>'english_g3'} }
    assert(GameRoomTyping::Settings.new(program)['braille_table'] == 'english_g3', 'Explicit preference was overwritten')
    program.define_singleton_method(:read_json) { |_path, default:| default }
  end
ensure
  louis&.instance_variable_get(:@library)&.close
end
puts 'PASS every bundled braille variant translates with native Liblouis; language defaults and saved choices remain valid.'
