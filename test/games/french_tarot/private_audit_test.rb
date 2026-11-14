require_relative '../../support/private_card_games'
require_relative '../../../games/french_tarot_support/french_tarot_table'

%i[discard_king revoke].each do |attack|
  game = GameRoomGames::FrenchTarotTable.new
  room, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob Carol Dan])
  injected = false
  begin
    400.times do
      public_replay = room.replay(room.users.first)
      break if public_replay.finished? || public_replay.state[:private_error]
      phase = public_replay.state[:phase]
      if %i[private_draw private_show private_prepare private_wait private_dealing round_complete].include?(phase)
        PrivateCardGamesTest.tick(room, runners)
        next
      end
      actor = public_replay.current_player
      replay = room.replay(actor)
      actions = game.legal_actions(replay, actor)
      if phase == :bidding
        choice = replay.state[:bid_count].zero? ? 'petite' : 'pass'
        PrivateCardGamesTest.submit(room, runners, actor, actions.find { |action| action['choice'] == choice })
        next
      end
      hand = replay.state[:hands].fetch(actor)
      forged = if !injected && attack == :discard_king && phase == :discard
        index = hand.index { |card| GameRoomGames::FrenchTarotCards::DECODED[card]&.last == 14 }
        ['tarot_discard', index.to_s] if index
      elsif !injected && attack == :revoke && phase == :playing
        card = hand.find { |value| actions.none? { |action| action['card'] == value } }
        ['play', card] if card
      end
      if forged
        plan = game.send(:event_plan, *forged)
        status, secured = game.send(:private_secure_plan, plan, replay.state, actor)
        assert(status == :ok, 'The adversarial fixture did not use a genuine native claim/reveal')
        # A modified client bypasses local choices, not native ownership.
        room.write(actor, secured.events)
        injected = true
      else
        assert(actions.first, "Missing ordinary action in #{phase}")
        PrivateCardGamesTest.submit(room, runners, actor, actions.first)
      end
    end
    assert(injected, "The fixture never reached #{attack}")
    room.users.each do |viewer|
      replay = room.replay(viewer)
      assert(replay.state[:private_error] == :invalid_round, "#{viewer}: #{attack} escaped the final audit")
      assert(!replay.finished? && replay.state[:scores].values.all?(&:zero?), 'An illegal round published sporting results')
      assert(replay.history.none? { |entry| entry.kind == :result }, 'An illegal round announced a winner')
    end
    puts "PASS French Tarot: authenticated #{attack} cannot produce a scored round"
  ensure
    runners.each_value(&:close)
  end
end
