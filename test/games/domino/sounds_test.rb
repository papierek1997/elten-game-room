if ARGV.first
  require_relative "../../support/binary_rules_load"
else
  require_relative "../../support/ui"
  require_relative "../../../lib/game_surfaces"
  require_relative "../../../lib/game_screen"
  require_relative "../../../lib/hidden_submissions"
  require_relative "../../../lib/saved_games"
  require_relative "../../../lib/game_room_preferences"
  require_relative "../../../games/domino"
  require_relative "../../../games/mexican_train"
end
require "digest"

def n_(one, many, count); count == 1 ? one : many; end
def assert(value, message); raise message unless value; end
module Session
  class << self; attr_accessor :name; end
end

def tile_sound_replay(state, history = [])
  GameRoomGames::Replay.new(players: state[:players], current_player: state[:current_player],
    winner: state[:winner], draw: state[:draw], state: state, history: history, accepted_events: [])
end

def tile_sound_position(game, actor = "Alice", options = {})
  state = game.initial_state([actor, "Bob"], game.normalize_options(options))
  state.merge!(phase: :playing, round: 1, turn: 1, turn_started: 100,
    current_player: actor, hands: { actor => %w[120 550], "Bob" => %w[440] }, stock: %w[330 220])
  if game.id == "domino"
    state[:chain] = [{ tile: "240", left: 2, right: 4 }]
  else
    state[:trains] = {
      "p0" => { owner: actor, end: 2, open: false, chain: [] },
      "p1" => { owner: "Bob", end: 4, open: false, chain: [] },
      "m" => { owner: nil, end: 2, open: true, chain: [] }
    }
  end
  state
end

repo = SavedGames::ReplayRepository.new
def repo.bot_turn_controller(_table_id); nil; end

def tile_sound_step(game, state, action, repository, actor: nil, time: 100, expected_status: :ok, **extra)
  actor ||= state[:current_player]
  data = { "action" => action, "round" => state[:round], "turn" => state[:turn], "time" => time }
    .merge(extra.transform_keys(&:to_s))
  before = tile_sound_replay(Marshal.load(Marshal.dump(state)))
  history = []
  status = game.send(:apply, state, data, actor, 50, history)
  assert(status == expected_status, "#{game.id}/#{action}: #{status}, expected #{expected_status}")
  event = { "id" => 50, "actor" => actor, "action" => game.id, "value" => game.send(:encode, data) }
  after = tile_sound_replay(state, history)
  [actor, "Bob", "Observer"].uniq.to_h do |viewer|
    [viewer, Array(GameRoomSounds.event_cue(game: game, event: event,
      before_replay: before, after_replay: after, repository: repository, viewer: viewer))]
  end
end

[GameRoomGames::Domino, GameRoomGames::MexicanTrain].each do |type|
  game = type.new
  ["Alice", "bot:1:1"].each do |actor|
    state = tile_sound_position(game, actor)
    target = game.id == "domino" ? "l" : "p0"
    sounds = tile_sound_step(game, state, "play", repo, tile: "120", target: target)
    assert(sounds.values.all? { |cues| cues == ["domino_move_tile"] }, "#{game.id}: accepted move/audience")

    state = tile_sound_position(game, actor)
    sounds = tile_sound_step(game, state, "play", repo, tile: "550", target: target, expected_status: :invalid)
    assert(sounds.values.all?(&:empty?), "#{game.id}: rejected move played a sound")

    state = tile_sound_position(game, actor)
    state[:hands][actor] = ["550"]
    sounds = tile_sound_step(game, state, "draw", repo)
    assert(state[:current_player] == "Bob", "#{game.id}: unplayable draw did not pass")
    assert(sounds.values.all? { |cues| cues == ["domino_take_chip"] }, "#{game.id}: draw plus pass")

    state = tile_sound_position(game, actor)
    state[:hands][actor] = ["550"]
    state[:stock] = ["220"]
    sounds = tile_sound_step(game, state, "draw", repo)
    assert(state[:current_player] == actor, "#{game.id}: playable draw changed turn")
    assert(sounds.values.all? { |cues| cues == ["domino_take_chip"] }, "#{game.id}: playable draw")
    sounds = tile_sound_step(game, state, "draw", repo, expected_status: :invalid)
    assert(sounds.values.all?(&:empty?), "#{game.id}: repeated draw played a sound")

    state = tile_sound_position(game, actor)
    state[:hands][actor] = ["550"]
    state[:stock] = []
    sounds = tile_sound_step(game, state, "draw", repo, expected_status: :invalid)
    assert(sounds.values.all?(&:empty?), "#{game.id}: empty boneyard draw")
    sounds = tile_sound_step(game, state, "pass", repo)
    assert(sounds.values.all?(&:empty?), "#{game.id}: pass sounds like taking a tile")

    state = tile_sound_position(game, actor)
    state[:hands][actor] = ["120"]
    sounds = tile_sound_step(game, state, "play", repo, tile: "120", target: target)
    assert(sounds[actor] == %w[domino_move_tile win1], "#{game.id}: round winner")
    assert(sounds["Bob"] == %w[domino_move_tile lose1], "#{game.id}: round loser")
    assert(sounds["Observer"] == %w[domino_move_tile], "#{game.id}: observer")

    state = tile_sound_position(game, actor, "score_limit" => 10)
    state[:hands][actor] = ["120"]
    state[:scores]["Bob"] = 99
    sounds = tile_sound_step(game, state, "play", repo, tile: "120", target: target)
    assert(sounds[actor] == %w[domino_move_tile win1 win_party], "#{game.id}: game winner layering")
    assert(sounds["Bob"] == %w[domino_move_tile lose1 lose_party], "#{game.id}: game loser layering")
  end

  # Full action/replay/GameScreen path: a deal sounds once per viewer, not on
  # refresh, duplicate delivery, rejected events or reopening an old game.
  random = Object.new
  random.define_singleton_method(:roll) { |count:, sides:| Struct.new(:values).new(Array.new(count, 1)) }
  context = GameRoomGames::ActionContext.new(now: 100, random_source: random)
  session = { "__players" => %w[Alice Bob], "options" => JSON.generate(game.default_options) }
  before = game.replay(session, [], repo)
  status, plan = game.action_for({ "action" => "deal" }, before, "Alice", context: context)
  assert(status == :ok && plan.events.one?, "#{game.id}: deal plan")
  event = { "id" => 1, "actor" => "Alice", "action" => plan.events[0].action, "value" => plan.events[0].value }
  after = game.replay(session, [event], repo)
  %w[Alice Bob Observer].each do |viewer|
    Session.name = viewer
    played = []
    program = Object.new
    program.define_singleton_method(:play_sound_from_asset) do |name, volume:|
      raise "Unexpected domino volume: #{volume}" unless volume == 1.0
      played << name
      nil
    end
    screen = GameScreen.new(program: program, repository: repo, game: game, session: session,
      table: {}, table_owner: "Alice", room_snapshot_provider: nil, synchronizer: nil)
    screen.send(:process_new_events, before)
    assert(played.empty?, "#{game.id}: initial snapshot sound")
    screen.send(:process_new_events, after)
    assert(played == ["domino_refill"], "#{game.id}: live deal must use refill")
    screen.send(:process_new_events, game.replay(session, [event, event], repo))
    rejected = event.merge("id" => 2) # A second deal during play is invalid.
    screen.send(:process_new_events, game.replay(session, [event, rejected], repo))
    assert(played == ["domino_refill"], "#{game.id}: refresh/retry/rejection duplicated sound")
    screen = GameScreen.new(program: program, repository: repo, game: game, session: session,
      table: {}, table_owner: "Alice", room_snapshot_provider: nil, synchronizer: nil)
    screen.send(:process_new_events, after)
    assert(played == ["domino_refill"], "#{game.id}: replay on reopening made noise")
  end
