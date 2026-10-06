require_relative "../../support/mille_bornes"
require_relative "../../../lib/game_sounds"
require_relative "../../../lib/game_room_preferences"
require "digest"

include MilleBornesTest

def sound_step(fixture, state, actor, selection, viewer: actor)
  before = fixture.snapshot(Marshal.load(Marshal.dump(state)))
  status, plan = fixture.game.action_for(selection, before, actor, context: fixture.context)
  MilleBornesTest.equal(:ok, status, "sound action accepted")
  command = plan.events.fetch(0)
  identifier = 100 + state[:action_number]
  event = MilleBornesTest.event(identifier, actor, command.action, command.value)
  history = []
  accepted = fixture.game.send(:apply_event, state, event, actor, identifier, history)
  MilleBornesTest.assert(accepted, "sound event accepted by model")
  after = fixture.snapshot(state)
  after.history = history
  after.accepted_events = [event]
  cues = GameRoomSounds.event_cue(game: fixture.game, event: event, before_replay: before,
    after_replay: after, repository: fixture.repository, viewer: viewer)
  [Array(cues), event, before, after]
end

test("every mileage, hazard, remedy and safety uses its realistic sound mapping") do
  expected = {
    "25" => "mille_distance_25", "50" => "mille_distance_50", "75" => "mille_distance_75",
    "100" => "mille_distance_100", "200" => "mille_distance_200", "stop" => "mille_red_light",
    "speed_limit" => "mille_speed_limit", "out_of_gas" => "mille_fuel_drain",
    "flat_tire" => "mille_tire_puncture", "accident" => "mille_accident", "go" => "mille_start",
    "end_limit" => "mille_end_speed_limit", "fuel" => "mille_refuel", "spare_tire" => "mille_wheel_change",
    "repairs" => "mille_repair", "right_of_way" => "mille_right_of_way", "extra_tank" => "mille_extra_tank",
    "puncture_proof" => "mille_puncture_proof", "driving_ace" => "mille_driving_ace",
    "instant_repair" => "mille_instant_repair",
    "counterflow" => "mille_counterflow", "end_counterflow" => "mille_end_counterflow"
  }
  equal(GameRoomGames::MilleBornes::CARD_ORDER.sort, expected.keys.sort, "every card type has a cue")
  equal(expected.length, expected.values.uniq.length, "each card needs its own recording")
  expected.each do |type, sound|
    fixture = Fixture.new(options: { "include_instant_repairs" => type == "instant_repair", "counterflow" => true })
    state = fixture.scenario
    state[:hands]["Alice"] = ["#{type}:1", "25:9"]
    state[:tracks].each { |track| track[:moving] = true }
    track = state[:tracks][0]
    track[:moving] = false if type == "go"
    track[:speed_limit] = true if type == "end_limit"
    track[:counterflow] = true if type == "end_counterflow"
    if (hazard = fixture.game.class::REMEDIES[type]) && !%w[speed_limit counterflow].include?(hazard)
      track[:hazards] = [hazard]
      track[:moving] = false
    end
    selection = { "kind" => "card", "action" => "play", "card" => "#{type}:1" }
    if type == "instant_repair"
      track[:hazards] = ["accident"]
      track[:moving] = false
      selection["problem"] = "accident"
    end
    selection["target"] = "1" if fixture.game.class::HAZARDS.include?(type)
    cues, event, _before, after = sound_step(fixture, state, "Alice", selection, viewer: "Observer")
    equal([sound], cues, "#{type} cue")
    duplicate = GameRoomSounds.event_cue(game: fixture.game, event: event, before_replay: after,
      after_replay: after, repository: fixture.repository, viewer: "Alice")
    equal(nil, duplicate, "duplicate presentation is silent")
  end
end

