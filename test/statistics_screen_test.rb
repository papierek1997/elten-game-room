require "date"
require_relative "support/ui"
require_relative "support/host_source"
require_relative "../lib/game_content"

module EltenAPI
  module Controls
    module WaitForItem; end
    class SpeechSequence; end
    class FormField < FakeControl
      def text_utf8(value); GameRoomContent.utf8(value); end
      def on(event, &handler)
        @handlers ||= {}
        super
      end
    end
  end
end
class ListBox
  def item_states; @item_states ||= {}; end
  def clear_item_audio; end
end
load File.join(EltenTestHost.root, "src/ui/controls/table_box.rb")
TableBox = EltenAPI::Controls.const_get(:TableBox)

class Form
  class << self
    attr_accessor :statistics_driver
  end
  def wait
    Form.statistics_driver.call(self)
  end
end

def assert(value, message)
  raise message unless value
end

%w[game_statistics_periods game_statistics_screen].each do |name|
  path = File.expand_path("../lib/#{name}.rb", __dir__)
  next unless File.file?(path)
  TOPLEVEL_BINDING.eval(File.binread(path), path)
  $LOADED_FEATURES << path
end
assert(defined?(GameRoomStatisticsScreen), "Statistics screen is missing")
GameRoomLocalization.boot(host_language: "en", settings: { "interface_language" => "en" })

Registry = Struct.new(:names) do
  def ids; names.keys; end
  def name(id); names.fetch(id); end
end
registry = Registry.new({ "alpha" => "Alpha", "beta" => "Beta" })
program = Object.new
data = {
  "visitors" => 12, "players" => 8, "started" => 6, "completed" => 4,
  "first_day" => 20260920, "partial" => false, "games" => []
}
reads = []
Form.statistics_driver = lambda do |form|
  assert(form.is_a?(GameRoomUI::Form) && form.game_room_program.equal?(program), "Statistics lost application-aware UI")
  summary = form.fields.first
  assert(summary.is_a?(EditBox) && summary.flags & EditBox::Flags::ReadOnly != 0 &&
    summary.flags & EditBox::Flags::MultiLine != 0, "Statistics does not start with a read-only summary")
  ["Visitors: 12", "Players: 8", "Games started: 6", "Games completed: 4", "2026-09-25", "Europe/Warsaw"].each do |text|
    assert(summary.text.include?(text), "Summary is missing #{text}")
  end
  assert(reads.length == 1 && reads.first.key == "today", "Opening statistics does not read exactly Today once")
  assert(form.cancel_button, "Statistics has no Escape/Back action")
  assert(form.instance_variable_get(:@timers).to_a.empty?, "Statistics installed polling")
  form.cancel_button.trigger(:press)
end
GameRoomStatisticsScreen.new(program: program, reader: ->(period) { reads << period; data },
  years_reader: -> { [] }, registry: registry, today: Date.new(2026, 9, 25)).run
registry = Registry.new({ "zero" => "A zero", "b" => "Beta", "a" => "Alpha", "lead" => "Leader", "started" => "Starter" })
games = [
  { "id" => "b", "players" => 4, "started" => 5, "completed" => 2, "modes" => {} },
  { "id" => "a", "players" => 3, "started" => 5, "completed" => 2, "modes" => {} },
  { "id" => "lead", "players" => 8, "started" => 4, "completed" => 3, "modes" => {} },
  { "id" => "started", "players" => 2, "started" => 6, "completed" => 2, "modes" => {} }
]
Form.statistics_driver = lambda do |form|
  table = form.fields.find { |field| field.is_a?(TableBox) }
  assert(table, "Statistics has no accessible native table")
  assert(table.columns == ["Game", "Players", "Started", "Completed"], "Game table lacks named count columns")
  assert(table.rows == [["Leader", "8", "4", "3"], ["Starter", "2", "6", "2"],
    ["Alpha", "3", "5", "2"], ["Beta", "4", "5", "2"], ["A zero", "0", "0", "0"]],
    "Games are missing, not sorted by completed/started/name, or zeros are not last")
  assert(table.options.first.include?("Completed: 3"), "Native table did not expose count column speech")
  form.cancel_button.trigger(:press)
end
GameRoomStatisticsScreen.new(program: program, reader: ->(_) { data.merge("games" => games) },
  years_reader: -> { [] }, registry: registry, today: Date.new(2026, 9, 25)).run
