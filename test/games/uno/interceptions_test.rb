require_relative "../../support/ui"
require_relative "../../support/log"

class Program
  def self.server_app(**_options); end
end
module Session
  def self.name; "Alice"; end
end
class FormTimer
  def initialize(*_args, **_options, &_callback); end
end
class Form
  class << self; attr_accessor :driver; end
  def wait; Form.driver.call(self); end
  def resume; end
end
module EltenAPI
  module Tasks
    class Cancelled < StandardError; end
    class CancellationToken
      def cancel; @cancelled = true; end
      def cancelled?; @cancelled == true; end
    end
  end
end
require_relative "../../../__app"

def assert(value, message)
  raise message unless value
end

class InterceptionRepository
  attr_reader :players
  def initialize(players); @players = players; end
  def players_for(_session); players; end
  def session_id(session); session["__id"]; end
  def actor_of(event, _session = nil); event["actor"]; end
  def event_id(event); event["id"]; end
end

def position(game, opponent = "Bob", **options)
  players = ["Alice", opponent]
  game.send(:initial_state, players, game.normalize_options({ "interceptions" => true, "bot_delay" => 5 }.merge(options))).merge(
    phase: :playing, round: 1, current_player: opponent, discard: ["R50"], colour: "R",
    turn_deadline: 0, hands: { "Alice" => %w[R51 G30 NW0], opponent => %w[R60 B20] })
end

def replay_of(state)
  GameRoomGames::Replay.new(players: state[:players], current_player: state[:current_player],
    winner: state[:winner], draw: false, state: state, accepted_events: [], history: [])
end

def select_card(card)
  { "kind" => "card", "action" => "select", "card_id" => card, "card" => card }
end

def plan_for(game, state, card, actor = "Alice")
  game.action_for(select_card(card), replay_of(state), actor, context: GameRoomGames::ActionContext.new(now: 100))
end

def play_event(game, state, card, actor = "Alice", id = 1)
  event = { "id" => id, "actor" => actor, "action" => "play", "value" => "#{card}||0" }
  history = []
  applied = game.send(:apply_play, state, event, actor, InterceptionRepository.new(state[:players]), history)
  [applied, history, event]
end

def drive_screen(game, state, card: "R51", key: nil)
  repo = InterceptionRepository.new(state[:players])
  table = { "__id" => 7, "owner" => "Alice", "game" => game.id, "name" => "Probe", "status" => "playing", "max_players" => 8 }
  room = LobbyRepository::TableSnapshot.new(table: table, members: state[:players], bots: [])
  screen = GameScreen.new(program: Object.new, repository: repo, game: game,
    session: { "__id" => 1, "options" => JSON.generate(state[:options]) },
    table: table, table_owner: "Alice", room_snapshot_provider: -> { room }, synchronizer: nil)
  screen.instance_variable_set(:@room_snapshot, room)
  screen.define_singleton_method(:getkeychar) { "" }
  Form.driver = lambda do |form|
    layout = screen.instance_variable_get(:@layout)
    if key
      form.trigger("key_#{key}".to_sym, [])
    else
      cards = layout.surface.instance_variable_get(:@cards).fetch("hand")
      index = cards.index { |item| item.id == card }
      layout.surface.fields.first.trigger(:select, [index])
    end
    # A blocked selection ends the probe without hanging the test runner.
    layout.back_button.trigger(:press) if screen.instance_variable_get(:@selected_surface_action) == nil
  end
  result = screen.send(:wait_for_action, replay_of(state), [0, 0])
  [result, screen.instance_variable_get(:@selected_surface_action)]
end

failures = []
check = lambda do |name, &probe|
  probe.call
  puts "PASS #{name}"
rescue StandardError => error
  failures << "#{name}: #{error.message} (#{error.backtrace.first})"
  puts "FAIL #{failures.last}"
end
uno = GameRoomGames::Uno.new

check.call("human and bot turns accept legal interceptions and penalize nonmatches") do
  ["Bob", "bot:7:1"].each do |opponent|
    state = position(uno, opponent)
    assert(plan_for(uno, state, "R51").first == :ok, "Matching interception rejected")
    assert(play_event(uno, state, "R51").first, "Matching play rejected by replay")
    assert(state[:current_player] == "Alice" && state[:scores]["Alice"] == 0, "Interception did not take over cleanly")
    state = position(uno, opponent)
    before = Marshal.load(Marshal.dump(state))
    assert(plan_for(uno, state, "G30").first == :ok, "Too-late attempt never reaches the shared event stream")
    applied, history, event = play_event(uno, state, "G30")
    assert(applied && state[:scores]["Alice"] == 3, "Wrong penalty")
    assert(state.reject { |key, _| key == :scores } == before.reject { |key, _| key == :scores }, "Penalty changed cards, turn or timer")
    assert(history.one? && history.first.text.include?("Too late") && history.first.value == 3, "Missing penalty announcement/history")
    sound = GameRoomSounds.event_cue(game: uno, event: event, before_replay: replay_of(before), after_replay: replay_of(state).tap { |r| r.history = history }, repository: InterceptionRepository.new(state[:players]), viewer: "Alice")
    assert(sound != "play" && sound != "reverse", "Penalty sounds like a played card")
  end
