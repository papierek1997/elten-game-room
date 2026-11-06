require_relative "../../support/ui"
require_relative "../../support/elten_array_shuffle"
require_relative "../../../lib/game_surfaces"
require_relative "../../../lib/game_screen"
require_relative "../../../games/rummy"

def n_(one, many, count); count == 1 ? one : many; end
def assert(value, message); raise message unless value; end

def interaction_fixture(mode = "single", drawn: true, opened: true, viewer: "Alice")
  game = GameRoomGames::Rummy.new
  state = game.initial_state(%w[Alice Bob], game.default_options.merge("discard_mode" => mode, "manipulation" => true))
  state.merge!(phase: :playing, round: 1, turn: 1, current_player: "Alice", drawn: drawn,
    first_meld: { "Alice" => opened }, stock: %w[AC0], discard: %w[9H0 7D0 5C0],
    hands: { "Alice" => %w[2S0 3S0 4S0 8H0 KS0], "Bob" => %w[QC0] },
    melds: [GameRoomRummyRules.validate(%w[TS1 JS1 QS1]).merge(id: 1)])
  state[:turn_initial_hand] = state[:hands]["Alice"].dup
  replay = GameRoomGames::Replay.new(players: state[:players], current_player: "Alice", state: state, history: [])
  surface = GameSurfaces.build(game.surface_spec(replay, viewer))
  emitted = []
  surface.on_action { |action| emitted << action }
  [game, state, replay, surface, surface.fields.first, emitted]
end

def select_row(control, index)
  control.index = index
  control.trigger(:select, [index])
end

def prepare_group(surface, control)
  surface.handle_command("meld_new")
  [0, 1, 2].each { |index| select_row(control, index) }
end

def shortcut(game, replay, key, modifiers = [])
  game.game_shortcuts(replay, "Alice").find { |item| item.key == key && item.modifiers.to_a == modifiers }
end

checks = []
check = lambda do |name, &block|
  $spoken_messages.clear
  begin
    block.call
    checks << { name: name, passed: true }
  rescue StandardError => error
    checks << { name: name, passed: false, error: error.message }
  end
end

%w[none discard single multiple].each do |mode|
  check.call("D only announces visible discards: #{mode}") do
    game, state, replay, surface, control, emitted = interaction_fixture(mode, drawn: false)
    before = Marshal.dump(state)
    read = shortcut(game, replay, "d")
    assert(read.kind == :announcement, "D opens a dialog")
    expected = mode == "none" ? "There is no discard pile in this variant." : mode == "multiple" ? "5 of clubs, 7 of diamonds, 9 of hearts" : "5 of clubs"
    assert(read.message == expected, "wrong visible discard order or scope: #{read.message}")
    screen = GameScreen.allocate
    original = control.options.dup
    screen.send(:activate_game_shortcut, read, surface, replay: replay)
    assert($spoken_messages.last == expected && control.options == original && emitted.empty?, "D changed the surface or played")
    assert(Marshal.dump(state) == before, "reading changed game state")
  end
end

%w[single multiple].each do |mode|
  check.call("one possible discard draw needs no extra Enter: #{mode}") do
    game, state, replay, surface, control, = interaction_fixture(mode, drawn: false)
    state[:discard] = ["5C0"] if mode == "multiple"
    surface.update_spec(game.surface_spec(replay, "Alice"))
    original = control.options.dup
    action = surface.handle_command("meld_discard_pile")
    assert(action.is_a?(GameSurfaces::Action) && action.name == "draw" && action["depth"] == 1, "not a direct draw")
    assert(control.options == original, "one choice opened a list")
    status, = game.action_for(action, replay, "Alice", context: GameRoomGames::ActionContext.new(now: 1))
    assert(status == :ok, "direct draw bypasses or fails game validation")
  end
end

