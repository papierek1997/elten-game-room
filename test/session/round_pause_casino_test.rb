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

[GameRoomGames::Blackjack, GameRoomGames::BlackjackDice, GameRoomGames::DicePoker,
 GameRoomGames::LiarsDice, GameRoomGames::Roulette].each do |type|
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
      time.call(1005)
      h.users.each { |user| step(h, runners[user], user, count: 5) }
      actor = f.replay.current_player
      if actor && (choice = pause_test_choice(game, f.replay(actor), actor, f.context(actor)))
        status, = h.as(actor) { runners[actor].submit(session: f.snapshot(actor).session,
          replay: f.replay(actor), selection: choice, actor: actor) }
        assert(status == :ok, "#{game.id}: new input rejected at five seconds: #{status}")
      end
      assert(h.events('Alice').size > before.size, "#{game.id}: unchanged revision never wakes")
      assert(!paused.call, "#{game.id}: first new action restarted the pause")
      assert(f.replay.state[:round] >= round, "#{game.id}: the break reset the round counter")
      h.assert_converged("#{game.id} five-second settlement pause")
      puts "PASS native #{game.id}: complete settlement, human/automatic gates, exact next-round wake and no repeat"
    ensure
      runners.each_value(&:close)
    end
  end
end
