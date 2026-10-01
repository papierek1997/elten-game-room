require_relative "../support/ui"

# ELTEN defines this alongside Form. The lightweight UI fixture does not run
# timers here, but the form's timer classification still needs the host type.
class FormTimer; end unless defined?(FormTimer)

require_relative "../../lib/game_surfaces"
require_relative "../../lib/game_layout"
require_relative "../../lib/game_chat_commands"

def assert(condition, message)
  raise message if !condition
end

layout_spec = GameRoomLayout::ViewSpec.new(
  surface: GameSurfaces::GridSpec.new(
    width: 1,
    height: 1,
    header: "Board",
    cells: [["empty"]],
    row_origin: :bottom
  )
)
layout = GameRoomLayout::Screen.new(
  view_spec: layout_spec,
  surface_state: {},
  history_items: ["Game started", "Alice moved"],
  user_items: ["Alice", "Bob"],
  history_index: 99,
  users_index: 99,
  users_header: "Users at the table (2)"
)
assert(layout_spec.sections == [:status, :game, :chat, :history, :users], "the shared game layout has the wrong section order")
assert(layout.shortcut_fields.length == 3, "the shared game layout did not expose all non-chat content fields")
assert(layout.form.controls[0] == layout.surface.fields[0], "the game field is not first in the shared layout")
assert(layout.form.controls[1] == layout.chat, "chat is not directly after the game")
assert(layout.form.controls[2] == layout.history, "history is not directly after chat")
assert(layout.form.controls[3] == layout.users, "users are not last")
assert(layout.form.hidden_controls == [layout.back_button], "the back action became a visible tab stop")
assert(layout.form.controls.none? { |control| control.is_a?(Button) && control.label == "Game rules" }, "rules remained a visible tab stop")
layout.form.instance_variable_set(:@updated, true)
layout.wait_without_announcement
assert(
  layout.form.wait_announced == false,
  "a maintenance refresh re-entered the form with its announcement enabled"
)
assert(
  layout.form.instance_variable_get(:@quiet) == true,
  "a maintenance refresh permanently changed the form's normal quiet mode"
)
layout.form.index = 0
layout.suppress_focus!
layout.wait_without_announcement
layout.surface.fields.first.focus(nil, nil, true, include_header: false)
assert(
  layout.surface.fields.first.last_focus_spoken == true,
  "a silent form re-entry swallowed the first manual board movement"
)
layout.form.index = layout.form.fields.index(layout.chat)
layout.form.game_shortcut_signatures = [["t", []], ["t", [:control]]]
layout.form.held_modifiers = []
assert(layout.form.key_processed(:t) == true, "an ordinary game shortcut captured a letter typed in an edit field")
layout.form.held_modifiers = [:main_modifier]
assert(layout.form.key_processed(:t) == false, "Ctrl+T was captured by the active edit field")
layout.form.held_modifiers = [:shift]
assert(layout.form.key_processed(:t) == true, "Shift+T was captured instead of being typed in an edit field")
layout.form.history_navigation_signatures = [
  ["left", [:shift]],
  ["right", [:control]],
  ["left", [:control, :shift]]
]
layout.form.held_modifiers = [:shift]
assert(layout.form.key_processed(:left) == true, "Shift+Left was stolen from the active edit field")
layout.form.held_modifiers = [:main_modifier]
assert(layout.form.key_processed(:right) == true, "Ctrl+Right was stolen from the active edit field")
layout.form.index = 0
assert(layout.form.key_processed(:right) == false, "Ctrl+Right did not activate history navigation outside an edit field")
layout.form.held_modifiers = [:shift, :main_modifier]
assert(layout.form.key_processed(:left) == false, "Ctrl+Shift+Left did not activate history navigation outside an edit field")
layout.form.index = 0
layout.form.held_modifiers = []
layout.form.game_shortcut_keys = ["s", "space"]
assert(layout.form.key_processed(:s) == false, "an active list can block a shared letter shortcut")
assert(layout.form.key_processed(:space) == false, "the active control can block a shared Space shortcut")

yahtzee_spec = GameSurfaces::RollAndScoreSpec.new(
  id: "yahtzee",
  header: "Yahtzee",
  dice: [1, 1, 3, 4, 5].each_with_index.map do |value, index|
    GameSurfaces::Die.new(id: "d#{index}", value: value, sides: 6, held: true, enabled: true)
  end,
  categories: [GameSurfaces::ScoreChoice.new(id: "chance", label: "Chance: 15", value: "chance")],
  can_roll: true,
  force_categories: false,
  empty_label: "No categories",
  roll_number: 1
)
yahtzee_surface = GameSurfaces::RollAndScoreSurface.new(yahtzee_spec)
assert(yahtzee_surface.fields.first.options == ["Roll the dice"],
  "the Yahtzee surface still exposes dice as separate interface items")
assert(yahtzee_surface.handle_command("select_die", "value" => 1),
  "the Yahtzee surface did not select a die by value")
assert(yahtzee_surface.state["selected_ids"] == ["d0"],
  "the wrong first matching Yahtzee die was selected")
assert($spoken_messages.last == "You keep 1 3 4 5 and reroll 1.", "the Yahtzee selection summary is incorrect")
assert(yahtzee_surface.handle_command("select_die", "value" => 1),
  "the Yahtzee surface did not select the next matching die")
assert(yahtzee_surface.state["selected_ids"] == ["d0", "d1"],
  "repeated value selection did not advance to the next matching die")
assert(yahtzee_surface.handle_command("unselect_die", "value" => 1),
  "the Yahtzee surface did not keep one selected matching die")
assert(yahtzee_surface.state["selected_ids"] == ["d0"],
  "keeping by value did not remove exactly one selected die")
assert($spoken_messages.last == "You keep 1 3 4 5 and reroll 1.", "the Yahtzee keep summary is incorrect")
$spoken_messages.clear
assert(yahtzee_surface.handle_command("announce_dice"), "the Yahtzee dice status shortcut was rejected")
assert($spoken_messages.last == "You keep 1 3 4 5 and reroll 1.",
  "the Yahtzee dice status did not include the selection state")
yahtzee_action = nil
yahtzee_surface.on_action { |action| yahtzee_action = action }
yahtzee_surface.fields.first.trigger(:select)
assert(yahtzee_action&.name == "roll" && yahtzee_action.payload["die_ids"] == "d0",
  "Enter did not reroll only the selected Yahtzee die")

