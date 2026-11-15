require_relative '../support/private_card_games'
require_relative '../../games/catalog'

%w[belote jass hearts].each do |id|
  game = GameRoomGames::CATALOG.build(id)
  h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob Carol Dan])
  begin
    cheated = false
    240.times do
      replay = h.replay(h.users.first)
      break if replay.state[:private_error]
      raise "#{id}: ended before rejecting an illegal round" if replay.finished?
      actor = replay.current_player
      if !actor || replay.state[:phase].to_s.start_with?('private_') || replay.state[:phase] == :round_complete
        PrivateCardGamesTest.tick(h, runners)
        next
      end
      mine = h.replay(actor)
      actions = game.legal_actions(mine, actor)
      if !cheated && mine.state[:phase] == :playing
        owned = mine.state[:hands].fetch(actor)
        legal = actions.filter_map { |action| action['card'] }
        illegal = (owned - legal).find { |card| !GameRoomPrivateCardLedger.hidden?(card) }
        if illegal
          before = mine.accepted_events.length
          # The native server proves ownership and publication, not following
          # suit. A modified client can publish this actual owned card.
          status, plan = game.send(:private_secure_plan, game.send(:event_plan, 'play', illegal), mine.state, actor)
          assert(status == :ok, "#{id}: owned-card receipt could not be prepared")
          h.write(actor, plan.events)
          assert(h.replay(actor).accepted_events.length > before, "#{id}: fixture did not exercise the provisional private reducer")
          cheated = true
          next
        end
      end
      if actions.empty?
        PrivateCardGamesTest.tick(h, runners)
      else
        choice = if mine.state[:phase] == :bidding
          actions.find { |action| action['choice'] != 'pass' }
        else
          actions.first
        end
        PrivateCardGamesTest.submit(h, runners, actor, choice || actions.first)
      end
    end
    assert(cheated, "#{id}: no owned illegal card was exercised")
    h.users.each do |user|
      result = h.replay(user)
      assert(result.state[:private_error] == :invalid_round, "#{id}: an owned off-suit card escaped final audit")
      assert(!result.finished? && !result.winner && result.state[:scores].values.all?(&:zero?),
        "#{id}: rejected round published a score or winner")
      assert(result.history.none? { |entry| [:round_result, :result].include?(entry.kind) }, "#{id}: rejected round announced a final result")
    end
    puts "PASS #{id}: real native card ownership does not bypass the production legality audit"
  ensure
    runners.each_value(&:close)
  end
end
