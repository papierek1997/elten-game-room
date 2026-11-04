require_relative '../support/volume_and_help'
require_relative '../support/localization'
require_relative '../support/assertions'
require_relative '../../tools/support/translation_extractor'
require 'json'
include GameRoomTest::Assertions

root = File.expand_path('../..', __dir__)
messages = GameRoomTranslationExtractor.extract(root, warnings: []).reject do |message|
  # Historical release notes describe the name used at that time, including
  # the explicit announcement that ELTEN Game Room became Power Games.
  message[:references].all? { |reference| reference.start_with?('lib/game_room_changelog.rb:') }
end
old_name = /\bgame[ -]?room(?:u|ie|em)?\b/i
labels = {
  'en'=>'All Power Games sounds', 'pl'=>'Wszystkie dźwięki Power Games',
  'cs'=>'Všechny zvuky Power Games', 'es'=>'Todos los sonidos de Power Games',
  'ru'=>'Все звуки Power Games'
}
languages = JSON.parse(File.read(File.join(root, 'manifest.json'))).fetch('supported_languages')
assert_equal(languages.sort, labels.keys.sort, 'Product-name coverage omits an interface language')
levels = GameRoomPreferences.sound_volumes({})
program = EltenGameRoom.new
languages.each do |language|
  runtime = GameRoomTestLocalization.use_language(language)
  begin
    messages.each do |message|
      counts = message[:msgid_plural] ? [1, 2] : [nil]
      counts.each do |count|
        text = GameRoomLocalization.translate(message[:msgid], context: message[:msgctxt],
          plural: message[:msgid_plural], count: count)
        assert(!text.match?(old_name), "#{language}: old product name in #{message[:references].join(', ')}: #{text}")
      end
    end
    assert_equal(labels.fetch(language), GameRoomLocalization.translate(GameRoomUI::VOLUME_LABELS.fetch('all')))
    %w[all notifications].each do |group|
      index = GameRoomPreferences::SOUND_GROUPS.index(group)
      program.instance_variable_set(:@game_room_volume_group, index - 1)
      program.send(:adjust_game_room_volume, -3, reader: -> { levels })
      expected = GameRoomLocalization.translate('%{group}, %{volume}%%') % {
        group: GameRoomLocalization.translate(GameRoomUI::VOLUME_LABELS.fetch(group)), volume: levels.fetch(group)
      }
      assert_equal(expected, $spoken_messages.last, "#{language}: the actual volume announcement used another label")
      assert($spoken_messages.last.include?('Power Games'), "#{language}: missing current name in spoken volume")
    end
  ensure
    runtime.close
  end
end
puts 'PASS current product name: all extracted active UI messages in five compiled languages, real volume announcements, historical notes excluded'
