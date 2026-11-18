require_relative "game_statistics_periods"
require_relative "game_room_ui"
require_relative "game_room_background"

class GameRoomStatisticsMenu
  using GameRoomLocalization::Translations

  def initialize(program:, registry:, general:)
    @program, @registry, @general = program, registry, general
    @user = Session.name.to_s.dup.freeze
  end

  def run
    games = @registry.ids.map { |id| @registry.build(id) }.select(&:supports_player_statistics?)
    labels = [_('General')] + games.map(&:name)
    choices = ListBox.new(labels.map { |label| text(label) }, header: text(_('Statistics')), quiet: true)
    open_button, back = Button.new(text(_('Open'))), Button.new(text(_('Back')))
    form = GameRoomUI::Form.new([choices, open_button, back], program: @program, quiet: true)
    form.accept_button, form.cancel_button = open_button, back
    form.hide(open_button)
    form.hide(back)
    open_button.on(:press) do
      unless GameRoomParticipants.same?(@user, Session.name)
        form.resume
        next
      end
      choices.index.zero? ? @general.call : open_game(games.fetch(choices.index - 1))
    end
    back.on(:press) { form.resume }
    form.wait
  end

  private

  def text(value); GameRoomContent.utf8(value); end

  def open_game(game)
    client = game.build_player_statistics_client(@program)
    client&.run
  ensure
    client&.close
  end
end