check.call("multiple discards survive harmless refresh and draw the selected packet") do
  game, state, replay, surface, control, emitted = interaction_fixture("multiple", drawn: false)
  surface.handle_command("meld_discard_pile")
  assert(control.options == ["5 of clubs", "7 of diamonds", "9 of hearts"], "wrong picker labels")
  control.index = 1
  surface.update_spec(game.surface_spec(replay, "Alice"))
  assert(control.header == "Discard pile" && control.index == 1, "refresh closed or moved discard picker")
  select_row(control, 1)
  assert(emitted.one? && emitted.first.name == "draw" && emitted.first["depth"] == 2, "Enter selected a hand card, not the packet")
  before = state[:hands]["Alice"].dup
  data = emitted.first.to_h.merge("round" => 1, "turn" => 1, "time" => 1)
  assert(game.send(:apply, state, data, "Alice", 1, []) == :ok, "packet invalid")
  surface.update_spec(game.surface_spec(replay, "Alice"))
  assert(state[:hands]["Alice"] == before + %w[5C0 7D0], "wrong acquisition order")
  assert(surface.take_cursor_announcement(0) == "7 of diamonds", "last drawn cursor announcement")
end

check.call("disabled discard draws explain first meld without offering a list") do
  _game, _state, _replay, surface, control, emitted = interaction_fixture(drawn: false, opened: false)
  original = control.options.dup
  surface.handle_command("meld_discard_pile")
  assert($spoken_messages.last == "Make your first meld before taking discards.", "generic unavailable message")
  assert(control.options == original && emitted.empty?, "illegal draw changed view")
end

check.call("Enter before drawing does not present a Cancel-only action menu") do
  _game, _state, _replay, _surface, control, emitted = interaction_fixture(drawn: false)
  original = control.options.dup
  select_row(control, 0)
  assert(control.options == original && emitted.empty?, "non-action menu opened")
  assert($spoken_messages.last == "Draw a card first.", "missing draw explanation")
end

check.call("Escape from card choices reads the card without Your hand") do
  _game, _state, _replay, surface, control, = interaction_fixture
  select_row(control, 4)
  assert(control.header == "Choose an action", "choice did not open")
  surface.cancel_pending_action!
  assert(control.index == 4 && control.last_focus_header == "", "Escape repeats the hand heading or moves cursor")
end

check.call("C while choosing a card cannot leave an invisible pending choice") do
  _game, _state, _replay, surface, control, emitted = interaction_fixture
  select_row(control, 4)
  surface.handle_command("meld_table")
  surface.cancel_pending_action!
  assert(control.options.last == "king of spades" && control.index == 4, "return from table restores wrong list/cursor")
  select_row(control, 4)
  assert(emitted.empty? && control.header == "Choose an action", "next Enter played a stale choice")
end

check.call("prepared group editor survives state refresh and surface recreation") do
  game, _state, replay, surface, control, emitted = interaction_fixture
  prepare_group(surface, control)
  surface.handle_command("meld_edit")
  surface.update_spec(game.surface_spec(replay, "Alice"))
  assert(control.header == "Prepared melds", "refresh silently closes draft editor")
  select_row(control, 0)
  control.index = 1
  restored = GameSurfaces.build(game.surface_spec(replay, "Alice"), state: surface.state)
  assert(restored.fields.first.header == "Prepared meld" && restored.fields.first.index == 1, "recreation lost the selected draft operation")
  restored.update_spec(game.surface_spec(replay, "Alice"))
  select_row(restored.fields.first, 1)
  assert(restored.state["meld_groups"].empty? && emitted.empty?, "Remove did not remove the draft locally")
end

check.call("expired discard chooser cannot play a hand card on the next Enter") do
  game, state, replay, surface, control, emitted = interaction_fixture("multiple", drawn: false)
  surface.handle_command("meld_discard_pile")
  state[:turn] += 1
  state[:current_player] = "Bob"
  surface.update_spec(game.surface_spec(replay, "Alice"))
  select_row(control, 0)
  assert(control.header == "Your hand" && emitted.empty?, "stale view switched Enter into an unintended action")
end

check.call("taking from table returns to the actual newly acquired card") do
  game, state, replay, surface, control, emitted = interaction_fixture
  surface.handle_command("meld_table")
  action = game.surface_spec(replay, "Alice").table.first[:actions].first[:action]
  surface.send(:send_table_action, action)
  assert(control.header == "Your hand", "take keeps cursor on a table meld")
  data = emitted.first.to_h.merge("round" => 1, "turn" => 1, "time" => 1)
  game.send(:apply, state, data, "Alice", 2, [])
  surface.update_spec(game.surface_spec(replay, "Alice"))
  assert(control.options[control.index] == "queen of spades" && surface.take_cursor_announcement(0) == "queen of spades", "borrowed cards break the hand cursor")
