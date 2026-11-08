require_relative "../../support/bingo"
require_relative "../../../lib/game_sounds"

include BingoChecksSupport
game = GameRoomGames::Bingo.new
repository = BingoChecksSupport::Repository.new(%w[Alice Bob])
session = bingo_session(game, variant: "30", marking: "manual")
start = bingo_event(1, "Alice", "start", 'a' * 32)
draw = bingo_event(2, "Alice", "draw", "1")
before = game.replay(session, [start], repository)
after = game.replay(session, [start, draw], repository)
args = {event: draw, before_replay: before, after_replay: after, history: after.history, viewer: "Alice", random_variant: 0}
check(game.event_sound_cues(**args).include?("bingo_draw"), "Accepted draw is silent")
check(!game.event_sound_cues(**args.merge(before_replay: after)).include?("bingo_draw"), "Unchanged replay repeats the draw effect")
check(GameRoomSounds::ASSET_NAMES.include?("bingo_draw"), "Sound not in shared selector")
root = File.expand_path("../../..", __dir__)
check(File.binread(File.join(root, "Audio/bingo_draw.opus")).start_with?("OggS"), "Missing Opus sample")
check(JSON.parse(File.read(File.join(root, "manifest.json"))).dig("required_assets", "sounds").include?("bingo_draw"), "Sound not packaged")
check(File.read(File.join(root, "LICENSES/BINGO-SOUND.md")).include?("CC0"), "Sound provenance missing")
puts "Bingo sound: accepted-event cue, deduplication, shared volume asset, package declaration and CC0 provenance passed"