next_roll_spec = yahtzee_spec.dup
next_roll_spec.roll_number = 2
next_roll_surface = GameSurfaces::RollAndScoreSurface.new(next_roll_spec, state: yahtzee_surface.state)
assert(next_roll_surface.state["selected_ids"].empty?,
  "Yahtzee preserved selected dice after a completed roll")
next_roll_surface.fields.first.trigger(:select)
assert(next_roll_surface.fields.first.options == ["Chance: 15"],
  "Enter did not open Yahtzee scoring categories when no die was selected")
layout.users.game_shortcut_keys = ["s", "space"]
layout.users.next_character = "s"
assert(layout.users.send(:getkeychar) == "", "a shared shortcut leaked into list quick search")
layout.users.next_character = "a"
assert(layout.users.send(:getkeychar) == "a", "a normal list quick-search character was suppressed")
layout.users.game_shortcut_signatures = [["1", []], ["1", [:shift]]]
layout.users.next_character = "!"
assert(layout.users.send(:getkeychar) == "", "a shifted digit shortcut leaked into list quick search")

sortable_cards = [
  GameSurfaces::Card.new(id: "b2", label: "blue 2", value: "b2", sort_keys: {
    "colour" => [1, 1], "number" => [1, 1], "none" => [0]
  }),
  GameSurfaces::Card.new(id: "r1", label: "red 1", value: "r1", sort_keys: {
    "colour" => [0, 0], "number" => [0, 0], "none" => [1]
  }),
  GameSurfaces::Card.new(id: "b1", label: "blue 1", value: "b1", sort_keys: {
    "colour" => [1, 0], "number" => [0, 1], "none" => [2]
  })
]
sortable_spec = GameSurfaces::CardTableSpec.new(zones: [
  GameSurfaces::CardZoneSpec.new(id: "hand", header: "Hand", cards: sortable_cards, empty_label: "Empty")
])
sortable_surface = GameSurfaces::CardTable.new(sortable_spec)
assert(sortable_surface.handle_command("sort_cards", "mode" => "number", "message" => "Sorted by value."),
  "the shared card surface rejected a local sort command")
assert(sortable_surface.fields.first.options == ["red 1", "blue 1", "blue 2"],
  "the shared card surface did not sort cards by the requested key")
assert(sortable_surface.state["card_sort_mode"] == "number", "the selected card sort mode was not preserved")
restored_sortable_surface = GameSurfaces::CardTable.new(sortable_spec, state: sortable_surface.state)
assert(restored_sortable_surface.fields.first.options == ["red 1", "blue 1", "blue 2"],
  "the selected card sort mode was lost during a refresh")
answer_field = GameSurfaces::RefreshAwareEditBox.new("Country", text: "")
answer_field.game_shortcut_signatures = [["t", [:control]]]
context_menu = FakeMenu.new
answer_field.context(context_menu, false)
assert(
  context_menu.options.map { |option| option[2] } == ["", "T"],
  "the answer field left the conflicting Ctrl+T translator shortcut active"
)
layout.form.index = layout.form.fields.index(layout.chat)
layout_snapshot = layout.snapshot
assert(layout_snapshot.history_index == 1, "the shared layout did not bound the history position")
assert(layout_snapshot.users_index == 1, "the shared layout did not bound the user position")
assert(layout_snapshot.form_index == 1, "the shared layout did not bound the active section")
assert(layout_snapshot.focus_location == [:chat, 0], "the shared layout did not remember the active section semantically")
assert(layout_snapshot.chat_text == "", "the shared layout did not preserve the chat draft")
layout.history.index = 0
layout.form.index = layout.form.fields.index(layout.history)
browsing_history_snapshot = layout.snapshot
assert(browsing_history_snapshot.history_index == 0, "browsing old history was forced back to the newest item")
assert(!browsing_history_snapshot.history_follows_tail, "old history unexpectedly followed the tail while it was focused")
layout.form.index = layout.form.fields.index(layout.chat)
returning_history_snapshot = layout.snapshot
assert(returning_history_snapshot.history_index == 0, "leaving history lost the reading position")
assert(!returning_history_snapshot.history_follows_tail, "history selection unexpectedly resumed tail-following")
layout.chat.text = "draft message"
layout.chat.index = 8
layout.chat.check = 3
chat_snapshot = layout.snapshot
restored_chat_layout = GameRoomLayout::Screen.new(
  view_spec: layout_spec,
  surface_state: {},
  history_items: [],
  user_items: [],
  history_index: 0,
  users_index: 0,
  users_header: "Users at the table (2)",
  chat_text: chat_snapshot.chat_text,
  chat_index: chat_snapshot.chat_index,
  chat_check: chat_snapshot.chat_check
)
assert(restored_chat_layout.chat.text == "draft message", "a refresh lost the chat draft")
assert(restored_chat_layout.chat.index == 8, "a refresh moved the chat caret")
assert(restored_chat_layout.chat.check == 3, "a refresh lost the chat selection anchor")
layout.suppress_focus!
layout.chat.focus
assert(layout.chat.last_focus_spoken == false, "a remote refresh repeated the active chat field")

persistent_chat_layout = GameRoomLayout::Screen.new(
  view_spec: layout_spec,
  surface_state: {},
  history_items: ["Remote move"],
  user_items: ["Alice", "Bob"],
  history_index: 0,
  users_index: 0,
  users_header: "Users at the table (2)",
  chat_text: "stale copy",
  chat_index: 0,
  chat_check: 0,
  chat_control: layout.chat
)
assert(persistent_chat_layout.chat.equal?(layout.chat), "a refresh replaced the active chat control")
assert(persistent_chat_layout.chat.text == "draft message", "a refresh restored a stale chat copy")
persistent_chat_layout.form.index = persistent_chat_layout.form.fields.index(persistent_chat_layout.chat)
persistent_chat_layout.chat.index = 8
persistent_chat_layout.chat.check = 8
persistent_chat_layout.form.resume_for_refresh
persistent_chat_layout.update(
  view_spec: layout_spec,
  history_items: ["Remote move", "Another remote move"],
  user_items: ["Alice", "Bob"],
  users_header: "Users at the table (2)",
  focus_location: [:chat, 0]
)
assert(persistent_chat_layout.chat.equal?(layout.chat), "a live update replaced the chat being edited")
assert(
  [persistent_chat_layout.chat.text, persistent_chat_layout.chat.index, persistent_chat_layout.chat.check] ==
    ["draft message", 8, 8],
  "a live update changed the chat text or selection"
)
persistent_chat_layout.chat.text =
  persistent_chat_layout.chat.text.dup.insert(persistent_chat_layout.chat.index, "X")
