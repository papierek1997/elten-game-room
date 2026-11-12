require_relative '../support/tournament_forfeit_native'
T=GameRoomTournaments

%i[build_forfeit_preview map_forfeit_checkpoint session_for_forfeit].each do |name|
  assert(!T::OrdinaryMatchService.method_defined?(name) && !T::OrdinaryMatchService.private_method_defined?(name),
    "Historical fixture generator #{name} leaked into the production service")
end

%w[ordinary-match-forfeit-v1 ordinary-match-cancel-forfeit-v1].each do |kind|
  TournamentForfeitNative.with_fixture do |f|
    f.start if kind.include?('cancel')
    service=f.services['Alice']
    preview=f.h.as('Alice') {service.send(:build_forfeit_preview,f.candidate,5,f.match,'alice')}
    doc=preview.slice('schedule_id','match_id','leg','publication_ref','cancelled_game').merge(
      'kind'=>kind,'summary'=>{'participants'=>%w[alice bob],'winners'=>['bob'],'draw'=>false,'scores'=>nil,'event_count'=>0})
    anchor=service.send(:anchor,f.candidate,5,f.match,'forfeit')
    journal=service.instance_variable_get(:@journal)
    pending=journal.prepare(kind:'plan_document',intent_id:'old-'+kind,
      values:anchor.merge('kind'=>'plan_document','document_json'=>JSON.generate(doc)))
    count=f.documents.insert_count
    error=assert_raises(T::OrdinaryMatchService::Blocked) {service.reconcile(pending['id'])}
    assert_equal(:legacy_forfeit_write_disabled,error.code)
    assert_equal(count,f.documents.insert_count,'Retained v1 operation published new data')
    f.documents.on_select=-> {raise 'Legacy direct write read server state before denying'}
    error=assert_raises(T::OrdinaryMatchService::Blocked) do
      service.award_forfeit(match_id:f.match['match_id'],leg:1,winner:'bob',
        expected_schedule_id:f.candidate['schedule_id'],cancel_started:kind.include?('cancel'))
    end
    assert_equal(:legacy_forfeit_write_disabled,error.code)
    f.documents.on_select=nil
    assert_equal(count,f.documents.insert_count,'Old callback published a new decision')
    # Historical accepted records, inserted as source fixtures rather than via
    # the now-disabled production writer, must still project their old result.
    T::ServerPlanDocument.encode(doc,anchor:anchor).each { |row| f.documents.insert(row) }
    view=f.services['Bob'].result_view
    assert_equal(doc,view['results'].first)
    assert_equal({'alice'=>0,'bob'=>2},view['standings'].to_h { |row| [row['unit'],row['points']] })
    count=f.documents.insert_count
    assert_raises(T::OrdinaryMatchService::Blocked) {service.reconcile(pending['id'])}
    assert_equal(count,f.documents.insert_count,'Reading accepted v1 history rewrote the document')
  end
end
puts 'PASS legacy forfeit is read-only: new calls and retained journal cannot write, both historical v1 kinds keep original results'
