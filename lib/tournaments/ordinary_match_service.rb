# encoding: UTF-8
require 'thread'
require_relative 'server_plan_archive'
require_relative 'ordinary_match_results'
require_relative 'standings_ranking'
require_relative 'group_standings'
require_relative 'match_order'
require_relative 'ordinary_team_players'
require_relative 'knockout_standings'
require_relative 'ordinary_match_forfeit'
require_relative 'ordinary_match_presence'
require_relative 'ordinary_saved_match'
require_relative 'ordinary_match_entry'
require_relative 'server_document_rows'
require_relative 'server_capacity'
require_relative 'registration_projection'

module GameRoomTournaments
  # Ordinary invitations, one elected creator per table, first native game only.
  # Any bound participant can retain its verified result after creator departure.
  class OrdinaryMatchService
    include OrdinaryMatchForfeit
    include OrdinaryMatchPresence
    include OrdinarySavedMatch
    include OrdinaryMatchEntry
    class Blocked < StandardError
      attr_reader :code
      def initialize(code); @code = code; super(code.to_s); end
    end
    Data = Publication::Data
    attr_reader :owner
    def initialize(program:, registry:, lobby:, games:, transport:, table:, journal:, source:, user:, entry_guard:nil, changed:->(_reference){}, read_scope:->(&block){block.call}, completed_source:nil, rankings_observer:nil)
      @program, @registry, @lobby, @games, @transport = program, registry, lobby, games, transport
      @table, @journal, @source, @user = table, journal, source, user
      @entry_guard,@result_changed=entry_guard,changed
      @read_scope=read_scope
      @completed_source=completed_source
      @rankings_observer=rankings_observer
      @owner = journal.owner
      @changed = false
      @bindings, @binding_usernames, @seen, @errors = {}, {}, {}, Queue.new
      @result_jobs = {}
      @jobs, @lock, @closed = Queue.new, Mutex.new, false
      account!
    end

    def open_match(match_id:, leg:)
      candidate, id, usernames = source!
      match = candidate.fetch('matches').find { |m| m['match_id'] == match_id && m['leg'] == leg }
      raise Blocked, :missing_match unless match
      reject_voided_return!(candidate,id,match,allow_incomplete:false)
      documents=match_documents(candidate,id,match)
      raise Blocked,:result_already_recorded if forfeit_document(candidate,id,match,rows:documents['forfeit'],result_rows:documents['result'],allow_incomplete:false) ||
        read_result_document(candidate,id,match,rows:documents['result'])
      raise Blocked, :unsupported_match_players unless supported_match?(candidate,match)
      raise Blocked, :not_a_match_player unless match['players'].include?(@owner)
      raise Blocked,:private_game_not_supported if @registry.build(candidate['game_id']).private_table_required?(candidate['game_options'])
      initial=initial_match_binding(candidate,id,match,rows:documents['binding'],creator_rows:documents['creator'])
      binding=initial && read_match_binding(candidate,id,match,nil,initial:initial)
      if binding
        current_room=@lobby.current_table_for(@user.call)
        raise Blocked,:already_at_another_table if current_room && current_room['__live_session_id']!=binding['table']['__live_session_id']
        unless current_room
          # A complete discovery read, not a cached widget list or a failed
          # request. Tournament tables are public and cannot change visibility.
          available=@transport.discover_rooms(include_private:true).any?{|room|room['__live_session_id']==binding['table']['__live_session_id']}
          unless available
            replacement_allowed!(candidate,id,match,binding)
            binding=create_match_table(candidate,id,match,previous:binding)
          end
        end
      else
        binding=create_match_table(candidate,id,match)
      end
      raise Blocked, :wrong_match_binding unless valid_binding?(binding, candidate, match)
      entry_authorized=authorize_existing_entry(candidate,match,binding)
      room = binding.fetch('table')
      current_room = @lobby.current_table_for(@user.call)
      if current_room && current_room['__live_session_id'] != room['__live_session_id']
        raise Blocked, :already_at_another_table
      end
      unless current_room && current_room['__live_session_id'] == room['__live_session_id']
        joined = @lobby.join_table(room, @user.call)
        raise Blocked, :table_join_failed unless joined && [:joined,:already_here].include?(joined.status)
        room = joined.table
      end
      unless entry_authorized
        begin
          authorize_existing_entry(candidate,match,binding,joined:true)
        rescue Publication::Invalid
          @lobby.leave_table(room,@user.call) unless current_room
          raise
        end
      end
      account!
      remember_binding(binding,candidate,id,match,usernames: usernames)
      room
    end

    # Only an event handoff inside the existing runner's observation boundary.
    # Repository/server I/O happens later, on this separate finite-work consumer.
    def start_parameters(table, players: nil, options: nil)
      row=@lock.synchronize{@bindings[table['__id']]}
      return {} unless row && row[0]['table']['__live_session_id']==table['__live_session_id']
      account!
      binding,candidate,id,match=row
      reject_voided_return!(candidate,id,match,allow_incomplete:false)
      documents=match_documents(candidate,id,match)
      raise Blocked,:result_already_recorded if forfeit_document(candidate,id,match,rows:documents['forfeit'],result_rows:documents['result'],allow_incomplete:false) ||
        read_result_document(candidate,id,match,rows:documents['result'])
      raise Blocked,:not_a_match_player unless match['players'].include?(@owner) && table['owner'].to_s.downcase==@owner
      current,current_id=source!
      raise Blocked,:source_changed unless current==candidate && current_id==id
      @entry_guard&.call(candidate,match,binding)
      ordered = binding['players'].sort_by{|person|person['seat']}.map do |person|
        (players || []).find{|name|Data.account(name).downcase==person['account']} || person['username']
      end
      actual_options=options || StrictJson.parse(table.fetch('game_options'),max_nesting:12)
      game=@registry.build(binding['game_id'])
      normalized=game.normalize_options(actual_options)
      team=binding['players'].any?{|person|person.key?('team')}
      # Room order follows joins; the fixed tournament seats need not. Compare
      # the same people in planned order, not two differently ordered indices.
      normalized=game.options_for_team_roster(normalized,players:ordered) if team
      equal=team ? normalized.reject{|key,_|key=='team_players'}==binding['options'].reject{|key,_|key=='team_players'} : normalized==binding['options']
      raise Blocked,:wrong_game_options unless equal
      if players
        raise Blocked,:wrong_game_players unless players.map{|name|Data.account(name).downcase}.sort==binding['players'].map{|p|p['account']}.sort
      end
      raise Blocked,:match_already_has_a_game unless @transport.game_sessions(table,force:true).empty?
      raise Blocked,:wrong_match_binding unless read_match_binding(candidate,id,match,nil)==binding
      retain_start_intent(candidate,id,match,binding)
      result={requested_session_id:binding.fetch('session_id'), players:ordered}
      if team
        result[:options]=JSON.generate(@registry.build(binding['game_id']).with_team_assignment(binding['options'],players:ordered,seats:binding['options'].fetch('team_seats')))
      end
      result
    end

    # A fresh reference for a notification/coordinator; no native membership or
    # worker is created by this read. Completed fixtures cannot be re-entered.
    def entry_status(match_id:,leg:)
      candidate,id=source!
      match=candidate.fetch('matches').find{|row|row['match_id']==match_id && row['leg']==leg}
      raise Blocked,:missing_match unless match && supported_match?(candidate,match)
      reject_voided_return!(candidate,id,match,allow_incomplete:false)
      documents=match_documents(candidate,id,match)
      raise Blocked,:result_already_recorded if forfeit_document(candidate,id,match,rows:documents['forfeit'],result_rows:documents['result'],allow_incomplete:false) ||
        read_result_document(candidate,id,match,rows:documents['result'])
      initial=initial_match_binding(candidate,id,match,rows:documents['binding'],creator_rows:documents['creator'])
      binding=initial && read_match_binding(candidate,id,match,nil,initial:initial)
      raise Blocked,:wrong_match_binding if binding && !valid_binding?(binding,candidate,match)
      creator=binding && binding['creator']
      Data.freeze_tree({'candidate'=>candidate,'match'=>match,'creator'=>creator,'binding'=>binding})
    end

    def observe(table, session, replay, events=nil)
      return unless session && table && (replay.finished? || GameRoomTournamentPresence.ended?(session))
      @lock.synchronize do
        row = @bindings[table['__id']]
        return unless row && row[0]['players'].any? { |person| person['account'] == @owner } && !@closed
        return unless row[0]['table']['__live_session_id']==table['__live_session_id']
        return unless session['__id']==row[0]['session_id']
        key = [table['__id'], row[0]['match_id'], row[0]['leg']]
        if @seen[key]
          return unless queue_result_retry(@result_jobs[key])
        else
          raise Blocked, :result_queue_limit if @result_jobs.size >= 64
          capture=events && OrdinaryMatchResults.capture(registry:@registry,binding:row[0],session:session,replay:replay,events:events)
          job={key:key.freeze,row:(capture ? row+[capture] : row).freeze,queued:true,retryable:false}
          @result_jobs[key]=job
          @jobs << job
          @seen[key] = true
          start_worker
        end
      end
      true
    rescue Publication::Invalid=>error
      @errors << error if @errors.size<16
      false
    end

    def result_view(include_match_status:false,allow_incomplete_forfeits:true)
      candidate, id = source!
      raise Blocked, :plan_too_large if candidate['matches'].size > ServerCapacity::MAX_MATCHES
      rows = ServerDocumentRows.read_keys(@table, result_document_keys(candidate,id), guard: method(:account!))
      grouped=rows.group_by{|row|row.fetch('operation_key')}
      ordered=ordered_result_receipts(candidate,id,grouped,allow_incomplete_forfeits:allow_incomplete_forfeits)
      effective_forfeits=ordered.transform_values do |attempts|
        first=attempts.first
        first && first['document']['kind']!='ordinary-match-result-v1' ? [first] : []
      end
      bindings=result_bindings(candidate,id,grouped,forfeits:effective_forfeits)
      start_keys=include_match_status ? candidate['matches'].filter_map do |match|
        binding=bindings[[match['match_id'],match['leg']]]
        entry_anchor(candidate,id,match,'start',binding)['operation_key'] if binding
      end : []
      starts=ServerDocumentRows.read_keys(@table,start_keys,guard:method(:account!)).group_by { |row| row.fetch('operation_key') }
      results = []
      result_times=[]
      forfeit_conflicts=[]
      forfeitable=[]
      cancellable=[]
      unavailable=[]
      candidate.fetch('matches').each do |match|
        next unless supported_match?(candidate,match)
        attempts=ordered.fetch([match['match_id'],match['leg']])
        accepted=attempts.first
        forfeit=accepted && accepted['document']['kind']!='ordinary-match-result-v1' && accepted['document']
        if attempts.size>1
          forfeit_conflicts << match.slice('match_id','leg').merge('accepted_digest'=>accepted['digest'],
            'accepted_kind'=>accepted['document']['kind'],
            'later_attempts'=>attempts.drop(1).map { |entry| entry.slice('digest','completed_row_id').merge('kind'=>entry['document']['kind']) })
        end
        if forfeit
          validate_forfeit!(forfeit,candidate,match)
          if forfeit['kind']=='ordinary-match-cancel-forfeit-v1' || forfeit['kind']=='ordinary-match-forfeit-v2' && forfeit.key?('cancelled_game')
            binding=read_match_binding(candidate,id,match,nil)
            raise Blocked,:wrong_match_binding unless cancellation_valid_binding?(forfeit,binding,candidate,match)
            # Explicit organizer cancellation is the sporting cutoff. Native
            # history remains untouched; any later ordinary receipt is excluded.
          end
          results << forfeit
          time=accepted['time']
          result_times << time if time
          next
        end
        binding = bindings[[match['match_id'],match['leg']]]
        unless binding
          forfeitable << {'match_id'=>match['match_id'],'leg'=>match['leg']} if include_match_status
          next
        end
        raise Blocked, :wrong_match_binding unless valid_binding?(binding,candidate,match)
        result_time=accepted && accepted['time']
        receipt=accepted && accepted['document']
        unless receipt
          if include_match_status && @transport
            status=unfinished_result_status(candidate,id,match,binding,starts)
            forfeitable << match.slice('match_id','leg') if status==:forfeitable
            cancellable << match.slice('match_id','leg') if status==:cancellable
            unavailable << match.slice('match_id','leg') if status==:unavailable
          end
          next
        end
        validate_bound_result!(receipt,match,binding)
        results << receipt
        result_times << result_time if result_time
      end
      result_summary(candidate, id, results, result_times, forfeitable, cancellable,
        include_match_status: include_match_status,forfeit_conflicts:forfeit_conflicts,unavailable:unavailable)
    end

    private def ordered_result_receipts(candidate,id,grouped,allow_incomplete_forfeits:)
      forfeits=candidate['matches'].to_h do |match|
        [[match['match_id'],match['leg']],forfeit_receipts(candidate,id,match,
          rows:grouped[anchor(candidate,id,match,'forfeit')['operation_key']] || [])]
      end
      candidate['matches'].to_h do |match|
        key=[match['match_id'],match['leg']]
        forfeit_rows=grouped[anchor(candidate,id,match,'forfeit')['operation_key']] || []
        attempts=forfeits.fetch(key)
        ordinary=ordinary_result_receipt(candidate,id,match,
          rows:grouped[anchor(candidate,id,match,'result')['operation_key']] || [],
          allow_incomplete:!attempts.empty?) if supported_match?(candidate,match)
        accepted=ordered_match_receipts(attempts,ordinary)
        # A result list may omit an unfinished administrative upload, but
        # retention cannot mistake it for proof of an abandoned fixture.
        # An already complete result remains decisive despite later chunks.
        forfeit_receipts(candidate,id,match,rows:forfeit_rows,allow_incomplete:false) if !allow_incomplete_forfeits && accepted.empty?
        [key,accepted]
      end
    end

    private def unfinished_result_status(candidate,id,match,binding,starts)
      start_key=entry_anchor(candidate,id,match,'start',binding)['operation_key']
      administrative_boundary(candidate,id,match,start_rows:starts.fetch(start_key,[]),binding:binding)
      :forfeitable
    rescue Blocked=>error
      raise unless [:result_already_recorded,:game_state_unavailable,:match_in_progress].include?(error.code)
      :unavailable if error.code==:game_state_unavailable
    end

    private def validate_bound_result!(receipt,match,binding)
      unless receipt['kind']=='ordinary-match-result-v1' && receipt['binding_digest']==Digest::SHA256.hexdigest(JSON.generate(binding)) &&
          receipt['match_id']==match['match_id'] && receipt['leg']==match['leg'] &&
          receipt['session_id']==binding['session_id'] && receipt['history_digest'].is_a?(String) &&
          /\A[0-9a-f]{64}\z/.match?(receipt['history_digest']) && receipt['summary'].is_a?(Hash) &&
          valid_summary?(receipt['summary'],match)
        raise Blocked, :invalid_result_receipt
      end
    end

    def result_document_keys(candidate,id)
      candidate.fetch('matches').flat_map{|match|%w[creator binding result forfeit].map{|kind|anchor(candidate,id,match,kind)['operation_key']}}
    end

    # Traverse independent binding chains together. The same authenticated
    # lineage validation is used by entry/recovery; only SDK reads are batched.
    private def result_bindings(candidate,id,grouped,forfeits:)
      completed={}
      pending=candidate['matches'].filter_map do |match|
        next unless supported_match?(candidate,match)
        next unless forfeits.fetch([match['match_id'],match['leg']]).empty?
        binding=initial_match_binding(candidate,id,match,rows:grouped[anchor(candidate,id,match,'binding')['operation_key']] || [],
          creator_rows:grouped[anchor(candidate,id,match,'creator')['operation_key']] || [])
        [match,binding] if binding
      end
      64.times do
        return completed if pending.empty?
        pending.each { |match,binding| raise Blocked,:wrong_match_binding unless valid_binding?(binding,candidate,match) }
        keys=pending.flat_map do |match,binding|
          [entry_anchor(candidate,id,match,'creator',binding)['operation_key'],continuation_anchor(candidate,id,match,binding)['operation_key']]
        end
        documents=ServerDocumentRows.read_keys(@table,keys,guard:method(:account!)).group_by{|row|row.fetch('operation_key')}
        pending=pending.filter_map do |match,binding|
          following=next_match_binding(candidate,id,match,binding,
            creator_rows:documents[entry_anchor(candidate,id,match,'creator',binding)['operation_key']] || [],
            continuation_rows:documents[continuation_anchor(candidate,id,match,binding)['operation_key']] || [])
          if following
            [match,following]
          else
            completed[[match['match_id'],match['leg']]]=binding
            nil
          end
        end
      end
      raise Blocked,:continuation_limit unless pending.empty?
      completed
    end

    private def result_summary(candidate, id, results, result_times, forfeitable, cancellable, include_match_status:,forfeit_conflicts:,unavailable:)
      normalized = results.map { |r| r['summary'].slice('participants','winners','scores','score_order','places','forfeits','resolution').merge('id'=>JSON.generate([r['match_id'],r['leg']])) }
      team=candidate.key?('membership')
      units=team ? candidate['membership']['units'].map{|unit|unit['unit_id']} : candidate.fetch('roster')
      knockout=nil
      standings = if candidate['format']=='knockout'
        knockout=KnockoutStandings.calculate(candidate:candidate,units:units,results:normalized,unit_key:team ? 'unit_ids' : 'players')
        knockout['standings']
      elsif candidate['format']=='groups_knockout'
        GroupStandings.calculate(candidate:candidate,units:units,results:normalized,unit_key:team ? 'unit_ids' : 'players',players_per_match:2)['standings']
      else
        StandingsRanking.calculate(units:units,results:normalized,points:Standings::MATCH_POINTS,criteria:StandingsRanking::CRITERIA)
      end
      current,current_id=source!
      raise Blocked,:source_changed unless current==candidate && current_id==id
      value={'results'=>results,'standings'=>standings,'schedule_id'=>candidate['schedule_id']}
      voided=KnockoutSeries.voided_matches(candidate:candidate,receipts:results)
      unless voided.empty?
        value['settled_without_play']=voided
        keys=voided.map { |row|row.values_at('match_id','leg') }
        forfeitable.reject! { |row|keys.include?(row.values_at('match_id','leg')) }
        cancellable.reject! { |row|keys.include?(row.values_at('match_id','leg')) }
      end
      completed=candidate['format']=='knockout' ? knockout['knockout_state']=='completed' : candidate['format']=='round_robin' && !candidate['matches'].empty? && results.size==candidate['matches'].size
      value['completed']=completed
      if result_times.size==results.size && !result_times.empty?
        value['completed_at']=result_times.max if completed
        value['progress_times']=result_times.uniq.sort
      end
      value['forfeitable_matches']=forfeitable if include_match_status
      value['cancellable_matches']=cancellable if include_match_status
      value['forfeit_conflicts']=forfeit_conflicts unless forfeit_conflicts.empty?
      value['forfeit_unavailable_matches']=unavailable unless unavailable.empty?
      value.merge!(knockout.slice('knockout_state','champion','series_progress')) if knockout
      Data.freeze_tree(value)
    end

    def take_error
      # Opening Matches is an explicit retry opportunity, not a polling loop.
      # Only a failed LOCAL retain is queued again, with its original capture.
      @lock.synchronize do
        unless @closed
          @result_jobs.each_value { |job| queue_result_retry(job) }
          start_worker unless @jobs.empty?
        end
      end
      begin
        @errors.pop(true)
      rescue ThreadError
        nil
      end
    end
    def operations; account!; @journal.list; end
    def reconcile(id)
      account!
      record=@journal.fetch(id)
      raise Blocked,:missing_operation unless record
      candidate,tournament_id=source!
      document=StrictJson.parse(record['values']['document_json'],max_nesting:12)
      raise Blocked,:tournament_saved_game_disabled if document['kind']=='ordinary-match-continuation-v1'
      raise Blocked,:legacy_forfeit_write_disabled if %w[ordinary-match-forfeit-v1 ordinary-match-cancel-forfeit-v1 ordinary-match-forfeit-v2 ordinary-match-elimination-v1].include?(document['kind'])
      match=candidate['matches'].find{|m|m['match_id']==document['match_id'] && m['leg']==document['leg']}
      if match && document['kind']=='ordinary-match-result-v1'
        binding=read_match_binding(candidate,tournament_id,match,nil,stop_at:document['binding_digest'])
        raise Blocked,:wrong_match_binding unless binding && binding_digest(binding)==document['binding_digest']
        raise Blocked,:tournament_saved_game_disabled if binding.key?('continuation')
      end
      if match && entry_operation?(document)
        return reconcile_entry_operation(record,document,candidate,tournament_id,match)
      end
      is_forfeit=document['kind']=='ordinary-match-forfeit-v3'
      author=is_forfeit ? candidate.fetch('publication_ref').fetch('author').downcase : match && prepared_match(candidate,match)['players'].first['account']
      authorized = author == @owner || document['kind'] == 'ordinary-match-result-v1' && match && match['players'].include?(@owner)
      raise Blocked,:source_changed unless match && candidate['schedule_id']==document.fetch('schedule_id',candidate['schedule_id']) && authorized
      if is_forfeit
        return forfeit_archive(document,candidate,tournament_id,match).resume(id).tap do
          @result_changed.call(candidate.fetch('publication_ref'))
          notify_sports_rankings(candidate,tournament_id,match)
        end
      end
      if document['kind']=='ordinary-match-create-v1'
        bound=read_document(anchor(candidate,tournament_id,match,'binding'),@owner)
        raise Blocked,:creation_unconfirmed unless bound && valid_binding?(bound,candidate,match)
        return record if record['status']=='confirmed'
        return @journal.resolve(id,status:'confirmed',evidence:{'table_id'=>bound['table']['__id'],'native_session_id'=>bound['table']['__live_session_id']},expected_revision:record['revision'])
      end
      kind=document['kind']=='ordinary-match-binding-v1' ? 'binding' : 'result'
      expected=anchor(candidate,tournament_id,match,kind)
      ServerPlanArchive.new(table:@table,journal:@journal,user:-> {account!; @user.call},verify:->(doc,retained) do
        current,current_id=source!
        retained==expected && current==candidate && current_id==tournament_id && doc==document
      end).resume(id).tap do
        @result_changed.call(candidate.fetch('publication_ref')) if %w[forfeit result].include?(kind)
        notify_sports_rankings(candidate,tournament_id,match) if kind == 'result'
      end
    rescue Publication::Invalid=>error
      raise unless error.code==:missing_publication && @completed_source && record
      reconcile_completed_result(record)
    end

    # Expiry cannot authorize another append, but must not discard the ACK of
    # an exact result already stored in full. This fallback only reads and
    # resolves the existing local journal; never resume a missing document part.
    private def reconcile_completed_result(record)
      document=StrictJson.parse(record.fetch('values').fetch('document_json'),max_nesting:12)
      is_forfeit=document['kind']=='ordinary-match-forfeit-v3'
      raise Publication::Invalid,:missing_publication unless is_forfeit || document['kind']=='ordinary-match-result-v1'
      candidate,id=source!(reader:@completed_source)
      match=candidate.fetch('matches').find{|row|row['match_id']==document['match_id'] && row['leg']==document['leg']}
      raise Blocked,:source_changed unless match && document['publication_ref']==candidate['publication_ref'] &&
        document.fetch('schedule_id',candidate['schedule_id'])==candidate['schedule_id']
      author=is_forfeit ? candidate.fetch('publication_ref').fetch('author').downcase : @owner
      raise Blocked,:not_a_match_player unless author==@owner && (is_forfeit || match['players'].include?(@owner))
      expected=anchor(candidate,id,match,is_forfeit ? 'forfeit' : 'result')
      digest=Digest::SHA256.hexdigest(JSON.generate(document)) if is_forfeit
      ServerPlanArchive.new(table:@table,journal:@journal,user:-> {account!;@user.call},document_digest:digest,
        verify:->(value,retained) do
          next false unless retained==expected && value==document
          if is_forfeit
            verify_administrative_intent!(value,candidate,id,match,source:@completed_source)
          else
            current,current_id=source!(reader:@completed_source)
            binding=read_match_binding(candidate,id,match,nil,stop_at:value['binding_digest'])
            raise Blocked,:wrong_match_binding unless binding && valid_binding?(binding,candidate,match)
            raise Blocked,:tournament_saved_game_disabled if binding.key?('continuation')
            validate_bound_result!(value,match,binding)
            current==candidate && current_id==id
          end
        end).reconcile(record.fetch('id')).tap { notify_sports_rankings(candidate,id,match) }
    end
    def close
      thread=@lock.synchronize do
        return if @closing
        @closing=@closed=true
        @thread
      end
      thread&.join(2) unless thread == Thread.current
      release_management unless thread&.alive?
    end

    # Public for deterministic tests of the queue consumer, never a game executor.
    def collect(row, pending: nil)
      binding, candidate, id, match, captured = row
      raise Blocked,:tournament_saved_game_disabled if binding.key?('continuation')
      # The runner already verified this terminal history. Retain its immutable
      # result locally before the first network read, so an outage cannot lose
      # the only completion callback. This grants no permission to publish:
      # the normal archive and recovery paths still revalidate the source.
      result=captured && retain_observed_result(captured,row,pending)
      current, current_id = source!
      raise Blocked, :source_changed unless current == candidate && id == current_id
      documents=match_documents(candidate,id,match)
      return if forfeit_document(candidate,id,match,rows:documents['forfeit'],result_rows:documents['result'])
      return unless read_match_binding(candidate,id,match,binding['creator'])==binding
      result ||= OrdinaryMatchResults.read(repository:@games,registry:@registry,transport:@transport,table:binding['table'],binding:binding)
      return unless result
      result=retain_observed_result(result,row,pending) unless captured
      publish_document(result,anchor(candidate,id,match,'result')) do |document|
        fresh=captured || OrdinaryMatchResults.read(repository:@games,registry:@registry,transport:@transport,table:binding['table'],binding:binding)
        current,current_id=source!
        current==candidate && current_id==id && fresh && document==fresh.merge('publication_ref'=>candidate.fetch('publication_ref'))
      end
      @result_changed.call(candidate.fetch('publication_ref'))
      notify_sports_rankings(candidate,id,match)
    end

    private
    # Only confirmed, canonical receipts reach ranking persistence. A ranking
    # outage must not turn a successfully saved sporting result into a failure.
    def notify_sports_rankings(candidate,id,match)
      return unless @rankings_observer && @registry.build(candidate['game_id']).respond_to?(:sports_ranking_result)
      completed_at = nil
      receipt = forfeit_document(candidate,id,match) { |entry| completed_at = entry.fetch('time') }
      receipt ||= read_result_document(candidate,id,match) { |time| completed_at = time }
      return unless receipt && completed_at.is_a?(Integer) && completed_at.positive?
      people = prepared_match(candidate,match).fetch('players')
      @rankings_observer.call(candidate,match,receipt,people,completed_at)
    rescue StandardError => error
      begin
        Log.warning("Sports tournament ranking handoff failed: #{error.class}") if defined?(Log)
      rescue StandardError
        nil
      end
      nil
    end

    # Called under @lock. No recapture, journal access or network write here.
    def queue_result_retry(job)
      return false unless job && job[:retryable] && !job[:queued] && !@closed
      job[:queued]=true
      job[:retryable]=false
      @jobs << job
      start_worker
      true
    end

    def retain_observed_result(result,row,pending)
      if pending
        @lock.synchronize do
          pending[:row]=(row.first(4)+[result]).freeze
          pending[:retaining]=true
        end
      end
      document=retain_result(result,*row.values_at(1,2,3))
      @lock.synchronize { @result_jobs.delete(pending[:key]) } if pending
      document
    end

    def retain_result(result,candidate,id,match)
      account!
      document=Data.freeze_tree(ServerPlanDocument.copy_document(result.merge('publication_ref'=>candidate.fetch('publication_ref'))))
      key=anchor(candidate,id,match,'result')
      @journal.prepare(kind:'plan_document',intent_id:'ordinary-document:'+key['operation_key'],
        values:key.merge('kind'=>'plan_document','document_json'=>JSON.generate(document)))
      document
    end

    # Called under @lock after admission. Checking for an empty queue and
    # relinquishing this worker slot use the same lock as enqueue/retry, so
    # a result arriving at the drain boundary cannot be left without a worker.
    def start_worker
      return if @thread || @closed
      runtime = @program.class.app_runtime if @program.class.respond_to?(:app_runtime)
      @thread = Thread.new do
        Thread.current.report_on_exception=false
        work = -> do
          loop do
            job=@lock.synchronize do
              if @closed || @jobs.empty?
                @thread=nil if @thread.equal?(Thread.current)
                nil
              else
                @jobs.pop(true)
              end
            end
            break unless job
            failure=nil
            stop=false
            begin
              collect(job.fetch(:row),pending:job)
            rescue StandardError=>error
              failure=error
              # A programming failure must not keep processing faulty work.
              stop=!(error.is_a?(Blocked) || error.is_a?(Publication::Invalid) || error.is_a?(IOError) ||
                  error.is_a?(ServerPlanArchive::Unconfirmed) || error.is_a?(OperationJournal::Error) ||
                  (defined?(EltenLink::Error) && error.is_a?(EltenLink::Error)))
            ensure
              # Publish a retryable job only after this attempt is fully done.
              # UI/runner may immediately requeue it when they read the error.
              @lock.synchronize do
                @closed=true if stop
                if @result_jobs[job[:key]].equal?(job)
                  job[:queued]=false
                  job[:retryable]=!@closed && job[:retaining] && (failure.is_a?(IOError) ||
                    failure.is_a?(OperationJournal::Error) && failure.code==:journal_io_error)
                  @result_jobs.delete(job[:key]) unless job[:retryable]
                end
              end
            end
            @errors << failure if failure && @errors.size<16
            break if stop
          end
        end
        runtime && defined?(Programs) ? Programs.with_runtime(runtime,&work) : work.call
      ensure
        closed_and_idle=@lock.synchronize do
          @thread=nil if @thread.equal?(Thread.current)
          @closed && @thread.nil?
        end
        release_management if closed_and_idle
      end
    end

    def release_management
      managed=@lock.synchronize { value=@managed; @managed=false; value }
      @program.class.release(self) if managed && @program.class.respond_to?(:release)
    end
    def source!(reader:@source)
      account!
      source=reader.call
      account!
      names=source['usernames'] && Data.freeze_tree(Data.copy(source['usernames'],max_bytes:131072,max_nodes:1024))
      [Data.freeze_tree(Data.copy(source.fetch('candidate').reject{|k,_|k=='observed_at'},max_bytes:262144,max_nodes:16384,max_depth:12)),source.fetch('tournament_id'),names]
    end

    def authorize_existing_entry(candidate,match,binding,joined:false)
      @entry_guard&.call(candidate,match,binding)
      true
    rescue Publication::Invalid => error
      # Timing limits forbid a new game, not returning to one already started.
      # Creation/replacement and start_parameters use the strict guard.
      raise unless %i[deadline_passed outside_window].include?(error.code) && @transport && @games
      return true if @transport.game_sessions(binding.fetch('table'),force:true).
        any?{|session|@games.session_id(session)==binding['session_id']}
      # Native history becomes readable only after membership. This permits
      # joining the verified table to inspect it, never creating/starting a game.
      # A failed inspection releases only membership acquired by this call.
      return false unless joined
      raise
    end
    def account!
      value=Data.account(@user.call).downcase
      @changed=true unless value==@owner
      raise Blocked,:account_changed if @changed || @closed
    end
    def anchor(candidate,id,match,kind)
      {'operation_key'=>Digest::SHA256.hexdigest(JSON.generate(['ordinary-match-v1',@journal.backend_identity,candidate['schedule_id'],match['match_id'],match['leg'],kind])),
        'tournament_id'=>id,'publication_digest'=>candidate['publication_digest'],'roster_generation'=>candidate['roster_generation']}
    end
    def read_document(anchor,author,rows:nil)
      account!
      rows ||= ServerDocumentRows.read(@table,where:{'operation_key'=>anchor['operation_key']},author:author,guard:method(:account!))
      rows=ServerDocumentRows.owned(rows,author)
      account!
      rows.empty? ? nil : ServerPlanDocument.decode(rows,anchor:anchor,author:author)
    end

    def match_documents(candidate,id,match)
      keys=%w[creator binding result forfeit].to_h{|kind|[kind,anchor(candidate,id,match,kind)['operation_key']]}
      rows=ServerDocumentRows.read(@table,where:{'operation_key'=>{'in'=>keys.values}},
        guard:method(:account!)).group_by{|row|row['operation_key']}
      keys.transform_values{|key|rows.fetch(key,[])}
    end

    def read_result_document(candidate, id, match, rows: nil, allow_incomplete: false)
      key = anchor(candidate,id,match,'result')
      rows ||= ServerDocumentRows.read(@table,where:{'operation_key'=>key['operation_key']},guard:method(:account!))
      receipts = []
      incomplete = false
      rows.group_by { |row| row['__insertion_user'].to_s.downcase }.each do |author, parts|
        next unless match['players'].include?(author)
        begin
          receipt = ServerPlanDocument.decode(parts,anchor:key,author:author)
          raise Blocked,:invalid_result_receipt unless receipt['kind']=='ordinary-match-result-v1' &&
            receipt['publication_ref']==candidate['publication_ref'] && receipt['match_id']==match['match_id'] && receipt['leg']==match['leg'] &&
            Data.integer?(receipt['session_id'],1) && %w[binding_digest history_digest].all? { |field| receipt[field].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(receipt[field]) } &&
            valid_summary?(receipt['summary'],match)
          canonical=ServerPlanDocument.canonical_rows(parts,anchor:key,author:author)
          receipts << [canonical.map { |row|row['__id'] }.max, receipt, document_time(canonical),canonical.first['document_digest']]
        rescue Publication::Invalid => error
          raise unless error.code == :incomplete_plan_document
          incomplete = true
        end
      end
      raise ServerPlanArchive::Unconfirmed,'Result is incomplete' if receipts.empty? && incomplete && !allow_incomplete
      return nil if receipts.empty?
      receipts.sort_by!(&:first)
      chosen = receipts.first[1]
      sporting = ->(value) { value.slice('binding_digest','session_id','match_id','leg').merge(
        'summary'=>value['summary'].reject { |field,_|field=='event_count' }) }
      raise Blocked,:conflicting_match_results unless receipts.all? { |_,value| sporting.call(value)==sporting.call(chosen) }
      yield receipts.first[2],{'completed_row_id'=>receipts.first[0],'digest'=>receipts.first[3]} if block_given?
      chosen
    end

    def document_time(parts)
      times=parts.map { |row| row['__insertion_time'] }
      times.max if times.all? { |time| Data.integer?(time) }
    end
    def publish_document(document,anchor,&verify)
      begin
        previous=read_document(anchor,@owner)
      rescue Publication::Invalid => error
        raise unless error.code == :incomplete_plan_document
      end
      raise Blocked,:conflicting_document if previous && previous!=document
      return if previous
      ServerPlanArchive.new(table:@table,journal:@journal,user:-> {account!; @user.call},verify:->(doc,retained){account!; retained==anchor && verify.call(doc)}).
        publish(intent_id:'ordinary-document:'+anchor['operation_key'],document:document,anchor:anchor)
    end
    def valid_binding?(binding,candidate,match)
      expected=prepared_match(candidate,match)
      if binding.is_a?(Hash) && binding.key?('continuation')
        marker=binding['continuation']
        return false unless marker.is_a?(Hash) && marker.keys.sort==(%w[archive_id event_count prefix_digest save_checksum]+(marker.key?('start_reserved') ? ['start_reserved'] : [])) &&
          (!marker.key?('start_reserved') || marker['start_reserved']==true) &&
          marker['archive_id'].is_a?(String) && marker['archive_id'].bytesize.between?(1,128) && Data.integer?(marker['event_count']) &&
          %w[prefix_digest save_checksum].all?{|key|marker[key].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(marker[key])}
      end
      return false unless binding.is_a?(Hash) && binding['players'].is_a?(Array) && binding['players'].size==match['players'].size &&
        binding['players'].each_with_index.all?{|person,index|person.is_a?(Hash) && person.keys.sort==expected['players'][index].keys.sort &&
          person['account'].is_a?(String) && person['username'].is_a?(String) && person['username'].downcase==person['account'] && person['seat']==index} &&
        binding['table'].is_a?(Hash) && binding['table']['owner'].is_a?(String) && Data.integer?(binding['table']['__id'],1) &&
        binding['table']['__live_session_id'].is_a?(String) && !binding['table']['__live_session_id'].empty?
      return false if binding.key?('entry_version') && binding['entry_version']!=ENTRY_VERSION
      return false if binding.key?('result_policy') && ![GameResult::RANKING_RESULT_POLICY, *GameResult::SELECTED_SMALL_POLICIES].include?(binding['result_policy'])
      if binding['entry_version']==ENTRY_VERSION
        marker=candidate.slice('publication_ref','schedule_id').merge(match.slice('match_id','leg'))
        return false unless binding['table']['tournament_match']==marker ||
          binding.key?('continuation') && !binding['table'].key?('tournament_match')
      end
      binding['publication_ref']==candidate['publication_ref'] && binding['kind']=='ordinary-match-binding-v1' && binding['schedule_id']==candidate['schedule_id'] && binding['match_id']==match['match_id'] && binding['leg']==match['leg'] &&
        (binding['entry_version']==ENTRY_VERSION ? match['players'].include?(binding['creator']) : binding['creator']==expected['players'].first['account']) && binding['game_id']==candidate['game_id'] && binding['options']==expected['options'] &&
        Data.integer?(binding['session_id'],1) && binding['session_id']<=2_000_000_000 &&
        binding['players']==expected['players'] && binding['table']['owner'].downcase==binding['creator'] && binding['table']['game']==candidate['game_id']
    end

    def supported_match?(candidate,match)
      return false unless match.is_a?(Hash) && match['players'].is_a?(Array) && match['players'].size.between?(2,8)
      if match.key?('unit_ids')
        prepared_match(candidate,match)
        return true
      end
      return false if candidate['format']=='groups_knockout' && match['players'].size!=2
      game=@registry.build(candidate['game_id'])
      game && game.tournament_capabilities(options:candidate['game_options'])[:player_counts].include?(match['players'].size) &&
        game.team_size(candidate['game_options'],player_count:match['players'].size)==0
    rescue Publication::Invalid,KeyError
      false
    end

    def prepared_match(candidate,match)
      return OrdinaryTeamPlayers.prepare(candidate:candidate,match:match,registry:@registry) if match.key?('unit_ids')
      {'options'=>candidate['game_options'],'players'=>MatchOrder.players(candidate['matches'],match).each_with_index.map{|account,seat|{'account'=>account,'username'=>account,'seat'=>seat}}}
    end

    def valid_summary?(summary,match)
      return false unless summary.is_a?(Hash) && (summary.keys-%w[participants winners draw scores event_count score_order places forfeits]).empty? &&
        summary['participants']==(match['unit_ids'] || match['players']).sort && summary['winners'].is_a?(Array) && summary['winners'].uniq==summary['winners'] &&
        (summary['winners']-summary['participants']).empty? && [true,false].include?(summary['draw']) &&
        (summary['draw'] ? summary['winners'].empty? : !summary['winners'].empty?) && Data.integer?(summary['event_count']) &&
        (!summary.key?('score_order') || %w[higher lower].include?(summary['score_order']))
      if summary.key?('places')
        groups=summary['places']
        return false unless groups.is_a?(Array) && !groups.empty? && groups.all? { |group| group.is_a?(Array) && !group.empty? && group.all? { |unit| unit.is_a?(String) } } &&
          groups.flatten.sort==summary['participants'] && groups.first.sort==summary['winners'].sort && summary['draw']==false
      end
      if summary.key?('forfeits')
        forfeits=summary['forfeits']
        return false unless forfeits.is_a?(Array) && forfeits.uniq==forfeits && (forfeits-summary['participants']).empty? &&
          (forfeits & summary['winners']).empty? && summary.key?('places')
      end
      scores=summary['scores']
      scores.nil? || (scores.is_a?(Hash) && scores.keys.sort==summary['participants'] &&
        scores.values.all?{|value|value.is_a?(Integer) || value.is_a?(Float) && value.finite?})
    end

    module WorkerReads
      %i[open_match attach_table start_parameters entry_status result_view collect reconcile
        saved_match_reference check_saved_match prepare_saved_match start_saved_match bind_resumed_match award_forfeit forfeit_preview confirm_forfeit].each do |name|
        define_method(name) do |*args,**keywords,&block|
          @read_scope.call { super(*args,**keywords,&block) }
        end
      end
    end
    prepend WorkerReads
  end
end