persistent_chat_layout.chat.index += 1
persistent_chat_layout.chat.check = persistent_chat_layout.chat.index
assert(
  persistent_chat_layout.chat.text == "draft meXssage" && persistent_chat_layout.chat.index == 9,
  "the first character typed after a live update was lost"
)
submit_result = []
persistent_chat_layout.chat.on_submit { submit_result << :old }
persistent_chat_layout.chat.on_submit { submit_result << :current }
persistent_chat_layout.chat.trigger(:select)
assert(submit_result == [:current], "a persistent chat control accumulated old submit handlers")

waiting_spec = GameRoomLayout::ViewSpec.new(
  surface: GameSurfaces::QuestionSpec.new(
    id: "waiting",
    prompt: "Categories",
    mode: :information,
    value: "Waiting for the judge"
  )
)
waiting_layout = GameRoomLayout::Screen.new(
  view_spec: waiting_spec,
  surface_state: {},
  history_items: ["Game started", "Alice moved"],
  user_items: ["Alice", "Bob"],
  history_index: 1,
  users_index: 1,
  focus_location: [:game, 7],
  users_header: "Users at the table (2)"
)
assert(waiting_layout.form.index == 0, "a shorter game surface moved focus into the users section")
waiting_layout.suppress_focus!
waiting_layout.form.controls[0].focus
assert(waiting_layout.form.controls[0].last_focus_spoken == false, "a remote refresh repeated the waiting field")

answer_layout_spec = GameRoomLayout::ViewSpec.new(
  surface: GameSurfaces::AnswerSheetSpec.new(
    id: "round_2",
    title: "Round 2",
    fields: [
      GameSurfaces::AnswerField.new(id: "country", label: "Country"),
      GameSurfaces::AnswerField.new(id: "city", label: "City")
    ]
  )
)
answer_layout = GameRoomLayout::Screen.new(
  view_spec: answer_layout_spec,
  surface_state: {},
  history_items: [],
  user_items: ["Alice", "Bob"],
  history_index: 0,
  users_index: 0,
  focus_location: [:game, 7],
  previous_surface_identity: "GameSurfaces::ReviewSpec:round_1",
  users_header: "Users at the table (2)"
)
assert(answer_layout.form.index == 0, "a new game surface inherited the previous surface's final button")

action = GameSurfaces::Action.new(
  kind: :grid,
  name: :select,
  payload: { x: 2, "y" => 1 }
)
assert(action["kind"] == "grid", "surface action lost its kind")
assert(action[:action] == "select", "surface action lost its name")
assert(action["x"] == 2 && action[:y] == 1, "surface action did not normalize payload keys")

grid = GameSurfaces.build(
  GameSurfaces::GridSpec.new(
    width: 2,
    height: 2,
    header: "Board",
    cells: [["A1", "B1"], ["A2", "B2"]],
    row_origin: :bottom
  )
)
grid_action = nil
grid.on_action { |value| grid_action = value }
grid.fields.first.trigger(:select, [1, 0])
assert(grid_action.kind == "grid" && grid_action.name == "select", "grid emitted an invalid action")
assert(grid_action["x"] == 1 && grid_action["y"] == 1, "grid emitted invalid logical coordinates")
grid_command = grid.movement_command(["B2"])
assert(grid_command.message == nil, "a valid grid command returned an error")
assert(
  grid_command.action["x"] == 1 && grid_command.action["y"] == 1 && grid_command.action.source == "chat_command",
  "a grid command did not create the same logical selection as Enter"
)
assert(grid.movement_command(["C1"]).action == nil, "a command accepted a field outside the grid")
chat_command = GameRoomChatCommands.interpret("/B2", grid)
assert(chat_command.kind == :movement && chat_command.action["x"] == 1, "chat did not route a slash command to the grid")
literal_chat = GameRoomChatCommands.interpret("//B2", grid)
assert(literal_chat.kind == :chat && literal_chat.text == "/B2", "double slash did not escape a chat command")

rook = GameSurfaces::Piece.new(
  id: "white_rook_a1",
  label: "White rook",
  owner: "Alice",
  kind: "rook"
)
piece_spec = GameSurfaces::PieceBoardSpec.new(
  id: "chess",
  width: 3,
  height: 3,
  header: "Piece board",
  pieces: [
    [rook, nil, nil],
    [nil, nil, nil],
    [nil, nil, nil]
  ],
  row_origin: :bottom,
  selectable: ["A1"],
  targets: { "A1" => ["A2", "B1"] },
  empty_label: "Empty"
)
piece_board = GameSurfaces.build(piece_spec)
piece_actions = []
piece_board.on_action { |value| piece_actions << value }
piece_control = piece_board.fields.first

piece_control.trigger(:select, [0, 2])
assert(piece_actions.empty?, "selecting a piece sent a network action")
assert(piece_board.cancel_pending_action?, "piece selection was not retained locally")
assert(piece_board.state["selected"] == { "x" => 0, "y" => 0 }, "piece board lost its selected origin")
assert(piece_control.cells[2][0].include?("selected"), "piece board did not mark the selected origin")
assert(piece_control.cells[1][0].include?("available move"), "piece board did not mark an available destination")

piece_control.trigger(:select, [2, 2])
assert(piece_actions.empty?, "piece board emitted an unavailable move")
assert($spoken_messages.last.include?("cannot move the selected piece"), "piece board did not explain an unavailable move")

piece_control.trigger(:select, [1, 2])
assert(piece_actions.length == 1, "piece board did not emit a legal move")
piece_action = piece_actions.first
assert(piece_action.kind == "piece_board" && piece_action.name == "move", "piece board emitted an invalid action")
assert(piece_action["piece_id"] == "white_rook_a1", "piece board lost the piece id")
assert(piece_action["from_field"] == "A1" && piece_action["to_field"] == "B1", "piece board lost field labels")
assert(piece_action["from_x"] == 0 && piece_action["from_y"] == 0, "piece board lost source coordinates")
assert(piece_action["to_x"] == 1 && piece_action["to_y"] == 0, "piece board lost destination coordinates")
piece_command = piece_board.movement_command(["A1", "A2"])
assert(piece_command.message == nil, "a valid piece-board command returned an error")
assert(
  piece_command.action["from_x"] == 0 && piece_command.action["from_y"] == 0 &&
    piece_command.action["to_x"] == 0 && piece_command.action["to_y"] == 1 &&
    piece_command.action.source == "chat_command",
  "a piece-board command did not produce the ordinary move action"
)
assert(piece_board.movement_command(["A1", "C3"]).action == nil, "a command accepted an unavailable piece move")

