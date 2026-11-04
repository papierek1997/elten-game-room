# encoding: UTF-8
require_relative 'proposal_notice'
require_relative 'local_registration_time'
require_relative 'registration_projection'

module GameRoomTournaments
  # Informational event only. No player readiness, reservation or game action.
  class TournamentStartNotice
    TYPE='game_room.tournament_started'.freeze
    Data=Publication::Data
    FIELDS=%w[version backend_identity publication_ref recipient event_id].freeze
    DESCRIPTION_FIELDS=%w[title game].freeze

    def self.metadata(value)
      value=Data.copy(value,max_bytes:2048,max_nodes:64,max_depth:4)
      raise Publication::Invalid,:invalid_start_notice unless value.is_a?(Hash) &&
        ((value['version']==1 && value.keys.sort==FIELDS.sort) ||
          (value['version']==2 && value.keys.sort==(FIELDS+DESCRIPTION_FIELDS).sort))
      if value['version']==2
        Data.text!(value['title'],bytes:1024)
        Data.text!(value['game'],bytes:128)
      end
      Data.text!(value['backend_identity'],bytes:256)
      reference=value['publication_ref']
      raise Publication::Invalid,:invalid_start_notice unless reference.is_a?(Hash) && reference.keys.sort==%w[author publication_key]
      reference['author']=Data.account(reference['author']).downcase
      Data.key!(reference['publication_key'])
      value['recipient']=Data.account(value['recipient']).downcase
      ServerPlanDocument.digest!(value['event_id'])
      expected=Digest::SHA256.hexdigest(JSON.generate(['tournament-start-v1',value['backend_identity'],reference]))
      raise Publication::Invalid,:invalid_start_notice unless value['event_id']==expected
      Data.freeze_tree(value)
    end

    def initialize(source:,context:,clock:,registry:)
      @source,@context,@clock,@registry=source,context,clock,registry
      @scope=scope
      @changed=false
    end

    def notices(publication_ref:,addressed:false)
      current!
      reference={'author'=>Data.account(publication_ref.fetch('author')).downcase,'publication_key'=>Data.key!(publication_ref.fetch('publication_key'))}
      proof=source!(reference,delivery:true)
      raise ProposalNotice::Stale,'Not tournament organizer' unless proof['sender']==@scope['account']
      proof['participants'].map do |person|
        metadata=self.class.metadata({'version'=>2,'backend_identity'=>@scope['backend_identity'],'publication_ref'=>reference,'recipient'=>person,
          'title'=>proof['title'],'game'=>proof['game'],
          'event_id'=>Digest::SHA256.hexdigest(JSON.generate(['tournament-start-v1',@scope['backend_identity'],reference]))})
        addressed ? [metadata,RegistrationProjection.delivery_name(proof['usernames'],person)].freeze : metadata
      end.freeze
    end

    def inspect(metadata:,sender:,delivery:false)
      current!
      notice=self.class.metadata(metadata)
      sender=Data.account(sender).downcase
      unless notice['backend_identity']==@scope['backend_identity'] && (delivery ? sender==@scope['account'] : notice['recipient']==@scope['account'])
        raise ProposalNotice::Stale,'Different start recipient or backend'
      end
      proof=source!(notice['publication_ref'],delivery:delivery)
      raise ProposalNotice::Stale,'Not registered or wrong sender' unless proof['sender']==sender && proof['participants'].include?(notice['recipient'])
      if notice['version']==2 && notice.slice(*DESCRIPTION_FIELDS)!=proof.slice(*DESCRIPTION_FIELDS)
        raise ProposalNotice::Stale,'Start description changed'
      end
      current!
      Data.freeze_tree(proof.merge('metadata'=>notice))
    end

    def presentable?(proof)
      current!
      now=now!
      proof['metadata']['recipient']==@scope['account'] && proof['starts_at']<=now && !expired?(proof['expires_at'])
    rescue ProposalNotice::Stale,Publication::Invalid
      false
    end

    def assert_context!;current!;end

    def delivery_identity(notice)
      notice.slice(*FIELDS).merge('version'=>1)
    end

    def expired?(deadline)
      current!
      return false if deadline==0
      now!>=deadline
    end

    def retention_deadline
      current!
      0
    end

    # These are retained event records, not still-pending invitations. A
    # later rename/removal must not withdraw an authenticated historical text.
    def retain_stale_notice?(metadata,sender:)
      current!
      notice=self.class.metadata(metadata)
      notice['version']==2 && notice['recipient']==@scope['account'] &&
        notice['backend_identity']==@scope['backend_identity'] &&
        Data.account(sender).downcase==notice['publication_ref']['author']
    rescue ProposalNotice::Stale,Publication::Invalid
      false
    end

    def refresh_on_change?(_metadata,proof:nil)
      false
    end
    # Authenticated sender + scoped event metadata describe an event, not
    # permission to play or to announce it again. No network read on list focus.
    def description(metadata:,sender:)
      current!
      notice=self.class.metadata(metadata)
      return unless notice['backend_identity']==@scope['backend_identity'] && notice['recipient']==@scope['account'] &&
        Data.account(sender).downcase==notice['publication_ref']['author']
      notice.slice(*DESCRIPTION_FIELDS) if notice['version']==2
    end
    def remaining_seconds(closes)
      current!
      return 0 if closes==0
      seconds=closes-now!
      raise ProposalNotice::Stale,'Start notice expired' unless seconds>0
      seconds
    end

    private

    def source!(reference,delivery:)
      raise ProposalNotice::Unavailable,'Start notice source is not connected' unless @source
      value=Data.copy(@source.call(reference),max_bytes:262_144,max_nodes:16_384,max_depth:12)
      current!
      unless value.is_a?(Hash) && (value.keys-['usernames']).sort==%w[complete participants publication] && value['complete']==true
        raise ProposalNotice::Stale,'Incomplete start evidence'
      end
      publication=Publication.project(rows:[value['publication']],registry:@registry,complete:true)
      raise ProposalNotice::Stale,'Invalid start publication' unless publication['diagnostics'].empty? && publication['announcements'].size==1
      row=publication['announcements'].first
      sender=Data.account(row['__insertion_user']).downcase
      raise ProposalNotice::Stale,'Different publication' unless sender==reference['author'] && row['publication_key']==reference['publication_key']
      people=value['participants']
      unless people.is_a?(Array) && people.size.between?(1,256) && people.uniq==people && people.all?{|person|Data.account(person).downcase==person}
        raise ProposalNotice::Stale,'Invalid registered roster'
      end
      starts=TournamentTiming.starts_at(row)
      raise ProposalNotice::Stale,'Tournament not started' unless starts
      now=now!
      unless TournamentTiming.registration_closed?(row,now) && starts<=now
        raise ProposalNotice::Stale,'Not a current tournament start'
      end
      Data.freeze_tree({'sender'=>sender,'title'=>row['title'],'game'=>row['game'],'participants'=>people,
        'usernames'=>value['usernames'],
        'starts_at'=>starts,'expires_at'=>0,'publication_digest'=>Digest::SHA256.hexdigest(JSON.generate(row.slice(*Publication::COLUMNS)))})
    end

    def now!
      value=@clock.call
      raise Publication::Invalid,:invalid_clock unless Data.integer?(value)
      value
    end
    def scope
      value=@context.call
      unless value.is_a?(Hash) && value.keys.sort==%w[account account_epoch backend_identity] && value.values.all?{|part|Data.text?(part) && !part.empty?}
        raise ProposalNotice::Unavailable,'Start notice context unavailable'
      end
      Data.freeze_tree(Data.copy(value.merge('account'=>Data.account(value['account']).downcase)))
    end
    def current!
      @changed=true unless scope==@scope
      raise ProposalNotice::Stale,'Account or backend changed' if @changed
    rescue Publication::Invalid,ProposalNotice::Unavailable
      @changed=true
      raise ProposalNotice::Stale,'Account or backend unavailable'
    end
  end
end
