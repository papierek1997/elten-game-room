def _(text)
  text
end

require_relative "../../games/base"
require_relative "../../games/four_in_a_row"
require_relative "../../games/tic_tac_toe"
require_relative "../../games/spades"
require_relative "../../games/farkle"
require_relative "../../games/ninety_nine"
require_relative "../../games/tysiac"
require_relative "../../games/categories"
require_relative "../../games/checkers"
require_relative "../../games/chess"
require_relative "../../games/reversi"
require_relative "../../games/ludo"
require_relative "../../games/monopoly"
require_relative "../../games/yahtzee"
require_relative "../../games/uno"
require_relative "../../games/makao"
require_relative "../../games/poker"
require_relative "../../games/registry"

def assert(condition, message)
  raise message if !condition
end

game_types = [
  GameRoomGames::FourInARow,
  GameRoomGames::TicTacToe,
  GameRoomGames::Spades,
  GameRoomGames::Farkle,
  GameRoomGames::NinetyNine,
  GameRoomGames::Tysiac,
  GameRoomGames::Categories,
  GameRoomGames::Checkers,
  GameRoomGames::Chess,
  GameRoomGames::Reversi,
  GameRoomGames::Ludo,
  GameRoomGames::Monopoly,
  GameRoomGames::Yahtzee,
  GameRoomGames::Uno,
  GameRoomGames::Makao,
  GameRoomGames::Poker
]

registry = GameRoomGames::Registry.new(game_types)
assert(registry.ids.length == 16, "the rules registry lost a game")

game_types.each do |game_type|
  game = game_type.new
  book = game.rule_book
  ids = book.sections.map(&:id)
  missing = GameRoomRules::REQUIRED_SECTION_IDS - ids
  assert(missing.empty?, "#{game.id} is missing rule sections: #{missing.join(", ")}")
  required_order = ids.select { |id| GameRoomRules::REQUIRED_SECTION_IDS.include?(id) }
  assert(required_order == GameRoomRules::REQUIRED_SECTION_IDS, "#{game.id} has rule sections out of order")
  assert(ids.uniq.length == ids.length, "#{game.id} repeats a rule section")
  assert(book.sections.all? { |section| !section.text.empty? }, "#{game.id} contains empty rules")
  assert(book.sections.all? { |section| !section.title.empty? }, "#{game.id} contains an untitled rule section")
  assert(book.documents.map(&:id) == [:rules, :controls], "#{game.id} library must have exactly two documents")
  rules = book.documents.first
  assert(rules.sections == book.sections.reject { |section| section.id == :controls }, "#{game.id} lost structured rule sections")
  assert(rules.contents_title == _("Contents"), "#{game.id} lost its translated contents heading")
  contents = [rules.contents_title, *rules.sections.map(&:title)].join("\r\n")
  body = rules.sections.map { |section| "#{section.title}\r\n#{section.text}" }
  assert(rules.text == [contents, *body].join("\r\n\r\n"), "#{game.id} lost contents or changed rule text")
  controls = book.sections.find { |section| section.id == :controls }
  assert(book.documents[1].text.include?(controls.text), "#{game.id} lost its game shortcuts")
  assert(book.documents[1].paragraphs == controls.paragraphs, "#{game.id} includes unrelated shared shortcuts")
  assert(book.documents.first.text != book.documents[1].text, "#{game.id} repeats rules instead of shortcuts")
  table = game.rule_book(options: game.default_options)
  assert(table.documents.map(&:id) == [:rules, :controls, :current_options], "#{game.id} table must have settings third")
  assert(table.documents.first.text == book.documents.first.text, "#{game.id} table settings overwrote the full rules")
end

