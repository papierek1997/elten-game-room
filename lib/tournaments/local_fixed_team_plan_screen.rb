# encoding: UTF-8
require_relative 'local_test_dialogs'
require_relative 'local_readiness_session'

module GameRoomTournaments
  class LocalFixedTeamPlanScreen < LocalTestDialogs::Window
    using GameRoomLocalization::Translations
    TEMPLATES = [[0, 1, 0, 1], [0, 0, 1, 1], [0, 1, 1, 0],
      [1, 0, 0, 1], [1, 0, 1, 0], [1, 1, 0, 0]].map(&:freeze).freeze

    def initialize(program:, workspace:, owner:)
      @program, @workspace, @owner = program, workspace, owner
    end

    def run
      return if @running || @finished
      primary = nil
      completed = false
      begin
        @session = LocalReadinessSession.new
        @session.choose_actor(@workspace.actor)
        @context = EntryContext.new(program: @program, runtime: @program.class.app_runtime,
          owner_reader: @owner.method(:current), actor: @workspace.actor, account_events: @session.actor_events)
        @lease = @context.capture
        result = super
        completed = true
        result
      rescue Exception => error
        primary = error
        raise error, cause: error.cause
      ensure
        begin
          @context&.close(primary: primary || (completed ? nil : :unwind))
        ensure
          @session&.close
          raise primary, cause: primary.cause if primary
        end
      end
    end

    private

    def build_form
      snapshot = @workspace.entry_load(context: @context, lease: @lease)
      unless snapshot && current?
        @finished = true
        return
      end
      @rows = snapshot.fetch('announcements').select { |row| row['__insertion_user'].downcase == @workspace.actor.downcase }
      @list = ListBox.new([], header: text(_("Tournament to plan")), quiet: true)
      @list.update_options(@rows.map { |row| row.fetch('title') }, keys: @rows.map { |row| row.fetch('__id') })
      roster = readonly(_("Registered participants"), '')
      update_roster = lambda do
        row = @rows[@list.index]
        names = row ? snapshot.fetch('members').select { |member| member['tournament_id'] == row['__id'] }.map { |member| member['username'] } : []
        roster.set_text(names.join(', '))
        update_team_fields(row) if @pairs && @template
        reset_confirmed_preview_for(row)
      end
      @pairs = EditBox.new(text(_("Teams: two accounts per line, separated by a comma")), type: EditBox::Flags::MultiLine, text: '', quiet: true)
      @template = ListBox.new(TEMPLATES.map { |value| value.map { |side| side + 1 }.join(', ') },
        header: text(_("Team sides at seats 1 to 4")), quiet: true)
      @details = readonly(_("Fixed-team plan preview"), instructions)
      preview = button(_("Preview fixed-team plan")) { create_preview }
      accept = button(_("Accept displayed plan")) { accept_preview }
      check = button(_("Check plan acceptance")) { check_acceptance }
      @table_limit = EditBox.new(text(_("Maximum simultaneous tables")), text: '3', quiet: true)
      configure = button(_("Set tournament table limit")) { configure_dispatch }
      back = button(_("Back"))
      make_form([@list, roster, @pairs, @template, @details, preview, accept, check, @table_limit, configure, back], cancel: back)
      @form.accept_button = preview
      @form.game_room_general_help_tips = [instructions]
      @list.on(:move) { interaction { update_roster.call } }
      update_roster.call
    end

    def current?
      @owner.check && @context.current?(@lease)
    end

    def configure_dispatch
      return unless @accepted && @preview && !@uncertain && current?
      unless form_input == @shown_input
        @details.set_text(text(_("Settings changed. Preview the plan again before accepting.")))
        return
      end
      raw = @table_limit.text.strip
      return show_failure(state: :blocked, reason: :invalid_table_limit) unless raw.match?(/\A[0-9]{1,2}\z/)
      result = operation(:dispatch_configure, {'intent_id' => @preview.fetch('intent_id'), 'max_tables' => raw.to_i})
      if result && result[:state] == :confirmed
        @details.set_text(text(_("Automatic invitations enabled for up to %{count} tables. Participants enable their own availability.")) % {count: result[:value]})
      else
        show_failure(result)
      end
    end
    def form_input
      row = @rows[@list.index]
      return unless row
      lines = @pairs.text.split(/\r?\n/).reject { |line| line.strip.empty? }
      {'publication_ref' => {'author' => row['__insertion_user'], 'publication_key' => row['publication_key']},
        (@team_size == 2 ? 'pairs' : 'teams') => lines.map { |line| line.split(',', -1).map(&:strip) },
        'team_template' => (@templates || TEMPLATES).fetch(@template.index)}
    end

    def update_team_fields(row)
      count = row ? JSON.parse(row.fetch('settings_json')).fetch('players_per_match') : 4
      @team_size = count.is_a?(Integer) && count.even? && count >= 4 ? count / 2 : 2
      @templates = @team_size == 2 ? TEMPLATES : [
        Array.new(@team_size * 2) { |index| index % 2 },
        Array.new(@team_size, 0) + Array.new(@team_size, 1)]
      @template.update_options(@templates.map { |value| value.map { |side| side + 1 }.join(', ') },
        keys: @templates.map { |value| value.join(',') })
      @pairs.header = @team_size == 2 ? text(_("Teams: two accounts per line, separated by a comma")) :
        text(_("Teams: %{count} accounts per line, separated by a comma")) % {count: @team_size}
      @template.header = @team_size == 2 ? text(_("Team sides at seats 1 to 4")) :
        text(_("Team sides at seats 1 to %{count}")) % {count: @team_size * 2}
    end

    def operation(action, input)
      return unless current?
      @workspace.fixed_team_plan(action: action, input: input, context: @context, lease: @lease, session: @session)
    end

    def create_preview
      return if @uncertain || !current?
      input = form_input
      return unless input
      return if @accepted && input == @shown_input
      @accepted = false
      @preview = @shown_input = nil
      result = operation(:preview, input.merge('intent_id' => SecureRandom.uuid))
      if result && result[:state] == :confirmed && current?
        @preview = result[:value]
        @shown_input = Publication::Data.freeze_tree(Publication::Data.copy(input))
        @details.set_text(preview_text)
      else
        show_failure(result)
      end
    end

    def reset_confirmed_preview_for(row)
      return if @uncertain || !@preview
      reference = row && {'author' => row['__insertion_user'], 'publication_key' => row['publication_key']}
      return if @shown_input && reference == @shown_input['publication_ref']
      @preview = @shown_input = nil
      @accepted = false
      @details.set_text(instructions)
    end

    def accept_preview
      return unless @preview && !@accepted && !@uncertain && current?
      unless form_input == @shown_input
        @preview = @shown_input = nil
        @details.set_text(text(_("Settings changed. Preview the plan again before accepting.")))
        return
      end
      result = operation(:accept, @preview)
      if result && result[:state] == :uncertain
        @uncertain = true
        @details.set_text([preview_text, text(_("Acceptance is uncertain. Use Check plan acceptance; do not send a new plan."))].join("\r\n"))
      elsif result && result[:state] == :confirmed
        @accepted = true
        @details.set_text(accepted_plan_text)
      else
        # Awaria po zapisie również wymaga sprawdzenia pierwotnego zamiaru.
        @uncertain = true
        show_failure(result)
      end
    end

    def check_acceptance
      return unless @preview && current?
      result = operation(:readback, {'intent_id' => @preview.fetch('intent_id')})
      if result && result[:state] == :confirmed
        if result[:value]
          @accepted, @uncertain = true, false
          @details.set_text(accepted_plan_text)
        else
          @uncertain = false
          @details.set_text([preview_text, text(_("No acceptance for this intent. You can accept the displayed plan."))].join("\r\n"))
        end
      else
        show_failure(result)
      end
    end

    def show_failure(result)
      reason = result && result[:reason] || 'read_failed'
      reason = text(_("Every assigned participant must compete for the result. Choose a mode without a permanent non-playing judge.")) if reason == :non_competing_player
      @details.set_text([@preview ? preview_text : instructions, text(_("Plan operation blocked: %{reason}")) % {reason: reason}].join("\r\n"))
    end

    def instructions
      text(_("Local test only. Registration must be closed. Each registered account must belong to exactly one team. Team size follows the game and the number of seats. Line order and account order define first-leg seats; the return leg swaps sides. Preview does not save. Acceptance does not invite players or start games."))
    end

    def accepted_plan_text
      text(_("Plan accepted. Open Fixed teams — local execution to check its matches."))
    end

    def preview_text
      lines = [instructions, @preview.fetch('digest')]
      @preview.fetch('membership').fetch('units').each { |unit| lines << "#{unit['unit_id']}: #{unit['accounts'].join(', ')}" }
      @preview.fetch('assignments').each do |match|
        seats = match['players'].map { |person| "#{person['seat'] + 1}: #{person['username']} (#{person['team']})" }.join('; ')
        lines << "#{match['match_id']} / #{match['leg']}: #{seats}"
      end
      @preview.fetch('windows').each { |window| lines << "#{Time.at(window['opens']).getlocal} — #{Time.at(window['closes']).getlocal}" }
      lines.join("\r\n")
    end
  end
end
