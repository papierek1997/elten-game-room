require_relative "../../support/elten_array_shuffle"
require_relative "../../support/mille_bornes"
include MilleBornesTest

test("ordinary bots ignore hidden hands and deck order, preserving RNG") do
  fixture = Fixture.new
  state = fixture.scenario
  state[:hands]["Alice"] = %w[go:1 100:1 stop:1]
  state[:tracks][1][:moving] = true
  game = fixture.game
  replay = fixture.snapshot(state)
  alternative = Marshal.load(Marshal.dump(state))
  alternative[:hands]["Bob"] = %w[right_of_way:1 driving_ace:1]
  alternative[:hands]["Carol"] = %w[200:1 200:2]
  alternative[:draw_pile].reverse!
  other = fixture.snapshot(alternative)
  equal(game.bot_observation(replay, "Alice"), game.bot_observation(other, "Alice"), "public observation invariant")
  actions = game.legal_actions(replay, "Alice")
  equal(actions, game.legal_actions(other, "Alice"), "legal own actions invariant")
  equal(actions.map { |action| game.bot_action_score(replay, "Alice", action) },
    actions.map { |action| game.bot_action_score(other, "Alice", action) }, "heuristic must not peek")
  random = GameRoomRandom::SeededSource.new(42)
  alternate_random = random.dup
  chosen = game.bot_strategy.choose(actions: actions, game: game, replay: replay, actor: "Alice", random_source: random)
  alternative_chosen = game.bot_strategy.choose(actions: actions, game: game, replay: other, actor: "Alice", random_source: alternate_random)
  equal(chosen, alternative_chosen, "chosen action invariant")
  equal(random.roll(count: 5, sides: 100).values, alternate_random.roll(count: 5, sides: 100).values, "subsequent RNG invariant")
  observation = game.bot_observation(replay, "Alice")
  observation["tracks"][0][:miles] = 777
  observation["hand"].clear
  equal(0, state[:tracks][0][:miles], "public tracks copied")
  equal(3, state[:hands]["Alice"].length, "own hand copied")
  assert(game.session_runner?, "standard runner enabled")
  assert(!game.perfect_information?, "no omniscient mode")
  assert(!game.bot_strategy.simulation_required?, "heuristic needs no hidden simulation")
end

test("full games through action_for, conservation and deterministic histories") do
  variants = [{}, { "counterflow" => true, "counterflow_cards" => 1, "end_counterflow_cards" => 20 },
    { "counterflow" => true, "counterflow_cards" => 20, "end_counterflow_cards" => 1 }]
  variants += variants.map { |options| options.merge("include_safeties" => false) }
  [2, 4, 6, 8].product(variants).each do |count, variant|
    options = { "target_score" => 100 }.merge(variant)
    deck_count = (variant.fetch("include_safeties", true) ? 106 : 102) + variant.fetch("counterflow_cards", 0) + variant.fetch("end_counterflow_cards", 0)
    options["team_count"] = 4 if count == 8
    fixture = Fixture.new(players: Array.new(count) { |index| "Player#{index + 1}" }, options: options)
    random = GameRoomRandom::SeededSource.new(count * 13)
    fixture.start
    800.times do
      current = fixture.replay
      break if current.finished?
      automatic = fixture.game.automatic_action(current, fixture.players.first)
      if automatic
        fixture.act(fixture.players.first, automatic)
        next
      end
      actor = fixture.game.active_actors(current).first
      assert(actor, "unfinished game has no active actor")
      actions = fixture.game.legal_actions(current, actor)
      assert(!actions.empty?, "active actor has no legal action")
      action = fixture.game.bot_strategy.choose(actions: actions, game: fixture.game, replay: current,
        actor: actor, random_source: random)
      after = fixture.act(actor, action)
      state = after.state
      cards = state[:hands].values.flatten + state[:draw_pile] + state[:discard] + state[:spent]
      equal(deck_count, cards.length, "card conservation")
      equal(deck_count, cards.uniq.length, "no physical duplicate")
      assert(state[:tracks].all? { |track| track[:miles].between?(0, 1000) && track[:two_hundreds] <= 2 }, "track invariants")
    end
    final = fixture.replay
    assert(final.finished?, "#{count}-player match did not finish")
    equal(fixture.events.length, final.accepted_events.length, "every planned event accepted")
    equal(final.history.map(&:to_h), fixture.replay.history.map(&:to_h), "stable history")
    if variant["include_safeties"] == false
      equal(false, final.state[:options]["include_safeties"], "disabled flag survives complete replay")
      assert(final.state[:tracks].all? { |track| track[:safeties].empty? && track[:dirty_tricks] == 0 }, "disabled match has no safeties or dirty tricks")
    else
      enabled_session = fixture.session.merge("options" => JSON.generate(options.merge("include_safeties" => true)))
      equal(final.state, fixture.game.replay(enabled_session, fixture.events, fixture.repository).state, "old replay equals explicitly enabled replay")
      assert(!final.state[:options].key?("include_safeties"), "old replay retains its option shape")
    end
  end
