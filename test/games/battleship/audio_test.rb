require_relative "../../support/ui"
require_relative "../../../lib/game_surfaces"
require_relative "../../support/new_games_fixture"
require_relative "../../../lib/game_sounds"
require_relative "../../../lib/game_room_preferences"
require "digest"

assets = {
  "hit_ship1" => "d470f12aa263041c99026210dd5419ac43953fe61efc261e64b771da84f1b5b5",
  "hit_ship2" => "7472f93bbea2dc6bdaed09ab21a75fe0f163f36dcb840e62ed06910aa63cf936",
  "rocket_launch1" => "9dee002f48495bc43932679f1bf8b378cdf73d5ff746443ef0ff1d3632587ed7",
  "rocket_launch2" => "65e86b69b871c0fda6c4a537f6536ab0045d8d7bd0c74f02fb31fcc54177ffb1",
  "rocket_launch3" => "aaed65dcba7931ca6b9337bb2a1d934da64ef6972049eff89db7225adc1aaefb",
  "rocket_miss" => "4ee9eb016b3f21d399f317ab85415b5b1e0d7ec62bffcce8e449be1cf2fd806d"
}
manifest = JSON.parse(File.read(File.expand_path("../../../manifest.json", __dir__)))
app = File.read(File.expand_path("../../../__app.rb", __dir__))
embedded = JSON.parse(app.split("=begin Elten3AppInfo", 2).last.split("=end Elten3AppInfo", 2).first)
assert(manifest == embedded, "sound manifests disagree")
assets.each do |name, hash|
  path = File.expand_path("../../../Audio/#{name}.opus", __dir__)
  assert(GameRoomSounds::ASSET_NAMES.include?(name) && manifest.dig("required_assets", "sounds").include?(name), "unregistered sound #{name}")
  assert(File.binread(path, 4) == "OggS" && Digest::SHA256.file(path).hexdigest == hash, "altered audio #{name}")
end
assert(!GameRoomSounds::ASSET_NAMES.include?("hit_ship3"), "unavailable third hit was registered")
gains = assets.keys.to_h { |name| [name, 0.2] }.merge("war_open" => 0.6)
volume_assets = gains.keys + %w[connect disconnect chatmsg notice table_notice ding shuffle card-shuffle draw draw2 hit1 play win1 lose1]

game = GameRoomGames::Battleship.new
repo = NewGames116Repository.new(%w[Alice Bob])
session = { "options" => JSON.generate(game.default_options) }
events = %w[Alice Bob].each_with_index.map { |actor, i| { "id" => i + 1, "actor" => actor, "action" => "place", "value" => "a" * 64 } }
ready = game.replay(session, events, repo)
shot_event = { "id" => 3, "actor" => "Alice", "action" => "shoot", "value" => "0" }
shot = game.replay(session, events + [shot_event], repo)
GameRoomSounds.instance_variable_set(:@sound_random, Random.new(229))
launches = 40.times.map { GameRoomSounds.event_cue(game: game, event: shot_event, before_replay: ready, after_replay: shot, repository: repo, viewer: "Observer") }
assert(launches.uniq.sort == GameRoomSounds::BATTLESHIP_LAUNCHES.sort, "launch randomization omitted or added a variant")
hits = []
%w[hit sunk miss].each do |result|
  event = { "id" => 4, "actor" => "Bob", "action" => "answer", "value" => result }
  after = game.replay(session, events + [shot_event, event], repo)
  %w[Alice Bob Observer].each do |viewer|
    cue = GameRoomSounds.event_cue(game: game, event: event, before_replay: shot, after_replay: after, repository: repo, viewer: viewer)
    assert(result == "miss" ? cue == "rocket_miss" : GameRoomSounds::BATTLESHIP_HITS.include?(cue), "wrong #{result} cue for #{viewer}")
  end
  40.times do
    cue = GameRoomSounds.event_cue(game: game, event: event, before_replay: shot, after_replay: after, repository: repo, viewer: "Alice")
    hits << cue unless result == "miss"
  end
end
assert(hits.uniq.sort == GameRoomSounds::BATTLESHIP_HITS.sort, "hit randomization omitted or added a variant")

levels = { "sound_volumes" => { "all" => 50, "game" => 40 } }
played = []
program = Object.new
program.define_singleton_method(:game_room_sound_volume) { |name| GameRoomPreferences.sound_volume(levels, name) }
program.define_singleton_method(:play_sound_from_asset) { |name, volume:| played << [name, volume]; Object.new }
GameRoomSounds.play_all(program, assets.keys)
assert(played.map(&:first) == assets.keys && played.all? { |_, volume| (volume - 0.04).abs < 1e-9 }, "Battleship gain must multiply master and game volume")
levels["sound_volumes"]["game"] = 0
assets.each { |name| assert(GameRoomSounds.play(program, name) == nil, "muted sound returns a waiting handle") }
assert(played.length == assets.length, "muted audio still played")

handle = Object.new
program.define_singleton_method(:play_sound_from_asset) { |name, volume:| played << [name, volume]; handle }
[0, 20, 50, 100].each do |master|
  [0, 10, 20, 50, 100].each do |game_volume|
    levels["sound_volumes"].merge!("all" => master, "game" => game_volume)
    before = Marshal.dump(levels)
    volume_assets.each do |name|
      played.clear
      result = GameRoomSounds.play(program, name)
      expected = GameRoomPreferences.sound_volume(levels, name) * gains.fetch(name, 1.0)
      if expected.zero?
        assert(result == nil && played.empty?, "muted #{name} played or returned a handle")
      else
        assert(result.equal?(handle), "#{name} lost its playback handle")
        assert(played.length == 1 && played.first.first == name && (played.first.last - expected).abs < 1e-9, "wrong gain for #{name}: #{played.inspect}")
      end
    end
    assert(Marshal.dump(levels) == before, "playback changed the user's volume settings")
  end
end

# A caller without saved volume settings gets the same base balance. Return the
# original sound object so serial presentation still waits for actual completion.
default_program = Object.new
default_program.define_singleton_method(:play_sound_from_asset) { |name, volume: 1.0| played << [name, volume]; handle }
volume_assets.each do |name|
  played.clear
  assert(GameRoomSounds.play(default_program, name).equal?(handle), "default playback lost its handle")
  assert(played == [[name, gains.fetch(name, 1.0)]], "default asset gain for #{name}")
end
program.define_singleton_method(:game_room_sound_enabled?) { |_name| false }
played.clear
assets.each { |name| assert(GameRoomSounds.play(program, name) == nil, "disabled effect returned a handle") }
assert(played.empty?, "asset gain bypassed the sound switch")
assert(game.serial_event_presentation? && !GameRoomGames::Uno.new.serial_event_presentation?, "serial audio affected another game")
puts "PASS Battleship sounds: six unchanged assets at 20% gain, the war sound at 60%, both manifests, random variants, all viewers, volume controls, default gain, mute, handles, unchanged preferences and game/room/result control sounds"
