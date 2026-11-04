# encoding: UTF-8
require_relative 'tournament_start_notice'
require_relative 'schedule_source'
require_relative 'phase_description'

module GameRoomTournaments
  # Registration invitations and final standings are information, never
  # participant consent or permission to create/start a table.
  class TournamentEventNotice < TournamentStartNotice
    TYPES={'registration'=>'game_room.tournament_registration','finished'=>'game_room.tournament_finished',
      'phase_finished'=>'game_room.tournament_phase_finished', 'partnership'=>'game_room.tournament_partnership'}.freeze
    LIFETIME=7*86400
    FINISH_FIELDS=%w[place winners team].freeze

    def self.metadata(raw)
      finish=raw.is_a?(Hash) && raw['version']==2 && raw['kind']=='finished'
      value=Data.copy(raw,max_bytes:finish ? 65_536 : 2048,max_nodes:finish ? 1024 : 64,max_depth:4)
      fields=FIELDS+DESCRIPTION_FIELDS+%w[kind issued_at]
      fields=fields+['phase_id'] if value.is_a?(Hash) && value['kind']=='phase_finished'
      fields+=%w[change_key change_index] if value.is_a?(Hash) && value['kind']=='partnership'
      permanent = value.is_a?(Hash) && value['version'] == 2 && value['kind'] == 'registration'
      fields += ['invitation_key'] if permanent
      fields += FINISH_FIELDS if finish
      unless value.is_a?(Hash) && value.keys.sort==fields.sort &&
          (value['version']==1 || permanent || finish) && TYPES.key?(value['kind']) && Data.integer?(value['issued_at'],1)
        raise Publication::Invalid,:invalid_tournament_notice
      end
      Data.text!(value['title'],bytes:1024)
      Data.text!(value['game'],bytes:128)
      Data.text!(value['backend_identity'],bytes:256)
      reference=ScheduleSource.reference(value['publication_ref'])
      value['publication_ref']=reference
      value['recipient']=Data.account(value['recipient']).downcase
      Data.key!(value['phase_id']) if value['kind']=='phase_finished'
      if value['kind']=='partnership'
        Data.key!(value['change_key'])
        raise Publication::Invalid,:invalid_tournament_notice unless Data.integer?(value['change_index']) && value['change_index']<=511
      end
      Data.key!(value['invitation_key']) if permanent
      if finish
        valid_place=value['place'].nil? || Data.integer?(value['place'],1) && value['place']<=256
        unless valid_place && [true,false].include?(value['team']) && value['winners'].is_a?(Array) &&
            value['winners'].size<=256 && value['winners'].uniq==value['winners']
          raise Publication::Invalid,:invalid_tournament_notice
        end
        value['winners'].each { |name| Data.text!(name,bytes:512) }
      end
      expected=event_id(value)
      raise Publication::Invalid,:invalid_tournament_notice unless value['event_id']==expected
      Data.freeze_tree(value)
    end

    def self.event_id(value)
      identity=['tournament-event-v1',value['kind'],value['backend_identity'],value['publication_ref']]
      identity << (value['version'] == 2 ? value['invitation_key'] : value['issued_at']) if value['kind']=='registration'
      identity << value['phase_id'] if value['kind']=='phase_finished'
      identity.concat(value.values_at('change_key','change_index')) if value['kind']=='partnership'
      Digest::SHA256.hexdigest(JSON.generate(identity))
    end

    def initialize(kind:,**arguments)
      raise ArgumentError,'Unknown tournament notice' unless TYPES.key?(kind)
      @kind=kind
      super(**arguments)
    end

    def notices(publication_ref:,recipient:nil,phase_id:nil,addressed:false,invitation_key:nil,change_key:nil,change_index:nil)
      current!
      reference=ScheduleSource.reference(publication_ref)
      proof=source!(reference,delivery:true,phase_id:phase_id,invitation_key:invitation_key,recipient:recipient,change_key:change_key,change_index:change_index)
      raise ProposalNotice::Stale,'Not tournament organizer' unless proof['sender']==@scope['account']
      people=@kind=='registration' ? [Data.account(recipient).downcase] : proof.fetch('recipients',proof['participants'])
      people.map do |person|
        check_recipient!(proof,person)
        metadata={'version'=>1,'kind'=>@kind,'issued_at'=>proof['issued_at'],'backend_identity'=>@scope['backend_identity'],
          'publication_ref'=>reference,'recipient'=>person,'title'=>proof['title'],'game'=>proof['game'],
          'event_id'=>nil}
        metadata['phase_id']=phase_id if @kind=='phase_finished'
        metadata.merge!('change_key'=>change_key,'change_index'=>change_index) if @kind=='partnership'
        metadata.merge!('version'=>2,'invitation_key'=>invitation_key) if @kind=='registration' && invitation_key
        if @kind=='finished'
          metadata.merge!('version'=>2,'place'=>proof.fetch('places')[person],
            'winners'=>proof.fetch('winners'),'team'=>proof.fetch('team_mode'))
        end
        metadata['event_id']=self.class.event_id(metadata)
        metadata=self.class.metadata(metadata)
        name=@kind=='registration' ? Data.account(recipient) : RegistrationProjection.delivery_name(proof['usernames'],person) if addressed
        addressed ? [metadata,name].freeze : metadata
      end.freeze
    end

    def inspect(metadata:,sender:,delivery:false)
      current!
      notice=self.class.metadata(metadata)
      sender=Data.account(sender).downcase
      unless notice['kind']==@kind && notice['backend_identity']==@scope['backend_identity'] &&
          (delivery ? sender==@scope['account'] : notice['recipient']==@scope['account'])
        raise ProposalNotice::Stale,'Different tournament notice scope'
      end
      proof=source!(notice['publication_ref'],delivery:delivery,issued_at:notice['issued_at'],phase_id:notice['phase_id'],
        invitation_key:notice['invitation_key'],recipient:notice['recipient'],change_key:notice['change_key'],change_index:notice['change_index'])
      raise ProposalNotice::Stale,'Wrong organizer or changed description' unless sender==proof['sender'] &&
        (notice['version']==2 || notice.slice(*DESCRIPTION_FIELDS)==proof.slice(*DESCRIPTION_FIELDS))
      check_recipient!(proof,notice['recipient'])
      if @kind=='finished' && notice['version']==2
        expected={'place'=>proof.fetch('places')[notice['recipient']],
          'winners'=>proof.fetch('winners'),'team'=>proof.fetch('team_mode')}
        raise ProposalNotice::Stale,'Tournament result description changed' unless notice.slice(*FINISH_FIELDS)==expected
      end
      current!
      Data.freeze_tree(proof.merge('metadata'=>notice))
    end

    def description(metadata:,sender:)
      current!
      notice=self.class.metadata(metadata)
      if @kind=='partnership'
        return unless notice['backend_identity']==@scope['backend_identity'] && notice['recipient']==@scope['account']
        # Unlike organizer notices, a proposal may come from any entrant. Only
        # the asynchronously verified transition supplies its description.
        return nil
      end
      return unless notice['kind']==@kind && notice['backend_identity']==@scope['backend_identity'] &&
        notice['recipient']==@scope['account'] && Data.account(sender).downcase==notice['publication_ref']['author']
      notice.slice(*(DESCRIPTION_FIELDS+(@kind=='finished' ? FINISH_FIELDS : [])))
    end

    def delivery_identity(notice)
      identity=notice.slice(*(FIELDS+%w[kind phase_id change_key change_index]))
      identity['version']=1 if notice['kind']=='finished'
      identity
    end

    def retention_deadline
      current!
      @kind=='finished' ? 0 : now!+LIFETIME
    end

    def retain_stale_notice?(metadata,sender:)
      @kind=='finished' && super
    end

    def refresh_on_change?(_metadata,proof:nil)
      @kind=='registration' || @kind=='partnership' && (proof.nil? || proof.dig('change','kind')=='requested')
    end

    def presentable?(proof)
      if @kind == 'registration' && proof['metadata']['version'] == 2
        assert_context!
        return proof['metadata']['recipient'] == @scope['account'] && !expired?(proof['expires_at'])
      end
      super
    rescue ProposalNotice::Stale, Publication::Invalid
      false
    end

    private

    def check_recipient!(proof,person)
      if @kind=='partnership'
        raise ProposalNotice::Stale,'Not a partnership recipient' unless proof['recipients'].include?(person)
      elsif @kind=='registration'
        raise ProposalNotice::Stale,'Already registered or tournament full' if proof['participants'].include?(person) || proof['full']
      else
        raise ProposalNotice::Stale,'Not a participant' unless proof['participants'].include?(person)
      end
    end

    def source!(reference,delivery:,issued_at:nil,phase_id:nil,invitation_key:nil,recipient:nil,change_key:nil,change_index:nil)
      raise ProposalNotice::Unavailable,'Tournament notice source is not connected' unless @source
      raw=@kind=='phase_finished' ? @source.call(reference,phase_id) : @source.call(reference)
      value=Data.copy(raw,max_bytes:@kind=='partnership' ? 1_048_576 : 262_144,max_nodes:32_768,max_depth:12)
      current!
      row=value['publication']
      raise ProposalNotice::Stale,'Tournament unavailable' unless row && row['__insertion_user'].downcase==reference['author'] && row['publication_key']==reference['publication_key']
      people=value.fetch('people')
      unless people.is_a?(Array) && people.size.between?(1,256) && people.uniq==people && people.all?{|person|Data.account(person).downcase==person}
        raise ProposalNotice::Stale,'Invalid registered roster'
      end
      now=now!
      raise ProposalNotice::Stale,'Notice from the future' if issued_at && issued_at>now+5
      proof={'sender'=>reference['author'],'title'=>row['title'],'game'=>row['game'],'participants'=>people,
        'usernames'=>value['usernames'],
        'publication_digest'=>RegistrationProjection.publication_generation(row)}
      if @kind=='partnership'
        change=value.fetch('partner_changes',[]).find { |item| item['key']==change_key && item['index']==change_index }
        raise ProposalNotice::Stale,'Partnership change unavailable' unless change
        if change['kind']=='requested'
          request=value.fetch('pair_requests',[]).find { |item| item['from']==change['from'] && item['to']==change['to'] && item['key']==change['request_key'] }
          raise ProposalNotice::Stale,'Partnership proposal is no longer current' unless request && !TournamentTiming.started?(row,now)
        end
        proof['sender']=change['author']
        proof['change']=change
        affected=%w[requested cancelled declined].include?(change['kind']) ? [change['to']] : change.values_at('from','to')
        proof['recipients']=affected.uniq.reject { |person| person==change['author'] }
        proof['usernames']=(proof['usernames'] || {}).merge(change['from']=>change['from_name'],change['to']=>change['to_name'])
        proof['starts_at']=proof['issued_at']=change.fetch('time')
        raise ProposalNotice::Stale,'Partnership change time changed' if issued_at && issued_at!=proof['issued_at']
        proof['expires_at']=proof['issued_at']+LIFETIME
      elsif @kind=='registration'
        raise ProposalNotice::Stale,'Registration not open' unless TournamentTiming.registration_open?(row,now)
        settings=JSON.parse(row['settings_json'])
        proof['full']=!!(settings['participant_limit'] && value.fetch('members').size>=settings['participant_limit'])
        proof['starts_at']=row['registration_opens_at']
        proof['issued_at']=issued_at || now
        if invitation_key
          person=Data.account(recipient).downcase
          entry=value.fetch('invitations',[]).find { |item| item['account']==person && item['operation_key']==invitation_key && item['status']=='pending' && !item['resolved'] }
          raise ProposalNotice::Stale,'Invitation is no longer pending' unless entry
          proof['issued_at']=entry.fetch('invited_at')
          raise ProposalNotice::Stale,'Invitation changed' if issued_at && issued_at!=proof['issued_at']
          proof['expires_at']=TournamentTiming.closes_at(row) || 0
        else
          proof['expires_at']=[proof['issued_at']+LIFETIME,TournamentTiming.closes_at(row)].compact.min
        end
      elsif @kind=='phase_finished'
        transition=value['transition']
        raise ProposalNotice::Stale,'Phase not completed' unless transition && transition['phase_id']==phase_id && Data.integer?(transition['completed_at'],1)
        proof['starts_at']=proof['issued_at']=transition['completed_at']
        raise ProposalNotice::Stale,'Phase completion changed' if issued_at && issued_at!=proof['issued_at']
        proof['expires_at']=proof['issued_at']+LIFETIME
        proof.merge!(transition.slice('phase','next_phase'))
      else
        results=value.fetch('results')
        raise ProposalNotice::Stale,'Tournament not finished' unless results['completed']==true && Data.integer?(results['completed_at'],1)
        proof['starts_at']=results['completed_at']
        proof['issued_at']=results['completed_at']
        raise ProposalNotice::Stale,'Completion changed' if issued_at && issued_at!=proof['issued_at']
        proof['expires_at']=0
        proof['winners']=value.fetch('winners')
        proof['places']=value.fetch('places')
        proof['team_mode']=value.fetch('team_mode')
      end
      raise ProposalNotice::Stale,'Tournament notice expired' unless proof['expires_at']==0 || now<proof['expires_at']
      Data.freeze_tree(Data.copy(proof,max_bytes:262_144,max_nodes:16384,max_depth:12))
    end
  end
end
