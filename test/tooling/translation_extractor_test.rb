# encoding: UTF-8
require "minitest/autorun"
require "json"

extractor = File.expand_path("../../tools/support/translation_extractor.rb", __dir__)
require extractor if File.file?(extractor)

class TranslationExtractorTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def extract(source, path: "games/fixture.rb", warnings: [])
    assert defined?(GameRoomTranslationExtractor), "the source-only extractor API is missing"
    GameRoomTranslationExtractor.extract_source(source, path: path, warnings: warnings)
  end

  def test_missing_repository_is_not_a_successful_empty_catalog
    error = assert_raises(ArgumentError) { GameRoomTranslationExtractor.extract(File.join(ROOT, "no-such-repository"), warnings: []) }
    assert_includes error.message, "source root"
  end

  def test_missing_message_arguments_are_reported_without_crashing
    warnings = []
    records = extract("_(); n_(); p_(); np_(); N_(); Nn_(); GameRoomLocalization.translate()", warnings: warnings)
    assert_empty records
    assert_equal 7, warnings.length
  end

  def test_known_ui_inventory_consumers_are_not_unresolved_calls
    warnings = []
    extract('_(GameRoomUI::VOLUME_LABELS.fetch(group))', warnings: warnings)
    extract('module GameRoomUI; GLOBAL_TIPS.map { |tip| _(tip) }; end', path: "lib/game_room_ui.rb", warnings: warnings)
    assert_empty warnings
    extract('_(Other::VOLUME_LABELS.fetch(group))', warnings: warnings)
    extract('OTHER_TIPS.map { |tip| _(tip) }', path: "lib/game_room_ui.rb", warnings: warnings)
    assert_equal 2, warnings.size
  end

  def test_dynamic_ui_constants_extract_values_but_not_internal_ids
    source = <<~'RUBY'
      module GameRoomUI
        VOLUME_LABELS = { "internal_id" => "Volume label", "other" => dynamic_label }.freeze
        GLOBAL_TIPS = ["Press a key.", dynamic_tip].freeze
        INTERNAL = ["do not translate"]
      end
    RUBY
    warnings = []
    records = extract(source, path: "lib/game_room_ui.rb", warnings: warnings)
    assert_equal ["Volume label", "Press a key."], records.map { |record| record[:msgid] }
    assert_equal [2, 3], warnings.map { |warning| warning[:line] }
    assert_equal ["lib/game_room_ui.rb:2"], records[0][:references]
    assert_empty extract(source, path: "content/unrelated.rb")
  end

  def test_invalid_gettext_arguments_are_not_silently_downgraded
    warnings = []
    records = extract(<<~'RUBY', warnings: warnings)
      n_("One", nil, count)
      n_("One")
      p_(nil, "Open")
      np_("context", "One", nil, count)
      _("الله")
      _("")
    RUBY
    assert_equal ["الله"], records.map { |record| record[:msgid] }
    assert_equal [1, 2, 3, 4, 6], warnings.map { |warning| warning[:line] }
  end

  def test_changelog_translator_callback_is_a_known_inventory_consumer
    warnings = []
    extract('GameRoomChangelog.list_items(entries, translator: ->(text) { _(text) })', path: "__app.rb", warnings: warnings)
    extract('GameRoomChangelog.markdown(entries, translator: ->(text) { _(text) })', path: "__app.rb", warnings: warnings)
    assert_empty warnings
    extract('Other.list_items(entries, translator: ->(text) { _(text) })', path: "__app.rb", warnings: warnings)
    assert_equal 1, warnings.size
  end

  def test_known_translation_forwarders_do_not_generate_warning_noise
    %w[lib/game_rules.rb lib/game_room_localization.rb].each do |path|
      warnings = []
      extract(File.read(File.join(ROOT, path), encoding: "UTF-8"), path: path, warnings: warnings)
      assert_empty warnings, path
    end
    warnings = []
    extract("module GameRoomRules; def self.other(text); _(text); end; end", path: "lib/game_rules.rb", warnings: warnings)
    assert_equal 1, warnings.size, "only the known call-through, not arbitrary methods, is exempt"
  end

  def test_ninety_nine_changed_assignment_warns_rather_than_guessing_dataflow
    source = <<~'RUBY'
      def penalty_text(names, amount)
        singular, plural = if names.one?
          ["One", "Ones"]
        else
          ["Other", "Others"]
        end
        singular = fetch_message
        n_(singular, plural, amount)
      end
    RUBY
    warnings = []
    assert_empty extract(source, path: "games/ninety_nine.rb", warnings: warnings)
    assert_equal [8], warnings.map { |warning| warning[:line] }
    mutated = source.sub("singular = fetch_message", "singular.replace(fetch_message)")
    assert_empty extract(mutated, path: "games/ninety_nine.rb", warnings: warnings = [])
    assert_equal [8], warnings.map { |warning| warning[:line] }
  end

  def test_ninety_nine_literal_pair_assignment_is_an_explicit_ui_inventory
    source = <<~'RUBY'
      class NinetyNine
        def penalty_text(names, amount)
          singular, plural = if names.length == 1
            ["Player loses a token.", "Player loses tokens."]
          else
            ["Players lose a token.", "Players lose tokens."]
          end
          n_(singular, plural, amount)
        end
      end
    RUBY
    warnings = []
    records = extract(source, path: "games/ninety_nine.rb", warnings: warnings)
    assert_equal [["Player loses a token.", "Player loses tokens."], ["Players lose a token.", "Players lose tokens."]],
      records.map { |record| record.values_at(:msgid, :msgid_plural) }
    assert_equal ["games/ninety_nine.rb:4", "games/ninety_nine.rb:8"], records[0][:references]
    assert_empty warnings
    changed = source.sub('"Player loses tokens."', 'dynamic_plural')
    assert_empty extract(changed, path: "games/ninety_nine.rb", warnings: warnings = [])
    refute_empty warnings
    assert_empty extract(source, path: "games/unrelated.rb")

    records = extract(File.read(File.join(ROOT, "games/ninety_nine.rb"), encoding: "UTF-8"), path: "games/ninety_nine.rb", warnings: warnings = [])
    assert records.any? { |record| record[:msgid] == "%{players} loses %{count} token." && record[:msgid_plural] == "%{players} loses %{count} tokens." }
    assert records.any? { |record| record[:msgid] == "%{players} lose %{count} token." && record[:msgid_plural] == "%{players} lose %{count} tokens." }
    assert_empty warnings
  end

  def test_changelog_inventory_extracts_only_template_and_entry_changes
    source = <<~'RUBY'
      module GameRoomChangelog
        STORAGE_FILE = "not-ui.json".freeze
        ENTRY_TEMPLATE = "Version %{version}, build %{build}".freeze
        ENTRIES = [
          Entry.new(version: "7.3", build: 4, changes: ["Added café.", "Press 1\u20134."].freeze).freeze,
          Entry.new(version: "7.4", build: 5, changes: ["Added café.", make_change].freeze).freeze
        ].freeze
        UNRELATED = ["not UI"]
      end
    RUBY
    warnings = []
    records = extract(source, path: "lib/game_room_changelog.rb", warnings: warnings)
    assert_equal ["Version %{version}, build %{build}", "Added café.", "Press 1–4."], records.map { |record| record[:msgid] }
    assert_equal ["lib/game_room_changelog.rb:5", "lib/game_room_changelog.rb:6"], records[1][:references]
    assert_equal [6], warnings.map { |warning| warning[:line] }
    assert_empty extract(source, path: "content/unrelated.rb"), "the inventory is intentionally path-scoped"

    path = "lib/game_room_changelog.rb"
    actual = File.read(File.join(ROOT, path), encoding: "UTF-8")
    records = extract(actual, path: path, warnings: warnings = [])
    expected = actual.scan(/changes: \[\s*(.*?)\s*\]\.freeze/m).flat_map { |block| JSON.parse("[#{block.first}]") }
    assert_equal expected.uniq.sort, records.map { |record| record[:msgid] }.reject { |text| text.start_with?("Version %{version}") }.sort
    assert_empty warnings
  end

  def test_repository_scan_contains_every_rulebook_but_not_gameplay_blobs
    assert_respond_to GameRoomTranslationExtractor, :extract
    require "json"
    records = GameRoomTranslationExtractor.extract(ROOT, warnings: [])
    index = records.to_h { |record| [[record[:msgctxt], record[:msgid]], record] }
    books = Dir.glob('*.json', base: File.join(ROOT, 'tools/data/rulebooks')).map { |name| File.join(ROOT, 'tools/data/rulebooks', name) }
    sources = JSON.parse(File.read(File.join(ROOT, 'tools/rulebook_sources.json'), encoding: 'UTF-8'))
    assert_equal 33, books.size
    books.each do |file|
      book = JSON.parse(File.read(file, encoding: "UTF-8"))
      book.fetch("sections").each do |section|
        ([section.fetch("title")] + section.fetch("paragraphs")).each do |text|
          english = text.is_a?(Hash) ? text.fetch("en") : text
          record = index[[nil, english]]
          refute_nil record, "missing rulebook UI: #{file}: #{english}"
          output = sources.fetch(File.basename(file)).fetch('output')
          assert record[:references].any? { |reference| reference.start_with?(output + ":") }
        end
      end
    end
    assert index.key?([nil, "General knowledge"]), "runtime pack title must not be lost with quiz data"
    files = GameRoomTranslationExtractor.source_files(ROOT)
    refute files.any? { |file| file.match?(/(?:quiz_.*_data|taboo_cards_.*_data|scrabble_words_.*_data|noun_data)[.]rb$/) }
    assert files.include?("games/krowa_support/client.rb")
    assert files.include?("content/monopoly_boards.rb")
    refute records.any? { |record| record[:msgid] == "cat_head_tail" || record[:msgid] == "abazja" }
    refute defined?(GameRoomGames), "extracting the repository must not execute game classes"
  end

  def test_dynamic_calls_warn_instead_of_creating_incorrect_keys
    warnings = []
    source = <<~'RUBY'
      _("Hello #{dangerous_call}")
      _(name)
      n_("One", plural, count)
      p_(context, "Open")
      GameRoomLocalization.translate("Safe?", **options)
      GameRoomLocalization.translate("Safe", context: nil, plural: nil)
    RUBY
    records = extract(source, warnings: warnings)
    assert_equal ["Safe"], records.map { |record| record[:msgid] }
    assert_equal [1, 2, 3, 4, 5], warnings.map { |warning| warning[:line] }
    assert warnings.all? { |warning| warning[:path] == "games/fixture.rb" && warning[:code] == :dynamic_message && warning[:message].include?("literal") }
    _stdout, stderr = capture_io { extract("_(variable)", warnings: nil) }
    assert_includes stderr, "games/fixture.rb:1"
  end

  def test_parse_errors_abort_with_source_location
    error = assert_raises(ArgumentError) { extract("_('valid')\ndef broken(\n", path: "lib/broken.rb") }
    assert_includes error.message, "lib/broken.rb:2"
    assert_includes error.message, "parse error"
  end

  def test_conflicting_plural_ids_fail_with_both_references
    error = assert_raises(ArgumentError) do
      extract("n_('Token', 'Tokens', n)\nn_('Token', 'Pieces', n)")
    end
    assert_includes error.message, "conflicting plural"
    assert_includes error.message, "games/fixture.rb:1"
    assert_includes error.message, "games/fixture.rb:2"
  end

  def test_duplicate_identity_promotes_plural_and_merges_unique_references
    records = extract(<<~'RUBY')
      _("Token"); _("Token")
      n_("Token", "Tokens", count)
      _("Token")
      p_("different", "Token")
    RUBY
    assert_equal 2, records.length
    assert_equal "Tokens", records[0][:msgid_plural]
    assert_equal ["games/fixture.rb:1", "games/fixture.rb:2", "games/fixture.rb:3"], records[0][:references]
    reverse = extract("n_('Token', 'Tokens', n)\n_('Token')")
    assert_equal "Tokens", reverse[0][:msgid_plural]
  end

  def test_cat_head_tail_context_is_lexical_and_keeps_general_fallback
    source = <<~'RUBY'
      module GameRoomGames
        class CatHeadTail
          _("Roll")
          self._("Bank")
          GameRoomRules.translate("Rules")
          p_("explicit", "Other")
        end
        class Other
          _("Roll")
        end
      end
    RUBY
    records = extract(source)
    assert_equal [["Roll", "cat_head_tail"], ["Roll", nil], ["Bank", "cat_head_tail"], ["Bank", nil], ["Rules", nil], ["Other", "explicit"]],
      records.map { |record| record.values_at(:msgid, :msgctxt) }
    assert_equal ["games/fixture.rb:3", "games/fixture.rb:9"], records[1][:references]
  end

  def test_gettext_wrappers_preserve_context_and_plural
    source = <<~'RUBY'
      n_("One", "Many", count)
      p_("menu", "Open")
      np_("stock", "Item", "Items", count)
      N_("Deferred")
      Nn_("Deferred item", "Deferred items")
      GameRoomRules.translate("Rule")
      ::GameRoomLocalization.translate("Token", context: "game", plural: "Tokens", count: count)
      module GameRoomRules
        translate("Controls")
        self.translate("Self rule")
      end
      translate("Unrelated")
      Other.translate("Not UI")
    RUBY
    records = extract(source)
    assert_equal [
      ["One", "Many", nil], ["Open", nil, "menu"], ["Item", "Items", "stock"],
      ["Deferred", nil, nil], ["Deferred item", "Deferred items", nil],
      ["Rule", nil, nil], ["Token", "Tokens", "game"], ["Controls", nil, nil], ["Self rule", nil, nil]
    ], records.map { |record| record.values_at(:msgid, :msgid_plural, :msgctxt) }
    assert_equal ["games/fixture.rb:7"], records[6][:references]
  end

  def test_prism_decodes_literals_without_executing_source
    source = <<~'RUBY'
      raise "this source must never execute"
      _("Press 1\u20134: \"café\"\nnext\tline")
      _('single \'quote\' keeps \n')
      _(%q{Backslash \\ and "quote"})
      _(<<~TEXT)
        First line
        Second line
      TEXT
    RUBY
    assert_equal [
      { msgid: "Press 1–4: \"café\"\nnext\tline", msgid_plural: nil, msgctxt: nil, references: ["games/fixture.rb:2"], comments: [] },
      { msgid: "single 'quote' keeps \\n", msgid_plural: nil, msgctxt: nil, references: ["games/fixture.rb:3"], comments: [] },
      { msgid: 'Backslash \\ and "quote"', msgid_plural: nil, msgctxt: nil, references: ["games/fixture.rb:4"], comments: [] },
      { msgid: "First line\nSecond line\n", msgid_plural: nil, msgctxt: nil, references: ["games/fixture.rb:5"], comments: [] }
    ], extract(source)
  end
end
