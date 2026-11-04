require_relative '../../tools/translations'
require_relative '../support/assertions'
include GameRoomTest::Assertions

root=File.expand_path('../..', __dir__)
messages=GameRoomTranslationExtractor.extract(root).select do |message|
  %w[Table\ history Saving\ table\ history].include?(message[:msgid]) ||
    message[:references].any? { |reference| reference.start_with?('lib/recordings/') }
end
assert(messages.any? { |message| message[:msgid]=='Table history' }, 'Missing fallback history title')
assert(messages.any? { |message| message[:msgid]=='Saving table history' }, 'Missing history task title')
%w[PL CS ES RU].each do |language|
  path=File.join(root,'locale',"#{language}.po")
  catalog=GameRoomTranslationCatalog.read_po(path)
  messages.each do |message|
    entry=catalog[message[:msgctxt],message.fetch(:msgid)]
    assert(entry && !entry.obsolete? && !entry.fuzzy? && !entry.msgstr.to_s.empty?,
      "#{language}: missing recording label #{message[:msgid]}")
  end
  GameRoomTranslationCatalog.compile_file(path,File.join(root,'locale',"#{language}.mo"),check:true)
end
puts "PASS #{messages.length} recording/history labels in four maintained language catalogs"
