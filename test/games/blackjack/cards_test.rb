require_relative "../../../games/blackjack" unless defined?(GameRoomGames::Blackjack)
require_relative "../../support/blackjack" unless defined?(BlackjackChecksSupport)

module BlackjackCardChecks
  extend BlackjackChecksSupport

  def self.run!
    game = BlackjackChecksSupport::FixedDeck.new
    repo = BlackjackChecksSupport::Repository.new(["Alice"])
    session = {"options" => JSON.generate(game.default_options.merge("round_limit" => 1, "stake" => 1, "variant" => "extended"))}
    seed = event(1, "Alice", "deal", "1|#{'0' * 32}")
    check(game.hand_total(%w[AS AH 9C]) == 21, "Multiple aces")
    check(game.hand_total(%w[AS 6H]) == 17, "Soft 17")
    game.first_cards = %w[AS 9C KD 8D]
    replay = game.replay(session, [seed], repo)
    check(replay.state[:phase] == :dealer, "Natural should skip decisions")
    hidden = game.surface_spec(replay, "Alice").zones.last.header
    check(!hidden.include?(game.send(:playing_card_label, "0:8D")), "Dealer hole card revealed before settlement")
    won = game.replay(session, [seed, event(2, "Alice", "dealer")], repo)
    check(won.finished? && won.state[:chips]["Alice"] == 203, "Exact 3:2 payout with odd stake")
    game.first_cards = %w[AS AH KD TC]
    push = game.replay(session, [seed, event(2, "Alice", "dealer")], repo)
    check(push.state[:chips]["Alice"] == 200, "Two naturals must push")
    game.first_cards = %w[TC AS 9D 6C 2H]
    replay = game.replay(session, [seed, event(2, "Alice", "stand"), event(3, "Alice", "dealer")], repo)
    check(replay.state[:dealer].size == 2 && replay.state[:chips]["Alice"] == 202, "Dealer must stand on soft 17")
    game.first_cards = %w[TC 9D 6C 7H KD QS]
    lost = game.replay(session, [seed, event(2, "Alice", "hit"), event(3, "Alice", "dealer")], repo)
    check(lost.state[:chips]["Alice"] == 198, "Player bust loses even when dealer busts")
    game.first_cards = %w[5C 6D 6C TH TD 2S]
    doubled = game.replay(session, [seed, event(2, "Alice", "double"), event(3, "Alice", "dealer")], repo)
    check(doubled.state[:hands]["Alice"].first[:cards].size == 3 && doubled.state[:hands]["Alice"].first[:bet] == 4, "Double must draw once and stop")
    check(doubled.state[:chips]["Alice"] == 204, "Doubled win payout")
    game.first_cards = %w[AS 9D AC 7H TC KD 2S]
    split = game.replay(session, [seed, event(2, "Alice", "split"), event(3, "Alice", "dealer")], repo)
    hands = split.state[:hands]["Alice"]
    check(hands.size == 2 && hands.all? { |hand| hand[:cards].size == 2 && hand[:done] }, "Split aces")
    check(hands.none? { |hand| game.natural?(hand) } && split.state[:chips]["Alice"] == 204, "Split 21 is not a natural")
    game.first_cards = %w[8C 9D 8D 7H 2C 3C]
    split_events = [seed, event(2, "Alice", "split")]
    replay = game.replay(session, split_events, repo)
    check(game.legal_actions(replay, "Alice").map { |item| item["action"] } == %w[hit stand], "No resplitting or double after split")
    next_hand = game.replay(session, split_events + [event(3, "Alice", "stand")], repo)
    check(next_hand.state[:hand_index] == 1 && next_hand.current_player == "Alice", "Second split hand skipped")
    simple = {"options" => JSON.generate(game.default_options)}
    check(game.replay(simple, [seed, event(2, "Alice", "split")], repo).accepted_events.size == 1, "Simple variant allowed splitting")
    check(game.replay(session, [seed, event(2, "Mallory", "hit")], repo).accepted_events.size == 1, "Wrong actor accepted")
    check(game.replay(session, [seed, seed], repo).accepted_events.size == 1, "Duplicate accepted")
    observation = game.bot_observation(replay, "Alice")
    check(observation.keys.sort == %w[cards dealer_upcard round total], "Bot sees future deck or hole card")
    surface = game.surface_spec(replay, "Alice")
    check(surface.zones.first.hand_order == replay.state[:hands]["Alice"].first[:cards], "Physical draw order missing")
    check(surface.zones.first.hand_epoch != game.surface_spec(next_hand, "Alice").zones.first.hand_epoch, "Split hands share epoch")
    check(game.validation_error({"stake" => 101}) != nil, "Stake exceeds bankroll")
    actual = GameRoomGames::Blackjack.new
    first = actual.replay(session, [seed], repo)
    second = actual.replay(session, [seed], repo)
    check(first.state == second.state, "Seeded replay changed")
    physical = first.state[:deck] + first.state[:dealer] + first.state[:hands].values.flatten.flat_map { |hand| hand[:cards] }
    check(physical.size == 312 && physical.uniq.size == 312, "Physical card duplication")
    check(actual.method(:hand_total).call(physical.take(2)) >= 2, "Physical card values invalid")
    game.first_cards = %w[TC AS 5D KD 6C]
    dealer_natural = game.replay(session, [seed, event(2, "Alice", "hit"), event(3, "Alice", "dealer")], repo)
    check(dealer_natural.accepted_events.size == 2 && dealer_natural.state[:chips]["Alice"] == 198, "Dealer natural allowed a player decision")
    poor = {"options" => JSON.generate(game.default_options.merge('variant' => 'extended', 'starting_chips' => 10, 'stake' => 10))}
    game.first_cards = %w[8C 9D 8D 7H]
    poor_replay = game.replay(poor, [seed], repo)
    check(game.legal_actions(poor_replay, 'Alice').map { |item| item['action'] } == %w[hit stand], "Extra stake allowed without funds")
    check(game.game_shortcuts(poor_replay, 'Alice').map(&:key).include?('h'), "Hand shortcut missing")
    epoch = game.surface_spec(poor_replay, 'Alice').zones.first.hand_epoch
    after_hit = game.replay(poor, [seed, event(2, 'Alice', 'hit')], repo)
    check(game.surface_spec(after_hit, 'Alice').zones.first.hand_epoch == epoch, "Hit resets the hand epoch")
    two = BlackjackChecksSupport::Repository.new(%w[Alice Bob])
    game.first_cards = %w[AS 8C 5C KD 6C 6D TC]
    compared = game.replay(session, [seed, event(2, 'Bob', 'stand'), event(3, 'Alice', 'dealer')], two)
    check(compared.state[:dealer].size == 3 && game.hand_total(compared.state[:dealer]) == 21, "Dealer ordinary 21 fixture")
    check(compared.state[:chips] == {'Alice' => 203, 'Bob' => 198}, "Natural must beat ordinary 21")
    "Blackjack: aces, payouts, naturals, dealer, double, split, privacy, hands and deterministic replay passed"
  end
end

puts BlackjackCardChecks.run! if $PROGRAM_NAME == __FILE__