end

test("recycling bots release surplus remedies while standard choices and RNG stay unchanged") do
  %w[go fuel spare_tire repairs end_limit].product([false, true]).each do |type, recycling|
    fixture = Fixture.new(options: { "recycle_discard" => recycling })
    state = fixture.scenario
    state[:hands]["Alice"] = ["#{type}:1", "#{type}:2", "#{type}:3", "200:1", "200:2"]
    state[:tracks][0].merge!(moving: true, miles: 875)
    replay = fixture.snapshot(state)
    actions = fixture.game.legal_actions(replay, "Alice")
    choices = actions.select { |action| action["action"] == "discard" && action["card"].start_with?(recycling ? "#{type}:" : "200:") }
    random = GameRoomRandom::SeededSource.new(42)
    expected_random = random.dup
    expected = choices[expected_random.roll(count: 1, sides: choices.length).values.first - 1]
    chosen = fixture.game.bot_strategy.choose(actions: actions, game: fixture.game, replay: replay,
      actor: "Alice", random_source: random)
    equal(expected, chosen, "recycling releases redundant defenses; standard retains its original choice")
    equal(expected_random.roll(count: 8, sides: 1000).values, random.roll(count: 8, sides: 1000).values, "one ordinary tie-break draw, no extra RNG")
    equal(:ok, fixture.game.action_for(chosen, replay, "Alice").first, "discard follows normal rules")
  end
end

test("recycling bots preserve a possible exact finish using only publicly spent distance cards") do
  [false, true].each do |recycling|
    fixture = Fixture.new(options: { "recycle_discard" => recycling })
    state = fixture.scenario
    state[:hands]["Alice"] = %w[100:3 75:4 75:1 100:2 go:5 end_limit:3]
    state[:tracks][0].merge!(moving: true, miles: 775, two_hundreds: 2)
    state[:spent] = fixture.game.send(:deck_for, {}).select { |card| card.start_with?("25:", "50:") } +
      %w[200:1 200:2 100:1 100:4 100:8 100:9 100:11]
    replay = fixture.snapshot(state)
    actions = fixture.game.legal_actions(replay, "Alice")
    assert(actions.any? { |action| action["action"] == "play" && action["card"] == "100:3" }, "100 remains legal even if strategically losing")
    hidden = Marshal.load(Marshal.dump(state))
    hidden[:hands]["Bob"] = %w[go:1 end_limit:1 75:3]
    hidden[:hands]["Carol"] = %w[100:5 200:3 75:5]
    hidden[:draw_pile].reverse!
    alternative = fixture.snapshot(hidden)
    scores = actions.map { |action| fixture.game.bot_action_score(replay, "Alice", action) }
    equal(scores, actions.map { |action| fixture.game.bot_action_score(alternative, "Alice", action) }, "unseen hands and draw order cannot affect finish analysis")
    random = GameRoomRandom::SeededSource.new(42)
    alternate_random = random.dup
    chosen = fixture.game.bot_strategy.choose(actions: actions, game: fixture.game, replay: replay,
      actor: "Alice", random_source: random)
    other = fixture.game.bot_strategy.choose(actions: actions, game: fixture.game, replay: alternative,
      actor: "Alice", random_source: alternate_random)
    equal("play", chosen["action"], "bot chooses available progress")
    equal(recycling ? "75" : "100", chosen["card"].split(":").first, "avoid an impossible 125-mile gap only in recycling variant")
    equal(chosen, other, "same decision without hidden-card knowledge")
    equal(random.roll(count: 8, sides: 1000).values, alternate_random.roll(count: 8, sides: 1000).values, "same subsequent RNG")
  end
