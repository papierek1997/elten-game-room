require_relative '../../support/clock_event_contract'
require_relative '../../support/private_card_games'
require_relative '../../../games/poker'

def poker_idle_label(game, replay, viewer)
  surface = game.surface_spec(replay, viewer)
  assert(surface.is_a?(GameSurfaces::PawnTrackSpec), 'The idle poker surface changed its native control type')
  assert(surface.items.one? && surface.items.first.action.nil?, 'An idle poker label became an actionable command')
  surface.items.first.label
end

label_errors = []
%w[holdem draw].product([false, true]).each do |variant, private_cards|
  ClockEventContract.with_server_time do |time|
    game = GameRoomGames::Poker.new
    marker = {'publication_ref' => {'author' => 'Alice', 'publication_key' => 'poker-pause-label'},
      'schedule_id' => 'a' * 64, 'match_id' => 'b' * 64, 'leg' => 1} if private_cards
    h = NativeRoomHarness.new(game: game, users: %w[Alice Bob], tournament: marker,
      options: game.default_options.merge('variant' => variant, 'bot_delay' => 0))
    h.start
    h.add_client('Watcher')
    assert(h.join('Watcher'), 'The native observer could not join')
    viewers = %w[Alice Bob Watcher]
    label = "#{variant}/private=#{private_cards}"
    viewers.each do |viewer|
      initial = h.replay(viewer)
      assert(initial.state[:phase] == :awaiting_deal, "#{label}: unexpected initial phase")
      unless poker_idle_label(game, initial, viewer) == 'Waiting for the next deal.'
        label_errors << "#{label}: #{viewer} initial idle status names an absent player"
      end
    end

    runners = h.users.to_h do |user|
      [user, runner_for(h, user).tap { |runner| runner.instance_variable_set(:@clock, ClockEventContract.clock) }]
    end
    begin
      16.times { PrivateCardGamesTest.tick(h, runners) }
      active = h.replay('Alice')
      actor = active.current_player
      assert(active.state[:phase] == :betting && actor, "#{label}: initial native deal did not finish")
      waiting = (h.users - [actor]).first
      assert(poker_idle_label(game, h.replay(waiting), waiting) == "Waiting for #{actor}",
        "#{label}: the ordinary named-player status changed")
      time.call(1002)
      choice = game.legal_actions(h.replay(actor), actor).find { |item| item['action'] == 'fold' }
      PrivateCardGamesTest.submit(h, runners, actor, choice)
      viewers.each do |viewer|
        paused = h.replay(viewer)
        assert(paused.state[:phase] == :hand_complete && paused.current_player.nil?, "#{label}: hand did not end")
        unless poker_idle_label(game, paused, viewer) == 'Waiting for the next deal.'
          label_errors << "#{label}: #{viewer} receives a blank-player status during the hand pause"
        end
        assert(paused.state[:hand_resume_at] == 1007, "#{label}: presentation changed the five-second boundary")
        final = GameRoomSnapshot.copy(paused)
        final.winner = 'Alice'
        final.state[:winner] = 'Alice'
        final.state[:phase] = :finished
        assert(poker_idle_label(game, final, viewer) == game.result_text(final),
          "#{label}: the idle label replaced the final result")
      end
      time.call(1007)
      16.times { PrivateCardGamesTest.tick(h, runners) }
      assert(h.replay('Alice').state[:phase] == :betting && h.replay('Alice').state[:hand_number] == 2,
        "#{label}: the neutral status prevented the next deal")
    ensure
      runners.each_value(&:close)
    end
  end
end
assert(label_errors.empty?, label_errors.join("\n"))

puts 'PASS Poker idle surface: named active player, neutral initial/hand pause, unchanged final result and five-second next deal'
