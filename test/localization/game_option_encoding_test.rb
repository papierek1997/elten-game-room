require_relative "../support/game_option_encoding"

app = EltenGameRoom.allocate
app.define_singleton_method(:read_json) { |_path, default:| default }
app.define_singleton_method(:remember_multiple_choice_options) { |*_arguments| }
app.define_singleton_method(:alert) { |message| raise message }
checks = { forms: 0, checkbox_states: 0, labels: 0 }
Form.option_encoding_driver = GameOptionEncodingFixture.driver(checks)

# Reversi/Russian first reproduces the real failure before any stricter
# encoding assertions, with the untranslated em dash in Mandatory capture.
ids = ["reversi"] + (EltenGameRoom::GAME_REGISTRY.ids - ["reversi"])
%w[ru en pl].each do |language|
  $option_host_language = language
  GameRoomTestLocalization.use_language(language)
  ids.each do |id|
    game = EltenGameRoom::GAME_REGISTRY.build(id)
    actual = app.send(:configure_game_options, game)
    raise "Encoding fix changed defaults for #{id}" unless actual == game.default_options
    if %w[axel_pong audio_ball].include?(id)
      changed = game.normalize_options('p2p_enabled' => true, 'p2p_participants_limit' => 8)
      actual = app.send(:configure_game_options, game, initial_options: changed, submit_label: "Save changes")
      raise "Editing P2P changed selected options" unless actual == changed
    end
    if id == "tysiac"
      %w[2 3].product([false, true]).each do |size, award|
        changed = game.normalize_options("variant" => "two_players", "talon_size" => size, "last_trick_talon" => award)
        actual = app.send(:configure_game_options, game, initial_options: changed, submit_label: "Save changes")
        raise "Editing Tysiac changed selected variants" unless actual == changed
      end
    end
    if id == "mille_bornes"
      [true, false].each do |enabled|
        changed = game.normalize_options("include_safeties" => enabled)
        actual = app.send(:configure_game_options, game, initial_options: changed, submit_label: "Save changes")
        raise "Editing Mille Bornes changed selected safeties" unless actual == changed
        raise "Safety option did not change the deck" unless game.send(:deck_for, actual).length == (enabled ? 106 : 102)
      end
    end
    next unless id == "reversi"

    changed = game.normalize_options("allow_passing" => false, "mandatory_capture" => false)
    actual = app.send(:configure_game_options, game, initial_options: changed, submit_label: "Save changes")
    raise "Editing Reversi changed selected variants" unless actual == changed
  end
end

label = "Capture — żółty".b.freeze
value = "stable-value".b.freeze
choice = GameRoomGames::OptionChoice.new(value: value, label: label)
definition = GameRoomGames::OptionDefinition.new(key: value, label: label, kind: :choice,
  default: value, choices: [choice], visible_if: { "enabled" => true })
raise "Encoding fix mutated a frozen source string" unless label.encoding == Encoding::ASCII_8BIT
raise "Encoding fix changed option identity" unless definition.key.equal?(value) && definition.default.equal?(value) && choice.value.equal?(value)
[definition.label, choice.label].each do |text|
  raise "Lost option label characters" unless text == "Capture — żółty" && text.encoding == Encoding::UTF_8
end

puts "Binary game-option focus passed: #{checks[:forms]} forms, #{checks[:checkbox_states]} checkbox states, #{checks[:labels]} labels; untranslated EN with RU host, EN and PL"
