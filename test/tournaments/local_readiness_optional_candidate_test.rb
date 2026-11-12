require_relative '../support/tournament_local_readiness'
include TournamentLocalReadinessSupport
include GameRoomTest::Assertions

%i[optional daily wins].each do |variant|
  sandbox do |context|
    author = context.workspace('Organizator')
    settings = draft('chess').merge('starts_at' => 0, 'deadline_at' => 0, 'windows' => [])
    if variant == :daily
      settings['daily_hours'] = {'start' => '10:00', 'end' => '11:00', 'utc_offset_minutes' => 60}
    elsif variant == :wins
      settings.merge!('format' => 'groups_knockout', 'group_advancement' => 'automatic_cross_groups_v1',
        'group_count' => nil, 'places_per_group' => nil, 'knockout_rematch' => false,
        'final_rematch' => false, 'knockout_wins_to' => 2, 'final_wins_to' => 3)
    end
    result = author.publish(**local_params(draft: settings, intent_id: "optional-#{variant}"))
    assert_equal('confirmed', result.fetch('status'))
    row = author.load.fetch('announcements').first
    %w[Alicja Bob Celina].each do |name|
      assert_equal('confirmed', context.workspace(name).join(row['__id']).fetch('status'))
    end
    context.now = row.fetch('registration_closes_at') + 1
    reference = row.slice('publication_key').merge('author' => row.fetch('__insertion_user'))
    source = ->(ref) { author.schedule_candidate(publication_ref: ref) }
    candidate = source.call(reference)
    assert_equal(0, candidate.to_h.fetch('starts_at'))
    backend = T::LocalReadinessBackend.new(directory: File.join(context.directory, 'k03'),
      actor: 'Alicja', clock: -> { context.now }, source: source)
    anchor = backend.accept(candidate: candidate)
    assert_equal(candidate.to_h, anchor.fetch('candidate'))
    assert_equal([anchor], backend.plans)
    match = candidate.to_h.fetch('matches').find { |item| item.fetch('players').include?('alicja') }
    target = backend.target(plan_id: anchor.fetch('plan_id'), match_id: match.fetch('match_id'))
    gate = backend.gate_state(**target)
    assert_equal(false, gate.fetch('open'), 'Optional metadata opened a local start gate')
    assert_equal([], gate.fetch('grants'))
    path = backend.instance_variable_get(:@storage).path
    original = File.binread(path)
    assert_equal(anchor, backend.accept(candidate: candidate))
    assert_equal(original, File.binread(path), 'Idempotent acceptance rewrote optional metadata')

    changes = [['starts_at', -1], ['starts_at', '0']]
    changes << ['daily_hours', {'start' => '25:00', 'end' => '11:00', 'utc_offset_minutes' => 60}] if variant == :daily
    changes << ['final_wins_to', 0] if variant == :wins
    begin
      changes.each do |key, value|
        document = JSON.parse(original)
        stored = document.fetch('plans').first
        stored.fetch('candidate')[key] = value
        stored['source_digest'] = Digest::SHA256.hexdigest(JSON.generate(stored['candidate'].reject { |name, _| name == 'observed_at' }))
        bytes = JSON.generate(document)
        File.binwrite(path, bytes)
        error = assert_raises(T::ReadinessContract::Blocked) { backend.plans }
        assert_equal(:sandbox_corrupt, error.code)
        assert_equal(bytes.b, File.binread(path), 'Rejected optional metadata was rewritten')
      end
    ensure
      File.binwrite(path, original)
    end
    assert_equal([anchor], backend.plans)
  end
end
puts 'PASS full current local candidates: optional/daily/win-target metadata retained, closed gate, strict typed cold validation, no idempotent rewrites'
