require_relative '../support/clock_event_contract'
require_relative '../support/session_runner'
require_relative '../../games/poker'

ClockEventContract.with_server_time do |time|
  f = ClockEventContract::Fixture.new(GameRoomGames::Poker.new, users: %w[Alice Bob],
    options: {'thinking_time' => 30, 'blind_interval' => 'minutes', 'blind_interval_value' => 1})
  h = f.h
  runners = h.users.to_h { |user| [user, runner_for(h, user)] }
  runners.each_value { |runner| runner.instance_variable_set(:@clock, ClockEventContract.clock) }
  toggle = lambda do |user|
    snapshot = f.snapshot(user)
    h.as(user) { runners[user].toggle_round_pause(session: snapshot.session, replay: f.replay(user)) }
  end
  begin
    step(h, runners['Alice'])
    assert(toggle.call('Alice') == :unavailable, 'The host can pause an active hand')
    time.call(1002)
    actor = f.replay.current_player
    h.as(actor) do
      status, = runners[actor].submit(session: f.snapshot(actor).session, replay: f.replay(actor),
        selection: {'kind' => 'command', 'action' => 'fold'}, actor: actor)
      assert(status == :ok, 'The first hand did not finish')
    end
    time.call(1003)
    stale_boundary = f.snapshot.session
    assert(toggle.call('Bob') == :unavailable, 'A guest bypassed controller permissions')
    assert(toggle.call('Alice') == :ok, 'The host cannot pause between hands')
    h.users.each { |user| assert(f.snapshot(user).session['__round_pause'], 'Pause did not reach both accounts') }
    before = h.events('Alice')
    time.call(1303)
    h.users.each { |user| step(h, runners[user], user, count: 3) }
    assert(h.events('Alice') == before && f.replay.state[:hand_number] == 1, 'Permanent pause expired by itself')
    assert(f.logical_now == 1003, 'Manual pause advanced the rule clock')
    assert(toggle.call('Alice') == :ok, 'The same shortcut cannot resume')
    time.call(1306)
    step(h, runners['Alice'], count: 3)
    assert(f.replay.state[:hand_number] == 1, 'Resume discarded the remaining fixed pause')
    time.call(1307)
    step(h, runners['Alice'], count: 3)
    assert(f.replay.state[:hand_number] == 2 && f.replay.state[:turn_deadline] == 1037,
      'Resume lost the deadline or the full next thinking time')
    assert(f.replay.state[:blind_paused_seconds] == 5, 'Manual pause was counted again in blind escalation')
    h.as('Alice') { h.transports['Alice'].freeze_game(stale_boundary, round_pause: true) }
    assert(!f.snapshot.session['__frozen'], 'A stale round-pause record froze a later hand')
    # Technical freezes have a different owner/receipt and are never released
    # by the player's round-pause shortcut.
    f.freeze('Alice', true)
    assert(toggle.call('Alice') == :unavailable && f.snapshot.session['__frozen'], 'Shortcut released a technical freeze')
    f.freeze('Alice', false)
    h.assert_converged('manual round pause')
  ensure
    runners.each_value(&:close)
  end
end

ClockEventContract.with_server_time do |time|
  f = ClockEventContract::Fixture.new(GameRoomGames::Poker.new, users: %w[Alice Bob])
  f.submit('Alice')
  time.call(1002)
  f.submit(f.replay.current_player, {'kind' => 'command', 'action' => 'fold'})
  runners = f.h.users.to_h { |user| [user, runner_for(f.h, user)] }
  runners.each_value { |runner| runner.instance_variable_set(:@clock, ClockEventContract.clock) }
  begin
    time.call(1003)
    status = f.h.as('Alice') { runners['Alice'].toggle_round_pause(session: f.snapshot.session, replay: f.replay) }
    assert(status == :ok, 'Handover fixture cannot pause')
    f.h.as('Alice') { f.h.transports['Alice'].transfer_room_owner(f.h.table, 'Bob') }
    step(f.h, runners['Bob'], 'Bob', count: 3)
    status = f.h.as('Bob') { runners['Bob'].toggle_round_pause(session: f.snapshot('Bob').session, replay: f.replay('Bob')) }
    assert(status == :ok && !f.snapshot('Bob').session['__frozen'], "Successor cannot resume an inherited manual pause: #{status}")
    status = f.h.as('Alice') { runners['Alice'].toggle_round_pause(session: f.snapshot.session, replay: f.replay) }
    assert(status == :unavailable, 'The former host retained pause control')
  ensure
    runners.each_value(&:close)
  end
end
puts 'PASS native manual pause: host-only round boundary, both clients, indefinite freeze, same-key resume, full clocks, no technical unfreeze and host handover'
