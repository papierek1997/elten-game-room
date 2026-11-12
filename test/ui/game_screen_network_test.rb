require_relative "../support/ui"
require_relative "../../lib/game_surfaces"

def _(text)
  text
end

$spoken_messages = []

def speak(text, **_options)
  $spoken_messages << text.to_s
end

module Session
  def self.name
    "Alice"
  end
end

require_relative "../../lib/game_screen"

def assert(condition, message)
  raise message if !condition
end

screen = GameScreen.allocate
assert(
  screen.send(:normalize_event_descriptions, "one event") == ["one event"],
  "a legacy single event description was not preserved"
)
assert(
  screen.send(:normalize_event_descriptions, ["first event", nil, "", "second event"]) == ["first event", "second event"],
  "separate event descriptions were not preserved"
)

shortcut_game = Object.new
shortcut_calls = 0
shortcut_game.define_singleton_method(:game_shortcuts) do |_replay, _viewer|
  shortcut_calls += 1
  [
    GameRoomGames::GameShortcut.new(
      key: "t",
      modifiers: [:control],
      label: "read the remaining time",
      kind: :announcement,
      message: "#{60 - shortcut_calls} seconds remaining."
    )
  ]
end
screen.instance_variable_set(:@game, shortcut_game)
initial_shortcut = shortcut_game.game_shortcuts(Object.new, "Alice").first
refreshed_shortcut = screen.send(:refreshed_announcement_shortcut, initial_shortcut, Object.new, "Alice")
assert(
  refreshed_shortcut.message == "58 seconds remaining.",
  "an announcement shortcut reused the value frozen when the form opened"
)

shortcut_form = Form.new([])
screen.define_singleton_method(:getkeychar) { "" }
shortcut_field = Object.new
shortcut_field.define_singleton_method(:game_shortcut_keys=) { |_keys| nil }
shortcut_field.define_singleton_method(:add_tip) { |_tip| nil }
activated_shortcuts = []
screen.send(:bind_game_shortcuts, shortcut_form, [shortcut_field], [initial_shortcut]) do |shortcut|
  activated_shortcuts << shortcut
end
shortcut_form.trigger(:key_t, [false, false, false])
assert(activated_shortcuts.empty?, "an ordinary T activated the Ctrl+T announcement")
shortcut_form.trigger(:key_t, [false, true, false])
assert(activated_shortcuts == [initial_shortcut], "Ctrl+T was not handled after the form passed the key through")

plain_c_shortcut = GameRoomGames::GameShortcut.new(
  key: "c",
  label: "read cards",
  kind: :announcement,
  message: "cards"
)
control_c_shortcut = GameRoomGames::GameShortcut.new(
  key: "c",
  modifiers: [:control],
  label: "browse cards",
  kind: :browse,
  prompt: "Cards on the table",
  choices: [GameRoomGames::ShortcutChoice.new(value: "AS", label: "Alice: ace of spades")]
)
activated_shortcuts.clear
screen.send(:bind_game_shortcuts, shortcut_form, [shortcut_field], [plain_c_shortcut, control_c_shortcut]) do |shortcut|
  activated_shortcuts << shortcut
end
shortcut_form.trigger(:key_c, [false, false, false])
shortcut_form.trigger(:key_c, [false, true, false])
assert(
  activated_shortcuts == [plain_c_shortcut, control_c_shortcut],
  "plain C and Ctrl+C were not distinguished by the shared shortcut handler"
)

history_form = GameRoomUI::Form.new([])
history_signatures = nil
history_form.define_singleton_method(:history_navigation_signatures=) { |value| history_signatures = value }
history_actions = []
screen.send(:bind_history_navigation, history_form) { |operation, value| history_actions << [operation, value] }
history_form.trigger(:key_comma, [false, true, false])
history_form.trigger(:key_period, [true, true, false])
history_form.trigger(:key_home, [false, true, false])
assert(
  history_actions == [[:move, -1], [:category, 1], [:jump, :first]],
  "shared history navigation mapped punctuation/Home modifiers incorrectly"
)
assert(history_signatures.include?(['end', [:control]]) && history_signatures.include?(['>', [:control, :shift]]), "missing history key/shifted alias")
assert(history_form.instance_variable_get(:@handlers).keys.none? { |key| [:key_left, :key_right].include?(key) }, "history still intercepts text arrows")
assert(history_form.game_room_general_help_tips.length == 6, "history help needs one shortcut per line")

