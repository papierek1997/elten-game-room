require_relative "../../support/elten_array_shuffle"
require_relative "../../support/mille_bornes"
require_relative "../../support/private_archives"
require_relative "../../../lib/account_saved_games"
include MilleBornesTest

module CustomReplayTest
  Snapshot = Struct.new(:session, :events)
  module_function

  def counted_options(counts, flags = {})
    GameRoomGames::MilleBornes::CARD_ORDER.to_h { |type| ["#{type}_cards", counts.fetch(type, 0)] }
      .merge("custom_deck" => true).merge(flags)
  end

  def repair_fixture(problem)
    options = { "custom_deck" => true, "include_safeties" => false, "counterflow" => true,
      "include_instant_repairs" => true, "instant_repair_cards" => 6, "accumulate_hazards" => true,
      "flat_tire_cards" => 10, "speed_limit_cards" => 10, "25_cards" => 13 }
    bot = GameRoomParticipants.bot_id(17, 1, name_token: "en03")
    fixture = MilleBornesTest::Fixture.new(players: ["Alice", bot], options: options)
    fixture.start
    unless problem == "go"
      %w[accident speed_limit].each do |hazard|
        fixture.act("Alice", { "kind" => "command", "action" => "draw" })
        card = fixture.replay.state[:hands]["Alice"].find { |value| !value.start_with?("instant_repair:") }
        fixture.act("Alice", { "kind" => "card", "action" => "discard", "card" => card })
        fixture.act(bot, { "kind" => "command", "action" => "draw" })
        card = fixture.replay.state[:hands][bot].find { |value| value.start_with?("#{hazard}:") }
        MilleBornesTest.assert(card, "fixed seed must provide #{hazard} to the attacking bot")
        fixture.act(bot, { "kind" => "card", "action" => "play", "card" => card, "target" => "0" })
      end
    end
    fixture.act("Alice", { "kind" => "command", "action" => "draw" })
    card = fixture.game.surface_spec(fixture.replay, "Alice").zones.first.cards.find { |entry| entry.id.start_with?("instant_repair:") }
    MilleBornesTest.assert(card, "fixed seed must provide a physical joker")
    expected = problem == "go" ? ["go"] : %w[accident speed_limit]
    MilleBornesTest.equal(expected, card.choices.map(&:id), "real surface exposes each current problem independently")
    choice = card.choices.find { |entry| entry.id == problem }
    fixture.act("Alice", { "kind" => "card", "action" => "select", "card" => choice.value })
    fixture
  end

  def save(fixture)
    resources = PrivateArchiveDouble.new
    saves = AccountSavedGames.new(Object.new, owner: "Alice", resources: resources)
    snapshot = Snapshot.new(fixture.session, fixture.events)
    row = saves.put(game: fixture.game, table: { "owner" => "Alice", "name" => "Custom replay" },
      snapshot: snapshot, repository: fixture.repository, now: 1000)
    reader = AccountSavedGames.new(Object.new, owner: "Alice", resources: resources)
    MilleBornesTest.equal(row, reader.fetch(row.fetch("id")), "compressed private-resource archive verifies through a fresh reader")
    [reader, reader.fetch(row.fetch("id"))]
  end

  def remapped_state(replay, old_player, new_player)
    JSON.parse(JSON.generate(replay.state).gsub(old_player, new_player))
  end

  def distance_fixture(counts, spent:, hand:, miles:, two_hundreds: 0)
    options = counted_options(counts.merge("go" => 20), "recycle_discard" => true, "include_safeties" => false)
    fixture = MilleBornesTest::Fixture.new(options: options)
    state = fixture.scenario
    state[:hands] = { "Alice" => hand, "Bob" => ["go:1"], "Carol" => ["go:2"] }
    state[:spent] = spent + ["go:3"]
    state[:discard] = []
    state[:draw_pile] = fixture.game.send(:deck_for, options) - state[:spent] - state[:hands].values.flatten
    state[:tracks][0].merge!(moving: true, miles: miles, two_hundreds: two_hundreds)
    [fixture, state]
  end
