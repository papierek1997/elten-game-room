require_relative "../../support/ui"
require_relative "../../support/native_room_harness"
require_relative "../../support/elten_array_shuffle"
require_relative "../../../lib/game_surfaces"
require_relative "../../../lib/game_sounds"
require_relative "../../../lib/saved_game_archive"
require_relative "../../../games/three_five_eight"

# Storage is outside this regression's boundary: exercise the actual archive
# codec/validation and restore protocol, retaining just its returned row.
class ThreeFiveEightArchive < GameRoomSavedGameArchive
  def persist(row); row; end
end

module ThreeFiveEightIntegration
  module_function

  def position(room, session = room.session)
    repository = room.repositories.fetch("Alice")
    snapshot = repository.snapshot_for(session)
    [room.game.replay(snapshot.session, snapshot.events, repository), snapshot]
  end

  def submit(room, selection, session: room.session)
    before, snapshot = position(room, session)
    actor = before.current_player || before.players.first
    context = GameRoomGames::ActionContext.new(server_random: snapshot.session['__server_random'] == GameRoomServerRandom::VERSION)
    status, plan = room.game.action_for(selection, before, actor, context: context)
    assert(status == :ok, "3-5-8 normal selection rejected: #{status}")
    repository = room.repositories.fetch("Alice")
    room.as("Alice") do
      # Deterministic entropy belongs to the server double, not the move.
      room.view('Alice').next_random_values = [1] * 15 + [selection.fetch('round') * 3 + 1] if selection['action'] == 'deal'
      repository.append_events(session: snapshot.session,
        sequence: repository.next_sequence(snapshot.session, snapshot.events),
        events: plan.events, actor: actor, controller: true)
    end
    after, next_snapshot = position(room, session)
    assert(after.accepted_events.length == before.accepted_events.length + plan.events.length,
      "3-5-8 replay rejected a normally submitted event")
    [before, after, next_snapshot.events.last]
  end

  def next_selection(game, replay, prefer_trump_exchange: false)
    state = replay.state
    if [:awaiting_deal, :round_complete].include?(state[:phase])
      round = state[:round] + 1
      dealer = state[:dealer_index] ? (state[:dealer_index] + 1) % 3 : 0
      return {"action" => "deal", "round" => round, "dealer" => dealer,
        "seed" => round.to_s(16).rjust(32, "0")}
    end
    actions = game.legal_actions(replay, replay.current_player)
    if prefer_trump_exchange && state[:phase] == :exchanging
      preferred = actions.find { |action| action["action"] == "exchange" && action["card"].end_with?(state[:contract]) }
      return preferred if preferred
    end
    actions.first
  end

  def continue_play(room, session: room.session, count: 3)
    plays = 0
    100.times do
      replay, = position(room, session)
      selection = next_selection(room.game, replay, prefer_trump_exchange: true)
      assert(selection, "3-5-8 continuation stalled")
      submit(room, selection, session: session)
      plays += 1 if selection["action"] == "play"
      return if plays >= count
    end
    raise "3-5-8 continuation never reached card play"
  end

  def cue(game, repository, before, after, event, viewer)
    Array(GameRoomSounds.event_cue(game: game, repository: repository,
      before_replay: before, after_replay: after, event: event, viewer: viewer))
  end

  def hand_cursor(surface)
    state = surface.state
    state = state.fetch("parts").fetch("cards") if state.key?("parts")
    state.fetch("hand_cursors").fetch("hand")
  end
end

game = GameRoomGames::ThreeFiveEight.new
room = NativeRoomHarness.new(game: game, users: ["Alice"], bots: 2)
room.start
repository = room.repositories.fetch("Alice")
positions = {}
audio = {}
exchange = nil
# Every fixture state below is reached through action_for, repository append,
# native stack projection and model replay; no test mutates the game state.
100.times do
  before, = ThreeFiveEightIntegration.position(room)
  positions[before.state[:phase]] ||= before
  selection = ThreeFiveEightIntegration.next_selection(game, before)
  assert(selection, "3-5-8 legal trace stalled")
  before, after, event = ThreeFiveEightIntegration.submit(room, selection)
  positions[after.state[:phase]] ||= after
  cues = ThreeFiveEightIntegration.cue(game, repository, before, after, event, "Alice")
  audio[event["action"]] ||= cues
  if event["action"] == "play" && event["value"].end_with?(after.state[:contract].to_s)
    assert(cues.include?("play") && cues.include?("draw2"), "trump play lost one of its independent sounds")
    audio["trump"] = cues
  end
  result = after.history.find { |entry| entry.event_id == repository.event_id(event) && entry.kind == :round_result && entry.actor == "Alice" }
  if result
    expected = result.value > 0 ? "win1" : (result.value < 0 ? "lose1" : nil)
    assert(cues.include?("play") && (expected == nil || cues.include?(expected)), "round end lost play or score audio")
    assert(!cues.include?("ding"), "round result bypassed the shared own-turn preference")
    assert(cues.uniq == cues, "round audio duplicated a cue")
    audio["round"] = cues
  end
  if event["action"] == "exchange"
    exchange = event
    break
  end
