require 'digest'
require_relative "../support/translation_reference"
require_relative "../support/ui"
require_relative "../support/log"

class Program
  def self.server_app(**_options); end
  def self.app_runtime; nil; end

  def self.test_json
    @test_json ||= {}
  end

  def read_json(path, default:)
    self.class.test_json.fetch(path, default)
  end

  def update_json(path, default:)
    value = self.class.test_json.fetch(path, default)
    yield(value)
    self.class.test_json[path] = value
  end
end

module Session
  def self.name; "Alice"; end
end

module EltenLink
  class Error < StandardError; end
  class Client; end
  module Contacts; end
end

module EltenAPI
  module LiveSessions
    class Error < StandardError; end
    class TimeoutError < Error; end
    class SessionClosed < Error; end
    class StackFull < Error; end
  end

  module Tasks
    class Cancelled < StandardError; end
  end
end

require_relative "../../__app"

def assert(condition, message)
  raise message if !condition
end

entries = GameRoomChangelog::ENTRIES
first_install = GameRoomChangelog.pending_entries(nil, 222, entries: entries)
assert(first_install.map(&:build) == [222], "first installation did not show only the current build")
missed = GameRoomChangelog.pending_entries(220, 222, entries: entries)
assert(missed.map(&:build) == [222, 221], "missed updates were not shown newest first")
assert(GameRoomChangelog.pending_entries(223, 222, entries: entries).empty?, "a downgrade reopened an old changelog")
assert(GameRoomChangelog.pending_entries(nil, 220, entries: entries).empty?, "first installation showed an older build")
assert(GameRoomChangelog.available_entries(221, entries: entries).map(&:build) == [221], "future entries appeared in the manual list")

lines = GameRoomChangelog.list_items(first_install)
assert(lines.first == "Version 1.1.8, build 222", "the current build heading is incorrect")
assert(lines.drop(1) == first_install.first.changes, "the build number is repeated for every change")
missed_lines = GameRoomChangelog.list_items(missed)
assert(missed_lines.count { |line| line.start_with?("Version ") } == 2, "missed builds do not have one heading each")
assert(missed_lines.first == "Version 1.1.8, build 222", "missed builds are not shown newest first")

resumes = 0
captured_form = nil
Form.class_eval do
  define_method(:resume) { resumes += 1 }
  alias_method :changelog_original_wait, :wait
  define_method(:wait) do
    captured_form = self
    cancel_button.trigger(:press)
  end
end
document_text = GameRoomChangelog.markdown(first_install)
GameRoomScreens::Changelog.new(document_text).wait
assert(captured_form.fields.length == 2, "the changelog needs one document and a close button")
field = captured_form.fields.first
assert(field.is_a?(EditBox) && field.text == document_text, "the changelog is not a text document")
assert(field.flags & EditBox::Flags::ReadOnly != 0 && field.flags & EditBox::Flags::MarkDown != 0, "the document is editable or has no headings")
assert(captured_form.accept_button.nil?, "Enter closes the document instead of following a link")
assert(captured_form.cancel_button == captured_form.fields.last && resumes == 1, "Escape does not close the document")
Form.class_eval do
  alias_method :wait, :changelog_original_wait
  remove_method :changelog_original_wait
end

shown = []
GameRoomScreens::Changelog.define_singleton_method(:new) do |items, **_options|
  shown << items
  Object.new.tap { |screen| screen.define_singleton_method(:wait) { true } }
end

