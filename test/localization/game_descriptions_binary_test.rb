require_relative '../support/binary_rules_load'
require_relative '../support/assertions'
include GameRoomTest::Assertions

expected = JSON.parse(File.read(File.join(BinaryRulesLoad::ROOT, 'test/fixtures/game_descriptions_pl.json'), encoding: 'UTF-8'))
registry = EltenGameRoom::GAME_REGISTRY
app = EltenGameRoom.allocate
%w[pl en cs es ru].each do |language|
  GameRoomTestLocalization.use_language(language)
  registry.ids.each do |id|
    game = registry.build(id)
    label = app.send(:game_lobby_label, id)
    assert(label.encoding == Encoding::UTF_8 && label.valid_encoding?, "#{language}/#{id}: binary label encoding")
    assert(label == "#{game.name}. #{game.short_description}", "#{language}/#{id}: binary label differs from description")
    assert(game.short_description == expected.fetch(id), "#{id}: binary load changed approved Polish text") if language == 'pl'
  end
end
puts 'PASS binary-source descriptions: all 33 games in PL/EN/CS/ES/RU'