surface_calls = []
surface = Object.new
surface.define_singleton_method(:handle_command) do |command, payload|
  surface_calls << [command, payload]
  true
end
surface_shortcut = GameRoomGames::GameShortcut.new(
  key: "v",
  label: "read available moves",
  kind: :surface,
  action_kind: "surface",
  action_name: "announce_moves",
  payload: { "scope" => "current" }
)
assert(
  screen.send(:activate_game_shortcut, surface_shortcut, surface) == :surface_handled,
  "a surface shortcut was not handled locally"
)
assert(surface_calls == [["announce_moves", { "scope" => "current" }]], "a surface shortcut sent the wrong command")

history_entry = lambda do |event_id, text, kind|
  GameRoomGames::HistoryEntry.new(
    key: "#{kind}:#{event_id}:#{text}",
    text: text,
    event_id: event_id,
    actor: "",
    kind: kind
  )
end
history_replay = Struct.new(:history).new([
  history_entry.call(1, "first card", :play),
  history_entry.call(3, "second card", :play),
  history_entry.call(4, "third card", :play),
  history_entry.call(4, "round result", :result)
])
screen.send(:event_presenter).instance_variable_set(:@turn_history_entries, {
  2 => history_entry.call(2, "next turn after a silent draw", :turn),
  4 => history_entry.call(4, "next turn after the round result", :turn),
  5 => history_entry.call(5, "final silent transition", :turn)
})
screen.send(:merge_turn_history!, history_replay)
assert(
  history_replay.history.map(&:text) == [
    "first card",
    "next turn after a silent draw",
    "second card",
    "third card",
    "round result",
    "next turn after the round result",
    "final silent transition"
  ],
  "turn announcements were not merged into history by event order"
)

presentation_game = Object.new
presentation_game.define_singleton_method(:history_entries_for_display) do |replay, _viewer, surface_state:|
  replay.history.map do |entry|
    displayed = entry.dup
    displayed.text = "#{entry.text}:#{surface_state['coordinate_label_set']}"
    displayed
  end
end
screen.instance_variable_set(:@game, presentation_game)
screen.instance_variable_set(:@surface_state, { "coordinate_label_set" => "algebraic" })
screen.instance_variable_set(:@activity_repository, nil)
assert(
  screen.send(:combined_history_items, history_replay).first == "first card:algebraic",
  "the game screen did not apply a client's local history-presentation filter"
)
history_layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new)
screen.instance_variable_set(:@layout, history_layout)
history_control = history_layout.history
screen.instance_variable_set(:@history_follows_tail, true)
screen.send(:refresh_history_control, history_control, history_replay)
assert(history_control.items.last == "final silent transition:algebraic", "the visible history was not updated after a local presentation change")
assert(history_control.entry_index == history_control.items.length - 1, "refreshing local history lost its tail position")

module EltenAPI
  module Tasks
    class << self
      attr_accessor :game_screen_test_options

      def run(**options)
        self.game_screen_test_options = options
        token = options[:cancellation_token] || Object.new
        token.define_singleton_method(:raise_if_cancelled!) { nil } if !token.respond_to?(:raise_if_cancelled!)
        progress = Object.new
        progress.define_singleton_method(:update) { |_message| nil }
        yield(progress, token)
      end
    end
  end
end

screen.instance_variable_set(:@repository, Object.new)
network_result = screen.send(:network_task, "Sending assessment") { :sent }
network_options = EltenAPI::Tasks.game_screen_test_options
assert(!network_options.key?(:ui), "an inline assessment retained its callback-only UI override")
assert(network_options[:cancellable] == true, "an inline assessment lost network cancellation")
assert(network_result == :sent, "an inline assessment changed the network result")

