require_relative "../support/rulebook_authoring"

root = File.expand_path("../..", __dir__)
registry = EltenGameRoom::GAME_REGISTRY
coverage = JSON.parse(File.read(File.join(root, "tools/rulebook_option_chapters.json"), encoding: "UTF-8"))
books = Dir.glob("tools/data/rulebooks/*.json", base: root).to_h do |relative_path|
  path = File.join(root, relative_path)
  [File.basename(path, ".json"), JSON.parse(File.read(path, encoding: "UTF-8"))]
end
assert(books.keys.sort == registry.ids.sort, "a game has no authored bilingual rules, or a retired game remains")
assert(coverage.keys.sort == registry.ids.sort, "option coverage differs from the actual game registry")

mo = File.binread(File.join(root, "locale/PL.mo"))
count, originals, translated = mo.byteslice(8, 12).unpack("V3")
reader = lambda do |offset|
  length, start = mo.byteslice(offset, 8).unpack("V2")
  mo.byteslice(start, length).force_encoding("UTF-8")
end
catalog = count.times.to_h { |index| [reader.call(originals + 8 * index), reader.call(translated + 8 * index)] }
options_count = paragraphs_count = 0
registry.ids.each do |id|
  game, authored = registry.build(id), books.fetch(id)
  source = File.join(root, authored.fetch("source"))
  assert(File.file?(source), "missing rule source for #{id}")
  sections = authored.fetch("sections")
  ids = sections.map { |section| section.fetch("id") }
  assert(ids.uniq == ids && ids.last == "controls", "bad section IDs/order for #{id}")
  actual = game.rule_sections.to_h { |section| [section.id.to_s, section] }
  expected_ids = ids + (authored["preserve_board_profiles"] ? ["board_profiles"] : [])
  assert(actual.keys.sort == expected_ids.sort, "compiled sections out of sync for #{id}")
  sections.each do |section|
    compiled = actual.fetch(section.fetch("id"))
    pairs = [section.fetch("title")] + section.fetch("paragraphs")
    assert(compiled.title == section["title"]["en"], "stale compiled heading for #{id}")
    assert(compiled.paragraphs == section["paragraphs"].map { |pair| pair.fetch("en") }, "stale compiled paragraphs for #{id}/#{section['id']}")
    pairs.each do |pair|
      en, pl = pair.fetch("en"), pair.fetch("pl")
      assert(en.valid_encoding? && pl.valid_encoding? && !en.strip.empty? && !pl.strip.empty?, "invalid bilingual text for #{id}")
      assert(en.scan(/%\{[^}]+\}/).sort == pl.scan(/%\{[^}]+\}/).sort, "translated placeholders differ for #{id}")
      assert(catalog[en] == pl, "Polish rules are not compiled for #{id}: #{en}")
      assert(!en.include?("TODO") && !pl.include?("TODO"), "unfinished rule text for #{id}")
    end
    paragraphs_count += section["paragraphs"].length
  end

  # This is an explicit editorial index, not a keyword-based assertion of
  # factual correctness. A new option must receive a reviewed chapter.
  keys = game.effective_option_definitions.map(&:key)
  # Transport configuration is shared infrastructure, not a game rule. Its
  # presence, validation and current-options text have dedicated P2P tests.
  # Keep the editorial index strict for each game's own rules.
  transport_keys = game.respond_to?(:p2p_option_definitions) ? game.p2p_option_definitions.map(&:key) : []
  local_keys = keys - ["bot_delay"] - transport_keys
  assert(local_keys.sort == coverage.fetch(id).keys.sort, "an option lacks a reviewed explanation for #{id}: #{local_keys - coverage[id].keys}")
  coverage.fetch(id).each do |key, chapter|
    assert(ids.include?(chapter) && chapter != "controls", "#{id}/#{key} points to no rule chapter")
  end
  options_count += local_keys.length
  book = game.rule_book(options: game.default_options)
  assert(book.documents.map(&:id) == [:rules, :controls, :current_options], "table rules changed their three-document structure for #{id}")
  assert(!book.documents.first.sections.any? { |section| section.id == :bot_pacing },
    "#{id}: generic bot pacing was appended to the complete authored edition")
end
puts "PASS authoring: #{books.length} bilingual books, #{paragraphs_count} paragraphs, #{options_count} actual options mapped to reviewed chapters; compiled rules and Polish catalogue agree"
