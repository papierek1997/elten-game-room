require_relative '../support/tournament_native'
require_relative '../support/tournament_public_ui'
require_relative '../../lib/tournaments/operations_screen'
include GameRoomTest::Assertions
GameRoomLocalization.boot(settings: {'interface_language' => 'en', 'known_languages' => ['en']})

header = 'Tournament operations'
notice = 'The tournament changed. Refresh its view before changing it again.'
%w[pairing partnership pair_draw].product([false, true, nil]).each do |kind, applied|
  record = TournamentPublicUI.record('attempted')
  record = GameRoomTournaments::Publication::Data.copy(record)
  record['kind'] = kind
  record['values']['account'] = 'Alpha'
  record['values']['partner'] = 'Beta'
  confirmed = GameRoomTournaments::Publication::Data.copy(record)
  confirmed['status'] = 'confirmed'
  confirmed['evidence'] = {'record_ids' => [12]}
  confirmed['evidence']['pairing_applied'] = applied unless applied.nil?
  GameRoomTournaments::Publication::Data.freeze_tree(confirmed)
  alerts, calls, reads = [], [], 0
  driver = TournamentNativeDriver.new
  driver.step(header) do |form|
    TournamentPublicUI.button(form, 'Check selected operation').press
    assert(form.fields.first.options.first.end_with?('; confirmed'), 'The durable write must remain confirmed')
    assert_equal(applied == false, form.fields[1].text.include?(notice), 'Details must distinguish a stale pair from a stored request')
    assert_equal(applied == false, alerts.last.include?(notice), 'Readback must announce the ignored partner selection')
  end
  driver.step(header, [27])
  GameRoomTournaments::OperationsScreen.new(program: Object.new,
    load: -> { reads += 1; reads == 1 ? [record] : [confirmed] },
    reconcile: ->(id) { calls << id; confirmed }, alert: ->(message) { alerts << message },
    mode_label: TournamentPublicUI::MODE, actor: TournamentPublicUI::ACTOR).run
  driver.finish
  assert_equal([record['id']], calls)
  assert_equal(2, reads)
  assert_equal('confirmed', confirmed['status'])
end
puts 'PASS operation readback: stale pairing has an explanation without changing the confirmed storage status or resubmitting'
