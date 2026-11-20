# encoding: UTF-8
require_relative 'tournament_start_publisher'
require_relative 'proposal_notice_inbox'
require_relative 'proposal_notice_journal'
require_relative 'tournament_event_notice'
require_relative '../game_room_notifications'

module GameRoomTournaments
  module TournamentStartRuntime
    using GameRoomLocalization::Translations
    # Explicit application composition only. No inferred remote reader or timer.
    def configure_tournament_starts(source:,context:,clock:,registry:)
      service=TournamentStartNotice.new(source:source,context:context,clock:clock,registry:registry)
      stop_tournament_starts
      @tournament_start_service=service
      @tournament_start_registry=registry
      @tournament_start_inbox=ProposalNoticeInbox.new(service:service,metadata:TournamentStartNotice.method(:metadata),
        worker:GameRoomBackground::Work.new(runtime:app_runtime))
    end
    def stop_tournament_starts
      @tournament_start_inbox&.close
      @tournament_start_inbox=@tournament_start_service=nil
      @tournament_event_inboxes&.each_value(&:close)
      @tournament_event_inboxes=@tournament_event_services=nil
    end

    def configure_tournament_events(source:,context:,clock:,registry:)
      @tournament_event_services={}
      @tournament_event_inboxes={}
      TournamentEventNotice::TYPES.each_key do |kind|
        service=TournamentEventNotice.new(kind:kind,source:->(reference,phase_id=nil){source.call(reference,kind,phase_id)},context:context,clock:clock,registry:registry)
        @tournament_event_services[kind]=service
        @tournament_event_inboxes[kind]=ProposalNoticeInbox.new(service:service,metadata:TournamentEventNotice.method(:metadata),
          worker:GameRoomBackground::Work.new(runtime:app_runtime))
      end
    end

    def send_tournament_event(kind:,publication_ref:,recipient:nil,phase_id:nil,invitation_key:nil,change_key:nil,change_index:nil)
      service=@tournament_event_services&.fetch(kind)
      raise ProposalNotice::Unavailable,'Tournament notices are not connected' unless service
      account=Publication::Data.account(Session.name).downcase
      notices=service.notices(publication_ref:publication_ref,recipient:recipient,phase_id:phase_id,addressed:true,invitation_key:invitation_key,change_key:change_key,change_index:change_index)
      journal=tournament_notice_journal(account:account,notice:notices.first.first,kind:kind) unless notices.empty?
      notices.map do |notice,delivery_name|
        TournamentStartPublisher.new(service:service,sender:-> {Session.name},transaction:journal.method(:update),
          send:->(metadata,closes){GameRoomNotifications.deliver(self,delivery_name,type:TournamentEventNotice::TYPES.fetch(kind),metadata:metadata,
            expires_in:service.remaining_seconds(closes))}).deliver(metadata:notice)
      end
    end

    # Finite worker operation. One local durable attempt per recipient/event.
    def send_tournament_start_notices(publication_ref:)
      service=@tournament_start_service
      raise ProposalNotice::Unavailable,'Tournament starts are not connected' unless service
      account=Publication::Data.account(Session.name).downcase
      notices=service.notices(publication_ref:publication_ref,addressed:true)
      results={}
      journal=tournament_notice_journal(account:account,notice:notices.first.first,kind:'start') unless notices.empty?
      notices.each do |notice,delivery_name|
        results[notice['recipient']]=TournamentStartPublisher.new(service:service,sender:-> {Session.name},transaction:journal.method(:update),
          send:->(metadata,closes){GameRoomNotifications.deliver(self,delivery_name,type:TournamentStartNotice::TYPE,metadata:metadata,
            expires_in:service.remaining_seconds(closes))}).deliver(metadata:notice)
      end
      results.freeze
    end

    def tournament_notice_journal(account:,notice:,kind:)
      identity=[account,notice['backend_identity']]
      permanent=%w[start finished].include?(kind)
      previous=Digest::SHA256.hexdigest(JSON.generate(identity))
      identity << notice['publication_ref'] if permanent || notice['version']==2
      scope=Digest::SHA256.hexdigest(JSON.generate(identity))
      seed=nil
      if permanent
        old=ProposalNoticeJournal.new(program:self,path:"tournament-#{kind}-deliveries-#{previous}.json").read
        if old
          unless old.is_a?(Hash) && old.keys.sort==%w[operations version] && old['version']==1 && old['operations'].is_a?(Hash)
            raise ProposalNotice::Unavailable,'Notification journal is corrupt'
          end
          seed=old['operations'].select do |_key,entry|
            unless entry.is_a?(Hash) && entry.dig('descriptor','metadata').is_a?(Hash)
              raise ProposalNotice::Unavailable,'Notification journal is corrupt'
            end
            entry['descriptor']['metadata']['publication_ref']==notice['publication_ref']
          end.transform_values { |entry| entry.merge('expires_at'=>0) }
        end
      end
      ProposalNoticeJournal.new(program:self,path:"tournament-#{kind}-deliveries-#{scope}.json",seed:seed)
    end

    def tournament_start_presentation(notification)
      cached=@tournament_start_inbox&.verified(notification.id)
      notice=TournamentStartNotice.metadata(notification.metadata.to_h)
      same_app=notification.app_uuid.to_s.downcase==server_app_uuid.to_s.downcase
      verified=same_app && cached && cached[0]['metadata']==notice && cached[1]==notification.sender.to_s.downcase
      description=@tournament_start_service&.description(metadata:notice,sender:notification.sender) if same_app
      # Old notices lack a description in metadata; retain their verified text
      # while available, even after the delivery window has elapsed.
      description ||= cached[0].slice('title','game') if verified
      valid=verified && @tournament_start_service.presentable?(cached[0])
      return notification.presentation(title:_("Tournament"),body:_("Open My tournaments to see the current status."),sound:nil).suppress_default! unless description
      body=GameRoomContent.utf8(_("The tournament %{name} (%{game}) you registered for has started."))%
        {name:GameRoomContent.utf8(description['title']),game:GameRoomContent.utf8(@tournament_start_registry.name(description['game']))}
      presentation=notification.presentation(title:_("Tournament started"),body:body,sound:nil,action: :open_tournament_matches)
      presentation.suppress_default! unless valid
      if valid && normalized_settings['invitation_sounds'] && respond_to?(:play_sound_from_asset)
        presentation.extend(GameRoomUI::NotificationSound)
        presentation.game_room_notice_player=-> {
          volume=GameRoomPreferences.sound_volume(normalized_settings,'notice')
          play_sound_from_asset('notice',volume:volume) if volume>0
        }
      end
      presentation
    rescue Publication::Invalid,ProposalNotice::Stale
      notification.presentation(title:_("Tournament"),body:_("This tournament notification is no longer available."),sound:nil).suppress_default!
    end

    def receive_tournament_start(notification)
      return unless @tournament_start_inbox && notification.app_uuid.to_s.downcase==server_app_uuid.to_s.downcase
      return if notification.respond_to?(:revoked) && notification.revoked
      @tournament_start_inbox.receive(id:notification.id,metadata:notification.metadata.to_h,sender:notification.sender)
    rescue Publication::Invalid
      false
    end

    def tournament_event_presentation(notification)
      kind=TournamentEventNotice::TYPES.key(notification.type.to_s)
      service=@tournament_event_services&.[](kind)
      notice=TournamentEventNotice.metadata(notification.metadata.to_h)
      cached=@tournament_event_inboxes&.[](kind)&.verified(notification.id)
      same_app=notification.app_uuid.to_s.downcase==server_app_uuid.to_s.downcase
      valid=same_app && cached && cached[0]['metadata']==notice && cached[1]==notification.sender.to_s.downcase && service&.presentable?(cached[0])
      description=service&.description(metadata:notice,sender:notification.sender) if same_app
      description ||= cached[0].slice('title','game') if kind=='partnership' && valid
      return notification.presentation(title:_("Tournament"),body:_("This tournament notification is no longer available."),sound:nil).suppress_default! unless description
      if kind=='partnership'
        title=_("Tournament partnership")
        change=cached[0].fetch('change')
        peer=change['from']==notice['recipient'] ? change['to_name'] : change['from_name']
        template=case change['kind']
        when 'requested' then _("%{player} invites you to be partners in %{name}.")
        when 'cancelled' then _("%{player}'s partner invitation in %{name} was cancelled.")
        when 'declined' then _("%{player} declined your partner invitation in %{name}.")
        when 'dissolved' then _("Your partnership with %{player} in %{name} has ended.")
        when 'assigned' then _("Your drawn partner in %{name}: %{player}.")
        else _("Your partner in %{name}: %{player}.")
        end
        body=GameRoomContent.utf8(template)%{player:peer,name:description['title']}
        action=:open_tournament_partner
      elsif kind=='registration'
        title=_("Tournament invitation")
        body=GameRoomContent.utf8(_("%{sender} invites you to register for %{name} (%{game})."))%{
          sender:notification.sender,name:description['title'],game:@tournament_start_registry.name(description['game'])}
        action=:open_tournament_registration
      elsif kind=='phase_finished'
        title=_("Tournament phase finished")
        body=GameRoomContent.utf8(_("A phase of %{name} has finished. Open its standings."))%{name:description['title']}
        if valid
          body=GameRoomContent.utf8(_("%{name}: %{phase} has finished. Next: %{next_phase}."))%{
            name:description['title'],phase:PhaseDescription.label(cached[0]['phase']),next_phase:PhaseDescription.label(cached[0]['next_phase'])}
        end
        action=:open_tournament_phase_standings
      else
        title=_("Tournament finished")
        body=GameRoomContent.utf8(_("The tournament %{name} has finished."))%{name:description['title']}
        result=notice['version']==2 ? notice : (cached[0] if valid)
        if result
          place=notice['version']==2 ? result['place'] : result.dig('places',notice['recipient'])
          if place
            template=result['team']==true || result['team_mode']==true ? _("Your team's place: %{place}.") : _("Your place: %{place}.")
            body+="\n"+GameRoomContent.utf8(template)%{place:place}
          end
          winners=result.fetch('winners')
          body+="\n"+GameRoomContent.utf8(winners.empty? ? _("No winner was determined.") :
            winners.size==1 ? _("Winner: %{players}") : _("Joint winners: %{players}"))%{players:winners.join(', ')}
        end
        action=:open_tournament_standings
      end
      presentation=notification.presentation(title:title,body:body,sound:nil,action:action)
      presentation.suppress_default! unless valid
      if valid && normalized_settings['invitation_sounds'] && respond_to?(:play_sound_from_asset)
        presentation.extend(GameRoomUI::NotificationSound)
        presentation.game_room_notice_player=-> {
          volume=GameRoomPreferences.sound_volume(normalized_settings,'notice')
          play_sound_from_asset('notice',volume:volume) if volume>0
        }
      end
      presentation
    rescue Publication::Invalid,ProposalNotice::Stale
      notification.presentation(title:_("Tournament"),body:_("This tournament notification is no longer available."),sound:nil).suppress_default!
    end

    def receive_tournament_event(notification)
      return unless notification.app_uuid.to_s.downcase==server_app_uuid.to_s.downcase
      return if notification.respond_to?(:revoked) && notification.revoked
      kind=TournamentEventNotice::TYPES.key(notification.type.to_s)
      @tournament_event_inboxes&.[](kind)&.receive(id:notification.id,metadata:notification.metadata.to_h,sender:notification.sender)
    rescue Publication::Invalid
      false
    end
    def tournament_starts_tick
      start_inbox=@tournament_start_inbox
      return unless start_inbox
      event_inboxes=@tournament_event_inboxes
      work_pending=start_inbox.work_pending?
      unless work_pending
        event_inboxes&.each_value do |inbox|
          if inbox.work_pending?
            work_pending=true
            break
          end
        end
      end
      return unless work_pending
      inboxes=[start_inbox,*(event_inboxes || {}).values]
      inboxes.flat_map(&:tick).each do |id,_proof|
        row=EltenAPI::NotificationService.active_notifications.find{|value|value.id.to_i==id && value.cat.to_s=='app' && value.app_uuid.to_s.downcase==server_app_uuid.to_s.downcase}
        next unless row && row.revoked!=true
        notification=Programs.app_notification_from(row)
        next unless ([TournamentStartNotice::TYPE]+TournamentEventNotice::TYPES.values).include?(notification.type)
        present_deferred_contact_notification(notification)
      end
      # Keep the native entries until their lifecycle callback has revoked
      # them on the server too. Removing only the local rows loses that task
      # and lets an obsolete notification return after a refresh/restart.
      inboxes.each(&:take_revoked)
    rescue StandardError => error
      Log.warning("Tournament start delivery failed: #{error.class}: #{error.message}") if defined?(Log)
    end
  end
end