end

test("custom archive restores the exact selected joker problem and continues after bot identity remapping") do
  %w[go accident speed_limit].each do |problem|
    fixture = CustomReplayTest.repair_fixture(problem)
    game = fixture.game
    before = fixture.replay
    saves, row = CustomReplayTest.save(fixture)
    equal(fixture.session.fetch("options"), row.fetch("options"), "custom option bytes saved without canonicalizing counts")
    equal(game.deck_counts_for(before.state[:options]), game.deck_counts_for(JSON.parse(row.fetch("options"))), "every effective custom count archived")
    equal("instant_repair:2|#{problem}", row.fetch("events").last.fetch("value"), "selected problem persisted in the joker event")
    original = Marshal.dump(row)
    data = saves.restored_data(row, game: game, table_id: 81, now: 2000)
    equal(original, Marshal.dump(row), "restoration leaves the archive immutable")
    equal(row.fetch("events").map { |entry| entry.fetch("value") }, data.fetch(:events).map { |entry| entry.fetch("value") }, "card IDs and problem values are not treated as player identities")
    old_bot = fixture.players.last
    new_bot = GameRoomParticipants.bot_id(81, 1, name_token: "en03")
    equal(["Alice", new_bot], data.fetch(:players), "only the native bot table identity changes")
    restored = Fixture.new(players: data.fetch(:players), options: JSON.parse(row.fetch("options")))
    restored.session["id"] = 81
    restored.events.concat(data.fetch(:events))
    after = restored.replay
    equal(row.fetch("events").length, after.accepted_events.length, "every archived event accepted")
    equal(CustomReplayTest.remapped_state(before, old_bot, new_bot), JSON.parse(JSON.generate(after.state)), "complete custom game state restored")
    equal(game.deck_counts_for(before.state[:options]), game.deck_counts_for(after.state[:options]), "restoration retains custom counts")
    track = after.state[:tracks][0]
    equal(problem == "speed_limit" ? ["accident"] : [], track[:hazards], "only the selected mechanical problem removed")
    equal(problem == "accident", track[:speed_limit], "unselected speed limit survives")
    equal(problem == "go", track[:moving], "mechanical repair does not invent a green light")
    equal(0, game.participant_scores(after).fetch("Alice"), "joker adds no safety points or bonus")
    next_action = { "kind" => "command", "action" => "draw" }
    expected = fixture.act(old_bot, next_action)
    actual = restored.act(new_bot, next_action)
    equal(CustomReplayTest.remapped_state(expected, old_bot, new_bot), JSON.parse(JSON.generate(actual.state)), "next move agrees with uninterrupted play")
    equal(actual.state, restored.replay.state, "continued replay remains deterministic")
  end
end

test("archive semantic validation rejects missing or inapplicable joker choices and altered custom counts") do
  fixture = CustomReplayTest.repair_fixture("accident")
  saves, row = CustomReplayTest.save(fixture)
  changes = [
    ->(changed) { changed["events"].last["value"] = "instant_repair:2" },
    ->(changed) { changed["events"].last["value"] = "instant_repair:2|out_of_gas" },
    ->(changed) { changed["events"].last["value"] = "instant_repair:2|accident|0" },
    ->(changed) { changed["options"] = JSON.generate(JSON.parse(changed["options"]).merge("instant_repair_cards" => 0)) }
  ]
  changes.each do |change|
    invalid = JSON.parse(JSON.generate(row))
    change.call(invalid)
    invalid["checksum"] = saves.send(:checksum, invalid)
    failure = nil
    begin
      saves.restored_data(invalid, game: fixture.game, table_id: 81, now: 2000)
    rescue ArgumentError => error
      failure = error
    end
    assert(failure && failure.message == "Incompatible saved game events", "semantic replay validation must reject the modified archive, not only its checksum")
  end
