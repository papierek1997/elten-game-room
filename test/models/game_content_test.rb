def _(text)
  text
end

require_relative "../../lib/game_content"
require_relative "../../games/base"

def assert(condition, message)
  raise message if !condition
end

registry = GameRoomContent::Registry.new
polish = registry.register_language(
  GameRoomContent::LanguageProfile.new(
    id: "pl-PL",
    label: "Polish",
    alphabet: %w[a ą b c ć d e ę f g h i j k l ł m n ń o ó p r s ś t u w y z ź ż],
    normalizer: ->(text) { text.downcase }
  )
)
registry.register_language(
  GameRoomContent::LanguageProfile.new(
    id: "en",
    label: "English",
    alphabet: ("a".."z").to_a,
    normalizer: ->(text) { text.downcase }
  )
)

assert(polish.normalize("  ZAŻÓŁĆ   GĘŚLĄ  ") == "zażółć gęślą", "Polish normalization is incorrect")
binary_polish = "ZAŻÓŁĆ".dup.force_encoding(Encoding::ASCII_8BIT)
assert(polish.normalize(binary_polish) == "zażółć", "embedded binary source text was not converted to UTF-8")
assert(polish.valid_word_shape?("ŻÓŁĆ"), "Polish letters were rejected")
assert(!polish.valid_word_shape?("quiz"), "letters outside the Polish profile were accepted")

pack = registry.register_pack(
  GameRoomContent::Pack.new(
    id: "quiz.general.pl",
    set_id: "quiz.general",
    kind: :quiz,
    language_id: "pl-PL",
    version: 2,
    title: "General knowledge",
    game_ids: ["quiz"],
    author: "Game Room",
    license: "test",
    data: {
      questions: [
        { id: "capital", prompt: "Capital of Poland", answers: ["Warsaw"] }
      ]
    }
  )
)
english_pack = registry.register_pack(
  GameRoomContent::Pack.new(
    id: "quiz.general.en",
    set_id: "quiz.general",
    kind: :quiz,
    language_id: "en",
    version: 2,
    title: "General knowledge",
    game_ids: ["quiz"],
    author: "Game Room",
    license: "test",
    data: {
      questions: [
        { id: "capital", prompt: "Capital of Poland", answers: ["Warsaw"] }
      ]
    }
  )
)
assert(pack.checksum.length == 64, "the content pack has no SHA-256 checksum")
assert(pack.data["questions"].first["id"] == "capital", "content data was not normalized")
assert(pack.data.frozen? && pack.data["questions"].frozen?, "content data is mutable")
assert(registry.packs_for(game_id: "quiz", kind: :quiz) == [english_pack, pack], "the registry lost compatible packs")
assert(registry.packs_for(game_id: "words", kind: :quiz).empty?, "the registry exposed a pack to another game")
quiz_set = registry.pack_set("quiz.general")
assert(quiz_set.title == "General knowledge", "the logical content set lost its title")
assert(quiz_set.language_ids.sort == ["en", "pl-PL"], "language variants were not grouped into one set")
assert(registry.pack_sets_for(game_id: "quiz", kind: :quiz).map(&:id) == ["quiz.general"], "one set was exposed more than once")
assert(
  registry.pack_for(game_id: "quiz", kind: :quiz, set_id: "quiz.general", language_id: "pl-PL").equal?(pack),
  "the Polish set variant was not resolved"
)

loader_calls = 0
lazy_data = { words: ["cat", "dog"] }
reference = GameRoomContent::Pack.new(
  id: "words.reference.en",
  set_id: "words.reference",
  kind: :words,
  language_id: "en",
  version: 1,
  title: "Reference words",
  game_ids: ["words"],
  data: lazy_data
)
lazy = registry.register_pack(
  GameRoomContent::Pack.new(
    id: "words.standard.en",
    set_id: "words.standard",
    kind: :words,
    language_id: "en",
    version: 1,
    title: "Standard words",
    game_ids: ["words"],
    checksum: reference.checksum,
    loader: -> do
      loader_calls += 1
      lazy_data
    end
  )
)
assert(loader_calls == 0 && !lazy.verified?, "a lazy pack loaded during registration")
assert(lazy.data["words"] == ["cat", "dog"], "a lazy pack returned invalid data")
assert(loader_calls == 1 && lazy.verified?, "a lazy pack was not cached after verification")
lazy.data
assert(loader_calls == 1, "a lazy pack loaded more than once")

