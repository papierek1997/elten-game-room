require_relative '../../support/assertions'
require_relative '../../support/elten_array_shuffle'
require_relative '../../../lib/cash_auction/question_bank'
require_relative '../../../content/languages'
require_relative '../../../content/quiz_general_en'

include GameRoomTest::Assertions

row = ->(id, category) do
  {'id'=>id, 'category'=>category, 'prompt'=>"Question #{id}",
    'correct'=>"Answer #{id}", 'wrong'=>%w[first second third]}
end
rows = [row.call('z1', 'Zulu'), row.call('a1', 'Alpha'),
  row.call('a2', 'Alpha'), row.call('z2', 'Zulu')]
metadata = {id: 'test.cash.en', set_id: 'test.cash', kind: 'quiz',
  language_id: 'en', version: 3, title: 'Questions', game_ids: ['quiz']}
pack = GameRoomContent::Pack.new(**metadata, data: {'questions'=>rows})
bank = GameRoomCashAuction::QuestionBank.new(pack)
assert_equal([0, 1], bank.categories)
assert_equal(%w[Alpha Zulu], bank.categories.map { |id| bank.category_label(id) })
assert(bank.categories.frozen?, 'Category IDs were mutable')

used = ['z1'].freeze
first = bank.draw(category: 0, seed: 91, used: used)
assert_equal(first, bank.draw(category: 0, seed: 91, used: used))
assert_equal(['z1'], used, 'Drawing mutated the supplied used IDs')
assert_equal(0, first[:category])
assert(%w[a1 a2].include?(first[:question_id]), 'The draw crossed into another category')
assert_equal(['z1', first[:question_id]], first[:used])
second = bank.draw(category: 0, seed: 91, used: first[:used])
assert(first[:question_id] != second[:question_id], 'A question repeated before category exhaustion')
before_cycle = second[:used].dup
cycled = bank.draw(category: 0, seed: 91, used: second[:used])
assert_equal(before_cycle, second[:used], 'Recycling changed an earlier question result')
assert_equal(['z1', cycled[:question_id]], cycled[:used], 'Recycling removed another category or retained the exhausted cycle')
following = bank.draw(category: 0, seed: 91, used: cycled[:used])
assert(cycled[:question_id] != following[:question_id], 'The second cycle repeated too early')
assert_equal([0, 1], GameRoomCashAuction::QuestionBank.new(pack).categories)
assert_equal(first, GameRoomCashAuction::QuestionBank.new(pack).draw(category: 0, seed: 91, used: used), 'Cold replay changed the question or answer order')

positions = []
80.times do |seed|
  question = bank.draw(category: seed % 2, seed: seed)
  source = pack.data['questions'].find { |item| item['id'] == question[:question_id] }
  assert_equal(source['correct'], question[:choices].fetch(question[:correct_index]))
  assert_equal(4, question[:choices].uniq.length)
  assert_equal(pack.id, question[:pack_id])
  assert_equal(pack.set_id, question[:set_id])
  assert_equal(pack.language_id, question[:language_id])
  assert_equal(pack.version, question[:pack_version])
  assert_equal(pack.checksum, question[:pack_checksum])
  assert(question[:prompt].equal?(source['prompt']), 'The adapter copied immutable question text')
  assert(question.frozen? && question[:choices].frozen? && question[:used].frozen?, 'Resolver result was mutable')
  positions << question[:correct_index]
  view = bank.public_view(question.merge(unexpected_secret: 'must stay private'))
  assert_equal(false, view.key?(:correct_index))
  assert_equal(false, view.key?(:correct))
  assert_equal(false, view.key?(:used))
  assert_equal(false, view.key?(:unexpected_secret))
  view[:choices][0].replace('changed')
  view[:prompt].replace('changed')
  assert_equal(source['prompt'], question[:prompt], 'Public view changed resolver data')
  assert_equal(source['correct'], question[:choices].fetch(question[:correct_index]))
end
assert_equal([0, 1, 2, 3], positions.uniq.sort)
assert_equal(nil, bank.public_view(nil))
[-1, 2, '0', nil].each do |category|
  assert_raises(ArgumentError) { bank.category_label(category) }
  assert_raises(ArgumentError) { bank.draw(category: category, seed: 0) }
end
[-1, 1 << 128, 'seed', nil].each do |seed|
  assert_raises(ArgumentError) { bank.draw(category: 0, seed: seed) }
end
[nil, 'a1', ['missing'], %w[a1 a1], Array.new(5, 'a1')].each do |ids|
  assert_raises(ArgumentError) { bank.draw(category: 0, seed: 1, used: ids) }
end
[[], [rows.first, rows.first], [rows.first.merge('wrong'=>%w[first second])],
  [rows.first.merge('correct'=>'FIRST')]].each do |invalid|
  invalid_pack = GameRoomContent::Pack.new(**metadata, data: {'questions'=>invalid})
  assert_raises(ArgumentError) { GameRoomCashAuction::QuestionBank.new(invalid_pack) }
end
non_quiz = GameRoomContent::Pack.new(**metadata.merge(kind: 'words'), data: {'questions'=>rows})
assert_raises(ArgumentError) { GameRoomCashAuction::QuestionBank.new(non_quiz) }

# One actual shared pack, loaded once. Preparing/drawing borrows its frozen
# question rows rather than exporting or cloning the quiz database.
actual_pack = GameRoomContent.registry.pack('quiz.general.en')
manifest = actual_pack.manifest
actual = GameRoomCashAuction::QuestionBank.new(actual_pack)
actual_question = actual.draw(category: actual.categories.first, seed: 0x123456789abcdef)
assert_equal(actual.category_label(actual_question[:category]),
  actual_pack.data['questions'].find { |item| item['id'] == actual_question[:question_id] }['category'])
assert_equal(manifest, actual_pack.manifest, 'Question selection changed the real content manifest')
assert_equal(['quiz'], actual_pack.game_ids)
assert_equal(actual_question, GameRoomCashAuction::QuestionBank.new(actual_pack).draw(category: actual.categories.first, seed: 0x123456789abcdef))
assert_equal(false, actual.public_view(actual_question).key?(:correct_index))

puts 'Cash Auction question bank: category IDs, deterministic ABCD, bounded non-repeating cycles, immutable shared data, private-field projection and the actual quiz pack passed.'