assert(piece_board.cancel_pending_action!, "piece board did not cancel a pending selection")
assert(!piece_board.cancel_pending_action?, "piece board kept a cancelled selection")
assert(!piece_board.state.key?("selected"), "cancelled piece selection leaked into state")

restored_piece_board = GameSurfaces.build(
  piece_spec,
  state: { "x" => 1, "y" => 0, "selected" => { "x" => 0, "y" => 0 } }
)
assert(restored_piece_board.cancel_pending_action?, "piece board did not restore its selected origin")
restored_piece_board.fields.first.trigger(:select, [0, 2])
assert(!restored_piece_board.cancel_pending_action?, "selecting the origin again did not cancel it")

spectator_board = GameSurfaces.build(
  GameSurfaces::PieceBoardSpec.new(
    id: "spectator",
    width: 1,
    height: 1,
    header: "Board",
    pieces: [[rook]],
    selectable: []
  )
)
spectator_board.fields.first.trigger(:select, [0, 0])
assert(!spectator_board.cancel_pending_action?, "spectator could select a piece")

sparse_board = GameSurfaces.build(
  GameSurfaces::PieceBoardSpec.new(
    id: "sparse",
    width: 3,
    height: 1,
    header: "Sparse board",
    pieces: [[rook, nil, nil]],
    selectable: [],
    navigable: ["A1", "C1"]
  )
)
sparse_control = sparse_board.fields.first
sparse_control.move_by(1, 0)
assert(sparse_control.x == 2 && sparse_control.y == 0, "sparse board navigation did not skip an unused field")
assert(sparse_control.coordinate_label == "C1", "sparse board navigation changed the original field coordinate")

checker_navigation = GameSurfaces.build(
  GameSurfaces::PieceBoardSpec.new(
    id: "checker_navigation",
    width: 4,
    height: 4,
    header: "Board",
    pieces: Array.new(4) { Array.new(4) },
    selectable: [],
    navigable: [[0, 3], [2, 3], [1, 2], [3, 2], [0, 1], [2, 1], [1, 0], [3, 0]],
    row_origin: :bottom
  ),
  state: { "x" => 0, "y" => 3 }
)
checker_control = checker_navigation.fields.first
checker_control.move_by(0, 1)
assert(checker_navigation.state.values_at("x", "y") == [1, 2], "vertical checker navigation did not reach the adjacent playable row")
checker_control.set_logical_position(2, 1)
checker_control.move_by(0, -1)
assert(
  checker_navigation.state.values_at("x", "y") == [3, 2],
  "vertical checker navigation shifted left instead of preserving the field column"
)
checker_control.move_by(0, 1)
assert(
  checker_navigation.state.values_at("x", "y") == [2, 1],
  "reverse vertical checker navigation did not return to the original field column"
)

standard_checkers_fields = Array.new(8) do |y|
  Array.new(8) { |x| [x, y] if (x + y).odd? }
end.flatten(1).compact
standard_checkers_labels = Array.new(8) { Array.new(8, "") }
standard_checkers_fields.each do |x, y|
  standard_checkers_labels[y][x] = ((7 - y) * 4 + x / 2 + 1).to_s
end
standard_checkers_navigation = GameSurfaces.build(
  GameSurfaces::PieceBoardSpec.new(
    id: "standard_checkers_navigation",
    width: 8,
    height: 8,
    header: "Board",
    pieces: Array.new(8) { Array.new(8) },
    selectable: [],
    navigable: standard_checkers_fields,
    coordinate_label_sets: { "numeric" => standard_checkers_labels },
    default_coordinate_label_set: "numeric",
    row_origin: :bottom
  ),
  state: { "x" => 6, "y" => 3 }
)
standard_checkers_control = standard_checkers_navigation.fields.first
assert(standard_checkers_control.coordinate_label == "20", "the navigation regression did not start on field 20")
standard_checkers_control.move_by(0, -1)
assert(standard_checkers_control.coordinate_label == "16", "up from field 20 did not preserve the column and reach field 16")
standard_checkers_control.move_by(0, 1)
assert(standard_checkers_control.coordinate_label == "20", "down from field 16 did not return to field 20")

black_king = GameSurfaces::Piece.new(id: "black_king_c3", label: "black king", owner: "Bob", kind: "king")
presentation_spec = GameSurfaces::PieceBoardSpec.new(
  id: "presentation",
  width: 3,
  height: 3,
  header: "Board",
  pieces: [[rook, nil, nil], [nil, nil, nil], [nil, nil, black_king]],
  row_origin: :bottom,
  selectable: ["A1"],
  targets: { "A1" => ["A2"] },
  navigable: [[0, 0], [2, 0], [0, 1], [1, 1], [0, 2], [2, 2]],
  navigable_by_coordinate_label_set: {
    "numbers" => [[0, 0], [2, 0], [0, 1], [1, 1], [0, 2], [2, 2]],
    "coordinates" => nil
  },
  coordinate_label_sets: {
    "numbers" => [["7", "", ""], ["4", "", ""], ["1", "", "3"]],
    "coordinates" => [["A1", "B1", "C1"], ["A2", "B2", "C2"], ["A3", "B3", "C3"]]
  },
  coordinate_label_names: { "numbers" => "numbers", "coordinates" => "coordinates" },
  default_coordinate_label_set: "numbers",
  default_orientation: "normal",
  orientation_labels: { "normal" => "Own side at bottom", "rotated" => "Opponent side at bottom" },
  square_details: Array.new(3) { Array.new(3, "No threat") }
)
presentation_board = GameSurfaces.build(presentation_spec, state: { "x" => 0, "y" => 0 })
presentation_control = presentation_board.fields.first
assert(presentation_control.coordinate_label == "7", "piece board ignored its default coordinate notation")
numeric_command = presentation_board.movement_command(["7", "4"])
assert(
  numeric_command.action != nil && numeric_command.action["from_field"] == "7" && numeric_command.action["to_field"] == "4",
  "a piece-board command ignored the active numeric notation"
)
presentation_control.focus
assert($spoken_messages.last == "7, White rook", "piece board did not announce the field before its occupant")
presentation_board.handle_command("toggle_coordinate_labels")
assert(presentation_control.coordinate_label == "A1", "piece board did not switch coordinate notation")
presentation_control.move_by(1, 0)
assert(presentation_board.state.values_at("x", "y") == [1, 0], "coordinate notation did not enable navigation through every board field")
presentation_board.handle_command("toggle_coordinate_labels")
assert(
  presentation_spec.navigable.include?(presentation_board.state.values_at("x", "y")),
  "restricted notation did not return from a light field to a playable field"
)
presentation_board.handle_command("toggle_coordinate_labels")
position_before_rotation = presentation_board.state.values_at("x", "y")
presentation_board.handle_command("toggle_orientation")
assert(presentation_board.state.values_at("x", "y") == position_before_rotation, "rotating a board changed the selected logical field")
assert(
  presentation_control.x == 2 - position_before_rotation[0] && presentation_control.y == 2 - position_before_rotation[1],
  "rotating a board did not reverse both axes"
)
presentation_board.handle_command("navigate_piece", { "owner" => "Bob", "kind" => "king" })
assert(presentation_board.state.values_at("x", "y") == [2, 2], "piece navigation did not move to the matching piece")
assert($spoken_messages.last.include?("C3, black king"), "piece navigation did not announce the field and piece")
presentation_board.handle_command("announce_square_details")
assert($spoken_messages.last == "No threat", "piece board did not announce details for the current field")

