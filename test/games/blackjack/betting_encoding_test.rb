require_relative "../../support/game_option_encoding"

repository = Struct.new(:players) do
  def players_for(_session); players; end
  def actor_of(event, _session); event.fetch("actor"); end
  def event_id(event); event.fetch("id"); end
end.new(%w[Alice Bob])
checks = {forms: 0, checkbox_states: 0, labels: 0}
%w[en pl ru].each do |language|
  $option_host_language = language
  GameRoomTestLocalization.use_language(language)
  [GameRoomGames::Blackjack.new, GameRoomGames::BlackjackDice.new].each do |game|
    session = {"options" => JSON.generate(game.new_game_options("scoring" => "chips"))}
    replay = game.replay(session, [{"id" => 1, "actor" => "Alice", "action" => "ante", "value" => ""}], repository)
    surface = GameSurfaces.build(game.surface_spec(replay, "Alice"))
    button = Button.new("OK")
    form = GameRoomUI::Form.new(surface.fields + [button], program: EltenGameRoom.allocate, quiet: true)
    form.accept_button = button
    GameOptionEncodingFixture.driver(checks).call(form)
    selected = nil
    surface.on_action { |action| selected = action }
    surface.fields.first.trigger(:select, [0])
    raise "Binary betting surface cannot submit a preset" unless selected && game.action_for(selected.to_h, replay, "Alice").first == :ok
    shortcut = game.game_shortcuts(replay, "Alice").find { |item| item.key == "b" }
    raise "Missing numeric betting shortcut" unless shortcut
    [shortcut.label, shortcut.prompt, shortcut.invalid_message].compact.each do |label|
      label + " — выбранное поле"
    end
    if language == "pl"
      raise "Betting header was not translated" unless surface.fields.first.header.start_with?("Licytacja:")
    end
  end
end
puts "Blackjack binary betting controls: EN, PL and untranslated EN with Russian host passed (#{checks[:forms]} forms)"
