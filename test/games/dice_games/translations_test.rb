require_relative "../../../lib/game_room_localization"
require_relative "../../../tools/support/translation_catalog"
require "json"
root = File.expand_path("../../..",__dir__)
messages = %w[games/dice_poker.rb games/liars_dice.rb games/liars_dice_players.rb].flat_map do |relative|
  File.read(File.join(root,relative),encoding:'UTF-8').scan(/_\("((?:[^"\\]|\\.)*)"\)/).flatten.map { |value| JSON.parse('"'+value+'"') }
end.uniq
missing = []
%w[PL CS ES RU].each do |language|
  entries = GameRoomTranslationCatalog.read_po(File.join(root,"locale/#{language}.po")).to_h { |entry| [entry.msgid,entry] }
  catalog = GameRoomLocalization::Catalog.new(File.binread(File.join(root,"locale/#{language}.mo")))
  messages.each do |message|
    entry = entries.fetch(message)
    if entry.fuzzy? || entry.msgstr.to_s.empty?
      missing << "#{language}: #{message}"
      next
    end
    raise "#{language}: uncompiled #{message}" unless catalog.translate(message) == entry.msgstr
  end
end
raise "Missing translations:\n#{missing.join("\n")}" unless missing.empty?
puts "Dice game translations: #{messages.size} UI messages in four compiled languages passed"
