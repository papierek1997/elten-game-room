require_relative "../../../lib/game_room_localization"
require_relative "../../../tools/support/translation_catalog"
require "json"

root = File.expand_path("../../..", __dir__)
source = File.read(File.join(root, "games/bingo.rb"), encoding: "UTF-8")
messages = source.scan(/_\("((?:[^"\\]|\\.)*)"\)/).flatten.map { |literal| JSON.parse('"' + literal + '"') }.uniq
%w[PL CS ES RU].each do |language|
  entries = GameRoomTranslationCatalog.read_po(File.join(root, "locale/#{language}.po")).to_h { |entry| [entry.msgid, entry] }
  catalog = GameRoomLocalization::Catalog.new(File.binread(File.join(root, "locale/#{language}.mo")))
  messages.each do |message|
    entry = entries.fetch(message)
    raise "#{language}: missing #{message}" if entry.fuzzy? || entry.msgstr.to_s.empty?
    raise "#{language}: uncompiled #{message}" unless catalog.translate(message) == entry.msgstr
  end
end
puts "Bingo translations: #{messages.size} UI messages in four compiled languages passed"