content_game = Class.new(GameRoomGames::Base) do
  define_method(:id) { "quiz" }
  define_method(:name) { "Quiz" }
  define_method(:content_pack_kind) { :quiz }
  define_method(:content_registry) { registry }
  define_method(:default_content_language_id) { |_set_id = nil| "pl-PL" }

  def option_definitions
    [
      GameRoomGames::OptionDefinition.new(
        key: "timed",
        label: "Timed",
        kind: :boolean,
        default: true
      )
    ]
  end

  def options_summary(options)
    options["timed"] ? "timed" : "untimed"
  end
end.new

definitions = content_game.effective_option_definitions
assert(
  definitions.map(&:key) == ["content_language_id", "content_set_id", "timed"],
  "the language must be offered before the set that depends on it"
)
options = content_game.default_options
assert(options["content_set_id"] == "quiz.general", "the default content set was not selected")
assert(options["content_language_id"] == "pl-PL", "the default content language was not selected")
assert(options["content_pack_id"] == pack.id, "the default pack was not selected")
assert(options["content_pack_version"] == 2, "the pack version was not stored")
assert(options["content_pack_checksum"] == pack.checksum, "the pack checksum was not stored")
assert(content_game.validation_error(options) == nil, "valid content options were rejected")
assert(content_game.selected_content_pack(options).equal?(pack), "the selected pack was not resolved")
assert(content_game.combined_options_summary(options).include?("General knowledge"), "the pack is missing from the option summary")
assert(content_game.combined_options_summary(options).include?("timed"), "game options disappeared from the summary")

english_options = content_game.normalize_options(
  "content_set_id" => "quiz.general",
  "content_language_id" => "en",
  "timed" => false
)
assert(english_options["content_pack_id"] == english_pack.id, "changing language did not select its pack variant")
assert(content_game.selected_content_pack(english_options).equal?(english_pack), "the English variant was not resolved")
assert(content_game.validation_error(english_options) == nil, "a valid set-language pair was rejected")

wrong_version = options.merge("content_pack_version" => 1)
assert(content_game.validation_error(wrong_version).include?("different version"), "a mismatched pack version was accepted")
wrong_checksum = options.merge("content_pack_checksum" => "0" * 64)
assert(content_game.validation_error(wrong_checksum).include?("does not match"), "a mismatched pack checksum was accepted")
wrong_variant = options.merge("content_pack_id" => english_pack.id)
assert(content_game.validation_error(wrong_variant).include?("set and language"), "a pack from another language was accepted")
unknown = content_game.normalize_options("content_set_id" => "quiz.missing", "content_language_id" => "pl-PL", "timed" => false)
assert(unknown["content_set_id"] == "quiz.missing", "an unknown set silently changed to the default")
assert(content_game.validation_error(unknown).include?("set is not installed"), "an unknown set did not block the game")
missing_language = content_game.normalize_options("content_set_id" => "quiz.general", "content_language_id" => "de")
assert(missing_language["content_language_id"] == "de", "an unavailable language silently changed")
assert(content_game.validation_error(missing_language).include?("language is not available"), "an unavailable language did not block the game")

