# encoding: UTF-8
require_relative 'interrupted_outcome'
require_relative 'ordinary_match_administration'
module GameRoomTournaments
  module OrdinaryMatchForfeit
    include OrdinaryMatchAdministration
    Data = Publication::Data
    # Read-only proposal. The returned immutable document is the exact intent
    # confirmed by the organizer; committing a changed projection needs consent
    # again, not a silent recomputation of the winner or places.
    def forfeit_preview(match_id:, leg:, expected_schedule_id:, loser: nil, places: nil, forfeits: nil, scores: nil, all_zero: false)
      candidate,id=source!
      match=forfeit_match!(candidate,match_id,leg,expected_schedule_id)
      raise OrdinaryMatchService::Blocked,:result_already_recorded if forfeit_document(candidate,id,match) ||
        read_result_document(candidate,id,match)
      units = (match['unit_ids'] || match['players']).sort
      if loser && !all_zero && places.nil?
        raise OrdinaryMatchService::Blocked, :invalid_forfeit_loser unless units.include?(loser)
        places = [units - [loser], [loser]]
        forfeits = [loser]
        policy = @registry.build(candidate['game_id']).tournament_small_point_policy(options: candidate['game_options'])
        scores ||= AdministrativeResult.suggestions(units: units, forfeits: forfeits, policy: policy)
      end
      build_administrative_preview(candidate, id, match, places: places, forfeits: forfeits || [], scores: scores, all_zero: all_zero)
    end

    def confirm_forfeit(preview:)
      candidate,id=source!
      raise OrdinaryMatchService::Blocked,:invalid_forfeit_receipt unless preview.is_a?(Hash)
      match=forfeit_match!(candidate,preview['match_id'],preview['leg'],preview['schedule_id'])
      document=Data.freeze_tree(ServerPlanDocument.copy_document(preview))
      raise OrdinaryMatchService::Blocked, :legacy_forfeit_write_disabled unless document['kind'] == 'ordinary-match-forfeit-v3'
      validate_administrative_receipt!(document,candidate,match)
      verify_administrative_intent!(document,candidate,id,match)
      key=anchor(candidate,id,match,'forfeit')
      digest=Digest::SHA256.hexdigest(JSON.generate(document))
      forfeit_archive(document,candidate,id,match).publish(
        intent_id:'ordinary-forfeit:'+key['operation_key']+':'+digest,document:document,anchor:key)
      view=result_view
      @result_changed.call(candidate.fetch('publication_ref'))
      notify_sports_rankings(candidate,id,match)
      view
    end

    # Historical v1 documents remain readable. Neither old UI callbacks nor a
    # retained operation may publish a new winner-based decision.
    def award_forfeit(**_legacy_arguments)
      raise OrdinaryMatchService::Blocked,:legacy_forfeit_write_disabled
    end

    private
    def forfeit_match!(candidate,match_id,leg,schedule_id)
      raise OrdinaryMatchService::Blocked,:not_organizer unless candidate.fetch('publication_ref').fetch('author').downcase==@owner
      raise OrdinaryMatchService::Blocked,:source_changed unless candidate['schedule_id']==schedule_id
      match=candidate.fetch('matches').find { |row| row['match_id']==match_id && row['leg']==leg }
      raise OrdinaryMatchService::Blocked,:missing_match unless match && supported_match?(candidate,match)
      match
    end


    def validate_forfeit_v2!(value,candidate,match)
      units=(match['unit_ids'] || match['players']).sort
      keys=%w[decision kind leg match_id organizer publication_ref schedule_id summary]
      keys << 'cancelled_game' if value.key?('cancelled_game')
      decision=value['decision']
      unless value.keys.sort==keys.sort && value['kind']=='ordinary-match-forfeit-v2' &&
          value['schedule_id']==candidate['schedule_id'] && value['match_id']==match['match_id'] && value['leg']==match['leg'] &&
          value['publication_ref']==candidate['publication_ref'] && value['organizer']==candidate.fetch('publication_ref').fetch('author').downcase &&
          decision.is_a?(Hash) && decision.keys.sort==(%w[basis checkpoint loser mode]+(decision.key?('eliminations') ? ['eliminations'] : [])).sort && decision['mode']=='terminal'
        raise OrdinaryMatchService::Blocked,:invalid_forfeit_receipt
      end
      boundary=value['cancelled_game']
      validate_cancellation_boundary!(boundary) if boundary
      expected=InterruptedOutcome.build(units:units,loser:decision['loser'],started:!boundary.nil?,
        checkpoint:decision['checkpoint'],continuation:{'status'=>'cannot_continue'},event_count:boundary ? boundary['event_count'] : 0,
        eliminations:decision.fetch('eliminations',[]))
      raise OrdinaryMatchService::Blocked,:invalid_forfeit_receipt unless value['decision']==expected['decision'] && value['summary']==expected['summary']
      true
    rescue Publication::Invalid
      raise OrdinaryMatchService::Blocked,:invalid_forfeit_receipt
    end

    def validate_cancellation_boundary!(boundary)
      unless boundary.is_a?(Hash) && boundary.keys.sort==%w[binding_digest event_count history_digest session_id] &&
          %w[binding_digest history_digest].all? { |key| boundary[key].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(boundary[key]) } &&
          Publication::Data.integer?(boundary['session_id'],1) && Publication::Data.integer?(boundary['event_count'])
        raise OrdinaryMatchService::Blocked,:invalid_forfeit_receipt
      end
    end

    def forfeit_native_sessions(candidate,id,match,binding,start_rows:nil)
      raise OrdinaryMatchService::Blocked,:game_state_unavailable unless @transport
      sessions=@transport.game_sessions(binding['table'],force:true)
      if sessions.empty? && (binding['entry_version']!=OrdinaryMatchEntry::ENTRY_VERSION ||
          binding.key?('continuation') || read_start_intent(candidate,id,match,binding,rows:start_rows))
        # game_sessions is membership-local. A missing/closed native projection
        # is not evidence that an accepted or uncertain start never happened.
        raise OrdinaryMatchService::Blocked,:game_state_unavailable
      end
      sessions
    end

    def cancellation_valid_binding?(value,binding,candidate,match)
      binding && valid_binding?(binding,candidate,match) &&
        value['cancelled_game']['binding_digest']==Digest::SHA256.hexdigest(JSON.generate(binding)) &&
        value['cancelled_game']['session_id']==binding['session_id']
    end
    def forfeit_document(candidate,id,match,rows:nil,result_rows:nil,allow_incomplete:true)
      attempts=forfeit_receipts(candidate,id,match,rows:rows,allow_incomplete:allow_incomplete)
      return nil if attempts.empty?
      ordinary=ordinary_result_receipt(candidate,id,match,rows:result_rows,allow_incomplete:true)
      entry=ordered_match_receipts(attempts,ordinary).first
      return nil if entry['document']['kind']=='ordinary-match-result-v1'
      yield entry if entry && block_given?
      entry && entry['document']
    end

    def ordered_match_receipts(forfeits,ordinary)
      # Both document kinds live in the same server table. Their completion
      # row IDs share one monotonic order, even when an older batch arrives late.
      (forfeits+(ordinary ? [ordinary] : [])).sort_by { |entry| entry['completed_row_id'] }
    end

    def ordinary_result_receipt(candidate,id,match,rows:nil,allow_incomplete:false)
      entry=nil
      document=read_result_document(candidate,id,match,rows:rows,allow_incomplete:allow_incomplete) do |time,evidence|
        entry=evidence.merge('time'=>time)
      end
      entry && entry.merge('document'=>document)
    end

    def forfeit_receipts(candidate,id,match,rows:nil,allow_incomplete:true)
      author=candidate.fetch('publication_ref').fetch('author').downcase
      key=anchor(candidate,id,match,'forfeit')
      rows ||= ServerDocumentRows.read(@table,where:{'operation_key'=>key['operation_key']},guard:method(:account!))
      account!
      incomplete=false
      receipts=ServerDocumentRows.owned(rows,author).group_by { |row| row['document_digest'] }.filter_map do |_digest,attempt|
        parts=ServerPlanDocument.canonical_rows(attempt,anchor:key,author:author)
        validate_forfeit_parts!(parts)
        # Only valid incomplete attempts are absent results. Broken payloads,
        # mixed parts, hashes and authenticated invalid receipts still fail.
        unless parts.first['part_index']==0 && parts.size==parts.first['part_count']+1
          incomplete=true
          next
        end
        value=ServerPlanDocument.decode(parts,anchor:key,author:author)
        validate_forfeit!(value,candidate,match)
        {'document'=>value,'digest'=>parts.first['document_digest'],
          'completed_row_id'=>parts.map { |part| part['__id'] }.max,'time'=>document_time(parts)}
      end.sort_by { |entry| entry['completed_row_id'] }
      # Incomplete chunks cannot settle a fixture, but a visible authenticated
      # organizer intent must fence a new start until the archive is recovered.
      # Reading results and resuming that exact intent remain non-blocking.
      raise ServerPlanArchive::Unconfirmed,'Administrative result is incomplete' if receipts.empty? && incomplete && !allow_incomplete
      receipts
    end

    def validate_forfeit_parts!(parts)
      first=parts.first
      parts.each do |part|
        raise Publication::Invalid,:invalid_plan_part unless part['part_count']==first['part_count'] &&
          part['document_digest']==first['document_digest']
        if part['part_index']==0
          raise Publication::Invalid,:invalid_plan_part unless part['payload']==''
          next
        end
        payload=part['payload']
        raise Publication::Invalid,:invalid_plan_encoding unless payload.is_a?(String) && payload.bytesize.between?(1,2048)
        begin
          bytes=Base64.strict_decode64(payload)
        rescue ArgumentError
          raise Publication::Invalid,:invalid_plan_encoding
        end
        raise Publication::Invalid,:invalid_plan_encoding unless bytes.bytesize.between?(1,ServerPlanDocument::PART_BYTES) &&
          (part['part_index']==part['part_count'] || bytes.bytesize==ServerPlanDocument::PART_BYTES)
      end
    end

    def forfeit_archive(document,candidate,id,match)
      expected=anchor(candidate,id,match,'forfeit')
      digest=Digest::SHA256.hexdigest(JSON.generate(ServerPlanDocument.copy_document(document)))
      ServerPlanArchive.new(table:@table,journal:@journal,user:-> {account!; @user.call},document_digest:digest,
        verify:->(value,retained) do
          retained==expected && value==document && verify_administrative_intent!(value,candidate,id,match)
        end)
    end
    def validate_forfeit!(value,candidate,match)
      return validate_administrative_receipt!(value,candidate,match) if value['kind']=='ordinary-match-forfeit-v3'
      return validate_forfeit_v2!(value,candidate,match) if value['kind']=='ordinary-match-forfeit-v2'
      units=(match['unit_ids'] || match['players']).sort
      summary=value['summary']
      cancellation=value['kind']=='ordinary-match-cancel-forfeit-v1'
      keys=%w[kind leg match_id publication_ref schedule_id summary]
      keys << 'cancelled_game' if cancellation
      boundary=value['cancelled_game']
      if cancellation
        raise OrdinaryMatchService::Blocked,:invalid_forfeit_receipt unless boundary.is_a?(Hash) &&
          boundary.keys.sort==%w[binding_digest event_count history_digest session_id] &&
          %w[binding_digest history_digest].all?{|key|boundary[key].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(boundary[key])} &&
          Publication::Data.integer?(boundary['session_id'],1) && Publication::Data.integer?(boundary['event_count'])
      end
      raise OrdinaryMatchService::Blocked,:invalid_forfeit_receipt unless value.keys.sort==keys.sort &&
        (cancellation || value['kind']=='ordinary-match-forfeit-v1') && value['schedule_id']==candidate['schedule_id'] &&
        value['match_id']==match['match_id'] && value['leg']==match['leg'] && value['publication_ref']==candidate['publication_ref'] &&
        summary.is_a?(Hash) && summary.keys.sort==%w[draw event_count participants scores winners] &&
        summary['participants']==units && summary['winners'].is_a?(Array) && summary['winners'].size==1 &&
        units.include?(summary['winners'].first) && summary['draw']==false && summary['scores'].nil? && summary['event_count']==0
      true
    end
  end
end