app = EltenGameRoom.new
app.send(:show_update_changelog)
state = app.read_json(GameRoomChangelog::STORAGE_FILE, default: {})
current_entry = GameRoomChangelog::ENTRIES.find { |entry| entry.build == EltenGameRoom::GAME_ROOM_BUILD_ID }
assert(current_entry.version == EltenGameRoom::GAME_ROOM_VERSION, "current changelog version differs from runtime")
entry_226 = entries.find { |entry| entry.build == 226 }
assert(entry_226.version == "1.1.10" && entry_226.changes.length == 9, "build 226 does not contain the agreed release notes")
assert(entry_226.changes.last.include?("empty notification entry"), "build 226 lacks invitation history correction")
assert(GameRoomChangelog.pending_entries(225, 226).map(&:build) == [226], "build 226 repeats already-read changes")
entry_224 = entries.find { |entry| entry.build == 224 }
entry_225 = entries.find { |entry| entry.build == 225 }
assert(entry_225.changes.take(3) == entry_224.changes.take(3), "build 225 dropped the agreed previous changelog")
assert(entry_225.changes.last.include?("announced during a bot's turn"), "build 225 does not explicitly mention Makao during bot turns")
expected_current_text = GameRoomChangelog.markdown([current_entry])
assert(shown.length == 1 && shown.first == expected_current_text, "the current changelog was not shown on first launch")
assert(state[GameRoomChangelog::LAST_SEEN_BUILD_KEY] == EltenGameRoom::GAME_ROOM_BUILD_ID, "closing the changelog did not mark the build as read")
reopened_app = EltenGameRoom.new
reopened_app.send(:show_update_changelog)
assert(shown.length == 1, "the changelog was shown again after reopening Game Room")
reopened_app.send(:show_changelog)
assert(shown.length == 2, "the changelog could not be opened manually")

assert(EltenGameRoom::MAIN_OPTIONS.last == "What's new", "the main menu has no What's new entry")
opened = 0
app.define_singleton_method(:show_changelog) { opened += 1 }
app.send(:open_main_option, EltenGameRoom::MAIN_OPTIONS.length - 1)
assert(opened == 1, "the main menu entry does not open the changelog")

translations = GameRoomTest::TranslationReference.fetch("changelog_222_225")
mo = File.binread(File.expand_path("../../locale/PL.mo", __dir__))
count, originals, localized = mo.byteslice(8, 12).unpack("V3")
catalog = count.times.to_h do |index|
  source_length, source_offset = mo.byteslice(originals + index * 8, 8).unpack("V2")
  value_length, value_offset = mo.byteslice(localized + index * 8, 8).unpack("V2")
  [
    mo.byteslice(source_offset, source_length).force_encoding("UTF-8"),
    mo.byteslice(value_offset, value_length).force_encoding("UTF-8")
  ]
end
translations.each do |source, translation|
  assert(catalog[source] == translation, "uncompiled changelog translation: #{source}")
end
assert(catalog[entry_225.changes.last].to_s.include?("powiedzieć również w trakcie tury bota"),
  "the Polish changelog does not explicitly mention Makao during bot turns")
release_translations = GameRoomTest::TranslationReference.fetch("changelog_226")
assert(release_translations.keys == entry_226.changes, "release notes and Polish translation differ")
release_translations.each do |source, translation|
  assert(catalog[source] == translation, "uncompiled build 226 translation: #{source}")
end

