require_relative "../support/rules_native_navigation"
require_relative "../../tools/support/release_files"

root = File.expand_path("../..", __dir__)
manifest = JSON.parse(File.read(File.join(root, "manifest.json"), encoding: "UTF-8"))
paths = GameRoomReadmeView::FILES
assert(paths.keys.sort == manifest.fetch("supported_languages").sort, "Every interface language needs a complete README")
assert(paths.values.sort == (["README.md"] + GameRoomReleaseFiles::README_TRANSLATIONS).sort, "README runtime and installer lists differ")
assert(GameRoomReadmeView.path("future") == paths.fetch("en"), "Future unknown language has no English fallback")
source = File.read(File.join(root, "README.md"), encoding: "UTF-8")
taboo_intro = "W grze taboo potrzebujesz komunikacji z innymi graczami. Możesz użyć do tego konferencji w eltenie, innego komunikatora lub grać na żywo."
assert(source.gsub(/\s+/, " ").include?(taboo_intro), "Polish Taboo introduction differs from the requested text")
levels = source.lines.filter_map { |line| line[/\A(#+) /, 1]&.length }
bullets = source.lines.count { |line| line.start_with?("- ") }
menu = EltenGameRoom::MAIN_OPTIONS
settings_index = menu.index(GameRoomLocalization.translate("Settings"))
assert(settings_index, "Settings is missing from the initial menu language")
assert(menu[-2] == "README", "README is not immediately before What's new")

app = EltenGameRoom.allocate
requested = []
app.define_singleton_method(:asset_path) { |path| requested << path; File.join(root, path) }
app.define_singleton_method(:read_text) { |*| raise "README was read from account data" }
app.define_singleton_method(:run_network_task) { |*| raise "README opened a network task" }
app.define_singleton_method(:alert) { |text| (@readme_alerts ||= []) << text }

paths.each do |language, path|
  GameRoomTestLocalization.use_language(language)
  assert(GameRoomReadmeView.path == path, "#{language}: document does not follow interface language")
  bytes = File.binread(File.join(root, path))
  markdown = bytes.dup.force_encoding(Encoding::UTF_8)
  assert(markdown.valid_encoding?, "#{language}: invalid UTF-8")
  assert(!markdown.include?("*"), "#{language}: README contains unwanted asterisks")
  assert(markdown.lines.filter_map { |line| line[/\A(#+) /, 1]&.length } == levels, "#{language}: section structure differs from the user's README")
  assert(markdown.lines.count { |line| line.start_with?("- ") } == bullets, "#{language}: missing list entries")
  %w[Ctrl+R Ctrl+W Ctrl+I Ctrl+Shift+I Ctrl+J Ctrl+O Ctrl+M Ctrl+Shift+R Ctrl+Q Ctrl+X Ctrl+F1 Ctrl+F4 Ctrl+P Ctrl+N Ctrl+S Ctrl+Shift+S Ctrl+Home Ctrl+End Shift+C Shift+H Shift+M Ctrl+C Ctrl+Shift+H Ctrl+H].each do |key|
    assert(markdown.include?(key), "#{language}: missing shortcut #{key}")
  end
  visited = false
  Form.driver = lambda do |form|
    visited = true
    field = form.fields.first
    assert(field.is_a?(GameRoomReadmeView), "README menu did not open its native document view")
    assert(field.flags & EditBox::Flags::ReadOnly != 0, "README can be edited")
    assert(form.accept_button.nil?, "Enter closes README instead of following links")
    assert(form.cancel_button == form.fields.last, "Escape does not use the Close action")
    assert(form.game_room_program.equal?(app), "README bypasses the shared program form")
    field.extend(NativeRuleInput)
    headings = elements(field, EditBox::Element::Header)
    expected_titles = markdown.lines.filter_map { |line| line.chomp[/\A#+ (.+)$/, 1] }
    assert(headings.map { |h| field.text_range(h.from, h.to) } == expected_titles, "#{language}: native headings or Unicode offsets changed")
    links = elements(field, EditBox::Element::Link)
    contents = links.select { |link| link.param[1].start_with?("#") }
    assert(contents.length == 16, "#{language}: lost a contents or chapter link")
    contents.each do |link|
      target = field.instance_variable_get(:@contents_targets)[link]
      assert(target, "#{language}: broken internal link #{link.param[1]}")
      field.index = link.from
      field.press(:key_enter)
      assert(field.index == target.from && field.check == target.from, "#{language}: contents did not move caret and selection")
      assert(field.announcements == [field.text_range(target.from, target.to)], "#{language}: contents did not read just the heading")
      assert(field.opened_urls.to_a.empty?, "Internal README link opened a browser")
    end
    [[72, headings], [75, links]].each do |key, targets|
      field.index = targets[0].from
      field.press(key)
      assert(field.index == targets[1].from, "#{language}: native forward navigation failed")
      field.press(key, reverse: true)
      assert(field.index == targets[0].from, "#{language}: native backward navigation failed")
    end
    external = links.reject { |link| link.param[1].start_with?("#") }
    assert(external.length == 10, "#{language}: missing repository link")
    assert(external.all? { |link| link.param[1].start_with?("https://github.com/papierek1997/elten-game-room/") }, "Repository-only docs became missing local links")
    external.each do |link|
      field.index = link.from
      field.press(:key_enter)
      assert(field.opened_urls.last == link.param[1], "External link bypassed native process_url")
    end
    form.cancel_button.trigger(:press)
  end
  app.send(:open_main_option, menu.length - 2)
  assert(visited && requested.last == path, "#{language}: menu did not read its packaged asset")
end
Form.driver = nil

# Duplicate headings still have distinct GitHub-style anchors.
field = GameRoomReadmeView.new("README".b, text: "[one](#żółw) [two](#żółw-1)\n\n## Żółw\n\n## Żółw\n".b)
targets = field.instance_variable_get(:@contents_targets).values
assert(targets.none?(&:nil?) && targets.uniq.length == 2, "Duplicate Unicode headings share an anchor")

%i[show_settings show_changelog].each { |method| app.define_singleton_method(method) { @selected_action = method } }
app.send(:open_main_option, settings_index)
assert(app.instance_variable_get(:@selected_action) == :show_settings, "Settings menu route changed")
app.send(:open_main_option, menu.length - 1)
assert(app.instance_variable_get(:@selected_action) == :show_changelog, "What's new menu route changed")
[nil, File.join(root, "does-not-exist-readme.md")].each do |missing|
  app.define_singleton_method(:asset_path) { |_| missing }
  app.send(:show_readme)
end
assert(app.instance_variable_get(:@readme_alerts).length == 2, "Missing README did not show a recoverable error")
puts "PASS README: #{$assertions} checks across all interface languages, native Markdown navigation, main menu, missing files and installer coverage"