test("red light reaches the shared sound output for the attacker, target and observer") do
  %w[Alice Bob Observer].each do |viewer|
    fixture = Fixture.new
    state = fixture.scenario
    state[:hands]["Alice"] = %w[stop:1 25:9]
    state[:tracks][1][:moving] = true
    cues, event, before, after = sound_step(fixture, state, "Alice",
      { "kind" => "card", "action" => "play", "card" => "stop:1", "target" => "1" }, viewer: viewer)
    equal(["mille_red_light"], cues, "red-light cue for #{viewer}")
    assert(after.state[:tracks][1][:hazards].include?("stop") && !after.state[:tracks][1][:moving],
      "red light must be applied before its cue")
    played = []
    program = Object.new
    program.define_singleton_method(:game_room_sound_volume) { |_name| 0.4 }
    program.define_singleton_method(:play_sound_from_asset) do |name, volume:|
      played << [name, volume]
      Object.new
    end
    GameRoomSounds.play_event(program, game: fixture.game, event: event, before_replay: before,
      after_replay: after, repository: fixture.repository, viewer: viewer)
    equal([["mille_red_light", 0.4]], played, "red light must not be silent for #{viewer}")
    GameRoomSounds.play_event(program, game: fixture.game, event: event, before_replay: after,
      after_replay: after, repository: fixture.repository, viewer: viewer)
    equal(1, played.length, "reconstructed red light must not repeat")
  end
end

test("five mileage cues remain distinct during counterflow and at zero miles") do
  expected = %w[mille_distance_25 mille_distance_50 mille_distance_75 mille_distance_100 mille_distance_200]
  [0, 300].each do |miles|
    cues = %w[25 50 75 100 200].map do |distance|
      fixture = Fixture.new(options: { "counterflow" => true, "counterflow_cards" => 3, "end_counterflow_cards" => 4 })
      state = fixture.scenario
      state[:hands]["Alice"] = ["#{distance}:1", "go:1"]
      state[:tracks][0].merge!(moving: true, counterflow: true, miles: miles)
      sounds, _event, _before, after = sound_step(fixture, state, "Alice",
        { "kind" => "card", "action" => "play", "card" => "#{distance}:1" }, viewer: "Observer")
      equal([miles - distance.to_i, 0].max, after.state[:tracks][0][:miles], "counterflow distance changed")
      equal(1, sounds.length, "one mileage cue expected")
      sounds.first
    end
    equal(expected, cues, "distance identity lost during counterflow")
    equal(5, cues.uniq.length, "distance cues share one sound")
  end
end

test("counterflow uses dedicated attack and remedy cues and preserves both dirty-trick effects") do
  fixture = Fixture.new(options: { "counterflow" => true, "counterflow_cards" => 3, "end_counterflow_cards" => 4 })
  state = fixture.scenario
  state[:hands]["Alice"] = %w[counterflow:1 25:1]
  state[:hands]["Bob"] = %w[end_counterflow:1 25:2]
  cues, attack, before, after = sound_step(fixture, state, "Alice",
    { "kind" => "card", "action" => "play", "card" => "counterflow:1", "target" => "1" }, viewer: "Observer")
  equal(["mille_counterflow"], cues, "attack cue")
  equal(nil, GameRoomSounds.event_cue(game: fixture.game, event: attack, before_replay: after,
    after_replay: after, repository: fixture.repository, viewer: "Alice"), "repeated attack presentation silent")
  state[:phase] = :playing
  cues, = sound_step(fixture, state, "Bob", { "kind" => "card", "action" => "play", "card" => "end_counterflow:1" })
  equal(["mille_end_counterflow"], cues, "remedy cue")
  state = Marshal.load(Marshal.dump(before.state))
  state[:hands]["Bob"] = %w[driving_ace:1 25:2]
  sound_step(fixture, state, "Alice", { "kind" => "card", "action" => "play", "card" => "counterflow:1", "target" => "1" })
  action = fixture.game.legal_actions(fixture.snapshot(state), "Bob").find { |candidate| candidate["action"] == "dirty_trick" }
  cues, event, _before, after = sound_step(fixture, state, "Bob", action)
  equal(%w[mille_driving_ace mille_dirty_trick], cues, "ace and dirty trick have independent ordered cues")
  equal(nil, GameRoomSounds.event_cue(game: fixture.game, event: event, before_replay: after,
    after_replay: after, repository: fixture.repository, viewer: "Bob"), "repeated counterflow dirty trick is silent")