silent_board = GameSurfaces.build(
  GameSurfaces::PieceBoardSpec.new(
    id: "silent_fields",
    width: 2,
    height: 1,
    header: "Board",
    pieces: [[nil, nil]],
    selectable: [],
    navigable_by_coordinate_label_set: { "numbers" => nil, "coordinates" => nil },
    silent_positions_by_coordinate_label_set: { "numbers" => [[1, 0]] },
    silent_sound: "ding",
    coordinate_label_sets: {
      "numbers" => [["1", ""]],
      "coordinates" => [["A1", "B1"]]
    },
    default_coordinate_label_set: "numbers"
  )
)
silent_sounds = []
silent_actions = []
silent_board.sound_player = ->(name) { silent_sounds << name }
silent_board.on_action { |action| silent_actions << action }
silent_control = silent_board.fields.first
silent_control.set_logical_position(1, 0)
spoken_before_silent_focus = $spoken_messages.length
silent_control.focus
assert(silent_sounds == ["ding"], "an unplayable field did not play ding on focus")
assert($spoken_messages.length == spoken_before_silent_focus, "an unplayable field spoke a name or coordinate")
silent_control.trigger(:select, [1, 0])
assert(silent_sounds == ["ding", "ding"], "Enter on an unplayable field did not play ding")
assert(silent_actions.empty?, "Enter on an unplayable field emitted a move")
silent_board.handle_command("toggle_coordinate_labels")
silent_control.focus
assert($spoken_messages.last.end_with?("B1"), "coordinate notation kept an unplayable field silent")
assert(silent_sounds == ["ding", "ding"], "coordinate notation played the numeric-field sound")

activation_board = GameSurfaces.build(
  GameSurfaces::PieceBoardSpec.new(
    id: "roll_board",
    width: 1,
    height: 1,
    header: "Board",
    pieces: [[nil]],
    selectable: [],
    activation_action: GameSurfaces::Action.new(kind: "dice", name: "roll", source: "board")
  )
)
activation_action = nil
activation_board.on_action { |value| activation_action = value }
activation_board.fields.first.trigger(:select, [0, 0])
assert(activation_action&.kind == "dice" && activation_action&.name == "roll", "piece board activation did not emit its direct action")
assert(!activation_board.cancel_pending_action?, "piece board activation started piece selection")

pawn_track = GameSurfaces.build(
  GameSurfaces::PawnTrackSpec.new(
    id: "race_pawns",
    header: "Choose a pawn",
    items: [
      GameSurfaces::PawnTrackItem.new(
        id: "pawn_1",
        label: "Pawn 1: track 4; will move to track 10",
        action: GameSurfaces::Action.new(kind: "pawn", name: "move", payload: { "pawn" => "0" })
      ),
      GameSurfaces::PawnTrackItem.new(id: "pawn_2", label: "Pawn 2: base")
    ],
    empty_label: "No pawns",
    activation_action: GameSurfaces::Action.new(kind: "dice", name: "roll")
  ),
  state: { "item_id" => "pawn_1" }
)
pawn_action = nil
pawn_track.on_action { |value| pawn_action = value }
pawn_track.fields.first.trigger(:select, [0])
assert(pawn_action&.kind == "pawn" && pawn_action["pawn"] == "0", "pawn track did not prefer an item's move action")
pawn_track.fields.first.trigger(:select, [1])
assert(pawn_action&.kind == "dice" && pawn_action&.name == "roll", "pawn track did not use its direct activation action")
assert(pawn_track.state["item_id"] == "pawn_1", "pawn track did not preserve selection by stable item id")
pawn_track.suppress_next_focus!
pawn_track.fields.first.focus
assert(pawn_track.fields.first.last_focus_spoken == false, "pawn track refresh repeated its header")

begin
  GameSurfaces.build(
    GameSurfaces::PieceBoardSpec.new(
      id: "invalid",
      width: 1,
      height: 1,
      header: "Board",
      pieces: [[rook]],
      selectable: ["A1"],
      targets: { "A1" => ["B1"] }
    )
  )
  raise "piece board accepted a target outside the board"
rescue ArgumentError => error
  raise if error.message == "piece board accepted a target outside the board"
end

cards = GameSurfaces.build(
  GameSurfaces::CardTableSpec.new(
    zones: [
      GameSurfaces::CardZoneSpec.new(
        id: "hand",
        header: "Hand",
        cards: [GameSurfaces::Card.new(id: "red_5", label: "Red five", value: 5)],
        empty_label: "Empty"
      )
    ]
  )
)
card_action = nil
cards.on_action { |value| card_action = value }
cards.fields.first.trigger(:select, [0])
assert(card_action.kind == "card" && card_action["card_id"] == "red_5", "card table emitted an invalid action")
cards.suppress_next_focus!(0)
cards.fields.first.focus
assert(cards.fields.first.last_focus_spoken == false, "card refresh repeated the full zone header")
cards.fields.first.focus
assert(cards.fields.first.last_focus_spoken == true, "card refresh permanently silenced manual focus")

