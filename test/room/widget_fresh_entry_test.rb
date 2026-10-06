require_relative "../support/widget"

worker = WidgetManualWorker.new
active, now, loads = true, 0.0, 0
opened = []
row = ->(id, owner) { WidgetSnapshot.new(table: { "__id" => id, "owner" => owner }) }
rows = [row.call(1, "Alice"), row.call(2, "Bob")]
widget = GameRoomWidget::TableList.new(
  loader: -> { loads += 1; rows }, opener: ->(snapshot) { opened << snapshot.table["__id"] },
  labeler: ->(snapshot) { snapshot.table["owner"] }, id_for: ->(snapshot) { snapshot.table["__id"] },
  active: -> { active }, clock: -> { now }, worker: worker
)
widget.focus
assert(widget.focus_texts == ["Alice"] && loads == 1, "first Tab read happened before loading fresh data")
widget.index = 1
active = false
widget.update
rows = [row.call(3, "Carol")]
active = true
widget.focus
assert(widget.focus_texts == ["Alice", "Carol"], "Tab read Bob's closed table before fetching the current list")
assert(widget.sayoption_count.to_i == 0, "entry was announced twice")
widget.trigger(:select)
assert(opened == [3], "Enter opened a stale cached table")
worker.finish
widget.update

# A timer response finished during absence is not evidence that the room is
# still present on the next entry. Fetch anew before native focus speaks.
now += 5
widget.update
worker.finish
active = false
rows = []
widget.update
active = true
widget.focus
assert(widget.focus_texts.last == "No matching Power Games tables" && widget.options.empty?, "a completed old response was read on reentry")
widget.trigger(:select)
assert(opened == [3], "Enter opened an old row after the fresh empty response")

# The earlier background fetch must never overwrite the fresh entry, even if
# it finishes later. The production loader serializes the actual requests.
now += 5
widget.update
active = false
rows = [row.call(4, "Dave")]
active = true
widget.focus
rows = [row.call(99, "Obsolete timer response")]
worker.finish
widget.update
assert(widget.options == ["Dave"] && widget.focus_texts.last == "Dave", "old in-flight response replaced the entry result")

# Periodic refresh stays silent and preserves the cursor as it is at delivery,
# not the cursor when the request began.
rows = [row.call(4, "Dave"), row.call(5, "Eve")]
widget.refresh
worker.finish
widget.update
now += 4.9
widget.update
assert(!worker.busy?, "timer polled before five seconds")
now += 0.1
widget.update
assert(worker.busy?, "focused five-second refresh did not start")
widget.index = 1
rows = rows.reverse
worker.finish
widget.update
assert(widget.index == 0 && widget.options[0] == "Eve", "periodic refresh restored an old cursor")
assert(widget.sayoption_count.to_i == 0, "periodic refresh interrupted speech")
before = loads
$game_room_widget_arrow = true
100.times { widget.update }
$game_room_widget_arrow = false
assert(loads == before && !worker.busy?, "arrow navigation triggered a refresh")

# R pressed while a pre-entry worker finishes must still cause a fresh manual
# refresh, not silently disappear along with the obsolete response.
now += 5
widget.update
widget.focus
$game_room_widget_r = true
widget.update
$game_room_widget_r = false
worker.finish
widget.update
assert(worker.busy?, "R was lost when the obsolete response was discarded")
worker.finish
widget.update
assert(widget.sayoption_count == 1, "manual R refresh was not announced once")
before = loads
active = false
now += 100
widget.update
assert(loads == before && !worker.busy?, "inactive widget polled")
puts "Widget reads fresh rows on Tab, ignores stale ready/in-flight results and preserves arrow/timer behavior."
