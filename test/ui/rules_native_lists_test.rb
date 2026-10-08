require_relative "../support/rules_native_navigation"

GameRoomTestLocalization.use_language("pl")
sections = [
  GameRoomRules::Section.new(id: :melds, title: "Rodzaje układów", paragraphs: [
    "Możesz wyłożyć dwa rodzaje układów:",
    "- Seria to kolejne karty w jednym kolorze, na przykład 5, 6 i 7 kier.",
    "- Zestaw tworzą karty tej samej wartości w różnych kolorach.",
    "As może rozpoczynać lub kończyć serię."
  ]),
  GameRoomRules::Section.new(id: :steps, title: "Przygotowanie", paragraphs: [
    "1. Wybierz pierwszą kartę.", "2. Dobierz do niej pozostałe karty.",
    "Zdanie zawiera - myślnik, ale nie jest punktem listy.",
    "-5 punktów to liczba ujemna, a nie wypunktowanie.",
    "Więcej: https://example.org/rules"
  ])
]
[true, false].each do |contents|
  document = GameRoomRules::Document.new(id: :rules, title: "Zasady", sections: sections, contents: contents)
  field = GameRoomRules::View.new("Zasady", document: document)
  check_document(field, document, "native lists contents=#{contents}")
  items = elements(field, EditBox::Element::ListItem)
  expected = [*sections.first.paragraphs[1, 2], *sections.last.paragraphs[0, 2]]
  assert(items.map { |item| field.text_range(item.from, item.to) } == expected,
    "List recognition changed text or included ordinary prose")
  items.each_cons(2) do |first, second|
    field.index = first.from
    field.press(73)
    assert(field.index == second.from, "I did not reach the next list item")
    field.press(73, reverse: true)
    assert(field.index == first.from, "Shift+I did not reach the previous list item")
  end
  external = elements(field, EditBox::Element::Link).find { |element| element.param[1] == "https://example.org/rules" }
  assert(external, "List recognition removed a normal external link")
end

puts "PASS native rule lists: text, Unicode offsets, I/Shift+I, headings and contents links (#{$assertions} assertions)"
