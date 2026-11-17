require_relative "../../support/elten_array_shuffle"
require_relative "../../support/ui"
require "json"
class Program
  def self.server_app(**_options); end
end
require_relative "../../../__app"
require_relative "../../../tools/training/match_runner"

def assert(condition, message)
  raise message unless condition
end

class WarRepository
  def initialize(players) = @players = players
  def players_for(_session) = @players
  def actor_of(event, _session = nil) = event.fetch("actor")
  def event_id(event) = event.fetch("id")
end

def war_session(game, options = {})
  { "options" => JSON.generate(game.normalize_options(options)) }
end

def war_play(game, session, repository, events, context)
  replay = game.replay(session, events, repository)
  actor = game.active_actors(replay).first || replay.players.first
  selection = game.automatic_action(replay, replay.players.first, context: context) ||
    game.legal_actions(replay, actor, context: context).first
  actor = replay.players.first if selection["action"] == "deal"
  status, plan = game.action_for(selection, replay, actor, context: context)
  raise "rejected #{selection} for #{actor}: #{status}" unless status == :ok
  plan.events.each do |command|
    assert(command.value.length <= GameRepository::MAX_VALUE_LENGTH, "an event value exceeds the repository limit")
    events << { "id" => events.length + 1, "actor" => actor, "action" => command.action, "value" => command.value }
  end
  game.replay(session, events, repository)
end

def state_replay(game, players, piles, options = {})
  state = game.send(:initial_state, players, game.normalize_options(options))
  state.update(phase: :playing, seed: "0" * 32, piles: piles)
  game.send(:start_battle, state)
  GameRoomGames::Replay.new(players: players, current_player: game.send(:current_actor, state), winner: nil, draw: false,
    state: state, history: [], accepted_events: [])
end

def apply(game, replay, count)
  history = []
  count.times do |index|
    player = game.send(:current_actor, replay.state)
    event = { "id" => index + 1, "actor" => player, "action" => "play", "value" => game.send(:step_key, replay.state) }
    assert(game.send(:apply_play, replay.state, event, player, WarRepository.new(replay.players), history), "a legal play was rejected")
  end
  history
end

game = EltenGameRoom::GAME_REGISTRY.build("war")
assert(game.is_a?(GameRoomGames::War) && game.name == "War", "War is not registered")
assert(game.minimum_players == 2 && game.maximum_players == 8 && game.supports_bots?, "wrong player range or bot support")
assert(game.default_options.values_at("deck", "battle_limit") == ["short", 20], "wrong default options")
assert(game.options_error({ "battle_limit" => 19 }) && game.options_error({ "battle_limit" => 301 }), "an invalid battle limit was accepted")
assert(game.options_error({ "battle_limit" => 20 }).nil? && game.options_error({ "battle_limit" => 300 }).nil?, "a valid battle limit was rejected")

players = %w[Alice Bob]
repository = WarRepository.new(players)
session = war_session(game)
context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SeededSource.new(5), now: 0)
events = []
replay = war_play(game, session, repository, events, context)
assert(replay.state[:phase] == :playing && replay.state[:piles].values.map(&:length) == [12, 12], "the short deck was not dealt equally")
assert(replay.current_player == "Alice", "the first player does not start")
assert(game.legal_actions(replay, "Bob").empty?, "a waiting player can play")
status, = game.action_for({ "kind" => "command", "action" => "play" }, replay, "Bob", context: context)
assert(status == :not_your_turn, "a waiting player was allowed to play")
surface = game.surface_spec(replay, "Alice")
assert(surface.zones.first.cards.map(&:id) == ["play"] && surface.zones.first.header.include?("12"), "the player surface lacks the play action or pile size")
assert(game.surface_spec(replay, "Bob").zones.first.cards.empty?, "a waiting player received the play action")
status, plan = game.action_for({ "kind" => "card", "action" => "select", "zone" => "actions", "card" => "play" }, replay, "Alice", context: context)
assert(status == :ok && plan.events.first.value == "0.0", "Enter on the surface did not play")

shortcuts = game.game_shortcuts(replay, "Alice").to_h { |item| [[item.key, item.modifiers], item] }
%w[t c e v space].each { |key| assert(shortcuts[[key, []]], "shortcut #{key} is missing") }
assert(shortcuts[["space", []]].action_name == "play", "Space does not play")
assert(shortcuts.keys.none? { |key, _| key == "z" }, "a pile without choices exposes card navigation")

