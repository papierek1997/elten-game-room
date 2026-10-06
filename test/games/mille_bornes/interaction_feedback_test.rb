if ARGV.first
  require_relative "../../support/binary_rules_load"
end
require_relative "../../support/ui"
require_relative "../../support/localization"
require_relative "../../support/mille_bornes"
require_relative "../../../lib/game_surfaces"
include MilleBornesTest
GameRoomTestLocalization.use_language("en")

test("two-player Enter targets the sole opponent without a chooser") do
  GameRoomGames::MilleBornes::HAZARDS.each do |type|
    fixture = Fixture.new(players: %w[Alice Bob], options: { "counterflow" => true })
    state = fixture.scenario
    state[:hands]["Alice"] = ["#{type}:1", "25:1"]
    state[:tracks][1][:moving] = true
    replay = fixture.snapshot(state)
    card = fixture.game.surface_spec(replay, "Alice").zones.first.cards.first
    equal([], card.choices, "#{type}: the only opponent must not require selection")
    surface = GameSurfaces.build(fixture.game.surface_spec(replay, "Alice"))
    emitted = []
    surface.on_action { |action| emitted << action }
    surface.fields.first.trigger(:select, [0])
    equal(1, emitted.length, "#{type}: Enter submits exactly once")
    assert(!surface.cancel_pending_action?, "#{type}: no hidden target chooser remains")
    equal("play|#{type}:1|1", emitted.first["card"], "#{type}: concrete opponent is serialized")
    equal(:ok, fixture.game.action_for(emitted.first, replay, "Alice").first, "#{type}: normal validation accepts the attack")
    navigation = fixture.game.playable_card_navigation(replay, "Alice")
    equal(["#{type}:1"], navigation[:automatic_card_ids], "#{type}: unambiguous navigation agrees with Enter")
    safety = GameRoomGames::MilleBornes::PROTECTION.fetch(type)
    state[:tracks][1][:safeties] << safety
    equal(:invalid, fixture.game.action_for(emitted.first, fixture.snapshot(state), "Alice").first,
      "#{type}: a stale target still requires revalidation")
  end
end

test("one remaining legal target in a larger game still requires a choice") do
  fixture = Fixture.new
  state = fixture.scenario
  state[:hands]["Alice"] = %w[stop:1 25:1]
  state[:tracks][1][:moving] = true
  state[:tracks][2][:safeties] << "right_of_way"
  replay = fixture.snapshot(state)
  card = fixture.game.surface_spec(replay, "Alice").zones.first.cards.first
  equal(["1"], card.choices.map(&:id), "multi-player target remains explicit")
  equal([], fixture.game.playable_card_navigation(replay, "Alice")[:automatic_card_ids], "no multi-player auto attack")
  surface = GameSurfaces.build(fixture.game.surface_spec(replay, "Alice"))
  emitted = []
  surface.on_action { |action| emitted << action }
  surface.fields.first.trigger(:select, [0])
  assert(surface.cancel_pending_action?, "multi-player Enter opens its chooser")
  equal([], emitted, "opening a target chooser is not a move")
end

test("every distance history entry reports the resulting mileage, including reverse and zero") do
  GameRoomGames::MilleBornes::DISTANCES.each do |type|
    [[200, false], [200, true], [25, true], [0, true], [1000 - type.to_i, false]].each do |initial, reverse|
      fixture = Fixture.new(players: %w[Alice Bob], options: { "counterflow" => true })
      state = fixture.scenario
      state[:hands]["Alice"] = ["#{type}:1", "fuel:1"]
      state[:tracks][0].merge!(moving: true, miles: initial, counterflow: reverse)
      selection = { "kind" => "card", "action" => "play", "card" => "#{type}:1" }
      status, plan = fixture.game.action_for(selection, fixture.snapshot(state), "Alice")
      equal(:ok, status, "distance selection remains legal")
      history = []
      command = plan.events.fetch(0)
      assert(fixture.game.send(:apply_event, state, event(99, "Alice", command.action, command.value), "Alice", 99, history),
        "accepted distance event produces history")
      resulting = [initial + (reverse ? -type.to_i : type.to_i), 0].max
      equal(resulting, state[:tracks][0][:miles], "distance rules unchanged")
      entries = history.select { |entry| entry.kind == :play }
      equal(1, entries.length, "one announcement per accepted distance card")
      expected = "Alice played #{type} miles, now at #{resulting} miles."
      equal(expected, entries.first.text, "distance history uses post-move mileage")
      state[:tracks][0][:miles] = 0
      equal(expected, entries.first.text, "later state changes cannot rewrite the earlier mileage")
    end
  end
end

