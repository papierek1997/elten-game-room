# encoding: UTF-8
require_relative 'draft_editor'
require_relative 'local_registration_time'
require_relative 'publication'
require_relative 'tournament_datetime_field'
require_relative 'tournament_dates_editor'
require_relative 'scoring_text'
require_relative 'server_capacity'

module GameRoomTournaments
  # Game selection, game options, then tournament rules; no write before publish.
  class TournamentSetupEditor < DraftEditor
    using GameRoomLocalization::Translations
    def initialize(program:, registry:, configure:, publish:, alert:, clock: -> { Time.now.to_i }, publication: nil, publish_label: nil)
      @publish_label = publish_label
      @clock, @publish_callback = clock, publish
      @initial_publication = publication
      @timing=TournamentDatesEditor.values(publication)
      if publication
        settings = JSON.parse(publication['settings_json'])
        draft = settings.merge('name'=>publication['title'], 'game_id'=>publication['game'], 'windows'=>JSON.parse(publication['schedule_json'])['windows'])
      end
      super(program: program, registry: registry, configure: configure, save: method(:publish_configuration), alert: alert, draft: draft)
    end

    def wait
      unless @initial_publication
        ids=@registry.ids
        games=ListBox.new(ids.map{|id|text(@registry.name(id))},header:text(_("Game")),quiet:true)
        cancel=Button.new(text(_("Cancel")))
        selection=GameRoomUI::Form.new([games,cancel],program:@program,quiet:true)
        selection.cancel_button=cancel
        selection.hide(cancel)
        choosing=false
        games.on(:select) do
          next if choosing
          choosing=true
          begin
            game=@registry.build(ids.fetch(games.index))
            initial=game.new_game_options(game.table_creation_options({}))
            options=@configure.call(game,copy(initial))
            if options
              @setup_game_id=game.id
              @prepared_options=copy(options)
              selection.resume
            end
          ensure
            choosing=false
          end
        end
        cancel.on(:press){selection.resume}
        selection.wait
        return nil unless @setup_game_id
      end
      super
    end
    private
    def initialize_game_options
      @options_by_game[@setup_game_id]=copy(@prepared_options) if @prepared_options
    end
    def initialize_form_state; update_match_sizes; end
    def save_label; @initial_publication ? _("Save tournament changes") : (@publish_label || _("Publish in local test")); end
    def format_values; ['round_robin','groups_knockout']; end
    def format_labels; [_("Round robin"),_("Groups and knockout")]; end
    def rematch_values; [false,true]; end
    def rematch_labels; [_("No"),_("Yes")]; end
    def selected_game; @registry.build(@setup_game_id || @initial_publication.fetch('game')); end
    def update_group_fields
      super
      [@advancement, @group_count, @group_places].each { |field| @form.hide(field) }
      [@knockout_rematch, @final_rematch].compact.each do |field|
        groups_selected? ? @form.show(field) : @form.hide(field)
      end
      [[@knockout_rematch,@knockout_target],[@final_rematch,@final_target]].each do |mode,target|
        next unless target
        groups_selected? && mode.index==2 ? @form.show(target) : @form.hide(target)
      end
    end
    def setup_fields(fields)
      @games.options=@ids.map{|id|text(@registry.name(id))}
      @games.index=@draft ? (@ids.index(@draft['game_id']) || 0) : 0
      settings = @initial_publication ? JSON.parse(@initial_publication['settings_json']) : {}
      @organizer_notes = EditBox.new(text(_("Organizer's notes (optional)")),
        type: EditBox::Flags::MultiLine, text: @initial_publication ? ScoringText.notes(@initial_publication['rules']) : '', max_length: 4000, quiet: true)
      modes=[text(_("No")),text(_("Yes")),text(_("Play until a specified number of wins"))]
      @knockout_rematch = ListBox.new(modes, header: text(_("Return matches in knockout rounds")), index: settings['knockout_wins_to'] ? 2 : settings['knockout_rematch'] ? 1 : 0, quiet: true)
      @final_rematch = ListBox.new(modes.dup, header: text(_("Return match in the final")), index: settings['final_wins_to'] ? 2 : settings['final_rematch'] ? 1 : 0, quiet: true)
      @knockout_target=EditBox.new(text(_("Wins required in knockout rounds")),text:(settings['knockout_wins_to'] || 2).to_s,quiet:true)
      @final_target=EditBox.new(text(_("Wins required in the final")),text:(settings['final_wins_to'] || 2).to_s,quiet:true)
      [@knockout_rematch,@final_rematch].each{|mode|mode.on(:move){interaction{update_group_fields}}}
      @count = EditBox.new(text(_("Participant limit (maximum 128)")), text: '16', quiet: true)
      @seat_counts = (2..8).to_a
      @seats = ListBox.new(@seat_counts.map(&:to_s), header: text(_("Players per match")), index: 0, quiet: true)
      @pairing = ListBox.new([text(_("All possible compositions")), text(_("Rotating compositions; equal appearances"))],
        header: text(_("Multiplayer pairings")), index: 0, quiet: true)
      if @initial_publication
        settings = JSON.parse(@initial_publication['settings_json'])
        @count.set_text((settings['participant_limit'] || 16).to_s)
        @seats.index = @seat_counts.index(settings['players_per_match']) || 0
        @pairing.index = %w[all_combinations balanced_cycle].index(settings['pairing']) || 0
      end
      dates=Button.new(text(_("Dates and playing hours")))
      dates.on(:press) do
        interaction do
          result=TournamentDatesEditor.new(program:@program,values:@timing,alert:@alert,clock:@clock).run
          @timing=result if result
          @form.focus
        end
      end
      @games.on(:move) do
        interaction do
          update_match_sizes
        end
      end
      @seats.on(:move) { interaction { update_pairing_field } }
      enrollment=GameRoomUI::HelpText.new(text(_("Organizer")),type:EditBox::Flags::ReadOnly,
        text:text(_("Publishing also enrolls you as a participant. You can withdraw before the tournament starts.")),quiet:true) unless @initial_publication
      back=Button.new(text(_("Back"))) unless @initial_publication
      back&.on(:press) { interaction { configure_settings; @form.focus } }
      [@name, @organizer_notes, @format, @rematch, @knockout_rematch, @knockout_target, @final_rematch, @final_target, @count, @seats, @pairing,
        (@initial_publication ? fields[2] : nil),dates,enrollment,@advancement, @group_count, @group_places, back, fields[-2], fields[-1]].compact
    end
    def configure_settings
      super
      update_match_sizes
    end
    def update_match_sizes
      game = selected_game
      return unless game
      previous = @seat_counts[@seats.index]
      @seat_counts = ServerCapacity.supported_player_counts(game: game, options: options_for(game)).select { |n| n.between?(2, 8) }
      @seats.options = @seat_counts.map(&:to_s)
      @seats.index = @seat_counts.index(previous) || 0
      @seat_counts.size == 1 ? @form.hide(@seats) : @form.show(@seats)
      update_pairing_field
    end
    def update_pairing_field
      count = @seat_counts[@seats.index]
      count && count > 2 ? @form.show(@pairing) : @form.hide(@pairing)
    end
    def publish_configuration(attributes)
      if @submitted
        @alert.call(text(_("Publication not confirmed. Check Operations before trying again.")))
        return nil
      end
      raw = text(@count.text).strip
      raise Publication::Invalid, :invalid_participant_limit unless raw.match?(/\A[0-9]{1,3}\z/) && raw.to_i.between?(2, 128)
      opens=@timing['opens'] || @clock.call
      closes=@timing['closes']
      windows=@timing['windows']
      count = @seat_counts[@seats.index]
      raise Publication::Invalid, :unsupported_match_size unless count
      if attributes['format'] == 'groups_knockout'
        game = @registry.build(attributes['game_id'])
        team_size = game.team_size(attributes['game_options'], player_count: count)
        unless (count == 2 && team_size == 0) || (count == 4 && team_size == 2)
          @alert.call(text(_("Groups and knockout currently require two individual players or two fixed pairs per match. Choose round robin for other match sizes.")))
          return nil
        end
      end
      unless @initial_publication
        game = @registry.build(attributes.fetch('game_id'))
        attributes = attributes.merge('game_options' => game.new_game_options(copy(attributes.fetch('game_options'))))
      end
      draft = attributes.merge('players_per_match' => count,
        'pairing' => %w[all_combinations balanced_cycle].fetch(@pairing.index),
        'participant_limit' => raw.to_i, 'windows' => windows,'starts_at'=>@timing['starts'],'deadline_at'=>@timing['deadline'])
      draft['daily_hours']=@timing['daily_hours'] if @timing['daily_hours']
      if draft['format'] == 'groups_knockout'
        draft.merge!('group_advancement' => GroupAdvancement::COMPACT, 'group_count' => nil, 'places_per_group' => nil)
        draft.merge!('knockout_rematch' => @knockout_rematch.index == 1, 'final_rematch' => @final_rematch.index == 1)
        [['knockout_wins_to',@knockout_rematch,@knockout_target],['final_wins_to',@final_rematch,@final_target]].each do |key,mode,field|
          next unless mode.index==2
          value=text(field.text).strip
          raise Publication::Invalid,:invalid_win_target unless value.match?(/\A[0-9]{1,2}\z/) && value.to_i.between?(1,99)
          draft[key]=value.to_i
        end
      end
      rules = text(@organizer_notes.text)
      rules = ScoringText::DEFAULT if rules.strip.empty?
      timezone = @timing.fetch('timezone', 'UTC')
      Publication.from_draft(draft: draft, registry: @registry, publication_key: 'setup-preflight', rules: rules,
        registration_opens_at: opens, registration_closes_at: closes, timezone: timezone)
      @submitted = true
      result = @publish_callback.call(draft: draft, rules: rules, registration_opens_at: opens,
        registration_closes_at: closes, timezone: timezone)
      unless result && result['status'] == 'confirmed'
        @alert.call(text(_("Publication not confirmed. Check Operations before trying again.")))
        return nil
      end
      enrollment = result['organizer_registration']
      if enrollment && !%w[confirmed withdrawn].include?(enrollment['status'])
        @alert.call(text(_("Tournament published, but organizer enrollment was not confirmed. Check Operations before joining again.")))
      end
      result
    rescue Publication::Invalid, LocalRegistrationTime::Invalid => error
      message=case error.code
      when :invalid_participant_limit then _("Participant limit: enter a number from 2 to 128.")
      when :invalid_win_target then _("Required wins: enter a number from 1 to 99.")
      when :invalid_name,:invalid_title then _("Tournament name: enter a name.")
      when :registration_after_start then _("Registration must close no later than the tournament starts.")
      when :invalid_registration_window,:invalid_registration_time then _("Registration cannot close before it opens.")
      when :deadline_before_start then _("The deadline cannot be earlier than the tournament start.")
      when :invalid_playing_hours then _("Choose different start and end times, or turn off the playing-hours limit.")
      else _("Check tournament settings and dates: %{reason}")
      end
      @alert.call(text(message)%{reason:error.code})
      nil
    end
  end
end
