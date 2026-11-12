# encoding: UTF-8
require_relative '../game_room_ui'
require_relative 'public_text'
require_relative 'view_refresh'
require_relative 'partner_choice'

module GameRoomTournaments
  class PublicPreview
    using GameRoomLocalization::Translations
    attr_reader :snapshot

    # Wspólna pomoc pozostaje właścicielem modalu; guard obejmuje także resume.
    class Form < GameRoomUI::Form
      attr_writer :public_interaction
      attr_writer :public_update
      def schedule_lifecycle(seconds,&block);register_timer(seconds,repeat:false,&block);end
      def update
        super
        @public_update&.call
      end

      def show_game_room_help
        @public_interaction.call { super }
      end

      private

      def restore_game_room_help_focus(_field)
        # interaction odtworzy pole/ID przed jedynym Form#focus, nadal pod busy.
        nil
      end
    end
    private_constant :Form

    def initialize(program:, registry:, publication:, snapshot:, load:, join:, alert:, mode_label:, actor:, join_virtual: nil, overview: nil, withdraw: nil, manage_participants: nil, set_partner: nil, partner_action: nil, edit_tournament: nil, delete_tournament: nil,initial_action:nil,results:nil,phase:nil,invite:nil,decline_invitation:nil,clock:-> {Time.now.to_i})
      @initial_action=initial_action
      @registry = registry
      @program, @publication, @snapshot = program, publication, snapshot
      @load, @join, @alert = load, join, alert
      @join_virtual, @overview = join_virtual, overview
      @withdraw = withdraw
      @manage_participants = manage_participants
      @set_partner = set_partner
      @partner_action = partner_action
      @edit_tournament, @delete_tournament = edit_tournament, delete_tournament
      @results,@phase,@clock=results,phase,clock
      @invite=invite
      @decline_invitation=decline_invitation
      update_pair_game
      @text = PublicText.new(registry: registry, mode_label: mode_label, actor: actor)
      @actor = text(actor)
      # Niezgodna para pozostaje tylko do odczytu; samo ID/tytuł nie dowodzi zamiaru.
      @stale = !@snapshot.fetch('announcements').any? { |row| row.eql?(@publication) }
    end

    def wait
      return if @running || @finished
      @running = true
      begin
        show
      ensure
        @finished = true
        @lifecycle_timer&.close
      end
    end

    # Context operations reuse the one-attempt guards without a details browser.
    # Only input genuinely needed by an action gets a modal.
    def perform(action)
      return if @running || @finished
      @running=true
      begin
        case action
        when :join
          @join_virtual ? virtual_join : request_join
        when :withdraw then request_withdrawal
        when :overview
          @overview.call(@publication) if @overview
          refresh_snapshot
        when :results
          @results.call(@publication) if @results
          refresh_snapshot
        when :partner, :participants then execute_action(action)
        when :manage then manage_tournament
        when :edit,:delete
          if @publication['__insertion_user'].downcase==@actor.downcase
            callback={edit:@edit_tournament,delete:@delete_tournament,manage:@manage_participants}[action]
            callback.call(@publication) if callback
            refresh_snapshot
          end
        end
      ensure
        @running=false
        @finished=true
        @lifecycle_timer&.close
      end
    end

    private

    def virtual_join
      @virtual_name=EditBox.new(text(_("Virtual player name (local test only)")),text:'',max_length:64,quiet:true)
      join=Button.new(text(_("Join tournament")))
      cancel=Button.new(text(_("Cancel")))
      @form=Form.new([@virtual_name,join,cancel],program:@program,quiet:true)
      @form.public_interaction=method(:interaction)
      @form.accept_button=join
      @form.cancel_button=cancel
      join.on(:press) do
        interaction do
          if text(@virtual_name.text).strip.empty?
            @alert.call(text(_("Enter a virtual player name.")))
            next
          end
          request_join
          @finished=true
          @form.resume
        end
      end
      cancel.on(:press){interaction{@finished=true;@form.resume}}
      @form.wait_without_announcement
    end

    def show
      @status = GameRoomUI::HelpText.new(text(_("Status")),
        type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine, text: '', quiet: true)
      back = Button.new(text(_("Back")))
      @actions=ListBox.new([],header:text(_("Actions")),quiet:true)
      @virtual_name=EditBox.new(text(_("Virtual player name (local test only)")),text:'',max_length:64,quiet:true) if @join_virtual
      @form = Form.new([@actions,@virtual_name,@status,back].compact, program: @program, quiet: true)
      @form.hide(back)
      @form.public_interaction = method(:interaction)
      reference={'author'=>@publication['__insertion_user'].downcase,'publication_key'=>@publication['publication_key']}
      @view_refresh=ViewRefresh.new(@program,reference:reference){interaction(focus:false){refresh_snapshot}}
      @form.public_update=method(:update_lifecycle)
      @form.game_room_general_help_tips = [text(_("Choose an action with the arrows and press Enter. Escape returns without leaving the tournament."))]
      @form.cancel_button = back
      @actions.on(:select){interaction{execute_action(@action_keys[@actions.index])}}
      back.on(:press) { interaction { @finished = true; @form.resume } }
      interaction { render_status }
      interaction(restore:!(@initial_action==:join && @virtual_name)) do
        case @initial_action
        when :join
          @virtual_name ? @form.index=@form.fields.index(@virtual_name) : request_join
        when :withdraw then request_withdrawal
        when :overview
          @overview.call(@publication) if @overview
          refresh_snapshot
        when :results
          @results.call(@publication) if @results
          refresh_snapshot
        when :partner, :participants
          # A drawn/confirmed team's notice remains useful after start, when
          # choosing a new partner is no longer permitted.
          execute_action(@initial_action)
        when :manage then manage_tournament
        when :edit,:delete
          if @publication['__insertion_user'].downcase==@actor.downcase
            callback={edit:@edit_tournament,delete:@delete_tournament,manage:@manage_participants}[@initial_action]
            callback.call(@publication) if callback
            refresh_snapshot
          end
        end
      end if @initial_action
      @form.wait_without_announcement
    end

    def execute_action(action)
      case action
      when :join then request_join
      when :withdraw then request_withdrawal
      when :overview then @overview.call(@publication);refresh_snapshot
      when :results then @results.call(@publication);refresh_snapshot
      when :partner
        partner_choice_available? ? choose_partner : execute_action(:participants)
      when :participants
        @manage_participants.call(@publication) if @manage_participants
        refresh_snapshot
      when :decline_invitation
        @decline_invitation.call(@publication) if @decline_invitation && pending_invitation?
        refresh_snapshot
      when :rules then show_document(_("Information and rules"),@text.description(@publication,@snapshot))
      when :manage then manage_tournament
      when :refresh then refresh_snapshot
      end
    end

    def show_document(header,value)
      field=GameRoomUI::HelpText.new(text(header),type:EditBox::Flags::ReadOnly|EditBox::Flags::MultiLine,text:value,quiet:true)
      back=Button.new(text(_("Back")))
      form=GameRoomUI::Form.new([field,back],program:@program,quiet:true)
      form.hide(back)
      form.cancel_button=back
      back.on(:press){form.resume}
      form.wait
    end

    def manage_tournament
      return unless @publication['__insertion_user'].downcase==@actor.downcase
      state=TournamentLifecycle.classify(@publication,now:@clock.call)[:state]
      options=[]
      before_start=[:soon,:registration,:waiting].include?(state)
      if before_start
        options << [:edit,_("Edit tournament")] if @edit_tournament
        options << [:open,_("Open registration")] if @phase && state!=:registration
        options << [:close,_("Close registration")] if @phase && state==:registration
        options << [:start,_("Start tournament")] if @phase
      end
      options << [:delete,_("Cancel tournament")] if @delete_tournament && state!=:completed
      list=ListBox.new(options.map{|_,label|text(label)},header:text(_("Manage tournament")),quiet:true)
      back=Button.new(text(_("Back")))
      form=GameRoomUI::Form.new([list,back],program:@program,quiet:true)
      form.cancel_button=back
      form.hide(back)
      busy=false
      list.on(:select) do
        next if busy
        busy=true
        begin
          action=options[list.index]&.first
          if [:open,:close,:start].include?(action)
            @phase.call(@publication,action.to_s)
          elsif action
            {invite:@invite,manage:@manage_participants,edit:@edit_tournament,delete:@delete_tournament}.fetch(action).call(@publication)
          end
          form.resume
        ensure
          busy=false
        end
      end
      back.on(:press){form.resume}
      form.wait
      refresh_snapshot
    end

    def interaction(restore:true,focus:true)
      return if @busy || @finished
      @busy = true
      index = @form.index
      begin
        yield
      ensure
        unless @finished
          @form.index = index if restore && @form.index != index
          @form.focus if focus
        end
        @busy = false
      end
    end

    def registered?
      name = @virtual_name ? text(@virtual_name.text).strip : @actor
      @text.members(@publication, @snapshot).any? { |member| member.fetch('account').downcase == name.downcase }
    end

    def request_withdrawal
      return if @stale || @withdrawal_requested
      @withdrawal_requested, @withdrawal_confirmed = true, false
      result = @withdraw.call(@publication.fetch('__id'))
      @withdrawal_confirmed = result && result['status'] == 'confirmed'
      @result_text = text(result && result['status'] == 'confirmed' ? _("Withdrawal confirmed.") : _("Withdrawal not confirmed. Check Operations before trying again."))
      @join_requested = false if result && result['status'] == 'confirmed'
      refresh_snapshot
      @alert.call(@result_text)
    end

    def request_join
      if @virtual_name && text(@virtual_name.text).strip.empty?
        @alert.call(text(_("Enter a virtual player name.")))
        return
      end
      if @stale || registered? || @join_requested
        @alert.call(@status ? @status.text : render_status)
        return
      end
      # Nie ponawiamy z tego widoku nawet po nil/niepewności callbacku.
      @join_requested, @join_confirmed = true, false
      record = @virtual_name ? @join_virtual.call(@publication.fetch('__id'), text(@virtual_name.text).strip) : @join.call(@publication.fetch('__id'))
      @join_confirmed = record && record['status'] == 'confirmed'
      @withdrawal_requested = false if record && record['status'] == 'confirmed'
      @result_text = result_text(record)
      render_status
      @alert.call(@result_text) if record
      refresh_snapshot
      if @virtual_name && record && record['status'] == 'confirmed'
        @virtual_name.set_text('')
        @join_requested = false
        render_actions
      end
    end

    def result_text(record)
      return text(_("Registration not confirmed. The request was cancelled or failed. No automatic retry.")) unless record
      case record.fetch('status')
      when 'confirmed' then text(_("Registration confirmed."))
      when 'prepared', 'attempted' then text(_("Registration not confirmed. No automatic retry."))
      when 'outside_window' then text(_("Registration outside the allowed window."))
      when 'conflict' then text(_("Conflict — registration was not sent again."))
      else
        raise ArgumentError, "Unexpected tournament join status: #{record.fetch('status').inspect}"
      end
    end

    def refresh_snapshot
      @view_refresh&.acknowledge
      fresh = @load.call
      unless fresh
        @refresh_failed = true
        render_status
        return
      end
      @snapshot, @refresh_failed = fresh, false
      current = fresh.fetch('announcements').find { |row| row['__id']==@publication['__id'] && row['publication_key']==@publication['publication_key'] && row['__insertion_user']==@publication['__insertion_user'] }
      @stale = current.nil?
      if current
        @publication = current
        update_pair_game
        # A successful read retires only confirmed local attempts. The service
        # owns idempotence and registration epochs; uncertainty still requires
        # explicit reconciliation, not another click on a stale view.
        @join_requested = @join_confirmed = false if @join_confirmed
        @withdrawal_requested = @withdrawal_confirmed = false if @withdrawal_confirmed
      end
      render_status
    end

    def update_pair_game
      settings = JSON.parse(@publication.fetch('settings_json'))
      @pair_game = @registry.build(@publication.fetch('game')).team_size(
        settings.fetch('game_options'), player_count: settings.fetch('players_per_match')) == 2
    end

    def render_status
      lines = []
      lines << @result_text if @result_text
      lines << text(_("Outdated preview — the announcement is missing or conflicting. Joining is unavailable.")) if @stale
      lines << text(_("Refresh failed or was cancelled. The last readable view is retained.")) if @refresh_failed
      value = lines.join("\r\n\r\n")
      @status.set_text(value) if @status && @status.text != value
      if @form && @status
        value.empty? ? @form.hide(@status) : @form.show(@status)
      end
      render_actions if @actions
      value
    end

    def render_actions
      now=@clock.call
      state=TournamentLifecycle.classify(@publication,now:now)[:state]
      actions=[]
      unless @stale
        actions << [:join,_("Join tournament")] if @join && !registered? && !@join_requested && @text.can_join?(@publication,@snapshot,now:now)
        actions << [:decline_invitation,_("Decline invitation")] if @decline_invitation && !registered? && pending_invitation?
        actions << [:overview,_("Tournament matches")] if @overview
        actions << [:results,_("Standings")] if @results
        actions << [:participants,_("Participants")]
        actions << [:rules,_("Information and rules")]
        actions << [:partner,_("Team partner")] if partner_choice_available?(state)
        actions << [:manage,_("Manage tournament")] if @publication['__insertion_user'].downcase==@actor.downcase
        actions << [:withdraw,_("Leave tournament")] if registered? && @withdraw && [:soon,:registration,:waiting].include?(state)
      end
      actions << [:refresh,_("Refresh")]
      @actions.header=@text.action_header(@publication,@snapshot,now:now)
      @action_keys=actions.map(&:first)
      @actions.update_options(actions.map{|_,label|text(label)},keys:@action_keys)
      @lifecycle_timer&.close
      deadline=TournamentLifecycle.next_change(@publication,now:now) unless @stale
      @lifecycle_timer=deadline && @form.schedule_lifecycle(deadline-now){@lifecycle_dirty=true}
    end

    # A directory revision is not a clock: an unregistered browser may receive
    # no coordinator wake when registration opens/closes. Follow only the next
    # local boundary, without refocusing or polling the server. Retention expiry
    # needs one fresh directory read, as in the parent tournament list.
    def update_lifecycle
      return if @busy || @finished
      @view_refresh.tick
      return unless @lifecycle_dirty && !@busy && !@finished
      @lifecycle_dirty=false
      interaction(focus:false) do
        expired=@publication['expires_at'] && @publication['expires_at']<=@clock.call
        expired ? refresh_snapshot : render_status
      end
    end

    def partner_choice_available?(state = TournamentLifecycle.classify(@publication, now: @clock.call)[:state])
      !@stale && registered? && @pair_game && @set_partner && [:soon, :registration, :waiting].include?(state)
    end

    def choose_partner
      return if @stale || @pairing_uncertain
      PartnerChoice.new(program: @program, publication: @publication, account: @actor,
        load: @load, choose: @set_partner, action: @partner_action, alert: @alert,
        confirm: ->(message) { @program.send(:confirm, message) }).run
      refresh_snapshot
    end

    def pending_invitation?
      TournamentTiming.registration_open?(@publication,@clock.call) && @snapshot.fetch('invitations',[]).any? do |entry|
        entry['tournament_id']==@publication['__id'] && entry['account']==@actor.downcase && entry['status']=='pending' && !entry['resolved']
      end
    end

    def text(value)
      GameRoomContent.utf8(value)
    end
  end
end
