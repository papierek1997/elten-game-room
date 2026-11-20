require 'gettext/mo'
require_relative '../../tools/support/translation_extractor'

root = File.expand_path('../..', __dir__)
scope = %r{\Agames/(?:cribbage_support/|belote_support/|jass_support/|hearts_support/|generated/rulebooks/(?:cribbage|belote|jass|hearts)\.rb)}
messages = GameRoomTranslationExtractor.extract(root, warnings: []).select do |message|
  message.fetch(:references).any? { |reference| reference.match?(scope) }
end
raise 'No card-game messages were checked' if messages.empty?

%w[PL CS ES RU].each do |language|
  catalog = GetText::MO.open(File.join(root, "locale/#{language}.mo")).to_h.transform_keys do |key|
    key.dup.force_encoding('UTF-8')
  end
  missing = messages.filter_map do |message|
    key = message.fetch(:msgid)
    key = "#{message[:msgctxt]}\u0004#{key}" if message[:msgctxt]
    key += "\0#{message[:msgid_plural]}" if message[:msgid_plural]
    value = catalog[key]
    key unless value && !value.empty? && value.split("\0", -1).none?(&:empty?)
  end
  raise "#{language}: untranslated card-game messages: #{missing.inspect}" unless missing.empty?
end
puts "PASS four dealt-card games: #{messages.size} extracted messages, contexts and all plural forms in PL/CS/ES/RU"
