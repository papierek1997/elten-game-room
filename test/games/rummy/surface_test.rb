require_relative "../../support/ui"
require_relative "../../../lib/game_surfaces"
require_relative "../../../games/rummy"
def n_(a, b, count); count == 1 ? a : b; end
def assert(value, message); raise message unless value; end

game = GameRoomGames::Rummy.new
state = game.initial_state(%w[Alice Bob], game.default_options)
state.merge!(phase: :playing, round: 1, turn: 1, current_player: "Alice", drawn: true,
  hands: { "Alice" => %w[2S0 3S0 4S0 6H0 7H0 8H0 9C0], "Bob" => %w[KS0] })
replay = GameRoomGames::Replay.new(players: state[:players], current_player: "Alice", state: state, history: [])
surface = GameSurfaces.build(game.surface_spec(replay, "Alice"))
control = surface.fields.first
emitted = []
surface.on_action { |action| emitted << action }
surface.handle_command("meld_new")
["2 of spades", "3 of spades", "4 of spades"].each do |label|
  index = control.options.index(label)
  control.index = index
  control.trigger(:select, [index])
end
assert(emitted.empty?, "draft accidentally emitted a move")
assert(surface.state["meld_selection"] == %w[2S0 3S0 4S0], "ordered selection")
surface.handle_command("sort_cards", { "mode" => "number", "toggle" => true })
assert(surface.state["meld_selection"] == %w[2S0 3S0 4S0], "sorting reordered draft")
surface.handle_command("meld_new")
assert(surface.state["meld_groups"] == [%w[2S0 3S0 4S0]], "N did not keep group")
["6 of hearts", "7 of hearts", "8 of hearts"].each do |label|
  index = control.options.index(label)
  control.index = index
  control.trigger(:select, [index])
end
action = surface.handle_command("meld_submit")
assert(action.is_a?(GameSurfaces::Action) && action.payload["groups"].length == 2, "F not atomic")
assert(surface.state["meld_draft"], "submission cleared before confirmation")
surface.update_spec(game.surface_spec(replay, "Alice"))
assert(surface.state["meld_groups"].length == 1, "refresh destroyed draft")
restored = GameSurfaces.build(game.surface_spec(replay, "Alice"), state: surface.state)
assert(restored.state["meld_selection"] == %w[6H0 7H0 8H0], "form resume lost draft")
state[:turn] = 2
surface.update_spec(game.surface_spec(replay, "Alice"))
assert(!surface.state["meld_draft"], "timeout kept stale draft")

control.index = control.options.index("9 of clubs")
action = surface.handle_command("meld_discard")
assert(action.name == "discard" && action["card"] == "9C0", "Delete did not discard highlighted card")
surface.handle_command("meld_new")
assert(surface.handle_command("meld_discard") == true && emitted.empty?, "Delete played during draft")
surface.cancel_pending_action!
index = control.options.index("9 of clubs")
control.index = index
control.trigger(:select, [index])
assert(control.options == ["Discard", "Cancel"], "Enter should offer discard/cancel")
control.trigger(:select, [1])
assert(emitted.empty? && control.last_focus_header == "", "Cancel emitted action or hand caption")

state[:first_meld]["Alice"] = true
state[:melds] = [GameRoomRummyRules.validate(%w[TS0 JS0 QS0]).merge(id: 1)]
state[:hands]["Alice"] << "KS1"
surface.update_spec(game.surface_spec(replay, "Alice"))
assert(surface.take_cursor_announcement(0) == "king of spades", "last draw cursor")
index = control.options.index("king of spades")
control.index = index
control.trigger(:select, [index])
assert(control.options.length == 2 && control.options.first.start_with?("Lay off"), "Enter auto-played unique target")
control.trigger(:select, [0])
assert(emitted.length == 1, "target select emitted twice")
surface.handle_command("meld_table")
control.trigger(:select, [0])
assert($spoken_messages.last.include?("jack of spades"), "table detail missing")
surface.cancel_pending_action!
assert(control.header == "Your hand", "table Escape failed")
puts "Rummy local meld editor, ordered groups, menus, cursor, sort and refresh: OK"
