if ARGV.delete("--binary")
  require_relative "../support/binary_rules_load"
  # Re-enter with an absolute source path so nested requires stay inside the
  # binary loader instead of accidentally replacing classes with UTF-8 files.
  BinaryRulesLoad.load(File.expand_path(__FILE__))
  exit
end
require_relative "../support/card_timeouts"

[GameRoomGames::NinetyNine.new, GameRoomGames::Poker.new].each do |game|
  off = TimedCardCase.new(game, {"thinking_time"=>0})
  assert(!off.events.first["value"].include?("~") && !off.replay.state.key?(:turn_deadline), "disabled clock changed legacy state/wire")
  off.context.now = 9_999_999_999
  assert(!game.automatic_action_due?(off.replay, "A", context: off.context), "disabled clock expired")
  c = TimedCardCase.new(game)
  assert(c.replay.state[:turn_deadline] == 120 && c.replay.state[:turn_number] == 1, "deal starts clock")
  c.context.now = 119
  selection = game.legal_actions(c.replay, c.replay.current_player, context: c.context).first
  status, late_plan = game.action_for(selection, c.replay, c.replay.current_player, context: c.context)
  assert(status == :ok, "legal action before deadline")
  assert(!game.automatic_action_due?(c.replay, "A", context: c.context), "timeout early")
  assert(game.action_for({"action"=>"turn_timeout"}, c.replay, "A", context: c.context).first == :invalid, "early timeout request")
  c.context.now = 120
  assert(game.automatic_action_due?(c.replay, "A", context: c.context), "deadline not scheduled")
  assert(game.automatic_action(c.replay, "A", context: c.context)["action"] == "turn_timeout", "deadline selection")
  assert(game.action_for({"action"=>"turn_timeout"}, c.replay, "B", context: c.context).first == :not_your_turn, "non-owner timed another player out")
  assert(game.action_for(selection, c.replay, c.replay.current_player, context: c.context).first != :ok, "late UI action accepted")
  command = late_plan.events.first
  late = {"id"=>2,"actor"=>c.replay.current_player,"action"=>command.action,
    "value"=>command.value.sub(/:[0-9a-z]+\z/, ":#{120.to_s(36)}")}
  assert(game.replay(c.session, c.events + [late], c.repo).accepted_events == c.events, "late wire action accepted")
  c.timeout
  assert(c.replay.state[:turn_deadline] == 140, "next turn has no full time")
  assert(game.replay(c.session, c.events + c.events, c.repo).state == c.replay.state, "duplicate event reapplied")
  stale = c.events.last.merge("id"=>900)
  assert(game.replay(c.session, c.events + [stale], c.repo).accepted_events == c.events, "stale timeout applied twice")
  frozen = game.replay(c.session.merge("__clock_offset"=>500, "__frozen_at"=>625), c.events, c.repo)
  assert(frozen.state[:turn_deadline] == 140 && GameRoomTurnClock.logical_now(frozen.state) == 125, "pause consumed thinking time")
  command = game.legal_actions(frozen, frozen.current_player).first
  status, plan = game.action_for(command, frozen, frozen.current_player)
  assert(status == :ok && plan.events.first.value.end_with?(":#{125.to_s(36)}"), "fallback clock ignored frozen logical time")
end

game = GameRoomGames::NinetyNine.new
c = TimedCardCase.new(game)
player = c.replay.current_player
before = Marshal.load(Marshal.dump(c.replay.state))
c.timeout
assert(c.replay.state[:tokens][player] == before[:tokens][player] - 1, "99 did not charge one token")
%i[hands draw_pile discard total round].each { |key| assert(c.replay.state[key] == before[key], "99 timeout changed #{key}") }
assert(game.describe_event(c.events.last, c.repo, c.replay, player) == ["You lose 1 token for running out of time."], "99 local announcement")
other = c.replay.players.find { |p| p != player }
assert(game.describe_event(c.events.last, c.repo, c.replay, other) == ["#{player} loses 1 token for running out of time."], "99 other player's announcement")

[1, -1].each do |direction|
  [1, 0].each do |tokens|
    s = Marshal.load(Marshal.dump(before))
    s[:direction] = direction
    s[:tokens][player] = tokens
    hist = []
    assert(game.send(:apply_timeout, s, {"id"=>2,"value"=>120.to_s(36)}, "A", c.repo, hist, 120), "99 scenario timeout")
    assert(s[:tokens][player] == 0 && s[:eliminated][player] == tokens.zero?, "99 zero-token grace changed")
    expected = s[:players][(s[:players].index(player) + direction) % 3]
    assert(s[:current_player] == expected, "99 direction/elimination turn order")
  end
