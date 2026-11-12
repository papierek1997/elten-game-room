# encoding: UTF-8
# Historical read-only receipt construction belongs to explicit test fixtures,
# never the production service. Preserve the original generator unchanged.
module GameRoomTournaments
  module LegacyForfeitFixture
    Data = Publication::Data
    private

    def build_forfeit_preview(candidate,id,match,loser)
      units=(match['unit_ids'] || match['players']).sort
      raise OrdinaryMatchService::Blocked,:invalid_forfeit_loser unless units.include?(loser)
      binding=read_match_binding(candidate,id,match,nil)
      raise OrdinaryMatchService::Blocked,:wrong_match_binding if binding && !valid_binding?(binding,candidate,match)
      boundary=nil
      checkpoint={'status'=>'unsupported'}
      continuation={'status'=>'unsupported'}
      eliminations=[]
      if binding
        raise OrdinaryMatchService::Blocked,:game_state_unavailable unless @transport
        sessions=forfeit_native_sessions(candidate,id,match,binding)
        unless sessions.empty?
          raise OrdinaryMatchService::Blocked,:wrong_bound_session unless sessions.first['__id']==binding['session_id']
          boundary,game,replay,session=session_for_forfeit(binding)
          checkpoint=game.tournament_scored_checkpoint(replay,options:binding['options'])
          if checkpoint.is_a?(Hash) && checkpoint['status']=='scored'
            checkpoint=map_forfeit_checkpoint(checkpoint,game,replay,binding,candidate,match)
          end
          mapping=GameResult.roster_mapping(game:game,replay:replay,options:binding['options'],players:binding['players'])
          continuation=game.tournament_forfeit_continuation(replay,losing_unit:mapping.key(loser),options:binding['options'])
          eliminations=GameResult.eliminations(replay,players:binding['players'])
        end
      end
      outcome=InterruptedOutcome.build(units:units,loser:loser,started:!boundary.nil?,
        checkpoint:checkpoint,continuation:continuation,event_count:boundary ? boundary['event_count'] : 0,
        eliminations:eliminations)
      document={'kind'=>'ordinary-match-forfeit-v2','schedule_id'=>candidate['schedule_id'],
        'match_id'=>match['match_id'],'leg'=>match['leg'],'publication_ref'=>candidate.fetch('publication_ref'),
        'organizer'=>@owner,**outcome}
      document['cancelled_game']=boundary if boundary
      if outcome.dig('decision','mode')=='continue'
        document['kind']='ordinary-match-elimination-v1'
        document['continued_game']=document.delete('cancelled_game')
        room=@transport.room_snapshot(binding['table'],read_only:true)
        raise OrdinaryMatchService::Blocked,:game_state_unavailable unless room && room[:members]
        active=game.tournament_active_players(replay,options:binding['options'])
        absent=active.reject { |player| GameRoomParticipants.includes?(room[:members],player) }
        document['native_boundary']=GameRoomTournamentPresence.data(session:session,
          fixture:binding['table'].fetch('tournament_match'),binding_digest:boundary['binding_digest'],
          absent:absent,elapsed_ms:0,loser:mapping.key(loser),mode:'continue',origin:'organizer')
      end
      Data.freeze_tree(Data.copy(document))
    rescue Publication::Invalid=>error
      raise unless [:tournament_continuation_unsupported,:tournament_checkpoint_unsupported].include?(error.code)
      raise OrdinaryMatchService::Blocked,error.code
    end

    def map_forfeit_checkpoint(checkpoint,game,replay,binding,candidate,match)
      assignment=game.prepared_team_assignment(game.normalize_options(binding['options']),players:replay.players)
      units=assignment ? assignment.team_ids.to_h { |unit| [unit,assignment.members_for(unit)] } :
        replay.players.to_h { |player| [player,[player]] }
      mapping=GameResult.unit_mapping(units:units,players:prepared_match(candidate,match)['players'])
      scores=checkpoint['scores']
      unless scores.is_a?(Hash) && scores.keys.sort==mapping.keys.sort
        raise OrdinaryMatchService::Blocked,:invalid_forfeit_checkpoint
      end
      checkpoint.merge('scores'=>scores.to_h { |unit,score| [mapping.fetch(unit),score] })
    rescue Publication::Invalid
      raise OrdinaryMatchService::Blocked,:invalid_forfeit_checkpoint
    end

    def session_for_forfeit(binding)
      raise OrdinaryMatchService::Blocked,:game_state_unavailable unless @games
      session=@games.session_by_id(binding['session_id'],table:binding['table'])
      snapshot=session && @games.snapshot_for(session,force_events:true)
      raise OrdinaryMatchService::Blocked,:game_state_unavailable unless snapshot
      session=snapshot.session
      raise OrdinaryMatchService::Blocked,:wrong_bound_session unless session['__id']==binding['session_id'] &&
        session['table_id']==binding['table']['__id'] && session['game']==binding['game_id'] &&
        OrdinaryMatchResults.valid_continuation?(binding,session,snapshot.events)
      game=@registry.build(binding['game_id'])
      replay=game.replay(session,snapshot.events,@games)
      raise OrdinaryMatchService::Blocked,:game_state_unavailable unless GameResult.valid_replay_history?(replay,snapshot.events) &&
        replay.players.map { |name| Data.account(name).downcase }.sort==binding['players'].map { |person| person['account'] }.sort
      raise OrdinaryMatchService::Blocked,:result_already_recorded if replay.finished? || session['__aborted']
      boundary={'binding_digest'=>Digest::SHA256.hexdigest(JSON.generate(binding)),'session_id'=>binding['session_id'],
        'event_count'=>snapshot.events.size,'history_digest'=>Digest::SHA256.hexdigest(JSON.generate(snapshot.events))}
      [boundary,game,replay,session]
    end
  end
end