end

check.call("P reports missing first meld points and invalid selections honestly") do
  game, state, replay, surface, control, = interaction_fixture(opened: false)
  prepare_group(surface, control)
  surface.handle_command("meld_read")
  assert($spoken_messages.last.include?("15 more required"), "P omits how much is missing")
  select_row(control, 1)
  surface.handle_command("meld_read")
  assert($spoken_messages.last.include?("do not form valid ordered melds"), "P does not flag invalid draft")
  state[:first_meld]["Alice"] = true
  surface.update_spec(game.surface_spec(replay, "Alice"))
  select_row(control, 1) # append order is now 2,4,3: still invalid
  select_row(control, 2)
  select_row(control, 2) # restore 2,3,4
  surface.handle_command("meld_read")
  assert(!$spoken_messages.last.include?("first meld requires 0"), "P reads a fake minimum after opening")
end

check.call("sorting tells both ascending and descending directions") do
  game, _state, replay, surface, _control, = interaction_fixture
  %w[c h].each do |key|
    item = shortcut(game, replay, key, [:shift])
    surface.handle_command(item.action_name, item.payload)
    assert($spoken_messages.last.include?("ascending"), "no ascending sort confirmation")
    surface.handle_command(item.action_name, item.payload)
    assert($spoken_messages.last.include?("descending"), "no descending sort confirmation")
  end
end

check.call("identical melds are distinguishable in table and card destinations") do
  game, state, replay, _surface, _control, = interaction_fixture
  state[:melds] << GameRoomRummyRules.validate(%w[TS0 JS0 QS0]).merge(id: 2)
  spec = game.surface_spec(replay, "Alice")
  assert(spec.table.map { |entry| entry[:label] }.uniq.length == 2, "two melds have indistinguishable labels")
  choices = spec.zones.first.cards.last.choices.reject { |choice| choice.id == "cancel" }
  assert(choices.map(&:label).uniq.length == 2, "two lay-off choices have indistinguishable labels")
end

check.call("empty table explains what is empty") do
  game, state, replay, surface, _control, = interaction_fixture
  state[:melds] = []
  surface.update_spec(game.surface_spec(replay, "Alice"))
  surface.handle_command("meld_table")
  assert($spoken_messages.last == "There are no melds on the table.", "generic error on empty table")
end

check.call("table inspection follows stable meld IDs and never reads a hidden hand cursor") do
  game, state, replay, surface, control, = interaction_fixture
  state[:melds] << GameRoomRummyRules.validate(%w[6C1 7C1 8C1]).merge(id: 2)
  surface.update_spec(game.surface_spec(replay, "Alice"))
  surface.handle_command("meld_table")
  control.index = 1
  state[:melds].shift
  state[:hands]["Alice"] << "AC0"
  $spoken_messages.clear
  surface.update_spec(game.surface_spec(replay, "Alice"))
  assert(control.index == 0 && control.options.first.include?("Meld 2"), "table selection follows index instead of meld")
  assert(surface.take_cursor_announcement(0) == nil && $spoken_messages.empty?, "table refresh reads a hand card")
  surface.cancel_pending_action!
  assert(control.options[control.index] == "ace of clubs", "hidden hand did not track the actual draw")
end

check.call("no-discard Enter does not send a raw card when there is no matching meld") do
  _game, _state, _replay, _surface, control, emitted = interaction_fixture("none")
  original = control.options.dup
  select_row(control, 0)
  assert(emitted.empty? && control.options == original, "no-discard Enter emitted invalid card")
  assert($spoken_messages.last == "This card cannot be laid off. Use N to prepare a meld.", "missing way forward")
end

check.call("public history identifies lay-off and joker destinations without revealing stock") do
  game, state, _replay, _surface, _control, = interaction_fixture
  data = { "action" => "add", "round" => 1, "turn" => 1, "time" => 1, "card" => "KS0", "target" => 1, "mode" => "extend" }
  history = []
  game.send(:apply, state, data, "Alice", 10, history)
  assert(history.first.text == "Alice lays off king of spades on meld 1.", "lay-off destination missing")
  state[:melds] = [GameRoomRummyRules.validate(%w[X00 3S1 4S1]).merge(id: 3)]
  history = []
  game.send(:apply, state, data.merge("card" => "2S0", "target" => 3, "mode" => "recover"), "Alice", 11, history)
  assert(history.first.text == "Alice exchanges 2 of spades for the joker in meld 3.", "replacement card or destination missing")
