require "json"
require_relative "../support/rules_native_navigation"

root = File.expand_path("../..", __dir__)
registry = EltenGameRoom::GAME_REGISTRY
languages = JSON.parse(File.read(File.join(root, "manifest.json"))).fetch("supported_languages")
owners = JSON.parse(File.read(File.join(root, "tools/rulebook_sources.json")))
paragraphs = options = lists = books = 0

languages.each do |language|
  GameRoomTestLocalization.use_language(language)
  paths = Dir.glob("tools/data/rulebooks/#{language.upcase}/*.json", base: root)
  assert(paths.map { |path| File.basename(path, ".json") }.sort == registry.ids.sort,
    "#{language}: the complete edition must cover every registered game")
  paths.each do |relative|
    source = JSON.parse(File.read(File.join(root, relative), encoding: "UTF-8"))
    id = File.basename(relative, ".json")
    assert(source.fetch("source") == owners.fetch("#{id}.json").fetch("source"),
      "#{language}/#{id}: rulebook belongs to the wrong game")
    game = registry.build(id)
    expected = source.fetch("sections")
    ids = expected.map { |section| section.fetch("id") }
    assert(ids.uniq == ids && ids.last == "controls", "#{language}/#{id}: invalid chapter order")
    compiled = game.send(:localized_rule_sections)
    assert(compiled && compiled.map { |section| section.id.to_s } == ids,
      "#{language}/#{id}: localized chapter order differs")
    compiled.zip(expected).each do |section, authored|
      assert(section.title == authored.fetch("title").fetch(language), "#{language}/#{id}: heading differs")
      text = authored.fetch("paragraphs").map { |pair| pair.fetch(language) }
      assert(section.paragraphs == text, "#{language}/#{id}/#{section.id}: authored text differs")
      assert(([section.title] + section.paragraphs).all? { |line| line.encoding == Encoding::UTF_8 && line.valid_encoding? && !line.empty? },
        "#{language}/#{id}: invalid localized encoding")
      paragraphs += text.length
    end
    definitions = game.effective_option_definitions.map(&:key)
    transport = game.respond_to?(:p2p_option_definitions) ? game.p2p_option_definitions.map(&:key) : []
    keys = definitions - ["bot_delay"] - transport
    coverage = source.fetch("option_chapters")
    assert(coverage.keys.sort == keys.sort, "#{language}/#{id}: a game option has no reviewed explanation")
    coverage.each do |key, chapter|
      assert(ids.include?(chapter) && chapter != "controls", "#{language}/#{id}/#{key}: missing chapter")
    end
    options += keys.length

    book = game.rule_book(options: game.default_options)
    assert(book.documents.map(&:id) == [:rules, :controls, :current_options], "#{language}/#{id}: document navigation changed")
    rendered = book.documents.first.sections.map { |section| [section.id, section.title, section.paragraphs] }
    authored = compiled.reject { |section| section.id == :controls }.map { |section| [section.id, section.title, section.paragraphs] }
    assert(rendered == authored,
      "#{language}/#{id}: old or foreign chapters leaked into the authored rules")
    screen = GameRoomScreens::GameRules.new(book, game_shortcuts: ["Current field shortcut"])
    screen.instance_variable_get(:@documents).each do |document|
      field = screen.send(:section_form, document).fields.first
      if document.id == :controls
        assert(field.options == ["Current field shortcut"], "#{language}/#{id}: live shortcuts were replaced")
        next
      end
      check_document(field, document, "#{language}/#{id}/#{document.id}")
      items = elements(field, EditBox::Element::ListItem)
      expected_items = document.sections.flat_map(&:paragraphs).select { |line| line.match?(/\A(?:- |\d+\. )/) }
      assert(items.map { |item| field.text_range(item.from, item.to) } == expected_items,
        "#{language}/#{id}: native list items differ from the authored paragraphs")
      lists += items.length
    end
    books += 1
  end
end

# Switching back must not leave a book cached in the previously used language.
%w[pl en ru cs es pl].each do |language|
  GameRoomTestLocalization.use_language(language)
  game = registry.build("krowa")
  source = JSON.parse(File.read(File.join(root, "tools/data/rulebooks", language.upcase, "krowa.json"), encoding: "UTF-8"))
  assert(game.rule_book.documents.first.sections.first.title == source.fetch("sections").first.fetch("title").fetch(language),
    "Switching to #{language} retained another language's book")
end

GameRoomTestLocalization.use_language("missing_translation")
fallback = registry.build("krowa").rule_book.documents.first
english = JSON.parse(File.read(File.join(root, "tools/data/rulebooks/EN/krowa.json"), encoding: "UTF-8"))
assert(fallback.sections.first.title == english.fetch("sections").first.fetch("title").fetch("en"),
  "Missing interface catalogue must fall back to the complete English book")

puts "PASS localized rulebooks: #{books} books in #{languages.join(', ')}, #{paragraphs} paragraphs, #{options} option mappings, #{lists} native list items (#{$assertions} assertions)"