stale = events + [{ "id" => 99, "actor" => "Alice", "action" => "play", "value" => "5.0" }]
assert(game.replay(session, stale, repository).accepted_events.length == events.length, "a play for another battle was accepted")
duplicate = events + [{ "id" => 1, "actor" => "Alice", "action" => "deal", "value" => events.first["value"] }]
assert(game.replay(session, duplicate, repository).accepted_events.length == 1, "a duplicate event was applied")

battle = state_replay(game, players, { "Alice" => %w[AS 9H], "Bob" => %w[KD TC] })
history = apply(game, battle, 2)
assert(battle.state[:piles]["Alice"].sort == %w[9H AS KD].sort && battle.state[:piles]["Bob"] == ["TC"], "the highest card did not take the table")
assert(history.any? { |entry| entry.kind == :take && entry.text.include?("takes 2 cards") }, "the battle result is missing")

war = state_replay(game, players, { "Alice" => %w[QS 9H AC TD], "Bob" => %w[QH JC KD 9S] })
history = apply(game, war, 2)
assert(history.any? { |entry| entry.kind == :war } && war.state[:depth] == 1, "equal cards did not start a war")
history = apply(game, war, 2)
assert(history.first.text.include?("hidden card"), "the war did not place a hidden card")
assert(war.state[:piles]["Alice"].length == 7 && war.state[:piles]["Bob"] == ["9S"], "the war winner did not take six cards")
won = GameRoomGames::Replay.new(players: players, state: war.state, history: history)
alice_hears = game.history_entries_for_display(won, "Alice").map(&:text).join(" ")
bob_hears = game.history_entries_for_display(won, "Bob").map(&:text).join(" ")
assert(alice_hears.include?("You win the war") && alice_hears.index("Your opponent's hidden cards: jack of clubs") < alice_hears.index("Your hidden cards: 9 of hearts"),
  "the war winner did not hear the opponent's hidden cards before their own: #{alice_hears}")
assert(alice_hears.include?("Other cards: queen of spades, queen of hearts, ace of clubs, king of diamonds."), "the war winner did not hear the other cards")
assert(bob_hears.include?("Alice wins the war") && bob_hears.include?("Your hidden cards: jack of clubs") && bob_hears.include?("Hidden cards of Alice: 9 of hearts"),
  "the loser did not hear the hidden cards: #{bob_hears}")
assert(game.game_shortcuts(won, "Alice").find { |item| item.key == "v" }.message.include?("Your hidden cards"), "V lost the hidden cards")
mid = state_replay(game, players, { "Alice" => %w[QS 9H AC TD], "Bob" => %w[QH JC KD 9S] })
apply(game, mid, 3)
assert(game.send(:table_text, mid.state, "Bob").start_with?("Bob: queen of hearts. Alice: queen of spades, ace of clubs, 1 hidden card"),
  "C does not read the listener's cards first: #{game.send(:table_text, mid.state, "Bob")}")
counter = game.game_shortcuts(mid, "Alice").find { |item| item.key == "t" && item.modifiers.to_a == [:alt, :control] }
assert(counter && counter.message == "Battle 1 of 20.", "Ctrl+Alt+T does not read the battle number: #{counter&.message}")
apply(game, mid, 1)
assert(game.game_shortcuts(mid, "Alice").find { |item| item.key == "t" && item.modifiers.to_a == [:alt, :control] }.message == "Battle 2 of 20.",
  "Ctrl+Alt+T did not advance after a battle")
assert(game.restart_guard_seconds >= 2, "a held Enter can restart a finished War game at once")

last = state_replay(game, players, { "Alice" => %w[QS KC], "Bob" => %w[QH] })
history = apply(game, last, 2)
assert(history.any? { |entry| entry.kind == :eliminated && entry.actor == "Bob" }, "a player without cards was not eliminated")
assert(last.state[:phase] == :finished && last.state[:winner] == "Alice", "a player without cards could continue the war")

