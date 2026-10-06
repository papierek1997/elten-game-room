require "json"
require_relative "../support/audio_tutorial_native"
require EltenTestHost.file("src/ui/controls/grid_box.rb")
GridBox = EltenAPI::Controls::GridBox
require_relative "../support/localization"
require_relative "../support/elten_array_shuffle"

module MilleBornesUISources
  ROOT = File.expand_path("../..", __dir__)
  LOADED = []

  module BinaryRequires
    def require_relative(name)
      origin = caller_locations(1, 1).first.path
      path = File.expand_path(name, File.dirname(origin))
      path += ".rb" unless path.end_with?(".rb")
      production = %w[games lib].any? { |directory| path.start_with?("#{MilleBornesUISources::ROOT}/#{directory}/") }
      return require(path) unless production
      return false if $LOADED_FEATURES.include?(path)

      $LOADED_FEATURES << path
      source = File.binread(path)
      raise "Production source was not binary" unless source.encoding == Encoding::ASCII_8BIT
      MilleBornesUISources::LOADED << path
      TOPLEVEL_BINDING.eval(source, path, 1)
      true
    end
  end
end

Kernel.prepend(MilleBornesUISources::BinaryRequires) if ENV["MILLE_BORNES_BINARY"] == "1"
require_relative "../../lib/game_surfaces"
require_relative "../../lib/game_screen"
require_relative "../../lib/game_room_screens"
require_relative "../support/mille_bornes"

def p_(_context, text)
  return text unless GameRoomLocalization.primary_language == "pl"
  { "List" => "Lista", "Empty list" => "Pusta lista", "Button" => "Przycisk" }.fetch(text, text)
end

def SpeechOutput.speak_sequence(sequence)
  speak_text(sequence.speech_text, method: 1, interrupt: true)
end

class MilleBornesUIKeyboard
  attr_reader :modal_forms

  def initialize
    @previous = []
    @frames = 0
    @modal_keys = []
    @modal_forms = []
    @characters = ""
  end

  def frame(keys, characters: "")
    @characters = characters
    @frames += 1
    state = "\0" * 256
    keys.each { |code| state.setbyte(code, 0x80) }
    events = (@previous - keys).map { |code| [code, false] } + (keys - @previous).map { |code| [code, true] }
    EltenAPI::KeyboardState.update(raw_state: state, events: events, now: @frames * 0.1,
      pressed_implies_held: false, synthesize_repeats: false)
    @previous = keys
    $input_frame_serial = $input_frame_serial.to_i + 1
    $keyboard_state_frame_serial = $input_frame_serial
    $keyboard_state_frame_thread = Thread.current
    $activecontrols = []
  end

  def press(form, *keys, characters: "")
    frame(keys, characters: characters)
    form.update
    frame([])
    form.update
  end

  def take_character
    characters = @characters
    @characters = ""
    characters
  end

  def modal_input_consumed?
    @modal_keys.empty? && @modal_callback == nil
  end

  def modal(*keys, &callback)
    raise "Unconsumed modal input" unless @modal_keys.empty?
    @modal_keys = [[]] + keys.flat_map { |code| [[code], []] }
    @modal_keys.pop
    @modal_callback = callback
  end

  def tick(form)
    if form.instance_variable_get(:@wait)
      raise "Unexpected native wait or exhausted modal input" if @modal_keys.empty?
      @modal_forms << form unless @modal_forms.include?(form)
      callback = @modal_callback
      @modal_callback = nil
      callback.call(form) if callback
      frame(@modal_keys.shift)
    else
      frame([])
    end
  end
end

module EltenWindow
  def self.take_character(_multi)
    $native_tutorial_driver.take_character
  end
end

class MilleBornesUIHarness
  attr_reader :fixture, :game, :state, :layout, :actions, :shortcuts, :screen
  attr_accessor :viewer

  def initialize(viewer: "Alice", players: %w[Alice Bob Carol], options: {}, hand: nil)
    @fixture = MilleBornesTest::Fixture.new(players: players, options: options)
    @fixture.start
    @game = fixture.game
    @state = Marshal.load(Marshal.dump(fixture.replay.state))
    @viewer = viewer
    if hand
      state[:hands] = players.each_with_index.to_h do |player, position|
        [player, position.zero? ? hand.dup : ["75:#{position}", "fuel:#{position}"]]
      end
      state[:draw_pile] = game.send(:deck_for, state[:options]) - state[:hands].values.flatten
      state[:tracks].each { |track| track[:moving] = true }
      state[:phase] = :playing
    end
    @actions = []
    @screen = GameScreen.allocate
    @layout = GameRoomLayout::Screen.new(view_spec: view_spec, phase: :active)
    screen.instance_variable_set(:@layout, layout)
    bind
    focus_hand
  end

  def replay
    fixture.snapshot(state)
  end

  def view_spec
    GameRoomLayout::ViewSpec.new(surface: game.surface_spec(replay, viewer))
  end

  def hand_surface
    candidates = layout.surface.respond_to?(:reuse_candidates) ? layout.surface.reuse_candidates : [layout.surface]
    candidates.find { |surface| surface.is_a?(GameSurfaces::CardTable) }
  end

  def field
    hand_surface.fields.first
  end

  def cursor
    hand_surface.state.fetch("hand_cursors").fetch("hand")
  end

  def focus_hand(card = nil)
    layout.form.index = layout.form.fields.index(field)
    field.index = cursor.fetch("ids").index(card) || raise("Missing physical card #{card}") if card
  end

  def press(*keys, characters: "")
    $native_tutorial_driver.press(layout.form, *keys, characters: characters)
  end

  def refresh
    layout.update(view_spec: view_spec, history_items: [], user_items: [], users_header: "")
    bind
  end

  def bind
    layout.form.reset_bindings!
    layout.back_button.reset_bindings!
    @shortcuts = game.game_shortcuts(replay, viewer)
    layout.surface.on_action { |action| actions << action }
    screen.send(:bind_game_shortcuts, layout.form, layout.shortcut_fields, shortcuts) do |shortcut|
      result = screen.send(:activate_game_shortcut, shortcut, layout.surface, replay: replay)
      actions << result if result.is_a?(GameSurfaces::Action)
    end
    layout.form.cancel_button = layout.back_button
    layout.back_button.on(:press) { layout.surface.cancel_pending_action! if layout.surface.cancel_pending_action? }
  end

  def apply_last(history: [])
    action = actions.last || raise("No surface action to apply")
    status, plan = game.action_for(action, replay, viewer, context: fixture.context)
    MilleBornesTest.equal(:ok, status, "Native surface selection rejected by action_for: #{action.to_h}")
    plan.events.each do |command|
      event = MilleBornesTest.event(100 + state[:action_number], viewer, command.action, command.value)
      accepted = game.send(:apply_event, state, event, viewer, event["id"], history)
      MilleBornesTest.assert(accepted, "Native surface plan rejected by apply_event")
    end
    plan
  end
end