flexible_cards = GameSurfaces.build(
  GameSurfaces::CardTableSpec.new(
    zones: [
      GameSurfaces::CardZoneSpec.new(
        id: "hand",
        header: "Hand",
        cards: [
          GameSurfaces::Card.new(
            id: "ten_hearts",
            label: "10 of hearts",
            value: "ten_hearts|plus",
            choices: [
              GameSurfaces::CardChoice.new(id: "plus", label: "Add 10", value: "ten_hearts|plus"),
              GameSurfaces::CardChoice.new(id: "minus", label: "Subtract 10", value: "ten_hearts|minus")
            ],
            choice_header: "Choose a value"
          )
        ],
        empty_label: "Empty"
      )
    ]
  )
)
flexible_action = nil
flexible_cards.on_action { |value| flexible_action = value }
flexible_cards.fields.first.trigger(:select, [0])
assert(flexible_action == nil, "opening a card choice emitted a game action")
assert(flexible_cards.cancel_pending_action?, "the card choice was not retained locally")
assert(flexible_cards.fields.first.options == ["Add 10", "Subtract 10"], "the card did not open its choices")
assert(flexible_cards.fields.first.header == "Choose a value", "the card ignored its custom choice header")
flexible_cards.fields.first.trigger(:select, [1])
assert(flexible_action["card_id"] == "ten_hearts", "the chosen card lost its physical id")
assert(flexible_action["card"] == "ten_hearts|minus", "the chosen card emitted the wrong value")
assert(!flexible_cards.cancel_pending_action?, "a completed card choice remained pending")
assert(flexible_cards.fields.first.options == ["10 of hearts"], "the hand did not return after choosing a value")

flexible_cards.fields.first.trigger(:select, [0])
assert(flexible_cards.cancel_pending_action!, "Escape could not cancel a card choice")
assert(flexible_cards.fields.first.options == ["10 of hearts"], "cancelling did not restore the hand")

roll_command = GameSurfaces::Command.new(id: "roll", label: "Roll", enabled: true, payload: { count: 3 })
dice = GameSurfaces.build(
  GameSurfaces::DiceTraySpec.new(
    id: "main",
    header: "Dice",
    dice: [
      GameSurfaces::Die.new(id: "d1", value: 4, sides: 6, held: false),
      GameSurfaces::Die.new(id: "d2", value: 2, sides: 6, held: true)
    ],
    commands: [roll_command]
  )
)
dice_actions = []
dice.on_action { |value| dice_actions << value }
dice.fields[0].trigger(:select, [1])
dice.fields[1].trigger(:press)
assert(dice_actions[0].kind == "dice" && dice_actions[0].name == "toggle", "dice selection has an invalid action")
assert(dice_actions[0]["die_id"] == "d2" && dice_actions[0]["held"] == true, "dice selection lost die state")
assert(dice_actions[1].name == "roll" && dice_actions[1]["count"] == 3, "dice command lost its payload")

question = GameSurfaces.build(
  GameSurfaces::QuestionSpec.new(
    id: "capital",
    prompt: "Capital of Poland",
    mode: :text,
    value: "",
    required: true,
    submit_label: "Answer"
  )
)
question_action = nil
question.on_action { |value| question_action = value }
question.fields[0].text = "Warsaw"
question.fields[1].trigger(:press)
assert(question_action.kind == "question", "text question emitted an invalid action")
assert(question_action["question_id"] == "capital" && question_action["answer"] == "Warsaw", "text answer was not collected")

multiple = GameSurfaces.build(
  GameSurfaces::QuestionSpec.new(
    id: "colors",
    prompt: "Choose colors",
    mode: :multiple_choice,
    options: [
      GameSurfaces::QuestionOption.new(id: "red", label: "Red"),
      GameSurfaces::QuestionOption.new(id: "blue", label: "Blue")
    ],
    value: ["blue"]
  )
)
multiple_action = nil
multiple.on_action { |value| multiple_action = value }
multiple.fields[1].trigger(:press)
assert(multiple_action["answer"] == ["blue"], "multiple-choice answer was not preserved")

single = GameSurfaces.build(
  GameSurfaces::QuestionSpec.new(
    id: "capital_choice",
    prompt: "Capital of Poland",
    mode: :single_choice,
    options: [
      GameSurfaces::QuestionOption.new(id: "krakow", label: "Krakow"),
      GameSurfaces::QuestionOption.new(id: "warsaw", label: "Warsaw")
    ],
    required: true,
    submit_on_select: true
  )
)
assert(single.fields.length == 1, "an immediate single choice must not add a submit button")
single_action = nil
single.on_action { |value| single_action = value }
single.fields[0].index = 1
single.fields[0].trigger(:select)
assert(single_action.kind == "question" && single_action.name == "submit", "an immediate single choice emitted an invalid action")
assert(single_action["answer"] == "warsaw", "an immediate single choice lost its selected option")

pending = single.submission_action
assert(pending != nil, "a timed question surface exposed no pending submission")
assert(pending.kind == "question" && pending.name == "submit", "a pending question submission used an invalid action")
assert(pending["answer"] == "warsaw", "a pending question submission lost the selected answer")
assert(pending["question_id"] == "capital_choice", "a pending question submission lost its question id")

readable_spec = GameSurfaces::QuestionSpec.new(
  id: "readable_capital",
  prompt: "Capital of Poland",
  mode: :single_choice,
  options: [
    GameSurfaces::QuestionOption.new(id: "krakow", label: "Krakow"),
    GameSurfaces::QuestionOption.new(id: "warsaw", label: "Warsaw"),
    GameSurfaces::QuestionOption.new(id: "paris", label: "Paris"),
    GameSurfaces::QuestionOption.new(id: "rome", label: "Rome")
  ],
  required: true,
  submit_on_select: true,
  prompt_in_choices: true
)
readable = GameSurfaces.build(readable_spec)
assert(readable.fields[0].options == ["Capital of Poland", "Krakow", "Warsaw", "Paris", "Rome"], "the question is not the first line above its answers")
assert(readable.fields[0].header == "", "the question is still only a list header")
assert(readable.fields[0].index == 0, "the question is not focused when the answer list opens")
readable_action = nil
readable.on_action { |value| readable_action = value }
readable.fields[0].trigger(:select)
assert(readable_action == nil, "the question line was submitted as an answer")
readable.fields[0].index = 1
readable.fields[0].trigger(:select)
assert(readable_action != nil && readable_action["answer"] == "krakow", "the first answer below the question mapped to the wrong option")
readable.fields[0].index = 4
readable.fields[0].trigger(:select)
assert(readable_action["answer"] == "rome", "the last answer below the question mapped to the wrong option")
restored_readable = GameSurfaces.build(readable_spec, state: readable.state)
assert(restored_readable.fields[0].index == 4, "refreshing the answer list lost its position")

