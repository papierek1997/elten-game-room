def _(text)
  text
end

require "json"
require_relative "../lib/game_sounds"

def assert(condition, message)
  raise message if !condition
end

Replay = Struct.new(:players, :winner, :draw, :state, :history, keyword_init: true) do
  def finished?
    winner != nil || draw == true
  end
end
History = Struct.new(:event_id, :kind, :key, :actor, :value, keyword_init: true)

class SoundGame
  attr_reader :id

  def initialize(id)
    @id = id
  end

  def bot_reward(replay, viewer)
    GameRoomParticipants.same?(replay.winner, viewer) ? 1.0 : -1.0
  end
end

repository = Object.new
repository.define_singleton_method(:event_id) { |event| event.fetch("id") }
viewer = "Alice"

def cue(game_id, event, before, after, repository, viewer)
  GameRoomSounds.event_cue(
    game: SoundGame.new(game_id),
    event: event,
    before_replay: before,
    after_replay: after,
    repository: repository,
    viewer: viewer
  )
end

playing = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: {}, history: [])
root = File.expand_path("..", __dir__)
manifest = JSON.parse(File.read(File.join(root, "manifest.json"), encoding: "UTF-8"))
app_source = File.read(File.join(root, "__app.rb"), encoding: "UTF-8")
embedded_manifest = JSON.parse(app_source[/\A=begin Elten3AppInfo\s+(\{.*?\})\s+=end Elten3AppInfo/m, 1])
assert(manifest == embedded_manifest, "the source manifests disagree")
{
  "cht-bank" => "cht-bank.opus",
  "cht-cat-minus-8" => "cht-cat-minus-8.opus",
  "cht-cat-plus-8" => "cht-cat-plus-8.opus",
  "cht-lost-points" => "cht-lost-points.opus",
  "cht-roll-dice" => "cht-roll-dice.opus"
}.each do |asset, filename|
  assert(GameRoomSounds::ASSET_NAMES.include?(asset), "#{asset} is not registered")
  assert(manifest.dig("required_assets", "sounds").include?(asset), "#{asset} is missing from the manifest")
  assert(File.file?(File.join(root, "Audio", filename)), "#{filename} is missing")
end
cht_event = { "id" => 7999, "action" => "roll", "value" => "1" }
cht_after = playing.dup
cht_after.history = [History.new(event_id: 7999, kind: :lost_points)]
assert(cue("cat_head_tail", cht_event, playing, cht_after, repository, viewer) == %w[cht-roll-dice cht-lost-points], "one has the wrong Cat, head, tail sounds")
cht_after.history = [History.new(event_id: 7999, kind: :cat_minus)]
assert(cue("cat_head_tail", cht_event, playing, cht_after, repository, viewer) == %w[cht-roll-dice cht-cat-minus-8], "negative cat tail has the wrong sounds")
cht_after.history = [History.new(event_id: 7999, kind: :cat_plus)]
assert(cue("cat_head_tail", cht_event, playing, cht_after, repository, viewer) == %w[cht-roll-dice cht-cat-plus-8], "positive cat tail has the wrong sounds")
cht_after.history = [History.new(event_id: 7999, kind: :roll)]
assert(cue("cat_head_tail", cht_event, playing, cht_after, repository, viewer) == "cht-roll-dice", "an ordinary roll has the wrong sound")
cht_bank = { "id" => 7999, "action" => "bank", "value" => "" }
cht_after.history = [History.new(event_id: 7999, kind: :bank)]
assert(cue("cat_head_tail", cht_bank, playing, cht_after, repository, viewer) == "cht-bank", "banking has the wrong sound")
%w[rummy domino mexican_train].each do |game_id|
  event = { "id" => 8000, "action" => game_id, "value" => "compact" }
  sounds = game_id == "rummy" ? %w[shuffle draw play] : %w[domino_refill domino_take_chip domino_move_tile]
  %i[deal draw play].zip(sounds).each do |kind, sound|
    after = playing.dup
    after.history = [History.new(event_id: 8000, kind: kind)]
    assert(cue(game_id, event, playing, after, repository, viewer) == sound, "#{game_id} missing #{kind} sound")
  end
  after = playing.dup
  after.history = [History.new(event_id: 8000, kind: :play), History.new(event_id: 8000, kind: :round_result, actor: "Bob", value: ["Bob", "Alice"])]
  assert(cue(game_id, event, playing, after, repository, viewer) == [sounds.last, "win1"], "#{game_id} team round winner sound")
  after.history.last.value = ["Bob"]
  assert(cue(game_id, event, playing, after, repository, viewer) == [sounds.last, "lose1"], "#{game_id} round loser sound")
  assert(cue(game_id, event, playing, after, repository, "Observer") == sounds.last, "observer receives a result meant for players")