end
c = TimedCardCase.new(game, {"starting_tokens"=>1}, %w[A B])
3.times { c.timeout }
assert(c.replay.finished? && c.replay.state[:turn_deadline] == 0, "99 timeout elimination did not finish game")
assert(c.replay.state[:eliminated].values.count(true) == 1, "99 eliminated on payment of last token")

# Atomic play+draw still gives the next turn a full clock. A jack with two
# players can leave the same player current: it must still be a NEW turn.
c = TimedCardCase.new(game, {}, %w[A B])
s = c.replay.state
p = c.replay.current_player
s[:hands][p] = %w[0JC 05C 06C]
s[:total] = 0
c.context.now = 110
status, plan = game.action_for({"kind"=>"card", "action"=>"select", "card"=>"0JC|normal"}, c.replay, p, context: c.context)
assert(status == :ok && plan.events.first.action == "play_draw", "99 atomic move lost")
decoded, time = GameRoomTurnClock.decode(s, {"id"=>2,"actor"=>p,"value"=>plan.events.first.value})
assert(game.send(:apply_play_draw, s, decoded, p, c.repo, []), "99 jack move rejected")
GameRoomTurnClock.advance(s, time, running: true)
assert(s[:current_player] == p && s[:turn_deadline] == 130 && s[:turn_number] == 2, "99 same-player extra turn kept old clock")

# Every betting structure and each variant folds, including a free check.
%w[holdem draw].product(%w[no_limit pot_limit half_pot fixed]).each do |variant, structure|
  c = TimedCardCase.new(GameRoomGames::Poker.new, {"variant"=>variant, "betting"=>structure})
  player = c.replay.current_player
  before_stacks = c.replay.state[:stacks].dup
  before_pot = c.replay.state[:contributions].dup
  before_cards = Marshal.load(Marshal.dump(c.replay.state[:hands]))
  c.timeout
  assert(c.replay.state[:folded][player] && c.replay.state[:stacks] == before_stacks, "poker timeout not fold: #{variant}/#{structure}")
  assert(c.replay.state[:contributions] == before_pot && c.replay.state[:hands] == before_cards, "fold played cards or removed committed chips")
  assert(c.replay.history.any? { |e| e.event_id == c.events.last["id"] && e.text == "#{player} folds." }, "missing fold message")
end

c = TimedCardCase.new(GameRoomGames::Poker.new, {"variant"=>"draw"})
3.times { c.act({"action"=>"check"}) }
assert(c.replay.state[:phase] == :exchange, "draw never reached exchange")
player = c.replay.current_player
hands = Marshal.load(Marshal.dump(c.replay.state[:hands]))
c.timeout
assert(c.replay.state[:folded][player] && c.replay.state[:hands] == hands, "non-all-in exchange timeout did not fold without exchanging")
assert(c.replay.state[:phase] == :exchange && c.replay.current_player != player, "fold stuck exchange")
2.times { c.act({"action"=>"exchange", "cards"=>"[]"}) }
assert(c.replay.state[:phase] == :betting && c.replay.state[:street] == 1, "remaining exchanges did not reach second betting")

# All-in exchange times out by standing pat, then participates in showdown.
c = TimedCardCase.new(GameRoomGames::Poker.new, {"variant"=>"draw"}, %w[A B])
c.act({"action"=>"all_in", "amount"=>995})
c.act({"action"=>"call", "amount"=>995})
assert(c.replay.state[:phase] == :exchange && c.replay.state[:all_in].values.all?, "all-in exchange fixture")
hands = Marshal.load(Marshal.dump(c.replay.state[:hands]))
deck = c.replay.state[:deck].dup
2.times do
  player = c.replay.current_player
  c.timeout
  assert(!c.replay.state[:folded][player] && c.replay.state[:exchanged][player], "all-in was folded by timeout")
  assert(c.replay.state[:hands] == hands && c.replay.state[:deck] == deck, "all-in timeout exchanged cards")
  assert(c.replay.history.any? { |e| e.event_id == c.events.last["id"] && e.text == "#{player} keeps all cards." }, "missing stand-pat message")
end
assert([:finished, :hand_complete].include?(c.replay.state[:phase]), "all-in exchange stuck before showdown")
assert(c.replay.state[:stacks].values.sum == 2000 && c.replay.state[:turn_deadline] == 0, "all-in lost chips or continued timer")
assert(c.replay.history.any? { |e| e.kind == :round_result && e.key.start_with?("showdown:") }, "all-in showdown missing")
assert(c.game.send(:poker_public_exchanges, c.replay).empty?, "forced standing pat was treated as voluntary evidence of hand strength")