class GameRoomStatisticsScreen
  using GameRoomLocalization::Translations

  class Form < GameRoomUI::Form
    attr_writer :statistics_update

    def update
      super
      @statistics_update&.call
    end
  end
  private_constant :Form

  def initialize(program:, reader:, years_reader:, registry:, today: -> { GameRoomStatistics::Periods.today }, valid: -> { true }, unavailable: -> { nil })
    @program, @reader, @years_reader, @registry, @today = program, reader, years_reader, registry, today
    @valid = valid
    @unavailable = unavailable
  end

  def run
    @work = GameRoomBackground::Work.new
    @generation = 0
    update_periods
    @period_list = ListBox.new(@periods.map(&:label), header: text(_("Period")), quiet: true)
    @summary = EditBox.new(text(_("Statistics")),
      type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
      text: summary_text(nil), quiet: true)
    @games = []
    @table = TableBox.new([_("Game"), _("Players"), _("Started"), _("Completed")].map { |label| text(label) },
      [], header: text(_("Games")), quiet: true, empty_label: empty_label(nil))
    details = Button.new(text(_("Game details")))
    @table.add_tip(text(_("Enter: show the selected game's mode breakdown.")))
    refresh = Button.new(text(_("Refresh")))
    back = Button.new(text(_("Back")))
    @form = Form.new([@summary, @period_list, @table, refresh, details, back], program: @program, quiet: true)
    @form.statistics_update = method(:update)
    @form.cancel_button = back
    @form.accept_button = details
    @form.hide(details)
    details.on(:press) { show_details if @form.fields[@form.index].equal?(@table) }
    @period_list.on(:move) do
      next if @periods.empty?
      @period = @periods.fetch(@period_list.index)
      request_data
    end
    refresh.on(:press) do
      update_periods
      render_periods
      request_data(refresh_years: true)
    end
    back.on(:press) { close; @form.resume }
    request_data(refresh_years: true)
    @form.wait
  ensure
    close
  end

  private

  def show_details
    row = @games[@table.index]
    return unless row
    modes = row.fetch(:data).fetch("modes")
    lines = [row.fetch(:cells).first] + @summary.text.lines.first(2).map(&:chomp)
    [["humans", _("Humans only")], ["bots", _("With bots")], ["solo", _("Solo")]].each do |key, label|
      counts = modes[key] || { "started" => 0, "completed" => 0 }
      lines << text(_("%{mode}: started %{started}, completed %{completed}")) % {
        mode: text(label), started: counts.fetch("started"), completed: counts.fetch("completed") }
    end
    content = EditBox.new(text(_("Game details")),
      type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine, text: lines.join("\n"), quiet: true)
    back = Button.new(text(_("Back")))
    form = GameRoomUI::Form.new([content, back], program: @program, quiet: true)
    form.cancel_button = back
    back.on(:press) { form.resume }
    form.wait
  end

  def text(value)
    GameRoomContent.utf8(value)
  end

  def update_periods
    @period_key = @period&.key || @period_key
    @date = @today.respond_to?(:call) ? @today.call : @today
    rebuild_periods
  rescue GameRoomNetworkErrors::ClockUnavailable
    # A cold or changed account may not have a confirmed server date yet.
    # Keep Refresh available without inventing a local date or querying tables.
    @periods, @period, @date = [], nil, nil
  end

  def rebuild_periods
    @period_key = @period&.key || @period_key
    @periods = GameRoomStatistics::Periods.options(today: @date, years: @years)
    @period = @periods.find { |period| period.key == @period_key } || @periods.first
  end

  def render_periods
    @period_list.options = @periods.map(&:label)
    @period_list.index = @periods.index(@period) || 0
  end

  def render_data(data, loading: false)
    @selected_game = @games[@table.index]&.fetch(:id) || @selected_game
    @summary.set_text(loading ? text(_("Loading statistics")) : summary_text(data))
    @games = game_rows(data)
    @table.rows = @games.map { |row| row.fetch(:cells) }
    @table.empty_label = loading ? text(_("Loading statistics")) : empty_label(data)
    @table.reload
    @table.index = @games.index { |row| row.fetch(:id) == @selected_game } || 0
  end

  # Keep at most one native worker and one latest selection, rather than
  # queuing every arrow key. Results only touch controls on the UI thread.
  def request_data(refresh_years: false)
    return if @closed
    previous = @pending_request || @active_request
    if @period && previous && previous[:period].key == @period.key && previous[:date] == @date &&
        (!refresh_years || previous[:refresh_years])
      return
    end
    @generation += 1
    @pending_request = @period && {generation: @generation, period: @period, date: @date, refresh_years: refresh_years}.freeze
    render_data(nil, loading: !@period.nil?)
    start_pending
  end

  def start_pending
    return if @closed || @active_request || !@pending_request
    unless @valid.call
      close
      @form.resume
      return
    end
    request, @pending_request = @pending_request, nil
    token = EltenAPI::Tasks::CancellationToken.new
    @active_request, @active_token = request, token
    @work.start do
      years = read_value(token) { @years_reader.call(token) } if request[:refresh_years]
      data = read_value(token) { @reader.call(request[:period], token) }
      {years: years, data: data}
    end
  rescue EltenAPI::Tasks::Busy => error
    @active_request = @active_token = nil
    log_read_error(error)
    render_data(nil)
  end

  def update
    return false if @closed
    unless @valid.call && !@work.closed?
      close
      @form.resume
      return false
    end
    if (outcome = @work.take)
      request, @active_request = @active_request, nil
      @active_token = nil
      result, error = outcome
      log_read_error(error) if error
      result ||= {years: nil, data: nil}
      # Year discovery is useful even if the user has already selected a
      # different period. It must still belong to the same confirmed date.
      if request[:refresh_years] && request[:date] == @date
        @years_unavailable = result[:years].nil?
        @years = result[:years] unless @years_unavailable
        rebuild_periods
        render_periods
      end
      if request[:generation] == @generation
        render_data(result[:data])
        if @form.fields[@form.index].equal?(@summary) && @form.game_room_hotkeys_active? && !@form.game_room_background_help?
          @summary.focus
        end
      end
    end
    start_pending
    !!(@active_request || @pending_request)
  end

  def close
    @closed = true
    @pending_request = nil
    @active_token&.cancel
    @work&.close
    @form.statistics_update = nil if @form
  end

  def read_value(token)
    token.raise_if_cancelled!
    return unless @valid.call
    result = yield
    token.raise_if_cancelled!
    result if @valid.call
  rescue EltenAPI::Tasks::Cancelled
    nil
  rescue StandardError => error
    log_read_error(error)
    nil
  end

  def log_read_error(error)
    Log.warning("Statistics read failed: #{error.class}: #{error.message}") if defined?(Log)
  end

  def before_collection?(data)
    data && data["first_day"] && @period.to_day < data.fetch("first_day")
  end

  def empty_label(data)
    text(before_collection?(data) ? _("No statistics were collected for this period.") : unavailable_message)
  end

  def game_rows(data)
    return [] if !data || before_collection?(data)
    records = data.fetch("games").to_h { |game| [game.fetch("id"), game] }
    @registry.ids.map do |id|
      game = records[id] || { "players" => 0, "started" => 0, "completed" => 0, "modes" => {} }
      name = text(@registry.name(id))
      { id: id, data: game, cells: [name, text(game.fetch("players")), text(game.fetch("started")), text(game.fetch("completed"))] }
    end.sort_by do |row|
      game = row.fetch(:data)
      empty = %w[players started completed].all? { |key| game.fetch(key).zero? }
      [empty ? 1 : 0, -game.fetch("completed"), -game.fetch("started"), row.fetch(:cells).first.downcase, row.fetch(:id)]
    end
  end

  def summary_text(data)
    return text(unavailable_message) unless @period
    first_date = data && data["first_day"] && Date.strptime(data.fetch("first_day").to_s, "%Y%m%d")
    from = @period.from_date || first_date
    lines = [text(_("Period: %{period}")) % { period: @period.label },
      text(_("Date range: %{from} to %{to} (inclusive; Europe/Warsaw)")) % {
        from: from ? from.iso8601 : text(_("collection start (unknown)")), to: @period.to_date.iso8601 }]
    lines << text(_("The list of years could not be loaded. Try Refresh.")) if @years_unavailable && !@unavailable.call
    return (lines + [text(unavailable_message)]).join("\n") unless data
    lines << if first_date
      text(_("Collection started: %{date}.")) % { date: first_date.iso8601 }
    else
      text(_("No collection start date is available."))
    end
    return (lines + [empty_label(data)]).join("\n") if before_collection?(data)
    if data["partial"] || (@period.from_date && first_date && @period.from_date < first_date)
      lines << text(_("Coverage is partial. Older client versions and uncollected days may be missing."))
    end
    (lines + [text(_("Visitors: %{count}")) % { count: data.fetch("visitors") },
      text(_("Players: %{count}")) % { count: data.fetch("players") },
      text(_("Games started: %{count}")) % { count: data.fetch("started") },
      text(_("Games completed: %{count}")) % { count: data.fetch("completed") }
    ]).join("\n")
  end

  def unavailable_message
    @unavailable.call || _('Statistics could not be loaded. Check your connection and try Refresh.')
  end
end