module MilleBornesUIVerification
  module_function

  def equal(expected, actual, message)
    MilleBornesTest.equal(expected, actual, message)
  end

  def check(condition, message)
    MilleBornesTest.assert(condition, message)
  end

  def text(source)
    GameRoomLocalization.translate(source)
  end

  def test(name)
    SpeechOutput.reset
    $native_tutorial_driver = MilleBornesUIKeyboard.new
    EltenAPI::KeyboardState.reset
    $focus = false
    yield
    check($native_tutorial_driver.modal_input_consumed?, "Native modal did not consume its scheduled input")
    SpeechOutput.calls.each do |call|
      spoken = call.first
      check(spoken.encoding == Encoding::UTF_8 && spoken.valid_encoding?, "Invalid native focus/status speech: #{spoken.inspect}")
    end
    puts "PASS #{GameRoomLocalization.primary_language} #{name}"
  end

  def discard_dialog(harness, card, *keys, &callback)
    $native_tutorial_driver.modal(*keys) do |form|
      check(form.instance_of?(GameRoomUI::Form), "Discard confirmation bypassed the native form")
      choice = form.fields.first
      check(choice.is_a?(ListBox), "Discard confirmation bypassed the native list")
      if GameRoomLocalization.primary_language == "pl"
        check(text("Discard %{card}?") != "Discard %{card}?", "Polish discard confirmation fell back to English")
      end
      prompt = text("Discard %{card}?") % { card: harness.game.send(:card_label, card) }
      equal(prompt, choice.header, "Discard confirmation names the wrong physical card")
      equal([text("No"), text("Yes")], choice.options, "Discard confirmation lacks localized choices")
      equal(0, choice.index, "Discard confirmation did not default to No")
      check(SpeechOutput.calls.any? { |call| call.first.include?(prompt) }, "Native focus did not speak the discard confirmation")
      callback.call(form) if callback
    end
  end

  def repair_harness(problems:, hand: %w[instant_repair:2 instant_repair:1 25:1], moving: false, options: {})
    settings = { "include_instant_repairs" => true, "accumulate_hazards" => true,
      "counterflow" => true, "counterflow_cards" => 2, "end_counterflow_cards" => 2 }.merge(options)
    harness = MilleBornesUIHarness.new(hand: hand, options: settings)
    harness.state[:tracks].first.merge!(moving: moving, hazards: problems & %w[stop out_of_gas flat_tire accident],
      speed_limit: problems.include?("speed_limit"), counterflow: problems.include?("counterflow"))
    harness.refresh
    harness
  end

  def repair_problem_text(harness, problem)
    problem == "go" ? text("No green light") : harness.game.send(:card_label, problem)
  end

  def instant_repair_tests
    test("native instant repair chooser cancels without losing the physical card or chat draft") do
      harness = repair_harness(problems: %w[stop flat_tire speed_limit counterflow])
      harness.focus_hand("instant_repair:1")
      harness.press(0x10, 0x43)
      harness.layout.chat.set_text("Repair draft")
      harness.layout.chat.index = 6
      harness.layout.chat.check = 2
      original = Marshal.dump(harness.state)
      field = harness.field
      form = harness.layout.form
      order = harness.cursor["ids"].dup
      harness.press(0x0D)
      check(harness.layout.surface.cancel_pending_action?, "Instant repair skipped explicit problem selection")
      check(harness.field.is_a?(ListBox), "Instant repair replaced the native choice list")
      equal(text("Choose a problem to remove"), harness.field.header, "Problem chooser has the wrong accessible title")
      expected = %w[stop flat_tire speed_limit counterflow].map { |problem| repair_problem_text(harness, problem) }
      equal(expected, harness.field.options, "Problem chooser lists missing or unrelated conditions")
      check(SpeechOutput.calls.any? { |call| call.first.include?(harness.field.header) }, "Native focus omitted the problem chooser title")
      harness.press(0x28)
      harness.press(0x1B)
      check(!harness.layout.surface.cancel_pending_action?, "Escape retained a pending repair")
      equal([], harness.actions, "Cancelling a repair emitted an action")
      equal(original, Marshal.dump(harness.state), "Cancelling consumed or applied a repair")
      equal("instant_repair:1", harness.cursor["selected_id"], "Cancelling selected the other identical repair")
      equal(order, harness.cursor["ids"], "Cancelling changed the sorted hand")
      equal(["Repair draft", 6, 2], [harness.layout.chat.text, harness.layout.chat.index, harness.layout.chat.check], "Repair cancellation changed the chat draft")
      check(harness.field.equal?(field) && harness.layout.form.equal?(form), "Problem cancellation rebuilt native controls")
      check(form.fields[form.index].equal?(field), "Problem cancellation lost hand focus")
      harness.press(0x0D)
      harness.press(0x28)
      harness.press(0x0D)
      equal(1, harness.actions.length, "Confirmed repair did not emit exactly one action")
      equal("instant_repair:1", harness.actions.last["card_id"], "Problem confirmation lost physical identity")
      equal("flat_tire", harness.actions.last["choice_id"], "Problem confirmation used the wrong choice")
      equal("play|instant_repair:1|flat_tire", harness.actions.last["card"], "Surface serialized a repair as an opponent attack")
      plan = harness.apply_last
      equal([["play", "instant_repair:1|flat_tire"]], plan.events.map { |event| [event.action, event.value] }, "Repair event lost its selected problem")
      track = harness.state[:tracks].first
      equal(["stop"], track[:hazards], "Repair removed more than the selected mechanical problem")
      check(track[:speed_limit] && track[:counterflow] && !track[:moving], "Repair cleared other restrictions or started a blocked car")
      check(harness.state[:hands]["Alice"].include?("instant_repair:2"), "Repair consumed its identical neighbour")
    end

    test("every instant repair problem passes native selection and records localized history") do
      %w[stop out_of_gas flat_tire accident speed_limit counterflow go].each do |problem|
        moving = %w[speed_limit counterflow].include?(problem)
        harness = repair_harness(problems: [problem], moving: moving, hand: %w[instant_repair:1 25:1])
        harness.focus_hand("instant_repair:1")
        harness.field.focus
        label = GameRoomLocalization.primary_language == "pl" ? "Błyskawiczna naprawa" : "Instant repair"
        equal(label, harness.field.options[harness.field.index], "Repair label is missing or mistranslated")
        check(SpeechOutput.calls.last.first.include?(label), "Native focus did not speak the repair label")
        harness.press(0x0D)
        check(harness.layout.surface.cancel_pending_action?, "A sole repair problem was chosen automatically")
        equal([], harness.actions, "Opening a single-problem chooser submitted the repair")
        if GameRoomLocalization.primary_language == "pl"
          check(harness.field.header != "Choose a problem to remove", "Polish problem chooser fell back to English")
        end
        expected_problem = repair_problem_text(harness, problem)
        if problem == "go"
          expected_problem = GameRoomLocalization.primary_language == "pl" ? "Brak zielonego światła" : "No green light"
        end
        equal([expected_problem], harness.field.options, "Native chooser mislabeled #{problem}")
        harness.field.focus
        check(SpeechOutput.calls.last.first.include?(expected_problem), "Native problem focus omitted #{problem}")
        harness.press(0x0D)
        history = []
        plan = harness.apply_last(history: history)
        equal("instant_repair:1|#{problem}", plan.events.first.value, "Problem was not preserved in the event")
        track = harness.state[:tracks].first
        equal([], track[:hazards], "Selected hazard survived its repair")
        check(!track[:speed_limit] && !track[:counterflow], "Selected restriction survived its repair")
        equal(moving || %w[stop go].include?(problem), track[:moving], "Repair incorrectly granted or withheld a green light")
        equal([], track[:safeties], "Repair granted lasting immunity")
        equal(0, track[:dirty_tricks], "Repair counted as a dirty trick")
        equal(0, harness.game.participant_scores(harness.replay).fetch("Alice"), "Repair granted bonus points")
        equal(["Bob", :awaiting_draw], [harness.state[:current_player], harness.state[:phase]], "Repair granted an extra turn")
        equal(nil, harness.state[:reaction], "Repair opened a dirty-trick window")
        template = "%{player} used %{card} to remove %{problem}."
        check(text(template) != template, "Polish repair history fell back to English") if GameRoomLocalization.primary_language == "pl"
        equal(text(template) % { player: "Alice", card: label, problem: expected_problem }, history.last.text, "Repair history lost the actor, card or problem")
        check(history.last.text.encoding == Encoding::UTF_8 && history.last.text.valid_encoding?, "Repair history is not UTF-8")
      end
    end

    test("green-light choices respect remaining problems and right-of-way protection") do
      harness = repair_harness(problems: %w[stop flat_tire])
      harness.focus_hand("instant_repair:1")
      harness.press(0x0D)
      check(!harness.field.options.include?(text("No green light")), "Missing-green choice bypassed a mechanical hazard")
      harness.press(0x0D)
      harness.apply_last
      equal(["flat_tire"], harness.state[:tracks].first[:hazards], "Stop repair also removed the mechanical hazard")
      check(!harness.state[:tracks].first[:moving], "Removing Stop started a car with a mechanical hazard")
      harness = repair_harness(problems: ["flat_tire"])
      harness.state[:tracks].first[:safeties] = ["right_of_way"]
      harness.refresh
      harness.focus_hand("instant_repair:1")
      harness.press(0x0D)
      harness.press(0x0D)
      harness.apply_last
      check(harness.state[:tracks].first[:moving], "Mechanical repair ignored existing right-of-way protection")
      equal(["right_of_way"], harness.state[:tracks].first[:safeties], "Repair changed existing immunity")
    end

    test("Z groups physical instant repairs and never auto-selects a problem") do
      harness = repair_harness(problems: %w[stop flat_tire speed_limit], hand: %w[25:1 instant_repair:2 instant_repair:1])
      navigation = harness.game.playable_card_navigation(harness.replay, "Alice")
      equal(%w[instant_repair:2 instant_repair:1], navigation[:card_actions].keys, "Navigation flattened problems instead of physical repairs")
      navigation[:card_actions].each_value do |actions|
        equal(%w[stop flat_tire speed_limit], actions.map { |action| action["problem"] }, "Navigation lost legal repair choices")
      end
      equal([], navigation[:automatic_card_ids], "Repair was marked as an automatic action")
      harness.focus_hand("25:1")
      %w[instant_repair:2 instant_repair:1 instant_repair:2].each do |card|
        harness.press(0x5A)
        equal(card, harness.cursor["selected_id"], "Z repeated a physical card for each problem")
      end
      harness.press(0x10, 0x5A)
      equal("instant_repair:1", harness.cursor["selected_id"], "Shift+Z skipped a physical repair")
      equal([], harness.actions, "Playable navigation submitted a repair")
      check(!harness.layout.surface.cancel_pending_action?, "Navigation opened a repair chooser without Enter")
      ["flat_tire", "go"].each do |problem|
        single = repair_harness(problems: [problem], hand: %w[25:1 instant_repair:1])
        original = Marshal.dump(single.state)
        single.focus_hand("25:1")
        single.press(0x5A)
        single.press(0x10, 0x5A)
        equal("instant_repair:1", single.cursor["selected_id"], "Navigation failed to focus the sole repair")
        equal([], single.actions, "Z auto-played a sole repair problem")
        equal(original, Marshal.dump(single.state), "Single-card navigation changed game state")
        single.press(0x0D)
        check(single.layout.surface.cancel_pending_action?, "Single-problem navigation bypassed explicit confirmation")
        single.press(0x1B)
      end
    end

    test("J discards a repair without confirmation but not during problem selection") do
      harness = repair_harness(problems: ["flat_tire"])
      harness.focus_hand("instant_repair:1")
      harness.press(0x0D)
      choice = [harness.field.header, harness.field.options.dup, harness.field.index]
      harness.press(0x4A)
      equal([], harness.actions, "J discarded a repair while its problem chooser was open")
      equal(choice, [harness.field.header, harness.field.options, harness.field.index], "J changed the selected problem")
      check($native_tutorial_driver.modal_forms.empty?, "J nested a discard modal inside problem selection")
      harness.press(0x1B)
      tracks = Marshal.dump(harness.state[:tracks])
      harness.press(0x4A)
      check($native_tutorial_driver.modal_forms.empty?, "J asked to confirm the discard")
      equal(1, harness.actions.length, "J did not immediately submit exactly one discard")
      plan = harness.apply_last
      equal([["discard", "instant_repair:1"]], plan.events.map { |event| [event.action, event.value] }, "J repaired instead of discarding")
      equal(tracks, Marshal.dump(harness.state[:tracks]), "Discarding a repair removed a problem")
      equal(["instant_repair:1"], harness.state[:discard], "J discarded the wrong physical repair")
      check(harness.state[:hands]["Alice"].include?("instant_repair:2"), "J discarded both identical repairs")
    end

    test("Enter confirms a discard when an instant repair has no problem to remove") do
      harness = repair_harness(problems: [], moving: true)
      harness.focus_hand("instant_repair:1")
      actions = harness.game.legal_actions(harness.replay, "Alice").select { |action| action["card"] == "instant_repair:1" }
      equal(["discard"], actions.map { |action| action["action"] }, "Moving, unhindered car can play a useless repair")
      original = Marshal.dump(harness.state)
      discard_dialog(harness, "instant_repair:1", 0x1B)
      harness.press(0x0D)
      equal([], harness.actions, "Cancelled Enter discarded a useless repair")
      equal(original, Marshal.dump(harness.state), "Cancelled Enter changed the unhindered car")
      equal("instant_repair:1", harness.cursor["selected_id"], "Cancelled Enter lost the selected repair")
      tracks = Marshal.dump(harness.state[:tracks])
      discard_dialog(harness, "instant_repair:1", 0x28, 0x0D)
      harness.press(0x0D)
      plan = harness.apply_last
      equal([["discard", "instant_repair:1"]], plan.events.map { |event| [event.action, event.value] }, "Enter silently played a useless repair")
      equal(tracks, Marshal.dump(harness.state[:tracks]), "Discarding a useless repair changed the car")
      check(!harness.layout.surface.cancel_pending_action?, "Useless repair opened an empty problem chooser")
    end

    test("pending repair rejects a changed state and refresh preserves chat focus") do
      harness = repair_harness(problems: %w[flat_tire speed_limit])
      harness.focus_hand("instant_repair:1")
      original = Marshal.dump(harness.state)
      harness.layout.surface.action_guard = -> { Marshal.dump(harness.state) == original }
      harness.press(0x0D)
      harness.state[:tracks].first[:hazards].clear
      changed = Marshal.dump(harness.state)
      harness.press(0x0D)
      equal([], harness.actions, "Stale problem confirmation emitted a repair")
      equal(changed, Marshal.dump(harness.state), "Stale repair changed the current model")
      stale = { "kind" => "card", "action" => "select", "card" => "play|instant_repair:1|flat_tire" }
      status, plan = harness.game.action_for(stale, harness.replay, "Alice", context: harness.fixture.context)
      equal([:invalid, nil], [status, plan], "Model accepted a problem already removed during selection")
      harness.layout.surface.action_guard = nil
      harness.press(0x1B) if harness.layout.surface.cancel_pending_action?
      harness.refresh
      harness.focus_hand("instant_repair:1")
      harness.press(0x0D)
      equal([text("No green light"), repair_problem_text(harness, "speed_limit")], harness.field.options, "Refreshed chooser retained the old hazard")
      harness.press(0x1B)
      field = harness.field
      harness.layout.form.index = harness.layout.form.fields.index(harness.layout.chat)
      harness.layout.chat.set_text("Repair draft")
      harness.layout.chat.index = 6
      harness.layout.chat.check = 2
      harness.state[:tracks].first[:speed_limit] = false
      harness.refresh
      check(harness.field.equal?(field), "Problem refresh rebuilt the hand")
      check(harness.layout.form.fields[harness.layout.form.index].equal?(harness.layout.chat), "Problem refresh stole chat focus")
      equal(["Repair draft", 6, 2], [harness.layout.chat.text, harness.layout.chat.index, harness.layout.chat.check], "Problem refresh changed the chat draft")
      harness.press(0x4A, characters: "j")
      harness.press(0x5A, characters: "z")
      equal([], harness.actions, "Chat typing repaired or discarded a selected card")
      equal(nil, harness.layout.take_cursor_announcement, "Unchanged hand announced a phantom draw")
    end

    test("custom deck repair copies retain unique physical choices") do
      harness = repair_harness(problems: ["go"], hand: %w[25:1 instant_repair:4 instant_repair:1],
        options: { "custom_deck" => true, "instant_repair_cards" => 4, "25_cards" => 3 })
      inventory = harness.state[:hands].values.flatten + harness.state[:draw_pile]
      equal(%w[instant_repair:1 instant_repair:2 instant_repair:3 instant_repair:4], inventory.grep(/^instant_repair:/).sort, "Custom repair count did not reach the surface fixture")
      equal(%w[25:1 25:2 25:3], inventory.grep(/^25:/).sort, "Custom mileage count was ignored")
      harness.focus_hand("instant_repair:4")
      harness.press(0x10, 0x43)
      harness.refresh
      equal("instant_repair:4", harness.cursor["selected_id"], "Sorting lost a custom physical card")
      harness.press(0x0D)
      harness.press(0x0D)
      equal("instant_repair:4|go", harness.apply_last.events.first.value, "Custom repair used a standard-deck physical ID")
      check(harness.state[:hands]["Alice"].include?("instant_repair:1"), "Custom repair consumed an identical neighbour")
    end
  end

  def run
    test("private physical hands, teammates and observer isolation") do
      harness = MilleBornesUIHarness.new(players: %w[Alice Bob Carol David], options: { "team_count" => 2 })
      original = Marshal.dump(harness.state)
      %w[Alice Bob Carol David alice Observer].each do |viewer|
        harness.viewer = viewer
        harness.refresh
        expected = harness.state[:hands].fetch(viewer.casecmp?("Alice") ? "Alice" : viewer, [])
        equal(expected, harness.cursor.fetch("raw_ids"), "Visible hand leaked another player's cards to #{viewer}")
        equal(expected, harness.cursor.fetch("ids"), "Surface is not the viewer's physical hand")
        equal(expected.map { |card| harness.game.send(:card_label, card) }, harness.field.options, "Wrong native private labels")
        check(harness.game.legal_actions(harness.replay, viewer).empty?, "Observer received legal actions") if viewer == "Observer"
      end
      check(harness.shortcuts.none? { |shortcut| [:action, :choice, :surface].include?(shortcut.kind) }, "Observer received hand actions")
      harness.focus_hand
      harness.press(0x0D)
      equal([], harness.actions, "Observer submitted a hidden card")
      harness.press(0x48)
      equal(text("Your hand is empty."), SpeechOutput.calls.last.first, "Observer hand announcement leaked private cards")
      equal(original, Marshal.dump(harness.state), "Presentation changed private game state")
    end

    test("native Enter plays the selected physical mileage card through the model") do
      harness = MilleBornesUIHarness.new(hand: %w[100:1 25:1 25:2 stop:1])
      harness.focus_hand("25:2")
      harness.field.focus
      check(SpeechOutput.calls.last.first.include?(harness.game.send(:card_label, "25:2")), "Native focus omitted the card label")
      harness.press(0x0D)
      equal(1, harness.actions.length, "Enter did not produce exactly one action")
      equal("25:2", harness.actions.last["card_id"], "Enter lost physical card identity")
      plan = harness.apply_last
      equal("play", plan.events.first.action, "Enter bypassed the standard play event")
      equal(25, harness.state[:tracks][0][:miles], "Accepted card did not change mileage")
      check(harness.state[:hands]["Alice"].include?("25:1") && !harness.state[:hands]["Alice"].include?("25:2"), "Wrong duplicate card was removed")
      check($native_tutorial_driver.modal_forms.empty?, "Playable Enter unexpectedly asked to discard")
    end

    test("after drawing Enter confirms the unplayable sorted physical duplicate") do
      harness = MilleBornesUIHarness.new(hand: %w[100:1 fuel:3 25:2])
      harness.state[:phase] = :awaiting_draw
      harness.state[:draw_pile].delete("fuel:4")
      harness.state[:draw_pile].unshift("fuel:4")
      harness.refresh
      harness.press(0x20)
      equal("draw", harness.apply_last.events.first.action, "Fixture did not perform a real draw")
      harness.refresh
      harness.actions.clear
      equal("fuel:4", harness.cursor["selected_id"], "Draw did not select the received physical card")
      original_hand = harness.state[:hands]["Alice"].dup
      harness.press(0x10, 0x43)
      check(original_hand != harness.cursor["ids"], "Fixture did not sort the native hand")
      harness.refresh
      equal("fuel:4", harness.cursor["selected_id"], "Sorted refresh lost the received duplicate")
      candidates = harness.game.legal_actions(harness.replay, "Alice").select { |action| action["card"] == "fuel:4" }
      equal(["discard"], candidates.map { |action| action["action"] }, "Fixture card is not exclusively discard-legal")
      discard_dialog(harness, "fuel:4", 0x28, 0x0D)
      harness.press(0x0D)
      equal(1, harness.actions.length, "Confirmed Enter emitted more than one action")
      equal("fuel:4", harness.actions.last["card_id"], "Enter used the wrong physical duplicate")
      plan = harness.apply_last
      equal(["discard", "fuel:4"], [plan.events.first.action, plan.events.first.value], "Enter did not use the standard discard event")
      equal(original_hand - ["fuel:4"], harness.state[:hands]["Alice"], "Enter discarded a different duplicate")
      equal(["fuel:4"], harness.state[:discard], "Confirmed discard did not reach the model")
      harness.refresh
      check(harness.shortcuts.none? { |shortcut| shortcut.key == "j" }, "J remained active after the turn ended")
    end

    test("No and Escape cancel Enter without an action or cursor change") do
      [[0x0D, "fuel:4"]].each do |activation, card|
        [[0x0D], [0x1B], [0x28, 0x1B]].each do |cancellation|
          harness = MilleBornesUIHarness.new(hand: %w[100:1 fuel:4 25:2 fuel:3 25:1])
          harness.focus_hand(card)
          harness.press(0x10, 0x43)
          harness.refresh
          before = Marshal.dump(harness.state)
          cursor = harness.cursor.dup
          discard_dialog(harness, card, *cancellation)
          harness.press(activation)
          equal([], harness.actions, "Declining a discard emitted an action")
          equal(before, Marshal.dump(harness.state), "Declining a discard changed the model")
          equal(cursor, harness.cursor, "Declining a discard changed physical selection or sorting")
          check(harness.layout.form.fields[harness.layout.form.index].equal?(harness.field), "Discard cancellation stole hand focus")
          check(!harness.layout.surface.cancel_pending_action?, "Discard cancellation retained a pending choice")
          check($native_tutorial_driver.modal_input_consumed?, "Discard cancellation left modal input pending")
        end
      end
      equal(3, $native_tutorial_driver.modal_forms.length, "A cancellation path skipped its native confirmation")
    end

    test("J immediately discards a playable selected duplicate or attack instead of playing it") do
      %w[25:2 stop:1].each do |card|
        harness = MilleBornesUIHarness.new(hand: %w[100:1 25:2 stop:1 25:1])
        harness.focus_hand(card)
        harness.press(0x10, 0x43)
        harness.refresh
        equal(card, harness.cursor["selected_id"], "Sort lost the card intended for J")
        check(harness.game.legal_actions(harness.replay, "Alice").any? { |action| action["card"] == card && action["action"] == "play" }, "J fixture is not playable")
        before = harness.state[:hands]["Alice"].dup
        tracks = Marshal.dump(harness.state[:tracks])
        harness.press(0x4A)
        check($native_tutorial_driver.modal_forms.empty?, "J asked to confirm a playable card discard")
        equal(1, harness.actions.length, "J did not emit exactly one immediate action")
        equal("shortcut:j", harness.actions.last.source, "J bypassed the surface shortcut path")
        plan = harness.apply_last
        equal(["discard", card], [plan.events.first.action, plan.events.first.value], "J played a card or discarded the wrong physical copy")
        equal(before - [card], harness.state[:hands]["Alice"], "J removed a different physical card")
        equal(tracks, Marshal.dump(harness.state[:tracks]), "J played the mileage or attacked an opponent")
        check(!harness.layout.surface.cancel_pending_action?, "J opened an opponent chooser")
      end
    end

    test("before drawing and off-turn cards never become default discards") do
      [[:awaiting_draw, "Alice"], [:playing, "Bob"], [:awaiting_draw, "Bob"]].each do |phase, current_player|
        harness = MilleBornesUIHarness.new(hand: %w[fuel:3 25:1])
        harness.state[:phase] = phase
        harness.state[:current_player] = current_player
        harness.refresh
        harness.focus_hand("fuel:3")
        before = Marshal.dump(harness.state)
        check(harness.shortcuts.none? { |shortcut| %w[j delete].include?(shortcut.key) }, "Unavailable discard shortcut was advertised")
        harness.press(0x4A)
        harness.press(0x11, 0x4A)
        harness.press(0x2E)
        equal([], harness.actions, "An unavailable discard shortcut emitted an action")
        harness.press(0x0D)
        harness.actions.each do |action|
          status, plan = harness.game.action_for(action, harness.replay, "Alice", context: harness.fixture.context)
          equal(:invalid, status, "Enter bypassed turn/draw rules")
          equal(nil, plan, "Unavailable Enter produced a plan")
        end
        equal(before, Marshal.dump(harness.state), "Unavailable input changed the model")
      end
      check($native_tutorial_driver.modal_forms.empty?, "Unavailable discard opened a confirmation or chooser")
    end

    test("J cannot discard while an opponent choice is pending") do
      harness = MilleBornesUIHarness.new(hand: %w[stop:1 25:1])
      harness.focus_hand("stop:1")
      harness.press(0x0D)
      harness.press(0x28)
      check(harness.layout.surface.cancel_pending_action?, "Fixture did not open its opponent choice")
      before = Marshal.dump(harness.state)
      choice = [harness.field.header, harness.field.options.dup, harness.field.index]
      harness.press(0x4A)
      equal([], harness.actions, "J submitted a card while choosing an opponent")
      equal(text("Finish or cancel the current card choice first."), SpeechOutput.calls.last.first, "Pending choice did not explain why J was blocked")
      harness.press(0x11, 0x4A)
      equal(choice, [harness.field.header, harness.field.options, harness.field.index], "J changed the pending opponent")
      equal(before, Marshal.dump(harness.state), "Blocked J changed game state")
      check($native_tutorial_driver.modal_forms.empty?, "Pending opponent choice opened a second modal")
      harness.press(0x1B)
      harness.press(0x4A)
      check($native_tutorial_driver.modal_forms.empty?, "J opened a confirmation after cancelling the opponent choice")
      equal("discard", harness.apply_last.events.first.action, "J did not recover after cancelling the opponent choice")
    end

    test("chat J inserts text and Ctrl+J never discards a selected card") do
      harness = MilleBornesUIHarness.new(hand: %w[25:2 fuel:3 25:1])
      harness.focus_hand("25:2")
      before = Marshal.dump(harness.state)
      harness.press(0x11, 0x4A)
      equal([], harness.actions, "Ctrl+J on the hand discarded a card")
      harness.layout.form.index = harness.layout.form.fields.index(harness.layout.chat)
      harness.layout.chat.set_text("Draft ")
      harness.layout.chat.index = harness.layout.chat.text.length
      harness.layout.chat.check = harness.layout.chat.index
      harness.layout.chat.focus
      harness.press(0x4A, characters: "j")
      equal("Draft j", harness.layout.chat.text, "J did not reach the native chat editor")
      draft = [harness.layout.chat.text, harness.layout.chat.index, harness.layout.chat.check]
      harness.press(0x11, 0x4A)
      equal(draft, [harness.layout.chat.text, harness.layout.chat.index, harness.layout.chat.check], "Ctrl+J changed the chat draft")
      equal([], harness.actions, "Chat J or Ctrl+J emitted a game action")
      equal("25:2", harness.cursor["selected_id"], "Chat input changed physical card selection")
      equal(before, Marshal.dump(harness.state), "Chat input changed game state")
      check($native_tutorial_driver.modal_forms.empty?, "Chat or Ctrl+J opened a discard modal")
    end

    test("Enter and J respect the action guard and Enter rechecks after confirmation") do
      [[0x0D, "fuel:3"], [0x4A, "25:2"]].each do |activation, card|
        harness = MilleBornesUIHarness.new(hand: %w[fuel:3 25:2 25:1])
        harness.focus_hand(card)
        harness.layout.surface.action_guard = -> { false }
        count = $native_tutorial_driver.modal_forms.length
        harness.press(activation)
        equal([], harness.actions, "A denied action guard allowed a discard")
        equal(count, $native_tutorial_driver.modal_forms.length, "A denied action guard opened a confirmation")
        next if activation == 0x4A

        revision = Marshal.dump(harness.state)
        harness.layout.surface.action_guard = -> { Marshal.dump(harness.state) == revision }
        changed = nil
        discard_dialog(harness, card, 0x28, 0x0D) do
          harness.state[:current_player] = "Bob"
          harness.state[:phase] = :awaiting_draw
          changed = Marshal.dump(harness.state)
        end
        harness.press(activation)
        equal(count + 1, $native_tutorial_driver.modal_forms.length, "The stale-state test did not confirm a real modal")
        equal([], harness.actions, "Yes emitted a discard after the action guard became stale")
        equal(changed, Marshal.dump(harness.state), "Stale confirmation changed the new turn")
      end
    end

    test("native two-player Enter selects the sole opponent without losing focus or identity") do
      GameRoomGames::MilleBornes::HAZARDS.each do |type|
        harness = MilleBornesUIHarness.new(players: %w[Alice Bob], hand: ["#{type}:1", "25:1"],
          options: { "counterflow" => true })
        harness.focus_hand("#{type}:1")
        form = harness.layout.form
        field = harness.field
        harness.press(0x0D)
        equal(1, harness.actions.length, "Enter did not submit the sole-target attack once")
        equal("#{type}:1", harness.actions.last["card_id"], "Automatic target lost the physical card")
        equal("play|#{type}:1|1", harness.actions.last["card"], "Automatic target serialized the wrong opponent")
        check(!harness.layout.surface.cancel_pending_action?, "Two-player attack opened a target chooser")
        check($native_tutorial_driver.modal_forms.empty?, "Two-player attack opened a modal")
        check(harness.layout.form.equal?(form) && harness.field.equal?(field), "Automatic target rebuilt native controls")
        check(form.fields[form.index].equal?(field), "Automatic target lost hand focus")
        equal(["play"], harness.apply_last.events.map(&:action), "Automatic attack bypassed the normal action path")
      end
    end

    test("native distance events speak the resulting mileage through the shared presenter") do
      GameRoomGames::MilleBornes::DISTANCES.each do |type|
        [false, true].each do |reverse|
          harness = MilleBornesUIHarness.new(players: %w[Alice Bob], hand: ["#{type}:1", "fuel:1"],
            options: { "counterflow" => true })
          harness.state[:tracks][0].merge!(miles: 75, counterflow: reverse)
          harness.refresh
          harness.focus_hand("#{type}:1")
          before = Marshal.load(Marshal.dump(harness.replay))
          harness.press(0x0D)
          history = []
          plan = harness.apply_last(history: history)
          after = harness.replay
          after.history = history
          event = MilleBornesTest.event(history.first.event_id, "Alice", plan.events.first.action, plan.events.first.value)
          program = Object.new
          program.define_singleton_method(:game_room_sound_enabled?) { |_name| false }
          speaker = Object.new
          presenter = GameRoomEventPresenter.new(game: -> { harness.game }, repository: -> { harness.fixture.repository },
            program: -> { program }, viewer: -> { "Alice" }, client: -> { nil }, surface_state: -> { {} },
            clock: -> { 0 }, covered: -> { false }, speech: ->(message) { speaker.send(:speak, message) },
            trace: ->(*_arguments, **_options) {}, history_changed: ->(*_arguments) {}, session_changed: ->(*_arguments) {})
          resulting = [75 + (reverse ? -type.to_i : type.to_i), 0].max
          expected = if GameRoomLocalization.primary_language == "pl"
            "Alice zagrywa #{type} mil. Łącznie #{resulting} mil."
          else
            "Alice played #{type} miles, now at #{resulting} miles."
          end
          SpeechOutput.reset
          presenter.present_game_event(event, before, after, after, nil)
          equal([expected], SpeechOutput.calls.map(&:first), "Shared native speech missed or duplicated resulting mileage")
          equal(expected, history.find { |entry| entry.kind == :play }.text, "Speech and history disagree")
        end
      end
    end

    test("native opponent selection, cancellation and explicit target submission") do
      harness = MilleBornesUIHarness.new(hand: %w[stop:1 25:1])
      harness.focus_hand("stop:1")
      before = Marshal.dump(harness.state)
      harness.press(0x0D)
      check(harness.layout.surface.cancel_pending_action?, "Enter did not open the opponent chooser")
      equal([], harness.actions, "Opening the opponent chooser prematurely submitted an attack")
      equal(text("Choose an opponent"), harness.field.header, "Opponent chooser lacks an accessible header")
      check(harness.field.options[0].include?("Bob") && harness.field.options[1].include?("Carol"), "Opponent list lacks target status")
      harness.press(0x1B)
      check(!harness.layout.surface.cancel_pending_action?, "Escape left an attack pending")
      equal("stop:1", harness.cursor["selected_id"], "Cancellation lost the attacking physical card")
      equal([], harness.actions, "Cancelling the target chooser emitted an event")
      equal(before, Marshal.dump(harness.state), "Target cancellation changed game state")
      harness.press(0x0D)
      harness.press(0x28)
      harness.press(0x0D)
      equal(1, harness.actions.length, "Explicit target confirmation did not emit one action")
      harness.apply_last
      check(harness.state[:tracks][2][:hazards].include?("stop"), "Selected opponent was not attacked")
      check(!harness.state[:tracks][1][:hazards].include?("stop"), "Attack silently used the first opponent")
    end

    test("Space draws and native Delete chooser supports cancel and selection") do
      harness = MilleBornesUIHarness.new(hand: %w[100:1 25:1 25:2])
      harness.state[:phase] = :awaiting_draw
      harness.refresh
      drawn = harness.state[:draw_pile].first
      before = harness.state[:hands]["Alice"].dup
      harness.press(0x20)
      equal(1, harness.actions.length, "Space emitted more than one draw action")
      equal("draw", harness.apply_last.events.first.action, "Space bypassed draw rules")
      equal(before + [drawn], harness.state[:hands]["Alice"], "Draw did not append the physical card")
      harness.refresh
      equal(drawn, harness.cursor["selected_id"], "Draw did not focus the last received card")
      harness.actions.clear
      $native_tutorial_driver.modal(0x1B)
      harness.press(0x2E)
      equal([], harness.actions, "Cancelled discard dialog emitted an action")
      $native_tutorial_driver.modal(0x28, 0x28, 0x0D)
      harness.press(0x2E)
      modal = $native_tutorial_driver.modal_forms.last
      check(modal.instance_of?(GameRoomUI::Form) && modal.fields.first.instance_of?(ListBox), "Delete did not use the real native chooser")
      equal(text("Choose a card to discard"), modal.fields.first.header, "Discard chooser lost its accessible title")
      equal(1, harness.actions.length, "Discard confirmation emitted more than one action")
      equal("25:2", harness.actions.last["card"], "Native chooser discarded a label rather than the selected physical duplicate")
      equal("discard", harness.apply_last.events.first.action, "Delete bypassed the discard event")
      check(!harness.state[:hands]["Alice"].include?("25:2") && harness.state[:hands]["Alice"].include?("25:1"), "Discard removed the wrong duplicate")
    end

    test("Z and Shift+Z keep multiplayer targets explicit and allow unambiguous two-player attacks") do
      harness = MilleBornesUIHarness.new(hand: %w[fuel:3 25:1 stop:1 25:2])
      harness.focus_hand("fuel:3")
      original = Marshal.dump(harness.state)
      %w[25:1 stop:1 25:2 25:1].each do |expected|
        harness.press(0x5A)
        equal(expected, harness.cursor["selected_id"], "Z did not cycle distinct playable cards")
        check(SpeechOutput.calls.last.first.include?(harness.game.send(:card_label, expected)), "Z did not speak the new card")
      end
      harness.press(0x10, 0x5A)
      equal("25:2", harness.cursor["selected_id"], "Shift+Z did not wrap backwards")
      equal([], harness.actions, "Navigation with multiple choices played a card")
      equal(original, Marshal.dump(harness.state), "Navigation changed game state")
      single = MilleBornesUIHarness.new(players: %w[Alice Bob], hand: %w[fuel:3 stop:1])
      single.focus_hand("fuel:3")
      single.press(0x5A)
      equal("fuel:3", single.cursor["selected_id"], "Direct submission changed the cursor before the accepted hand update")
      equal(1, single.actions.length, "Z did not submit the sole unambiguous two-player attack")
      equal(["play", "stop:1", "1"], %w[action card target].map { |key| single.actions.first[key] }, "Z used the wrong opponent")
      check(!single.layout.surface.cancel_pending_action?, "Two-player Z left a redundant opponent choice")
      single.apply_last
    end

    test("sorting, refresh, chat and hand epochs preserve the correct cursor") do
      harness = MilleBornesUIHarness.new(hand: %w[100:1 25:2 stop:1 25:1])
      harness.focus_hand("25:2")
      original = Marshal.dump(harness.state)
      field = harness.field
      form = harness.layout.form
      [
        [0x48, %w[stop:1 25:1 25:2 100:1]],
        [0x48, %w[100:1 25:2 25:1 stop:1]],
        [0x43, %w[25:1 25:2 100:1 stop:1]],
        [0x43, %w[stop:1 100:1 25:2 25:1]],
        [0x4D, %w[100:1 25:2 stop:1 25:1]]
      ].each do |key, expected|
        harness.press(0x10, key)
        equal(expected, harness.cursor["ids"], "Sort shortcut did not change the actual displayed order")
        equal("25:2", harness.cursor["selected_id"], "Sort replaced physical focus with an identical label")
        harness.refresh
        check(harness.field.equal?(field) && harness.layout.form.equal?(form), "Refresh rebuilt native hand controls")
        equal(expected, harness.cursor["ids"], "Refresh discarded the selected sort order")
        equal("25:2", harness.cursor["selected_id"], "Refresh lost sorted physical focus")
        equal(nil, harness.layout.take_cursor_announcement, "Unchanged sorted refresh repeated a card")
      end
      equal(original, Marshal.dump(harness.state), "Presentation sorting mutated the model")
      equal(harness.state[:hands]["Alice"], harness.cursor["ids"], "Restore acquisition order did not restore raw order")
      harness.layout.chat.set_text("Draft message")
      harness.layout.chat.index = 5
      harness.layout.chat.check = 2
      form.index = form.fields.index(harness.layout.chat)
      harness.state[:hands]["Alice"] << harness.state[:draw_pile].shift
      harness.refresh
      check(form.fields[form.index].equal?(harness.layout.chat), "Incoming card stole chat focus")
      equal(["Draft message", 5, 2], [harness.layout.chat.text, harness.layout.chat.index, harness.layout.chat.check], "Refresh changed the chat draft")
      equal(nil, harness.layout.take_cursor_announcement, "Incoming hand spoke over chat")
      harness.focus_hand("stop:1")
      harness.press(0x0D)
      check(harness.layout.surface.cancel_pending_action?, "Epoch fixture never opened its target chooser")
      epoch = harness.cursor["epoch"]
      harness.state[:round] += 1
      harness.refresh
      check(harness.cursor["epoch"] != epoch, "A new round retained the old hand epoch")
      check(!harness.layout.surface.cancel_pending_action?, "New round retained the old target choice")
      equal(harness.cursor["ids"].first, harness.cursor["selected_id"], "New round retained a stale card cursor")
      equal(nil, harness.layout.take_cursor_announcement, "New round was announced as a draw")
      epoch = harness.cursor["epoch"]
      harness.viewer = "Bob"
      harness.refresh
      check(harness.cursor["epoch"] != epoch, "Changing owner retained the private hand epoch")
      equal(harness.state[:hands]["Bob"], harness.cursor["raw_ids"], "Changing owner reused the previous private hand")
      epoch = harness.cursor["epoch"]
      harness.fixture.session["id"] += 1
      harness.refresh
      check(harness.cursor["epoch"] != epoch, "New session retained the old private hand epoch")
      equal(nil, harness.layout.take_cursor_announcement, "New session was announced as a draw")
    end

    test("localized native focus retains English names and requested Polish names during immediate discards") do
      expected = if GameRoomLocalization.primary_language == "pl"
        { "out_of_gas:3" => "Spuszczenie paliwa", "fuel:3" => "Zatankowanie",
          "flat_tire:3" => "Przedziurawienie opon", "driving_ace:1" => "As drogi" }
      else
        { "out_of_gas:3" => "Out of gas", "fuel:3" => "Gas",
          "flat_tire:3" => "Flat tire", "driving_ace:1" => "Driving ace" }
      end
      harness = MilleBornesUIHarness.new(hand: expected.keys)
      equal(expected.values, harness.field.options, "Native hand has incompatible or untranslated card labels")
      expected.each do |card, label|
        harness.focus_hand(card)
        harness.field.focus
        check(SpeechOutput.calls.last.first.include?(label), "Native card focus did not speak the localized label")
        harness.press(0x4A)
        equal(1, harness.actions.length, "J did not immediately discard the localized card")
        equal(card, harness.actions.last["card"], "J discarded the wrong physical card")
        check($native_tutorial_driver.modal_forms.empty?, "J opened a localized confirmation")
        harness.actions.clear
      end
    end

    test("native dirty trick announces the localized reaction and preserves its meaning") do
      harness = MilleBornesUIHarness.new(players: ["Alice", "Bob", "Żaneta"], hand: %w[stop:1 25:1])
      harness.state[:hands]["Żaneta"] = %w[right_of_way:1 100:2 100:3 100:4 100:5 100:6]
      harness.state[:draw_pile] = harness.game.send(:deck_for, harness.state[:options]) - harness.state[:hands].values.flatten
      equal(:ok, harness.fixture.play(harness.state, "Alice", "play", "stop:1", target: "2"), "Setup attack rejected")
      equal("Bob", harness.state[:current_player], "Reaction is not outside the responder's turn")
      harness.viewer = "Żaneta"
      harness.refresh
      harness.focus_hand("right_of_way:1")
      harness.press(0x0D)
      equal(1, harness.actions.length, "Enter did not produce exactly one safety reaction")
      equal("right_of_way:1", harness.actions.last["card_id"], "Enter lost the physical safety card")
      history = []
      plan = harness.apply_last(history: history)
      equal("dirty_trick", plan.events.first.action, "Enter did not select the pending safety reaction")
      expected = if GameRoomLocalization.primary_language == "pl"
        "Żaneta: nieczysta zagrywka — Pierwszeństwo przejazdu. Premia 300 punktów i dodatkowa tura."
      else
        "Żaneta played Right of way: dirty trick! 300 bonus points and an extra turn."
      end
      equal([expected], history.map(&:text), "Real reaction history uses the wrong translated name or bonus")
      harness.layout.update_history(history.map(&:text))
      harness.layout.form.index = harness.layout.form.fields.index(harness.layout.history)
      harness.layout.history.focus
      check(SpeechOutput.calls.last.first.include?(expected), "Native history focus did not speak the localized dirty trick")
      check(harness.state[:tracks][2][:moving], "Translated reaction failed to restore driving")
      equal([], harness.state[:tracks][2][:hazards], "Translated reaction did not cancel the attack")
      equal([], harness.state[:tracks][0][:hazards], "Dirty trick became an attack back")
      equal(400, harness.game.participant_scores(harness.replay).fetch("Żaneta"), "Safety and dirty-trick bonuses changed")
      equal("Żaneta", harness.state[:current_player], "Responder did not receive the extra turn")
      equal(6, harness.state[:hands]["Żaneta"].length, "Replacement draw changed")
      harness.refresh
      harness.focus_hand
      harness.press(0x20)
      harness.apply_last
      equal(7, harness.state[:hands]["Żaneta"].length, "Normal extra-turn draw changed")
      harness.refresh
      harness.focus_hand("100:2")
      harness.press(0x0D)
      harness.apply_last
      equal("Alice", harness.state[:current_player], "Play did not continue after the responder")
    end

    test("native rules and shortcut reference speak the correctly inflected dirty-trick name") do
      harness = MilleBornesUIHarness.new(hand: %w[100:1 25:1])
      book = harness.game.rule_book(options: harness.game.default_options)
      rules = book.documents.find { |document| document.id == :rules }
      controls = book.documents.find { |document| document.id == :controls }
      screen = GameRoomScreens::GameRules.new(book)
      rules_form = screen.send(:section_form, rules)
      rules_field = rules_form.fields.first
      title = GameRoomLocalization.primary_language == "pl" ? "Nieczyste zagrywki" : "Dirty tricks"
      check(rules_form.is_a?(GameRoomUI::Form), "Rules bypassed the shared native form")
      check(rules_field.is_a?(GameRoomRules::View), "Rules bypassed the accessible document view")
      check((rules_field.flags & EditBox::Flags::ReadOnly) != 0, "Rules are editable")
      check(rules_field.text.include?(title), "Native rules document uses the wrong reaction heading")
      rules_field.focus
      check(SpeechOutput.calls.any? { |call| call.first.include?(title) }, "Native rules focus omitted the localized reaction heading")
      controls_form = screen.send(:section_form, controls)
      controls_field = controls_form.fields.first
      check(controls_field.is_a?(ListBox), "Shortcut help bypassed the native list")
      %w[Z Shift+Z].each do |key|
        position = controls_field.options.index { |row| row.start_with?("#{key}: ") }
        check(position, "Shortcut reference omitted #{key}")
        controls_field.index = position
        expected = GameRoomLocalization.primary_language == "pl" ? "poza czasem na nieczystą zagrywkę." : "outside the dirty-trick window."
        check(controls_field.options[position].end_with?(expected), "Shortcut help uses the wrong case for the reaction name")
        controls_field.focus
        check(SpeechOutput.calls.last.first.include?(expected), "Native shortcut focus did not speak the localized reaction window")
      end
    end

    test("status speech, local shortcut help and editable chat isolation") do
      harness = MilleBornesUIHarness.new(hand: %w[100:1 25:1])
      harness.state[:tracks][0][:miles] = 175
      harness.state[:tracks][0][:speed_limit] = true
      harness.refresh
      signatures = harness.shortcuts.map { |shortcut| [shortcut.key, shortcut.modifiers.to_a] }
      equal(signatures.uniq, signatures, "Game duplicated a shortcut")
      check(harness.shortcuts.none? { |shortcut| %w[f1 f2 f3 f4].include?(shortcut.key) }, "Game duplicated shared function keys")
      check(harness.shortcuts.all? { |shortcut| !shortcut.label.to_s.strip.empty? && shortcut.label.valid_encoding? }, "A shortcut has no accessible label")
      harness.press(0x49)
      check(SpeechOutput.calls.last.first.include?("175"), "I did not announce actual mileage")
      check(SpeechOutput.calls.last.first.include?(harness.game.send(:card_label, "speed_limit")), "I omitted the current hazard")
      harness.press(0x10, 0x49)
      check(%w[Alice Bob Carol].all? { |player| SpeechOutput.calls.last.first.include?(player) }, "Shift+I omitted a participant")
      status = harness.game.participant_status(harness.replay, "Alice")
      check(status.include?("175") && status.valid_encoding?, "Participant status does not expose actual mileage")
      tips = GameRoomContextHelp.game_field_tips(harness.layout.game_help_fields)
      check(tips.any? { |tip| tip.include?("Shift+Z") } && tips.any? { |tip| tip.include?("DELETE") }, "Local help does not describe active game shortcuts")
      form = harness.layout.form
      form.index = form.fields.index(harness.layout.chat)
      harness.layout.chat.set_text("Untouched draft")
      count = SpeechOutput.calls.length
      harness.press(0x49)
      harness.press(0x5A)
      harness.press(0x20)
      equal([], harness.actions, "Typing in chat activated a game action")
      equal(count, SpeechOutput.calls.length, "Typing in chat activated a game announcement")
      check($native_tutorial_driver.modal_forms.empty?, "Typing opened a chooser")
      equal([], GameRoomContextHelp.game_field_tips([harness.layout.chat]), "Game shortcut help leaked into chat")
    end
  end
