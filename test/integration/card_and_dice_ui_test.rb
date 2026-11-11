require_relative "../support/ui"
require_relative "../../lib/game_surfaces"
require_relative "../../games/yahtzee"
require_relative "../../games/monopoly"
require_relative "../../games/poker"
require_relative "../../games/uno"
require_relative "../../lib/game_screen"

def assert(value, message)
  raise message unless value
end

uno = GameRoomGames::Uno.new
uno_state = uno.send(:initial_state, %w[Alice Bob], uno.default_options)
uno_state.update(phase: :playing, current_player: "Alice", colour: "R", discard: ["R5a"],
  hands: { "Alice" => %w[B3a R1a G2a R2a Y1a], "Bob" => ["G5a"] })
uno_view = GameRoomGames::Replay.new(players: uno_state[:players], current_player: "Alice",
  history: [], accepted_events: [], state: uno_state)
uno_spec = uno.surface_spec(uno_view, "Alice")
uno_surface = GameSurfaces::CardTable.new(uno_spec)
uno_surface.fields.first.index = 2
focused_label = uno_surface.fields.first.options[2]
shortcuts = uno.custom_game_shortcuts(uno_view, "Alice")
%w[c h].zip(%w[colour number], %w[color number]).each do |key, mode, spoken_mode|
  shortcut = shortcuts.find { |item| item.key == key && item.modifiers == [:shift] }
  assert(shortcut != nil, "UNO Shift+#{key} is not bound")
  3.times do |press|
    $spoken_messages.clear
    assert(uno_surface.handle_command("sort_cards", shortcut.payload), "UNO sort refused")
    expected = uno_spec.zones.first.cards.sort_by { |card| card.sort_keys[mode] }.map(&:label)
    direction = press.odd? ? "descending" : "ascending"
    expected.reverse! if press.odd?
    assert(uno_surface.fields.first.options == expected, "UNO #{mode} #{direction} order is wrong")
    assert($spoken_messages == ["Your cards are now sorted by #{direction} #{spoken_mode}."], "UNO sort announcement is not concise")
    assert(uno_surface.fields.first.options[uno_surface.fields.first.index] == focused_label, "Sorting moved to another card")
    uno_surface = GameSurfaces::CardTable.new(uno_spec, state: uno_surface.state)
    assert(uno_surface.fields.first.options == expected, "Sorting direction lost on refresh")
  end
end
reset_sort = shortcuts.find { |item| item.key == "d" && item.modifiers == [:shift] }
uno_surface.handle_command("sort_cards", reset_sort.payload)
assert(uno_surface.fields.first.options == uno_state[:hands]["Alice"].map { |card| uno.send(:uno_label, card, uno_state) }, "Shift+D did not restore deal order")
assert(shortcuts.any? { |item| item.key == "c" && item.kind == :announcement && item.modifiers.to_a.empty? }, "Normal C was replaced by sort")
card_counts = shortcuts.find { |item| item.key == "e" && item.kind == :announcement && item.modifiers.to_a.empty? }
assert(card_counts && card_counts.message == "Alice, 5. Bob, 1.", "UNO E does not read concise card counts")

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

# The example supplied by the user: select and keep one matching die at a time.
example = yahtzee_spec.dup
example.dice = [2, 3, 4, 4, 4].each_with_index.map { |value, index| GameSurfaces::Die.new(id: "d#{index}", value: value) }
example_surface = GameSurfaces::RollAndScoreSurface.new(example)
expected = [
  "You keep 3 4 4 4 and reroll 2.",
  "You keep 4 4 4 and reroll 2 3.",
  "You keep 4 4 and reroll 2 3 4.",
  "You keep 4 and reroll 2 3 4 4.",
  "You keep no dice and reroll 2 3 4 4 4.",
  "You keep 2 and reroll 3 4 4 4.",
  "You keep 2 3 and reroll 4 4 4.",
  "You keep 2 3 4 and reroll 4 4.",
  "You keep 2 3 4 4 and reroll 4.",
  "You keep 2 3 4 4 4 and reroll no dice."
]
[2, 3, 4, 4, 4].each_with_index do |value, index|
  example_surface.handle_command("select_die", "value" => value)
  assert($spoken_messages.last == expected[index], "wrong selection summary #{index}")
end
[2, 3, 4, 4, 4].each_with_index do |value, index|
  example_surface.handle_command("unselect_die", "value" => value)
  assert($spoken_messages.last == expected[index + 5], "wrong keep summary #{index}")
end
before = example_surface.state
example_surface.handle_command("announce_dice")
assert(example_surface.state == before && $spoken_messages.last == expected.last, "Space modified selection")

# Exercise the real form handler with the same controls as table options.
class Form
  class << self
    attr_accessor :on_wait
  end
  alias five_games_original_wait wait
  def wait
    # The application now creates a GameRoomUI::Form subclass. The test driver
    # belongs to Form, not to the subclass's separate class-instance variables.
    Form.on_wait ? Form.on_wait.call(self) : five_games_original_wait
  end
  def resume; end
