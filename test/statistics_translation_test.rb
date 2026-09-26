# encoding: UTF-8
require_relative "support/background_help_native"
require_relative "support/localization"
require_relative "../tools/translation_extractor"
require File.join(EltenTestHost.root, "src/ui/controls/table_box")
require File.join(EltenTestHost.root, "src/ui/controls/grid_box")
require File.join(EltenTestHost.root, "src/ui/controls/menu")
require File.join(EltenTestHost.root, "src/eapi/mainmenu")
require_relative "../lib/game_surfaces"
require_relative "../lib/game_layout"
require_relative "../lib/game_history_navigation"

root = File.expand_path("..", __dir__)
sources = %w[lib/game_statistics_periods.rb lib/game_statistics_screen.rb lib/game_room_presence_screen.rb]
messages = sources.flat_map do |relative|
  GameRoomTranslationExtractor.extract_source(File.read(File.join(root, relative), encoding: "UTF-8"), path: relative, warnings: [])
end
ids = (messages.map { |message| message.fetch(:msgid) } + ["Loading statistics"]).uniq
catalog = GameRoomLocalization::Catalog.new(File.binread(File.join(root, "locale/PL.mo")))
missing = ids.select { |id| catalog.translate(id).to_s.empty? }
assert(missing.empty?, "Compiled Polish catalog misses statistics/presence UI: #{missing.join(', ')}")
ids.each do |id|
  translated = catalog.translate(id.b)
  assert(translated && translated != id, "Polish UI falls back to English: #{id}")
  assert(translated.encoding == Encoding::UTF_8 && translated.valid_encoding?, "Invalid Polish catalog text: #{id}")
  assert(id.scan(/%\{[^}]+\}/).sort == translated.scan(/%\{[^}]+\}/).sort, "Changed interpolation tokens: #{id}")
end
assert(catalog.translate("Statistics") == "Statystyki", "Statistics menu label is not Polish")
assert(catalog.translate("Current room activity") == "Obecnie w pokojach", "Room activity title is misleading")

(sources + ["lib/game_room_screens.rb"]).each do |relative|
  path = File.join(root, relative)
  TOPLEVEL_BINDING.eval(File.binread(path), path)
  $LOADED_FEATURES << path unless $LOADED_FEATURES.include?(path)
end
runtime = GameRoomTestLocalization.use_language("pl")
assert(runtime.catalog_reads.include?("pl"), "The app did not load the actual Polish MO")

def loop_update(*_args); end

class Form
  class << self
    attr_accessor :statistics_translation_driver
  end
  def wait
    @wait = true
    Form.statistics_translation_driver.call(self)
    assert(@wait == false, "Translated screen did not resume its native form")
  end
end

def verify_statistics_utf8(form)
  form.fields.each do |field|
    strings = case field
    when TableBox then [field.header, field.empty_label] + field.columns + field.rows.flatten
    when EditBox then [field.header, field.text]
    when ListBox then [field.header] + field.options
    when Button then [field.label]
    else []
    end
    strings.each do |text|
      assert(text.encoding == Encoding::UTF_8 && text.valid_encoding?, "Native Polish UI received invalid UTF-8")
      assert((text + " — выбранное поле").valid_encoding?, "Polish text breaks host role speech")
    end
    field.focus
  end
end

translate = ->(id) { catalog.translate(id) }
program = Object.new
registry = Struct.new(:names) do
  def ids; names.keys; end
  def name(id); names.fetch(id); end
end.new({ "chess" => "Szachy".b })
modes = { "humans" => { "started" => 3, "completed" => 2 },
  "bots" => { "started" => 2, "completed" => 1 }, "solo" => { "started" => 1, "completed" => 1 } }
data = { "visitors" => 12, "players" => 8, "started" => 6, "completed" => 4,
  "first_day" => 20260920, "partial" => true,
  "games" => [{ "id" => "chess", "players" => 8, "started" => 6, "completed" => 4, "modes" => modes }] }
