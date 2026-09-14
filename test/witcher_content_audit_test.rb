require "json"
require "open3"
require "rbconfig"

$LOAD_PATH.unshift(File.expand_path("..", __dir__))

def _(text)
  text
end


def assert(condition, message)
  raise message if !condition
end

root = File.expand_path("..", __dir__)
stdout, stderr, status = Open3.capture3(RbConfig.ruby, "tools/rebuild-audited-witcher-quiz.rb", "--check", chdir: root)
assert(status.success?, "the Witcher audit cannot be reproduced: #{stdout}#{stderr}")
removals = JSON.parse(File.read(File.join(root, "content", "QUIZ_WITCHER_REMOVALS.json"), encoding: "UTF-8"))
edits = JSON.parse(File.read(File.join(root, "content", "QUIZ_WITCHER_EDITS.json"), encoding: "UTF-8"))
ledger = JSON.parse(File.read(File.join(root, "content", "QUIZ_WITCHER_AUDIT_LEDGER.json"), encoding: "UTF-8"))
assert(removals.fetch("removal_count") == 6_187 && removals.fetch("removals").length == 6_187, "the Witcher removal manifest is incomplete")
assert(edits.fetch("edit_count") == 35 && edits.fetch("edits").length == 35, "the Witcher edit manifest is incomplete")
assert(removals.fetch("removals").all? { |row| %w[category correct id level prompt wrong].all? { |key| row.fetch("original").key?(key) } }, "a Witcher removal lacks its complete old question")
assert(edits.fetch("edits").all? { |row| row.fetch("original") != row.fetch("replacement") }, "a Witcher edit does not change its old question")
assert(ledger.fetch("questions_checked") == 6_571 && ledger.fetch("question_checks").length == 6_571, "the Witcher audit ledger is incomplete")
assert(ledger.fetch("source_pages_checked") == 2_542, "the Witcher source-page ledger is incomplete")
assert(ledger.fetch("outcomes") == { "remove" => 6_187, "keep" => 349, "edit" => 35 }, "the Witcher audit outcomes changed")
assert(ledger.fetch("question_checks").all? { |row| row.fetch("source_revid") != nil && row.fetch("source_timestamp") != nil }, "a Witcher question has no source revision")

require_relative "../content/languages"
require_relative "../content/quiz_witcher_pl"
require_relative "../content/quiz_witcher_pl_medium_data"
full_pack = GameRoomContent.registry.pack("quiz.witcher.pl")
game_pack = GameRoomContent.registry.pack("quiz.witcher.g.pl")
book_pack = GameRoomContent.registry.pack("quiz.witcher.b.pl")
full = full_pack.data.fetch("questions")
games = game_pack.data.fetch("questions")
books_screen = book_pack.data.fetch("questions")
assert([full.length, games.length, books_screen.length] == [384, 144, 240], "an audited Witcher set has the wrong size")
full_ids = full.map { |question| question.fetch("id") }
game_ids = games.map { |question| question.fetch("id") }
book_ids = books_screen.map { |question| question.fetch("id") }
assert(full_ids.uniq.length == full.length, "the full Witcher set has duplicate IDs")
assert((game_ids & book_ids).empty?, "the detailed Witcher sets overlap")
assert((game_ids + book_ids).sort == full_ids.sort, "the detailed Witcher sets do not partition the full set")
assert([full_pack, game_pack, book_pack].all? { |pack| pack.version == 3 && pack.entry_count == pack.data.fetch("questions").length }, "an audited Witcher pack has stale metadata")
assert(ledger.fetch("expected_packs").all? do |id, expected|
  pack = GameRoomContent.registry.pack(id)
  pack.checksum == expected.fetch("checksum") && pack.entry_count == expected.fetch("questions")
end, "the Witcher audit ledger disagrees with a registered pack")

classification = GameRoomContent::WitcherPolishMediumData.load
assert(classification.fetch("version") == 3, "the Witcher medium data has the wrong version")
assert(classification.fetch("source_question_count") == 384, "the Witcher medium map has the wrong size")
assert(classification.fetch("media").values.tally == { "g" => 144, "b" => 231, "s" => 9 }, "the audited medium totals changed")
assert(classification.fetch("media").keys.sort == full_ids.sort, "the medium map does not cover the audited questions")
assert(classification.fetch("prompts").empty?, "audited prompts are duplicated outside the shared source database")

removed_ids = removals.fetch("removals").map { |row| row.fetch("id") }
assert((full_ids & removed_ids).empty?, "a removed Witcher question remains playable")
full_by_id = full.to_h { |question| [question.fetch("id"), question] }
edits.fetch("edits").each do |row|
  replacement = row.fetch("replacement").reject { |key, _value| key == "medium_code" }
  assert(full_by_id.fetch(row.fetch("original_id")) == replacement, "an audited Witcher edit was not applied")
