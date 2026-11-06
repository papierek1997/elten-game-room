require_relative "../../support/tysiac_redeal_fixture"

game = GameRoomGames::Tysiac.new
assert(game.table_creation_options.values_at('redeal_four_nines', 'redeal_talon_nines') == [true, false],
  'New-table defaults differ from the option form')
assert(!game.normalize_options({}).key?('redeal_four_nines'), 'New defaults rewrote a recorded option document')
['redeal_four_nines', :redeal_four_nines].each do |key|
  source = {key => false}
  assert(game.table_creation_options(source)['redeal_four_nines'] == false && source == {key => false},
    'Table defaults replaced an explicit false or mutated input')
end

nines = %w[9H 9S 9D 9C]
four = TysiacRedealFixture.seed_for { |deck| (nines - deck.slice(7, 7)).empty? }
music = TysiacRedealFixture.seed_for { |deck| deck.last(3).count { |card| card[0] == "9" } >= 2 }
three_plus_one = TysiacRedealFixture.seed_for do |deck|
  deck.slice(7, 7).count { |card| card[0] == "9" } == 3 && deck.last(3).count { |card| card[0] == "9" } == 1
end

f = TysiacRedealFixture.new
f.deal(four)
before = f.replay
assert(f.game.legal_actions(before, "Bob").any? { |action| action["action"] == "redeal" }, "Missing four-nines action")
assert(f.game.game_shortcuts(before, "Bob").any? { |key| key.key == "d" && key.modifiers == [:shift] }, "Missing Shift+D")
epoch = f.game.surface_spec(before, "Bob").zones.first.hand_epoch
assert(f.game.surface_spec(before, "Bob").zones.first.commands.first.id == "redeal", "No ordinary card-list command")
assert(f.request("talon_nines") == :cannot_redeal, "Wrong reason accepted")
assert(f.request("four_nines", actor: "Alice") == :cannot_redeal, "Another player claimed Bob's hand")
assert(f.request("four_nines") == :ok && f.state[:phase] == :redeal, "Four initial nines did not cancel")
%i[scores zero_rounds surrender_uses barrels].each { |key| assert(before.state[key] == f.state[key], "Redeal changed #{key}") }
assert(f.redeal == :ok, "Repeating deal failed")
assert(f.state[:round] == 1 && f.state[:dealer_index] == 0 && f.state[:current_player] == "Bob", "Redeal advanced round/dealer/first bidder")
assert(f.game.surface_spec(f.replay, "Bob").zones.first.hand_epoch != epoch, "New hand reused old cursor epoch")
assert(f.replay.history.map(&:key).uniq.size == f.replay.history.size, "Redeal duplicated history keys")
assert(f.state[:hands].values.flatten.uniq.size == 21 && f.state[:talon].size == 3, "Redeal lost/duplicated cards")
assert(f.request("four_nines") == :cannot_redeal, "An old four-nines claim survived a fresh hand")

f = TysiacRedealFixture.new({"redeal_four_nines"=>false})
f.deal(four)
assert(f.request("four_nines") == :cannot_redeal, "Disabled four-nines rule accepted")
assert(f.bid(100) == :ok, "Cannot keep a hand containing four nines")

f = TysiacRedealFixture.new
f.deal(four)
f.bid(100); f.bid(105); f.bid(110)
assert(f.state[:current_player] == "Bob" && f.request("four_nines") == :cannot_redeal, "Four-nines claim allowed after bidding")

[true, false].each do |enabled|
  f = TysiacRedealFixture.new({"redeal_talon_nines"=>enabled})
  f.deal(music)
  assert(f.request("talon_nines") == :cannot_redeal, "Hidden talon could be inspected for a redeal")
  f.bid(100); f.bid("pass"); f.bid("pass")
  before = f.replay
  if enabled
    assert(f.request("talon_nines") == :ok, "Two public talon nines did not cancel")
    assert(f.state[:scores] == before.state[:scores] && f.redeal == :ok && f.state[:dealer_index] == 0, "Talon redeal changed scores/dealer")
  else
    assert(f.request("talon_nines") == :cannot_redeal, "Talon rule should be disabled by default")
  end
end

f = TysiacRedealFixture.new({"redeal_talon_nines"=>true})
f.deal(music); f.bid(100); f.bid("pass"); f.bid("pass")
actor = f.replay.current_player
card = f.state[:hands][actor].first
assert(f.move({"kind"=>"card", "action"=>"select", "card"=>card}) == :ok, "Cannot start passing cards")
assert(f.request("talon_nines") == :cannot_redeal, "Talon claim allowed after first transfer")

f = TysiacRedealFixture.new({"redeal_talon_nines"=>true})
f.deal(three_plus_one); f.bid(100); f.bid("pass"); f.bid("pass")
assert(f.state[:hands]["Bob"].count { |card| card[0] == "9" } == 4, "Not testing 3 initial + 1 talon")
assert(f.request("four_nines") == :cannot_redeal && f.request("talon_nines") == :cannot_redeal, "Later fourth nine triggered a rule")

# Bots use the same accepted action and can also keep a hand when disabled.
f = TysiacRedealFixture.new
f.deal(four)
action = f.game.bot_strategy.choose(actions: f.game.legal_actions(f.replay, "Bob"), actor: "Bob", random_source: GameRoomRandom::SeededSource.new(1),
  game: f.game, replay: f.replay, context: f.context)
assert(action["action"] == "redeal" && f.move(action) == :ok, "Bot did not use the normal redeal plan")
puts "PASS Tysiac redeals: options, initial-only four nines, revealed talon, timing, dealer/round, counters, hand epoch, history and bots"