information = GameSurfaces.build(
  GameSurfaces::QuestionSpec.new(
    id: "summary",
    prompt: "Round summary",
    mode: :information,
    value: "Alice leads."
  )
)
assert(information.submission_action == nil, "an information surface must not submit an answer")

read_only_question = GameSurfaces.build(
  GameSurfaces::QuestionSpec.new(
    id: "closed",
    prompt: "Capital of Poland",
    mode: :single_choice,
    options: [GameSurfaces::QuestionOption.new(id: "warsaw", label: "Warsaw")],
    read_only: true
  )
)
assert(read_only_question.submission_action == nil, "a read-only question must not submit an answer")

sheet = GameSurfaces.build(
  GameSurfaces::AnswerSheetSpec.new(
    id: "cities",
    title: "Countries and cities",
    fields: [
      GameSurfaces::AnswerField.new(id: "country", label: "Country", required: true),
      GameSurfaces::AnswerField.new(id: "city", label: "City", required: true)
    ]
  )
)
sheet_action = nil
sheet.on_action { |value| sheet_action = value }
assert(sheet.fields[0].header == "Countries and cities", "the answer sheet lost its separate heading")
assert(sheet.fields[1].header == "Country", "the answer sheet merged its title into the first answer field")
sheet.fields[1].text = "Poland"
sheet.fields[2].text = "Poznan"
sheet.fields[3].trigger(:press)
assert(sheet_action.kind == "answer_sheet", "answer sheet emitted an invalid action")
assert(sheet_action["answers"] == { "country" => "Poland", "city" => "Poznan" }, "answer sheet lost answers")

review = GameSurfaces.build(
  GameSurfaces::ReviewSpec.new(
    id: "round_1",
    header: "Review answers",
    items: [
      GameSurfaces::ReviewItem.new(id: "a1", author: "Alice", category: "City", answer: "Athens")
    ],
    decisions: [
      GameSurfaces::ReviewDecision.new(id: "accept", label: "Accept"),
      GameSurfaces::ReviewDecision.new(id: "reject", label: "Reject")
    ]
  )
)
review_actions = []
review.on_action { |value| review_actions << value }
assert(review.fields[0].header == "Review answers", "the review heading was merged into the first answer")
assert(review.fields[1].header == "City; Alice: Athens", "the first answer lost its own label")
review.fields[1].index = 1
review.fields[1].trigger(:move, 1)
assert(review_actions.empty?, "moving through review choices submitted a false assessment")
review.fields[1].trigger(:select, 1)
assert(review_actions.last.kind == "review" && review_actions.last.name == "change", "manual review emitted an invalid change")
assert(review_actions.last["item_id"] == "a1" && review_actions.last["decision"] == "accept", "manual review lost its answer decision")
assert(review_actions.last["_stay_open"] == true, "an assessment still requests a full form refresh")
assert(review.state["decisions"] == { "a1" => "accept" }, "manual review did not preserve its choices")
assert(review.state["confirmed"] == { "a1" => "accept" }, "manual review did not preserve its confirmed assessments")
review.suppress_next_focus!(1)
review.fields[1].focus
assert(review.fields[1].last_focus_spoken == false, "review refresh repeated the active answer")
review.fields[2].trigger(:press)
assert(review_actions.last.name == "finish", "manual review did not emit its final confirmation")
assert(review_actions.last["decisions"] == { "a1" => "accept" }, "final review confirmation lost its assessments")

read_only_review = GameSurfaces.build(
  GameSurfaces::ReviewSpec.new(
    id: "round_1_read_only",
    header: "Revealed answers",
    items: [
      GameSurfaces::ReviewItem.new(id: "a1", author: "Alice", category: "City", answer: "Athens")
    ],
    decisions: [],
    read_only: true
  )
)
assert(read_only_review.fields.length == 1, "a read-only review exposed judging controls")

composite = GameSurfaces.build(
  GameSurfaces::CompositeSpec.new(
    parts: [
      GameSurfaces::SurfacePart.new(
        id: "actions",
        surface: GameSurfaces::CommandPanelSpec.new(
          commands: [GameSurfaces::Command.new(id: "finish", label: "Finish", enabled: true)]
        )
      ),
      GameSurfaces::SurfacePart.new(
        id: "question",
        surface: GameSurfaces::QuestionSpec.new(
          id: "name",
          prompt: "Name",
          mode: :text
        )
      )
    ]
  )
)
composite_action = nil
composite.on_action { |value| composite_action = value }
composite.fields[0].trigger(:press)
assert(composite_action.name == "finish" && composite_action.source == "actions", "composite surface lost action source")
assert(composite.state["parts"].key?("question"), "composite surface did not preserve child state")

piece_composite = GameSurfaces.build(
  GameSurfaces::CompositeSpec.new(
    parts: [GameSurfaces::SurfacePart.new(id: "board", surface: piece_spec)]
  )
)
piece_composite.fields.first.trigger(:select, [0, 2])
assert(piece_composite.cancel_pending_action?, "composite surface did not expose a child selection")
assert(piece_composite.cancel_pending_action!, "composite surface did not cancel a child selection")
assert(!piece_composite.cancel_pending_action?, "composite surface kept a cancelled child selection")

puts "Game surface framework tests passed"

# A room without a game has no artificial board or action list.
require_relative "../../lib/room_presentation"
room_rows = ["Alice", "bot:7:1", "bot:7:2", "bot:7:3"].map do |id|
  RoomPresentation::User.new(participant: id, label: id)