end

test("finish analysis accounts for the card being spent and the two-200 allowance") do
  fixture = Fixture.new(options: { "recycle_discard" => true })
  state = fixture.scenario
  state[:hands]["Alice"] = %w[25:10 200:4]
  state[:tracks][0].merge!(moving: true, miles: 775, two_hundreds: 2)
  state[:spent] = fixture.game.send(:deck_for, {}).select do |card|
    %w[25 50 75 100].include?(card.split(":").first) && card != "25:10"
  end
  replay = fixture.snapshot(state)
  action = { "kind" => "card", "action" => "play", "card" => "25:10" }
  equal(:ok, fixture.game.action_for(action, replay, "Alice").first, "mileage legality is not narrowed")
  equal(-20_000, fixture.game.bot_action_score(replay, "Alice", action), "third future 200 cannot complete the route")
  state[:tracks][0][:two_hundreds] = 1
  equal(425, fixture.game.bot_action_score(fixture.snapshot(state), "Alice", action), "one available 200 makes the route possible")
  state[:tracks][0][:miles] = 950
  equal(-20_000, fixture.game.bot_action_score(fixture.snapshot(state), "Alice", action), "the last 25 cannot be used twice")
  state[:tracks][0][:miles] = 975
  equal(20_000, fixture.game.bot_action_score(fixture.snapshot(state), "Alice", action), "actual exact finish keeps winning priority")
end

test("counterflow bots prefer discarding mileage without seeing hidden cards or changing RNG") do
  fixture = Fixture.new(options: { "counterflow" => true, "counterflow_cards" => 3, "end_counterflow_cards" => 4 })
  game = fixture.game
  game.class::DISTANCES.product([0, 975]).each do |distance, miles|
    state = fixture.scenario
    state[:hands]["Alice"] = ["#{distance}:1", "fuel:1"]
    state[:tracks][0].merge!(moving: true, counterflow: true, miles: miles)
    replay = fixture.snapshot(state)
    alternative = Marshal.load(Marshal.dump(state))
    alternative[:hands]["Bob"] = %w[driving_ace:1 end_counterflow:1]
    alternative[:hands]["Carol"] = %w[counterflow:1 counterflow:2]
    alternative[:draw_pile].reverse!
    other = fixture.snapshot(alternative)
    equal(game.bot_observation(replay, "Alice"), game.bot_observation(other, "Alice"), "only own hand and public state observed")
    actions = game.legal_actions(replay, "Alice")
    equal(actions, game.legal_actions(other, "Alice"), "hidden information cannot affect legal actions")
    equal(actions.map { |action| game.bot_action_score(replay, "Alice", action) },
      actions.map { |action| game.bot_action_score(other, "Alice", action) }, "hidden information cannot affect scores")
    random = GameRoomRandom::SeededSource.new(42)
    alternate_random = random.dup
    chosen = game.bot_strategy.choose(actions: actions, game: game, replay: replay, actor: "Alice", random_source: random)
    other_chosen = game.bot_strategy.choose(actions: actions, game: game, replay: other, actor: "Alice", random_source: alternate_random)
    equal({ "kind" => "card", "action" => "discard", "card" => "#{distance}:1" }, chosen, "discard rather than deliberately lose mileage")
    equal(chosen, other_chosen, "chosen action does not peek")
    equal(random.roll(count: 5, sides: 100).values, alternate_random.roll(count: 5, sides: 100).values, "subsequent RNG preserved")
    equal(:ok, game.action_for(chosen, replay, "Alice").first, "bot uses normal validation")
  end
  state = fixture.scenario
  state[:hands]["Alice"] = %w[25:1 end_counterflow:1]
  state[:tracks][0].merge!(moving: true, counterflow: true, miles: 975)
  replay = fixture.snapshot(state)
  chosen = game.bot_strategy.choose(actions: game.legal_actions(replay, "Alice"), game: game, replay: replay,
    actor: "Alice", random_source: GameRoomRandom::SeededSource.new(42))
  equal("end_counterflow:1", chosen["card"], "bot knows its own remedy")
  equal("play", chosen["action"], "remedy preferred to discarding")
