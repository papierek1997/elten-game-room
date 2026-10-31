require_relative "../../support/assertions"
require_relative "../../support/elten_array_shuffle"
require_relative "../../../content/languages"
require_relative "../../../content/quiz_general_en"
require_relative "../../../content/quiz_general_ru"
require_relative "../../../content/quiz_pl_wikidata"
require_relative "../../../content/quiz_witcher_pl"
require_relative "../../../content/quiz_harry_potter_pl"
require_relative "../../../games/duck_racing_support/question_sets"

include GameRoomTest::Assertions
adapter = GameRoomDuckRacing::QuestionSets
catalog = adapter.catalog
assert_equal(5, catalog.length)
assert_equal(["quiz.general"], adapter.defaults("en"))
assert_equal(["quiz.wikidata"], adapter.defaults("pl-PL"))
assert_equal(["quiz.general.ru"], adapter.defaults("ru-RU"))
assert_raises(adapter::Unavailable) { adapter.defaults("cs-CZ") }
assert_equal(%w[quiz.harry_potter.books quiz.wikidata quiz.witcher.books], adapter.choices(language: "pl-PL").map { |entry| entry[:value] }.sort)
assert_equal(["quiz.general"], adapter.choices(language: "en").map { |entry| entry[:value] })
assert_equal(["quiz.wikidata"], adapter.prepare_selected(ids: adapter.defaults("pl-PL"), language: "pl-PL").selection.keys)
selection = catalog.to_h { |entry| [entry[:set_id], entry[:languages].first[:language_id]] }
pool = adapter.prepare(selection: selection, weights: selection.transform_values { 1 })
seen = {}
200.times do |seed|
  question = pool.draw(seed: seed)
  seen[question[:set_id]] = true
  pack = GameRoomContent.registry.pack(question[:pack_id])
  original = pack.data.fetch("questions").find { |entry| entry["id"] == question[:question_id] }
  assert(original)
  assert_equal(original["prompt"], question[:prompt], "question text was rewritten")
  assert_equal(original["correct"], question[:choices].fetch(question[:correct_index]))
  assert_equal(original["wrong"].sort, question[:choices].each_with_index.filter_map { |choice, index| choice if index != question[:correct_index] }.sort)
  assert_equal(selection.fetch(question[:set_id]), question[:language_id])
  assert_equal(false, adapter.public_view(question).key?(:correct_index))
end
assert_equal(selection.keys.sort, seen.keys.sort)
puts "PASS Duck Racing real question resources: all five current sets usable, exact prompts/ABCD preserved, private correct index excluded from presentation"
