require_relative "../../support/elten_array_shuffle"
require_relative "../../support/ui"
require "json"
class Program
  def self.server_app(**_options); end
end
require_relative "../../../__app"
require_relative "../../../lib/saved_games"

def assert(condition, message)
  raise message unless condition
end

class ScientificWarRepository
  def initialize(players) = @players = players
  def players_for(_session) = @players
  def actor_of(event, _session = nil) = event.fetch("actor")
  def event_id(event) = event.fetch("id")
  def session_id(_session) = 7
end

class ScientificWarTable
  attr_reader :game, :session, :repository, :events, :vault, :replay

  def initialize(players, options = {}, seed: 1)
    @game = EltenGameRoom::GAME_REGISTRY.build("scientific_war")
    @session = { "options" => JSON.generate(@game.normalize_options(options)) }
    @repository = ScientificWarRepository.new(players)
    @events = []
    @vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
    @random = GameRoomRandom::SeededSource.new(seed)
    refresh
  end

  def context
    GameRoomGames::ActionContext.new(session_id: 7, hidden_submissions: @vault, random_source: @random, now: @events.length)
  end

  def refresh
    @replay = @game.replay(@session, @events, @repository)
  end

  def act(actor, selection)
    status, plan = @game.action_for(selection, @replay, actor, context: context)
    return status unless status == :ok

    plan.events.each do |command|
      assert(command.value.length <= GameRepository::MAX_VALUE_LENGTH, "an event value exceeds the repository limit")
      @events << { "id" => @events.length + 1, "actor" => actor, "action" => command.action, "value" => command.value }
    end
    refresh
    :ok
  end

  def choose(actor, card)
    act(actor, { "kind" => "card", "action" => "select", "zone" => "hand", "card" => card })
  end

  def reveal_all
    @replay.players.each do |player|
      selection = @game.automatic_action(@replay, player, context: context) ||
        @game.legal_actions(@replay, player, context: context).find { |item| item["action"] == "reveal" }
      act(player, selection) if selection
    end
  end

  def trick(cards)
    cards.each { |player, card| assert(choose(player, card) == :ok, "#{player} could not choose #{card}") }
    reveal_all
  end
end

def card_of(table, player, rank)
  table.replay.state[:hands][player].find { |card| card.start_with?(rank) }
end

players = %w[Alice Bob]
table = ScientificWarTable.new(players)
game = table.game
assert(game.name == "Scientific War" && game.minimum_players == 2 && game.maximum_players == 8, "wrong registration")
assert(game.supports_bots? && game.supports_saved_games?, "wrong bot or saved game support")
assert(game.default_options["trick_limit"] == 50, "wrong default trick limit")
assert(game.options_error({ "trick_limit" => 19 }) && game.options_error({ "trick_limit" => 101 }), "an invalid limit was accepted")
assert(game.options_error({ "trick_limit" => 20 }).nil? && game.options_error({ "trick_limit" => 100 }).nil?, "a valid limit was rejected")

state = table.replay.state
assert(state[:hands]["Alice"].length == 14 && state[:hands]["Alice"].all? { |card| card[1] == "H" || card[0] == "X" }, "Alice did not get all hearts and a joker")
assert(state[:hands]["Bob"].all? { |card| card[1] == "S" || card[0] == "X" }, "Bob did not get all spades and a joker")
eight = ScientificWarTable.new(%w[A B C D E F G H]).replay.state[:hands]
assert(eight.values.flatten.uniq.length == 8 * 14, "cards of a second deck are not distinct")
assert(eight.values.map { |hand| hand.first[1] }.tally.values.uniq == [2], "eight players do not share four suits twice")