end
assert(exchange && exchange["value"].start_with?("bot:"), "fixture never exchanged with a bot")
assert(game.method(:event_sound_cues).owner == GameRoomGames::ThreeFiveEight, "3-5-8 still relies on a removed central sound switch")
assert(audio["deal"] == ["shuffle"] && audio["choose_contract"] == [] &&
  audio["discard"] == ["draw"] && audio["exchange"] == ["draw"] &&
  audio.key?("trump") && audio.key?("round"), "3-5-8 event audio hooks are incomplete")

before, snapshot = ThreeFiveEightIntegration.position(room)
original_events = Marshal.load(Marshal.dump(snapshot.events))
original_history = before.history.map(&:to_h)
target = exchange["value"].split("|", 2).first
inherited_hand = before.state[:hands].fetch(target).dup

# Saving after an actual bot-target exchange must restore on another table,
# whose newly named bot has a different physical participant identifier.
archive = ThreeFiveEightArchive.new(nil, owner: "Alice")
row = archive.put(game: game, table: room.table, snapshot: snapshot,
  repository: repository, now: Time.now.to_i)
restored_table = room.as("Alice") do
  room.transports["Alice"].create_room(name: "3-5-8 restored test", game: game.id,
    owner: "Alice", game_options: row["options"], bot_count: 2)
end
restoration = archive.restored_data(row, game: game, table_id: restored_table["__id"], now: row["saved_at"] + 60)
assert(restoration[:players] != before.players, "restore fixture reused old bot identities")
restored_exchange = restoration[:events].find { |event| event["id"] == repository.event_id(exchange) }
assert(restored_exchange["value"] != exchange["value"] &&
  restored_exchange["value"].split("|", 2).last == exchange["value"].split("|", 2).last,
  "archive did not remap only the exchange recipient")
restored_session = room.as("Alice") do
  repository.restore_session(table: restored_table, game: game.id, players: restoration[:players],
    options: row["options"], restore: restoration)
end
restored, = ThreeFiveEightIntegration.position(room, restored_session)
assert(restored.accepted_events.length == before.accepted_events.length, "restore dropped an exchange")
before.players.each_with_index do |player, index|
  replacement = restored.players.fetch(index)
  assert(restored.state[:hands][replacement] == before.state[:hands][player], "restore changed a hand")
  assert(restored.state[:scores][replacement] == before.state[:scores][player], "restore changed a score")
end
ThreeFiveEightIntegration.continue_play(room, session: restored_session)

# Physical bot -> present observer -> new named bot. Both changes must replay
# exchanges addressed to the original occupant and preserve immutable history.
room.add_client("Watcher")
assert(room.join("Watcher"), "observer could not join")
room.as("Alice") { room.transports["Alice"].set_observer(room.table, true, actor: "Alice", subject: "Watcher") }
room.as("Alice") do
  room.transports["Alice"].replace_game_player(room.table, session_id: room.session["__id"],
    player: target, replacement: "Watcher")
end
human, human_snapshot = ThreeFiveEightIntegration.position(room)
assert(human.accepted_events.length == original_events.length, "bot-to-human replacement dropped an exchange")
assert(human.state[:hands]["Watcher"] == inherited_hand, "incoming human did not inherit exchanged cards")
assert(human_snapshot.events == original_events && human.history.map(&:to_h) == original_history,
  "replacement rewrote historical events or authors")
room.as("Alice") do
  room.transports["Alice"].replace_game_player(room.table, session_id: room.session["__id"], player: "Watcher")
end
replaced, replacement_snapshot = ThreeFiveEightIntegration.position(room)
replacement_bot = (replaced.players - before.players).first
assert(GameRoomParticipants.bot?(replacement_bot) && replacement_bot != target, "human was not replaced by a new physical bot")
assert(replaced.state[:hands][replacement_bot] == inherited_hand &&
  replaced.accepted_events.length == original_events.length, "second replacement lost historical exchange state")
assert(replacement_snapshot.events == original_events && replaced.history.map(&:to_h) == original_history,
  "second replacement changed the immutable log")
observer_replay = room.replay("Watcher")
assert(observer_replay.state == replaced.state, "observer projection disagrees after physical replacements")
ThreeFiveEightIntegration.continue_play(room)
advanced, = ThreeFiveEightIntegration.position(room)
assert(advanced.accepted_events.length > original_events.length, "replacement game did not continue")

