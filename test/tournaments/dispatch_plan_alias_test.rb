require_relative '../support/tournament_dispatch'
include TournamentDispatchSupport

with_fixture(game: 'tic_tac_toe', names: %w[Alpha Beta], rematch: false) do |fixture|
  backend = fixture.backend
  record = backend.accept(preview: backend.preview(publication_ref: fixture.reference,
    base_seats: fixture.base, intent_id: 'canonical-dispatch'))
  alias_id = 'second-accepted-dispatch'
  aliased = backend.accept(preview: backend.preview(publication_ref: fixture.reference,
    base_seats: fixture.base, intent_id: alias_id))
  assert_equal(record, aliased)
  canonical = record['preview']['intent_id']
  fixture.now = record['evidence']['plan']['matches'].first['windows'].first['opens'] + 1
  with_dispatch(fixture, record, 'Organizator') do |dispatcher|
    assert_equal(1, dispatcher.configure(intent_id: alias_id, max_tables: 1, consent_before_table: true))
  end
  with_dispatch(fixture, record, 'Alpha') do |dispatcher|
    row = dispatcher.available(intent_id: alias_id, available: true)
    fixture.now += T::LocalDispatchContract::TTL / 2
    assert(dispatcher.availability_refresh_due?(intent_id: alias_id), 'Alias lost its own heartbeat')
    refreshed = dispatcher.refresh_availability(intent_id: alias_id)
    assert_equal(:confirmed, refreshed[:state])
    assert(refreshed[:effect]['expires_at'] > row['expires_at'], 'Own lease did not renew')
    assert_equal(canonical, dispatcher.snapshot(intent_id: alias_id)['intent_id'])
  end
  with_dispatch(fixture, record, 'Beta') { |dispatcher| dispatcher.available(intent_id: canonical, available: true) }
  2.times do
    %w[Alpha Beta].each { |actor| with_dispatch(fixture, record, actor) { |dispatcher| dispatcher.advance(intent_id: alias_id) } }
  end
  assert_equal(0, dispatch_state(fixture)['native']['creates'].size, 'A proposal fabricated consent')
  %w[Alpha Beta].each do |actor|
    with_dispatch(fixture, record, actor) do |dispatcher|
      token = dispatcher.snapshot(intent_id: alias_id).fetch('proposal').fetch('token')
      result = dispatcher.accept(intent_id: alias_id, expected_proposal: token, require_expected: true)
      assert([:awaiting_consent, :confirmed].include?(result[:state]), 'Alias could not accept its canonical proposal')
    end
  end
  2.times do
    %w[Alpha Beta].each { |actor| with_dispatch(fixture, record, actor) { |dispatcher| dispatcher.advance(intent_id: alias_id) } }
  end
  %w[Alpha Beta].each do |actor|
    with_dispatch(fixture, record, actor) { |dispatcher| assert_equal(:confirmed, dispatcher.accept(intent_id: alias_id)[:state]) }
  end
  %w[Alpha Beta].each { |actor| with_dispatch(fixture, record, actor) { |dispatcher| dispatcher.advance(intent_id: alias_id) } }
  state = dispatch_state(fixture)
  assert_equal([canonical], state['dispatch']['policies'].keys)
  assert_equal([canonical], state['dispatch']['availability'].keys)
  assert_equal(1, state['native']['creates'].size)
  assert_equal(1, state['executions'].values.count { |execution| execution['start'] })
  assert_equal([canonical], state['executions'].values.map { |execution| execution['record_intent'] }.uniq)
end
puts 'PASS canonical dispatch aliases: configuration, own renewal, snapshot, reservation, invitations, admission and one Start'