end

check.call("own turn, disabled option, observers, eliminated players and buzzer are not penalized") do
  [:own, :disabled, :observer, :eliminated, :round_eliminated, :buzzer, :finished].each do |scenario|
    state = position(uno)
    state[:current_player] = "Alice" if scenario == :own
    state[:options]["interceptions"] = false if scenario == :disabled
    state[:eliminated]["Alice"] = true if scenario == :eliminated
    state[:round_eliminated]["Alice"] = true if scenario == :round_eliminated
    state[:buzzer_active] = true if scenario == :buzzer
    state[:phase] = :round_complete if scenario == :finished
    actor = scenario == :observer ? "Observer" : "Alice"
    assert(plan_for(uno, state, "G30", actor).first != :ok, "Invalid #{scenario} attempt was planned")
    assert(!play_event(uno, state, "G30", actor).first && state[:scores].values.sum.zero?, "Invalid #{scenario} attempt was scored")
  end
  assert(plan_for(uno, position(uno), "Y99").first != :ok, "A card not in the hand was penalized")
end

check.call("super interception uses face only; wild nonmatch has no colour picker") do
  state = position(uno, "Bob", "super_interceptions" => true)
  state[:hands]["Alice"] << "G51"
  assert(play_event(uno, state, "G51").first && state[:scores]["Alice"].zero?, "Super interception charged a penalty")
  state = position(uno)
  wild = uno.surface_spec(replay_of(state), "Alice").zones.first.cards.find { |card| card.id == "NW0" }
  assert(wild.choices.to_a.empty?, "An impossible wild interception opens a colour picker")
  assert(play_event(uno, state, "NW0").first && state[:scores]["Alice"] == 3, "Wild attempt missing penalty")
end

check.call("all readers replay the same penalty once without disclosing the attempted card") do
  players = %w[Alice Bob Carol]
  repo = InterceptionRepository.new(players)
  session = { "__id" => 1, "options" => JSON.generate(uno.default_options.merge("interceptions" => true)) }
  events = [{ "id" => 1, "actor" => "Alice", "action" => "deal", "value" => "1|0|0123456789abcdef0123456789abcdef|0" }]
  before = uno.replay(session, events, repo)
  actor = players.find { |player| player != before.current_player }
  card = before.state[:hands][actor].find { |item| !uno.send(:interceptable?, before.state, item) }
  status, plan = uno.action_for(select_card(card), before, actor, context: GameRoomGames::ActionContext.new(now: 100))
  assert(status == :ok && plan.events.one?, "Expected one attempted-play event")
  command = plan.events.first
  events << { "id" => 2, "actor" => actor, "action" => command.action, "value" => command.value }
  copies = players.map { uno.replay(session, events, InterceptionRepository.new(players)) }
  assert(copies.all? { |copy| copy.accepted_events.size == 2 && copy.state[:scores][actor] == 3 }, "Penalty was lost or applied twice")
  assert(copies.map(&:state).uniq.length == 1, "Readers disagree")
  assert(copies.first.history.last.text == "Too late!", "Penalty discloses card or has wrong text")
end

check.call("Enter works during human and bot turns") do
  # Cancellation while the strategy is running belongs to the real shared
  # worker, covered by game_session_runner_input_test, not a second UI worker.
  ["Bob", "bot:7:1"].each do |opponent|
    ["R51", "G30", "NW0"].each do |card|
      result, action = drive_screen(uno, position(uno, opponent), card: card)
      assert(result == :game_action && action["card_id"] == card, "#{opponent}'s turn swallowed #{card}")
    end
  end
  result, action, = drive_screen(uno, position(uno), card: "R51")
  assert(result == :game_action && action["card_id"] == "R51", "Human-opponent turn swallowed Enter")
end

check.call("UNO action shortcuts work during a bot turn") do
  state = position(uno, "bot:7:1")
  state[:hands]["Alice"] = ["R51"]
  result, action, = drive_screen(uno, state, key: "u")
  assert(result == :game_action && action["action"] == "uno", "Bot blocked U")
  state[:buzzer_active] = true
  result, action, = drive_screen(uno, state, key: "b")
  assert(result == :game_action && action["action"] == "buzz", "Bot blocked buzzer")
