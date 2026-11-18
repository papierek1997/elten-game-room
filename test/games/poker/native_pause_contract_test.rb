require_relative '../../support/clock_event_contract'
require_relative '../../support/private_card_games'
require_relative '../../../games/poker'
require_relative '../../../lib/game_sounds'

def poker_snapshot(h, user = 'Alice')
  h.repositories.fetch(user).snapshot_for(h.session)
end

def poker_freeze(h, owner, frozen)
  h.as(owner) { h.transports.fetch(owner).freeze_game(poker_snapshot(h, owner).session, frozen: frozen) }
end

def poker_runners(h)
  h.users.to_h do |user|
    [user, runner_for(h, user).tap { |runner| runner.instance_variable_set(:@clock, ClockEventContract.clock) }]
  end
end

%w[holdem draw].product([0, 30], [false, true]).each do |variant, thinking_time, private_cards|
  ClockEventContract.with_server_time do |time|
    game = GameRoomGames::Poker.new
    marker = {'publication_ref' => {'author' => 'Alice', 'publication_key' => 'poker-pause'},
      'schedule_id' => 'a' * 64, 'match_id' => 'b' * 64, 'leg' => 1} if private_cards
    h = NativeRoomHarness.new(game: game, users: %w[Alice Bob], tournament: marker,
      options: game.default_options.merge('variant' => variant, 'thinking_time' => thinking_time, 'bot_delay' => 0))
    h.start
    runners = poker_runners(h)
    label = "#{variant}/#{thinking_time}/#{private_cards}"
    begin
      16.times { PrivateCardGamesTest.tick(h, runners) }
      assert(h.replay('Alice').state[:phase] == :betting, "#{label}: initial deal did not finish")
      time.call(1002)
      poker_freeze(h, 'Alice', true)
      time.call(1062)
      poker_freeze(h, 'Alice', false)
      time.call(1064)
      actor = h.replay('Alice').current_player
      choice = game.legal_actions(h.replay(actor), actor).find { |item| item['action'] == 'fold' }
      PrivateCardGamesTest.submit(h, runners, actor, choice)
      assert(h.replay('Alice').state[:hand_resume_at] == 1009, "#{label}: hand end used wall time after a pause")
      first_events = poker_snapshot(h).events
      time.call(1066)
      h.as('Alice') { h.transports.fetch('Alice').transfer_room_owner(h.table, 'Bob') }
      4.times { PrivateCardGamesTest.tick(h, runners) }
      assert(h.replay('Bob').state[:hand_number] == 1, "#{label}: a new owner skipped the remaining delay")
      time.call(1067)
      poker_freeze(h, 'Bob', true)
      time.call(1127)
      poker_freeze(h, 'Bob', false)
      # Rebuilding the new owner's executor must not start a fresh five seconds.
      runners['Bob'].close
      runners['Bob'] = runner_for(h, 'Bob')
      runners['Bob'].instance_variable_set(:@clock, ClockEventContract.clock)
      time.call(1128)
      4.times { PrivateCardGamesTest.tick(h, runners) }
      assert(h.replay('Bob').state[:hand_number] == 1 && poker_snapshot(h).events == first_events,
        "#{label}: freeze/reconstruction changed accepted history or shortened the delay")
      time.call(1129)
      16.times { PrivateCardGamesTest.tick(h, runners) }
      h.users.each do |user|
        rep = h.replay(user)
        assert(rep.state[:hand_number] == 2 && rep.state[:phase] == :betting,
          "#{label}: #{user} did not resume at the same logical deadline")
        assert(!rep.state.key?(:hand_resume_at), "#{label}: previous hand delay survived a deal")
        assert(rep.state[:turn_deadline] == 1039, "#{label}: new deal lost thinking time") if thinking_time > 0
      end
      PrivateCardGamesTest.assert_private(h) if private_cards
      assert(poker_snapshot(h).events.count { |event| event['action'] == 'deal' } == 2, "#{label}: duplicate deal")
      assert(poker_snapshot(h).events == poker_snapshot(h, 'Bob').events, "#{label}: clients disagree")
    ensure
      runners.each_value(&:close)
    end
  end
end

# A private showdown completes on its last authenticated reveal, not the bet
# that triggered it. Date that receipt using the pause offset at acceptance.
%w[holdem draw].each do |variant|
  ClockEventContract.with_server_time do |time|
    game = GameRoomGames::Poker.new
    h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob],
      options: {'variant' => variant, 'thinking_time' => 600})
    runners.each_value { |runner| runner.instance_variable_set(:@clock, ClockEventContract.clock) }
    begin
      time.call(1005)
      poker_freeze(h, 'Alice', true)
      time.call(1065)
      poker_freeze(h, 'Alice', false)
      80.times do
        rep = h.replay('Alice')
        break if [:hand_complete, :finished].include?(rep.state[:phase])
        if rep.state[:phase].to_s.start_with?('private_') || game.send(:private_waiting?, rep.state)
          PrivateCardGamesTest.tick(h, runners)
        else
          actor = rep.current_player
          choices = game.legal_actions(h.replay(actor), actor)
          choice = if rep.state[:phase] == :exchange
            choices.find { |item| JSON.parse(item['cards']).empty? }
          else
            choices.find { |item| %w[check call].include?(item['action']) }
          end
          PrivateCardGamesTest.submit(h, runners, actor, choice)
        end
      end
      snapshot = poker_snapshot(h)
      rep = h.replay('Alice')
      assert(rep.state[:phase] == :hand_complete && snapshot.events.last['action'] == 'private_show',
        "#{variant}: fixture did not finish on a private reveal")
      assert(rep.state[:hand_resume_at] == 1010, "#{variant}: final private receipt restarted or omitted the delay")
      before = game.replay(snapshot.session, snapshot.events[0...-1], h.repositories['Alice'])
      cues = GameRoomSounds.event_cue(game: game, event: snapshot.events.last, before_replay: before,
        after_replay: rep, repository: h.repositories['Alice'], viewer: 'Alice')
      assert(Array(cues).count('poker_pot') == 1, "#{variant}: private result omitted or duplicated the pot cue")
      assert(rep.history.count { |entry| entry.key.start_with?('showdown_hand:') } == 2,
        "#{variant}: authenticated showdown did not announce both hands")
    ensure
      runners.each_value(&:close)
    end
  end
end

puts 'PASS native Poker: ordinary/private Holdem/draw, timed/untimed hand pauses, host handover, executor rebuild, freeze before/after result and private showdown receipt'