navigation = game.playable_card_navigation(table.replay, "Alice")
assert(navigation[:hand_id] == "hand" && navigation[:card_actions].keys.sort == table.replay.state[:hands]["Alice"].sort, "Z does not move through the whole hand")
z_keys = game.game_shortcuts(table.replay, "Alice").map { |shortcut| [shortcut.key, shortcut.modifiers.to_a] }
assert(z_keys.include?(["z", []]) && z_keys.include?(["z", [:shift]]), "Z or Shift+Z is missing")
assert(game.active_actors(table.replay).sort == players, "both players should choose at the same time")
assert(table.choose("Alice", "AH1") == :ok, "Alice could not choose")
assert(table.events.none? { |event| event["value"].include?("AH1") }, "the chosen card was public before the reveal")
assert(table.choose("Alice", "KH1") == :already_submitted, "a player could choose twice")
assert(game.controller_change_error(table.replay, replacement: true), "a seat with a sealed card could be handed over")
assert(game.controller_change_error(ScientificWarTable.new(players).replay, replacement: true).nil?, "a seat could not be handed over at the start of a trick")
assert(game.active_actors(table.replay) == ["Bob"], "Bob should still be choosing")
waiting = game.surface_spec(table.replay, "Alice").zones.first.header
assert(waiting.include?("You chose ace of hearts") && waiting.include?("Bob"), "the waiting player does not hear their card and who is choosing: #{waiting}")
bob_view = game.surface_spec(table.replay, "Bob").zones.first
assert(bob_view.cards.length == 14 && !bob_view.header.include?("ace of hearts"), "Bob's hand is wrong or leaks Alice's card")
alice_history = game.history_entries_for_display(table.replay, "Alice").map(&:text)
bob_history = game.history_entries_for_display(table.replay, "Bob").map(&:text)
assert(alice_history.include?("You chose ace of hearts.") && bob_history.include?("Alice has chosen a card."), "the commit history is wrong per listener")
assert(bob_history.none? { |text| text.include?("ace of hearts") }, "the history leaks the chosen card")
assert(game.playable_card_navigation(table.replay, "Alice").nil?, "Z still offers cards after the choice")
assert(table.choose("Bob", "KS1") == :ok, "Bob could not choose")
assert(table.replay.state[:phase] == :revealing, "the reveal did not start after all choices")
forged = table.events + [{ "id" => 99, "actor" => "Alice", "action" => "reveal", "value" => "1:#{'0' * 32}:2H1" }]
assert(game.replay(table.session, forged, table.repository).state[:reveals].empty?, "a reveal not matching the seal was accepted")
table.reveal_all
assert(table.replay.state[:piles]["Alice"].sort == %w[AH1 KS1] && table.replay.state[:trick] == 2, "the ace did not win the first trick")
assert(table.replay.state[:hands]["Alice"].length == 13, "the played card stayed in the hand")

table.trick("Alice" => "7H1", "Bob" => "7S1")
assert(table.replay.state[:carried].sort == %w[7H1 7S1] && table.replay.state[:piles]["Bob"].empty?, "a tie did not start a war")
table.trick("Alice" => "5H1", "Bob" => "6S1")
assert(table.replay.state[:piles]["Bob"].sort == %w[5H1 6S1 7H1 7S1] && table.replay.state[:carried].empty?, "the next trick did not take the war cards")

table.trick("Alice" => "JH1", "Bob" => "4S1")
assert(table.replay.state[:reversed] && table.replay.state[:piles]["Bob"].include?("JH1"), "a jack did not reverse the order at once")
table.trick("Alice" => "2H1", "Bob" => "AS1")
assert(table.replay.state[:piles]["Alice"].include?("AS1"), "two is not the strongest card after a revolution")
table.trick("Alice" => "TH1", "Bob" => "JS1")
assert(!table.replay.state[:reversed] && table.replay.state[:piles]["Bob"].include?("TH1"), "the next jack did not restore the order")

double = ScientificWarTable.new(%w[Alice Bob Carol])
double.trick("Alice" => "JH1", "Bob" => "JS1", "Carol" => "2D1")
assert(!double.replay.state[:reversed] && double.replay.state[:carried].length == 3, "two jacks did not cancel each other out")

jokers = ScientificWarTable.new(players)
jokers.trick("Alice" => "X1", "Bob" => "AS1")
assert(jokers.replay.state[:carried].sort == %w[AS1 X1], "a joker did not force a war")
cancel = ScientificWarTable.new(%w[Alice Bob Carol])
cancel.trick("Alice" => "QH1", "Bob" => "QS1", "Carol" => "X3")
assert(cancel.replay.state[:piles]["Carol"].length == 3, "a joker did not cancel a war and win")
assert(cancel.replay.state[:powers].empty?, "two queens were not cancelled")
both = ScientificWarTable.new(players)
both.trick("Alice" => "X1", "Bob" => "X2")
assert(both.replay.state[:carried].length == 2 && both.replay.history.any? { |entry| entry.kind == :jokers_cancelled }, "two jokers did not cancel each other out")
assert(both.replay.history.none? { |entry| entry.kind == :forced_war }, "two jokers forced a war")

