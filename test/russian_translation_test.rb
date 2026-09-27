require "json"

root = File.expand_path("..", __dir__)

def read_translation_catalog(path)
  bytes = File.binread(path)
  magic, revision, count, originals, translations = bytes.unpack("V5")
  raise "Invalid MO header" unless magic == 0x950412de && revision == 0
  count.times.to_h do |index|
    source_size, source_offset = bytes.byteslice(originals + index * 8, 8).unpack("V2")
    target_size, target_offset = bytes.byteslice(translations + index * 8, 8).unpack("V2")
    [bytes.byteslice(source_offset, source_size).force_encoding("UTF-8"),
     bytes.byteslice(target_offset, target_size).force_encoding("UTF-8")]
  end
end

# The checked-in PO uses ordinary quoted gettext strings. Continuations also
# allow editors such as Poedit to wrap long paragraphs without breaking tests.
def read_russian_po(path)
  File.read(path, encoding: "UTF-8").split(/\r?\n\s*\r?\n/).filter_map do |block|
    fields = {}
    active = nil
    flags = []
    block.each_line do |line|
      line = line.strip
      if line.start_with?("#, ")
        flags.concat(line.delete_prefix("#, ").split(/,\s*/))
      elsif line.match?(/\A(?:msgid|msgid_plural|msgstr(?:\[\d+\])?) /)
        active, value = line.split(" ", 2)
        fields[active] = JSON.parse(value)
      elsif line.start_with?('"') && active
        fields[active] << JSON.parse(line)
      end
    end
    next unless fields.key?("msgid")
    [fields, flags, block.include?("#. Требует проверки.")]
  end
end

catalog = read_translation_catalog(File.join(root, "locale/RU.mo"))
entries = read_russian_po(File.join(root, "locale/RU.po"))
keys = []
entries.each do |fields, flags, review_comment|
  source = fields.fetch("msgid")
  if source.empty?
    raise "Missing Russian language header" unless fields.fetch("msgstr").include?("Language: ru\n")
    raise "Missing Russian plural header" unless fields.fetch("msgstr").include?("nplurals=3;")
  else
    raise "Reviewed translation is still fuzzy: #{source}" if flags.include?("fuzzy")
    raise "Reviewed translation still has a review comment: #{source}" if review_comment
  end
  if fields.key?("msgid_plural")
    key = [source, fields.fetch("msgid_plural")].join("\0")
    raise "Russian needs exactly three plural forms: #{source}" unless fields.keys.grep(/\Amsgstr/).sort == %w[msgstr[0] msgstr[1] msgstr[2]]
    values = (0..2).map { |i| fields.fetch("msgstr[#{i}]") }
  else
    key = source
    values = [fields.fetch("msgstr")]
  end
  keys << key
  values.each do |value|
    raise "Empty Russian translation: #{source}" if value.empty?
    raise "Invalid UTF-8: #{source}" unless value.valid_encoding?
    unless source.empty?
      raise "Lost placeholder: #{source}" unless source.scan(/%\{[^}]+\}/).sort == value.scan(/%\{[^}]+\}/).sort
    end
  end
  raise "RU.mo is stale: #{source}" unless catalog.fetch(key) == values.join("\0")
end
raise "Duplicate PO entries" unless keys.uniq == keys
raise "Unexpected MO entries" unless keys.sort == catalog.keys.sort

# Include dynamic labels and historical messages from the shipped catalogue,
# as well as literal strings newly introduced in the application sources.
singulars = catalog.keys.map { |key| key.split("\0", 2).first }
polish = read_translation_catalog(File.join(root, "locale/PL.mo"))
missing = polish.keys.reject { |key| catalog.key?(key) || (!key.include?("\0") && singulars.include?(key)) }
files = [File.join(root, "__app.rb")] + Dir[File.join(root, "{games,lib,content}/**/*.rb")]
files.each do |path|
  text = File.read(path, encoding: "UTF-8")
  literals = text.scan(/(?<!\w)_\(\s*("(?:\\.|[^"\\])*")\s*\)/).flatten.map { |value| JSON.parse(value) }
  literals += text.scan(/(?<!\w)_\('([^']*)'\)/).flatten
  missing.concat(literals.reject { |source| singulars.include?(source) })
  text.scan(/n_\(("(?:\\.|[^"\\])*")\s*,\s*("(?:\\.|[^"\\])*")/).each do |pair|
    source = pair.map { |value| JSON.parse(value) }.join("\0")
    missing << source unless catalog.key?(source)
  end
end
raise "Missing Russian messages: #{missing.uniq.inspect}" unless missing.empty?

manifest = JSON.parse(File.read(File.join(root, "manifest.json"), encoding: "UTF-8"))
embedded = File.read(File.join(root, "__app.rb"), encoding: "UTF-8").match(/=begin Elten3AppInfo\s*(.*?)\s*=end Elten3AppInfo/m)[1]
embedded = JSON.parse(embedded)
%w[supported_languages localized_descriptions version build_id].each do |key|
  raise "Manifests disagree: #{key}" unless manifest[key] == embedded[key]
end
raise "Russian not registered" unless manifest.fetch("supported_languages").include?("ru")
raise "Missing Russian description" if manifest.fetch("localized_descriptions").fetch("ru").empty?

%w[yellow green black\ queen].zip(["жёлтый", "зелёный", "чёрный ферзь"]).each do |source, expected|
  raise "Incorrect spelling: #{source}" unless catalog.fetch(source) == expected
end
forbidden_yo_spellings = /\b(?:ее|партнер(?:а|ов|ы|ом|ами)?|счет(?:а|ов|ом|у|е|ный)?|подсчет(?:а|ов|ом|у|е)?|отсчет(?:а|ов|ом|у|е)?|объем(?:а|ов|ом|у|е)?|трех|четырех|все еще|все равно)\b/i
entries.each do |fields, _flags, _review_comment|
  fields.each do |name, value|
    next unless name.start_with?("msgstr")
    raise "Russian translation omits ё: #{fields.fetch("msgid")}: #{value}" if value.match?(forbidden_yo_spellings)
  end
end
raise "Card queen must be a dama" unless catalog.fetch("queen") == "дама"
raise "Chess queen must be a ferz" unless catalog.fetch("chess queen") == "ферзь"

$russian_test_catalog = catalog
def _(text)
  $russian_test_catalog.fetch(text, text)
end
require_relative "../games/base"
require_relative "../games/chess"
chess = GameRoomGames::Chess.new
raise "Chess promotion uses the card translation" unless chess.send(:translated_piece_name, "Q") == "ферзь"

puts "Russian PO/MO coverage, review status, ё spelling, placeholders, manifests and chess terminology passed (#{entries.length - 1} messages)"