reads = []
year_reads = 0
Form.statistics_driver = lambda do |form|
  periods = form.fields.find { |field| field.is_a?(ListBox) }
  refresh = form.fields.find { |field| field.is_a?(Button) && field.label == "Refresh" }
  assert(periods && refresh, "Statistics lacks period selection or deliberate refresh")
  assert(periods.options.include?("2025") && periods.options.last == "All time", "Available years or All time are missing")
  table = form.fields.find { |field| field.is_a?(TableBox) }
  form.index = form.fields.index(periods)
  periods.index = 1
  periods.trigger(:move)
  assert(reads.map(&:key) == %w[today last_7], "Changing period does not read that period exactly once")
  assert(form.fields.first.text.include?("2026-09-19 to 2026-09-25"), "Period range was not refreshed")
  assert(form.fields.first.text.include?("Visitors: 13"), "Period summary is stale")
  assert(form.index == form.fields.index(periods), "Changing period stole keyboard focus")
  table.index = 2
  form.index = form.fields.index(refresh)
  refresh.trigger(:press)
  assert(reads.map(&:key) == %w[today last_7 last_7], "Refresh changed the selected period or polled twice")
  assert(table.rows[table.index].first == "Alpha", "Refresh lost the selected game")
  assert(form.index == form.fields.index(refresh), "Refresh stole keyboard focus")
  assert(year_reads == 2, "Refresh failed to rediscover years or period navigation queried years")
  form.cancel_button.trigger(:press)
end
GameRoomStatisticsScreen.new(program: program,
  reader: ->(period) { reads << period; data.merge("visitors" => 11 + reads.length, "games" => games) },
  years_reader: -> { year_reads += 1; [2025] }, registry: registry, today: Date.new(2026, 9, 25)).run
[->(_) { nil }, ->(_) { raise IOError, "offline" }].each do |failed_reader|
  Form.statistics_driver = lambda do |form|
    summary = form.fields.first.text
    table = form.fields.find { |field| field.is_a?(TableBox) }
    assert(summary.include?("Statistics are unavailable. Try Refresh."), "A read failure was not explained")
    assert(!summary.include?("Visitors: 0") && table.rows.empty?, "A read failure was presented as zero activity")
    assert(table.empty_label == "Statistics unavailable", "An empty failed table has no accessible status")
    form.cancel_button.trigger(:press)
  end
  GameRoomStatisticsScreen.new(program: program, reader: failed_reader, years_reader: -> { [] },
    registry: registry, today: Date.new(2026, 9, 25)).run
end
responses = [data.merge("games" => games), nil, data.merge("games" => games)]
Form.statistics_driver = lambda do |form|
  table = form.fields.find { |field| field.is_a?(TableBox) }
  refresh = form.fields.find { |field| field.is_a?(Button) && field.label == "Refresh" }
  refresh.trigger(:press)
  assert(table.rows.empty? && form.fields.first.text.include?("unavailable"), "Failed refresh leaves stale counts on screen")
  refresh.trigger(:press)
  assert(!table.rows.empty? && form.fields.first.text.include?("Visitors: 12"), "Refresh cannot recover from a failed read")
  form.cancel_button.trigger(:press)
end
GameRoomStatisticsScreen.new(program: program, reader: ->(_) { responses.shift }, years_reader: -> { [] },
  registry: registry, today: Date.new(2026, 9, 25)).run
[-> { nil }, -> { raise IOError, "years offline" }].each do |failed_years|
  Form.statistics_driver = lambda do |form|
    periods = form.fields.find { |field| field.is_a?(ListBox) }
    assert(periods.options == ["Today", "Last 7 days (including today)", "Last 30 days (including today)",
      "Last 365 days (including today)", "2026", "All time"], "Unavailable years hide required periods")
    assert(form.fields.first.text.include?("Calendar years are unavailable. Try Refresh."), "Year discovery failure is silent")
    form.cancel_button.trigger(:press)
  end
  GameRoomStatisticsScreen.new(program: program, reader: ->(_) { data }, years_reader: failed_years,
    registry: registry, today: Date.new(2026, 9, 25)).run
end
[false, true].each do |partial|
  Form.statistics_driver = lambda do |form|
    summary = form.fields.first
    assert(summary.text.include?("Collection started: 2026-09-20."), "Collection start date is missing")
    assert(summary.text.include?("Coverage is partial.") == partial, "Backend partial coverage is not represented")
    periods = form.fields.find { |field| field.is_a?(ListBox) }
    periods.index = 2
    periods.trigger(:move)
    assert(summary.text.include?("Coverage is partial."), "Dates before collection imply falsely complete coverage")
    periods.index = periods.options.length - 1
    periods.trigger(:move)
    assert(summary.text.include?("2026-09-20 to 2026-09-25"), "All-time range does not use the actual collection start")
    form.cancel_button.trigger(:press)
  end
  GameRoomStatisticsScreen.new(program: program, reader: ->(_) { data.merge("partial" => partial) },
    years_reader: -> { [] }, registry: registry, today: Date.new(2026, 9, 25)).run