spy = ScientificWarTable.new(%w[Alice Bob Carol])
spy.trick("Alice" => "QH1", "Bob" => "5S1", "Carol" => "4D1")
assert(spy.replay.state[:powers]["Alice"] == "Q", "a single queen did not grant the spy power")
assert(game.active_actors(spy.replay).sort == %w[Bob Carol], "the spy was asked to choose with the others")
assert(spy.choose("Alice", "AH1") == :not_your_turn, "the spy could choose before the others")
spy.trick("Bob" => "KS1", "Carol" => "TD1")
assert(spy.replay.state[:phase] == :spying && spy.replay.current_player == "Alice", "the spy did not get the last choice")
power = game.game_shortcuts(spy.replay, "Alice").find { |item| item.key == "c" }
assert(power.message.include?("king of spades") && power.message.include?("10 of diamonds"), "C did not read the chosen cards to the spy")
bob_power = game.game_shortcuts(spy.replay, "Bob").find { |item| item.key == "c" }
assert(!bob_power.message.include?("10 of diamonds"), "another player could read the chosen cards")
assert(game.surface_spec(spy.replay, "Alice").zones.first.header.include?("king of spades"), "the spy surface does not list the chosen cards")
assert(game.turn_announcement(spy.replay, "Alice").include?("spy"), "the spy did not hear their turn")
assert(spy.choose("Alice", "AH1") == :ok && spy.replay.state[:piles]["Alice"].length == 6, "the spy's card was not resolved: #{spy.replay.state[:piles]}")
assert(spy.replay.state[:powers]["Alice"].nil? && spy.replay.state[:phase] == :choosing, "the spy power lasted more than one trick")

three = ScientificWarTable.new(%w[Alice Bob Carol])
three.trick("Alice" => "3H1", "Bob" => "5S1", "Carol" => "4D1")
message = game.game_shortcuts(three.replay, "Alice").find { |item| item.key == "c" }.message
assert(message.include?("Bob: 13 cards") && message.include?("Carol: 13 cards"), "the three did not reveal hand sizes: #{message}")
assert(!game.game_shortcuts(three.replay, "Bob").find { |item| item.key == "c" }.message.include?("Carol: 13"), "hand sizes leaked to another player")
totals = game.game_shortcuts(three.replay, "Bob").find { |item| item.key == "e" }.message
assert(totals.include?("Bob: 16 cards") && totals.include?("Alice: 13 cards"), "E does not read the total cards owned: #{totals}")

swap = ScientificWarTable.new(players)
swap.trick("Alice" => "8H1", "Bob" => "2S1")
assert(swap.replay.state[:powers]["Alice"] == "8", "an eight did not grant the swap power")
shortcut = game.game_shortcuts(swap.replay, "Alice").find { |item| item.key == "c" }
assert(shortcut.kind == :action && shortcut.action_name == "swap", "C does not swap after an eight")
assert(game.surface_spec(swap.replay, "Alice").is_a?(GameSurfaces::CompositeSpec), "the swap command is missing from the surface")
assert(swap.act("Bob", { "kind" => "command", "action" => "swap" }) == :invalid, "a player without an eight could swap")
assert(swap.act("Alice", { "kind" => "command", "action" => "swap" }) == :ok, "the swap was rejected")
assert(swap.replay.state[:hands]["Alice"].sort == %w[2S1 8H1] && swap.replay.state[:piles]["Alice"].length == 13, "the hand and pile were not swapped")
assert(game.history_entries_for_display(swap.replay, "Bob").none? { |entry| entry.kind == :swap }, "the private swap was announced to others")
assert(swap.act("Alice", { "kind" => "command", "action" => "swap" }) == :invalid, "the swap could be repeated")

order_table = ScientificWarTable.new(players)
order_table.trick("Alice" => "AH1", "Bob" => "5S1")
order_table.trick("Alice" => "7H1", "Bob" => "KS1")
order_table.trick("Alice" => "8H1", "Bob" => "2S1")
before_swap = GameSurfaces::CardTable.new(game.surface_spec(order_table.replay, "Alice").parts.last.surface)
assert(order_table.replay.state[:piles]["Alice"] == %w[AH1 5S1 8H1 2S1], "the pile was not built in the order won: #{order_table.replay.state[:piles]["Alice"]}")
assert(order_table.act("Alice", { "kind" => "command", "action" => "swap" }) == :ok, "the swap for the order check was rejected")
after_swap = GameSurfaces::CardTable.new(game.surface_spec(order_table.replay, "Alice"), state: before_swap.state)
expected_order = ["2 of spades", "5 of spades", "8 of hearts", "ace of hearts"]
assert(after_swap.fields.first.options == expected_order, "cards from the pile are not listed from the lowest: #{after_swap.fields.first.options}")
assert(after_swap.fields.first.index == 0, "the cursor did not start at the lowest card of the new hand")
refill = ScientificWarTable.new(players)
refill_state = refill.replay.state
refill_state[:hands]["Alice"] = %w[4H1]
refill_state[:piles]["Alice"] = %w[KS1 3S1 QH1 X1 9S1]
refill_state[:hands]["Bob"] = %w[2S1 6S1]
first_hand = GameSurfaces::CardTable.new(game.surface_spec(refill.replay, "Alice"))
refill_state[:reveals] = { "Alice" => "4H1", "Bob" => "2S1" }
game.send(:resolve_trick, refill_state, 1, [])
refilled = GameSurfaces::CardTable.new(game.surface_spec(refill.replay, "Alice"), state: first_hand.state)
labels = refilled.fields.first.options
assert(labels == ["2 of spades", "3 of spades", "4 of hearts", "9 of spades", "queen of hearts", "king of spades", "joker"], "a refilled hand is not listed from the lowest with the joker last: #{labels}")

