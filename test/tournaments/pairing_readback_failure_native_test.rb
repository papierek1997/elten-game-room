require_relative '../support/tournament_native'
require_relative '../support/tournament_public_ui'
require_relative '../../lib/tournaments/operations_screen'
include GameRoomTest::Assertions
GameRoomLocalization.boot(settings: {'interface_language' => 'en', 'known_languages' => ['en']})

T = GameRoomTournaments
notice = 'The tournament changed. Refresh its view before changing it again.'
record = T::Publication::Data.copy(TournamentPublicUI.record('attempted'))
record['kind'] = 'pairing'
record['values'].merge!('account' => 'Alpha', 'partner' => 'Beta')
confirmed = T::Publication::Data.copy(record)
confirmed.merge!('status' => 'confirmed', 'evidence' => {'pairing_applied' => false})
T::Publication::Data.freeze_tree(confirmed)
reads, reconciles, alerts = 0, [], []
driver = TournamentNativeDriver.new
driver.step('Tournament operations') do |form|
  TournamentPublicUI.button(form, 'Check selected operation').press
  assert(form.fields.first.options.first.end_with?('; confirmed'), 'Durable result stays confirmed')
  assert(form.fields[1].text.include?(notice), 'Successful readback must survive a failed following refresh')
  assert_equal(1, alerts.size)
  assert(alerts.first.include?(notice), 'The readback announces the discarded choice')
  TournamentPublicUI.button(form, 'Refresh').press
  assert(form.fields[1].text.include?(notice), 'A repeated failed refresh retains the reason')
  assert_equal(1, reconciles.size, 'Refresh cannot resubmit or reconcile implicitly')
end
driver.step('Tournament operations', [27])
T::OperationsScreen.new(program: Object.new,
  load: -> { reads += 1; reads == 1 ? [record] : nil },
  reconcile: ->(id) { reconciles << id; confirmed }, alert: ->(value) { alerts << value },
  mode_label: TournamentPublicUI::MODE, actor: TournamentPublicUI::ACTOR).run
driver.finish
assert_equal(3, reads)
assert_equal([record['id']], reconciles)
assert_equal('attempted', record['status'], 'The incoming immutable snapshot was not patched in place')
puts 'PASS native pairing readback: stale outcome survives failed refresh, no implicit write or repeated confirmation'