farkle = GameRoomGames::Farkle.new
configured = farkle.rule_book(
  options: {
    "score_limit" => 2_000,
    "turn_minimum" => 40,
    "entry_minimum" => 80
  }
)
assert(configured.sections.first.id == :current_options, "room rules do not begin with current table options")
assert(configured.sections.first.text.include?("2000"), "room rules lost the configured score limit")
assert(farkle.rule_book.sections.none? { |section| section.id == :current_options }, "library rules unexpectedly contain table options")
assert(configured.documents.last.text.include?("40"), "room rules lost turn minimum")
assert(configured.documents.last.text.include?("80"), "room rules lost entry minimum")
replacement = configured.with_current_options("replacement").documents.last
assert(replacement.sections.length == 1 && replacement.sections.first.text == "replacement", "table settings must be replaceable without duplicate sections")
assert(replacement.text == "#{replacement.title}\r\nreplacement", "table settings lost their heading")

def settings(game, values = {})
  game.rule_book(options: values).documents.last.text
end

uno = GameRoomGames::Uno.new
uno_default = settings(uno)
assert(uno_default.include?("Draw responses"), "an enabled UNO option is missing")
assert(uno_default.include?("Classic UNO deck"), "selected deck is missing")
assert(!uno_default.include?("No Mercy card limit"), "other deck's limit leaked into settings")
assert(!uno_default.include?("Interceptions"), "disabled additions must be omitted")
assert(!uno_default.include?("Thinking time"), "disabled timer must be omitted")
assert(!settings(uno, "deck" => "no_mercy", "no_mercy_limit" => 0).include?("No Mercy card limit"), "disabled numeric addition must be omitted")
assert(settings(uno, "thinking_time" => 10).include?("10"), "enabled timer disappeared")
assert(!settings(uno, "draw_responses" => false, "advanced_responses" => true).include?("Advanced responses"), "inactive dependent rule leaked")

poker = GameRoomGames::Poker.new
assert(!settings(poker, "variant" => "holdem", "draw_five" => true).include?("Allow exchanging"), "draw-poker settings leaked into Hold'em")
assert(!settings(poker).include?("Maximum raises"), "disabled raise cap leaked")
draw_settings = settings(poker, "variant" => "draw", "draw_five" => true, "raise_cap_enabled" => true, "raise_cap" => 4)
assert(draw_settings.include?("Allow exchanging all five cards"), "active draw-poker setting missing")
assert(draw_settings.include?("Maximum raises per betting round: 4"), "active raise cap missing")
assert(!draw_settings.include?("Small blind"), "blinds leaked into ante-only draw poker")

checkers = GameRoomGames::Checkers.new
checkers_settings = settings(checkers, "board_size" => 10, "rules" => 3)
assert(checkers_settings.include?("100 fields"), "board size label missing")
assert(checkers_settings.include?("Men may capture backward"), "checked bitmask option missing")
assert(checkers_settings.include?("Kings move and capture over any distance"), "second checked bitmask option missing")
assert(!checkers_settings.include?("Capturing is mandatory"), "unchecked bitmask option leaked")

categories = GameRoomGames::Categories.new
pool = categories.option_definitions.find { |item| item.key == "custom_categories" }
selected = [pool.choices[0].value, pool.choices[2].value]
category_settings = settings(categories, "category_set" => "custom", "custom_categories" => selected, "round_category_count" => 2)
assert(category_settings.include?("#{pool.label}: #{pool.choices[0].label}, #{pool.choices[2].label}"), "category identifiers were not converted to labels")
assert(!settings(categories).include?("#{pool.label}:"), "inactive custom category selection leaked")

spades_settings = settings(GameRoomGames::Spades.new, "team_size" => 2, "team_seats" => [0, 1, 0, 1])
assert(spades_settings.include?("Teams in seating order: 1, 2, 1, 2"), "team numbers are not one-based")

makao = GameRoomGames::Makao.new
custom_switches = %w[jokers mixed_draw_cards stack_fours ace_changes_suit jack_requests_rank queen_universal attacking_kings draw_responses allow_playable_draw]
assert(makao.option_definitions.select { |item| item.kind == :boolean }.map(&:key).sort == custom_switches.sort, "agreed Makao switches changed")
makao.option_definitions.each do |definition|
  assert(makao.option_visible?(definition, { "profile" => "custom" }), "Makao custom profile hides #{definition.key}")