end
empty_view = GameRoomLayout::ViewSpec.new
room_layout = GameRoomLayout::Screen.new(
  view_spec: empty_view, user_items: room_rows, phase: :waiting, own_table: true
)
assert(room_layout.form.fields == [room_layout.primary_button, room_layout.chat, room_layout.history, room_layout.users, room_layout.back_button], "waiting room order or optional board is wrong")
assert(room_layout.form.fields[room_layout.form.index] == room_layout.primary_button, "entering an owned room did not focus Start game")
room_layout.users.index = 2
room_layout.chat.text = "unfinished message"
room_layout.chat.index = 7
room_layout.chat.check = 3
original_controls = [room_layout.form, room_layout.users, room_layout.chat, room_layout.history]
room_layout.update_users([room_rows[0], room_rows[2], room_rows[3]])
assert(room_layout.selected_participant == "bot:7:2" && room_layout.users.index == 1, "removing an earlier row moved the selected identity")
room_layout.form.index = room_layout.form.fields.index(room_layout.chat)
room_layout.update(view_spec: layout_spec, history_items: ["started"], user_items: room_rows, users_header: "Players", phase: :active)
assert(room_layout.focus_location == [:chat, 0], "starting a game interrupted chat")
room_layout.form.index = room_layout.form.fields.index(room_layout.chat)
room_layout.update(view_spec: layout_spec, history_items: ["started", "move"], user_items: room_rows, users_header: "Players", phase: :active)
assert(room_layout.focus_location == [:chat, 0], "an ordinary game update moved focus away from chat")
assert(original_controls == [room_layout.form, room_layout.users, room_layout.chat, room_layout.history], "a game update rebuilt the room controls")
assert([room_layout.chat.text, room_layout.chat.index, room_layout.chat.check] == ["unfinished message", 7, 3], "starting a game lost the chat draft or caret")
assert(!room_layout.form.fields.include?(room_layout.primary_button) && !room_layout.form.fields.include?(room_layout.restart_button), "active game exposed start/restart")
room_layout.update(view_spec: layout_spec, history_items: ["finished"], user_items: room_rows, users_header: "Players", phase: :finished, own_table: true)
assert(room_layout.form.fields == [room_layout.restart_button, room_layout.surface.fields.first, room_layout.chat, room_layout.history, room_layout.users, room_layout.back_button], "finished game order is wrong")
assert(room_layout.focus_location == [:chat, 0], "ending a game interrupted chat")
room_layout.form.index = room_layout.form.fields.index(room_layout.restart_button)
room_layout.form.index += 1
assert(room_layout.focus_location == [:game, 0], "Tab from Restart game does not reach the final board")
room_layout.update(view_spec: layout_spec, history_items: ["finished", "chat"], user_items: room_rows, users_header: "Players", phase: :finished, own_table: true)
assert(room_layout.focus_location == [:game, 0], "a finished-game update interrupted board inspection")
room_layout.form.index = room_layout.form.fields.index(room_layout.restart_button)
room_layout.update(view_spec: layout_spec, history_items: [], user_items: room_rows, users_header: "Players", phase: :active)
assert(room_layout.focus_location == [:game, 0], "restarting a finished game did not focus its board")
room_layout.update(view_spec: empty_view, history_items: [], user_items: room_rows, users_header: "Players", phase: :waiting, own_table: false)
assert(room_layout.form.fields.first == room_layout.waiting_status, "a guest did not receive the waiting status")
assert(room_layout.waiting_status.options == ["Waiting for the game to start"], "the initial waiting status is wrong")
room_layout.update(view_spec: layout_spec, history_items: [], user_items: room_rows, users_header: "Players", phase: :finished, own_table: false)
assert(room_layout.form.fields == [room_layout.waiting_status, room_layout.surface.fields.first, room_layout.chat, room_layout.history, room_layout.users, room_layout.back_button], "guest final-position controls are wrong")
assert(room_layout.waiting_status.options == ["Waiting for a new game to start"], "the finished waiting status is wrong")

calls = []
3.times do |iteration|
  room_layout.begin_bindings
  room_layout.primary_button.on(:press) { calls << iteration }
  room_layout.form.add_timer(Object.new)
end
room_layout.primary_button.trigger(:press)
assert(calls == [2], "persistent controls accumulated obsolete handlers")
assert(room_layout.form.instance_variable_get(:@timers).length == 1, "persistent form accumulated refresh timers")
room_layout.begin_bindings
assert(room_layout.form.instance_variable_get(:@timers).empty?, "leaving a screen left its timer running")

require_relative "../../lib/participant_menu"
menu_calls = []
allowed = [:invite_online, :invite_contacts, :accept_invitation, :reject_invitation, :add_bot, :remove_bot, :rules, :save_table_history]
room_layout.users.index = 2
GameRoomParticipantMenu.bind(room_layout, available: -> { allowed }) { |action, id| menu_calls << [action, id] }
global_menu = FakeMenu.new
room_layout.form.context(global_menu, false)
assert(global_menu.options.none? { |option| ["Accept a game invitation", "Reject a game invitation"].include?(option[0]) }, "global table menu exposes accepting or rejecting invitations")
assert(["Invite an online Elten user", "Invite someone from your contacts"].all? { |label| global_menu.options.any? { |option| option[0] == label } }, "global table menu lost outgoing invitations")
assert_global_invitation_menu(room_layout.form, keys: %w[i I])
assert(global_menu.options.any? { |option| option[0] == "Game rules" }, "rules are absent from the global table menu")
save_history = global_menu.options.find { |option| option[0] == "Save table history" }
assert(save_history != nil && save_history[2] == "S", "table history has no native Ctrl+Shift+S shortcut")
add = global_menu.options.find { |option| option[0] == "Add a computer" }
assert(add != nil && add[2] == "o", "adding a computer has no native Ctrl+O shortcut")
menu = FakeMenu.new
room_layout.users.context(menu, false)
remove = menu.options.find { |option| option[2] == :del }
assert(remove != nil, "computer context menu has no native Delete action")
room_layout.users.index = 3
remove[3].call
assert(menu_calls == [[:remove_bot, "bot:7:2"]], "context action lost the original row used to validate computer removal")
allowed.delete(:remove_bot)
remove[3].call
assert(menu_calls.length == 1, "stale context menu bypassed updated permissions")
allowed << :remove_bot
room_layout.users.index = 0
menu = FakeMenu.new
room_layout.users.context(menu, false)
assert(menu.options.none? { |option| option[2] == :del }, "human participant exposed computer deletion")
other_menu = FakeMenu.new
room_layout.history.context(other_menu, false)
assert(other_menu.options.none? { |option| option[2] == :del }, "Delete leaked outside the users list")
puts "Room layout and participant menu tests passed"

room_layout.update(view_spec: empty_view, history_items: [], user_items: room_rows, users_header: "Users", phase: :waiting)
room_layout.form.index = room_layout.form.fields.index(room_layout.chat)
room_layout.update(view_spec: empty_view, history_items: [], user_items: room_rows, users_header: "Users", phase: :active)
assert(room_layout.focus_location == [:chat, 0], "game without a surface interrupted chat")
room_layout.update(view_spec: empty_view, history_items: [], user_items: room_rows, users_header: "Users", phase: :waiting, own_table: true)
room_layout.form.index = room_layout.form.fields.index(room_layout.primary_button)
room_layout.update(view_spec: answer_layout_spec, history_items: [], user_items: room_rows, users_header: "Users", phase: :active)
assert(room_layout.form.fields[room_layout.form.index] == room_layout.surface.fields.first, "starting a game with several surface fields did not focus the first one")
