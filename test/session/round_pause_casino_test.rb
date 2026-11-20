require_relative '../support/clock_event_contract'
require_relative '../support/session_runner'
require_relative '../../games/blackjack'
require_relative '../../games/blackjack_dice'
require_relative '../../games/dice_poker'
require_relative '../../games/liars_dice'
require_relative '../../games/roulette'

def pause_test_choice(game, replay, actor, context)
  actions = game.legal_actions(replay, actor, context: context)
  if game.id == 'roulette'
    return actions.find { |action| action['action'] == (replay.state[:bets][actor].empty? ? 'bet' : 'ready') }
  end
  %w[stand check call score challenge].each do |name|
    found = actions.find { |action| action['action'] == name }
    return found if found
  end
  actions.first
end

cases = [GameRoomGames::Blackjack, GameRoomGames::BlackjackDice, GameRoomGames::DicePoker,
  GameRoomGames::LiarsDice, GameRoomGames::Roulette].map { |type| [type, false] }
cases << [GameRoomGames::Blackjack, true]
cases.each do |type, next_dealer_blackjack|
  ClockEventContract.with_server_time do |time|
    game = type.new
    f = ClockEventContract::Fixture.new(game, users: %w[Alice Bob])
    h = f.h
    runners = h.users.to_h { |user| [user, runner_for(h, user)] }
    runners.each_value { |runner| runner.instance_variable_set(:@clock, ClockEventContract.clock) }
    pause = GameRoomRoundPause.new(h.repositories['Alice'])
    paused = -> { pause.active?(game: game, replay: f.replay, session: f.snapshot.session, now: f.logical_now) }
    begin
      300.times do
        h.users.each { |user| step(h, runners[user], user) }
        break if paused.call
        h.users.each do |user|
          replay = f.replay(user)
          choice = pause_test_choice(game, replay, user, f.context(user))
          next unless choice
          status, = h.as(user) { runners[user].submit(session: f.snapshot(user).session, replay: replay,
            selection: choice, actor: user) }
          assert(status == :ok || (status == :round_pause && paused.call), "#{game.id}: legal input rejected: #{status}")
          break if paused.call
        end
        break if paused.call
      end
      assert(paused.call && !f.replay.finished?, "#{game.id}: did not pause after its first complete settlement")
      before = h.events('Alice')
      round = f.replay.state[:round]
      actor = f.replay.current_player
      if actor && (choice = pause_test_choice(game, f.replay(actor), actor, f.context(actor)))
        status, = h.as(actor) { runners[actor].submit(session: f.snapshot(actor).session,
          replay: f.replay(actor), selection: choice, actor: actor) }
        assert(status == :round_pause, "#{game.id}: a human bypassed the break")
      end
      time.call(1004)
      h.users.each { |user| step(h, runners[user], user, count: 5) }
      assert(h.events('Alice') == before, "#{game.id}: automatic/private writes during the break")
      if game.id == 'blackjack'
        # Pin the native recipe, not the reducer outcome: seed byte 00 gives
        # totals 9/12/15; byte 22 gives 20/19/21, ending the next hand at once.
        h.view('Alice').next_random_values = Array.new(16, next_dealer_blackjack ? 35 : 1)
      end
      time.call(1005)
      h.users.each { |user| step(h, runners[user], user, count: 5) }
      actor = f.replay.current_player
      if !paused.call && actor && (choice = pause_test_choice(game, f.replay(actor), actor, f.context(actor)))
        status, = h.as(actor) { runners[actor].submit(session: f.snapshot(actor).session,
          replay: f.replay(actor), selection: choice, actor: actor) }
        assert(status == :ok, "#{game.id}: new input rejected at five seconds: #{status}")
      end
      assert(h.events('Alice').size > before.size, "#{game.id}: unchanged revision never wakes")
      current = f.replay
      repository = h.repositories['Alice']
      latest_id = repository.event_id(current.accepted_events.last)
      settled_again = current.state[:round] > round && latest_id != repository.event_id(before.last) &&
        current.history.any? { |entry| entry.event_id == latest_id && game.round_pause_end_kinds.include?(entry.kind) }
      assert(!paused.call || settled_again, "#{game.id}: a non-settling new action restarted the pause")
      if game.id == 'blackjack'
        assert(next_dealer_blackjack ? paused.call && settled_again : !paused.call,
          'Pinned second blackjack hand did not exercise its intended pause boundary')
      end
      assert(f.replay.state[:round] >= round, "#{game.id}: the break reset the round counter")
      h.assert_converged("#{game.id} five-second settlement pause")
      puts "PASS native #{game.id}: complete settlement, human/automatic gates, exact next-round wake, new settlement #{next_dealer_blackjack}"
    ensure
      runners.each_value(&:close)
    end
  end
end