end

test("counterflow pending dirty trick and configured counts survive deterministic replay and renaming") do
  options = { "counterflow" => true, "counterflow_cards" => 3, "end_counterflow_cards" => 4 }
  fixture = Fixture.new(options: options)
  seed = (1..2000).find do |number|
    fixture.events.replace([event(1, "Alice", "deal", "1|#{number.to_s(16).rjust(32, '0')}"), event(2, "Alice", "draw")])
    current = fixture.replay
    current.state[:hands]["Alice"].include?("counterflow:1") && current.state[:hands]["Carol"].include?("driving_ace:1")
  end
  assert(seed, "no deterministic counterflow dirty-trick fixture found")
  pending = fixture.act("Alice", { "kind" => "card", "action" => "play", "card" => "counterflow:1", "target" => "2" })
  assert(pending.state[:tracks][2][:counterflow], "attack accepted against initially stopped car")
  equal(pending.state, fixture.replay.state, "full replay preserves independent effect")
  repeated = fixture.game.replay(fixture.session, fixture.events + [fixture.events.last], fixture.repository)
  equal(pending.state, repeated.state, "duplicate does not reapply effect")
  renamed = %w[NewAlice NewBob NewCarol]
  mapping = fixture.players.zip(renamed).to_h
  restored_events = JSON.parse(JSON.generate(fixture.events)).map do |entry|
    value = fixture.game.restored_event_value(entry, mapping)
    equal(entry["value"], value, "card IDs, seat numbers and reaction tokens are stable")
    entry.merge("actor" => mapping.fetch(entry["actor"]), "value" => value)
  end
  session = JSON.parse(JSON.generate(fixture.session)).merge("__id" => 99, "__players" => renamed)
  restored = fixture.game.replay(session, restored_events, fixture.repository)
  equal(pending.state[:options], restored.state[:options], "explicit deck counts retained")
  equal(pending.state[:tracks], restored.state[:tracks], "effect retained after archive serialization")
  equal(pending.state[:reaction], restored.state[:reaction], "prior state and reaction token retained")
  reaction = fixture.game.legal_actions(restored, "NewCarol").find { |action| action["action"] == "dirty_trick" }
  assert(reaction, "renamed player may still respond")
  status, plan = fixture.game.action_for(reaction, restored, "NewCarol")
  equal(:ok, status, "restored reaction legal")
  command = plan.events.first
  after = fixture.game.replay(session, restored_events + [event(4, "NewCarol", command.action, command.value)], fixture.repository)
  equal(4, after.accepted_events.length, "restored reaction replayed")
  assert(!after.state[:tracks][2][:counterflow], "restored ace removes effect")
  equal(false, after.state[:tracks][2][:moving], "original stopped state preserved")
  equal("NewCarol", after.current_player, "extra turn belongs to current controller")
  expired = fixture.game.replay(session, restored_events + [event(4, "NewBob", "draw")], fixture.repository)
  equal(:invalid, fixture.game.action_for(reaction, expired, "NewCarol").first, "next draw expires restored reaction")
end

