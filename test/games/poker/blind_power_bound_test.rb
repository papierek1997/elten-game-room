require_relative '../../support/private_card_games'
require_relative '../../../games/poker'

# Fail before performing a huge native Integer power. The baseline reaches
# this guard through an accepted deal/fold/deal, without risking an allocation.
module PokerBlindPowerGuard
  class Unbounded < StandardError; end

  def **(exponent)
    if Thread.current[:poker_blind_power_guard] && exponent.is_a?(Integer) && exponent.abs > 1024 && abs >= 2
      raise Unbounded, "Unbounded Poker blind power: #{self} ** #{exponent}"
    end
    super
  end
end
Integer.prepend(PokerBlindPowerGuard)
previous_power_guard = Thread.current[:poker_blind_power_guard]
Thread.current[:poker_blind_power_guard] = true

begin
begin
  2**2048
  raise 'The regression allocation guard is not active'
rescue PokerBlindPowerGuard::Unbounded
end

%w[holdem draw].each do |variant|
  game = GameRoomGames::Poker.new
  options = game.normalize_options(game.default_options.merge('variant' => variant, 'draw_uses_blinds' => true,
    'blind_interval' => 'minutes', 'blind_interval_value' => 1, 'blind_multiplier' => 10))
  h = NativeRoomHarness.new(game: game, users: %w[Alice Bob], options: options)
  h.start
  context = GameRoomGames::ActionContext.new(session_id: h.session['__id'], table_id: h.table['__id'],
    now: 100, random_source: GameRoomRandom::SeededSource.new(19))
  h.submit('Alice', {'kind' => 'command', 'action' => 'deal'}, context: context)
  first = h.replay('Alice')
  assert(first.state[:hand_number] == 1 && first.state[:phase] == :betting, 'The first legal hand did not start')
  context.now = 110
  h.submit(first.current_player, {'kind' => 'command', 'action' => 'fold'}, context: context)
  assert(h.replay('Alice').state[:phase] == :hand_complete, 'The real fold did not close the first hand')
  context.now = 1_000_000_000_000_000
  h.submit('Alice', {'kind' => 'command', 'action' => 'deal'}, context: context)
  h.users.each do |user|
    replay = h.replay(user)
    assert(replay.accepted_events.size == 3 && replay.state[:hand_number] == 2, 'The second authenticated hand was not accepted')
    committed = %i[hand_complete finished].include?(replay.state[:phase]) ? 0 : replay.state[:contributions].values.sum
    assert(replay.state[:stacks].values.sum + committed == 2000, 'Saturation changed the chip pool')
    assert(replay.state[:options] == options, 'Saturation rewrote the nominal blind options')
    assert(h.events(user).last['__server_random'], 'The regression did not use a native server-random receipt')
    assert(h.events(user).all? { |event| event['value'].bytesize <= 64 }, 'The regression exceeded the real action dialect')
  end
  h.assert_converged("bounded #{variant} blind growth", expected_count: 3)
end

# Account-owned cards use the same arithmetic before starting the next pool.
game = GameRoomGames::Poker.new
h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob], options: {
  'blind_interval' => 'minutes', 'blind_interval_value' => 1, 'blind_multiplier' => 10
})
begin
  first = h.replay('Alice')
  actor = first.current_player
  own = h.replay(actor)
  fold = game.legal_actions(own, actor).find { |item| item['action'] == 'fold' }
  assert(fold, 'The private actor observation has no legal fold')
  PrivateCardGamesTest.submit(h, runners, actor, fold)
  assert(h.replay('Alice').state[:phase] == :hand_complete, 'Private fold did not complete its hand')
  context = GameRoomGames::ActionContext.new(session_id: h.session['__id'], table_id: h.table['__id'],
    now: 1_000_000_000_000_000, random_source: GameRoomRandom::SeededSource.new(19))
  h.submit('Alice', {'kind' => 'command', 'action' => 'deal'}, context: context)
  h.users.each do |user|
    assert(h.replay(user).state[:hand_number] == 2, 'The private next deal was not accepted')
  end
ensure
  runners.each_value(&:close)
end

# Every reachable nominal blind remains exact, with no change to the schedule.
game = GameRoomGames::Poker.new
[2, 3, 10].product([2, 8], [100, 100_000], [5, 10, 1_000_000]).each do |multiplier, seats, chips, base|
  options = game.default_options.merge('blind_interval' => 'hands', 'blind_interval_value' => 1,
    'blind_multiplier' => multiplier, 'starting_chips' => chips, 'small_blind' => base, 'big_blind' => base * 2)
  state = game.send(:initial_state, Array.new(seats) { |index| "Player#{index}" }, options)
  total = seats * chips
  (0..32).each do |level|
    state[:hand_number] = level + 1
    assert(game.send(:blind_level, state) == level, 'The nominal blind schedule changed')
    %w[small_blind big_blind].each do |key|
      expected = options[key] * multiplier**level
      actual = game.send("current_#{key}", state)
      if expected <= total || level.zero?
        assert(actual == expected, "Reachable nominal blind changed: #{[multiplier, seats, chips, base, level, key].inspect}")
      else
        assert(actual > total && actual <= expected, 'An unreachable blind no longer covers every possible stack')
      end
    end
  end
end

options = game.default_options.merge('blind_interval' => 'hands', 'blind_interval_value' => 1,
  'blind_multiplier' => 2)
state = game.send(:initial_state, %w[Alice Bob], options)
(-4..4).each do |level|
  state[:hand_number] = level + 1
  expected = [state[:hand_number] - 1, 0].max
  assert(game.send(:current_big_blind, state) == 10 * 2**expected, 'Ordinary nominal arithmetic changed')
end
state[:hand_number] = 1_000_000_000_000_001
assert(game.send(:current_big_blind, state) > 2000, 'Large hand-based growth did not saturate above the pool')
# Inactive historical settings can divide by a negative interval. Such a
# fraction already rounds to zero chips; do not build an enormous denominator.
state[:options] = options.merge('blind_interval_value' => -1)
assert(game.send(:current_big_blind, state).to_i.zero?, 'Negative legacy growth no longer rounds to zero chips')
state[:options] = options.merge('blind_multiplier' => -2)
[1_000_000_000_000_000, 1_000_000_000_000_001].each do |level|
  state[:hand_number] = level + 1
  value = game.send(:current_big_blind, state)
  assert(value.abs > 2000 && value.negative? == level.odd?, 'Historical multiplier parity changed')
end

puts 'PASS Poker blind power: safe native deal/fold/deal, bounded arithmetic, exact reachable blinds, unchanged options and conserved chips'
ensure
  Thread.current[:poker_blind_power_guard] = previous_power_guard
end
