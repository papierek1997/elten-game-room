# encoding: UTF-8
module GameRoomTournaments
  # A fixture has one creator, elected once by the ordered, authenticated log.
  # This is not player readiness and has no heartbeat. An incomplete creator
  # record blocks creation rather than allowing a second native table.
  module OrdinaryMatchEntry
    Data = Publication::Data
    ENTRY_VERSION = 2

    # Presentation only: entry has already checked this binding. Starting,
    # rejoining and publishing results still perform their own fresh checks.
    def attached_table?(table)
      !attached_binding(table).nil?
    end

    # Entry has just verified the binding before native membership. Reuse its
    # immutable roster for the local role; do not fetch the tournament again.
    def observer_on_join?(table)
      binding=attached_binding(table)
      raise OrdinaryMatchService::Blocked,:wrong_match_binding unless binding
      binding['players'].none?{|person|person['account']==@owner}
    end

    def attach_table(table)
      marker=table['tournament_match']
      return false unless marker
      candidate,id,usernames=source!
      raise OrdinaryMatchService::Blocked,:source_changed unless marker['publication_ref']==candidate['publication_ref'] && marker['schedule_id']==candidate['schedule_id']
      match=candidate['matches'].find{|item|item['match_id']==marker['match_id'] && item['leg']==marker['leg']}
      raise OrdinaryMatchService::Blocked,:missing_match unless match
      binding=read_match_binding(candidate,id,match,nil)
      raise OrdinaryMatchService::Blocked,:wrong_match_binding unless binding && binding['table']['__live_session_id']==table['__live_session_id'] && binding['table']['__id']==table['__id']
      remember_binding(binding,candidate,id,match,usernames: usernames)
      true
    end

    def invitation_players(table)
      row,usernames=@lock.synchronize{[@bindings[table['__id']],@binding_usernames[table['__id']]]}
      return [] unless row && row[0]['table']['__live_session_id']==table['__live_session_id']
      row[0]['players'].reject{|person|person['account']==@owner}.map do |person|
        RegistrationProjection.delivery_name(usernames,person['account'])
      end
    end

    private

    def attached_binding(table)
      account!
      @lock.synchronize do
        binding=@bindings[table['__id']]&.first
        binding if binding && binding['table']['__live_session_id']==table['__live_session_id'] &&
          binding['table']['tournament_match']==table['tournament_match']
      end
    end

    def binding_digest(binding)
      Digest::SHA256.hexdigest(JSON.generate(ServerPlanDocument.copy_document(binding)))
    end

    def entry_anchor(candidate,id,match,kind,previous=nil)
      base=anchor(candidate,id,match,kind)
      return base unless previous
      base.merge('operation_key'=>Digest::SHA256.hexdigest(JSON.generate([base['operation_key'],binding_digest(previous)])))
    end

    def creator_document(candidate,match,previous,creator)
      {'kind'=>'ordinary-match-creator-v1','schedule_id'=>candidate['schedule_id'],
        'publication_ref'=>candidate['publication_ref'],'match_id'=>match['match_id'],'leg'=>match['leg'],
        'previous_digest'=>previous && binding_digest(previous),'creator'=>creator}
    end

    def elected_creator(candidate,id,match,previous=nil,rows:nil)
      key=entry_anchor(candidate,id,match,'creator',previous)
      rows ||= ServerDocumentRows.read(@table,where:{'operation_key'=>key['operation_key']},guard:method(:account!))
      eligible=rows.select{|row|match['players'].include?(row['__insertion_user'].to_s.downcase)}
      first=eligible.min_by{|row|row.fetch('__id')}
      return nil unless first
      author=first['__insertion_user'].downcase
      value=read_document(key,author,rows:eligible)
      raise OrdinaryMatchService::Blocked,:wrong_match_creator unless value==creator_document(candidate,match,previous,author)
      author
    end

    def claim_creator(candidate,id,match,previous=nil)
      creator=elected_creator(candidate,id,match,previous)
      return creator if creator
      key=entry_anchor(candidate,id,match,'creator',previous)
      value=creator_document(candidate,match,previous,@owner)
      publish_document(value,key) do |document|
        current,current_id=source!
        reject_voided_return!(candidate,id,match,allow_incomplete:false)
        current==candidate && current_id==id && document==value &&
          !forfeit_document(candidate,id,match,allow_incomplete:false) && !read_result_document(candidate,id,match) &&
          (!@entry_guard || !!@entry_guard.call(candidate,match,previous))
      end
      elected_creator(candidate,id,match,previous)
    end

    def initial_match_binding(candidate,id,match,rows:nil,creator_rows:nil)
      key=anchor(candidate,id,match,'binding')
      if rows.nil? && creator_rows.nil?
        creator_key=entry_anchor(candidate,id,match,'creator')['operation_key']
        grouped=ServerDocumentRows.read_keys(@table,[key['operation_key'],creator_key],guard:method(:account!)).group_by{|row|row.fetch('operation_key')}
        rows=grouped[key['operation_key']] || []
        creator_rows=grouped[creator_key] || []
      end
      creator=elected_creator(candidate,id,match,rows:creator_rows)
      # Published bindings from before ordinary invitations retain their
      # original designated creator and their exact result hashes.
      creator ||= prepared_match(candidate,match)['players'].first['account']
      binding=read_document(key,creator,rows:rows)
      if binding && binding['entry_version']==ENTRY_VERSION
        raise OrdinaryMatchService::Blocked,:wrong_match_creator unless elected_creator(candidate,id,match,rows:creator_rows)==binding['creator']
      end
      binding
    end

    def remember_binding(binding,candidate,id,match,usernames: nil)
      @lock.synchronize do
        raise OrdinaryMatchService::Blocked,:account_changed if @closed
        table_id=binding['table']['__id']
        @bindings[table_id]=[Data.freeze_tree(Data.copy(binding)),candidate,id,match]
        @binding_usernames[table_id]=usernames
        unless @managed
          @program.class.manage(self) if @program.class.respond_to?(:manage)
          @managed=true
        end
      end
    end

    def create_match_table(candidate,id,match,previous:nil)
      current_room=@lobby.current_table_for(@user.call)
      current,current_id=source!
      raise OrdinaryMatchService::Blocked,:source_changed unless current==candidate && current_id==id
      @entry_guard&.call(candidate,match,previous)
      marker=candidate.slice('publication_ref','schedule_id').merge(match.slice('match_id','leg'))
      if current_room && current_room['tournament_match']!=marker
        raise OrdinaryMatchService::Blocked,:already_at_another_table
      end
      creator=claim_creator(candidate,id,match,previous)
      raise OrdinaryMatchService::Blocked,:waiting_for_match_creator unless creator==@owner
      prepared=prepared_match(candidate,match)
      key=previous ? continuation_anchor(candidate,id,match,previous) : anchor(candidate,id,match,'binding')
      create_key=entry_anchor(candidate,id,match,'create',previous)
      descriptor={'kind'=>'ordinary-match-create-v2','schedule_id'=>candidate['schedule_id'],
        'publication_ref'=>candidate['publication_ref'],'match_id'=>match['match_id'],'leg'=>match['leg'],
        'previous_digest'=>previous && binding_digest(previous)}
      record=@journal.prepare(kind:'plan_document',intent_id:'ordinary-create:'+create_key['operation_key'],
        values:create_key.merge('kind'=>'plan_document','document_json'=>JSON.generate(descriptor)))
      suffix=' / '+match['leg'].to_s+' ['+create_key['operation_key'][0,12]+']'
      names=prepared['players'].map{|person|person['account'][0,14]}.join(' — ')
      name=names[0,LobbyRepository::TABLE_NAME_MAX_LENGTH-suffix.length].rstrip+suffix
      marker=candidate.slice('publication_ref','schedule_id').merge(match.slice('match_id','leg'))
      room=current_room
      room ||= create_ordinary_room(candidate,id,match,previous,prepared,record,name,marker)
      raise OrdinaryMatchService::Blocked,:already_at_another_table unless room && room['name']==name &&
        room['game']==candidate['game_id'] && room['owner'].downcase==@owner && room['tournament_match']==marker &&
        room['game_options']==JSON.generate(prepared['options'])
      account!
      raise OrdinaryMatchService::Blocked,:table_already_has_games unless @transport.game_sessions(room,force:true).empty?
      binding={'kind'=>'ordinary-match-binding-v1','entry_version'=>ENTRY_VERSION,'schedule_id'=>candidate['schedule_id'],
        'publication_ref'=>candidate['publication_ref'],'match_id'=>match['match_id'],'leg'=>match['leg'],
        'session_id'=>SecureRandom.random_number(2_000_000_000)+1,'creator'=>creator,'game_id'=>candidate['game_id'],
        'options'=>prepared['options'],'players'=>prepared['players'],'result_policy'=>GameResult::CURRENT_RESULT_POLICY,
        'table'=>room.slice('__id','__live_session_id','name','game','owner','game_options','tournament_match')}
      document=previous ? {'kind'=>'ordinary-match-replacement-v1','publication_ref'=>candidate['publication_ref'],
        'schedule_id'=>candidate['schedule_id'],'match_id'=>match['match_id'],'leg'=>match['leg'],
        'previous_digest'=>binding_digest(previous),'binding'=>binding} : binding
      retained=@journal.find(kind:'plan_document',intent_id:'ordinary-document:'+key['operation_key'])
      document=StrictJson.parse(retained['values']['document_json'],max_nesting:12) if retained
      binding=previous ? document.fetch('binding') : document
      publish_document(document,key) do |value|
        fresh,fresh_id=source!
        reject_voided_return!(candidate,id,match,allow_incomplete:false)
        fresh==candidate && fresh_id==id && value==document && valid_binding?(binding,candidate,match) &&
          elected_creator(candidate,id,match,previous)==@owner &&
          (!previous || !read_start_intent(candidate,id,match,previous)) &&
          !forfeit_document(candidate,id,match,allow_incomplete:false) && !read_result_document(candidate,id,match) &&
          (!@entry_guard || !!@entry_guard.call(candidate,match,previous))
      end
      pending=@journal.fetch(record['id'])
      if pending['status']!='confirmed'
        @journal.resolve(pending['id'],status:'confirmed',evidence:{'table_id'=>room['__id'],
          'native_session_id'=>room['__live_session_id']},expected_revision:pending['revision'])
      end
      Data.freeze_tree(ServerPlanDocument.copy_document(binding))
    end

    def create_ordinary_room(candidate,id,match,previous,prepared,record,name,marker)
      history_capacity=@registry.build(candidate['game_id']).session_history_capacity(prepared['options'])
      creation_guard = -> do
        current,current_id=source!
        raise OrdinaryMatchService::Blocked,:source_changed unless current==candidate && current_id==id
        raise OrdinaryMatchService::Blocked,:source_changed if @entry_guard && !@entry_guard.call(candidate,match,previous)
        raise OrdinaryMatchService::Blocked,:creation_unconfirmed unless record['status']=='prepared' && @journal.claim(record['id'])
      end
      made=@lobby.create_table(name:name,game:candidate['game_id'],owner:@user.call,
        game_options:JSON.generate(prepared['options']),private_table:false,tournament_match:marker,
        creation_guard:creation_guard,**(history_capacity ? {history_capacity: history_capacity} : {}))
      unless made && made.created?
        raise OrdinaryMatchService::Blocked,:already_at_another_table
      end
      current,current_id=source!
      raise OrdinaryMatchService::Blocked,:source_changed unless current==candidate && current_id==id
      raise OrdinaryMatchService::Blocked,:source_changed if @entry_guard && !@entry_guard.call(candidate,match,previous)
      made.table
    end

    def read_start_intent(candidate,id,match,binding,rows:nil)
      key=entry_anchor(candidate,id,match,'start',binding)
      rows ||= ServerDocumentRows.read(@table,where:{'operation_key'=>key['operation_key']},guard:method(:account!))
      rows.any?{|row|match['players'].include?(row['__insertion_user'].to_s.downcase)}
    end

    def retain_start_intent(candidate,id,match,binding)
      return unless binding['entry_version']==ENTRY_VERSION
      key=entry_anchor(candidate,id,match,'start',binding)
      document={'kind'=>'ordinary-match-start-v1','publication_ref'=>candidate['publication_ref'],
        'schedule_id'=>candidate['schedule_id'],'match_id'=>match['match_id'],'leg'=>match['leg'],
        'binding_digest'=>binding_digest(binding),'session_id'=>binding['session_id']}
      publish_document(document,key) do |value|
        current,current_id=source!
        reject_voided_return!(candidate,id,match,allow_incomplete:false)
        current==candidate && current_id==id && value==document &&
          read_match_binding(candidate,id,match,nil)==binding &&
          !forfeit_document(candidate,id,match,allow_incomplete:false) && !read_result_document(candidate,id,match)
      end
    end

    def replacement_allowed!(candidate,id,match,binding)
      # Only a confirmed, never-started public table may be replaced. A lost
      # start/result acknowledgement remains recoverable, not a new match.
      raise OrdinaryMatchService::Blocked,:closed_match_needs_recovery unless binding['entry_version']==ENTRY_VERSION &&
        !binding.key?('continuation') && !read_start_intent(candidate,id,match,binding)
    end

    def entry_operation?(document)
      %w[ordinary-match-creator-v1 ordinary-match-create-v2 ordinary-match-replacement-v1 ordinary-match-start-v1].include?(document['kind']) ||
        document['kind']=='ordinary-match-binding-v1' && document['entry_version']==ENTRY_VERSION
    end

    def reconcile_entry_operation(record,document,candidate,id,match)
      raise OrdinaryMatchService::Blocked,:not_a_match_player unless match['players'].include?(@owner)
      raise OrdinaryMatchService::Blocked,:source_changed unless document['publication_ref']==candidate['publication_ref'] && document['schedule_id']==candidate['schedule_id']
      previous=nil
      if (digest=document['previous_digest'])
        ServerPlanDocument.digest!(digest)
        previous=read_match_binding(candidate,id,match,nil,stop_at:digest)
        raise OrdinaryMatchService::Blocked,:wrong_match_binding unless previous && binding_digest(previous)==digest
      end
      kind=document['kind']
      if kind=='ordinary-match-create-v2'
        binding=read_match_binding(candidate,id,match,nil)
        raise OrdinaryMatchService::Blocked,:creation_unconfirmed unless binding && binding['creator']==@owner && binding!=previous
        return record if record['status']=='confirmed'
        return @journal.resolve(record['id'],status:'confirmed',evidence:{'table_id'=>binding['table']['__id'],
          'native_session_id'=>binding['table']['__live_session_id']},expected_revision:record['revision'])
      end
      expected=case kind
      when 'ordinary-match-creator-v1' then entry_anchor(candidate,id,match,'creator',previous)
      when 'ordinary-match-replacement-v1' then continuation_anchor(candidate,id,match,previous)
      when 'ordinary-match-binding-v1' then anchor(candidate,id,match,'binding')
      when 'ordinary-match-start-v1'
        binding=read_match_binding(candidate,id,match,nil,stop_at:document['binding_digest'])
        raise OrdinaryMatchService::Blocked,:wrong_match_binding unless binding && binding_digest(binding)==document['binding_digest'] && binding['session_id']==document['session_id']
        entry_anchor(candidate,id,match,'start',binding)
      end
      ServerPlanArchive.new(table:@table,journal:@journal,user:-> {account!;@user.call},verify:->(value,retained) do
        current,current_id=source!
        # A confirmed entry is read-only evidence, not a request to launch
        # another game. Unfinished entries still need the fresh settlement
        # fence, including an uncertain all-zero decision on the return leg.
        settlement_open=record['status']=='confirmed' || begin
          reject_voided_return!(candidate,id,match,allow_incomplete:false)
          !forfeit_document(candidate,id,match,allow_incomplete:false) && !read_result_document(candidate,id,match)
        end
        valid=case kind
        when 'ordinary-match-creator-v1' then value==creator_document(candidate,match,previous,@owner)
        when 'ordinary-match-start-v1' then value==document
        else
          binding=kind=='ordinary-match-replacement-v1' ? value['binding'] : value
          valid_binding?(binding,candidate,match) && binding['creator']==@owner && elected_creator(candidate,id,match,previous)==@owner &&
            (!previous || !read_start_intent(candidate,id,match,previous))
        end
        retained==expected && current==candidate && current_id==id && value==document && valid && settlement_open
      end).resume(record['id'])
    end
  end
end