end
assert(full.all? do |question|
  options = [question.fetch("correct"), *question.fetch("wrong")]
  (%w[category correct id level prompt wrong] - question.keys).empty? &&
    (question.keys - %w[category correct id level prompt source_links wrong]).empty? &&
    question.fetch("wrong").length == 3 && options.map(&:downcase).uniq.length == 4
end, "an audited Witcher question has an invalid structure")
assert(full.count { |question| question.key?("source_links") } + removals.fetch("removals").count { |row| row.fetch("original").key?("source_links") } == 11, "the audit lost explicit question source links")
assert((full_ids & %w[9d208cb56c0d 507a9f55a112 c0cc0e45e3eb 1617a8bee572 0bbc5e2d8e54 673ae650419a 7cf767a90032 ad72438d23f5 2a96a36bef4e 853bc19cabcb 30169c67c107 0e366201bc9d a8b3acf58da9 d6afe446a0df 47a0dfefc2aa 085c49e4b888 9c7b8388f64e a39c0a19a939 e98370a085cf b145ba852682 c9d42c3c1bfc 7f83a348c7cb 2603a58e7ae9 a2767b1fd1ab 88074ef696da ece2e0537936 6f06b1f57842 67e80653d65d be5cb543959b 8438b58f2fda 8e3130083d6c e6cc1617ea0f 532a32e4030a 584e5081d42c 6b8cca6fe7a7 7393a3150a38 71f6303e6f48 134acf6ffc7f abd81049020c 7fe648e81469 12f5efdf00b1 8a8855a2eccc 41b7f337c4ad 0642fcdaf87a 5d643b32a78d cbdd9fa84015 a501e0bcdd20 d358c8b24ff7 a4b459c8c07d dfb30180d5c4 d7d11fb667a8 653da346f805 4c75ce3c0e04 241bcc62a095 a3825ed8bead dbfed6ed13d9 9f24c201e85a]).empty?, "an independently rejected Witcher question remains playable")
latest_rejected_ids = %w[
  e8f699538c95 bd59cbdf59fb 9a8b8cc33183 4ba9d6b1f172 99142dd7817d 8d2ffc96b1f2 fdb74d11b548 4550369c5d39 98b6881323e2 1f29214f46f9
  05729dcd4eff 07c1d125a138 0d164a42ee80 1739ab3d9a59 1cd43cef4af1 37379c1e6ff0 3d0c49fd7284 4393a1180b57 45f775e4de90 5bc98824f242 5eef2b3618b4 628004c51073 73ab20f4b2ba 77b9e978247b 932f787c0e2f 939b454f5176 9686d9c6a519 99a45c428b93 a2e876406066 ac1b106b350c b72e00389523 cf0686681a15
  075fe0f71f9f 22e7289ce11d 383bfee94f07 432709b4a153 4d27cf273869 54e37b5aedcb 5dfbfbd95bc1 666dac7756ee 85d58777dfb1 9329d34e0774 9518fbc2e7d9 d003bef67e92 d00dfb119664 e57014214f0d e8f69c78d23f
  2b899dee7c76 2ede512edc93 50798ae287af 7da1acdc1154 35fe761f1b68 3556c1bf1ca6 a7d9bb9a5c38
  2294557d75f7 25d1aed258ae 2d48fe43e287 4f223de4acaf 582ed456ae2f 67a1b0d5a45e 6d0dea60eaa2 7e2045a2b642 8901d065aa65 92ad2a23abdc 982ae8626f49 b3983989c496 e7321e48c256 f4d4c1651767 f4e5b5d90840 f6bad6486859
  80c92d9a11b4 da6ab80630b3 ad74d6496ea3 2f824b8a8256
]
assert((full_ids & latest_rejected_ids).empty?, "a fifth-review Witcher defect remains playable")
assert((full_ids & %w[f8b509d38865 f1baaf16e11a 18f7db84ec4a 6ab246edd7b2 7329411e6b06 61e8fa7261fb 38d4d357a009 528ff1e7543d 5f03862fb3c2 660d80b110d6 7cda3aa76dd4]).empty?, "a sixth-review Witcher defect remains playable")
non_games = ["Czwartki z Wiedźminem", "Cena neutralności", "Efekt Uboczny", "Pożegnanie Białego Wilka", "Wesele", "Wiedźmin 3: Krew i Wino", "Wiedźmin 3: Serca z Kamienia", "Gra Wyobraźni"]
assert(full.none? { |question| question.fetch("prompt").match?(/w której.*(?:grze|gier)/i) && ([question.fetch("correct"), *question.fetch("wrong")] & non_games).any? }, "a non-standalone work remains in game-appearance options")
non_single_books = ["Saga o wiedźminie", "Cykl wiedźmiński", "Wiedźmin. Oficjalna księga kucharska", "The Witcher: Gra Fabularna"]
assert(full.none? { |question| question.fetch("prompt").match?(/w której.*książce/i) && ([question.fetch("correct"), *question.fetch("wrong")] & non_single_books).any? }, "a non-book work remains in single-book appearance options")
assert(full.none? { |question| question.fetch("prompt").match?(/zagrał|zagrała|dubbingował|dubbingowała/i) && question.fetch("prompt").include?("w książkach z cyklu Wiedźmin") }, "an audiobook performance is misworded as occurring in a book")
assert(full.none? { |question| question.fetch("prompt").match?(/— jak zginęła ta postać(?: w |\?)/i) }, "a nonparallel free-text death question survived the audit")
assert(full.none? { |question| question.values.flatten.grep(String).any? { |value| value.match?(/\p{Cf}/) } }, "an invisible Unicode format character remains in the Witcher pack")
initial_case = lambda do |value|
  letter = value.each_char.find { |character| character.match?(/\p{L}/) }
  next :none if letter == nil
  letter == letter.upcase ? :upper : :lower
end
assert(full.none? do |question|
  correct_case = initial_case.call(question.fetch("correct"))
  wrong_cases = question.fetch("wrong").map { |value| initial_case.call(value) }
  wrong_cases.uniq.length == 1 && wrong_cases.first != correct_case
end, "answer capitalization reveals the correct option")
assert([games, books_screen].all? do |questions|
  questions.map { |question| question.fetch("category") }.uniq.length == 6 &&
    questions.map { |question| question.fetch("level") }.uniq.sort == %w[easy hard medium]
end, "a detailed Witcher set lost category or difficulty coverage")

puts "Witcher content audit tests passed: 6571 checked, 6187 removed, 35 edited, 384 retained"