test("team distance announcements use the shared track and the actual actor") do
  fixture = Fixture.new(players: %w[Alice Bob Carol Dave], options: { "team_count" => 2 })
  state = fixture.scenario
  unit = fixture.game.send(:unit_for, state, "Alice")
  state[:tracks][unit].merge!(moving: true, miles: 350)
  state[:hands]["Alice"] = %w[100:1 fuel:1]
  history = []
  selection = { "kind" => "card", "action" => "play", "card" => "100:1" }
  status, plan = fixture.game.action_for(selection, fixture.snapshot(state), "Alice")
  equal(:ok, status, "team distance remains legal")
  command = plan.events.fetch(0)
  assert(fixture.game.send(:apply_event, state, event(99, "Alice", command.action, command.value), "Alice", 99, history), "team event accepted")
  equal("Alice played 100 miles, now at 450 miles.", history.find { |entry| entry.kind == :play }.text, "actor and shared mileage")
end

test("resulting mileage is translated from real catalogs in all supported languages") do
  messages = {
    "en" => "Żaneta played 25 miles, now at 125 miles.",
    "pl" => "Żaneta zagrywa kartę 25 mil, mając przejechane 125 mil.",
    "cs" => "Żaneta zahrál kartu 25 mil a nyní má ujeto 125 mil.",
    "es" => "Żaneta jugó 25 millas y ahora lleva 125 millas.",
    "ru" => "Żaneta разыгрывает 25 миль, теперь у него 125 миль."
  }
  messages.each do |language, expected|
    GameRoomTestLocalization.use_language(language)
    fixture = Fixture.new(players: ["Żaneta", "Bob"])
    state = fixture.scenario
    state[:tracks][0].merge!(moving: true, miles: 100)
    state[:hands]["Żaneta"] = %w[25:1 fuel:1]
    selection = { "kind" => "card", "action" => "play", "card" => "25:1" }
    status, plan = fixture.game.action_for(selection, fixture.snapshot(state), "Żaneta")
    equal(:ok, status, "localized distance action stays legal")
    command = plan.events.fetch(0)
    played = event(99, "Żaneta", command.action, command.value)
    history = []
    assert(fixture.game.send(:apply_event, state, played, "Żaneta", 99, history), "localized distance event accepted")
    replay = fixture.snapshot(state)
    replay.history = history
    equal([expected], fixture.game.describe_event(played, fixture.repository, replay, "Bob"), "#{language}: visible event description")
    equal([expected], fixture.game.describe_event(played, fixture.repository, replay, "Observer"), "#{language}: observer sees the same public mileage")
    assert((history.first.text + " — żółty").valid_encoding?, "#{language}: history remains UTF-8")
  end
  GameRoomTestLocalization.use_language("en")
end

test("Polish safety reactions announce the dirty trick before the card and its rewards") do
  GameRoomTestLocalization.use_language("pl")
  GameRoomGames::MilleBornes::PROTECTION.each do |hazard, safety|
    fixture = Fixture.new(players: ["Alice", "Żaneta"], options: { "counterflow" => true })
    state = fixture.scenario
    state[:hands]["Alice"] = ["#{hazard}:1", "25:1"]
    state[:hands]["Żaneta"] = ["#{safety}:1", "50:1"]
    state[:tracks][1][:moving] = true
    equal(:ok, fixture.play(state, "Alice", "play", "#{hazard}:1", target: "1"), "attack remains legal")
    selection = { "kind" => "card", "action" => "dirty_trick", "card" => "#{safety}:1", "reaction" => state[:reaction][:token] }
    status, plan = fixture.game.action_for(selection, fixture.snapshot(state), "Żaneta", context: fixture.context)
    equal(:ok, status, "matching safety remains legal")
    command = plan.events.fetch(0)
    played = event(999, "Żaneta", command.action, command.value)
    history = []
    assert(fixture.game.send(:apply_event, state, played, "Żaneta", 999, history), "reaction is accepted")
    label = fixture.game.send(:card_label, "#{safety}:1")
    expected = "Nieczysta zagrywka! Żaneta zagrywa kartę #{label}. Otrzymuje 300 punktów premii i możliwość rozegrania dodatkowej tury!"
    equal([expected], history.select { |entry| entry.kind == :dirty_trick }.map(&:text), "reaction wording and order")
    replay = fixture.snapshot(state)
    replay.history = history
    equal([expected], fixture.game.describe_event(played, fixture.repository, replay, "Observer"), "one public announcement")
    equal("Żaneta", state[:current_player], "extra turn unchanged")
    equal(1, state[:tracks][1][:dirty_tricks], "bonus awarded once")
    equal(400, fixture.game.participant_scores(replay)["Żaneta"], "100 safety points plus 300 bonus")
  end
  GameRoomTestLocalization.use_language("en")
end
