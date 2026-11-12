require_relative '../support/tournament_native'
require_relative '../support/tournament_public_service'
require_relative '../../lib/tournaments/public_service'
require_relative '../../lib/tournaments/operations_screen'
include TournamentPublicServiceSupport
include GameRoomTest::Assertions
GameRoomLocalization.boot(settings: {'interface_language' => 'en', 'known_languages' => ['en']})

records = []
sandbox do |context|
  context.actor = 'Organizer'
  build = -> { context.service(journal: context.reopen_journal) }
  values = params('spades', timezone: 'UTC')
  values[:draft] = values[:draft].merge('players_per_match' => 4,
    'game_options' => GameRoomGames::CATALOG.build('spades').normalize_options('team_size' => 2))
  id = build.call.publish(**values).dig('evidence', 'canonical_id')
  %w[Alpha Beta Gamma Delta].each { |name| context.actor = name; build.call.join(tournament_id: id) }
  context.actor = 'Alpha'
  records << build.call.partnership_action(tournament_id: id, action: 'request',
    partner: 'Beta', request_key: nil, intent_id: 'modern-request')
  context.actor = 'Organizer'
  records << build.call.complete_partnerships(tournament_id: id, starting: true)
end
assert_equal(%w[partnership pair_draw], records.map { |record| record.fetch('kind') })
records.each do |record|
  original = Marshal.dump(record)
  driver = TournamentNativeDriver.new
  driver.step('Tournament operations', [13]) do |form|
    title = record['kind'] == 'partnership' ? 'Partner choice: alpha — beta' : "Tournament pair draw: #{record['values']['tournament_id']}"
    assert_equal([title + '; confirmed'], form.fields.first.options)
    assert(form.fields[1].text.include?(record['id']), 'Details lost the actual operation ID')
  end
  driver.step('Tournament operations', [27]) { |form| assert_equal(1, form.index, 'Enter did not open the selected operation details') }
  GameRoomTournaments::OperationsScreen.new(program: Object.new, load: -> { [record] },
    reconcile: ->(*) { raise 'Reading must not reconcile or resend' }, alert: ->(*) {},
    mode_label: 'Isolated local test', actor: record['values']['account']).run
  driver.finish
  assert_equal(original, Marshal.dump(record), 'Opening operations mutated its durable receipt')
end
puts 'PASS native Operations: real current partnership and pair-draw receipts render, Enter opens their exact details, no reconcile, resend or mutation'