end
custom_switches.each do |key|
  off = custom_switches.to_h { |switch| [switch, false] }.merge("profile" => "custom", key => true)
  normalized = makao.normalize_options(off)
  assert(custom_switches.all? { |switch| normalized[switch] == (switch == key) }, "Makao custom switch #{key} forces other switches")
  expected = makao.option_definitions.find { |item| item.key == key }.label
  assert(settings(makao, off).include?(expected), "Makao enabled #{key} is not listed")
end
assert(settings(makao, "profile" => "joker").include?("Use two jokers"), "locked profile's enabled rules missing")
assert(settings(makao, "profile" => "joker").include?("Cards dealt to each player: 5"), "fixed profile hand size missing")
assert(!settings(makao, "profile" => "joker").include?("Queen is universal"), "disabled preset rule leaked")
assert(settings(makao, "profile" => "polish").include?("Jack requests a rank"), "Polish profile's enabled jack rule missing")

profiles = GameRoomGames::Monopoly.new.rule_book.sections.find { |section| section.id == :board_profiles }
assert(profiles.paragraphs.length == 19, "Monopoly must describe all 19 boards")
GameRoomContent::MonopolyBoards.choices.each_with_index do |choice, index|
  id = choice.value
  board = GameRoomContent::MonopolyBoards.build(id)
  text = profiles.paragraphs[index]
  assert(text.include?(board[:name]), "missing regional Monopoly board #{id}")
  assert(text.include?(board[:starting_cash].to_s) && text.include?(board[:salary].to_s), "Monopoly economics do not match board #{id}")
end

class ShortcutEventSource
  attr_accessor :pressed_key

  def keyevents
    [[:key_a, :a]]
  end

  def key_first_pressed?(key)
    key == pressed_key
  end
end

shortcut_source = ShortcutEventSource.new
shortcut_source.extend(GameRoomRules::ShortcutFormEvents)
shortcut_source.pressed_key = 0x70
shortcut_events = shortcut_source.send(:keyevents)
assert(shortcut_events.include?([:key_f1, :f1]), "F1 is not captured directly by the form")
assert(shortcut_events.include?([:key_a, :a]), "the rules shortcut replaced standard form events")
shortcut_source.pressed_key = nil
assert(!shortcut_source.send(:keyevents).include?([:key_f1, :f1]), "an idle form reported F1")

assert(GameRoomRules.ctrl_f1_event?([false, true, false]), "Ctrl+F1 was not recognized")
assert(!GameRoomRules.ctrl_f1_event?([false, false, false]), "F1 without Ctrl opened the rules")
assert(!GameRoomRules.ctrl_f1_event?([true, true, false]), "Ctrl+Shift+F1 opened the rules")
assert(!GameRoomRules.ctrl_f1_event?([false, true, true]), "Ctrl+Alt+F1 opened the rules")

tip_field = Object.new
tips = []
tip_field.define_singleton_method(:add_tip) { |tip| tips << tip }
bound_handler = nil
fake_form = Object.new
fake_form.define_singleton_method(:extend) { |_mod| self }
fake_form.define_singleton_method(:on) do |event, &handler|
  bound_handler = [event, handler]
end
called = false
GameRoomRules.bind_ctrl_f1(fake_form, [tip_field]) { called = true }
assert(tips == ["Ctrl+F1, Game rules."], "F1 help does not advertise Ctrl+F1")
assert(bound_handler[0] == :key_f1, "Ctrl+F1 was bound to the wrong form event")
bound_handler[1].call([false, true, false])
assert(called, "the Ctrl+F1 handler was not called")

invalid_game = Class.new(GameRoomGames::Base) do
  def id
    "invalid"
  end

  def name
    "Invalid"
  end

  def rule_sections
    [rule_section(:goal, "Goal", "Missing the other required sections")]
  end
end
begin
  GameRoomGames::Registry.new([invalid_game])
  raise "the registry accepted a game with incomplete rules"
rescue ArgumentError => error
  raise if !error.message.include?("missing rule sections")
end

puts "Game rules tests passed"
