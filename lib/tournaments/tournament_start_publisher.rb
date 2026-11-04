require_relative 'tournament_start_notice'

module GameRoomTournaments
  class TournamentStartPublisher
    LIMIT=512
    def initialize(service:,sender:,transaction:,send:)
      @service,@sender,@transaction,@send=service,sender,transaction,send
    end
    def deliver(metadata:)
      sender=Publication::Data.account(@sender.call).downcase
      proof=@service.inspect(metadata:metadata,sender:sender,delivery:true)
      notice=proof['metadata']
      key=delivery_key(sender,notice)
      descriptor={'sender'=>sender,'metadata'=>notice}
      claimed=false
      full=false
      previous=nil
      @transaction.call do |state|
        validate!(state)
        fallback=@service.retention_deadline
        state['operations'].each_value{|entry|entry['expires_at'] ||= fallback}
        state['operations'].delete_if{|_,entry|@service.expired?(entry['expires_at'])}
        if (entry=state['operations'][key])
          prior=entry.fetch('descriptor')
          same_event=Publication::Data.account(prior.fetch('sender')).downcase==sender &&
            @service.delivery_identity(@service.class.metadata(prior.fetch('metadata')))==@service.delivery_identity(notice)
          raise ProposalNotice::Stale,'Start delivery changed' unless same_event
          previous=entry['state']
        else
          if state['operations'].size>=LIMIT
            full=true
          else
            state['operations'][key]={'descriptor'=>descriptor,'state'=>'attempted','expires_at'=>proof['expires_at']}
            claimed=true
          end
        end
      end
      raise ProposalNotice::Unavailable,'Start journal limit reached' if full
      return previous=='sent' ? :sent : :confirmation_pending unless claimed
      unless @service.inspect(metadata:notice,sender:sender,delivery:true)==proof && Publication::Data.account(@sender.call).downcase==sender
        raise ProposalNotice::Stale,'Start source changed before delivery'
      end
      raise ProposalNotice::Unavailable,'Start delivery not confirmed' unless @send.call(notice,proof['expires_at'])==true
      @service.assert_context!
      @transaction.call do |state|
        validate!(state)
        entry=state['operations'][key]
        raise ProposalNotice::Stale,'Start journal changed' unless entry && entry['descriptor']==descriptor
        entry['state']='sent'
      end
      :sent
    end
    private
    def delivery_key(sender,notice)
      # Adding display fields must not authorize a second send of an already
      # attempted event, including attempts retained by the previous format.
      identity=@service.delivery_identity(notice)
      Digest::SHA256.hexdigest(JSON.generate([sender,Publication::Data.copy(identity)]))
    end
    def validate!(state)
      unless state.is_a?(Hash) && state.keys.sort==%w[operations version] && state['version']==1 && state['operations'].is_a?(Hash) && state['operations'].size<=LIMIT
        raise ProposalNotice::Unavailable,'Start journal corrupt'
      end
      state['operations'].each do |key,entry|
        ServerPlanDocument.digest!(key)
        unless entry.is_a?(Hash) && [%w[descriptor state],%w[descriptor expires_at state]].include?(entry.keys.sort) &&
            (!entry.key?('expires_at') || Publication::Data.integer?(entry['expires_at'])) && %w[attempted sent].include?(entry['state']) &&
            entry['descriptor'].is_a?(Hash) && entry['descriptor'].keys.sort==%w[metadata sender]
          raise ProposalNotice::Unavailable,'Start journal corrupt'
        end
        notice=@service.class.metadata(entry['descriptor']['metadata'])
        sender=Publication::Data.account(entry['descriptor']['sender']).downcase
        raise ProposalNotice::Unavailable,'Start journal corrupt' unless key==delivery_key(sender,notice)
      end
    end
  end
end
