require_relative "support/settings_widget"

active = true
visits = 0
worker = WidgetManualWorker.new
widget = GameRoomWidget::TableList.new(loader: -> { [] }, opener: ->(_row) {}, labeler: ->(_row) { "table" },
  id_for: ->(_row) { 1 }, active: -> { active }, worker: worker, on_visit: -> { visits += 1 })
widget.focus
assert(visits == 1, "A deliberate Game Room tab entry did not count")
begin
  $game_room_widget_arrow = true
  widget.update
ensure
  $game_room_widget_arrow = false
end
assert(visits == 1, "Arrow navigation counted as another tab entry")
widget.refresh
assert(visits == 1, "Background table refresh counted as a visit")
active = false
widget.focus
assert(visits == 1, "An inactive widget counted a visit")
active = true
widget.focus
assert(visits == 2, "Returning to the tab missed its entry callback")
widget.close
puts "PASS statistics widget visits exclude refresh, arrows and inactive controls"