three = state_replay(game, %w[Alice Bob Carol], { "Alice" => %w[KS 9C AH], "Bob" => %w[KH TC 9D], "Carol" => %w[AS QD JH] })
apply(game, three, 3)
assert(three.state[:piles]["Carol"].length == 5, "the single highest card among three players did not win")
tie = state_replay(game, %w[Alice Bob Carol], { "Alice" => %w[KS 9C AH], "Bob" => %w[KH TC 9D], "Carol" => %w[QS JD JH] })
apply(game, tie, 3)
assert(tie.state[:contenders] == %w[Alice Bob] && game.send(:current_actor, tie.state) == "Alice", "only the tied players should fight the war")
apply(game, tie, 2)
assert(tie.state[:piles]["Alice"].length == 7 && tie.state[:piles]["Carol"].length == 2, "the war winner did not take the bystander's card")

limit = state_replay(game, players, { "Alice" => %w[AS KS 9H], "Bob" => %w[9C TC JC] }, "battle_limit" => 20)
limit.state[:battle] = 19
apply(game, limit, 2)
assert(limit.state[:phase] == :finished && limit.state[:limit_reached] && limit.state[:winner] == "Alice", "the battle limit did not end the game")

full = war_session(game, "deck" => "full")
events = []
war_play(game, full, WarRepository.new(%w[A B C]), events, GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SeededSource.new(3)))
counts = game.replay(full, events, WarRepository.new(%w[A B C])).state[:piles].values.map(&:length)
assert(counts.sum == 52 && counts.sort == [17, 17, 18], "the full deck was not dealt")

lengths = [2, 3, 4, 8].flat_map do |count|
  12.times.map do |seed|
    names = count.times.map { |index| "P#{index}" }
    repo = WarRepository.new(names)
    session = war_session(game)
    ctx = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SeededSource.new(seed + 40 * count))
    events = []
    replay = nil
    2_000.times do
      replay = war_play(game, session, repo, events, ctx)
      break if replay.finished?
    end
    assert(replay.finished?, "a #{count}-player game did not finish within the battle limit")
    cards = replay.state[:piles].values.sum(&:length) + replay.state[:carried].length
    assert(cards == 24, "cards were lost or duplicated")
    assert(game.replay(session, events, repo).state == replay.state, "replay is not deterministic")
    events.length
  end
end
assert(lengths.max < GameRoomLiveSessionStore::STACK_ENTRIES, "a game can exceed the repository event limit")

sound_repository = WarRepository.new(players)
heard = []
wars = 0
[5, 6, 7, 8, 9, 10].each do |seed|
  break if wars > 0
  sound_session = war_session(game)
  sound_context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SeededSource.new(seed), now: 0)
  sound_events = []
  80.times do
    before = game.replay(sound_session, sound_events, sound_repository)
    break if before.finished?
    after = war_play(game, sound_session, sound_repository, sound_events, sound_context)
    cues = Array(GameRoomSounds.event_cue(game: game, event: sound_events.last, before_replay: before, after_replay: after, repository: sound_repository, viewer: "Alice"))
    kinds = after.history.select { |item| item.event_id == sound_events.last["id"] }.map(&:kind)
    wars += 1 if kinds.include?(:war)
    assert(cues.include?("war_open") == kinds.include?(:war), "the war sound does not follow the war: #{kinds} #{cues}")
    assert(cues.include?("draw") == kinds.include?(:take), "the take sound does not follow the battle: #{kinds} #{cues}")
    heard.concat(cues)
  end
end
assert(heard.first == "shuffle" && heard.include?("play") && heard.include?("war_open"), "real games did not produce the deal, play and war sounds: #{heard.uniq}")
heard.uniq.each do |name|
  assert(GameRoomSounds::ASSET_NAMES.include?(name) && File.exist?(File.expand_path("../../../Audio/#{name}.opus", __dir__)), "missing sound #{name}")
end

result = GameRoomSimulation::MatchRunner.new(game: game, players: GameRoomParticipants.bots_for(1, 4), options: { "bot_delay" => 0 }).run(seed: 9)
assert(result.reason == :finished, "bots could not finish a simulated game: #{result.reason}")
puts "PASS War: deal, battles, wars, bystanders, elimination, limit, full deck, determinism, sounds, #{lengths.length} games up to #{lengths.max} events, bots"
