require_relative "../support/rules_native_navigation"

languages = { "en" => "Contents", "pl" => "Spis treści", "cs" => "Obsah", "es" => "Índice", "ru" => "Содержание" }
assert(languages.keys.drop(1).sort == Dir.glob(File.expand_path("../../locale/*.po", __dir__)).map { |path| File.basename(path, ".po").downcase }.sort, "A packaged interface language is missing from native rendering coverage")
books = 0
fields = 0
languages.each do |language, contents_title|
  GameRoomTestLocalization.use_language(language)
  EltenGameRoom::GAME_REGISTRY.ids.each do |id|
    game = EltenGameRoom::GAME_REGISTRY.build(id)
    book = game.rule_book(options: game.default_options)
    screen = GameRoomScreens::GameRules.new(book, game_shortcuts: ["Snapshot shortcut"])
    assert(book.documents.first.contents_title == contents_title, "#{language}/#{game.id}: Contents translation missing")
    screen.instance_variable_get(:@documents).each do |document|
      form = screen.send(:section_form, document)
      field = form.fields.first
      if document.id == :controls
        assert(field.is_a?(ListBox) && field.options == ["Snapshot shortcut"], "#{language}/#{game.id}: shortcut snapshot changed")
      else
        check_document(field, document, "#{language}/#{game.id}/#{document.id}")
        fields += 1
      end
    end
    books += 1
  end
end

GameRoomTestLocalization.use_language("en")
paragraphs = ["[x](y)", "[x][y]", "[x][y]\n[y]: https://example.org/reference", "[:n]", "[:12]", "---", "===", "- literal", "* literal", "# literal", "http://example.org/rules", "Zażółć gęślą jaźń — Příliš žluťoučký — Índice — Содержание — ♠ 🎲", "Nested [text](https://example.org/nested) stays literal"]
sections = [
  GameRoomRules::Section.new(id: :first, title: "# [Shared](title) [:n] ♠ 🎲", paragraphs: paragraphs),
  GameRoomRules::Section.new(id: :second, title: "# [Shared](title) [:n] ♠ 🎲", paragraphs: ["Other section"])
]
document = GameRoomRules::Document.new(id: :rules, title: "Rules", sections: sections, contents: true)
field = GameRoomRules::View.new("Rules", document: document)
check_document(field, document, "Markdown metacharacters and duplicate headings")
headings = elements(field, EditBox::Element::Header)
links = elements(field, EditBox::Element::Link).select { |element| element.param[1].start_with?("#rule-section-") }

[[72, headings], [0x31, headings.select { |heading| heading.param == 1 }], [0x32, headings.select { |heading| heading.param == 2 }], [75, elements(field, EditBox::Element::Link)]].each do |key, targets|
  targets.each_cons(2) do |first, second|
    field.index = first.from
    field.press(key)
    assert(field.index == second.from, "Native forward #{key} navigation changed")
    field.press(key, reverse: true)
    assert(field.index == first.from, "Native reverse #{key} navigation changed")
  end
end
field.index = headings.last.from
field.press(0x31, reverse: true)
assert(field.index == headings.first.from, "Shift+1 did not reach Contents")
(0x33..0x36).each do |key|
  [false, true].each do |reverse|
    field.index = headings.first.from
    field.press(key, reverse: reverse)
    assert(field.index == headings.first.from, "Navigation to an absent heading level changed the caret")
  end
end
field.index = links.first.to + 1
field.press(:key_enter)
assert(field.index == headings[1].from && field.opened_urls.to_a.empty?, "Enter at the end of a contents line escaped to the browser")
external = elements(field, EditBox::Element::Link).find { |element| element.param[1] == "http://example.org/rules" }
assert(external, "Native external URL detection was lost")
field.index = external.from
field.press(:key_enter)
assert(field.opened_urls == ["http://example.org/rules"], "External link did not retain native process_url behavior")
assert(field.announcements == ["Opening a link..."], "External link did not retain its native announcement")

book = EltenGameRoom::GAME_REGISTRY.build("makao").rule_book(options: {})
screen = GameRoomScreens::GameRules.new(book, game_shortcuts: ["Live snapshot"])
visits = 0
Form.driver = lambda do |form|
  if visits == 0
    visits += 1
    form.accept_button.trigger(:press)
  elsif visits == 1
    check_document(form.fields.first, book.documents.first, "wait path")
    visits += 1
    form.cancel_button.trigger(:press)
  else
    form.cancel_button.trigger(:press)
  end
end
screen.wait
Form.driver = nil
assert(visits == 2, "Modal rule document was not visited")
parent = GameRoomUI::Form.new([], quiet: true)
screen.open_on(parent)
picker = parent.game_room_background_help_form
picker.accept_button.trigger(:press)
form = parent.game_room_background_help_form
check_document(form.fields.first, book.documents.first, "open_on path")
form.cancel_button.trigger(:press)
assert(parent.game_room_background_help_form.equal?(picker), "Closing the document lost its background picker")
picker.fields.first.index = 1
picker.accept_button.trigger(:press)
assert(parent.game_room_background_help_form.fields.first.options == ["Live snapshot"], "Background shortcuts lost their live snapshot")
parent.clear_game_room_background_help

puts "PASS real host rule navigation: #{books} books, #{languages.length} languages, #{fields} rendered documents, #{$internal_jumps} internal jumps, #{$assertions} assertions"
