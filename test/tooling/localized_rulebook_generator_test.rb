require "tmpdir"
require_relative "../support/assertions"
require_relative "../../tools/compile-rulebooks"
include GameRoomTest::Assertions

Dir.mktmpdir("localized-rulebooks-") do |root|
  directory = File.join(root, "tools/data/rulebooks")
  FileUtils.mkdir_p(File.join(directory, "PL"))
  manifest = {"example.json" => {"source" => "games/example.rb", "class" => "Example", "kind" => "class", "output" => "games/generated/rulebooks/example.rb"}}
  english = {"source" => "games/example.rb", "sections" => [{"id" => "original", "title" => {"en" => "Goal"}, "paragraphs" => [{"en" => "English rules."}]}]}
  polish = {"source" => "games/example.rb", "sections" => [
    {"id" => "aim", "title" => {"pl" => "Cel gry"}, "paragraphs" => [{"pl" => "Zażółć gęślą jaźń."}]},
    {"id" => "controls", "title" => {"pl" => "Skróty"}, "paragraphs" => [{"pl" => "Enter: zagraj."}]}
  ]}
  File.write(File.join(root, "tools/rulebook_sources.json"), JSON.generate(manifest))
  File.write(File.join(directory, "example.json"), JSON.generate(english))
  path = File.join(directory, "PL/example.json")
  File.write(path, JSON.generate(polish))
  {
    "en" => ["Getting started", "Choose your first card."],
    "cs" => ["Jak začít", "Vyber první kartu."],
    "es" => ["Cómo empezar", "Elige tu primera carta."],
    "ru" => ["Начало игры", "Выбери первую карту."]
  }.each do |language, (title, text)|
    localized = {"source" => "games/example.rb", "sections" => [
      {"id" => "opening", "title" => {language => title}, "paragraphs" => [{language => text}]},
      {"id" => "controls", "title" => {language => "Enter"}, "paragraphs" => [{language => "Enter: #{text}"}]}
    ]}
    target = File.join(directory, language.upcase)
    FileUtils.mkdir_p(target)
    File.write(File.join(target, "example.json"), JSON.generate(localized))
  end
  output = "games/generated/rulebooks/example.rb"
  compiler = GameRoomRulebookCompiler
  assert_equal([output], compiler.run(root: root, check: true))
  assert(!File.exist?(File.join(root, output)), "Read-only check wrote a file")
  compiler.run(root: root)
  bytes = File.binread(File.join(root, output))
  RubyVM::InstructionSequence.compile(bytes)
  assert(bytes.start_with?("# Generated"), "Generator changed module indentation")
  %w[pl en cs es ru].each do |language|
    assert(bytes.include?("when #{language.dump}"), "#{language}: localized edition was omitted")
  end
  assert(bytes.include?('rule_section(:original, GameRoomRules.translate("Goal")'), "Fallback path changed")
  assert(bytes.include?('rule_section(:opening, "Getting started"'), "Authored English path was not generated")
  assert(compiler.run(root: root, check: true).empty?, "Localized generation is not reproducible")
  invalid_books = [
    polish.merge("source" => "games/wrong.rb"),
    polish.merge("sections" => [polish["sections"].last, polish["sections"].last]),
    polish.merge("sections" => [polish["sections"].first]),
    polish.merge("sections" => [polish["sections"].first.merge("id" => "invalid-id"), polish["sections"].last]),
    polish.merge("sections" => [polish["sections"].first.merge("title" => {"pl" => " "}), polish["sections"].last])
  ]
  invalid_books.each do |invalid|
    File.write(path, JSON.generate(invalid))
    assert_raises(RuntimeError) { compiler.run(root: root) }
    assert_equal(bytes, File.binread(File.join(root, output)), "Rejected source changed generated output")
  end
end
puts "PASS localized generator: independent chapters, encoding, deterministic output, read-only check and validation"
