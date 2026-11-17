require 'digest'
require_relative "../../../lib/game_simulation"
require_relative "../../../games/makao"

def assert(value, message)
  raise message unless value
end

game = GameRoomGames::Makao.new
players = ['Alice', 'bot:1:1', 'Carol']
bot = players[1]
state = game.send(:initial_state, players, game.normalize_options('profile' => 'custom', 'jokers' => true, 'jack_requests_rank' => true))
hand = %w[JH JS JD JC X0 X1 7H]
other = %w[2C 3C 4C 5C 6C]
top = '7S'
state.update(phase: :playing, current_player: bot, hands: {players[0] => other, bot => hand, players[2] => ['AH']},
  draw_pile: game.send(:makao_deck, true) - hand - other - [top, 'AH'], discard: [top], declared_suit: 'S', declared_rank: '7')
replay = GameRoomGames::Replay.new(players: players, current_player: bot, state: state, accepted_events: [], history: [], draw: false)

# Compare against the former exhaustive predicate, including simultaneous
# declarations/catches, every ordinary turn ending, and enabled clock state.
cases = 0
[false, true].repeated_permutation(5) do |declared, window, drawn, allow_draw, skip|
  state[:makao_declarations] = {'Carol' => declared}
  state[:makao_windows] = {'Carol' => window}
  state[:drawn_this_turn] = drawn
  state[:options]['allow_playable_draw'] = allow_draw
  state[:options]['thinking_time'] = 10
  state[:turn_deadline] = 5
  state[:skip_penalty] = skip ? 1 : 0
  state[:draw_penalty] = skip ? 2 : 0
  declaring = players.select { |p| state[:hands][p].length == 1 && !state[:makao_declarations][p] }
  expected = (declaring + [bot] + players).uniq.select { |p| !game.legal_actions(replay, p).empty? }
  assert(game.active_actors(replay) == expected, "actor order/availability changed: #{[declared, window, drawn, allow_draw, skip]}")
  cases += 1
end
state[:phase] = :awaiting_deal
assert(game.active_actors(replay).empty?, 'inactive phase exposes actors')
state[:phase] = :playing
replay.winner = bot
assert(game.active_actors(replay).empty?, 'finished match exposes actors')

# Exact audit reproducer: discovering a pending bot does no packet work;
# choosing its action enumerates the unchanged 2,868 root choices only once.
# The own-turn proof separately validates at most 128 simulated transitions.
players.pop
state[:hands].delete('Carol')
state[:draw_pile] << 'AH'
state[:makao_declarations] = {}
state[:makao_windows] = {}
state[:drawn_this_turn] = false
state[:options]['thinking_time'] = 0
state[:options]['allow_playable_draw'] = true
state[:skip_penalty] = state[:draw_penalty] = 0
replay.winner = nil
before = Marshal.dump(replay)
counts = Hash.new(0)
root_counts = Hash.new(0)
planning_counts = Hash.new(0)
planning_depth = 0
trace = TracePoint.new(:call, :return) do |event|
  next unless event.self.equal?(game)
  if event.method_id == :bot_own_finishes
    planning_depth += event.event == :call ? 1 : -1
  end
  next unless event.event == :call
  # The shared private-hand guard delegates ordinary hands unchanged. Count
  # actual packet enumeration, not the forwarding wrapper's method entry.
  next if event.method_id == :legal_actions && event.defined_class != GameRoomGames::Makao
  counts[event.method_id] += 1
  (planning_depth.positive? ? planning_counts : root_counts)[event.method_id] += 1
end
coordinator = GameRoomBots::Coordinator.new
assert(trace.enable { coordinator.pending_bot(game, replay) } == bot, 'pending bot changed')
assert(counts[:legal_actions] == 0 && counts[:validate_packet] == 0, 'pending check enumerates packets')
source = GameRoomRandom::SeededSource.new(19)
context = GameRoomGames::ActionContext.new(random_source: source, now: 100)
decision = trace.enable { coordinator.decide_next(game: game, replay: replay, context: context) }
assert(root_counts[:legal_actions] == 1 && root_counts[:validate_packet] == 6053,
  "decision repeats root packet enumeration: #{root_counts.slice(:legal_actions, :validate_packet)}")
assert(planning_depth.zero? && planning_counts[:apply_play] <= 128 &&
  planning_counts[:validate_packet] == planning_counts[:apply_play], 'own-turn proof exceeded its validated transition budget')
assert(planning_counts[:legal_actions].zero?, 'own-turn proof enumerated an unknown rival continuation')
assert(decision.available_actions.length == 2868, 'available action count changed')
assert(Digest::SHA256.hexdigest(Marshal.dump(decision.available_actions)) == 'c83b04a7bd472a29c3e911dca8ff4153c8fe8987260382948f1a2cdca958e49c', 'legal action ordering/content changed')
assert(decision.action == {'kind' => 'card_packet', 'action' => 'play', 'cards' => '["X1","JS","JD","JC","X0","JH"]', 'choice' => '7'}, 'strategy choice changed')
assert(source.roll(count: 8, sides: 6).values == [6,3,1,4,5,3,3,1], 'strategy RNG consumption changed')
assert(Marshal.dump(replay) == before, 'actor discovery mutated replay')
puts "Makao actor availability: #{cases} exhaustive comparisons; one root enumeration, bounded own-turn proof; decision/RNG preserved"
