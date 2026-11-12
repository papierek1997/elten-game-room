require_relative "../../support/ui"
require_relative "../../../lib/game_surfaces"
require_relative "../../support/new_games_fixture"
require_relative "../../../lib/game_repository"
require_relative "../../../lib/saved_games"
require_relative "../../../lib/game_sounds"

game = GameRoomGames::Battleship.new
players = %w[Alice Bob]
repo = NewGames116Repository.new(players)
session = { "__id" => 7, "table_id" => 3, "player_one" => "Alice", "__players" => players,
  "options" => JSON.generate(game.default_options) }
sample = [[0,1,2,3],[20,21,22],[40,41,42],[60,61],[80,81],[85,86],[8],[28],[48],[68]]
vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
context = GameRoomGames::ActionContext.new(session_id: 7, hidden_submissions: vault)
seals = players.each_with_index.map do |actor, index|
  envelope = vault.prepare(session_id: 7, round_id: "fleet", user: actor, payload: { "ships" => sample })
  { "id" => index + 1, "actor" => actor, "action" => "place", "value" => envelope.commitment }
end
empty = game.replay(session, [], repo)
ready = game.replay(session, seals, repo)
shot_event = { "id" => 3, "actor" => "Alice", "action" => "shoot", "value" => "0" }
answer_event = { "id" => 4, "actor" => "Bob", "action" => "answer", "value" => "hit" }
shot = game.replay(session, seals + [shot_event], repo)
answered = game.replay(session, seals + [shot_event, answer_event], repo)
[empty, ready, shot, answered].each do |replay|
  (players + ["Observer"]).each { |viewer| game.game_shortcuts(replay, viewer) }
end
last = game.game_shortcuts(answered, "Alice").find { |s| s.key == "l" && s.modifiers.empty? }.message
assert(last.scan("A1").length == 1 && last.include?("Alice"), "last shot lacks actor or repeats coordinates")

# Genuine CompositeSurface forwards the board ID, rather than a hand-made mock.
surface = GameSurfaces.build(game.surface_spec(ready, "Alice"))
selection = nil
surface.on_action { |action| selection = action }
surface.fields.last.trigger(:select, [5, 5])
assert(selection.source == "own", "own board source is lost")
status, plan = game.action_for(selection, ready, "Alice", context: context)
assert(status == :own_board && plan == nil, "own board fired a shot")
surface.fields.first.trigger(:select, [5, 5])
status, plan = game.action_for(selection, ready, "Alice", context: context)
assert(status == :ok && plan.events.first.value == "55", "enemy board cannot shoot")
[[-1, 1], [10, 0], ["x", 0], [nil, 0]].each do |x, y|
  assert(game.action_for({ "action" => "select", "x" => x, "y" => y }, ready, "Alice").first == :invalid,
    "bad coordinates were coerced into a square")
end

# A joining human does not need to execute an automatic move to see their fleet.
fresh = GameRoomGames::Battleship.new
assert(!fresh.automatic_action_allowed?(ready, "Bob", table_owner: "Alice"), "fixture should bypass automatic path")
fresh.prepare_view(ready, "Bob", context: context)
assert(fresh.surface_spec(ready, "Bob").parts.last.surface.cells.flatten.count { |cell| cell.include?("ship") } == 20,
  "joining player's private board is empty")
changed = ready.dup
changed.state = Marshal.load(Marshal.dump(ready.state))
changed.state[:commitments]["Bob"] = "f" * 64
fresh.prepare_view(changed, "Bob", context: context)
assert(fresh.surface_spec(changed, "Bob").parts.last.surface.cells.flatten.none? { |cell| cell.include?("ship") },
  "another session inherited a private fleet")
recoverable = GameRoomGames::Battleship.new
missing_vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
recoverable.prepare_view(ready, "Bob", context: GameRoomGames::ActionContext.new(session_id: 7, hidden_submissions: missing_vault))
recoverable.prepare_view(ready, "Bob", context: context)
assert(recoverable.surface_spec(ready, "Bob").parts.last.surface.cells.flatten.count { |cell| cell.include?("ship") } == 20,
  "a temporary missing fleet was cached forever")

[empty, ready, shot, answered].each do |replay|
  spectator = fresh.surface_spec(replay, "Observer")
  assert(spectator.is_a?(GameSurfaces::CompositeSpec), "observer got placement controls")
  assert(spectator.parts.all? { |part| players.any? { |name| part.surface.header.include?(name) } }, "observer boards have no owners")
  assert(spectator.parts.flat_map { |part| part.surface.cells.flatten }.none? { |cell| cell.include?("ship") }, "secret fleet leaked to observer")
  assert(game.action_for({ "action" => "begin" }, replay, "Observer").first == :invalid, "observer emitted an action")
