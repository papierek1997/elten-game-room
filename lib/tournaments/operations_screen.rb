# encoding: UTF-8
require_relative '../game_room_ui'
require_relative '../game_content'
require_relative '../game_room_localization'

module GameRoomTournaments
  # Jawne uzgodnienie przez callback kontrolera. Nie ma przycisku ponownego
  # wysłania, wywołania claim ani dostępu do providera w tym formularzu.
  class OperationsScreen
    using GameRoomLocalization::Translations

    # Treść i klawisze pomocy należą do wspólnego Form. Lokalny guard obejmuje
    # cały modal, jego resume oraz odtworzenie ID, szczegółów i fokusu rodzica.
    class Form < GameRoomUI::Form
      attr_writer :operations_interaction

      def show_game_room_help
        @operations_interaction.call { super }
      end

      private

      def restore_game_room_help_focus(_field)
        # interaction odtworzy pole/ID przed jedynym Form#focus, nadal pod busy.
        nil
      end
    end
    private_constant :Form

    def initialize(program:, load:, reconcile:, alert:, mode_label:, actor:)
      unless [mode_label, actor].all? { |value| value.is_a?(String) && !text(value).strip.empty? }
        raise ArgumentError, 'mode_label and actor must be explicit nonempty strings'
      end
      @program, @load, @reconcile, @alert = program, load, reconcile, alert
      @mode_label, @actor = text(mode_label).dup.freeze, text(actor).dup.freeze
    end

    def run
      return if @running || @finished
      @running = true
      begin
        @rows = @load.call
        return unless @rows
        show
      ensure
        @finished = true
      end
    end

    private

    def show
      @list = ListBox.new([], header: text(_("Tournament operations")), quiet: true,
        empty_label: text(_("No tournament operations.")))
      @details = GameRoomUI::HelpText.new(text(_("Operation details")),
        type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine, text: '', quiet: true)
      check = Button.new(text(_("Check selected operation")))
      refresh = Button.new(text(_("Refresh")))
      back = Button.new(text(_("Back")))
      @form = Form.new([@list, @details, check, refresh, back], program: @program, quiet: true)
      @form.operations_interaction = method(:interaction)
      @form.cancel_button = back
      @form.game_room_general_help_tips = [context,
        text(_("Enter on the list: read operation details. Check selected operation only reads and reconciles evidence; it never sends the request again."))]
      @list.on(:select) { interaction(restore_focus: false) { @form.index = 1 } }
      @list.on(:move) { render_details unless @busy || @finished }
      check.on(:press) { interaction { check_selected } }
      refresh.on(:press) { interaction { refresh_rows } }
      back.on(:press) { interaction { @finished = true; @form.resume } }
      interaction { render }
      @form.wait_without_announcement
    end

    def interaction(restore_focus: true)
      return if @busy || @finished
      @busy = true
      index, id = @form.index, selected&.fetch('id')
      begin
        yield
      ensure
        unless @finished
          selection = @rows.index { |row| row.fetch('id') == id }
          @list.index = selection if selection
          render_details
          @form.index = index if restore_focus && @form.index != index
          @form.focus
        end
        @busy = false
      end
    end

    def selected
      @rows[@list.index]
    end

    def check_selected
      row = selected
      return unless row
      id = row.fetch('id')
      result = @reconcile.call(id)
      return unless result
      raise ArgumentError, 'Reconciliation returned another operation' unless result.fetch('id') == id
      label = status_label(result)
      # Potwierdzony wynik trafia do widoku przed odświeżeniem, które może zawieść.
      @rows = @rows.map { |item| item.fetch('id') == id ? result : item }
      render
      message = text(_("Operation state: %{status}.")) % {status: label}
      @alert.call([message, outcome_notice(result)].compact.join("\r\n"))
      refresh_rows
    end

    def refresh_rows
      rows = @load.call
      return unless rows
      @rows = rows
      render
    end

    def render
      @list.update_options(@rows.map { |row| label(row) }, keys: @rows.map { |row| row.fetch('id') })
      # Szczegóły powstają dopiero po odtworzeniu ID w interaction. Przejściowy
      # kursor callbacka nie może podmienić tekstu ani wyzerować jego caret.
    end

    def label(row)
      title = case row.fetch('kind')
      when 'publication'
        text(_("Publication: %{title}")) % {title: text(row.fetch('values').fetch('title'))}
      when 'join'
        text(_("Registration for tournament %{id}")) % {id: row.fetch('values').fetch('tournament_id')}
      when 'withdrawal'
        text(_("Withdrawal from tournament %{id}")) % {id: row.fetch('values').fetch('tournament_id')}
      when 'removal'
        text(_("Removal of %{player} from tournament %{id}")) % {player: text(row.fetch('values').fetch('account')), id: row.fetch('values').fetch('tournament_id')}
      when 'pairing'
        text(_("Tournament pair: %{players}")) % {players: [row['values']['account'], row['values']['partner']].compact.join(' — ')}
      when 'partnership'
        text(_("Partner choice: %{players}")) % {players: [row['values']['account'], row['values']['partner']].compact.join(' — ')}
      when 'pair_draw'
        text(_("Tournament pair draw: %{id}")) % {id: row['values']['tournament_id']}
      when 'amendment'
        text(_("Tournament edit: %{id}")) % {id: row['values']['tournament_id']}
      when 'cancellation'
        text(_("Tournament deletion: %{id}")) % {id: row['values']['tournament_id']}
      when 'invitation'
        text(_("Tournament invitation: %{player}, %{id}")) % {player: text(row['values']['account']), id: row['values']['tournament_id']}
      when 'invite_declined'
        text(_("Declined tournament invitation: %{id}")) % {id: row['values']['tournament_id']}
      when 'plan_document'
        kind=row['values']['document_json'] && StrictJson.parse(row['values']['document_json'],max_nesting:12)['kind']
        label=case kind
        when 'ordinary-match-create-v1' then _("Tournament table creation: %{id}")
        when 'ordinary-match-binding-v1' then _("Tournament table link: %{id}")
        when 'ordinary-match-result-v1' then _("Tournament game result: %{id}")
        else _("Server match plan: tournament %{id}")
        end
        text(label) % {id: row['values']['tournament_id']}
      else
        raise ArgumentError, 'Unexpected tournament operation kind'
      end
      title + '; ' + status_label(row)
    end

    def status_label(row)
      value = case row.fetch('status')
      when 'prepared' then _("prepared; not confirmed")
      when 'attempted' then _("attempted; not confirmed")
      when 'confirmed' then _("confirmed")
      when 'outside_window' then _("outside the registration window")
      when 'conflict' then _("conflict; no further submission")
      else
        raise ArgumentError, 'Unexpected tournament operation status'
      end
      text(value)
    end

    def context
      [@mode_label, text(_("Current identity: %{actor}")) % {actor: @actor}].join("\r\n")
    end

    def outcome_notice(row)
      return unless %w[pairing partnership pair_draw].include?(row['kind']) && row['status'] == 'confirmed' &&
        row.dig('evidence', 'pairing_applied') == false

      text(_("The tournament changed. Refresh its view before changing it again."))
    end

    def render_details
      lines = [context]
      if selected
        lines << label(selected)
        lines << text(_("Operation ID: %{id}")) % {id: text(selected.fetch('id'))}
        notice = outcome_notice(selected)
        lines << notice if notice
      end
      lines << text(_("An unconfirmed operation is not proof of failure. Checking never sends it again."))
      value = lines.join("\r\n\r\n")
      @details.set_text(value) if @details.text != value
    end

    def text(value)
      GameRoomContent.utf8(value)
    end
  end
end
