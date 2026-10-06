require_relative "../../lib/table_control"
Record = Struct.new(:sequence, :sender, :packet, keyword_init: true)
def assert(value, message); raise message unless value; end
def control(seq, owner, previous: nil, session_id: 7, controllers: {}, from: seq)
  Record.new(sequence: seq, sender: owner, packet: {"kind" => "table_control", "data" => {
    "owner" => owner, "previous" => previous, "session_id" => session_id, "controllers" => controllers, "from" => from}})
end
a = control(4, "A")
b = control(12, "B", previous: GameRoomTableControl.anchor(a), controllers: {"A" => "bot"})
make = ->(rows, anchor) { GameRoomTableControl.new(founder: "A", records: rows, anchor: anchor) }
ledger = make.call([b, a], GameRoomTableControl.anchor(b))
assert(ledger.complete, "Out-of-order delivery should resolve once all records arrive")
assert(ledger.owner_at(11) == "A" && ledger.owner_at(12) == "B", "Historical authority changed retroactively")
assert(ledger.controllers(7, before: 12).empty? && ledger.controllers(7)["A"] == "bot", "Seat history boundary")
assert(ledger.controllers(8).empty?, "Controller leaked into a rematch")
assert(!make.call([b], GameRoomTableControl.anchor(b)).complete, "Missing chain must fail closed")
forged = control(13, "Mallory", previous: GameRoomTableControl.anchor(b))
assert(make.call([a, b, forged], GameRoomTableControl.anchor(b)).current_owner == "B", "Unanchored claim accepted")
changed = Marshal.load(Marshal.dump(b)); changed.packet["data"]["owner"] = "Mallory"
assert(!make.call([a, changed], GameRoomTableControl.anchor(b)).complete, "Digest mismatch accepted")
checkpoint = control(30, "B", from: 25, session_id: 8)
assert(make.call([checkpoint], GameRoomTableControl.anchor(checkpoint)).owner_at(25) == "B", "New-game checkpoint")
invalid = control(15, "B", previous: GameRoomTableControl.anchor(b), from: 1)
assert(!make.call([a,b,invalid], GameRoomTableControl.anchor(invalid)).complete, "Retroactive authority grant")
assert(make.call([], nil).current_owner == "A", "Original founder lost authority")
puts "Table control ledger: OK"

nine_players = %w[A B C D E F G H I]
nine_controllers = nine_players.to_h { |player| [player, "bot"] }
nine = control(40, "B", previous: GameRoomTableControl.anchor(b), controllers: nine_controllers)
nine.packet["data"]["players"] = nine_players
assert(GameRoomTableControl.valid_players?(nine_players), "Nine unique seats must be valid")
assert(GameRoomTableControl.valid_data?(nine.packet["data"], sequence: 40, sender: "B"), "Nine-seat control record rejected")
nine_ledger = make.call([nine, b, a], GameRoomTableControl.anchor(nine))
assert(nine_ledger.complete && nine_ledger.current_owner == "B", "Nine-seat authenticated chain did not resolve")
assert(nine_ledger.controllers(7, before: 40) == { "A" => "bot" }, "Nine-seat controllers changed the earlier prefix")
assert(nine_ledger.controllers(7) == nine_controllers, "Nine controllers were truncated")
assert(nine_ledger.controllers(8).empty?, "Nine-seat controls escaped their game")

replacement = control(50, "B", previous: GameRoomTableControl.anchor(nine))
replacement.packet["data"]["players"] = nine_players.first(8) + ["J"]
replacement_ledger = make.call([replacement, nine, b, a], GameRoomTableControl.anchor(replacement))
assert(replacement_ledger.players(7, initial: nine_players, before: 50) == nine_players, "Replacement changed the earlier roster")
assert(replacement_ledger.players(7, initial: nine_players, before: 51) == replacement.packet["data"]["players"], "Ninth seat replacement lost")
assert(replacement_ledger.replacements(7, initial: nine_players).map(&:sequence) == [50], "Replacement history changed cardinality or order")
shorter = control(60, "B", previous: GameRoomTableControl.anchor(replacement))
shorter.packet["data"]["players"] = nine_players.first(8)
shorter_ledger = make.call([shorter, replacement, nine, b, a], GameRoomTableControl.anchor(shorter))
assert(shorter_ledger.players(7, initial: nine_players) == replacement.packet["data"]["players"], "Replacement may not shorten a nine-seat game")

invalid_changes = [
  { "players" => nine_players + ["J"] },
  { "players" => nine_players.first(8) + ["a"] },
  { "players" => [] },
  { "players" => nine_players.first(8) + ["x" * 65] },
  { "controllers" => nine_controllers.merge("J" => "bot") },
  { "controllers" => nine_controllers.merge("I" => "admin") },
  { "owner" => "Mallory" },
  { "from" => 41 },
  { "previous" => { "seq" => 40, "digest" => "0" * 64 } }
]
invalid_changes.each do |changes|
  data = nine.packet["data"].merge(changes)
  assert(!GameRoomTableControl.valid_data?(data, sequence: 40, sender: "B"), "Nine-seat validation relaxed an existing boundary: #{changes.keys}")
end
tampered_nine = Marshal.load(Marshal.dump(nine))
tampered_nine.packet["data"]["controllers"]["I"] = "human"
assert(!make.call([a, b, tampered_nine], GameRoomTableControl.anchor(nine)).complete, "Ninth controller changed without an authenticated digest")
assert(!make.call([nine, b], GameRoomTableControl.anchor(nine)).complete, "Nine-seat chain accepted a missing ancestor")
unanchored = control(41, "Mallory", previous: GameRoomTableControl.anchor(nine))
assert(make.call([a, b, nine, unanchored], GameRoomTableControl.anchor(nine)).current_owner == "B", "Unanchored owner claim gained authority over nine seats")
puts "Nine-seat control: count, uniqueness, authentication, anchors, replacement cardinality and historical boundaries OK"