end

test("every dirty trick plays its safety then a distinct success cue once through the shared selector") do
  {
    "extra_tank" => ["out_of_gas", "mille_extra_tank"],
    "puncture_proof" => ["flat_tire", "mille_puncture_proof"],
    "right_of_way" => ["stop", "mille_right_of_way"],
    "driving_ace" => ["accident", "mille_driving_ace"]
  }.each do |safety, (hazard, sound)|
    fixture = Fixture.new
    state = fixture.scenario
    state[:tracks][1][:moving] = true
    state[:hands]["Alice"] = ["#{hazard}:1", "25:1"]
    state[:hands]["Bob"] = ["#{safety}:1", "25:2"]
    sound_step(fixture, state, "Alice", { "kind" => "card", "action" => "play", "card" => "#{hazard}:1", "target" => "1" })
    action = fixture.game.legal_actions(fixture.snapshot(state), "Bob").find { |candidate| candidate["action"] == "dirty_trick" }
    assert(action, "#{safety} did not offer a legal dirty trick")
    cues, event, before, after = sound_step(fixture, state, "Bob", action)
    equal([sound, "mille_dirty_trick"], cues, "#{safety} independent simultaneous effects")
    %w[Alice Bob Observer].each do |viewer|
      equal(cues, Array(GameRoomSounds.event_cue(game: fixture.game, event: event, before_replay: before,
        after_replay: after, repository: fixture.repository, viewer: viewer)), "#{safety} cues differ for #{viewer}")
      equal(nil, GameRoomSounds.event_cue(game: fixture.game, event: event, before_replay: after,
        after_replay: after, repository: fixture.repository, viewer: viewer), "#{safety} repeated presentation is not silent")
      equal(nil, GameRoomSounds.event_cue(game: fixture.game, event: event, before_replay: nil,
        after_replay: after, repository: fixture.repository, viewer: viewer), "#{safety} initial replay is not silent")
    end
    original_cues = fixture.game.method(:event_sound_cues)
    fixture.game.define_singleton_method(:event_sound_cues) { |**arguments| Array(original_cues.call(**arguments)) * 2 }
    equal([sound, "mille_dirty_trick"], GameRoomSounds.event_cue(game: fixture.game, event: event, before_replay: before,
      after_replay: after, repository: fixture.repository, viewer: "Bob"), "shared selector failed to deduplicate repeated #{safety} and success cues")
  end
end

test("deal, draw, discard, rejected events and initial reconstruction") do
  fixture = Fixture.new
  before = fixture.replay
  after = fixture.start
  cue = ->(event, earlier, later) do
    GameRoomSounds.event_cue(game: fixture.game, event: event, before_replay: earlier,
      after_replay: later, repository: fixture.repository, viewer: "Alice")
  end
  equal("shuffle", cue.call(fixture.events.last, before, after), "deal")
  equal(nil, cue.call(fixture.events.last, nil, after), "silent initial reconstruction")
  before = after
  after = fixture.act("Alice", { "kind" => "command", "action" => "draw" })
  equal("draw", cue.call(fixture.events.last, before, after), "draw")
  before = after
  card = after.state[:hands]["Alice"].first
  after = fixture.act("Alice", { "kind" => "card", "action" => "discard", "card" => card })
  equal("play", cue.call(fixture.events.last, before, after), "discard")
  rejected = MilleBornesTest.event(999, "Observer", "play", "200:1|")
  replay = fixture.game.replay(fixture.session, fixture.events + [rejected], fixture.repository)
  equal(nil, cue.call(rejected, after, replay), "rejected attack is silent")