end
assert(fresh.surface_spec(answered, "Observer").parts.last.surface.cells.flatten.count { |cell| cell.include?("hit") } == 1,
  "observer missed the public hit on Bob's board")

revealing = ready.dup
revealing.state = Marshal.load(Marshal.dump(ready.state))
revealing.state[:phase] = :revealing
status, opening = game.action_for({ "action" => "open" }, revealing, "Alice", context: context)
assert(status == :ok && opening.events.map { |event| event.value.length } == [64, 51], "fleet does not fit the real event limit")
assert(game.send(:decode_fleet, opening.events.last.value) == sample, "compact reveal changes commitment order")
%w[polish classic].each do |fleet|
  [false, true].each do |touching|
    state = game.send(:initial_state, players, game.normalize_options("fleet" => fleet, "touching" => touching))
    ships = game.send(:random_fleet, state).reverse.map(&:reverse)
    value = game.send(:encode_fleet, ships)
    assert(value.bytesize <= 64 && game.send(:decode_fleet, value) == ships, "variant codec loses ship/cell order")
  end
end

module Session
  def self.name; "Alice"; end
end
transport = Object.new
transport.define_singleton_method(:live_store?) { true }
transport.define_singleton_method(:append_game_action) { |**args| args.fetch(:events) }
real_repo = GameRepository.new(nil, transport: transport, server_tables: Object.new)
assert(real_repo.append_events(session: session, sequence: 3, events: opening.events, actor: "Alice") == opening.events,
  "real repository rejected the compact reveal")
begin
  snapshot = Struct.new(:session, :events).new(session, seals)
  SavedGames.new(Object.new, owner: "Alice").put(game: game, table: {}, snapshot: snapshot, repository: nil)
  raise "a secret-fleet game was archived without its private data"
rescue ArgumentError => error
  assert(error.message == "Unsupported saved game", "wrong archive refusal")
end

state = Marshal.load(Marshal.dump(revealing.state))
assert(game.send(:apply_open, state, { "value" => opening.events.first.value }, "Alice"), "nonce refused")
bad_values = ["[0]", "null", "{}", "[]", "[[0.5]]", "[[\"0\"]]", "[[100]]", "1:", "1:00.", "1:zz", "1:" + "00" * 100]
bad_values.each do |value|
  original = Marshal.dump(state)
  assert(!game.send(:apply_fleet, state, { "id" => 5, "value" => value }, "Alice", repo, []), "malformed reveal accepted")
  assert(Marshal.dump(state) == original, "malformed reveal changed state")
end
invalid_fleets = [sample.drop(1), sample.map { |ship| [ship.first] * ship.length }]
invalid_fleets.each do |ships|
  audit = Marshal.load(Marshal.dump(state))
  assert(game.send(:apply_fleet, audit, { "id" => 5, "value" => JSON.generate(ships) }, "Alice", repo, []),
    "a structurally complete illegal reveal did not reach final audit")
  assert(!game.send(:honest?, audit, "Alice"), "an illegal or mismatched fleet passed final verification")
end
assert(game.send(:apply_fleet, state, { "id" => 5, "value" => opening.events.last.value }, "Alice", repo, []), "valid compact reveal refused")

strategy = game.bot_strategy
model = ready.state.merge(shots: { "Alice" => { 44 => "sunk" } })
assert(strategy.cell_value(game, model, "Alice", 45) < strategy.cell_value(game, model, "Alice", 0), "bot hunts the forbidden halo")
touching = model.merge(options: model[:options].merge("touching" => true), shots: { "Alice" => { 0 => "sunk", 1 => "hit" } })
assert(strategy.cell_value(game, touching, "Alice", 2) > strategy.cell_value(game, touching, "Alice", 99), "adjacent wounded ship forgotten")
scores = (0...100).map { |cell| strategy.cell_value(game, touching, "Alice", cell) }
changed_secret = touching.merge(fleets: { "Bob" => sample }, commitments: { "Bob" => "different" })
assert(scores == (0...100).map { |cell| strategy.cell_value(game, changed_secret, "Alice", cell) }, "bot consulted secret fleet")

assert(GameRoomSounds::BATTLESHIP_LAUNCHES.include?(GameRoomSounds.event_cue(game: game, event: shot_event, before_replay: ready, after_replay: shot, repository: repo, viewer: "Alice")), "missing shot sound")
assert(GameRoomSounds::BATTLESHIP_HITS.include?(GameRoomSounds.event_cue(game: game, event: answer_event, before_replay: shot, after_replay: answered, repository: repo, viewer: "Observer")), "missing public hit sound")
assert(GameRoomSounds.event_cue(game: game, event: { "id" => 999, "action" => "shoot" }, before_replay: ready, after_replay: ready, repository: repo, viewer: "Alice") == nil, "rejected shot produced a sound")
puts "PASS Battleship integration: compact real-repository writes, private views, observer, controls, malformed events, save refusal and public-knowledge bot"
