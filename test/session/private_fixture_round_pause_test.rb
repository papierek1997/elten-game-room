require_relative '../support/private_card_games'
require_relative '../../games/bridge'

clock = ClockEventContract::ManualTime.new(1000)
game = GameRoomGames::Bridge.new
h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob Carol Dave],
  options: {'variant'=>'duplicate', 'boards'=>4}, clock: clock)
begin
  assert(clock.now == 1000 && h.replay('Alice').state[:phase] == :bidding,
    'The initial private deal advanced fixture time')
  2.times do |index|
    4.times do
      actor = h.replay('Alice').current_player
      PrivateCardGamesTest.submit(h, runners, actor, {'kind'=>'command', 'action'=>'call', 'call'=>'P'})
    end
    20.times do
      break if h.replay('Alice').state[:phase] == :round_complete
      PrivateCardGamesTest.tick(h, runners, advance_pause: false)
    end
    assert(h.replay('Alice').state[:phase] == :round_complete, 'A real private board did not reach its audited boundary')
    before = h.events('Alice')
    if index.zero?
      clock.advance(4)
      PrivateCardGamesTest.tick(h, runners, advance_pause: false)
      assert(h.events('Alice') == before && h.replay('Alice').state[:round] == 1,
        'The controlled clock bypassed a round gate before five seconds')
      clock.advance(1)
    else
      PrivateCardGamesTest.tick(h, runners)
      assert(h.events('Alice') == before && clock.now == 1010,
        'Automatic fixture advancement wrote an event or skipped the break')
    end
    16.times { PrivateCardGamesTest.tick(h, runners, advance_pause: false) }
    assert(h.replay('Alice').state[:phase] == :bidding && h.replay('Alice').state[:round] == index + 2,
      'The real session runner did not resume at the controlled boundary')
    assert(h.core.entries.last['created_at'] == clock.now,
      'Native stack/private receipts and the runner used different clocks')
    PrivateCardGamesTest.assert_private(h)
  end
  assert_raises(ArgumentError) { clock.advance(-1) }
  assert(clock.now == 1010, 'Rejected clock movement changed time')
  assert(h.users.map { |user| h.events(user) }.uniq.one?, 'Controlled private histories diverged')
  h.users.each do |user|
    assert(h.replay(user).accepted_events.size == h.events(user).size, 'Controlled private receipt was rejected')
  end
  # Full states intentionally differ by the viewer's own hidden hand.
  PrivateCardGamesTest.assert_private(h)
ensure
  runners.each_value(&:close)
end

# Fixtures which do not opt in retain ordinary wall-clock behavior.
wall = Time.now.to_i
broker = NativeLiveSessionsBroker.new
assert(broker.now.between?(wall, Time.now.to_i), 'The default native fixture clock changed')
puts 'PASS private fixture clock: unchanged default, coherent native receipts, exact five-second gates and three real private boards'
