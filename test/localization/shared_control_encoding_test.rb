require_relative "../support/binary_rule_dictionary"

[false, true].each do |english|
  $rules_english = english
  GameRoomTestLocalization.use_language(english ? :en : :pl)
  [GameRoomGames::Makao.new, GameRoomGames::Poker.new].each do |game|
    state = game.send(:initial_state, %w[Alice Bob], game.default_options)
    state.update(hands: { "Alice" => %w[9H 9S AS], "Bob" => %w[2S] },
      current_player: "Alice", phase: game.id == "poker" ? :exchange : :playing)
    state[:discard] = ["8H"] if game.id == "makao"
    replay = GameRoomGames::Replay.new(players: state[:players], current_player: "Alice", state: state, history: [], accepted_events: [])
    surface = GameSurfaces.build(game.surface_spec(replay, "Alice"))
    source = game.id == "makao" ? "Press Shift+Enter to add or remove the current card from the prepared packet." :
      "Press Shift+Enter to select or unselect the current card for exchange."
    expected = english ? source : RULES_CATALOG.fetch(source)
    tips = surface.fields.flat_map { |field| field.respond_to?(:get_tips) ? field.get_tips : [] }
    raise "Missing/duplicate translated packet shortcut" unless tips.count(expected) == 1
    if game.id == "poker"
      raise "Poker received Makao help" if tips.any? { |tip| tip.include?("packet") || tip.include?("paczki") }
    end
    # A host may append its translated role to an English fallback.
    tips.each do |tip|
      text = tip + " — справка"
      raise "Binary packet tip is invalid" unless text.valid_encoding?
    end
    shortcuts = game.game_shortcuts(replay, "Alice")
    %w[c h].each do |key|
      selected = shortcuts.select { |item| item.key == key && item.modifiers == [:shift] }
      raise "Sorting F1 shortcut missing/duplicated" unless selected.length == 1
      label = selected.first.label
      raise "Untranslated sorting help" unless english || RULES_CATALOG.values.include?(label)
    end
    raise "Removed sorting shortcut remains in F1" if shortcuts.any? { |item| item.key == 'm' && item.modifiers == [:shift] }
  end
end
puts "PASS binary UI: Makao/Poker packet F1 and shared sorting help in PL/EN beside a non-English host"