# Actual common surfaces and event handlers, using the shared UI doubles.
[:choosing_contract, :discarding, :playing, :exchanging].each do |phase|
  position = positions.fetch(phase)
  actor = position.current_player
  surface = GameSurfaces.build(game.surface_spec(position, actor))
  emitted = nil
  surface.on_action { |action| emitted = action }
  if phase == :choosing_contract
    surface.fields[1].trigger(:press)
  else
    surface.fields.first.trigger(:select, [0])
    if phase == :exchanging
      assert(emitted.nil? && surface.cancel_pending_action?, "exchange skipped its recipient choice")
      surface.fields.first.trigger(:select, [0])
    end
  end
  assert(emitted, "#{phase} surface did not emit an action")
  status, = game.action_for(emitted, position, actor)
  assert(status == :ok, "#{phase} surface emitted an invalid action")
end

playing = positions.fetch(:playing)
actor = playing.current_player
original_hand = playing.state[:hands][actor].dup
surface = GameSurfaces.build(game.surface_spec(playing, actor))
cursor = ThreeFiveEightIntegration.hand_cursor(surface)
assert(cursor["raw_ids"] == original_hand && cursor["epoch"] == "#{actor}:#{playing.state[:round]}",
  "hand lost acquisition order or ownership/deal identity")
original_ids = cursor["ids"].dup
selected = cursor["selected_id"]
shortcuts = game.game_shortcuts(playing, actor)
["colour", "number"].each do |mode|
  shortcut = shortcuts.find { |entry| entry.kind == :surface && entry.action_name == "sort_cards" && entry.payload["mode"] == mode }
  assert(shortcut && surface.handle_command(shortcut.action_name, shortcut.payload), "hand sorting #{mode} is unavailable")
  cursor = ThreeFiveEightIntegration.hand_cursor(surface)
  assert(cursor["selected_id"] == selected && cursor["ids"].sort == original_ids.sort, "sorting changed selected card or hand")
end
assert(shortcuts.none? { |entry| entry.action_name == 'sort_cards' && entry.payload['mode'] == 'none' }, 'Removed order still has a shortcut')
assert(!surface.handle_command('sort_cards', 'mode'=>'none'), 'A retained removed-order callback was accepted')
assert(ThreeFiveEightIntegration.hand_cursor(surface)['raw_ids'] == original_hand, 'Physical receipt metadata changed')
assert(playing.state[:hands][actor] == original_hand, "view sorting mutated game state")
[-1, 1].each do |direction|
  shortcut = shortcuts.find { |entry| entry.key == "z" && entry.modifiers == (direction < 0 ? [:shift] : []) }
  assert(shortcut && surface.handle_command(shortcut.action_name, shortcut.payload), "legal-card navigation failed")
  selected = ThreeFiveEightIntegration.hand_cursor(surface)["selected_id"]
  assert(game.playable_card_navigation(playing, actor)[:card_actions].key?(selected), "Z selected an illegal card")
end
assert(game.playable_card_navigation(positions[:exchanging], positions[:exchanging].current_player).nil?,
  "exchange incorrectly permits automatic legal-card play")
single_card_turn = original_events.each_index.filter_map do |index|
  candidate = game.replay(snapshot.session, original_events.first(index + 1), repository)
  next unless candidate.state[:phase] == :playing
  candidate if game.legal_actions(candidate, candidate.current_player).length == 1
end.first
assert(single_card_turn, "legal fixture never reached a one-card choice")
single_surface = GameSurfaces.build(game.surface_spec(single_card_turn, single_card_turn.current_player))
single_z = game.game_shortcuts(single_card_turn, single_card_turn.current_player).find { |entry| entry.key == "z" && entry.modifiers.empty? }
automatic = single_surface.handle_command(single_z.action_name, single_z.payload)
assert(automatic.is_a?(GameSurfaces::Action), "one unambiguous legal card was not emitted by Z")
status, plan = game.action_for(automatic, single_card_turn, single_card_turn.current_player)
expected_card = game.legal_actions(single_card_turn, single_card_turn.current_player).first.fetch("card")
assert(status == :ok && plan.events.first.value == expected_card, "automatic navigation bypassed or changed the legal card")
assert(game.surface_spec(playing, "Watcher").zones.first.cards.empty?, "observer received a private hand")
assert(game.playable_card_navigation(playing, "Watcher").nil?, "observer can navigate another person's legal cards")
puts "PASS 3-5-8 integration: archive exchange restore, physical bot/human replacements, continuing play, card UI/navigation/sort and event audio"
