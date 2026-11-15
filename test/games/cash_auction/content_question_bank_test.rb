require_relative '../../support/assertions'
require_relative '../../support/elten_array_shuffle'
require_relative '../../../lib/cash_auction/question_bank'

include GameRoomTest::Assertions
row = ->(id, category, source) do
  {'id'=>id, 'category'=>category, 'prompt'=>"#{source}: #{id}",
    'correct'=>"#{source} correct", 'wrong'=>%w[first second third]}
end
pack = ->(id, rows) do
  GameRoomContent::Pack.new(id: "test.#{id}.en", set_id: "test.#{id}", kind: 'quiz',
    language_id: 'en', version: 1, title: id, game_ids: ['quiz'], data: {'questions'=>rows})
end
a = pack.call('a', [row.call('same', 'Alpha', 'A'), row.call('other', 'Zulu', 'A')])
b = pack.call('b', [row.call('same', 'Alpha', 'B'), row.call('other', 'Zulu', 'B')])
bank = GameRoomCashAuction::QuestionBank.new([b, a])
assert_equal(%w[Alpha Zulu], bank.categories.map { |id| bank.category_label(id) })
first = bank.draw(category: 0, seed: 12)
assert_equal('same', first[:question_id])
assert_equal(["#{first[:pack_id]}:same"], first[:used])
second = bank.draw(category: 0, seed: 12, used: first[:used])
assert(first[:pack_id] != second[:pack_id], 'Colliding pack-local question IDs were treated as one question')
assert_equal(first, GameRoomCashAuction::QuestionBank.new([a, b]).draw(category: 0, seed: 12), 'Checkbox order changed the draw or answer order')
assert_equal(2, second[:used].length)
zulu = bank.draw(category: 1, seed: 6, used: second[:used])
cycled = bank.draw(category: 0, seed: 12, used: zulu[:used])
assert_equal(2, cycled[:used].length)
assert(cycled[:used].include?(zulu[:used].last), 'Recycling one category forgot the other category')
assert_equal(3, zulu[:used].length, 'Recycling mutated the caller ledger')

80.times do |seed|
  result = bank.draw(category: seed % 2, seed: seed)
  source = [a, b].find { |item| item.id == result[:pack_id] }
  question = source.data['questions'].find { |item| item['id'] == result[:question_id] }
  assert_equal(source.set_id, result[:set_id])
  assert_equal(source.checksum, result[:pack_checksum])
  assert_equal(question['correct'], result[:choices].fetch(result[:correct_index]))
  assert(question['prompt'].equal?(result[:prompt]), 'The pool copied shared question text')
  public_data = bank.public_view(result)
  assert_equal(false, public_data.key?(:correct_index))
  assert_equal(false, public_data.key?(:used))
end

# Passing an individual Pack keeps the original bare-ID ledger and exact RNG
# sequence. A one-pack Array is the explicit new pool schema for EN/RU.
single = GameRoomCashAuction::QuestionBank.new(a)
legacy = single.draw(category: 0, seed: 12)
assert_equal(['same'], legacy[:used])
assert_equal(legacy.reject { |key, _| key == :used },
  GameRoomCashAuction::QuestionBank.new([a]).draw(category: 0, seed: 12).reject { |key, _| key == :used })
assert_equal(['test.a.en:same'], GameRoomCashAuction::QuestionBank.new([a]).draw(category: 0, seed: 12)[:used])
[[], [a, a], [a, b, a, b], [nil], [a, 'pack']].each do |invalid|
  assert_raises(ArgumentError) { GameRoomCashAuction::QuestionBank.new(invalid) }
end
foreign = GameRoomContent::Pack.new(id: 'test.foreign.pl', set_id: 'test.foreign', kind: 'quiz',
  language_id: 'pl-PL', version: 1, title: 'Foreign', game_ids: ['quiz'], data: a.data)
assert_raises(ArgumentError) { GameRoomCashAuction::QuestionBank.new([a, foreign]) }
[['same'], ["#{a.id}:missing"], ["#{a.id}:same", "#{a.id}:same"]].each do |used|
  assert_raises(ArgumentError) { bank.draw(category: 0, seed: 12, used: used) }
end

puts 'Cash Auction merged question bank: canonical pack order, per-pack provenance, collision-free category cycles and unchanged legacy single-pack RNG passed.'