end

test("physical safety duplicates keep unique IDs but cannot score or play twice on one track") do
  GameRoomGames::MilleBornes::SAFETIES.each do |type|
    options = CustomReplayTest.counted_options("25" => 12, "go" => 2, type => 100)
    fixture = Fixture.new(players: %w[Alice Bob], options: options)
    game = fixture.game
    fixture.start
    fixture.act("Alice", { "kind" => "command", "action" => "draw" })
    copies = fixture.replay.state[:hands]["Alice"].select { |card| card.start_with?("#{type}:") }
    assert(copies.length >= 2 && copies.uniq == copies, "seed provides distinct physical safety copies")
    fixture.act("Alice", { "kind" => "card", "action" => "play", "card" => copies.first })
    fixture.act("Alice", { "kind" => "command", "action" => "draw" })
    before = fixture.replay
    duplicate = { "kind" => "card", "action" => "play", "card" => copies[1] }
    equal(:invalid, game.action_for(duplicate, before, "Alice", context: fixture.context).first, "owned safety cannot be played again")
    forged = event(fixture.events.length + 1, "Alice", "play", "#{copies[1]}|")
    replay = game.replay(fixture.session, fixture.events + [forged], fixture.repository)
    equal(before.state, replay.state, "forged duplicate safety event leaves state unchanged")
    equal(before.accepted_events, replay.accepted_events, "forged duplicate absent from accepted history")
    equal(100, game.participant_scores(before).fetch("Alice"), "only the first copy scores")
    fixture.act("Alice", { "kind" => "card", "action" => "discard", "card" => copies[1] })
    fixture.act("Bob", { "kind" => "command", "action" => "draw" })
    opponent_copy = fixture.replay.state[:hands]["Bob"].find { |card| card.start_with?("#{type}:") }
    assert(opponent_copy, "opponent has an independent safety copy")
    fixture.act("Bob", { "kind" => "card", "action" => "play", "card" => opponent_copy })
    current = fixture.replay
    equal({ "Alice" => 100, "Bob" => 100 }, game.participant_scores(current), "separate tracks can each own that safety")
    equal([[type], [type]], current.state[:tracks].map { |track| track[:safeties] }, "one safety per track")
    cards = current.state.values_at(:draw_pile, :discard, :spent).flatten + current.state[:hands].values.flatten
    equal(game.send(:deck_for, options).sort, cards.sort, "physical duplicates are conserved exactly")
    equal(cards.length, cards.uniq.length, "no physical ID reused")
    equal(current.state, fixture.replay.state, "accepted duplicate-card history replays deterministically")
  end
end