entry_227 = entries.find { |entry| entry.build == 227 }
release_2 = GameRoomTest::TranslationReference.fetch("changelog_227")
assert(entry_227.version == '2.0' && entry_227.changes == release_2.keys, '2.0 changelog and translations differ')
release_2.each { |source, translation| assert(catalog[source] == translation, "uncompiled 2.0 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(226, 227).map(&:build) == [227], '2.0 duplicates old build headings')

entry_228 = entries.find { |entry| entry.build == 228 }
release_228 = GameRoomTest::TranslationReference.fetch("changelog_228")
assert(entry_228.version == "2.0" && entry_228.changes == release_228.keys, "build 228 changelog and translations differ")
assert(entry_228.changes[0...-1] == entry_227.changes, "build 228 changed the copied changelog")
assert(entry_228.changes.length == entry_227.changes.length + 1 && entry_228.changes.last.include?("text encoding"),
  "build 228 must add only the encoding correction")
release_228.each { |source, translation| assert(catalog[source] == translation, "uncompiled build 228 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(227, 228).map(&:build) == [228], "build 228 repeats already-read build headings")
current_lines = GameRoomChangelog.list_items(GameRoomChangelog.pending_entries(227, 228))
assert(current_lines.first == "Version 2.0, build 228" && current_lines.length == entry_228.changes.length + 1,
  "build 228 must have one version heading")
entry_229 = entries.find { |entry| entry.build == 229 }
release_229 = GameRoomTest::TranslationReference.fetch("changelog_229")
assert(entry_229.version == "2.0.1" && entry_229.changes == release_229.keys, "2.0.1 changelog and translations differ")
assert(entry_229.changes.length == 29 && entry_229.changes.uniq.length == 29,
  "2.0.1 must preserve twenty-eight notes and append only Krowa")
assert(entry_229.changes[27].include?("Ctrl+F1"), "2.0.1 lacks the empty shortcut-list correction")
assert(entry_229.changes.last.include?("Krowa by paulinux"), "Krowa or its requested author credit missing")
assert(entry_229.changes[24].include?("random or manual") && entry_229.changes[25].include?("rocket-launch") &&
  entry_229.changes[26].include?("opening instructions"), "2.0.1 lacks the latest agreed improvements")
assert(entry_229.changes[22].include?("Battleship") && entry_229.changes[23].include?("Mancala"),
  "new board games missing from release notes")
assert(entry_229.changes[11].include?("Private table checkbox") &&
  entry_229.changes[12].include?("New games are selected in the widget") &&
  entry_229.changes[13].include?("Domino and Mexican Train"), "2.0.1 lost its earlier corrections")
%w[contacts Turn-time token Poker Ctrl+R Keyboard Reshuffling Score].each_with_index do |topic, index|
  assert(entry_229.changes[14 + index].include?(topic), "2.0.1 is missing #{topic}")
end
release_229.each { |source, translation| assert(catalog[source] == translation, "uncompiled 2.0.1 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(228, 229).map(&:build) == [229], "2.0.1 repeats already-read updates")
assert(GameRoomChangelog.pending_entries(nil, 229).map(&:build) == [229], "first 2.0.1 launch repeats past updates")
assert(GameRoomChangelog.pending_entries(229, 229).empty?, "2.0.1 keeps reopening after being read")
assert(GameRoomChangelog.list_items([entry_229]).first == "Version 2.0.1, build 229", "2.0.1 heading differs")
entry_230 = entries.find { |entry| entry.build == 230 }
release_230 = GameRoomTest::TranslationReference.fetch("changelog_230")
assert(entry_230.version == "2.0.1.1" && entry_230.changes == release_230.keys, "2.0.1.1 changelog and translations differ")
assert(entry_230.changes.length == 9 && entry_230.changes.uniq.length == 9, "2.0.1.1 has duplicate/missing notes")
release_230.each { |source, translation| assert(catalog[source] == translation, "uncompiled 2.0.1.1 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(229, 230).map(&:build) == [230], "2.0.1.1 repeats the previous release")
assert(GameRoomChangelog.pending_entries(nil, 230).map(&:build) == [230], "first 2.0.1.1 launch repeats history")
assert(GameRoomChangelog.pending_entries(230, 230).empty?, "2.0.1.1 reopens after being read")
assert(GameRoomChangelog.list_items([entry_230]).first == "Version 2.0.1.1, build 230", "2.0.1.1 heading differs")
entry_231 = entries.find { |entry| entry.build == 231 }
release_231 = GameRoomTest::TranslationReference.fetch("changelog_231")
assert(entry_231.version == "2.0.2" && entry_231.changes == release_231.keys, "2.0.2 changelog and translations differ")
assert(entry_231.changes.length == 10 && entry_231.changes.uniq.length == 10, "2.0.2 has duplicate/missing notes")
assert(entry_231.changes.last.include?("selected for lobby messages") && entry_231.changes.last.include?("does not enable main-screen notifications"), "lobby defaults scope is missing")
assert(entry_231.changes.take(2).last.start_with?("Added Axel Pong"), "Pong must be introduced as new since build 230")
assert(entry_231.changes.none? { |text| text.match?(/Fixed slowdowns|Fixed an error|Restored the original|brought closer|no longer serve/) }, "unreleased Pong test fixes do not belong in public release notes")
assert(entry_231.changes.first.include?("Dragon-Pong") && entry_231.changes.first.include?("Axel and balteam") && entry_231.changes.first.include?("with their permission"), "Pong attribution must lead the changelog")
assert(entry_231.changes.any? { |text| text.include?("Ctrl+1 through Ctrl+0") && text.include?("Settings > Widget.") && text.include?("Table shortcuts list") && text.include?("saved immediately") && text.include?("Cancel in Settings does not undo") }, "inline widget setup and immediate-save instructions missing")
release_231.each { |source, translation| assert(catalog[source] == translation, "uncompiled 2.0.2 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(230, 231).map(&:build) == [231], "2.0.2 repeats the previous release")
assert(GameRoomChangelog.pending_entries(nil, 231).map(&:build) == [231], "first 2.0.2 launch repeats history")
assert(GameRoomChangelog.pending_entries(231, 231).empty?, "2.0.2 reopens after being read")
assert(GameRoomChangelog.list_items([entry_231]).first == "Version 2.0.2, build 231", "2.0.2 heading differs")

entry_233 = entries.find { |entry| entry.build == 233 }
release_233 = GameRoomTest::TranslationReference.fetch("changelog_233")
assert(entry_233.version == '2.0.2.2' && entry_233.changes == release_233.keys, 'build 233 notes and translations differ')
assert(entry_233.changes.length == 10 && entry_233.changes.uniq.length == 10, 'build 233 must preserve four notes and append the new game and five improvements')
assert(entry_233.changes[4].include?('Cat, head, tail by TD Programs'), 'new game author is missing')
assert(entry_233.changes.any? { |line| line.include?('Ctrl+F4') && line.include?('ELTEN server') }, 'server ping scope is missing')
assert(entry_233.changes.any? { |line| line.include?('30 table presets') && line.include?('Settings > Widget') && line.include?('saved immediately') }, 'macro setup instructions are missing')
release_233.each { |source, translation| assert(catalog[source] == translation, "uncompiled build 233 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(232, 233).map(&:build) == [233], 'build 233 repeats already-read notes')
assert(GameRoomChangelog.pending_entries(nil, 233).map(&:build) == [233], 'first build 233 launch repeats older notes')
assert(GameRoomChangelog.pending_entries(233, 233).empty?, 'build 233 changelog reopens after being read')
assert(GameRoomChangelog.list_items([entry_233]).first == 'Version 2.0.2.2, build 233', 'build 233 heading differs')

entry_234 = entries.find { |entry| entry.build == 234 }
release_234 = GameRoomTest::TranslationReference.fetch("changelog_234")
assert(entry_234.version == '2.0.2.3' && entry_234.changes == release_234.keys, 'build 234 notes and translations differ')
assert(entry_234.changes.length == 3 && entry_234.changes.uniq.length == 3, 'build 234 has missing or duplicate notes')
release_234.each { |source, translation| assert(catalog[source] == translation, "uncompiled build 234 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(233, 234).map(&:build) == [234], 'build 234 repeats already-read notes')
assert(GameRoomChangelog.pending_entries(nil, 234).map(&:build) == [234], 'first build 234 launch repeats older notes')
assert(GameRoomChangelog.pending_entries(234, 234).empty?, 'build 234 changelog reopens after being read')
assert(GameRoomChangelog.list_items([entry_234]).first == 'Version 2.0.2.3, build 234', 'build 234 heading differs')
assert(entry_234.changes.last.include?('HTTP') && entry_234.changes.last.include?('Communications'), 'ping transport is ambiguous')

entry_235 = entries.find { |entry| entry.build == 235 }
release_235 = GameRoomTest::TranslationReference.fetch("changelog_235")
assert(entry_235.version == '2.0.2.4' && entry_235.changes == release_235.keys, 'build 235 notes and translations differ')
assert(entry_235.changes.length == 1 && entry_235.changes.first.include?('Doubles'), 'build 235 should describe only the doubles correction')
release_235.each { |source, translation| assert(catalog[source] == translation, "uncompiled build 235 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(234, 235).map(&:build) == [235], 'build 235 repeats already-read notes')
assert(GameRoomChangelog.pending_entries(nil, 235).map(&:build) == [235], 'first build 235 launch repeats older notes')
assert(GameRoomChangelog.pending_entries(235, 235).empty?, 'build 235 changelog reopens after being read')
assert(GameRoomChangelog.list_items([entry_235]).first == 'Version 2.0.2.4, build 235', 'build 235 heading differs')
entry_236 = entries.find { |entry| entry.build == 236 }
release_236 = GameRoomTest::TranslationReference.fetch("changelog_236")
assert(entry_236.version == '2.0.2.5' && entry_236.changes == release_236.keys, 'build 236 notes and translations differ')
assert(entry_236.changes.length == 3 && entry_236.changes.uniq.length == 3, 'build 236 has missing or duplicate notes')
release_236.each { |source, translation| assert(catalog[source] == translation, "uncompiled build 236 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(235, 236).map(&:build) == [236], 'build 236 repeats already-read notes')
assert(GameRoomChangelog.pending_entries(nil, 236).map(&:build) == [236], 'first build 236 launch repeats older notes')
assert(GameRoomChangelog.pending_entries(236, 236).empty?, 'build 236 changelog reopens after being read')
assert(GameRoomChangelog.list_items([entry_236]).first == 'Version 2.0.2.5, build 236', 'build 236 heading differs')
assert(entry_236.changes[1].include?('All participants'), 'mixed-match update requirement missing')
assert(entry_236.changes.last.include?('three-second delay at the start'), 'initial countdown change missing')
entry_237 = entries.find { |entry| entry.build == 237 }
release_237 = GameRoomTest::TranslationReference.fetch("changelog_237")
assert(entry_237.version == '2.0.3' && entry_237.changes == release_237.keys, 'build 237 notes and translations differ')
assert(entry_237.changes.length == 14 && entry_237.changes.uniq.length == 14, 'build 237 has missing or duplicate notes')
assert(entry_237.changes.first.include?('budyn1211, known on ELTEN as balteam'), 'Audio Ball author alias missing')
assert(release_237.values.first.include?('budyn1211, znanego na ELTEN-ie jako balteam'), 'Polish Audio Ball author alias missing')
assert(entry_237.changes[4].include?('F1') && entry_237.changes[4].include?('Ctrl+F1'), 'background help note missing')
assert(entry_237.changes[5].include?('serve in Axel Pong after using chat'), 'Pong chat correction missing')
assert(entry_237.changes[6].include?('installation error') && entry_237.changes[6].include?('Unicode'), 'Unicode installation correction missing')
assert(entry_237.changes[7].include?('Ctrl+J') && entry_237.changes[7].include?('widget') && entry_237.changes[7].include?('notification'), 'widget invitation shortcut note missing')
assert(entry_237.changes[8].include?('Settings > Language') && entry_237.changes[9].include?('balteam'), 'language choice or translator credit missing')
assert(entry_237.changes[10].include?('watching Axel Pong') && entry_237.changes[11].include?('Accept'), 'observer/teams notes missing')
assert(entry_237.changes[12].include?('observer role') && entry_237.changes[13].include?('reading position'), 'roles/focus notes missing')
assert(entry_237.changes.drop(1).none? { |line| line.include?('Audio Ball') }, 'unreleased Audio Ball details added to release notes')
release_237.each { |source, translation| assert(catalog[source] == translation, "uncompiled build 237 translation: #{source}") }
assert(GameRoomChangelog.pending_entries(236, 237).map(&:build) == [237], 'build 237 repeats already-read notes')
assert(GameRoomChangelog.pending_entries(237, 237).empty?, 'build 237 changelog reopens after being read')
assert(GameRoomChangelog.list_items([entry_237]).first == 'Version 2.0.3, build 237', 'build 237 heading differs')

entry_238 = entries.find { |entry| entry.build == 238 }
assert(entry_238.version == '2.0.3.1' && entry_238.changes.length == 8 && entry_238.changes.uniq.length == 8,
  'build 238 must contain seven approved changes and the arcade exception')
assert(entry_238.changes.all? { |text| !catalog[text].to_s.empty? }, 'build 238 has an untranslated change')
assert(GameRoomChangelog.pending_entries(237, 238).map(&:build) == [238], 'build 238 repeats older changes')
assert(GameRoomChangelog.pending_entries(nil, 238).map(&:build) == [238], 'first build 238 launch repeats history')
assert(GameRoomChangelog.pending_entries(238, 238).empty?, 'build 238 reopens after being read')
assert(GameRoomChangelog.list_items([entry_238]).first == 'Version 2.0.3.1, build 238', 'build 238 heading differs')
entry_239 = entries.find { |entry| entry.build == 239 }
assert(entry_239.version == '2.0.4' && entry_239.changes.length == 27 && entry_239.changes.uniq.length == 27,
  'build 239 must contain the approved changes and minimum ELTEN version')
assert(entry_239.changes.any? { |text| text.include?('P2P') && text.include?('off by default') && text.include?('defaulting to 8') && text.include?('relay server') }, 'optional P2P settings or relay fallback missing')
assert(entry_239.changes.any? { |text| text.include?('Ctrl+F4') && text.include?('HTTP') && text.include?('Communications') && text.include?('P2P') && text.include?('Mixed') }, 'ping transport distinctions missing')
assert(entry_239.changes.grep(/Ctrl\+J/).size == 1 && entry_239.changes.any? { |text| text.include?('Ctrl+J') && text.include?('context menu') && text.include?('typing in chat') && text.include?('settings') }, 'global invitation shortcut scope missing or duplicated')
assert(entry_239.changes.any? { |text| text.include?('Opening Game Room again') && text.include?("ELTEN's Windows menu") }, 'single-instance window cleanup note missing')
assert(entry_239.changes.any? { |text| text.include?('Fixed opening Messages') && text.include?('widget') && text.include?('receiving updates') }, 'widget navigation and game updates note missing')
assert(entry_239.changes.any? { |text| text.include?('Corrected many quiz questions') && text.include?('questions and answers') }, 'broader quiz wording corrections missing')
assert(entry_239.changes[1].include?('War and Scientific War by balteam'), 'new games or author credit missing')
assert(entry_239.changes.grep(/Ctrl\+M/).size == 1, 'Added the excluded Ctrl+M focus change to the changelog')
assert(entry_239.changes.first == 'This version requires ELTEN 3.0.4 or later.', 'minimum ELTEN version missing')
assert(entry_239.changes.all? { |text| !catalog[text].to_s.empty? }, 'build 239 has an untranslated change')
assert(GameRoomChangelog.pending_entries(238, 239).map(&:build) == [239], 'build 239 repeats older changes')
assert(GameRoomChangelog.pending_entries(nil, 239).map(&:build) == [239], 'first build 239 launch repeats history')
assert(GameRoomChangelog.pending_entries(239, 239).empty?, 'build 239 reopens after being read')
assert(GameRoomChangelog.list_items([entry_239]).first == 'Version 2.0.4, build 239', 'build 239 heading differs')
entry_240 = entries.find { |entry| entry.build == 240 }
assert(entry_240.version == '2.0.4.1' && entry_240.changes.length == 17 && entry_240.changes.uniq.length == 17,
  'build 240 must contain the approved user-facing changes without duplicates')
assert(entry_240.changes.first.include?('Danil (Kostenkov-2021)'), 'Russian translation author missing')
assert(entry_240.changes[1].include?('paulinux'), 'Daily Krowa author missing')
assert(entry_240.changes.last.include?('balteam'), 'Player-count correction author missing')
assert(entry_240.changes.any? { |text| text.include?('Press Enter') && text.include?("Users list") && text.include?("ELTEN's standard user menu") },
  'The user-menu note must explicitly explain Enter on the participants list')
assert(entry_240.changes.all? { |text| !catalog[text].to_s.empty? }, 'build 240 has an untranslated change')
assert(GameRoomChangelog.pending_entries(239, 240).map(&:build) == [240], 'build 240 repeats older changes')
assert(GameRoomChangelog.pending_entries(nil, 240).map(&:build) == [240], 'first build 240 launch repeats history')
assert(GameRoomChangelog.pending_entries(240, 240).empty?, 'build 240 reopens after being read')
assert(GameRoomChangelog.list_items([entry_240]).first == 'Version 2.0.4.1, build 240', 'build 240 heading differs')
# Exact release wording is pinned independently of runtime and catalog;
# rebuilding translations must never rewrite these expected checksums.
# Build 247's approved terminology change replaces paletka with rakietka,
# including the single occurrence in the Polish build 240 note.
release_checksums = JSON.parse(File.read(File.expand_path('../fixtures/changelog_checksums.json', __dir__), encoding: 'UTF-8'))
release_checksums.each do |build, expected|
  entry = entries.find { |item| item.build == build.to_i }
  english = JSON.generate(entry.changes)
  polish = JSON.generate(entry.changes.map { |source| catalog.fetch(source) })
  assert(Digest::SHA256.hexdigest(english) == expected.fetch('english'), "Changed English release wording: #{build}")
  assert(Digest::SHA256.hexdigest(polish) == expected.fetch('polish'), "Changed Polish release wording: #{build}")
end

entry_241 = entries.find { |entry| entry.build == 241 }
assert(entry_241.version == '2.0.4.2' && entry_241.changes.length == 17 && entry_241.changes.uniq.length == 17,
  'build 241 must contain seventeen user-facing notes without duplicates')
assert(entry_241.changes.last == 'The Game Room code has been reorganized to make it easier to develop games and introduce further fixes. Thanks to Dawid Pieper (Pajper) for preparing these changes.',
  'build 241 must credit Dawid Pieper for the cleanup')
assert(catalog[entry_241.changes.last] == 'Uporządkowano kod Game Roomu, ułatwiając dalszy rozwój gier i wprowadzanie kolejnych poprawek. Podziękowania dla Dawida Piepera (Pajpera) za przygotowanie tych zmian.',
  'build 241 must preserve the approved Polish cleanup note')
assert(entry_241.changes.any? { |text| text.include?('stalls caused by statistics collection') } &&
  entry_241.changes.any? { |text| text.include?('all records in the selected date range') } &&
  entry_241.changes.any? { |text| text.include?('decide whether to leave the table') } &&
  entry_241.changes.any? { |text| text.include?('Updating is optional') },
  'rebuilt 241 lacks the statistics or leave-confirmation changes')
assert(entry_241.changes.all? { |text| !catalog[text].to_s.empty? }, 'build 241 has an untranslated change')
assert(GameRoomChangelog.pending_entries(240, 241).map(&:build) == [241], 'build 241 repeats older changes')
assert(GameRoomChangelog.pending_entries(nil, 241).map(&:build) == [241], 'first build 241 launch repeats history')
assert(GameRoomChangelog.pending_entries(241, 241).empty?, 'build 241 reopens after being read')
assert(GameRoomChangelog.list_items([entry_241]).first == 'Version 2.0.4.2, build 241', 'build 241 heading differs')
# The runtime changelog and the compiled catalogue are the release sources;
# PR 28 deliberately removes duplicated release documents.
entry_247 = entries.find { |entry| entry.build == 247 }
assert(entry_247.version == '2.0.4.8' && entry_247.changes.length == 9, 'build 247 has incorrect release metadata')
assert(entry_247.changes.all? { |text| !catalog[text].to_s.empty? }, 'build 247 has an untranslated change')
assert(GameRoomChangelog.pending_entries(246, 247).map(&:build) == [247], 'build 247 repeats older notes')
assert(GameRoomChangelog.pending_entries(nil, 247).map(&:build) == [247], 'first build 247 launch repeats history')
assert(GameRoomChangelog.pending_entries(247, 247).empty?, 'build 247 reopens after being read')
assert(GameRoomChangelog.list_items([entry_247]).first == 'Version 2.0.4.8, build 247', 'build 247 heading differs')
puts "Changelog tests passed: first launch, updates, downgrade, Enter, storage, old notes preserved and bilingual build 247 notes"