end

game = GameRoomGames::Domino.new
state = tile_sound_position(game, "Alice", "draw_until" => true)
state[:hands]["Alice"] = ["550"]
state[:stock] = %w[660 330 220]
sounds = tile_sound_step(game, state, "draw", repo)
assert(state[:hands]["Alice"].length == 4, "draw-until fixture did not take three tiles")
assert(sounds.values.all? { |cues| cues == ["domino_take_chip"] }, "draw-until repeated its cue")
state = tile_sound_position(game, "Alice", "thinking_time" => 5)
state[:turn_deadline] = 105
sounds = tile_sound_step(game, state, "timeout", repo, time: 105)
assert(sounds.values.all? { |cues| cues == ["domino_take_chip"] }, "timeout draw has no cue")
state = tile_sound_position(game, "Alice", "thinking_time" => 5)
state.merge!(turn_deadline: 105, drawn: true)
sounds = tile_sound_step(game, state, "timeout", repo, time: 105)
assert(sounds.values.all?(&:empty?), "timeout without drawing has a cue")

assets = {
  "domino_refill" => "209459958aab87ef37c3bcd20cc323354c17b3d18e5c817288ede4be4c55a869",
  "domino_move_tile" => "695df75536d42400a0f813efc7a4dbd05845d6d99dc2fadbe39be677e2f5c40c",
  "domino_take_chip" => "654ffaf653c5cecfa772b3aea22329e791bdbdd75adf21475b6a1980655444c5"
}
manifest = JSON.parse(File.read(File.expand_path("../../../manifest.json", __dir__)))
app = File.read(File.expand_path("../../../__app.rb", __dir__))
embedded = JSON.parse(app.split("=begin Elten3AppInfo", 2).last.split("=end Elten3AppInfo", 2).first)
assert(manifest == embedded, "source manifests disagree")
assets.each do |name, hash|
  path = File.expand_path("../../../Audio/#{name}.opus", __dir__)
  assert(GameRoomSounds::ASSET_NAMES.include?(name) && manifest.dig("required_assets", "sounds").include?(name), "unregistered #{name}")
  assert(File.binread(path, 4) == "OggS" && Digest::SHA256.file(path).hexdigest == hash, "changed #{name}")
end
levels = { "sound_volumes" => { "all" => 50, "game" => 40 } }
played = []
program = Object.new
program.define_singleton_method(:game_room_sound_volume) { |name| GameRoomPreferences.sound_volume(levels, name) }
program.define_singleton_method(:play_sound_from_asset) { |name, volume:| played << [name, volume]; Object.new }
GameRoomSounds.play_all(program, assets.keys + ["win1"])
assert(played == (assets.keys + ["win1"]).map { |name| [name, 0.2] }, "layering/volume")
levels["sound_volumes"]["game"] = 0
GameRoomSounds.play_all(program, assets.keys)
assert(played.length == 4, "game mute ignored")
levels["sound_volumes"].merge!("game" => 100, "all" => 0)
GameRoomSounds.play_all(program, assets.keys)
assert(played.length == 4, "master mute ignored")
puts "PASS domino audio: both games, humans/bots/observers, accepted actions, draw batches/timeouts, results, replay silence, volume and assets"
