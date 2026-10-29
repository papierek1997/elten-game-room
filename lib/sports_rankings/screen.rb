require_relative 'result'
require_relative 'personal'
require_relative '../game_room_ui'
require_relative '../game_room_background'

module GameRoomSportsRankings
  class Screen
    using GameRoomLocalization::Translations

    class Form < GameRoomUI::Form
      attr_accessor :statistics_update
      def update
        super
        statistics_update&.call
      end
    end
    private_constant :Form

    def initialize(program:, game:, service:, today: -> { GameRoomStatistics::Periods.today })
      @program, @game, @service, @today = program, game, service, today
      @user = Session.name.to_s.dup.freeze
      @runtime = program.class.app_runtime if program.class.respond_to?(:app_runtime)
      @closed = false
    end

    def run
      unless @service && @program.class.analytics_enabled?
        alert(text(_("Player statistics are temporarily unavailable.")))
        return
      end
      index = 0
      @player = @user
      loop do
        selected = choose([_('Single'), _('Doubles')], header: @game.name, index: index)
        break if selected.nil?
        index, @mode = selected, selected.zero? ? 'singles' : 'doubles'
        show_statistics
      end
    end

    def close
      @closed = true
      @token&.cancel
      @work&.close
    end

    private

    def current?
      !@closed && @program.class.analytics_enabled? && GameRoomParticipants.same?(@user, Session.name) &&
        (!@runtime || @program.class.app_runtime.equal?(@runtime))
    end

    def text(value); GameRoomContent.utf8(value); end

    def choose(options, header:, index: 0)
      list = ListBox.new(options.map { |option| text(option) }, header: text(header), index: index, quiet: true)
      open_button, back = Button.new(text(_('Open'))), Button.new(text(_('Back')))
      form = GameRoomUI::Form.new([list, open_button, back], program: @program, quiet: true)
      form.accept_button, form.cancel_button = open_button, back
      form.hide(open_button)
      form.hide(back)
      selected = nil
      open_button.on(:press) { selected = list.index; form.resume }
      back.on(:press) { form.resume }
      form.wait
      selected if current?
    end

    def period_labels
      [_('All time'), _('Last 7 days'), _('Last 30 days'), _('Last six months'), _('Last year')]
    end

    def range(index, today)
      first = case index
      when 0 then nil
      when 1 then today - 6
      when 2 then today - 29
      when 3 then (today << 6) + 1
      when 4 then (today << 12) + 1
      else raise ArgumentError, 'Unknown statistics period'
      end
      [first&.strftime('%Y%m%d')&.to_i, today.strftime('%Y%m%d').to_i]
    end

    def show_statistics
      @player ||= @user
      @generation, @pending_request, @active_request = 0, nil, nil
      @period = ListBox.new(period_labels.map { |label| text(label) }, header: text(_('Period')), quiet: true)
      control = EditBox.new(text(_('Player statistics')), type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
        text: text(_('Loading statistics')), quiet: true)
      # Everyone the shown player met, below the counters; Enter opens head-to-head.
      @opponents = []
      opponents = TableBox.new([_('Opponent'), _('Played'), _('Won'), _('Lost')].map { |label| text(label) }, [],
        header: text(_('Opponents')), empty_label: text(_('Loading statistics')), quiet: true)
      @opponents_control = opponents
      head_to_head = Button.new(text(_('Matches against this opponent')))
      choose_player, own = Button.new(text(_('Choose player'))), Button.new(text(_('My statistics')))
      refresh, back = Button.new(text(_('Refresh'))), Button.new(text(_('Back')))
      @form = Form.new([control, opponents, @period, choose_player, own, refresh, head_to_head, back], program: @program, quiet: true)
      @form.cancel_button, @form.accept_button = back, head_to_head
      @form.hide(head_to_head)
      back.on(:press) { @form.resume }
      head_to_head.on(:press) do
        next unless @form.fields[@form.index].equal?(opponents) && @opponents[opponents.index]
        show_head_to_head(@opponents.fetch(opponents.index))
      end
      choose_player.on(:press) do
        selected = input_user(text(_('Player')))
        next unless current? && selected && !selected.strip.empty?
        @player = selected.strip
        request_results(control)
      end
      own.on(:press) { @player = @user; request_results(control) }
      @period.on(:move) { request_results(control) }
      @work = GameRoomBackground::Work.new
      refresh.on(:press) { request_results(control, fresh: true) }
      @form.statistics_update = -> { receive_results(control) }
      request_results(control)
      @form.wait
    ensure
      @token&.cancel
      @work&.close
      @work = @token = @pending_request = @active_request = @opponents_control = nil
      @form.statistics_update = nil if @form
    end

    def request_results(control, fresh: false)
      return unless current?
      @generation += 1
      @pending_request = {generation: @generation, player: @player.dup.freeze,
        mode: @mode, period: @period.index, fresh: fresh}.freeze
      control.header = text(_('%{player}: %{period}')) % {player: text(@player), period: text(period_labels.fetch(@period.index))}
      control.set_text(text(_('Loading statistics')))
      show_opponents(nil, text(_('Loading statistics')))
      start_pending
    end

    def start_pending
      return unless current? && @pending_request && !@work.busy?
      request = @pending_request
      token = EltenAPI::Tasks::CancellationToken.new
      return unless GameRoomBackground.admit(@work) do
        token.raise_if_cancelled!
        raise Unavailable, 'Statistics account changed' unless current?
        GameRoomClock.synchronize
        today = @today.call
        from, to = range(request.fetch(:period), today)
        report = @service.store.report(game: @game.id, mode: request.fetch(:mode), from_day: from, to_day: to,
          cancellation_token: token, fresh: request.fetch(:fresh))
        [report, @service.store.personal(game: @game.id, mode: request.fetch(:mode), today: today,
          player: request.fetch(:player), cancellation_token: token)]
      end
      @active_request, @token, @pending_request = request, token, nil
    end

    def receive_results(control)
      return @form.resume unless current?
      if (outcome = @work.take)
        request, @active_request, @token = @active_request, nil, nil
        value, error = outcome
        rows, personal = value if value.is_a?(Array)
        if request && request.fetch(:generation) == @generation
          if rows.is_a?(Array) && personal.is_a?(Array) && !error
            row = rows.find { |entry| GameRoomParticipants.same?(entry.fetch('user'), request.fetch(:player)) }
            control.set_text(statistics_text(row || empty_statistics(request.fetch(:player))))
            show_opponents(personal.reject { |entry| entry.fetch('own') }, text(_('No matches against other players')), period: request.fetch(:period))
          else
            show_error(control, error || Unavailable.new('Missing statistics response'))
          end
          control.focus if @form.fields[@form.index].equal?(control) && @form.game_room_hotkeys_active? && !@form.game_room_background_help?
        end
      end
      start_pending
    end

    def show_error(control, error)
      Log.warning("Player statistics read failed: #{error.class}") if defined?(Log)
      control.set_text(text(_('Player statistics are unavailable. Try Refresh.')))
      show_opponents(nil, text(_('Player statistics are unavailable. Try Refresh.')))
    end

    # Rows count the selected period and omit opponents not met in it; the
    # selection stays on the same opponent.
    def show_opponents(entries, empty, period: 0)
      control = @opponents_control
      return unless control
      selected = @opponents[control.index]&.fetch('players')
      key = Personal::PERIODS.fetch(period)
      @opponents = (entries || []).select { |entry| entry.fetch('periods').fetch(key).values.sum.positive? }
      control.rows = @opponents.map do |entry|
        counts = entry.fetch('periods').fetch(key)
        [entry_name(entry), (counts.fetch('won') + counts.fetch('lost')).to_s, counts.fetch('won').to_s, counts.fetch('lost').to_s]
      end
      control.empty_label = empty
      control.reload
      control.index = @opponents.index { |entry| entry['players'] == selected } || 0
    end

    # A doubles opponent is a pair, named by both members.
    def entry_name(entry)
      first, second = entry.fetch('players').map { |name| text(name) }
      second ? text(_('%{first} and %{second}')) % {first: first, second: second} : first
    end

    def show_head_to_head(entry)
      lines = Personal::PERIODS.each_with_index.map do |period, index|
        counts = entry.fetch('periods').fetch(period)
        text(_('%{period}: won %{won}, lost %{lost}, played %{played}')) % {period: text(period_labels.fetch(index)),
          won: counts.fetch('won'), lost: counts.fetch('lost'), played: counts.fetch('won') + counts.fetch('lost')}
      end
      header = text(_('%{player} against %{opponent}')) % {player: text(@player), opponent: entry_name(entry)}
      field = EditBox.new(header, type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine, text: lines.join("\n"), quiet: true)
      back = Button.new(text(_('Back')))
      form = GameRoomUI::Form.new([field, back], program: @program, quiet: true)
      form.cancel_button = back
      back.on(:press) { form.resume }
      form.wait
    end

    def empty_statistics(user)
      {'user'=>user, 'won'=>0, 'lost'=>0, 'scored'=>0, 'conceded'=>0}
    end

    def statistics_text(row)
      [text(_('Matches played: %{count}')) % {count: row.fetch('won') + row.fetch('lost')},
        text(_('Matches won: %{count}')) % {count: row.fetch('won')},
        text(_('Matches lost: %{count}')) % {count: row.fetch('lost')},
        text(_('Match balance: %{count}')) % {count: row.fetch('won') - row.fetch('lost')},
        text(_('Goals scored: %{count}')) % {count: row.fetch('scored')},
        text(_('Goals conceded: %{count}')) % {count: row.fetch('conceded')},
        text(_('Goal balance: %{count}')) % {count: row.fetch('scored') - row.fetch('conceded')}].join("\n")
    end

  end
end