forms = 0
Form.statistics_translation_driver = lambda do |form|
  forms += 1
  verify_statistics_utf8(form)
  summary = form.fields.first
  table = form.fields.find { |field| field.is_a?(TableBox) }
  if table
    assert(summary.header == "Statystyki", "Statistics screen did not use the compiled catalog")
    assert(table.columns == %w[Game Players Started Completed].map(&translate), "Table headers bypassed the catalog")
    %w[visitors players started completed].zip(["Visitors: %{count}", "Players: %{count}",
      "Games started: %{count}", "Games completed: %{count}"]).each do |key, id|
      assert(summary.text.include?(translate.call(id) % { count: data.fetch(key) }), "Missing translated count: #{id}")
    end
    periods = form.fields.find { |field| field.is_a?(ListBox) && !field.is_a?(TableBox) }
    expected = [translate.call("Today")] + [7, 30, 365].map { |days| translate.call("Last %{days} days (including today)") % { days: days } } +
      ["2026", "2025", translate.call("All time")]
    assert(periods.options == expected, "Not all statistics periods use the compiled Polish catalog")
    assert(summary.text.include?(translate.call("Coverage is partial. Older client versions and uncollected days may be missing.")),
      "Partial coverage explanation stayed English")
    assert(table.get_tips.include?(translate.call("Enter: show the selected game's mode breakdown.")), "Game details help stayed English")
    form.index = table
    form.accept_button.press
  else
    ["Humans only", "With bots", "Solo"].zip(modes.values).each do |id, counts|
      expected = translate.call("%{mode}: started %{started}, completed %{completed}") % {
        mode: translate.call(id), started: counts.fetch("started"), completed: counts.fetch("completed") }
      assert(summary.text.include?(expected), "Mode breakdown stayed English: #{id}")
    end
  end
  form.cancel_button.press
end
GameRoomStatisticsScreen.new(program: program, reader: ->(_) { data }, years_reader: -> { [2025] },
  registry: registry, today: Date.new(2026, 9, 25)).run
assert(forms == 2, "Polish statistics test missed the game details screen")

Form.statistics_translation_driver = lambda do |form|
  summary = form.fields.first
  table = form.fields.find { |field| field.is_a?(TableBox) }
  assert(summary.text.include?(translate.call("Statistics are unavailable. Try Refresh.")), "Statistics failure stayed English")
  assert(summary.text.include?(translate.call("Calendar years are unavailable. Try Refresh.")), "Calendar failure stayed English")
  assert(table.empty_label == translate.call("Statistics unavailable"), "Failed table has no translated status")
  verify_statistics_utf8(form)
  form.cancel_button.press
end
GameRoomStatisticsScreen.new(program: program, reader: ->(_) { nil }, years_reader: -> { nil },
  registry: registry, today: Date.new(2026, 9, 25)).run

presence = { "public_rooms" => 3, "private_rooms" => 2, "people" => 12 }
responses = [presence, nil, presence.merge("people" => 0)]
Form.statistics_translation_driver = lambda do |form|
  summary, refresh = form.fields
  assert(summary.header == "Obecnie w pokojach", "Presence screen title stayed English")
  assert(summary.text.include?("Pokoje publiczne: 3") && summary.text.include?("Pokoje prywatne: 2") &&
    summary.text.include?("Osoby w pokojach: 12"), "Translated presence counts are missing")
  ["sum", "obserwator", "bot", "więcej niż", "więcej niż raz", "online"].each do |meaning|
    assert(summary.text.include?(meaning), "Room membership explanation lost #{meaning}")
  end
  assert(refresh.label == "Odśwież", "Presence refresh stayed English")
  refresh.press
  assert(summary.text.include?(translate.call("Room activity is unavailable. Try Refresh.")), "Presence failure stayed English")
  assert(!summary.text.include?("Osoby w pokojach:"), "Presence failure retained stale counts")
  refresh.press
  assert(summary.text.include?("Osoby w pokojach: 0"), "Successful zero was confused with an unavailable result")
  verify_statistics_utf8(form)
  form.cancel_button.press
end
GameRoomPresenceScreen.new(program: program, reader: -> { responses.shift }).run

class StatisticsTranslationNativeInput
  def process_quick_action_hotkeys; end
  def speech_stop(*_args); end
end
Form.statistics_translation_driver = lambda do |form|
  options = form.fields.first
  menu = Menu.new
  options.context(menu, false)
  entry = menu.items.find { |item| item[0] == "Obecnie w pokojach" }
  assert(entry && entry[3] == "w", "Polish context menu lost native Ctrl+W")
  assert(options.get_tips.include?("Ctrl+W, Obecnie w pokojach."), "Polish context help disagrees with the action")
  driver = BackgroundHelpNativeDriver.new
  driver.root = form
  input = StatisticsTranslationNativeInput.new
  [[], [17, 87]].each do |keys|
    driver.keys = [keys]
    driver.tick(form)
    form.update
    input.send(:keyprocs)
  end
end
result = GameRoomScreens::MainMenu.new(options: ["Statystyki"], program: program).wait
assert(result.action == :room_activity, "Native Ctrl+W did not activate the Polish room activity action")
puts "PASS statistics/presence translations: #{ids.length} real MO entries, binary sources, native Polish forms/details/errors, Ctrl+W and UTF-8"
