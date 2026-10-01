require "tmpdir"
require_relative "../../lib/game_history_navigation"
require_relative "../../lib/table_history_exporter"

def assert(condition, message)
  raise message unless condition
end

entries = [
  GameRoomHistory::Entry.new(text: "Alice created the table.", category: :room),
  GameRoomHistory::Entry.new(text: "Alice: Cześć", category: :chat),
  GameRoomHistory::Entry.new(text: "Alice rolled 6.\nScore: 6.", category: :game)
]
now = Time.new(2026, 10, 2, 14, 5, 6)

Dir.mktmpdir do |directory|
  exporter = GameRoomTableHistoryExporter.new(clock: -> { now })
  first = exporter.write(directory, entries)
  second = exporter.write(directory, entries)
  expected = "Alice created the table.\r\nAlice: Cześć\r\nAlice rolled 6.\r\nScore: 6.\r\n".encode(Encoding::UTF_8)

  assert(File.basename(first) == "Table_history_2026-10-02_14-05.txt", "unexpected history filename")
  assert(File.basename(second) == "Table_history_2026-10-02_14-05-2.txt", "a repeated export overwrote the first file")
  assert(File.binread(first).force_encoding(Encoding::UTF_8) == expected, "the complete table history was not exported in order")
end

puts "Table history export: room, chat and game entries, UTF-8 text and unique filenames: OK"
