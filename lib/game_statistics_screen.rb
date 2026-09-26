require_relative "game_statistics_periods"
require_relative "game_room_ui"

class GameRoomStatisticsScreen
  using GameRoomLocalization::Translations

  def initialize(program:, reader:, years_reader:, registry:, today: -> { GameRoomStatistics::Periods.today })
    @program, @reader, @years_reader, @registry, @today = program, reader, years_reader, registry, today
  end

  def run
    update_periods
    @period_list = ListBox.new(@periods.map(&:label), header: text(_("Period")), quiet: true)
    data = read_data
    @summary = EditBox.new(text(_("Statistics")),
      type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
      text: summary_text(data), quiet: true)
    @games = game_rows(data)
    @table = TableBox.new([_("Game"), _("Players"), _("Started"), _("Completed")].map { |label| text(label) },
      @games.map { |row| row.fetch(:cells) }, header: text(_("Games")), quiet: true,
      empty_label: empty_label(data))
    details = Button.new(text(_("Game details")))
    @table.add_tip(text(_("Enter: show the selected game's mode breakdown.")))
    refresh = Button.new(text(_("Refresh")))
    back = Button.new(text(_("Back")))
    @form = GameRoomUI::Form.new([@summary, @period_list, @table, refresh, details, back], program: @program, quiet: true)
    @form.cancel_button = back
    @form.accept_button = details
    @form.hide(details)
    details.on(:press) { show_details if @form.fields[@form.index].equal?(@table) }
    @period_list.on(:move) do
      @period = @periods.fetch(@period_list.index)
      refresh_data
    end
    refresh.on(:press) do
      update_periods
      @period_list.options = @periods.map(&:label)
      @period_list.index = @periods.index(@period)
      refresh_data
    end
    back.on(:press) { @form.resume }
    @form.wait
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
    key = @period&.key
    today = @today.respond_to?(:call) ? @today.call : @today
    years = read_years
    @years_unavailable = years.nil?
    @years = years unless years.nil?
    @periods = GameRoomStatistics::Periods.options(today: today, years: @years)
    @period = @periods.find { |period| period.key == key } || @periods.first
  end

  def refresh_data
    selected = @games[@table.index]&.fetch(:id)
    data = read_data
    @summary.set_text(summary_text(data))
    @games = game_rows(data)
    @table.rows = @games.map { |row| row.fetch(:cells) }
    @table.empty_label = empty_label(data)
    @table.reload
    @table.index = @games.index { |row| row.fetch(:id) == selected } || 0
  end

  def read_years
    @years_reader.call
  rescue StandardError => error
    Log.warning("Statistics read failed: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  def read_data
    @reader.call(@period)
  rescue StandardError => error
    Log.warning("Statistics read failed: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  def before_collection?(data)
    data && data["first_day"] && @period.to_day < data.fetch("first_day")
  end

  def empty_label(data)
    text(before_collection?(data) ? _("No statistics were collected for this period.") : _("Statistics unavailable"))
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
    first_date = data && data["first_day"] && Date.strptime(data.fetch("first_day").to_s, "%Y%m%d")
    from = @period.from_date || first_date
    lines = [text(_("Period: %{period}")) % { period: @period.label },
      text(_("Date range: %{from} to %{to} (inclusive; Europe/Warsaw)")) % {
        from: from ? from.iso8601 : text(_("collection start (unknown)")), to: @period.to_date.iso8601 }]
    lines << text(_("Calendar years are unavailable. Try Refresh.")) if @years_unavailable
    return (lines + [text(_("Statistics are unavailable. Try Refresh."))]).join("\n") unless data
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
end