end

test("finishing a team game preserves mileage and the correct victory sound") do
  fixture = Fixture.new(players: %w[Alice Bob Carol David], options: { "team_count" => 2, "target_score" => 100 })
  state = fixture.scenario
  state[:tracks][0][:moving] = true
  state[:tracks][0][:miles] = 975
  state[:hands]["Alice"] = %w[25:1 50:1]
  _cues, event, before, after = sound_step(fixture, state, "Alice", { "kind" => "card", "action" => "play", "card" => "25:1" })
  assert(after.finished?, "team match should finish")
  fixture.players.each_with_index do |viewer, seat|
    cues = GameRoomSounds.event_cue(game: fixture.game, event: event, before_replay: before,
      after_replay: after, repository: fixture.repository, viewer: viewer)
    result = state[:seats][seat] == 0 ? "win_party" : "lose_party"
    equal(["mille_distance_25", result], cues, "#{viewer} team result")
  end
end

test("recycling the discard pile emits both shuffle and draw") do
  fixture = Fixture.new(options: { "recycle_discard" => true })
  state = fixture.scenario
  state[:draw_pile] = []
  state[:discard] = %w[200:1 200:2]
  state[:phase] = :awaiting_draw
  cues, event, before, after = sound_step(fixture, state, "Alice", { "kind" => "command", "action" => "draw" })
  raw_cues = fixture.game.event_sound_cues(event: event, before_replay: before, after_replay: after,
    history: after.history, viewer: "Alice", random_variant: GameRoomSounds.method(:random_variant))
  equal(%w[card-shuffle draw], raw_cues, "game supplies independent recycling and draw effects")
  equal(%w[card-shuffle draw], cues, "shuffle and draw are independent effects")
  equal(1, state[:recycle_count], "discard pile actually recycled")
end

test("accident playback applies 0.7 gain at maximum and user volume and respects mute") do
  levels = { "sound_volumes" => { "all" => 100, "game" => 100 } }
  played = []
  program = Object.new
  program.define_singleton_method(:game_room_sound_volume) { |name| GameRoomPreferences.sound_volume(levels, name) }
  program.define_singleton_method(:play_sound_from_asset) do |name, volume:|
    played << [name, volume]
    Object.new
  end

  GameRoomSounds.play(program, "mille_accident")
  equal([["mille_accident", 0.7]], played, "accident gain at maximum volume")
  levels["sound_volumes"].merge!("all" => 50, "game" => 40)
  GameRoomSounds.play(program, "mille_accident")
  equal(%w[mille_accident mille_accident], played.map(&:first), "accident plays at user volume")
  assert((played.last.last - 0.14).abs < 0.000001, "accident gain ignores master or game volume")
  GameRoomSounds.play(program, "mille_start")
  equal(["mille_start", 0.2], played.last, "accident gain must not attenuate other cues")

  levels["sound_volumes"]["game"] = 0
  GameRoomSounds.play(program, "mille_accident")
  equal(3, played.length, "game mute prevents accident playback")
  levels["sound_volumes"].merge!("all" => 0, "game" => 100)
  GameRoomSounds.play(program, "mille_accident")
  equal(3, played.length, "master mute prevents accident playback")
  levels["sound_volumes"]["all"] = 100
  GameRoomSounds.play(program, "mille_accident")
  equal(4, played.length, "unmuting restores accident playback")
  equal(["mille_accident", 0.7], played.last, "unmuting preserves accident gain")
  program.define_singleton_method(:game_room_sound_enabled?) { |_name| false }
  GameRoomSounds.play(program, "mille_accident")
  equal(4, played.length, "disabled sounds prevent accident playback at maximum volume")
end