stub = game.send(:initial_state, players, game.normalize_options({}))
stub[:hands]["Alice"] = %w[AH1]
stub[:hands]["Bob"] = %w[2S1]
stub[:piles]["Bob"] = []
stub[:reveals] = { "Alice" => "AH1", "Bob" => "2S1" }
history = []
game.send(:resolve_trick, stub, 1, history)
assert(stub[:hands]["Alice"].sort == %w[2S1 AH1] && stub[:piles]["Alice"].empty?, "an empty hand did not take the pile back")
assert(stub[:eliminated]["Bob"] && stub[:phase] == :finished && stub[:winner] == "Alice", "a player without cards was not eliminated")

limit = game.send(:initial_state, players, game.normalize_options({ "trick_limit" => 20 }))
limit.update(trick: 20, reveals: { "Alice" => "AH1", "Bob" => "2S1" })
limit[:hands].update("Alice" => %w[AH1 KH1], "Bob" => %w[2S1 3S1])
game.send(:resolve_trick, limit, 1, [])
assert(limit[:phase] == :finished && limit[:limit_reached] && limit[:winner] == "Alice", "the trick limit did not end the game")
tie = game.send(:initial_state, players, game.normalize_options({ "trick_limit" => 20 }))
tie.update(trick: 20, reveals: { "Alice" => "5H1", "Bob" => "5S1" })
tie[:hands].update("Alice" => %w[5H1 KH1], "Bob" => %w[5S1 3S1])
game.send(:resolve_trick, tie, 1, [])
assert(tie[:phase] == :finished && tie[:draw] && tie[:winner].nil?, "equal totals at the limit did not give a draw")

sound_table = ScientificWarTable.new(players)
sound_table.trick("Alice" => "JH1", "Bob" => "JS1")
cue = lambda do |event, viewer|
  before = game.replay(sound_table.session, sound_table.events[0...sound_table.events.index(event)], sound_table.repository)
  after = game.replay(sound_table.session, sound_table.events[0..sound_table.events.index(event)], sound_table.repository)
  Array(GameRoomSounds.event_cue(game: game, event: event, before_replay: before, after_replay: after, repository: sound_table.repository, viewer: viewer))
end
assert(cue.call(sound_table.events[0], "Bob") == ["play2"], "choosing a card has no sound")
assert(cue.call(sound_table.events.last, "Bob").include?("war_open"), "a war has no sound")
sound_table.trick("Alice" => "JH1".sub("J", "K"), "Bob" => "2S1")
assert(cue.call(sound_table.events.last, "Alice").include?("draw"), "taking a trick has no sound")
used = %w[play2 card-shuffle ding play reverse war_open draw]
used.each do |name|
  assert(GameRoomSounds::ASSET_NAMES.include?(name) && File.exist?(File.expand_path("../../../Audio/#{name}.opus", __dir__)), "missing sound #{name}")
end

lengths = [2, 3, 5, 8].flat_map do |count|
  6.times.map do |seed|
    names = count.times.map { |index| "P#{index}" }
    match = ScientificWarTable.new(names, {}, seed: seed + 11 * count)
    random = Random.new(seed)
    5_000.times do
      break if match.replay.finished?
      actor = game.active_actors(match.replay).first
      selection = game.automatic_action(match.replay, actor, context: match.context) ||
        game.legal_actions(match.replay, actor, context: match.context).sample(random: random)
      assert(match.act(actor, selection) == :ok, "a legal action was rejected: #{selection}")
    end
    assert(match.replay.finished?, "a #{count}-player game did not finish")
    owned = match.replay.state[:hands].values.sum(&:length) + match.replay.state[:piles].values.sum(&:length) + match.replay.state[:carried].length
    assert(owned == 14 * count, "cards were lost or duplicated")
    assert(game.replay(match.session, match.events, match.repository).state == match.replay.state, "replay is not deterministic")
    match.events.length
  end
