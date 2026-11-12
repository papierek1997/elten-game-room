# encoding: UTF-8
require_relative 'local_fixed_team_plan_screen'
module GameRoomTournaments
  class LocalIndividualPlanScreen < LocalFixedTeamPlanScreen
    using GameRoomLocalization::Translations
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
      @match_roster = readonly(_("Individual matches to plan"), '')
      @seats = EditBox.new(text(_("Seats: one match per line, accounts separated by commas")),
        type: EditBox::Flags::MultiLine, text: '', quiet: true)
      @details = readonly(_("Individual plan preview"), instructions)
      preview = button(_("Preview individual plan")) { create_preview }
      accept = button(_("Accept displayed plan")) { accept_preview }
      check = button(_("Check plan acceptance")) { check_acceptance }
      @table_limit = EditBox.new(text(_("Maximum simultaneous tables")), text: '3', quiet: true)
      configure = button(_("Set tournament table limit")) { configure_dispatch }
      back = button(_("Back"))
      make_form([@list, @match_roster, @seats, @details, preview, accept, check, @table_limit, configure, back], cancel: back)
      @form.accept_button = preview
      @form.game_room_general_help_tips = [instructions]
      @list.on(:move) { interaction { load_candidate } }
      load_candidate
    end
    def load_candidate
      @candidate = nil
      @first_legs = []
      unless @uncertain
        @preview = @shown_input = nil
        @accepted = false
      end
      row = @rows[@list.index]
      if row
        candidate = @workspace.schedule_candidate(publication_ref: {'author' => row['__insertion_user'],
          'publication_key' => row['publication_key']}, context: @context, lease: @lease)
        @candidate = candidate.to_h if candidate && !candidate.is_a?(Hash)
      end
      @first_legs = @candidate ? @candidate['matches'].select { |match| match['leg'] == 1 } : []
      @match_roster.set_text(@first_legs.each_with_index.map { |match, index| "#{index + 1}: #{match['players'].join(', ')}" }.join("\r\n"))
      @seats.set_text(@first_legs.map { |match| match['players'].join(', ') }.join("\r\n"))
      @details.set_text(@uncertain ? [preview_text,
        text(_("Acceptance is uncertain. Use Check plan acceptance; do not send a new plan."))].join("\r\n") : instructions)
    end
    def form_input
      row = @rows[@list.index]
      return unless row && @candidate
      lines = @seats.text.split(/\r?\n/).reject { |line| line.strip.empty? }
      unless lines.size == @first_legs.size
        @details.set_text(text(_("Enter one seat assignment line for every displayed match.")))
        return
      end
      {'publication_ref' => {'author' => row['__insertion_user'], 'publication_key' => row['publication_key']},
        'base_seats' => @first_legs.each_with_index.to_h { |match, index| [match['match_id'], lines[index].split(',', -1).map(&:strip)] }}
    end
    def operation(action, input)
      return unless current?
      @workspace.individual_plan(action: action, input: input, context: @context, lease: @lease, session: @session)
    end
    def instructions
      text(_("Local test only. Registration must be closed. Each line assigns seats for the corresponding displayed match. Review the complete plan before accepting. Acceptance does not enter participants or start games."))
    end
    def accepted_plan_text
      text(_("Plan accepted. Open Individual matches — local execution to check its matches."))
    end
    def preview_text
      lines = [instructions]
      @preview.fetch('assignments').each do |match|
        seats = match['players'].map { |person| "#{person['seat'] + 1}: #{person['username']}" }.join('; ')
        lines << "#{match['match_id']} / #{match['leg']}: #{seats}"
      end
      @preview.fetch('windows').each { |window| lines << "#{Time.at(window['opens']).getlocal} — #{Time.at(window['closes']).getlocal}" }
      lines.join("\r\n")
    end
  end
end