test("teammates cannot reuse a second safety for a dirty trick or a second safety award") do
  fixture = Fixture.new(players: %w[Alice Bob Carol Dave], options: { "custom_deck" => true, "team_count" => 2, "extra_tank_cards" => 2 })
  game = fixture.game
  state = fixture.scenario
  state[:hands] = { "Alice" => %w[out_of_gas:1 25:1], "Bob" => %w[extra_tank:1 25:2],
    "Carol" => %w[75:1 100:1], "Dave" => %w[extra_tank:2 50:1] }
  state[:tracks][1][:moving] = true
  equal(:ok, fixture.play(state, "Alice", "play", "out_of_gas:1", target: "1"), "attack the shared enemy track")
  token = state[:reaction][:token]
  %w[Bob Dave].each do |actor|
    available = game.legal_actions(fixture.snapshot(state), actor).select { |action| action["action"] == "dirty_trick" }
    equal([state[:hands][actor].first], available.map { |action| action["card"] }, "each teammate can use only their own physical safety")
  end
  equal(:ok, fixture.play(state, "Bob", "dirty_trick", "extra_tank:1", reaction: token), "first safety counters the attack")
  before = Marshal.dump(state)
  equal(:invalid, fixture.play(state, "Dave", "dirty_trick", "extra_tank:2", reaction: token), "second teammate cannot repeat the closed reaction")
  equal(before, Marshal.dump(state), "rejected duplicate reaction does not mutate state")
  equal(["extra_tank"], state[:tracks][1][:safeties], "one shared safety")
  equal(1, state[:tracks][1][:dirty_tricks], "one shared dirty-trick bonus")
  equal(400, game.participant_scores(fixture.snapshot(state)).fetch("Bob"), "shared track scores one safety and one bonus")
  equal(400, game.participant_scores(fixture.snapshot(state)).fetch("Dave"), "teammate sees the same score, not a second award")
  fixture.play(state, "Bob", "draw")
  fixture.play(state, "Bob", "discard", "25:2")
  fixture.play(state, "Carol", "draw")
  fixture.play(state, "Carol", "discard", "75:1")
  fixture.play(state, "Dave", "draw")
  equal(:invalid, fixture.play(state, "Dave", "play", "extra_tank:2"), "teammate cannot play the already-owned safety normally")
  equal(:ok, fixture.play(state, "Dave", "discard", "extra_tank:2"), "unusable physical copy remains discardable")
  equal(400, game.participant_scores(fixture.snapshot(state)).fetch("Dave"), "discarding a duplicate does not score")
end

test("exact-finish bot planning respects zero custom distances without inspecting unseen cards") do
  spent = Array.new(7) { |index| "100:#{index + 1}" } + ["75:1"]
  fixture, state = CustomReplayTest.distance_fixture({ "100" => 10, "75" => 4 },
    spent: spent, hand: %w[100:8 75:2], miles: 775)
  game = fixture.game
  replay = fixture.snapshot(state)
  actions = game.legal_actions(replay, "Alice")
  larger = actions.find { |action| action["action"] == "play" && action["card"] == "100:8" }
  viable = actions.find { |action| action["action"] == "play" && action["card"] == "75:2" }
  equal(:ok, game.action_for(larger, replay, "Alice", context: fixture.context).first, "strategy does not change legal mileage moves")
  equal(-20_000, game.bot_action_score(replay, "Alice", larger), "cannot invent absent 25/50-mile cards to fill the 125-mile gap")
  equal(475, game.bot_action_score(replay, "Alice", viable), "remaining two 75-mile cards can finish exactly")
  hidden = Marshal.load(Marshal.dump(state))
  pool = hidden[:draw_pile] + hidden[:hands]["Bob"] + hidden[:hands]["Carol"]
  hidden[:hands]["Bob"] = [pool.shift]
  hidden[:hands]["Carol"] = [pool.shift]
  hidden[:draw_pile] = pool.reverse
  alternate = fixture.snapshot(hidden)
  before = Marshal.dump(state)
  equal(actions.map { |action| game.bot_action_score(replay, "Alice", action) },
    actions.map { |action| game.bot_action_score(alternate, "Alice", action) }, "unseen hands and deck order cannot change scores")
  random = GameRoomRandom::SeededSource.new(42)
  alternate_random = random.dup
  chosen = game.bot_strategy.choose(actions: actions, game: game, replay: replay, actor: "Alice", random_source: random)
  other = game.bot_strategy.choose(actions: actions, game: game, replay: alternate, actor: "Alice", random_source: alternate_random)
  equal(viable, chosen, "bot takes the feasible smaller mileage card")
  equal(chosen, other, "chosen action does not depend on hidden cards")
  equal(random.roll(count: 8, sides: 1000).values, alternate_random.roll(count: 8, sides: 1000).values, "subsequent RNG state is unchanged by hidden information")
  equal(before, Marshal.dump(state), "bot estimation leaves its replay untouched")
  equal(:ok, fixture.play(state, "Alice", "play", chosen.fetch("card")), "bot choice uses the ordinary action and event path")
  equal(850, state[:tracks][0][:miles], "chosen distance really advances the track")