end
Form.statistics_driver = lambda do |form|
  periods = form.fields.find { |field| field.is_a?(ListBox) }
  periods.index = periods.options.length - 1
  periods.trigger(:move)
  assert(form.fields.first.text.include?("No collection start date is available."), "Unknown coverage claims an invented collection date")
  form.cancel_button.trigger(:press)
end
GameRoomStatisticsScreen.new(program: program, reader: ->(_) { data.merge("first_day" => nil) },
  years_reader: -> { [] }, registry: registry, today: Date.new(2026, 9, 25)).run
Form.statistics_driver = lambda do |form|
  periods = form.fields.find { |field| field.is_a?(ListBox) }
  periods.index = periods.options.index("2025")
  periods.trigger(:move)
  assert(form.fields.first.text.include?("No statistics were collected for this period."), "Pre-collection year claims measured activity")
  table = form.fields.find { |field| field.is_a?(TableBox) }
  assert(table.rows.empty? && !form.fields.first.text.include?("Visitors:"), "Pre-collection year displays counts")
  assert(table.empty_label == "No statistics were collected for this period.", "Uncollected table is labelled unavailable")
  form.cancel_button.trigger(:press)
end
GameRoomStatisticsScreen.new(program: program, reader: ->(_) { data }, years_reader: -> { [2025] },
  registry: registry, today: Date.new(2026, 9, 25)).run
detail_reads = 0
detail_visits = 0
modes = { "humans" => { "started" => 3, "completed" => 2 },
  "bots" => { "started" => 1, "completed" => 1 }, "solo" => { "started" => 0, "completed" => 0 } }
Form.statistics_driver = lambda do |form|
  table = form.fields.find { |field| field.is_a?(TableBox) }
  if table
    assert(form.accept_button, "The statistics table has no Enter action")
    form.index = form.fields.index(table)
    table.index = 0
    form.accept_button.trigger(:press)
    assert(detail_visits == 1 && detail_reads == 1, "Opening game details duplicated the view or queried the server")
    assert(form.index == form.fields.index(table) && table.index == 0, "Closing details lost table focus")
    form.cancel_button.trigger(:press)
  else
    detail_visits += 1
    assert(form.game_room_program.equal?(program), "Game details lost the program reference")
    content = form.fields.first
    assert(content.is_a?(EditBox) && content.flags & EditBox::Flags::ReadOnly != 0, "Mode details are not readable text")
    ["Leader", "Humans only: started 3, completed 2", "With bots: started 1, completed 1",
      "Solo: started 0, completed 0", "2026-09-25"].each do |expected|
      assert(content.text.include?(expected), "Mode details lost #{expected}")
    end
    form.cancel_button.trigger(:press)
  end
end
GameRoomStatisticsScreen.new(program: program,
  reader: ->(_) { detail_reads += 1; data.merge("games" => games.map { |game| game.merge("modes" => modes) }) },
  years_reader: -> { [] }, registry: registry, today: Date.new(2026, 9, 25)).run
translation = Object.new
translation.define_singleton_method(:translate) do |source, **_options|
  { "Statistics" => "Statystyki", "Today" => "Dzisiaj", "Game" => "Gra", "Period" => "Okres" }[source]
end
GameRoomLocalization.instance_variable_set(:@translator,
  GameRoomLocalization::Translator.new(catalogs: { "pl" => translation }, primary: "pl", known: []))
registry_utf8 = Registry.new({ "z" => "Żółw".b.freeze, "a" => "Łódź".b.freeze })
utf8_forms = 0
Form.statistics_driver = lambda do |form|
  utf8_forms += 1
  form.fields.each do |field|
    strings = case field
    when TableBox then [field.header, field.empty_label] + field.columns + field.rows.flatten + field.options
    when EditBox then [field.header, field.text]
    when ListBox then [field.header] + field.options
    when Button then [field.label]
    else []
    end
    strings.each do |string|
      assert(string.encoding == Encoding::UTF_8 && string.valid_encoding?, "UI text was not UTF-8: #{string.inspect}")
      assert((string + " — выбранное поле").valid_encoding?, "Host role speech breaks a statistics field")
    end
    field.focus
  end
  table = form.fields.find { |field| field.is_a?(TableBox) }
  if table
    assert(form.fields.first.header == "Statystyki", "Statistics bypassed the local translation refinement")
    assert(table.rows.map(&:first) == ["Łódź", "Żółw"], "Games are not sorted by localized UTF-8 names")
    form.index = form.fields.index(table)
    form.accept_button.trigger(:press)
  end
  form.cancel_button.trigger(:press)
end
GameRoomStatisticsScreen.new(program: program, reader: ->(_) { data }, years_reader: -> { [] },
  registry: registry_utf8, today: Date.new(2026, 9, 25)).run
