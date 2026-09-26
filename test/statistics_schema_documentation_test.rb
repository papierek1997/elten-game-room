require "json"
require_relative "../lib/game_statistics_store"
require_relative "../lib/game_room_presence_store"

path = File.expand_path("../docs/STATISTICS_TABLES.json", __dir__)
raise "The deployable statistics schema fragment is missing" unless File.file?(path)
expected = GameRoomStatistics::Schema::TABLES.merge(GameRoomPresence::Schema::TABLES)
actual = JSON.parse(File.read(path, encoding: "UTF-8"))
raise "The documented statistics tables differ from the runtime declarations" unless actual == expected
raise "The schema fragment must not contain unrelated tables" unless actual.keys.sort == %w[room_presence statistics_accounts statistics_events]
puts "PASS documented statistics schema matches all three runtime tables"