end

test("exact-finish estimator includes extra custom copies and still caps 200-mile usage") do
  [11, 12].each do |count|
    spent = Array.new(10) { |index| "25:#{index + 1}" } + Array.new(7) { |index| "100:#{index + 1}" }
    fixture, state = CustomReplayTest.distance_fixture({ "25" => count, "100" => 7 },
      spent: spent, hand: ["25:11"], miles: 950)
    action = { "kind" => "card", "action" => "play", "card" => "25:11" }
    equal(count == 12 ? 425 : -20_000, fixture.game.bot_action_score(fixture.snapshot(state), "Alice", action),
      "the twelfth physical 25-mile card exists only when configured; the selected eleventh card cannot be used twice")
  end
  spent = %w[200:1 200:2 100:1 100:2 100:3 75:1]
  fixture, state = CustomReplayTest.distance_fixture({ "200" => 100, "100" => 3, "75" => 1, "25" => 1 },
    spent: spent, hand: ["25:1"], miles: 775, two_hundreds: 2)
  action = { "kind" => "card", "action" => "play", "card" => "25:1" }
  equal(-20_000, fixture.game.bot_action_score(fixture.snapshot(state), "Alice", action), "a large custom supply does not permit a third 200-mile card")
end

test("bot discards an already-owned physical safety before useful green lights or remedies") do
  [false, true].each do |recycling|
    fixture = Fixture.new(options: { "custom_deck" => true, "driving_ace_cards" => 3, "recycle_discard" => recycling })
    state = fixture.scenario
    state[:hands]["Alice"] = %w[driving_ace:2 go:1 fuel:1]
    state[:spent] = ["driving_ace:1"]
    state[:tracks][0].merge!(safeties: ["driving_ace"], hazards: ["flat_tire"], moving: false)
    game = fixture.game
    replay = fixture.snapshot(state)
    actions = game.legal_actions(replay, "Alice")
    equal(["discard"], actions.map { |action| action["action"] }.uniq, "hand requires a discard while waiting for the tire remedy")
    duplicate = actions.find { |action| action["card"] == "driving_ace:2" }
    alternatives = actions.reject { |action| action == duplicate }
    duplicate_score = game.bot_action_score(replay, "Alice", duplicate)
    assert(alternatives.all? { |action| duplicate_score > game.bot_action_score(replay, "Alice", action) }, "owned safety must rank as useless, not as a new 3000-value safety")
    chosen = game.bot_strategy.choose(actions: actions, game: game, replay: replay, actor: "Alice", random_source: GameRoomRandom::SeededSource.new(42))
    equal(duplicate, chosen, "discard the duplicate safety rather than useful Go or Gas")
    equal(:ok, fixture.play(state, "Alice", "discard", chosen.fetch("card")), "bot discard accepted by the standard model")
    equal(%w[go:1 fuel:1], state[:hands]["Alice"], "useful future cards preserved")
    equal(["driving_ace:2"], state[:discard], "the physical duplicate was discarded")
    equal(100, game.participant_scores(fixture.snapshot(state)).fetch("Alice"), "existing safety still scores once")
  end
end