# Folding the penultimate player settles the hand, not the tournament; the
# next deal starts a fresh clock and rejects the old timeout even under a new ID.
%w[holdem draw].each do |variant|
  trial = TimedCardCase.new(GameRoomGames::Poker.new, {"variant"=>variant}, %w[A B])
  2.times { trial.act({"action"=>"check"}) } if variant == "draw"
  trial.timeout
  assert(trial.replay.state[:phase] == :hand_complete && trial.replay.state[:turn_deadline] == 0, "uncontested hand did not stop timer")
  old_timeout = trial.events.last.merge("id"=>900)
  trial.context.now = trial.replay.state.fetch(:hand_resume_at)
  assert(trial.context.now == 125, 'The five-second settlement break changed')
  expected_deadline = trial.context.now + 20
  trial.act({"kind"=>"command","action"=>"deal"}, "A")
  assert(trial.replay.state[:turn_deadline] == expected_deadline && trial.replay.state[:stacks].values.sum + trial.replay.state[:contributions].values.sum == 2000, "new hand clock or chips changed")
  assert(trial.game.replay(trial.session,trial.events + [old_timeout],trial.repo).accepted_events == trial.events, "old timeout folded a player in the next hand")
end

c = TimedCardCase.new(GameRoomGames::Poker.new, {"variant"=>"draw"})
3.times { c.act({"action"=>"check"}) }
before = c.replay
player = c.replay.current_player
c.act({"action"=>"exchange", "cards"=>"[]"})
assert(c.game.send(:poker_public_exchanges, c.replay)[player] == 0, "clock interpreted as an exchanged card")
cue = GameRoomSounds.event_cue(game:c.game,event:c.events.last,before_replay:before,after_replay:c.replay,repository:c.repo,viewer:player)
assert(cue == nil, "standing pat sounded like an exchange")

# A timeout fold during exchange must not strand a side pot with no eligible
# players. Return an unmatched excess, but keep matched forfeited chips in play.
[[%w[A B C], {"A"=>100,"B"=>100,"C"=>300}, %w[C]],
 [%w[A B C D], {"A"=>100,"B"=>100,"C"=>200,"D"=>200}, %w[C D]]].each do |players, contributions, folding|
  trial = TimedCardCase.new(GameRoomGames::Poker.new, {"variant"=>"draw"}, players)
  s = trial.replay.state
  s.merge!(phase: :exchange, exchanged: {}, current_player: "C", contributions: contributions,
    all_in: {"A"=>true,"B"=>true}, stacks: players.to_h { |p| [p, %w[A B].include?(p) ? 0 : 1000] })
  total = s[:stacks].values.sum + contributions.values.sum
  original_c_stack = s[:stacks]["C"]
  hist = []
  folding.each do |p|
    s[:current_player] = p
    assert(trial.game.send(:apply_timeout, s, {"id"=>20,"value"=>120.to_s(36)}, "A", trial.repo, hist, 120), "side-pot exchange fold failed")
  end
  assert(s[:stacks]["C"] == original_c_stack + 200, "uncalled excess forfeited by exchange timeout") if players.length == 3
  2.times do
    p = s[:current_player]
    assert(trial.game.send(:apply_exchange, s, {"id"=>21,"value"=>""}, p, trial.repo, hist), "side-pot standing pat failed")
  end
  assert(s[:stacks].values.sum == total, "exchange timeout lost a side pot")
end

# Timer envelope must leave room for even a long-running tournament deal.
s = c.replay.state.dup
s.merge!(phase: :hand_complete, hand_number: 1_000_000, turn_number: 10_000_000,
  turn_started: 2_000_000_000, turn_deadline: 0)
r = GameRoomGames::Replay.new(players: s[:players], state: s)
ctx = GameRoomGames::ActionContext.new(now:2_000_000_600, random_source:NewGames116Random.new)
status, plan = c.game.action_for({"kind"=>"command","action"=>"deal"}, r, "A", context:ctx)
assert(status == :ok && plan.events.one? && plan.events.first.value.bytesize <= 64, "timed poker deal exceeds event budget")

puts "PASS card timeouts: 99 penalty/zero-token grace/direction, both Poker variants and all betting structures, fold vs all-in exchange, clocks, stale/duplicate events, paused time, sounds and payload limits"
