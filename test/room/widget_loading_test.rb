require_relative "../support/widget"

worker = WidgetManualWorker.new
active, now, loads, foreground_calls = true, 0.0, 0, 0
rows = [WidgetSnapshot.new(table: { "__id" => 91, "owner" => "Bob" })]
error = nil
widget = nil
widget = GameRoomWidget::TableList.new(
  loader: -> { loads += 1; raise error if error; rows }, opener: ->(_) {},
  labeler: ->(row) { row.table["owner"] }, id_for: ->(row) { row.table["__id"] },
  active: -> { active }, clock: -> { now }, worker: worker,
  foreground: ->(&operation) do
    foreground_calls += 1
    read_count = widget.focus_texts.to_a.length
    widget.update # a host task tick cannot initiate a nested timer refresh
    widget.focus # closing a host progress screen may restore field focus
    assert(!worker.busy?, "entry task started a nested background fetch")
    value = operation.call
    assert(widget.focus_texts.to_a.length == read_count, "host read stale data before foreground fetch returned")
    value
  end
)
assert(widget.empty_label == "Loading Power Games tables", "unloaded widget falsely claims there are no tables")
widget.focus
assert(widget.focus_texts == ["Bob"] && foreground_calls == 1, "Tab did not use one foreground task before reading")
assert(widget.sayoption_count.to_i == 0, "duplicate entry speech")
now += 5
widget.update
worker.finish
widget.update
assert(foreground_calls == 1 && widget.sayoption_count.to_i == 0, "timer interrupted the UI")

rows = []
widget.focus
assert(widget.focus_texts.last == "No matching Power Games tables", "fresh empty entry not announced")
$game_room_widget_r = true
widget.update
$game_room_widget_r = false
$spoken_messages.clear
worker.finish
widget.update
assert($spoken_messages == ["No matching Power Games tables"], "R did not announce the empty result")

# Never fall back to a closed cached table on a failed entry. Keep the normal
# error/rate-limit backoff rather than issuing more requests for every Tab.
rows = [WidgetSnapshot.new(table: { "__id" => 92, "owner" => "Carol" })]
widget.focus
error = IOError.new("offline")
widget.focus
assert(widget.options.empty? && widget.focus_texts.last.include?("could not be loaded"), "entry failure read a stale table or claimed no tables")
before = loads
widget.focus
widget.update
assert(loads == before && !worker.busy?, "failed entry bypassed retry backoff")
now += 15
error = nil
rows = nil
widget.update
worker.finish
widget.update
assert(widget.empty_label.include?("could not be loaded"), "nil result left loading stuck or claimed no tables")
now += 15
rows = []
widget.focus
assert(widget.focus_texts.last == "No matching Power Games tables", "recovery did not clear the failure state")
puts "Widget entry task, empty/error results, retry backoff, R and silent timer refresh: OK"