test("eight-player custom archive saves lists fetches restores and rejects invalid seats or manifests") do
  players = %w[Alice Bob Carol Dave Eve Frank Grace Heidi]
  fixture = Fixture.new(players: players, options: { "custom_deck" => true, "25_cards" => 20,
    "include_instant_repairs" => true, "instant_repair_cards" => 6 })
  fixture.start
  fixture.act("Alice", { "kind" => "command", "action" => "draw" })
  fixture.act("Alice", { "kind" => "card", "action" => "discard", "card" => fixture.replay.state[:hands]["Alice"].first })
  before = fixture.replay
  saves, row = CustomReplayTest.save(fixture)
  manifest = saves.list.fetch(0)
  equal(1, saves.list.length, "exactly one eight-player archive listed")
  equal(players, manifest.fetch("players"), "manifest retains all eight seats")
  assert(!manifest.key?("events"), "listing remains a small manifest, not an eager event archive")
  equal(row, saves.fetch(row.fetch("id")), "eight-player compressed archive fetched unchanged")
  data = saves.restored_data(row, game: fixture.game, table_id: 91, now: 2000)
  restored = Fixture.new(players: data.fetch(:players), options: JSON.parse(row.fetch("options")))
  restored.session["id"] = 91
  restored.events.concat(data.fetch(:events))
  equal(before.state, restored.replay.state, "full eight-player custom state restored")
  equal(fixture.events.map { |entry| entry.fetch("id") }, restored.events.map { |entry| entry.fetch("id") }, "event identities preserved")
  action = { "kind" => "command", "action" => "draw" }
  equal(fixture.act("Bob", action).state, restored.act("Bob", action).state, "next eight-player move matches uninterrupted play")
  [players + ["Judy"], players.first(7) + ["ALICE"]].each do |invalid_players|
    invalid = JSON.parse(JSON.generate(row))
    invalid["players"] = invalid_players
    invalid["checksum"] = saves.send(:checksum, invalid)
    failure = nil
    begin
      saves.restored_data(invalid, game: fixture.game, table_id: 91, now: 2000)
    rescue ArgumentError => error
      failure = error
    end
    assert(failure && failure.message == "Invalid saved seats", "over-limit or duplicate archive seats must fail before replay")
  end
  resources = saves.instance_variable_get(:@resources)
  resource = resources.list(timeout: 1).fetch(0)
  original_meta = resource.meta
  original_manifest = JSON.parse(original_meta)
  invalid_values = [
    { "players" => players + ["Judy"] },
    { "players" => players.first(7) + ["ALICE"] },
    { "players" => [] },
    { "players" => players.first(7) + [42] },
    { "players" => players.first(7) + ["x" * 65] },
    { "owner" => "Mallory" },
    { "bytes" => AccountSavedGames::MAX_BYTES + 1 }
  ]
  invalid_values.each do |changes|
    resource.meta = JSON.generate(original_manifest.merge(changes))
    assert(saves.list.empty?, "invalid eight-player manifest must not enter the archive list: #{changes.keys}")
    equal(nil, saves.fetch(row.fetch("id")), "invalid manifest must not be fetched")
  end
  resource.meta = original_meta
  original_size = resource.filesize
  resource.filesize = AccountSavedGames::MAX_BYTES + 1
  assert(saves.list.empty?, "compressed resource size remains bounded")
  resource.filesize = original_size
  resource.uploader = "Mallory"
  assert(saves.list.empty?, "eight seats do not bypass authenticated uploader checks")
  resource.uploader = "Alice"
  equal(row, saves.fetch(row.fetch("id")), "failed reads never change the original compressed archive")
  large_players = Array.new(8) { |index| "\u{1f600}" * 63 + index.to_s }
  replacements = Array.new(20) { |index| { "id" => index + 1, "players" => large_players } }
  chunks = GameRoomLiveSessionStore.allocate.send(:archive_chunks, replacements, archive_id: "a" * 36, actor: "Alice")
  assert(chunks.length > 2, "eight long Unicode names require bounded archive chunks")
  equal(replacements, chunks.flatten(1), "chunking neither loses nor duplicates replacement rows")
  chunks.each_with_index do |entries, index|
    packet = { "version" => 2, "kind" => "game_archive", "actor" => "Alice",
      "data" => { "archive_id" => "a" * 36, "index" => index, "events" => entries } }
    assert(JSON.generate(packet).bytesize <= GameRoomLiveSessionStore::STACK_ENTRY_BYTES, "eight-player replacements preserve the native packet byte limit")
  end
end
