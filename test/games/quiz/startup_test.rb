require_relative "../../../lib/game_surfaces/specifications"
$LOAD_PATH.unshift(File.expand_path("../../..", __dir__))

def _(text)
  text
end

def p_(_context, text)
  text
end


require "json"
require_relative "../../../lib/game_content"
require_relative "../../../content/languages"
require_relative "../../../content/quiz_general_en"
require_relative "../../../content/quiz_general_ru"
require_relative "../../../content/quiz_pl_wikidata"
require_relative "../../../content/quiz_witcher_pl"
require_relative "../../../games/quiz_party"
require_relative "../../../games/registry"

def assert(condition, message)
  raise message if !condition
end

registry = GameRoomGames::Registry.new([GameRoomGames::QuizParty])
assert(registry.ids == ["quiz"], "the game did not register under its own id")
assert(registry.name("quiz") == "Quiz Party", "the registered game has no readable name")

game = registry.build("quiz")
book = game.rule_book
assert(book.documents.map(&:id) == [:rules, :controls], "rules and keyboard shortcuts are not separate documents")
assert(book.sections.all? { |section| section.paragraphs.any? { |text| !text.to_s.strip.empty? } }, "a rule section is empty")

options = game.default_options
options_book = game.rule_book(options: options)
assert(options_book.sections.first.id == :current_options, "the rule book does not show the table options")
assert(options_book.sections.first.paragraphs.first.include?("15"), "the shown table options lost the target score")
keys = game.effective_option_definitions.map(&:key)
assert(keys.uniq.length == keys.length, "the game exposes duplicate option keys")
assert(keys.include?("content_language_id"), "the table cannot choose a question language")

polish_pack = GameRoomContent.registry.pack("quiz.wikidata.pl")
packs = %w[
  quiz.wikidata.pl quiz.witcher.books.pl quiz.general.en quiz.general.ru
].map { |id| GameRoomContent.registry.pack(id) }
assert(packs.all? { |pack| pack && !pack.verified? }, "rules/defaults/options eagerly loaded a question database")
audit = JSON.parse(File.read(File.expand_path("../../../content/QUIZ_IMPORT_REPORT.json", __dir__), encoding: "UTF-8"))["packs"]
reference = JSON.parse(File.read(File.expand_path("../../fixtures/quiz/questions.json", __dir__), encoding: 'UTF-8'))
expected_count = lambda { |id| reference.fetch('packs').fetch(id).fetch('count') }
polish_reference = reference.fetch('packs').fetch(polish_pack.id)
assert(polish_pack.set_id == "quiz.wikidata" && polish_pack.language_id == "pl-PL", "the Polish general set changed its identity")
assert(polish_pack.title == "Wiedza ogólna", "the Polish general set has an outdated title")
assert(polish_pack.version == polish_reference.fetch('version'), "the Polish general set has an unexpected data version")
polish_questions = polish_pack.data["questions"]
assert(polish_questions.length == expected_count.call(polish_pack.id), "the reviewed Polish general set has an unexpected question count")
polish_sources = polish_questions.map { |question| question.fetch("source_dataset") }.uniq.sort
assert(polish_sources == ["1z10/MAUPQA", "Milionerzy/Polsat", "PolQA"], "the Polish general set lost a source or includes the retired pack")
polish_options = game.normalize_options("content_set_id" => "quiz.wikidata", "content_language_id" => "pl-PL")
assert(game.selected_content_pack(polish_options).equal?(polish_pack), "the Polish options resolve to another pack")
assert(game.validation_error(polish_options, player_count: 2) == nil, "the reviewed Polish general set cannot start a match")
assert(game.send(:pack_questions, polish_options) == polish_questions, "runtime validation silently dropped reviewed Polish questions")
stale_polish = polish_options.merge("content_pack_version" => polish_pack.version - 1)
assert(game.selected_content_pack(stale_polish) == nil && game.validation_error(stale_polish, player_count: 2) != nil, "a table using the previous Polish data version was accepted")
changed_polish = polish_options.merge("content_pack_checksum" => "0" * 64)
assert(game.selected_content_pack(changed_polish) == nil && game.validation_error(changed_polish, player_count: 2) != nil, "a table with different Polish question content was accepted")
assert(polish_pack.verified? && packs.drop(1).none?(&:verified?), "loading Polish also loaded an unrelated pack")
witcher_pack = GameRoomContent.registry.pack("quiz.witcher.books.pl")
assert(witcher_pack.data["questions"].length == expected_count.call(witcher_pack.id) && witcher_pack.verified?, "the Witcher books data did not verify")
assert(packs[2..].none?(&:verified?), "loading Witcher eagerly loaded another language")
assert(game.selected_content_pack(options) != nil, "the default table options do not resolve to an installed pack")
polish_sets = game.send(:available_content_sets, "pl-PL").map(&:id).sort
assert(polish_sets == ["quiz.wikidata", "quiz.witcher.books"], "Polish does not offer the intended question sets")
require_relative "../../support/native_live_sessions"
[
  ["quiz.wikidata", "pl-PL"],
  ["quiz.witcher.books", "pl-PL"]
].each do |set_id, language_id|
  set_options = game.normalize_options("content_set_id" => set_id, "content_language_id" => language_id)
  # Options now travel in a LiveSession record, not the retired string:256
  # table column. Exercise the actual room/start path and its packet limit.
  broker = NativeLiveSessionsBroker.new
  store = GameRoomLiveSessionStore.new(ProgramDouble.new(broker.endpoint("Alice")))
  room = store.create_room(name:"Quiz startup", game:game.id, owner:"Alice", game_options:JSON.generate(set_options))
  guest = GameRoomLiveSessionStore.new(ProgramDouble.new(broker.endpoint("Bob")))
  guest.join_room(room,"Bob")
  $game_room_test_user = "Alice"
  session = store.start_game(table:room,game:game.id,players:%w[Alice Bob],options:JSON.generate(set_options),actor:"Alice")
  assert(JSON.parse(session["options"]) == set_options, "#{set_id} options did not survive native room startup")
  assert(broker.cores.values.first.entries.all? { |entry| JSON.generate(entry["packet"]).bytesize <= GameRoomLiveSessionStore::STACK_ENTRY_BYTES }, "Quiz startup packet exceeds the native limit")