end

check.call("event ordering decides an interception, including a now-too-late card") do
  state = position(uno)
  state[:players] << "Carol"
  state[:hands]["Carol"] = %w[Y10 B10]
  state[:scores]["Carol"] = 0
  assert(plan_for(uno, state, "R51").first == :ok, "Interception not planned")
  # Bob's move reaches the shared stack first. Alice's matching five has
  # become too late, and is resolved against the six, not the old snapshot.
  assert(play_event(uno, state, "R60", "Bob", 1).first, "Bob's play failed")
  assert(state[:current_player] == "Carol", "Unexpected next turn")
  assert(play_event(uno, state, "R51", "Alice", 2).first, "Late play lost instead of scored")
  assert(state[:scores]["Alice"] == 3 && state[:hands]["Alice"].include?("R51"), "Wrong resolution after racing plays")
  assert(state[:discard].last == "R60" && state[:current_player] == "Carol", "Late attempt changed the table")

  state = position(uno)
  assert(play_event(uno, state, "R51", "Alice", 1).first, "First interception failed")
  assert(state[:scores]["Alice"].zero? && state[:current_player] == "Alice", "First event was penalized")
  # With two players, if Bob has already moved it is now Alice's ordinary
  # turn. A card matching the colour is a normal play, not a late penalty.
  state = position(uno)
  play_event(uno, state, "R60", "Bob", 1)
  assert(play_event(uno, state, "R51", "Alice", 2).first && state[:scores]["Alice"].zero?, "Own turn was mistaken for an interception")
end

check.call("a penalty does not restart the bot delay or alter confirmation revision") do
  clock = 100.0
  gate = GameRoomBots::TurnController.new(clock: -> { clock })
  state = position(uno, "bot:7:1")
  snapshot = replay_of(state)
  snapshot.accepted_events = [{ "id" => 1 }]
  gate.schedule_decision(session_id: 1, actor: "bot:7:1", revision: uno.bot_delay_revision(snapshot, [1, 1]), delay: 5)
  clock = 104.0
  _, history, event = play_event(uno, state, "G30", "Alice", 2)
  snapshot.history = history
  snapshot.accepted_events << event
  assert(uno.bot_delay_revision(snapshot, [2, 2]) == [1, 1], "Penalty restarted waiting")
  gate.schedule_decision(session_id: 1, actor: "bot:7:1", revision: uno.bot_delay_revision(snapshot, [2, 2]), delay: 5)
  assert(!gate.ready?(session_id: 1, actor: "bot:7:1"), "Bot skipped its original delay")
  clock = 105.0
  lease = gate.acquire(session_id: 1, actor: "bot:7:1", revision: [2, 2])
  assert(lease != nil, "Bot was postponed by a penalty")
  assert(gate.instance_variable_get(:@attempt).revision == [2, 2], "Confirmation revision was weakened")
  snapshot.accepted_events << { "__id" => 3 }
  assert(uno.bot_delay_revision(snapshot, [3, 3]) == [2, 3], "A genuine move failed to start a new waiting period")
end

check.call("games with out-of-turn actions opt in; the five-second gate remains nonblocking") do
  EltenGameRoom::GAME_REGISTRY.ids.each do |id|
    game = EltenGameRoom::GAME_REGISTRY.build(id)
    # Taboo also accepts the moderator's out-of-turn buzzer; it has no bots.
    assert(game.actions_during_bot_turn? == ["uno", "makao", "taboo", "mille_bornes"].include?(id), "Unexpected exception for #{id}")
    assert(game.bot_delay_revision(replay_of(position(uno)), [12, 20]) == [12, 20], "Pacing changed for #{id}") unless %w[uno rummy domino mexican_train].include?(id)
  end
  clock = 100.0
  gate = GameRoomBots::TurnController.new(clock: -> { clock })
  gate.schedule_decision(session_id: 1, actor: "bot:7:1", revision: [0, 0], delay: 5)
  assert(!gate.ready?(session_id: 1, actor: "bot:7:1"), "Bot did not wait")
  clock = 104.9
  assert(!gate.ready?(session_id: 1, actor: "bot:7:1"), "Bot moved early")
  clock = 105.0
  assert(gate.ready?(session_id: 1, actor: "bot:7:1"), "Bot waited too long")
end

abort failures.join("\n") unless failures.empty?
puts "UNO interception rules, shared UI and bot-wait regressions passed"
