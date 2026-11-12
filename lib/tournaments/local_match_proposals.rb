require_relative 'local_dispatch_contract'

module GameRoomTournaments
  # Shares the execution storage lock. A proposal is not a table reservation.
  module LocalMatchProposals
    module_function
    def key(candidate); JSON.generate(candidate.values_at('match_id','leg')); end
    def token(intent,id,row)
      Digest::SHA256.hexdigest(JSON.generate([intent,id,row['players'],row['revisions'],row['window_id']]))
    end
    def rows(document,intent)
      document['dispatch']['proposals'] ||= {}
      document['dispatch']['proposals'][intent] ||= {}
    end
    def prepare(document:,intent:,candidate:,now:)
      people=candidate['players']
      pending=rows(document,intent)
      id=key(candidate)
      prior=pending[id]
      return prior if prior
      raise CoordinationContract::Blocked,:participants_busy if pending.values.any?{|row|(row['players'] & people).any?}
      unless people.all?{|account|LocalDispatchContract.ready(document,intent,account,now)['state']=='ready'}
        raise CoordinationContract::Blocked,:participants_unavailable
      end
      pending[id]={'players'=>people,'accepted'=>[],'window_id'=>candidate['window_id'],'revisions'=>people.to_h{|account|[account,document['dispatch']['availability'][intent][account]['revision']]}}
    end
    def respond(document:,intent:,actor:,accept:,now:,expected:nil,require_expected:false)
      pending=rows(document,intent)
      pair=pending.find{|_key,row|row['players'].include?(actor)}
      raise CoordinationContract::Blocked,:invitation_required unless pair
      id,row=pair
      raise CoordinationContract::Blocked,:proposal_changed if (require_expected || expected) && expected!=token(intent,id,row)
      validate_current!(document,intent,row,now)
      if accept
        row['accepted']=(row['accepted']+[actor]).uniq
      else
        availability=document['dispatch']['availability'][intent][actor]
        availability['available']=false
        availability['revision']+=1
        pending.delete(id)
      end
      accept && row['accepted'].sort==row['players'].sort ? :confirmed : accept ? :awaiting_consent : :declined
    end
    def validate_current!(document,intent,row,now)
      unless row['players'].all?{|account|LocalDispatchContract.ready(document,intent,account,now)['state']=='ready' && document['dispatch']['availability'][intent][account]['revision']==row['revisions'][account]}
        raise CoordinationContract::Blocked,:availability_changed
      end
    end
    def withdraw(document,intent,actor)
      document.dig('dispatch','proposals',intent)&.delete_if{|_key,row|row['players'].include?(actor)}
    end
    def prune(document,intent,now)
      pending=document.dig('dispatch','proposals',intent)
      return false unless pending
      matches=document['records'][intent]['evidence']['plan']['matches']
      size=pending.size
      pending.delete_if do |id,row|
        fixture=JSON.parse(id)
        match=matches.find{|candidate|candidate.values_at('match_id','leg')==fixture}
        window=match && match['windows'].find{|value|value['id']==row['window_id']}
        readiness=row['players'].all?{|account|LocalDispatchContract.ready(document,intent,account,now)['state']=='ready' && document['dispatch']['availability'][intent][account]['revision']==row['revisions'][account]}
        claimed=document['executions'].values.any?{|execution|execution['record_intent']==intent && execution['request'].values_at('match_id','leg')==fixture && (execution['result'] || execution['operations'].key?('reserve'))}
        !readiness || !window || now<window['opens'] || now>=window['closes']-1 || claimed
      end
      pending.size!=size
    end
    def validate!(document)
      root=document.dig('dispatch','proposals')
      return unless root
      raise Publication::Invalid,:sandbox_corrupt unless root.is_a?(Hash) && root.size<=document['records'].size
      root.each do |intent,pending|
        roster=document.dig('records',intent,'evidence','source','roster')&.map{|row|row['account']}
        raise Publication::Invalid,:sandbox_corrupt unless roster && pending.is_a?(Hash) && pending.size<=128
        occupied=[]
        pending.each do |id,row|
          fixture=JSON.parse(id)
          valid=row.is_a?(Hash) && (row.keys-['window_id']).sort==%w[accepted players revisions] && row['players'].is_a?(Array) && row['players'].size.between?(2,8) &&
            row['players'].uniq==row['players'] && (row['players']-roster).empty? && row['accepted'].is_a?(Array) && row['accepted'].uniq==row['accepted'] &&
            (row['accepted']-row['players']).empty? && row['revisions'].is_a?(Hash) && row['revisions'].keys.sort==row['players'].sort &&
            row['revisions'].values.all?{|revision|revision.is_a?(Integer) && revision>=1} && fixture.is_a?(Array) && fixture.size==2
          match=document['records'][intent]['evidence']['plan']['matches'].find{|candidate|candidate.values_at('match_id','leg')==fixture}
          valid &&= match && match['players'].map{|person|person['account']}==row['players']
          valid &&= !row.key?('window_id') || match['windows'].any?{|window|window['id']==row['window_id']}
          raise Publication::Invalid,:sandbox_corrupt unless valid && (occupied & row['players']).empty?
          occupied.concat(row['players'])
        end
      end
    rescue JSON::ParserError
      raise Publication::Invalid,:sandbox_corrupt
    end
  end
end