assert(utf8_forms == 2, "UTF-8 verification skipped game details")
GameRoomLocalization.boot(host_language: "en", settings: { "interface_language" => "en" })
Form.statistics_driver = lambda do |form|
  table = form.fields.find { |field| field.is_a?(TableBox) }
  assert(table.rows.map(&:first) == ["Z active", "A zero"], "A game with players but no starts is buried among zero rows")
  form.cancel_button.trigger(:press)
end
GameRoomStatisticsScreen.new(program: program,
  reader: ->(_) { data.merge("games" => [{ "id" => "active", "players" => 1, "started" => 0, "completed" => 0, "modes" => {} }]) },
  years_reader: -> { [] }, registry: Registry.new({ "zero" => "A zero", "active" => "Z active" }),
  today: Date.new(2026, 9, 25)).run
day = Date.new(2026, 12, 31)
reads = []
Form.statistics_driver = lambda do |form|
  periods = form.fields.find { |field| field.is_a?(ListBox) }
  refresh = form.fields.find { |field| field.is_a?(Button) && field.label == "Refresh" }
  periods.index = 1
  periods.trigger(:move)
  day = Date.new(2027, 1, 1)
  refresh.trigger(:press)
  assert(reads.last.key == "last_7" && reads.last.from_day == 20261226 && reads.last.to_day == 20270101,
    "Refresh does not reevaluate the supplied civil-date clock or preserve the period")
  assert(periods.options.include?("2027"), "New calendar year was not discovered automatically")
  form.cancel_button.trigger(:press)
end
GameRoomStatisticsScreen.new(program: program, reader: ->(period) { reads << period; data }, years_reader: -> { [2026] },
  registry: registry, today: -> { day }).run

Form.statistics_driver = lambda do |form|
  table = form.fields.find { |field| field.is_a?(TableBox) }
  assert(table.rows.length == registry.ids.length && table.rows.all? { |row| row.drop(1) == %w[0 0 0] },
    "A successful empty result hides games or invents activity")
  assert(form.fields.first.text.include?("Visitors: 0"), "A successful zero result is treated as a failure")
  form.cancel_button.trigger(:press)
end
GameRoomStatisticsScreen.new(program: program,
  reader: ->(_) { data.merge("visitors" => 0, "players" => 0, "started" => 0, "completed" => 0, "first_day" => nil) },
  years_reader: -> { [] }, registry: registry, today: Date.new(2026, 9, 25)).run
empty_details = 0
Form.statistics_driver = lambda do |form|
  empty_details += 1
  table = form.fields.find { |field| field.is_a?(TableBox) }
  form.index = form.fields.index(table)
  form.accept_button.trigger(:press)
  assert(empty_details == 1, "Enter on an unavailable table opens invented game details")
  form.cancel_button.trigger(:press)
end
GameRoomStatisticsScreen.new(program: program, reader: ->(_) { nil }, years_reader: -> { [] },
  registry: registry, today: Date.new(2026, 9, 25)).run

refresh_reads = 0
year_reads = 0
Form.statistics_driver = lambda do |form|
  table = form.fields.find { |field| field.is_a?(TableBox) }
  periods = form.fields.find { |field| field.is_a?(ListBox) }
  refresh = form.fields.find { |field| field.is_a?(Button) && field.label == "Refresh" }
  periods.index = periods.options.index("2026")
  periods.trigger(:move)
  table.index = table.rows.index { |row| row.first == "Alpha" }
  refresh.trigger(:press)
  assert(periods.options[periods.index] == "2026", "Failed year refresh lost a previously available calendar year")
  assert(table.rows[table.index].first == "Alpha", "Refresh preserved row number instead of game identity after sorting")
  assert(form.fields.first.text.include?("Calendar years are unavailable."), "Failed year refresh was silent")
  form.cancel_button.trigger(:press)
end
GameRoomStatisticsScreen.new(program: program,
  reader: ->(_) do
    refresh_reads += 1
    current_games = games.map { |game| game["id"] == "a" && refresh_reads > 2 ? game.merge("completed" => 7) : game }
    data.merge("games" => current_games)
  end,
  years_reader: -> { year_reads += 1; year_reads == 1 ? [2026] : nil },
  registry: registry, today: Date.new(2027, 1, 1)).run
module Log
  def self.warning(message)
    (@statistics_warnings ||= []) << message
  end
  def self.statistics_warnings; @statistics_warnings || []; end
end
Form.statistics_driver = ->(form) { form.cancel_button.trigger(:press) }
GameRoomStatisticsScreen.new(program: program, reader: ->(_) { raise IOError, "read failed" },
  years_reader: -> { raise IOError, "years failed" }, registry: registry, today: Date.new(2026, 9, 25)).run
assert(Log.statistics_warnings.any? { |line| line.include?("read failed") } &&
  Log.statistics_warnings.any? { |line| line.include?("years failed") }, "Unavailable UI discarded exception diagnostics")
puts "PASS statistics screen"
