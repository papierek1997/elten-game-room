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
  %w[30 75 80 90].each do |variant|
    game = GameRoomGames::Bingo.new
    session = {"options" => JSON.generate(game.normalize_options("variant" => variant, "marking" => "manual"))}
    events = [{"id" => 1, "actor" => "Alice", "action" => "start", "value" => 'a' * 32},
      {"id" => 2, "actor" => "Alice", "action" => "draw", "value" => "1"}]
    [[], events.take(1)].each do |prefix|
      waiting = game.replay(session, prefix, repository)
      game.game_shortcuts(waiting, "Alice")
      GameSurfaces.build(game.surface_spec(waiting, "Alice"))
    end
    replay = game.replay(session, events, repository)
    spec = game.surface_spec(replay, "Alice")
    spec.parts.first.surface.cells.flatten.each do |label|
      raise "Ticket label is not UTF-8" unless label.encoding == Encoding::UTF_8
      label + " — выбранное поле"
    end
    surface = GameSurfaces.build(spec)
    raise "Missing ticket grid and actions" unless surface.fields.size == 2
    raise "Bingo ticket became a card hand" if game.playable_card_navigation(replay, "Alice")
    selected = nil
    surface.on_action { |action| selected = action }
    actions = spec.parts.last.surface.items
    raise "Bingo offered an incomplete claim" if actions.any? { |item| item.id == "claim" }
    raise "Bingo advertised the claim shortcut early" if game.game_shortcuts(replay, "Alice").any? { |shortcut| shortcut.key == "b" }
    ready = actions.index { |item| item.id == "ready" }
    raise "Missing ready command" unless ready
    surface.fields.last.index = ready
    surface.fields.last.trigger(:select, [ready])
    raise "Ready does not follow the standard action path" unless selected && game.action_for(selected.to_h, replay, "Alice").first == :ok
    button = Button.new("OK")
    form = GameRoomUI::Form.new(surface.fields + [button], program: EltenGameRoom.allocate, quiet: true)
    form.accept_button = button
    GameOptionEncodingFixture.driver(checks).call(form)
    game.game_shortcuts(replay, "Alice").each { |s| s.label + " — выбранное поле" }
    spectator = GameSurfaces.build(game.surface_spec(replay, "Observer"))
    raise "Spectator can play" unless game.legal_actions(replay, "Observer").empty? && spectator.fields.one?
    remembered = surface.state
    restored = GameSurfaces.build(game.surface_spec(replay, "Alice"), state: remembered)
    raise "Surface state was lost" unless restored.state == remembered
  end
end
puts "Bingo binary surfaces: 12 ticket/action forms, ready writes, spectators, shortcuts and restored focus passed"
