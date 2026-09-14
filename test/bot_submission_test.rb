def _(text)
  text
end

module Session
  def self.name = "Alice"
end

module Log
  def self.debug(_message); end
  def self.warning(_message); end
end

require_relative "../games/base"
require_relative "../lib/bot_turn_gate"
require_relative "../lib/game_repository"
require_relative "../lib/game_screen"

def assert(condition, message)
  raise message if !condition
end

bot = "bot:7:1"
session = { "id" => 11, "table_id" => 7, "__players" => ["Alice", bot] }
replay = Struct.new(:accepted_events).new([{ "id" => 20, "actor" => "Alice" }])
command = GameRoomGames::EventCommand.new(action: "play", value: "05C|normal")
plan = GameRoomGames::ActionPlan.new(events: [command])
decision = GameRoomBots::Decision.new(
  actor: bot,
  action: { "kind" => "card", "action" => "select", "card" => "05C|normal" },
  available_actions: []
)

game = Object.new
chosen_actor = nil
game.define_singleton_method(:id) { "ninety_nine" }
game.define_singleton_method(:action_for) do |_selection, _replay, actor, context:|
  chosen_actor = actor
  [:ok, plan]
end

repository = Object.new
append_arguments = nil
repository.define_singleton_method(:session_id) { |_session| 11 }
repository.define_singleton_method(:next_sequence) { |_session, _events| 21 }
repository.define_singleton_method(:append_events) do |**arguments|
  append_arguments = arguments
  [{ "__id" => 31, "actor" => arguments[:actor], "action" => "play" }]
end
repository.define_singleton_method(:event_id) { |event| event["__id"].to_i }

screen = GameScreen.allocate
screen.instance_variable_set(:@repository, repository)
screen.instance_variable_set(:@game, game)
screen.instance_variable_set(:@session, session)
screen.instance_variable_set(:@table, { "__id" => 7 })
screen.instance_variable_set(:@table_owner, "Alice")
screen.instance_variable_set(:@pending_event_ids, [])
screen.define_singleton_method(:action_context) { :test_context }
screen.define_singleton_method(:game_recipients) { ["Alice"] }

controller = GameRoomBots::TurnController.new
screen.instance_variable_set(:@bot_turn_controller, controller)
lease = controller.acquire(session_id: 11, actor: bot, revision: [1, 20])
form = Object.new
network_options = nil
screen.define_singleton_method(:network_task) do |_title, **options, &operation|
  network_options = options
  operation.call
end

assert(
  screen.send(:perform_bot_turn, replay, decision, lease: lease, form: form),
  "a valid computer action was not submitted"
)
assert(chosen_actor == bot, "the game validated the computer move as the human player")
assert(append_arguments[:actor] == bot, "the repository saved the computer move as the human player")
assert(append_arguments[:sequence] == 21, "the computer move bypassed normal sequence allocation")
assert(append_arguments[:events] == [command], "the computer move changed the validated action plan")
assert(append_arguments[:recipients] == ["Alice"], "the computer move changed normal recipients")
assert(network_options[:ui].equal?(form), "the computer write did not retain the active game form")
assert(network_options[:silent] == true, "a computer transport error would be announced as a human failure")
assert(screen.instance_variable_get(:@pending_event_ids) == [31], "the computer move did not use normal pending-event tracking")
assert(controller.waiting_for_confirmation?, "the next computer could start before server confirmation")
assert(
  controller.observe(
    session_id: 11,
    events: [{ "__id" => 31, "actor" => bot, "action" => "play", "value" => "05C|normal" }],
    confirmed_event_ids: [31],
    verified: true
  ) == :confirmed,
  "the submitted computer move was not released after confirmation"
)

append_arguments = nil
screen.instance_variable_set(:@pending_event_ids, [])
lease = controller.acquire(session_id: 11, actor: bot, revision: [2, 31])
screen.define_singleton_method(:network_task) { |_title, **_options, &_operation| nil }
assert(
  !screen.send(:perform_bot_turn, replay, decision, lease: lease, form: form),
  "an uncertain computer write was reported as successful"
)
assert(append_arguments == nil, "the test transport unexpectedly submitted an uncertain action")
assert(screen.instance_variable_get(:@pending_event_ids).empty?, "an uncertain computer write created a false pending event")
assert(controller.waiting_for_confirmation?, "an uncertain write released the computer immediately")
assert(
  controller.observe(
    session_id: 11,
    events: [],
    confirmed_event_ids: [],
    verified: true
  ) == :not_saved,
  "a verified missing computer write was not released for a fresh decision"
)
assert(controller.ready?(session_id: 11, actor: bot), "a missing write permanently blocked the computer")

puts "Computer submission tests passed: normal path, confirmation and uncertain writes"