end
assert(cue("spades", { "id" => 1, "action" => "deal" }, playing, playing, repository, viewer) == "shuffle", "Spades did not shuffle on a deal")
assert(cue("spades", { "id" => 2, "action" => "play", "value" => "AS" }, playing, playing, repository, viewer) == ["play", "draw2"], "Spades trump did not layer draw2 over the card sound")
assert(cue("spades", { "id" => 3, "action" => "play", "value" => "AH" }, playing, playing, repository, viewer) == "play", "ordinary Spades card did not use play")

three_five_eight = Replay.new(players: [viewer, "Bob", "Carol"], winner: nil, draw: false, state: { contract: "H" }, history: [])
assert(cue("three_five_eight", { "id" => 31, "action" => "deal" }, playing, three_five_eight, repository, viewer) == "shuffle", "3-5-8 did not shuffle on a deal")
assert(cue("three_five_eight", { "id" => 32, "action" => "choose_contract" }, playing, three_five_eight, repository, viewer) == "ding", "3-5-8 contract selection has no sound")
assert(cue("three_five_eight", { "id" => 33, "action" => "play", "value" => "AH" }, playing, three_five_eight, repository, viewer) == %w[play draw2], "3-5-8 trump did not layer its sound")
assert(cue("three_five_eight", { "id" => 34, "action" => "discard", "value" => "2C" }, playing, three_five_eight, repository, viewer) == "draw", "3-5-8 discard has no sound")
three_five_eight.history = [History.new(event_id: 35, kind: :round_result, actor: viewer, value: 5)]
assert(cue("three_five_eight", { "id" => 35, "action" => "play", "value" => "2C" }, playing, three_five_eight, repository, viewer) == %w[play win1], "3-5-8 positive round result has no sound")

before_32 = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: { total: 32, eliminated: { viewer => false, "Bob" => false } }, history: [])
after_34 = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: { total: 34, eliminated: { viewer => false, "Bob" => false } }, history: [])
assert(cue("ninety_nine", { "id" => 4, "action" => "play", "value" => "05C|normal" }, before_32, after_34, repository, viewer) == ["play", "draw2"], "crossing 33 did not layer draw2 over the card sound")

before_98 = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: { total: 98, eliminated: { viewer => false, "Bob" => false } }, history: [])
after_99 = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: { total: 99, eliminated: { viewer => false, "Bob" => false } }, history: [])
assert(cue("ninety_nine", { "id" => 5, "actor" => viewer, "action" => "play", "value" => "0AC|one" }, before_98, after_99, repository, viewer) == ["play", "win1"], "the viewer reaching exactly 99 lost one of its sounds")
assert(cue("ninety_nine", { "id" => 6, "actor" => "Bob", "action" => "play", "value" => "0AC|one" }, before_98, after_99, repository, viewer) == ["play", "lose1"], "an opponent reaching exactly 99 lost one of its sounds")

after_100 = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: { total: 100, eliminated: { viewer => false, "Bob" => false } }, history: [])
assert(cue("ninety_nine", { "id" => 7, "actor" => viewer, "action" => "play", "value" => "02C|normal" }, before_98, after_100, repository, viewer) == ["play", "lose1"], "the viewer exceeding 99 lost one of its sounds")
assert(cue("ninety_nine", { "id" => 8, "actor" => "Bob", "action" => "play", "value" => "02C|normal" }, before_98, after_100, repository, viewer) == ["play", "win1"], "an opponent exceeding 99 lost one of its sounds")

three_active = Replay.new(players: [viewer, "Bob", "Carol"], winner: nil, draw: false, state: { total: 10, eliminated: { viewer => false, "Bob" => false, "Carol" => false } }, history: [])
assert(cue("ninety_nine", { "id" => 9, "action" => "play", "value" => "04C|normal" }, three_active, three_active, repository, viewer) == ["play", "reverse3"], "a Ninety-Nine direction change lost one of its sounds")
assert(cue("ninety_nine", { "id" => 10, "action" => "play", "value" => "0JC|normal" }, playing, playing, repository, viewer) == ["play", "reverse"], "a Ninety-Nine skip lost one of its sounds")
assert(cue("ninety_nine", { "id" => 11, "action" => "draw" }, playing, playing, repository, viewer) == "draw", "a Ninety-Nine draw did not use draw")

