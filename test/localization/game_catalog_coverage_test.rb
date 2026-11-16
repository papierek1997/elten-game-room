require "json"
require_relative '../../tools/support/translation_catalog'
root = File.expand_path("../..", __dir__)
bytes = File.binread(File.join(root, "locale/PL.mo"))
count, originals, translations = bytes.byteslice(8, 12).unpack("V3")
catalog = count.times.to_h do |i|
  length, offset = bytes.byteslice(originals + i * 8, 8).unpack("V2")
  key = bytes.byteslice(offset, length).force_encoding("UTF-8")
  length, offset = bytes.byteslice(translations + i * 8, 8).unpack("V2")
  [key, bytes.byteslice(offset, length).force_encoding("UTF-8")]
end
messages = GameRoomTranslationCatalog.read_po(File.join(root, 'locale/pl.po')).filter_map do |entry|
    # Empty plural forms are represented by NUL separators, not an empty
    # Ruby string. Like the compiler, exclude untranslated/obsolete entries.
    next if entry.msgid.empty? || entry.msgstr.to_s.delete("\0").empty? || entry.fuzzy? || entry.obsolete?
    key = entry.msgid
    key = "#{entry.msgctxt}\u0004#{key}" if entry.msgctxt
    key += "\0#{entry.msgid_plural}" if entry.msgid_plural
    value = entry.msgstr
    raise "Uncompiled translation: #{key}" unless catalog[key] == value
    raise "Invalid encoding: #{key}" unless value.valid_encoding?
    value.split("\0").each do |variant|
      raise "Invalid placeholders: #{key}" unless variant.scan(/%\{[^}]+\}/).sort == key.split("\0").first.scan(/%\{[^}]+\}/).sort
    end
    raise "Missing Polish plural: #{key}" if key.include?("\0") && value.split("\0").length != 3
    key
end
source_paths = %w[games/rummy.rb games/tile_game.rb games/domino.rb games/mexican_train.rb lib/game_surfaces/meld_cards.rb lib/game_surfaces/tile_hand.rb] + Dir.glob('games/rummy/*.rb', base: root)
sources = source_paths.flat_map do |path|
  code = File.read(File.join(root, path), encoding: "UTF-8")
  singular = code.scan(/(?<![\w])_\("((?:[^"\\]|\\.)*)"\)/m).flatten.map { |literal| JSON.parse('"' + literal + '"') }
  plural = code.scan(/n_\(\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"/m).map { |pair| pair.map { |literal| JSON.parse('"' + literal + '"') }.join("\0") }
  singular + plural
end
missing = sources.uniq.reject { |key| catalog[key] && !catalog[key].empty? }
raise "Missing new game text translations:\n#{missing.join("\n")}" unless missing.empty?
puts "#{messages.length} new PL entries, #{sources.uniq.length} game/UI texts, full rules, plurals and compiled encoding: OK"