test("restored target seats survive controller rename and session identity changes") do
  fixture = Fixture.new
  fixture.start
  random = GameRoomRandom::SeededSource.new(313)
  40.times do
    replay = fixture.replay
    break if replay.finished?
    automatic = fixture.game.automatic_action(replay, fixture.players.first)
    if automatic
      fixture.act(fixture.players.first, automatic)
      next
    end
    actor = fixture.game.active_actors(replay).first
    actions = fixture.game.legal_actions(replay, actor)
    fixture.act(actor, fixture.game.bot_strategy.choose(actions: actions, game: fixture.game, replay: replay,
      actor: actor, random_source: random))
  end
  before = fixture.replay
  renamed = %w[NewAlice NewBob NewCarol]
  mapping = fixture.players.each_with_index.to_h { |player, seat| [player.downcase, renamed[seat]] }
  restored_events = fixture.events.map do |event|
    value = fixture.game.restored_event_value(event, mapping)
    equal(event["value"], value, "only seat numbers and card IDs in event values")
    event.merge("actor" => mapping.fetch(event["actor"].downcase), "value" => value)
  end
  session = fixture.session.merge("__id" => 12345, "__players" => renamed)
  after = fixture.game.replay(session, restored_events, fixture.repository)
  normalized = JSON.generate(after.state)
  mapping.each { |original, replacement| normalized = normalized.gsub(replacement, fixture.players.find { |player| player.downcase == original }) }
  equal(JSON.generate(before.state), normalized, "restored rules unchanged")
  equal(12345, after.session_identity, "restored identity is canonical __id")
  assert(after.session_identity != before.session_identity, "transport identity not retained from archive")
  equal(before.accepted_events.length, after.accepted_events.length, "restored events accepted")
end

test("out-of-turn exception is bound to session, round and pending attack") do
  fixture = Fixture.new
  state = fixture.scenario
  state[:hands]["Alice"] = %w[stop:1 25:1]
  state[:hands]["Carol"] = %w[right_of_way:1 50:1]
  state[:tracks][2][:moving] = true
  fixture.play(state, "Alice", "play", "stop:1", target: "2")
  before = fixture.snapshot(Marshal.load(Marshal.dump(state)))
  after = fixture.snapshot(Marshal.load(Marshal.dump(state)))
  reaction = fixture.game.legal_actions(before, "Carol").first
  assert(fixture.game.concurrent_session_input?(before, after, reaction), "same attack allowed")
  after.session_identity = 18
  assert(!fixture.game.concurrent_session_input?(before, after, reaction), "cross-session rejected")
  after.session_identity = before.session_identity
  after.state[:round] += 1
  assert(!fixture.game.concurrent_session_input?(before, after, reaction), "cross-round rejected")
  after.state[:round] -= 1
  after.state[:reaction][:token] = "1:999"
  assert(!fixture.game.concurrent_session_input?(before, after, reaction), "different attack rejected")
  equal(:invalid, fixture.game.action_for(reaction, after, "Carol").first, "standard validation rejects stale reaction")
end

test("pending dirty trick survives actual deterministic replay and archive renaming") do
  fixture = Fixture.new
  seed = (1..1000).find do |number|
    fixture.events.replace([event(1, "Alice", "deal", "1|#{number.to_s(16).rjust(32, '0')}"), event(2, "Alice", "draw")])
    current = fixture.replay
    current.state[:hands]["Alice"].include?("speed_limit:1") && current.state[:hands]["Carol"].include?("right_of_way:1")
  end
  assert(seed, "no deterministic dirty-trick fixture found")
  pending = fixture.act("Alice", { "kind" => "card", "action" => "play", "card" => "speed_limit:1", "target" => "2" })
  assert(pending.state[:reaction], "attack did not open reaction")
  renamed = %w[NewAlice NewBob NewCarol]
  mapping = fixture.players.zip(renamed).to_h
  restored_events = fixture.events.map { |entry| entry.merge("actor" => mapping.fetch(entry["actor"])) }
  restored = fixture.game.replay(fixture.session.merge("__id" => 99, "__players" => renamed), restored_events, fixture.repository)
  equal(pending.state[:reaction], restored.state[:reaction], "pending hazard token and prior track survive archive")
  reaction = fixture.game.legal_actions(restored, "NewCarol").find { |action| action["action"] == "dirty_trick" }
  assert(reaction, "renamed player lost reaction")
  status, plan = fixture.game.action_for(reaction, restored, "NewCarol")
  equal(:ok, status, "restored dirty trick accepted")
  command = plan.events.first
  restored_events << event(4, "NewCarol", command.action, command.value)
  after = fixture.game.replay(fixture.session.merge("__id" => 99, "__players" => renamed), restored_events, fixture.repository)
  equal(4, after.accepted_events.length, "replayed restored reaction accepted")
  equal("NewCarol", after.current_player, "extra turn restored to current controller")
end