end
class EditBox
  module Flags
    Numbers = 4
  end
  def select_all
    @index, @check = 0, text.length
  end
end
class CheckBox < FakeControl
  attr_accessor :checked
  def initialize(label, checked: false)
    super()
    @header = label
    @checked = checked
  end
end unless defined?(CheckBox)
game = GameRoomGames::Monopoly.new
state = game.send(:initial_state, %w[Alice Bob Carol], game.default_options)
state[:owners].merge!(1 => "Alice", 3 => "Bob", 6 => "Carol")
replay = GameRoomGames::Replay.new(players: state[:players], current_player: "Alice", history: [], accepted_events: [], state: state)
trade = game.custom_game_shortcuts(replay, "Alice").find { |shortcut| shortcut.key == "e" }
assert(trade.kind == :staged_form, "Trade does not begin with a player list")
trade_form = game.staged_form_shortcut(trade, replay, "Alice", { "target" => 1 })
assert(trade_form.kind == :form && trade_form.payload["target"] == 1, "Trade player selection did not open the offer form")
assert(trade_form.fields.count { |field| field.kind == :multiple_choice } == 2, "Trade properties are not grouped into two arrow lists")
screen = GameScreen.allocate
screen.instance_variable_set(:@game, game)
Form.on_wait = lambda do |form|
  own_properties = form.fields[2]
  requested_properties = form.fields[3]
  own_properties.select_multiselection_indices([0])
  requested_properties.select_multiselection_indices([0])
  form.accept_button.trigger(:press)
end
action = screen.send(:form_shortcut_action, trade_form)
assert(action.payload["target"] == 1 && action.payload["give_properties"] == [1] && action.payload["receive_properties"] == [3], "Wrong trade payload")
Form.on_wait = ->(form) { form.cancel_button.trigger(:press) }
assert(screen.send(:form_shortcut_action, trade_form) == nil, "Cancel sent a proposal")
Form.on_wait = nil

# Exercise the full two-stage flow: Escape from the offer returns to the player
# list, while selecting a player emits only the small preparation action.
module Session
  def self.name = "Alice"
end
prepared_targets = []
screen.define_singleton_method(:submit_inline_action) do |current_replay, selection, title:|
  assert(title == "Preparing trade", "trade preparation used the wrong task title")
  prepared_targets << selection.payload["target"]
  [current_replay, [Object.new]]
end
wait_step = 0
Form.on_wait = lambda do |form|
  case wait_step
  when 0
    form.fields.first.index = 1 # Carol
    form.accept_button.trigger(:press)
  when 1
    form.cancel_button.trigger(:press) # Back to the player list
  when 2
    form.fields.first.index = 0 # Bob
    form.accept_button.trigger(:press)
  when 3
    form.fields[2].select_multiselection_indices([0])
    form.accept_button.trigger(:press)
  end
  wait_step += 1
end
action = screen.send(:staged_form_shortcut_action, trade, replay)
assert(prepared_targets == [2, 1], "Escape did not return from the offer to the player list")
assert(action.name == "trade_offer" && action.payload["target"] == 1 && action.payload["give_properties"] == [1],
  "the staged trade returned the wrong final proposal")
Form.on_wait = nil

# Both variants use the real numeric-input handler, not a preset list.
%w[holdem draw].each do |variant|
  poker = GameRoomGames::Poker.new
  state = poker.send(:initial_state, %w[Alice Bob], poker.normalize_options("variant" => variant))
  state.update(phase: :betting, current_player: "Alice", current_bet: 20, min_raise: 10,
    street_bets: { "Alice" => 0, "Bob" => 20 }, contributions: { "Alice" => 0, "Bob" => 20 })
  replay = GameRoomGames::Replay.new(players: state[:players], state: state)
  shortcut = poker.custom_game_shortcuts(replay, "Alice").find { |entry| entry.key == "r" }
  assert(shortcut.kind == :number_input && shortcut.value_key == "raise_by", "#{variant}: R is not custom numeric input")
  answers = ["9", "37"]
  errors = []
  prompts = []
  screen.define_singleton_method(:number_shortcut_input) do |prompt, **options|
    assert(options[:select_all], "Missing selected default")
    prompts << prompt
    answers.shift
  end
  screen.define_singleton_method(:alert) { |message| errors << message }
  action = screen.send(:number_shortcut_action, shortcut)
  assert(action.payload == { "quoted_call" => 20, "raise_by" => 37 } && errors.empty?, "Wrong numeric input validation")
  assert(prompts.first == "Raise by:" && prompts.last.start_with?("This value is not allowed. Allowed values:") &&
    prompts.last.end_with?("Raise by:"), "Invalid raise was not explained with the reopened field")
  screen.define_singleton_method(:number_shortcut_input) { |_prompt, **_options| nil }
  assert(screen.send(:number_shortcut_action, shortcut) == nil, "Escape submitted a raise")
end
puts "Five-game UI tests passed"
