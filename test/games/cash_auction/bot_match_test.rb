require_relative '../../support/cash_auction'
require_relative '../../../lib/game_random'
include GameRoomTest::Assertions

$stdout.sync = true
unless ARGV.empty? || (ARGV.length == 2 && %w[1 2 3 4].include?(ARGV[0]) && %w[2 4 8].include?(ARGV[1]))
  raise ArgumentError, 'Expected no arguments, or rules version (1, 2, 3 or 4) and player count (2, 4 or 8)'
end
cases = ARGV.empty? ? [1, 2, 3, 4].product([2, 4, 8]) : [[ARGV[0].to_i, ARGV[1].to_i]]
cases.each do |version, count|
    label = "v#{version}, #{count} players"
    puts "#{label}: starting"
    players = Array.new(count) { |index| "Player#{index + 1}" }
    options = version >= 2 ? {'content_language_id'=>'pl-PL', 'content_pack_ids'=>%w[quiz.harry_potter.books.pl quiz.wikidata.pl quiz.witcher.books.pl]} : {}
    match = CashAuctionFixture::Match.new(players: players, options: options, rules_version: version)
    replay = match.replay
    if version >= 2
      assert_equal(3, replay.state[:options]['content_pack_ids'].length,
        'The revised bot game did not use the real three-pack Polish pool')
    end
    random = GameRoomRandom::SeededSource.new(20261114 + count)
    coordinator = GameRoomBots::Coordinator.new
    decisions = Hash.new(0)
    waits = 0
    2000.times do |step|
      break if replay.finished?
      state = replay.state
      if step % 100 == 0
        puts "#{label}: step #{step}; #{match.events.length} native events; phase #{state[:phase]}; questions #{state[:completed_rounds]}"
      end
      case state[:phase]
      when :drawing
        # Preserve the historical schedule. In v2, chests do not complete a
        # question round, so mix them by auction number rather than loop work.
        chest = (version >= 2 ? state[:round] : step) % 5 == 0
        replay = match.begin_round(chest: chest)
      when :question_pending
        replay = match.reveal_question(seed: step + 1)
      when :opening_chests
        if version >= 3
          match.now = replay.state[:open_chests_at]
          replay = match.automatic(seed: step + 1)
          next
        end
      when :auction
        if match.now >= state[:auction_deadline] || match.game.active_actors(replay).empty?
          match.now = [match.now, state[:auction_deadline]].max
          replay = match.automatic
          next
        end
      end
      next if replay.finished? || %i[drawing question_pending].include?(replay.state[:phase])
      context = GameRoomGames::ActionContext.new(now: match.now, server_random: true, random_source: random,
        table_owner: players.first, session_id: match.session['__id'])
      decision = coordinator.decide_next(game: match.game, replay: replay, context: context, controlled_actors: players)
      if !decision && version >= 2 && replay.state[:phase] == :auction
        waits += 1
        match.now = replay.state[:auction_deadline]
        next
      end
      assert(decision, "#{label}: no decision in #{replay.state[:phase]}")
      decisions[decision.action['action']] += 1
      # Plan against the current real replay, materialize the native request,
      # then reduce the appended log once. Re-reading an unchanged raw history
      # would copy its entire authenticated input/checkpoint on every read.
      status, plan = match.game.action_for(decision.action, replay, decision.actor, context: context)
      assert_equal(:ok, status, "#{label}: the coordinator proposed a refused move")
      accepted = replay.accepted_events.length
      plan.events.each { |command| match.materialize(command, actor: decision.actor, seed: step + 1) }
      replay = match.replay
      assert_equal(accepted + plan.events.length, replay.accepted_events.length, "#{label}: replay refused a planned native event")
      match.now += 1
    end
    assert(replay.finished?, "#{label}: bot match did not finish within 2000 steps")
    assert(decisions['submit'].positive?, "#{label}: bots never bid")
    assert(version >= 2 ? waits.positive? && decisions['pass'].zero? : decisions['pass'].positive?, "#{label}: bots failed to decline costly bids normally")
    if version >= 2
      assert(match.events.any? { |event| event['action'] == 'question' }, "#{label}: the match never drew a real quiz question")
      final = replay.state
      assert(final[:completed_auctions] > final[:completed_rounds], 'Revised bot play counted a chest as a question')
    end
    assert_equal(match.events, replay.accepted_events)
    cold = match.game.build_session_game.replay(match.session, match.events, match.repository)
    assert_equal(replay.state, cold.state, "#{label}: cold replay changed the bot result")
    assert_equal(replay.accepted_events, cold.accepted_events, "#{label}: cold replay changed the accepted bot moves")
    puts "#{label}: #{match.events.length} accepted native events; shared coordinator and cold replay OK"
end
puts "PASS Cash Auction complete bot matches: #{cases.map { |version, count| "v#{version}/#{count}" }.join(', ')}; shared coordinator, native seeds/deadlines, questions, passes, chests and production cold replay"
