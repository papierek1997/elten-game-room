require_relative "../support/table_notice_presentation"
now = 2_000_000_000
uuid = EltenGameRoom.server_app_uuid
receiver = GameRoomTableWatch::Receiver.new(user: "Alice", games: ["uno"], uuid: uuid, clock: -> { now })
receiver.games = ["uno"]
EltenGameRoom.instance_variable_set(:@table_watch_receiver, receiver)
wire_notice = Notice2.new(id: 600, app_uuid: uuid, type: GameRoomTableWatch::TYPE, sender: "Bob",
  metadata: { "format" => 1, "game" => "uno", "table_id" => 12,
    "live_session_id" => "uEoTspHz_s-PSO-UVrMr8CaRSyVLTraP", "created_at" => now, "expires_at" => now + 300 })
notice = EltenGameRoom.map_notification(wire_notice)
options = notice.instance_variable_get(:@options)
assert(options[:title] == "Bob, UNO" && options[:body] == "New table" && options[:action] == :open_new_table, "wire notification lost owner/game/type order or routing")
assert(!notice.default_suppressed && notice.sound.nil? &&
  EltenGameRoom.instance_variable_get(:@table_notice_test_sounds) == [["table_notice", {volume:1.0}]],
  "first wire notification lost announcement or its managed table sound")
EltenGameRoom.notification_received(wire_notice, notice)
assert(!notice.default_suppressed, "first receipt suppressed valid notification")
again = EltenGameRoom.map_notification(wire_notice)
EltenGameRoom.notification_received(wire_notice, again)
assert(again.sound.nil? && again.default_suppressed, "duplicate receipt repeated sound/announcement")
assert(!again.instance_variable_get(:@options)[:body].empty?, "duplicate receipt blanked the visible row")
now += 300
expired = EltenGameRoom.map_notification(wire_notice)
assert(expired.default_suppressed && expired.sound.nil?, "expired notification announced itself")
assert(expired.instance_variable_get(:@options)[:body] == "This table announcement has expired or is no longer available.", "suppression left an empty host notification row")
assert(expired.instance_variable_get(:@options)[:action].nil?, "unavailable notice retained a join action")
puts "Table notice mapping, separate table sound, receipt hook and nonempty unavailable fallback: OK"
