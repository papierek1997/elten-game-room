require_relative '../../support/cash_auction'
require_relative '../../../lib/game_random'
include GameRoomTest::Assertions

[2, 4, 8].each do |count|
  players = Array.new(count) { |index| "Player#{index + 1}" }
  match = CashAuctionFixture::Match.new(players: players)
  random = GameRoomRandom::SeededSource.new(20261114 + count)
  coordinator = GameRoomBots::Coordinator.new
  decisions = Hash.new(0)
  2000.times do |step|
    replay = match.replay
    break if replay.finished?
    state = replay.state
    case state[:phase]
    when :drawing
      match.begin_round(chest: (step % 5).zero?)
    when :question_pending
      match.reveal_question(seed: step + 1)
    when :auction
      if match.now >= state[:auction_deadline] || match.game.active_actors(replay).empty?
        match.now = [match.now, state[:auction_deadline]].max
        match.automatic
        next
      end
    end
    replay = match.replay
    next if replay.finished? || %i[drawing question_pending].include?(replay.state[:phase])
    context = GameRoomGames::ActionContext.new(now: match.now, server_random: true, random_source: random,
      table_owner: players.first, session_id: match.session['__id'])
    decision = coordinator.decide_next(game: match.game, replay: replay, context: context, controlled_actors: players)
    assert(decision, "#{count} players: no decision in #{replay.state[:phase]}")
    decisions[decision.action['action']] += 1
    match.submit(decision.action, actor: decision.actor, seed: step + 1)
    match.now += 1
  end
  assert(match.replay.finished?, "#{count} players: bot match did not finish")
  assert(decisions['submit'].positive? && decisions['pass'].positive?, 'Bots never bid or never give up')
  assert_equal(match.events, match.replay.accepted_events)
end
puts 'PASS Cash Auction complete 2/4/8-player bot games through the shared coordinator, deadlines, passes, questions, chests and ordinary reducer'