synchronizer = Object.new
synchronizer.define_singleton_method(:waiting?) { false }
synchronizer.define_singleton_method(:recovery_pending?) { false }
synchronizations = 0
synchronizer.define_singleton_method(:synchronize) do |**_options, &operation|
  synchronizations += 1
  operation.call
end
screen.instance_variable_set(:@synchronizer, synchronizer)
chat_control = Object.new
screen.instance_variable_set(:@chat_control, chat_control)
screen.instance_variable_set(:@focus_location, [:chat, 0])
synchronized_result = screen.send(
  :synchronized_network_task,
  "Updating game",
  ui: screen.send(:refresh_input_ui)
) { :updated }
synchronized_options = EltenAPI::Tasks.game_screen_test_options
assert(synchronizations == 1, "a maintenance read bypassed the shared synchronizer")
assert(synchronized_options[:ui].equal?(chat_control), "a maintenance read stopped servicing the active chat field")
assert(synchronized_result == :updated, "a synchronized maintenance read changed its result")
screen.instance_variable_set(:@focus_location, [:game, 0])
screen.send(:synchronized_network_task, "Updating game") { :updated }
assert(EltenAPI::Tasks.game_screen_test_options[:ui] == :none, "a maintenance read kept an inactive chat field open")
screen.instance_variable_set(:@chat_control, nil)

activity = Struct.new(:id, :created_at).new(8, 100)
activity_repository = Object.new
activity_repository.define_singleton_method(:text_for) do |_entry, game_name:, global:|
  raise "incorrect chat presentation context" if global != false || !game_name.respond_to?(:call)

  "Alice: hello"
end
sent_chat = nil
screen.instance_variable_set(:@table, { "__id" => 7 })
screen.instance_variable_set(:@room_snapshot, Struct.new(:members).new(["Alice", "Bob"]))
screen.instance_variable_set(:@activity_entries, [])
screen.instance_variable_set(:@activity_repository, activity_repository)
screen.instance_variable_set(:@game_name, ->(id) { id.to_s })
screen.instance_variable_set(:@chat_text, "hello")
screen.instance_variable_set(:@chat_index, 5)
screen.instance_variable_set(:@chat_check, 2)
screen.instance_variable_set(:@session, { '__id' => 42 })
screen.instance_variable_set(:@game_services, {})
screen.instance_variable_get(:@repository).define_singleton_method(:session_id) { |session| session.fetch('__id') }
screen.instance_variable_set(:@chat_sends, GameRoomUI::ChatSendBuffer.new)
history_layout.session_id = 42
history_layout.chat.set_text('hello')
screen.instance_variable_set(:@chat_control, history_layout.chat)
screen.send(:queue_chat_submission, history_layout.chat, 'hello', session_id: 42)
screen.instance_variable_set(:@send_chat, lambda do |table, message, users, **options|
  assert(options[:expected_session_id] == 42 && !options[:message_id].to_s.empty?, 'chat identity was lost')
  sent_chat = [table, message, users]
  activity
end)
screen.send(:submit_chat)
assert(sent_chat[1] == "hello" && sent_chat[2] == ["Alice", "Bob"], "chat was not sent to the table members")
assert(screen.instance_variable_get(:@chat_text).empty?, "a sent chat draft was not cleared")
assert(screen.instance_variable_get(:@chat_index) == 0 && screen.instance_variable_get(:@chat_check) == 0, "a sent chat message retained its old selection")
assert(screen.instance_variable_get(:@activity_entries) == [activity], "the sent chat was not added to local history")
assert($spoken_messages.last == "Alice: hello", "the sender's own chat message was not spoken")

speech_stopped = false
screen.define_singleton_method(:speech_stop) { speech_stopped = true }
screen.send(:stop_pending_speech)
assert(speech_stopped, "leaving a game did not stop queued history speech")

assert(
  screen.send(:recovery_allowed?, false),
  "an idle human turn disabled connection recovery"
)
assert(
  !screen.send(:recovery_allowed?, true),
  "an automatic action did not postpone connection recovery"
)
screen.instance_variable_set(:@new_session_id, 99)
assert(screen.send(:recovery_allowed?, true), "a new match cannot recover its connection")

puts "Game screen network policy tests passed"
