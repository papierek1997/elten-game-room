require_relative "../support/rulebook_authoring"
require_relative "../support/authored_rulebooks"
require_relative "../support/localization"

root = File.expand_path("../..", __dir__)
registry = EltenGameRoom::GAME_REGISTRY
coverage = JSON.parse(File.read(File.join(root, "tools/rulebook_option_chapters.json"), encoding: "UTF-8"))
books = Dir.glob("tools/data/rulebooks/*.json", base: root).to_h do |relative_path|
  [File.basename(relative_path, ".json"), JSON.parse(File.read(File.join(root, relative_path), encoding: "UTF-8"))]
end
assert(books.keys.sort == registry.ids.sort, "a game has no authored rules, or a retired game remains")
assert(coverage.keys.sort == registry.ids.sort, "option coverage differs from the actual game registry")

options_count = paragraphs_count = 0
%w[en pl cs es ru].each do |language|
  GameRoomTestLocalization.use_language(language)
  registry.ids.each do |id|
    game = registry.build(id)
    authored = GameRoomTest::Rulebooks.read(id, language)
    assert(authored.fetch('source') == books.fetch(id).fetch('source'), "wrong localized source for #{id}/#{language}")
    assert(File.file?(File.join(root, authored.fetch('source'))), "missing rule source for #{id}")
    sections = authored.fetch('sections')
    ids = sections.map { |section| section.fetch('id') }
    assert(ids.uniq == ids && ids.last == 'controls', "bad section IDs/order for #{id}/#{language}")
    actual = game.rule_book.sections.to_h { |section| [section.id.to_s, section] }
    assert(actual.keys == ids, "compiled sections out of sync for #{id}/#{language}")
    sections.each do |section|
      compiled = actual.fetch(section.fetch('id'))
      assert(compiled.title == section.fetch('title').fetch(language), "stale heading for #{id}/#{language}")
      expected = section.fetch('paragraphs').map { |pair| pair.fetch(language) }
      assert(compiled.paragraphs == expected, "stale paragraphs for #{id}/#{language}/#{section['id']}")
      [compiled.title, *expected].each do |text|
        assert(text.is_a?(String) && text.encoding == Encoding::UTF_8 && text.valid_encoding? && !text.strip.empty?, "invalid text for #{id}/#{language}")
        assert(!text.include?('TODO'), "unfinished rule text for #{id}/#{language}")
      end
      paragraphs_count += expected.length
    end

    # Complete editions have their own chapter layout; each actual option
    # must still point to an explanatory chapter in every language.
    keys = game.effective_option_definitions.map(&:key)
    transport_keys = game.respond_to?(:p2p_option_definitions) ? game.p2p_option_definitions.map(&:key) : []
    local_keys = keys - ['bot_delay'] - transport_keys
    chapters = authored.fetch('option_chapters')
    assert(local_keys.sort == chapters.keys.sort, "missing option explanation for #{id}/#{language}: #{local_keys - chapters.keys}")
    chapters.each do |key, chapter|
      assert(ids.include?(chapter) && chapter != 'controls', "#{id}/#{language}/#{key} points to no rule chapter")
    end
    options_count += local_keys.length
    book = game.rule_book(options: game.default_options)
    expected_documents = id == 'mania_pisania' ? [:rules, :controls, :touch_typing, :current_options] : [:rules, :controls, :current_options]
    assert(book.documents.map(&:id) == expected_documents, "table rules changed document structure for #{id}")
    assert(!book.documents.first.sections.any? { |section| section.id == :bot_pacing }, "#{id}: generic bot pacing appended to complete edition")
  end
end
puts "PASS authoring: #{books.length} games in five complete editions; #{paragraphs_count} paragraphs and #{options_count} option-to-chapter mappings agree with runtime"
