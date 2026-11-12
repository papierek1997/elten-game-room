require_relative '../../support/mahjong_private_pools'

def write_private_audit_event(harness, actor, commands)
  harness.instance_variable_set(:@session, harness.repositories.fetch(actor).snapshot_for(harness.session).session)
  harness.write(actor, commands)
  harness.broker.deliver(duplicate: true)
  harness.events(actor).last
end

def cold_private_audit(harness, user)
  repository = harness.repositories.fetch(user)
  snapshot = harness.as(user) { repository.snapshot_for(harness.session, read_only: true) }
  [GameRoomGames::Mahjong.new.replay(snapshot.session, snapshot.events, repository), snapshot, repository]
end

outcomes = []
%w[hong_kong riichi mcr].each do |variant|
  ready = [124,125,126,128,129,130,132,133,134,108,109,110,112]
  game, harness, runners = MahjongPrivateTest.create(variant, hands: {'Alice'=>ready}, extra: 113, winds: 1)
  rejected_ids = []
  begin
    original = harness.replay('Alice')
    alice_card = original.state.fetch(:hands).fetch('Alice').first
    alice_receipt = GameRoomPrivateCardLedger.locate(original.state, 'Alice', alice_card)
    bob_view = harness.replay('Bob')
    bob_card = bob_view.state.fetch(:hands).fetch('Bob').first
    bob_receipt = GameRoomPrivateCardLedger.locate(bob_view.state, 'Bob', bob_card)
    wrong_turn = {seat: 1, generation: original.state[:round].flow.generation, type: :discard, tile: bob_card}
    encoded = GameRoomMahjong::PrivateEvents.encode(wrong_turn, hand: original.state[:hand_number], cards: [bob_card])
    wrong_turn_event = write_private_audit_event(harness, 'Bob', [GameRoomPrivateCards.command('mahjong_move', encoded,
      operation: 'reveal', **bob_receipt)])
    rejected_ids << wrong_turn_event.fetch('__id')
    harness.users.each do |user|
      after, = cold_private_audit(harness, user)
      assert(after.accepted_events == original.accepted_events, "#{variant}: wrong-turn proof accepted a move")
      assert(GameRoomPrivateCardLedger.known?(after.state, bob_receipt), 'Authentic rejected observation disappeared')
      assert(!after.state[:private_public].include?(bob_card), 'Wrong-turn proof consumed a tile')
    end

    win = game.legal_actions(harness.replay('Alice'), 'Alice').find { |action| action['action'] == 'win' }
    assert(win, 'Legal winning fixture lost its action')
    PrivateCardGamesTest.submit(harness, runners, 'Alice', win)
    pending = harness.replay('Alice')
    assert(pending.state[:phase] == :private_show, 'Fixture must pause before the winning hand disclosure')
    purpose = pending.state.fetch(:private_disclosure).fetch(:purpose)
    claim_value = JSON.generate([purpose, alice_receipt.fetch(:draw_id), [alice_receipt.fetch(:value)]])
    premature = write_private_audit_event(harness, 'Alice', [GameRoomPrivateCards.command('private_show', claim_value, operation: 'claim')])
    rejected_ids << premature.fetch('__id')

    # Put a forged server proof inside a participant-controlled packet. The
    # native envelope remains an ordinary participant stack message.
    repository = harness.repositories.fetch('Alice')
    snapshot = repository.snapshot_for(harness.session)
    proof = {'operation'=>'reveal', 'pool_id'=>alice_receipt[:pool_id],
      'draw_id'=>alice_receipt[:draw_id], 'values'=>[alice_receipt[:value]]}
    fake_id = SecureRandom.uuid
    forged = GameRoomEventProtocol.game_action_packet(session_id: snapshot.session.fetch('__id'),
      sequence: repository.next_sequence(snapshot.session, snapshot.events),
      control_epoch: snapshot.session.fetch('__control_epoch'), actor: 'Alice',
      events: [{'action'=>'private_show', 'value'=>purpose, 'move_id'=>fake_id, '__server_pool'=>proof}])
    harness.view('Alice').stack_push(forged, message_id: fake_id)
    harness.broker.deliver(duplicate: true)
    fake_event = harness.events('Alice').find { |event| event['move_id'] == fake_id }
    assert(fake_event && !fake_event.key?('__server_pool'), 'Participant packet became native proof, or fixture was not projected')
    rejected_ids << fake_event.fetch('__id')

    foreign = write_private_audit_event(harness, 'Bob', [GameRoomPrivateCards.command('private_show', claim_value, operation: 'claim')])
    rejected_ids << foreign.fetch('__id')
    harness.users.each do |user|
      before_reveal, = cold_private_audit(harness, user)
      assert((before_reveal.accepted_events.map { |event| event['__id'] } & rejected_ids).empty?, 'Early/foreign/forged claim accepted')
      assert(!GameRoomPrivateCardLedger.known?(before_reveal.state, alice_receipt), 'Unrevealed Alice proof was seeded from future/private values')
      assert(!before_reveal.state[:private_public].include?(alice_card), 'Claim without public proof consumed a tile')
    end

    observed = write_private_audit_event(harness, 'Alice', [GameRoomPrivateCards.command('private_show', 'wrong-purpose',
      operation: 'reveal', **alice_receipt)])
    rejected_ids << observed.fetch('__id')
    harness.users.each do |user|
      after_reveal, = cold_private_audit(harness, user)
      assert(GameRoomPrivateCardLedger.known?(after_reveal.state, alice_receipt), 'Actual later reveal was lost')
      assert((after_reveal.accepted_events.map { |event| event['__id'] } & rejected_ids).empty?, 'Later reveal retroactively authorized an earlier claim/move')
    end

    # Repeat foreign use after the proof is genuinely known, so this checks
    # account binding rather than merely absence of the earlier observation.
    foreign_known = write_private_audit_event(harness, 'Bob', [GameRoomPrivateCards.command('private_show', claim_value, operation: 'claim')])
    rejected_ids << foreign_known.fetch('__id')
    other_card = harness.replay('Alice').state.fetch(:hands).fetch('Alice').find { |card| card != alice_card }
    other_receipt = GameRoomPrivateCardLedger.locate(harness.replay('Alice').state, 'Alice', other_card)
    assert(other_receipt[:draw_id] == alice_receipt[:draw_id], 'Unknown-value fixture is not from the same real draw')
    fabricated_value = JSON.generate([purpose, alice_receipt[:draw_id], [other_receipt[:value]]])
    fabricated = write_private_audit_event(harness, 'Alice', [GameRoomPrivateCards.command('private_show', fabricated_value, operation: 'claim')])
    rejected_ids << fabricated.fetch('__id')
    harness.users.each do |user|
      bounded, = cold_private_audit(harness, user)
      assert((bounded.accepted_events.map { |event| event['__id'] } & rejected_ids).empty?, 'Foreign known proof or unrevealed value became authorization')
      assert(!bounded.state[:private_public].include?(alice_card), 'Foreign known claim consumed Alice tile')
      assert(!GameRoomPrivateCardLedger.known?(bounded.state, other_receipt), 'Unrevealed value was fabricated from a real draw ID')
    end

    repeated = write_private_audit_event(harness, 'Alice', [GameRoomPrivateCards.command('private_show', claim_value, operation: 'claim')])
    harness.users.each do |user|
      after_claim, = cold_private_audit(harness, user)
      assert(after_claim.accepted_events.any? { |event| event['__id'] == repeated['__id'] }, 'Known claim after chronological proof was refused')
      assert(after_claim.state[:private_public].include?(alice_card), 'Legal known claim did not expose its own tile')
    end
    30.times do
      PrivateCardGamesTest.tick(harness, runners)
      break if harness.users.all? { |user| item = harness.replay(user); item.state[:phase] == :between_hands || item.state[:private_error] }
    end
    scores = harness.users.map do |user|
      final, snapshot, repository = cold_private_audit(harness, user)
      assert(final.state[:phase] == :between_hands && !final.state[:private_error],
        "#{variant}/#{user}: chronological negative-case settlement failed #{final.state[:phase]}/#{final.state[:private_error]}")
      assert((final.accepted_events.map { |event| event['__id'] } & rejected_ids).empty?, 'Strict audit accepted a rejected action')
      assert(final.state[:private_audit_sources].map { |event| event['__id'] }.include?(wrong_turn_event['__id']),
        'Audit did not retain the authentic wrong-turn observation')
      assert(final.state[:private_audit_sources].map { |event| event['__id'] }.include?(observed['__id']),
        'Audit did not retain the authentic wrong-purpose observation')

      # Same number of expected accepted rows is insufficient: exact row/order
      # comparison must reject a corrupt expected tape, not commit its result.
      auditor = GameRoomGames::Mahjong::Table.new
      altered = auditor.send(:private_table_copy, final.state)
      altered[:private_audit_events] = altered.fetch(:private_audit_events).reverse
      auditor.send(:private_table_audit, altered, snapshot.session, repository, [])
      assert(altered[:private_error] == :invalid_round, 'Equal-size different accepted tape passed the strict audit')
      assert(!final.state[:private_error], 'Probe mutated the original replay')
      game.participant_scores(final)
    end
    assert(scores.uniq.one?, 'Account scores diverged after bounded negative probes')
    outcomes << {variant: variant, views: harness.users.size, result: 'PASS',
      checks: ['wrong turn stays rejected', 'future proof is not seeded', 'premature claim stays rejected after later reveal',
        'client-forged proof sanitized', 'foreign known claim rejected after real revelation',
        'unrevealed value under a genuine draw ID rejected', 'later own known claim accepted',
        'cold scoring audit completes', 'equal-size wrong accepted tape rejected'], scores: scores.first}
  ensure
    runners.each_value(&:close)
  end
end
puts JSON.pretty_generate(status: 'PASS Mahjong chronological-proof authority boundaries', outcomes: outcomes)
