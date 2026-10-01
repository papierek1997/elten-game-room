# Binary sources and the real ELTEN dictionary, including its binary msgstrs.
require_relative "../support/binary_rule_dictionary"

%w[pl en fallback].each do |language|
  $rules_english = language != "pl"
  GameRoomTestLocalization.use_language(language)
  entry = GameRoomParticipantMenu.entries.find { |item| item.action == :table_options }
  history_entry = GameRoomParticipantMenu.entries.find { |item| item.action == :save_table_history }
  expected = language == "pl" ? "Ctrl+R, Odczytaj wariant i ustawienia stołu." : "Ctrl+R, Read the table variant and settings."
  expected_history = language == "pl" ? "Zapisz historię stołu" : "Save table history"
  raise "Incorrect table history translation" unless history_entry.label == expected_history
  raise "Incorrect table history shortcut" unless history_entry.menu_key == "S" && history_entry.help_key == "Ctrl+Shift+S"
  field = ListBox.new(["card"], header: "Hand")
  field.define_singleton_method(:add_tip) { |_| }
  form = GameRoomUI::Form.new([field])
  layout = Struct.new(:form, :back_button).new(form, nil)
  GameRoomParticipantMenu.add_context_help(layout, [:table_options])
  raise "Incorrect short table help: #{field.get_tips.inspect}" unless field.get_tips == [expected]
  raise "Double punctuation" unless GameRoomContextHelp.shortcut_tip(entry.help_key, entry.label + ".") == expected
  raise "Binary shortcut label" unless (field.get_tips.first + " — skrót").valid_encoding?

  game = GameRoomGames::Makao.new
  state = game.send(:initial_state, %w[Alice Bob], game.default_options)
  state.update(phase: :playing, current_player: "Alice", hands: {"Alice"=>%w[5C 5D], "Bob"=>%w[6C]}, discard:["4C"])
  replay = GameRoomGames::Replay.new(players:state[:players],state:state,current_player:"Alice")
  shortcuts = game.game_shortcuts(replay,"Alice")
  screen = GameScreen.allocate
  screen.send(:bind_game_shortcuts, form, [field], shortcuts) { raise "Help invoked a move" }
  tips = GameRoomContextHelp.game_field_tips([field])
  wanted = shortcuts.map { |s| GameRoomContextHelp.shortcut_tip(GameRoomShortcutBindings.key_label(s),s.label) }
  raise "Rules and F1 disagree" unless tips == wanted && wanted.all? { |tip| field.get_tips.include?(tip) }
  raise "Verbose wrapper retained" if tips.any? { |tip| tip.start_with?("Press ","Naciśnij ") || tip.include?(", aby:") }
end
puts "PASS concise F1/rules help: common table/game descriptions, PL/EN/fallback, binary sources, same keys and no duplicate punctuation"