end

english_pack = GameRoomContent.registry.pack("quiz.general.en")
assert(english_pack != nil && !english_pack.verified?, "English was loaded while choosing a Polish set")
assert(english_pack.license == "CC-BY-SA-4.0", "the English question pack lost its license")
assert(english_pack.author == "OpenTriviaQA contributors", "the English question pack lost its attribution")
assert(english_pack.data["questions"].length == audit.fetch(english_pack.id).fetch("kept") && english_pack.verified?, "the cleaned English data did not verify")
packs.each do |pack|
  assert(pack.entry_count == pack.data["questions"].length, "the lightweight count is incorrect")
end
removed = audit.fetch("quiz.general.en").fetch("rejected").map { |entry| entry["id"] }
assert((english_pack.data["questions"].map { |q| q["id"] } & removed).empty?, "a quarantined English question is still playable")
assert(english_pack.data["questions"].map { |question| question["category"] }.uniq.length == 20, "the English question pack lost its categories")
assert(GameRoomContent.registry.pack_set("quiz.general").language_ids == ["en"], "the removed Polish general variant is still registered")

russian_pack = GameRoomContent.registry.pack("quiz.general.ru")
assert(russian_pack != nil && russian_pack.language_id == "ru-RU", "the Russian question pack is not registered")
assert(russian_pack.data["questions"].length == 36 && russian_pack.verified?, "the Russian question pack failed lazy verification")
assert(game.send(:available_content_sets, "ru-RU").map(&:id) == ["quiz.general.ru"], "Russian does not offer its question set")

GameRoomContent.registry.register_language(
  GameRoomContent::LanguageProfile.new(
    id: "it-IT",
    label: "Italian",
    alphabet: ("a".."z").to_a,
    normalizer: ->(text) { text.downcase }
  )
)
GameRoomContent.registry.register_pack(
  GameRoomContent::Pack.new(
    id: "quiz.general.it",
    set_id: "quiz.general",
    kind: :quiz,
    language_id: "it-IT",
    version: 1,
    title: "General knowledge",
    game_ids: ["quiz"],
    author: "ELTEN Game Room",
    license: "CC0-1.0",
    data: {
      questions: [
        {
          id: "it0000000001",
          category: "geografia",
          level: "easy",
          prompt: "Qual e la capitale dell'Italia?",
          correct: "Roma",
          wrong: ["Milano", "Napoli", "Torino"]
        },
        {
          id: "it0000000002",
          category: "geografia",
          level: "easy",
          prompt: "Qual e la capitale della Francia?",
          correct: "Parigi",
          wrong: ["Lione", "Marsiglia", "Nizza"]
        },
        {
          id: "it0000000003",
          category: "geografia",
          level: "easy",
          prompt: "Qual e la capitale della Spagna?",
          correct: "Madrid",
          wrong: ["Barcellona", "Valencia", "Siviglia"]
        }
      ]
    }
  )
)

fresh = GameRoomGames::QuizParty.new
language_choices = fresh.effective_option_definitions
  .find { |definition| definition.key == "content_language_id" }.choices.map(&:value)
assert(language_choices.sort == ["en", "it-IT", "pl-PL", "ru-RU"], "a newly installed language did not appear as a table choice: #{language_choices.inspect}")

italian = fresh.normalize_options(
  "content_set_id" => "quiz.general",
  "content_language_id" => "it-IT"
)
assert(fresh.validation_error(italian, player_count: 2) == nil, "an Italian table was rejected: #{fresh.validation_error(italian, player_count: 2)}")
assert(fresh.selected_content_pack(italian).language_id == "it-IT", "the Italian table did not resolve to the Italian pack")
assert(fresh.options_summary(italian).include?("15"), "the Italian table lost its options summary")

mismatched = italian.merge("content_pack_checksum" => "0" * 64)
assert(fresh.validation_error(mismatched, player_count: 2) != nil, "a table with a tampered content checksum was accepted")

puts "Quiz Party startup tests passed: registry, two Polish sets, English OpenTriviaQA, and an added Italian language"