end

check.call("timeout records the actual forced draw but does not reveal its card") do
  game, state, _replay, _surface, _control, = interaction_fixture(drawn: false)
  state[:turn_deadline] = 10
  history = []
  game.send(:apply, state, { "action" => "timeout", "round" => 1, "turn" => 1, "time" => 10 }, "Alice", 12, history)
  assert(history.count { |item| item.text == "Alice draws a card." } == 1, "timeout silently draws")
  assert(history.none? { |item| item.text.include?("ace of clubs") }, "stock identity is public")
end

check.call("normal round summaries give each player's total, including blocked rounds") do
  [nil, "Alice"].each do |winner|
    game, state, _replay, _surface, _control, = interaction_fixture
    state[:scores].merge!("Alice" => 35, "Bob" => 15)
    state[:meld_turn] = {}
    history = []
    game.send(:finish_round, state, winner, 13, history)
    state[:players].each do |player|
      assert(history.any? { |item| item.text == "#{player}: #{state[:scores][player]} points in total." }, "#{player}'s total missing")
    end
    assert(history.first.kind == :round_result, "scores precede round result")
  end
end

check.call("an invalid submission unticks only the invalid selection and permits a retry") do
  game, state, replay, surface, control, emitted = interaction_fixture
  original = Marshal.dump(state)
  surface.handle_command("meld_new")
  [0, 3].each { |index| select_row(control, index) }
  cursor = control.index
  assert(surface.handle_command("meld_submit") == true, "invalid meld emitted an action")
  assert(surface.state["meld_selection"].empty? && surface.state["meld_draft"], "invalid cards remain selected or editor closed")
  assert(control.options.none? { |label| label.include?("; selected") } && control.index == cursor, "labels or cursor were not preserved")
  assert(emitted.empty? && Marshal.dump(state) == original, "invalid draft changed the game")
  [0, 1, 2].each { |index| select_row(control, index) }
  action = surface.handle_command("meld_submit")
  assert(action.is_a?(GameSurfaces::Action) && action.payload["groups"] == [%w[2S0 3S0 4S0]], "could not retry directly")
end

check.call("N clears a malformed next meld without discarding correct prepared groups") do
  _game, _state, _replay, surface, control, = interaction_fixture
  prepare_group(surface, control)
  surface.handle_command("meld_new")
  [3, 4].each { |index| select_row(control, index) }
  surface.handle_command("meld_new")
  assert(surface.state["meld_groups"] == [%w[2S0 3S0 4S0]] && surface.state["meld_selection"].empty?, "valid earlier meld lost or invalid cards retained")
end

check.call("invalid groups saved in the local editor are removed without losing a valid current selection") do
  _game, _state, _replay, surface, control, = interaction_fixture
  surface.handle_command("meld_new")
  [3, 4].each { |index| select_row(control, index) }
  surface.handle_command("meld_edit")
  surface.cancel_pending_action!
  [0, 1, 2].each { |index| select_row(control, index) }
  surface.handle_command("meld_submit")
  assert(surface.state["meld_groups"].empty? && surface.state["meld_selection"] == %w[2S0 3S0 4S0], "cleared the correct selection instead of the bad stored group")
end

check.call("reading invalid cards and a valid meld below the opening minimum do not clear the draft") do
  _game, _state, _replay, surface, control, = interaction_fixture(opened: false)
  prepare_group(surface, control)
  selected = surface.state["meld_selection"]
  surface.handle_command("meld_submit")
  assert(surface.state["meld_selection"] == selected, "opening minimum rejection cleared a valid meld")
  select_row(control, 1)
  invalid = surface.state["meld_selection"]
  surface.handle_command("meld_read")
  assert(surface.state["meld_selection"] == invalid, "P changed the selection")
end

puts JSON.pretty_generate(checks)
raise "#{checks.count { |result| !result[:passed] }} Rummy interaction regressions" if checks.any? { |result| !result[:passed] }
puts "Rummy interaction: #{checks.length} scenarios passed."
