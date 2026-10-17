require_relative "../../support/bridge"
require_relative "../../support/localization"
include GameRoomTest::Assertions

game = GameRoomGames::CATALOG.build("bridge")
label = ->(call) { GameRoomContent.utf8(game.send(:call_label, call)) }

GameRoomTestLocalization.use_language("pl")
assert_equal(%w[trefl trefle trefli], %w[1C 2C 5C].map { |call| label.(call).split(" ", 2).last }, "wrong Polish club forms")
assert_equal(["1 kier", "4 kiery", "6 kierów", "2 kara", "3 bez atu", "kontra"], %w[1H 4H 6H 2D 3N X].map(&label), "wrong Polish calls")
table = GameRoomTest::BridgeTable.new
text = GameRoomContent.utf8(game.game_shortcuts(table.replay, table.state[:current_player]).find { |item| item.key == "h" }.message)
assert(text.include?("punkty honorowe") || text.include?("Punkty honorowe"), "H is not translated: #{text}")
assert(text.encoding == Encoding::UTF_8 && text.valid_encoding?, "wrong encoding")
assert_equal("Brydż", GameRoomContent.utf8(game.name), "the Polish name is missing")

GameRoomTestLocalization.use_language("ru")
assert_equal(["1 пика", "2 пики", "5 пик"], %w[1S 2S 5S].map(&label), "wrong Russian spade forms")

GameRoomTestLocalization.use_language("en")
assert_equal(["1 club", "2 clubs", "7 no trump", "redouble"], %w[1C 2C 7N XX].map(&label), "wrong English calls")

puts "PASS bridge localization: Polish and Russian call plurals, translated hand readout and UTF-8 text"