polish_only = registry.register_pack(
  GameRoomContent::Pack.new(
    id: "quiz.witcher.pl",
    set_id: "quiz.witcher",
    kind: :quiz,
    language_id: "pl-PL",
    version: 1,
    title: "Witcher",
    game_ids: ["quiz"],
    data: {
      questions: [
        { id: "geralt", prompt: "Who is the witcher of Rivia", answers: ["Geralt"] }
      ]
    }
  )
)
assert(
  content_game.send(:available_content_sets, "pl-PL").map(&:id).sort == ["quiz.general", "quiz.witcher"],
  "the Polish language did not offer both of its sets"
)
assert(
  content_game.send(:available_content_sets, "en").map(&:id) == ["quiz.general"],
  "English offered a set that has no pack in that language"
)
switched = content_game.normalize_options(
  "content_set_id" => "quiz.witcher",
  "content_language_id" => "en",
  "timed" => false
)
assert(switched["content_set_id"] == "quiz.general", "a set unavailable in the chosen language was not replaced")
assert(content_game.validation_error(switched) == nil, "the repaired set-language pair was still rejected")
witcher_options = content_game.normalize_options(
  "content_set_id" => "quiz.witcher",
  "content_language_id" => "pl-PL",
  "timed" => false
)
assert(content_game.selected_content_pack(witcher_options).equal?(polish_only), "the Polish-only set was not resolved")

# A game may deliberately reuse another game's content catalog without
# modifying the packs' supported game IDs or the stored content identity.
shared_content_game = Class.new(GameRoomGames::Base) do
  def id; "shared_quiz_fixture"; end
  def name; "Shared quiz content"; end
  def content_pack_kind; :quiz; end
  def content_pack_game_id; "quiz"; end
  define_method(:content_registry) { registry }
end.new
original_manifest = pack.manifest
shared_options = shared_content_game.normalize_options(
  "content_set_id" => "quiz.general", "content_language_id" => "pl-PL"
)
shared_definitions = shared_content_game.effective_option_definitions(shared_options)
assert(shared_definitions.find { |definition| definition.key == "content_language_id" }.choices.map(&:value).sort == ["en", "pl-PL"],
  "the shared catalog lost a language")
assert(shared_definitions.find { |definition| definition.key == "content_set_id" }.choices.map(&:value).sort == ["quiz.general", "quiz.witcher"],
  "the shared catalog lost a content set")
assert(shared_content_game.selected_content_pack(shared_options).equal?(pack), "the shared game did not use the original pack instance")
assert(shared_content_game.validation_error(shared_options) == nil, "shared content passed selection but failed compatibility validation")
assert(shared_content_game.options_from_json(JSON.generate(shared_options)) == shared_options,
  "reading shared content options changed their recorded identity")
assert(shared_content_game.combined_options_summary(shared_options).include?("General knowledge"), "the shared pack disappeared from the summary")
assert(pack.manifest == original_manifest && pack.game_ids == ["quiz"], "sharing content rewrote its manifest")
assert(registry.packs_for(game_id: shared_content_game.id, kind: :quiz).empty?, "sharing widened the registry's game compatibility")
assert(content_game.content_pack_game_id == content_game.id, "the default provider changed existing games")
shared_english = shared_content_game.normalize_options("content_set_id" => "quiz.general", "content_language_id" => "en")
assert(shared_content_game.validation_error(shared_english) == nil && shared_content_game.selected_content_pack(shared_english).equal?(english_pack),
  "changing language did not select the shared catalog's matching pack")
shared_wrong_version = shared_options.merge("content_pack_version" => 1)
assert(shared_content_game.validation_error(shared_wrong_version).include?("different version"), "sharing bypassed the version pin")
assert(shared_content_game.selected_content_pack(shared_wrong_version) == nil, "sharing resolved an incorrect version")
shared_wrong_checksum = shared_options.merge("content_pack_checksum" => "0" * 64)
assert(shared_content_game.validation_error(shared_wrong_checksum).include?("does not match"), "sharing bypassed the checksum pin")
assert(shared_content_game.selected_content_pack(shared_wrong_checksum) == nil, "sharing resolved an incorrect checksum")
assert(shared_content_game.options_from_json(JSON.generate(shared_wrong_checksum)) == shared_wrong_checksum,
  "normalization silently repaired an incorrect shared checksum")
shared_wrong_kind = shared_options.merge("content_set_id" => lazy.set_id, "content_pack_id" => lazy.id)
assert(shared_content_game.validation_error(shared_wrong_kind).include?("not compatible"), "sharing admitted a different content kind")

puts "Game content pack tests passed"