test("balanced cue gains respect both volume controls, mute and sound settings") do
  { "mille_driving_ace" => 0.75, "mille_right_of_way" => 0.8,
    "mille_distance_25" => 1.0, "mille_distance_50" => 0.35, "mille_distance_75" => 0.35,
    "mille_distance_100" => 0.5, "mille_distance_200" => 1.0,
    "mille_wheel_change" => 0.5, "mille_instant_repair" => 0.65,
    "mille_speed_limit" => 0.35, "mille_tire_puncture" => 0.8,
    "mille_extra_tank" => 0.7, "mille_end_counterflow" => 0.7,
    "mille_puncture_proof" => 1.0, "mille_end_speed_limit" => 1.0 }.each do |sound, gain|
    levels = { "sound_volumes" => { "all" => 100, "game" => 100 } }
    played = []
    program = Object.new
    program.define_singleton_method(:game_room_sound_volume) { |name| GameRoomPreferences.sound_volume(levels, name) }
    program.define_singleton_method(:play_sound_from_asset) do |name, volume:|
      played << [name, volume]
      Object.new
    end
    GameRoomSounds.play(program, sound)
    equal([[sound, gain]], played, "#{sound} maximum gain")
    levels["sound_volumes"].merge!("all" => 50, "game" => 40)
    GameRoomSounds.play(program, sound)
    assert((played.last.last - gain * 0.2).abs < 0.000001, "#{sound} user volume ignored")
    levels["sound_volumes"]["game"] = 0
    GameRoomSounds.play(program, sound)
    levels["sound_volumes"].merge!("all" => 0, "game" => 100)
    GameRoomSounds.play(program, sound)
    equal(2, played.length, "#{sound} mute ignored")
    levels["sound_volumes"]["all"] = 100
    GameRoomSounds.play(program, sound)
    equal([sound, gain], played.last, "#{sound} gain after unmute")
    equal(3, played.length, "#{sound} did not resume")
    program.define_singleton_method(:game_room_sound_enabled?) { |_name| false }
    GameRoomSounds.play(program, sound)
    equal(3, played.length, "#{sound} disabled sound ignored")
    program.define_singleton_method(:game_room_sound_enabled?) { |_name| true }
    GameRoomSounds.play(program, "mille_dirty_trick")
    equal(["mille_dirty_trick", 1.0], played.last, "safety gain must not attenuate the success cue")
  end
end

test("Mille Bornes audio has exactly twenty-three distinct registered Opus assets") do
  expected_names = %w[
    mille_accident mille_distance_75 mille_distance_100 mille_start mille_red_light mille_fuel_drain
    mille_refuel mille_tire_puncture mille_wheel_change mille_puncture_proof mille_counterflow mille_repair
    mille_driving_ace mille_right_of_way mille_dirty_trick
    mille_distance_25 mille_distance_50 mille_distance_200 mille_instant_repair
    mille_speed_limit mille_end_speed_limit mille_extra_tank mille_end_counterflow
  ].sort
  root = File.expand_path("../../..", __dir__)
  manifest = JSON.parse(File.read(File.join(root, "manifest.json")))
  equal(expected_names, GameRoomSounds::ASSET_NAMES.grep(/\Amille_/).sort, "registered Mille Bornes audio")
  equal(expected_names, manifest.fetch("required_assets").fetch("sounds").grep(/\Amille_/).sort,
    "declared Mille Bornes audio")
  asset_names = Dir.glob(File.join(root, "Audio", "mille_*.opus")).map { |path| File.basename(path, ".opus") }
  equal(expected_names, asset_names.sort, "Mille Bornes audio files")
  hashes = expected_names.map do |name|
    bytes = File.binread(File.join(root, "Audio", "#{name}.opus"))
    assert(bytes.start_with?("OggS") && bytes.byteslice(28, 8) == "OpusHead", "not Opus: #{name}")
    Digest::SHA256.hexdigest(bytes)
  end
  equal(expected_names.length, hashes.uniq.length, "distinct registered sounds must not be duplicate files")
end