end
assert(lengths.max < GameRoomLiveSessionStore::STACK_ENTRIES, "a game can exceed the repository event limit")

bots = GameRoomParticipants.bots_for(1, 3)
bot_table = ScientificWarTable.new(bots, {}, seed: 4)
coordinator = GameRoomBots::Coordinator.new
spy_wins = 0
spy_tricks = 0
3_000.times do
  break if bot_table.replay.finished?
  spying = bot_table.replay.state[:phase] == :spying
  decision = coordinator.decide_next(game: game, replay: bot_table.replay, context: bot_table.context)
  assert(decision && bot_table.act(decision.actor, decision.action) == :ok, "a bot action was rejected: #{decision&.action}")
  next unless spying

  spy_tricks += 1
  spy_wins += 1 if bot_table.replay.history.last(8).any? { |entry| [:take, :joker_win].include?(entry.kind) && game.send(:same_user?, entry.actor, decision.actor) }
end
assert(bot_table.replay.finished?, "bots could not finish a game")
assert(spy_tricks == 0 || spy_wins * 2 >= spy_tricks, "the spy bot does not use the revealed cards: #{spy_wins}/#{spy_tricks}")
require_relative "../../support/hidden_submission_files"
class ScientificWarArchive < HiddenSubmissionFiles
  def update_json(path, default:)
    data = read_json(path, default: default)
    yield data
    write_json(path, data)
    data
  end
end

save_bot = GameRoomParticipants.bots_for(1, 1).first
save_players = ["Alice", save_bot]
archive = ScientificWarArchive.new
saves = SavedGames.new(archive, owner: "Alice")
save_table = ScientificWarTable.new(save_players)
save_table.instance_variable_set(:@vault, HiddenSubmissions::Vault.new(HiddenSubmissions::ProgramStorage.new(archive)))
save_table.trick("Alice" => "8H1", save_bot => "5S1")
bot_status = save_table.choose(save_bot, card_of(save_table, save_bot, "K"))
assert(bot_status == :ok, "the bot could not choose before saving: #{bot_status} #{save_table.replay.state.slice(:phase, :trick, :commits)}")
snapshot = Struct.new(:session, :events).new(save_table.session.merge("__players" => save_players, "__id" => 7), save_table.events)
table_info = { "owner" => "Alice", "name" => "Scientific War" }
row = saves.put(game: game, table: table_info, snapshot: snapshot, repository: save_table.repository, now: 1_900_000_000)
assert(row["private_data"]["cards"]["1"]["card"].start_with?("K"), "the bot's sealed card was not saved")
assert(row["events"].none? { |event| event["value"].include?(row["private_data"]["cards"]["1"]["card"]) }, "the sealed card leaked into the public archive")
restored = saves.restored_data(row, game: game, table_id: 55, now: 1_900_000_100)
restored.fetch(:before_publish).call(99)
new_bot = restored[:players].last
restored_repo = ScientificWarRepository.new(restored[:players])
restored_session = { "options" => row["options"] }
after = game.replay(restored_session, restored[:events], restored_repo)
assert(after.state[:powers]["Alice"] == "8" && after.state[:commits].key?(new_bot), "the restored game lost the power or the bot's choice")
restored_context = GameRoomGames::ActionContext.new(session_id: 99, hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::ProgramStorage.new(archive)))
status, = game.action_for({ "kind" => "card", "action" => "select", "zone" => "hand", "card" => card_of(save_table, "Alice", "2") }, after, "Alice", context: restored_context)
assert(status == :ok, "the restored game could not continue")
bad = Marshal.load(Marshal.dump(row))
bad["private_data"]["cards"]["1"]["nonce"] = "0" * 32
bad["checksum"] = saves.send(:checksum, bad)
begin
  saves.validate(bad, game: game)
  raise "a corrupt sealed card was accepted"
rescue ArgumentError
end
assert(save_table.choose("Alice", card_of(save_table, "Alice", "2")) == :ok, "Alice could not choose")
blocked = ScientificWarTable.new(%w[Alice Bob])
blocked.choose("Alice", "AH1")
assert(game.save_game_error(blocked.replay).to_s.include?("beginning of a trick"), "a game with a person's sealed card could be saved")
assert(game.save_game_error(ScientificWarTable.new(%w[Alice Bob]).replay).nil?, "a game at the start of a trick could not be saved")

puts "PASS Scientific War: equal suits, sorted hands after a swap or refill, Z navigation, sealed choices, wars, revolution, spy, three, eight, jokers, elimination, limit, sounds, save and restore, controller changes, #{lengths.length} games up to #{lengths.max} events, bots"