end

{
  ListBox.instance_method(:initialize) => "ui/controls/list_box.rb",
  ListBox.instance_method(:update) => "ui/controls/list_box.rb",
  EditBox.instance_method(:update) => "ui/controls/edit_box.rb",
  EditBox.instance_method(:focus) => "ui/controls/edit_box.rb",
  Form.instance_method(:wait) => "ui/form.rb",
  EltenAPI::KeyboardState.method(:update) => "eapi/keyboard.rb"
}.each do |native_method, relative|
  expected = File.join(EltenTestHost.root, "src", relative)
  MilleBornesTest.equal(expected, File.expand_path(native_method.source_location.first), "UI verification replaced a native method")
end

languages = ENV.key?("MILLE_BORNES_LANGUAGE") ? [ENV.fetch("MILLE_BORNES_LANGUAGE")] : %w[en pl]
raise "MILLE_BORNES_LANGUAGE must be en or pl" unless (languages - %w[en pl]).empty?
languages.each do |language|
  GameRoomTestLocalization.use_language(language)
  MilleBornesUIVerification.run
  MilleBornesUIVerification.instant_repair_tests
end

if ENV["MILLE_BORNES_BINARY"] == "1"
  %w[
    games/mille_bornes.rb games/mille_bornes/model.rb games/mille_bornes/presentation.rb
    games/mille_bornes/deck_options.rb games/mille_bornes/bots.rb
    games/generated/rulebooks/mille_bornes.rb lib/game_rules_view.rb lib/game_room_screens.rb
    lib/game_surfaces.rb lib/game_surfaces/card_actions.rb lib/game_surfaces/composite_surface.rb
  ].each do |relative|
    raise "Not loaded from binary source: #{relative}" unless MilleBornesUISources::LOADED.include?(File.join(MilleBornesUISources::ROOT, relative))
  end
end
puts "PASS native Mille Bornes UI (binary=#{ENV['MILLE_BORNES_BINARY'] == '1'}), languages=#{languages.join(',')} using current MO catalogs"
puts "Host: #{EltenTestHost.root}; isolated native controls and captured speech, not live NVDA/audio or a packaged release"
