require_relative "../../support/ui"
require_relative "../../support/mille_bornes"
require_relative "../../../lib/game_surfaces"
include MilleBornesTest

test("counterflow cards preserve shared hand identity, semantic sorting, navigation and public status") do
  fixture = Fixture.new(options: { "counterflow" => true, "counterflow_cards" => 3, "end_counterflow_cards" => 4 })
  state = fixture.scenario
  state[:hands]["Alice"] = %w[counterflow:2 end_counterflow:1 25:1 counterflow:1]
  state[:tracks][0].merge!(moving: true, counterflow: true, miles: 100)
  replay = fixture.snapshot(state)
  game = fixture.game
  spec = game.surface_spec(replay, "Alice")
  zone = spec.zones.first
  equal(state[:hands]["Alice"], zone.hand_order, "acquisition order uses physical IDs")
  equal(zone.hand_order, zone.cards.map(&:id), "default order unchanged")
  equal(["Counterflow", "End of counterflow", "25 miles", "Counterflow"], zone.cards.map(&:label), "labels support variant cards")
  equal(1, zone.cards.first.sort_keys["colour"].first, "counterflow is a hazard")
  equal(2, zone.cards[1].sort_keys["colour"].first, "end of counterflow is a remedy")
  zone.cards.each { |card| assert(card.sort_keys["number"].first.is_a?(Integer), "all cards have semantic numeric rank") }
  equal(zone.cards.first.sort_keys["number"].first, zone.cards.last.sort_keys["number"].first, "copies share type rank")
  navigation = game.playable_card_navigation(replay, "Alice")
  equal(zone.hand_order.sort, navigation[:card_actions].keys.sort, "all legal physical cards available to Z")
  equal(%w[end_counterflow:1 25:1], navigation[:automatic_card_ids], "targeted attacks never automatic")
  equal(%w[1 2], zone.cards.first.choices.map(&:id), "stopped opponents included in attack choices")
  before = Marshal.dump(state)
  surface = GameSurfaces.build(spec)
  emitted = []
  surface.on_action { |action| emitted << action }
  %w[number colour none].each do |mode|
    assert(surface.handle_command("sort_cards", { "mode" => mode, "toggle" => true }), "shared #{mode} sorting works")
  end
  equal(before, Marshal.dump(state), "sorting does not mutate game state")
  equal(zone.hand_epoch, game.surface_spec(replay, "Alice").zones.first.hand_epoch, "sort does not change hand epoch")
  shortcut = game.game_shortcuts(replay, "Alice").find { |item| item.key == "z" && item.modifiers.empty? }
  assert(shortcut, "shared forward playable-card navigation exists")
  assert(game.game_shortcuts(replay, "Alice").any? { |item| item.key == "z" && item.modifiers.include?(:shift) }, "shared backward navigation exists")
  status = game.participant_status(replay, "Alice")
  assert(status.include?("Counterflow") && status.include?("Moving"), "status announces independent effect without claiming stopped")
  equal([], game.surface_spec(replay, "Observer").zones.first.cards, "observer has no access to new cards in hands")
  surface.fields.first.index = 0
  surface.fields.first.trigger(:select, [0])
  assert(surface.cancel_pending_action?, "counterflow opens target chooser")
  surface.cancel_pending_action!
  equal([], emitted, "cancellation does not play a card")
  surface.fields.first.trigger(:select, [0])
  surface.fields.first.trigger(:select, [0])
  equal(:ok, game.action_for(emitted.last, replay, "Alice").first, "native target choice yields legal attack")
  state[:tracks][1][:safeties] << "driving_ace"
  equal(:invalid, game.action_for(emitted.last, fixture.snapshot(state), "Alice").first, "target immunity revalidated after chooser")
  state[:current_player] = "Alice"
  equal(:ok, fixture.play(state, "Alice", "play", "end_counterflow:1"), "remedy follows normal action path")
  assert(!game.participant_status(fixture.snapshot(state), "Alice").include?("Counterflow"), "cleared effect disappears from status")
end

test("native card surface emits a legal play and preserves acquisition order") do
  fixture = Fixture.new
  state = fixture.scenario
  state[:hands]["Alice"] = %w[go:1 25:2 25:1 100:1]
  replay = fixture.snapshot(state)
  spec = fixture.game.surface_spec(replay, "Alice")
  equal(state[:hands]["Alice"], spec.zones.first.hand_order, "acquisition order")
  equal(state[:hands]["Alice"], spec.zones.first.cards.map(&:id), "default order")
  equal(4, spec.zones.first.cards.map(&:id).uniq.length, "identical labels retain physical IDs")
  surface = GameSurfaces.build(spec)
  emitted = []
  surface.on_action { |action| emitted << action }
  surface.fields.first.trigger(:select, [0])
  equal(1, emitted.length, "Enter emits exactly once")
  equal(:ok, fixture.game.action_for(emitted.first, replay, "Alice").first, "surface event validates")
  equal("play|go:1|", emitted.first["card"], "wire card choice")
  prior = Marshal.dump(state)
  assert(surface.handle_command("sort_cards", { "mode" => "number", "toggle" => true }), "manual sort available")
  equal(prior, Marshal.dump(state), "sorting does not mutate rules")
  surface.fields.first.index = 1
  state[:hands]["Alice"] << "50:1"
  surface.update_spec(fixture.game.surface_spec(fixture.snapshot(state), "Alice"))
  equal("50 miles", surface.take_cursor_announcement(0), "newly drawn card announced")
  surface.update_spec(fixture.game.surface_spec(fixture.snapshot(state), "Alice"))
  equal(nil, surface.take_cursor_announcement(0), "unchanged hand silent")
