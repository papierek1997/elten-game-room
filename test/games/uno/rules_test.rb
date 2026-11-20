require_relative '../../support/new_games_fixture'

players = %w[Alice Bob Carol]
repository = NewGames116Repository.new(players)

uno = GameRoomGames::Uno.new
uno_session = { "options" => JSON.generate(uno.default_options) }
uno_events = []
uno_replay = uno.replay(uno_session, uno_events, repository)
deal_action = uno.automatic_action(uno_replay, "Alice")
uno_replay = append_action(uno, uno_session, repository, uno_events, uno_replay, "Alice", deal_action, context_for)
assert(uno_replay.state[:hands].values.all? { |hand| hand.length == 7 }, "UNO did not deal seven cards")
assert(uno_replay.state[:discard].length == 1, "UNO has no first discard")
uno_shortcuts = uno.custom_game_shortcuts(uno_replay, "Alice")
assert(["c", "h"].all? do |key|
  uno_shortcuts.any? { |shortcut| shortcut.key == key && shortcut.modifiers == [:shift] && shortcut.kind == :surface }
end, "UNO is missing the agreed local card-sorting shortcuts")
assert(uno_shortcuts.none? { |shortcut| shortcut.key == 'd' && shortcut.modifiers == [:shift] },
  "UNO still exposes the removed acquisition-order shortcut")
assert(uno_shortcuts.find { |shortcut| shortcut.key == "c" && shortcut.modifiers.empty? }.message !~ /Top card:/,
  "UNO still adds the redundant top-card prefix")
uno_actor = uno_replay.current_player
uno_move = uno.legal_actions(uno_replay, uno_actor).find { |action| action["action"] == "play" } ||
  uno.legal_actions(uno_replay, uno_actor).find { |action| action["action"] == "draw" }
uno_replay = append_action(uno, uno_session, repository, uno_events, uno_replay, uno_actor, uno_move)
assert(uno_replay.accepted_events.length == 2, "UNO rejected its first legal action")
assert(!uno_replay.history.last.text.match?(/[RYGB][0-9SVDF][ab0-9]/), "UNO exposed an internal card id")
assert(uno.default_options["draw_responses"] && uno.default_options["allow_optional_draw"], "UNO agreed draw defaults are missing")
assert(uno.default_options["maximum_optional_draws"] == 3, "UNO optional draw limit is not three")
uno_definitions = uno.option_definitions.to_h { |definition| [definition.key, definition] }
assert(!uno.option_visible?(uno_definitions["super_interceptions"], uno.default_options),
  "UNO shows super interceptions while interceptions are disabled")
assert(!uno.option_visible?(uno_definitions["maximum_optional_draws"], uno.default_options.merge("allow_optional_draw" => false)),
  "UNO shows the optional draw limit while optional drawing is disabled")
assert(uno.validation_error(uno.default_options.merge("allow_optional_draw" => false, "maximum_optional_draws" => 0), player_count: 3) == nil,
  "UNO validates a hidden optional draw limit")

uno_draw_state = uno.send(:initial_state, players, uno.default_options)
uno_draw_state.update(
  phase: :playing, current_player: "Alice", colour: "R", discard: ["R5a"],
  draw_pile: ["B2a"], hands: { "Alice" => ["G7a"], "Bob" => ["R1a"], "Carol" => ["Y1a"] }
)
uno_draw_history = []
assert(uno.send(:apply_draw, uno_draw_state,
  { "id" => 20, "actor" => "Alice", "action" => "draw", "value" => "" },
  "Alice", repository, uno_draw_history), "UNO rejected a normal voluntary draw")
assert(uno_draw_state[:current_player] == "Bob" && uno_draw_state[:optional_draws].zero?,
  "UNO did not end the turn after drawing with no playable card in hand")

