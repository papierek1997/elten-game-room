require_relative '../support/private_card_games'
require_relative '../../games/domino'
require_relative '../../games/mexican_train'

def tile_receipt_fixture(klass)
  harness, runners = PrivateCardGamesTest.create(klass.new, users: %w[Alice Bob Carol],
    random_values: Array.new(16, 8))
  20.times do
    replay = harness.replay('Alice')
    assert(!replay.finished?, 'Tile receipt fixture unexpectedly finished')
    actor = replay.current_player
    if actor
      own = harness.replay(actor)
      choices = harness.game.legal_actions(own, actor)
      choice = choices.find { |action| action['action'] == 'play' }
      return [harness, runners, actor, choice] if choice
      PrivateCardGamesTest.submit(harness, runners, actor, choices.first) if choices.any?
    end
    PrivateCardGamesTest.tick(harness, runners)
  end
  raise 'No legal tile play within fixture setup bound'
rescue Exception
  runners&.each_value(&:close)
  raise
end

def tile_receipt_plan(harness, actor, selection)
  snapshot = harness.repositories.fetch(actor).snapshot_for(harness.session)
  replay = harness.game.replay(snapshot.session, snapshot.events, harness.repositories.fetch(actor))
  context = GameRoomGames::ActionContext.new(session_id: snapshot.session['__id'],
    table_id: harness.table['__id'], table_owner: snapshot.session['__table_owner'],
    now: replay.state.fetch(:turn_started), server_random: true)
  status, plan = harness.game.action_for(selection, replay, actor, context: context)
  assert(status == :ok && plan, 'A legal tile action did not prepare through action_for')
  [replay, plan]
end

[GameRoomGames::Domino, GameRoomGames::MexicanTrain].each do |klass|
  control_runners = runners = nil
  begin
    control, control_runners, actor, selection = tile_receipt_fixture(klass)
    before, plan = tile_receipt_plan(control, actor, selection)
    assert(plan.events.one? && plan.events.first.pool_request['operation'] == 'reveal',
      'Legal tile control must use its actual native draw receipt')
    control.write(actor, plan.events)
    after = control.replay(actor)
    assert(after.accepted_events.size == before.accepted_events.size + 1 &&
      !after.state[:hands].fetch(actor).include?(selection.fetch('tile')), 'Legal control did not play its tile')

    harness, runners, actor, selection = tile_receipt_fixture(klass)
    before, plan = tile_receipt_plan(harness, actor, selection)
    card = selection.fetch('tile')
    receipt = GameRoomPrivateCardLedger.locate(before.state, actor, card)
    assert(receipt, 'Owned tile has no real native receipt')
    claim = GameRoomPrivateCards.command('private_show',
      JSON.generate(['action', receipt.fetch(:draw_id), [receipt.fetch(:value)]]), operation: 'claim')
    harness.write(actor, [claim])
    assert(harness.replay(actor).accepted_events == before.accepted_events &&
      harness.users.none? { |user| GameRoomPrivateCardLedger.known?(harness.replay(user).state, receipt) },
      'An unproved ordinary claim manufactured public reveal evidence')

    command = plan.events.fetch(0)
    data = harness.game.send(:decode, command.value)
    data['target'] = 'x'
    refused = GameRoomPrivateCards.command(command.action, harness.game.send(:encode, data),
      **command.pool_request.transform_keys(&:to_sym))
    count = harness.events(actor).size
    harness.write(actor, [refused])
    raw = harness.events(actor)
    assert(raw.size == count + 1 && raw.last['__server_pool'], 'Refused play did not really reveal through the native contract')
    rejected_id = harness.repositories.fetch(actor).event_id(raw.last)
    after = harness.replay(actor)
    assert(after.accepted_events == before.accepted_events && after.history.map(&:to_h) == before.history.map(&:to_h) &&
      after.state[:hands].fetch(actor) == before.state[:hands].fetch(actor), 'Rejected reveal consumed a rule move, history or tile')
    assert(!after.state[:private_public].include?(card), 'Public knowledge was confused with accepted card use')
    assert(harness.users.all? { |user| GameRoomPrivateCardLedger.known?(harness.replay(user).state, receipt) },
      "#{harness.game.id}: transactional rollback lost authentic irreversible reveal evidence")

    # The observer gate still requires the original account and native pool.
    other = (harness.users - [actor]).first
    [raw.last.merge('__server_pool' => raw.last.fetch('__server_pool').merge('pool_id' => 'f' * 32)),
      raw.last].each_with_index do |event, index|
      isolated = GameRoomSnapshot.copy(before.state)
      GameRoomPrivateCardLedger.observe_reveal(isolated, event, index.zero? ? actor : other)
      assert(!GameRoomPrivateCardLedger.known?(isolated, receipt), 'A foreign account or pool authorized reveal knowledge')
    end

    harness.users.each do |user|
      repository = harness.repositories.fetch(user)
      snapshot = repository.snapshot_for(harness.session)
      cold = klass.new.replay(snapshot.session, snapshot.events, repository)
      assert(GameRoomPrivateCardLedger.known?(cold.state, receipt) &&
        cold.accepted_events == before.accepted_events && cold.history.map(&:to_h) == before.history.map(&:to_h),
        'Cold account replay lost the proof or accepted the refused move')
    end
    PrivateCardGamesTest.assert_private(harness)

    current, retry_plan = tile_receipt_plan(harness, actor, selection)
    assert(retry_plan.events.fetch(0).pool_request == {'operation' => 'claim'},
      'A later legal tile play attempted to reveal the already public receipt again')
    calls = harness.users.to_h { |user| [user, harness.view(user).calls[:reveal]] }
    plays = current.history.count { |entry| entry.kind == :play }
    harness.write(actor, retry_plan.events)
    16.times { PrivateCardGamesTest.tick(harness, runners) }
    final = harness.replay(actor)
    assert(!final.state[:hands].fetch(actor).include?(card) && final.history.count { |entry| entry.kind == :play } == plays + 1,
      'The ordinary known-proof continuation failed to apply exactly one legal tile play')
    assert(final.accepted_events.none? { |event| harness.repositories.fetch(actor).event_id(event) == rejected_id },
      'Retry retroactively accepted the refused native event')
    assert(harness.users.all? { |user| harness.view(user).calls[:reveal] == calls.fetch(user) },
      'The tile retry made another native reveal request')
    PrivateCardGamesTest.assert_private(harness)
  ensure
    control_runners&.each_value(&:close)
    runners&.each_value(&:close)
  end
end

puts 'PASS Domino/Mexican Train refused native reveals: legal control, rule rollback, account/pool guards, cold projections and claim-only retry'