end

test("target chooser revalidates after changes and can be cancelled") do
  fixture = Fixture.new
  state = fixture.scenario
  state[:hands]["Alice"] = %w[stop:1 25:1]
  state[:tracks][1][:moving] = true
  state[:tracks][2][:moving] = true
  replay = fixture.snapshot(state)
  spec = fixture.game.surface_spec(replay, "Alice")
  card = spec.zones.first.cards.first
  equal(%w[1 2], card.choices.map(&:id), "opponents only")
  surface = GameSurfaces.build(spec)
  emitted = []
  surface.on_action { |action| emitted << action }
  surface.fields.first.trigger(:select, [0])
  assert(surface.cancel_pending_action?, "Enter opens target chooser")
  equal([], emitted, "opening chooser is not a move")
  assert(surface.fields.first.options.first.include?("Bob"), "target has accessible identity")
  surface.cancel_pending_action!
  equal("Red light", surface.fields.first.options.first, "cancel restores hand")
  surface.fields.first.trigger(:select, [0])
  surface.fields.first.trigger(:select, [1])
  equal(:ok, fixture.game.action_for(emitted.last, replay, "Alice").first, "target choice valid")
  state[:tracks][2][:safeties] << "right_of_way"
  equal(:invalid, fixture.game.action_for(emitted.last, fixture.snapshot(state), "Alice").first, "stale target checked again")
  navigation = fixture.game.playable_card_navigation(fixture.snapshot(state), "Alice")
  equal([], navigation[:automatic_card_ids], "targeted card never automatic")
end

test("contextual shortcuts, discard even legal card and observer privacy") do
  fixture = Fixture.new
  replay = fixture.start
  game = fixture.game
  shortcuts = game.game_shortcuts(replay, "Alice")
  assert(shortcuts.any? { |shortcut| shortcut.key == "space" }, "draw shortcut before draw")
  assert(shortcuts.none? { |shortcut| shortcut.key == "delete" }, "no discard before draw")
  state = fixture.scenario
  state[:hands]["Alice"] = %w[go:1 25:1]
  shortcuts = game.game_shortcuts(fixture.snapshot(state), "Alice")
  assert(shortcuts.none? { |shortcut| shortcut.key == "space" }, "no second draw")
  equal(shortcuts.length, shortcuts.map { |shortcut| [shortcut.key, shortcut.modifiers] }.uniq.length, "no shortcut conflicts")
  %w[i s t h z delete].each { |key| assert(shortcuts.any? { |shortcut| shortcut.key == key }, "missing #{key}") }
  discard = shortcuts.find { |shortcut| shortcut.key == "delete" }
  assert(discard.choices.any? { |choice| choice.value == "go:1" }, "legal card can be discarded")
  equal(:ok, game.action_for({ "kind" => discard.action_kind, "action" => discard.action_name, "card" => "go:1" }, fixture.snapshot(state), "Alice").first, "discard chooser action")
  observer = game.surface_spec(fixture.snapshot(state), "Observer")
  equal([], observer.zones.first.cards, "observer cannot see hands")
  equal([], game.legal_actions(fixture.snapshot(state), "Observer"), "observer has no moves")
  assert(game.game_shortcuts(fixture.snapshot(state), "Observer").none? { |shortcut| %w[delete space].include?(shortcut.key) }, "observer has no playing shortcuts")
end

test("playable navigation excludes discard and disables racing automation") do
  fixture = Fixture.new
  state = fixture.scenario
  state[:hands]["Alice"] = %w[go:1 25:1]
  game = fixture.game
  navigation = game.playable_card_navigation(fixture.snapshot(state), "Alice")
  equal(["go:1"], navigation[:card_actions].keys, "only playable cards")
  equal(["go:1"], navigation[:automatic_card_ids], "unambiguous green light can auto-play")
  surface = GameSurfaces.build(game.surface_spec(fixture.snapshot(state), "Alice"))
  shortcut = game.game_shortcuts(fixture.snapshot(state), "Alice").find { |item| item.key == "z" && item.modifiers.empty? }
  result = surface.handle_command(shortcut.action_name, shortcut.payload)
  assert(result.is_a?(GameSurfaces::Action), "navigation emits standard action")
  equal(:ok, game.action_for(result, fixture.snapshot(state), "Alice").first, "automatic action validated")
  state[:hands]["Alice"] = %w[right_of_way:1 25:1]
  state[:reaction] = { unit: 0, hazard: "stop", token: "1:1", before: game.send(:fresh_track) }
  equal(nil, game.playable_card_navigation(fixture.snapshot(state), "Alice"), "no navigation advantage in reaction race")
end

test("new round, session and owner invalidate hand epoch") do
  fixture = Fixture.new
  state = fixture.scenario
  game = fixture.game
  replay = fixture.snapshot(state)
  original = game.surface_spec(replay, "Alice").zones.first.hand_epoch
  replay.session_identity = 999
  assert(original != game.surface_spec(replay, "Alice").zones.first.hand_epoch, "new session resets hand cursor")
  replay.session_identity = fixture.session["id"]
  state[:round] += 1
  assert(original != game.surface_spec(replay, "Alice").zones.first.hand_epoch, "new round resets cursor")
  assert(original != game.surface_spec(replay, "Bob").zones.first.hand_epoch, "different hand owner")
end