assert(!uno.default_options["bluff_challenge"], "UNO bluff challenge is not an optional, disabled-by-default rule")
mercy_options = uno.normalize_options("deck" => "no_mercy", "advanced_responses" => true)
penalty_state = uno.send(:initial_state, players, mercy_options)
penalty_state.update(phase: :playing, current_player: "Alice", colour: "R", discard: ["RXa"],
  pending_draw: 4, pending_type: "X", pending_family: "coloured_draw",
  hands: { "Alice" => %w[GXa NF0 YSa GAa], "Bob" => ["R1a"], "Carol" => ["Y1a"] })
assert(uno.send(:playable?, penalty_state, "GXa"), "UNO No Mercy rejected an equal coloured draw response")
assert(!uno.send(:playable?, penalty_state, "NF0"), "UNO No Mercy mixed a wild and coloured draw chain")
assert(uno.send(:playable?, penalty_state, "YSa"), "UNO advanced responses rejected Skip")
skip_response_state = Marshal.load(Marshal.dump(penalty_state))
skip_response_history = []
assert(uno.send(:apply_play, skip_response_state,
  { "id" => 21, "actor" => "Alice", "action" => "play", "value" => "YSa||0" },
  "Alice", repository, skip_response_history), "UNO rejected Skip as an advanced response")
assert(skip_response_state[:pending_draw] == 4 && skip_response_state[:current_player] == "Bob",
  "UNO Skip did not pass the draw obligation to exactly the next player")

cancel_response_state = Marshal.load(Marshal.dump(penalty_state))
cancel_response_history = []
assert(uno.send(:apply_play, cancel_response_state,
  { "id" => 22, "actor" => "Alice", "action" => "play", "value" => "GAa||0" },
  "Alice", repository, cancel_response_history), "UNO rejected Discard All as an advanced response")
assert(cancel_response_state[:pending_draw].zero? && cancel_response_state[:pending_family] == nil,
  "UNO Discard All did not cancel the No Mercy draw chain")

seven_options = uno.normalize_options("zero_seven" => true)
seven_state = uno.send(:initial_state, players, seven_options)
seven_state.update(phase: :playing, current_player: "Alice", colour: "R", discard: ["R5a"],
  hands: { "Alice" => %w[R7a R9a], "Bob" => ["B1a"], "Carol" => ["G2a"] })
seven_replay = GameRoomGames::Replay.new(players: players, current_player: "Alice", winner: nil,
  draw: false, accepted_events: [], history: [], state: seven_state)
seven_actions = uno.legal_actions(seven_replay, "Alice").select { |action| action["card"] == "R7a" }
assert(seven_actions.map { |action| action["choice"] }.sort == %w[p1 p2],
  "UNO seven does not offer every other active player as a hand-swap target")
seven_history = []
assert(uno.send(:apply_play, seven_state,
  { "id" => 23, "actor" => "Alice", "action" => "play", "value" => "R7a|p2|0" },
  "Alice", repository, seven_history), "UNO rejected the selected seven target")
assert(seven_state[:hands]["Alice"] == ["G2a"] && seven_state[:hands]["Carol"] == ["R9a"],
  "UNO seven swapped with a different player than the selected target")

mercy_state = uno.send(:initial_state, players, mercy_options.merge("no_mercy_limit" => 3))
mercy_state.update(phase: :playing, current_player: "Alice",
  hands: { "Alice" => %w[R1a R2a R3a], "Bob" => ["B1a"], "Carol" => ["G1a"] })
mercy_history = []
uno.send(:apply_no_mercy, mercy_state, "Alice", 24, mercy_history)
assert(mercy_state[:round_eliminated]["Alice"] && !mercy_state[:eliminated]["Alice"],
  "UNO No Mercy removed a player from the whole match instead of only the current round")
assert(mercy_state[:scores]["Alice"] == 250,
  "UNO No Mercy did not apply the round-elimination penalty")
assert(uno.send(:next_game_active_index, mercy_state, 2, 1) == 0,
  "UNO No Mercy did not return a round-eliminated player to the next dealer rotation")

puts 'PASS uno: rules, legal actions and options'
