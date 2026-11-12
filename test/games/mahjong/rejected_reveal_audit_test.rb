require_relative '../../support/mahjong_private_pools'

# A real native-pool observation is irreversible even when its associated
# rule action is refused. It must not become an accepted move or be lost
# when the now-public hand is reconstructed for the strict scoring audit.
def settled_hand_after_rejected_reveal(variant, disclose:)
  ready = [124,125,126,128,129,130,132,133,134,108,109,110,112]
  game, harness, runners = MahjongPrivateTest.create(variant, hands: {'Alice'=>ready}, extra: 113, winds: 1)
  rejected = []
  begin
    if disclose
      2.times do |index|
        before = harness.replay('Alice')
        card = before.state[:hands].fetch('Alice')[index]
        receipt = GameRoomPrivateCardLedger.locate(before.state, 'Alice', card)
        repository = harness.repositories.fetch('Alice')
        harness.instance_variable_set(:@session, repository.snapshot_for(harness.session).session)
        harness.write('Alice', [GameRoomPrivateCards.command('private_show', 'not-a-legal-scoring-action',
          operation: 'reveal', **receipt)])
        harness.broker.deliver(duplicate: true)
        event = harness.events('Alice').last
        rejected << repository.event_id(event)
        assert(event.dig('__server_pool', 'operation') == 'reveal' && event.dig('__server_pool', 'draw_id') == receipt[:draw_id],
          'Fixture did not create a native authenticated reveal')
        harness.users.each do |user|
          after = harness.replay(user)
          assert(after.accepted_events.none? { |row| repository.event_id(row) == rejected.last }, 'Rejected reveal became a rule move')
          assert(GameRoomPrivateCardLedger.known?(after.state, receipt), 'Native observation was undone with its rejected move')
          assert(after.state[:private_draws].fetch(receipt[:draw_id])[:used].empty?, 'Rejected reveal consumed a card')
          assert(!after.state[:private_public].include?(card), 'Rejected observation changed legal hand positions/public use')
          next if user == 'Alice'
          assert(after.state[:hands].fetch('Alice').all? { |item| GameRoomPrivateCardLedger.hidden?(item) },
            'A rejected observation copied another account\'s hand into the ordinary view')
        end
        assert(before.accepted_events == harness.replay('Alice').accepted_events, 'A refused rule action changed the accepted log')
      end
    end

    selection = game.legal_actions(harness.replay('Alice'), 'Alice').find { |action| action['action'] == 'win' }
    assert(selection, "#{variant}: unchanged legal win disappeared")
    PrivateCardGamesTest.submit(harness, runners, 'Alice', selection)
    30.times do
      PrivateCardGamesTest.tick(harness, runners)
      break if harness.users.all? do |user|
        replay = harness.replay(user)
        replay.state[:phase] == :between_hands || replay.state[:private_error]
      end
    end
    results = harness.users.map do |user|
      repository = harness.repositories.fetch(user)
      snapshot = harness.as(user) { repository.snapshot_for(harness.session, read_only: true) }
      # Reconstruct the entire authenticated history in a fresh game instance;
      # no warm cache or test override can supply the missing earlier proof.
      cold = GameRoomGames::Mahjong.new.replay(snapshot.session, snapshot.events, repository)
      assert(cold.state[:phase] == :between_hands && !cold.state[:private_error],
        "#{variant}/#{user}: legal hand failed after observations=#{disclose}: #{cold.state[:phase]}/#{cold.state[:private_error]}")
      assert(cold.accepted_events.none? { |row| rejected.include?(repository.event_id(row)) }, 'Scoring audit accepted the rejected move')
      game.participant_scores(cold)
    end
    assert(results.uniq.one?, "#{variant}: four account scoring views diverged")
    results.first
  ensure
    runners&.each_value(&:close)
  end
end

%w[hong_kong riichi mcr].each do |variant|
  ordinary = settled_hand_after_rejected_reveal(variant, disclose: false)
  observed = settled_hand_after_rejected_reveal(variant, disclose: true)
  assert(ordinary == observed, "#{variant}: rejected observations changed the score")
  puts "PASS Mahjong #{variant}: native rejected observations, exact accepted log, private views, cold audit and unchanged scores"
end