farkled = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: {}, history: [History.new(event_id: 12, kind: :farkle)])
assert(cue("farkle", { "id" => 12, "action" => "roll" }, playing, farkled, repository, viewer) == ["roll", "farkle"], "a Farkle did not keep both roll sounds")
before_hot_dice = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: { dice_to_roll: 2 }, history: [])
after_hot_dice = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: { dice_to_roll: 6 }, history: [])
assert(cue("farkle", { "id" => 13, "action" => "keep", "value" => "0,1" }, before_hot_dice, after_hot_dice, repository, viewer) == "replay", "hot dice did not use replay")
assert(cue("four_in_a_row", { "id" => 14, "action" => "drop" }, playing, playing, repository, viewer) == "play2", "a board piece did not use play2")
assert(cue("chess", { "id" => 141, "action" => "move" }, playing, playing, repository, viewer) == "play2", "a chess move did not use play2")
assert(cue("checkers", { "id" => 142, "action" => "move" }, playing, playing, repository, viewer) == "play2", "a checkers move did not use play2")
assert(cue("reversi", { "id" => 143, "action" => "place" }, playing, playing, repository, viewer) == "play2", "a Reversi move did not use play2")
assert(cue("ludo", { "id" => 144, "action" => "roll" }, playing, playing, repository, viewer) == "roll", "a Ludo roll did not use roll")
assert(cue("ludo", { "id" => 145, "action" => "move" }, playing, playing, repository, viewer) == "play2", "a Ludo pawn move did not use play2")
assert(cue("ludo", { "id" => 146, "action" => "move_pawn" }, playing, playing, repository, viewer) == "play2", "a semantic Ludo pawn move did not use play2")
uno_declared = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: {},
  history: [History.new(event_id: 1461, kind: :game, key: "uno:1461")])
assert(cue("uno", { "id" => 1461, "action" => "uno" }, playing, uno_declared, repository, viewer) == "buzzer2", "saying UNO did not use buzzer2")
assert(cue("uno", { "id" => 1462, "action" => "uno" }, playing, playing, repository, viewer) == nil, "a rejected UNO declaration played its sound")
assert(File.file?(File.expand_path("../Audio/buzzer2.opus", __dir__)), "the UNO declaration sound asset is missing")
makao_declared = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: {},
  history: [History.new(event_id: 1463, kind: :game, key: "makao:1463")])
assert(cue("makao", { "id" => 1463, "action" => "makao" }, playing, makao_declared, repository, viewer) == "buzzer2", "saying Makao did not use buzzer2")
assert(cue("makao", { "id" => 1464, "action" => "makao" }, playing, playing, repository, viewer) == nil, "a rejected Makao declaration played its sound")
automatic_ludo = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: {}, history: [History.new(event_id: 147, kind: :move)])
assert(cue("ludo", { "id" => 147, "action" => "roll" }, playing, automatic_ludo, repository, viewer) == ["roll", "play2"], "an automatic Ludo move lost one of its sounds")

completed_group = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: {},
  history: [History.new(event_id: 148, kind: :game, key: "group_complete:148:Alice:pink")])
assert(cue("monopoly", { "id" => 148, "action" => "buy" }, playing, completed_group, repository, viewer) == ["play2", "hit1"],
  "a completed Monopoly group did not keep the purchase sound and add hit1")
assert(cue("monopoly", { "id" => 149, "action" => "buy" }, playing, playing, repository, viewer) == "play2",
  "an ordinary Monopoly purchase gained the completed-group sound")
bankruptcy_group = Replay.new(players: [viewer, "Bob"], winner: nil, draw: false, state: {},
  history: [History.new(event_id: 150, kind: :game, key: "group_complete:150:Alice:pink")])
assert(cue("monopoly", { "id" => 150, "action" => "bankrupt" }, playing, bankruptcy_group, repository, viewer) == "hit1",
  "a group completed by bankruptcy has no completion sound")

won = Replay.new(players: [viewer, "Bob"], winner: viewer, draw: false, state: {}, history: [])
lost = Replay.new(players: [viewer, "Bob"], winner: "Bob", draw: false, state: {}, history: [])
assert(cue("four_in_a_row", { "id" => 15, "action" => "drop" }, playing, won, repository, viewer) == ["play2", "win_party"], "winning a game lost the move or result sound")
assert(cue("four_in_a_row", { "id" => 16, "action" => "drop" }, playing, lost, repository, viewer) == ["play2", "lose_party"], "losing a game lost the move or result sound")

tracker = GameRoomSounds::MembershipTracker.new
assert(tracker.observe([viewer]).empty?, "the first room snapshot announced an old member")
assert(tracker.observe([viewer, "Bob"]) == ["connect"], "a room join did not use connect")
assert(tracker.observe([viewer]) == ["disconnect"], "a room departure did not use disconnect")
assert(tracker.observe([viewer, "bot:1:1"]).empty?, "a computer was announced as a human room member")

program = Object.new
played = []
program.define_singleton_method(:play_sound_from_asset) { |name| played << name }
GameRoomSounds.play_all(program, ["welcome", "connect", "chatmsg", "not_registered"])
assert(played == ["connect", "chatmsg"], "the sound player rejected a chat asset or accepted an unknown asset")

filtered_program = Object.new
filtered_played = []
filtered_program.define_singleton_method(:play_sound_from_asset) { |name| filtered_played << name }
filtered_program.define_singleton_method(:game_room_sound_enabled?) { |name| name == "connect" }
GameRoomSounds.play_all(filtered_program, ["roll", "connect", "chatmsg"])
assert(filtered_played == ["connect"], "the sound player ignored the Game Room category filter")

puts "Game sound tests passed"
