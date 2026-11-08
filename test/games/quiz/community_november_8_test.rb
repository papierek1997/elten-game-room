# encoding: UTF-8
require_relative '../../../content/languages'
require_relative '../../../content/quiz_pl_wikidata'
require_relative '../../../content/quiz_harry_potter_pl'
require_relative '../../support/quiz_editorial_baseline'

def assert(value, message); raise message unless value; end

def original_checksum(pack, questions, source: pack.data.fetch('source'))
  GameRoomContent::Pack.new(id: pack.id, set_id: pack.set_id, kind: pack.kind,
    language_id: pack.language_id, title: pack.title, game_ids: pack.game_ids,
    version: pack.version - 1, data: pack.data.merge('questions' => questions, 'source' => source)).checksum
end

general = GameRoomContent.registry.pack('quiz.wikidata.pl')
potter = GameRoomContent.registry.pack('quiz.harry_potter.books.pl')
prefixes = [
  [general, 'community_zz_20261108a_', 17, [2]],
  [general, 'community_zz_20261108b_', 25, [6, 17, 23, 25]],
  [potter, 'community_hp_zz_20261108_', 44, [5, 10, 12, 13, 15, 18, 19, 21, 22, 25, 28, 37, 38, 39]]
]
prefixes.each do |pack, prefix, size, excluded|
  rows = pack.data.fetch('questions')
  added, earlier = rows.partition { |row| row.fetch('id').start_with?(prefix) }
  expected = ((1..size).to_a - excluded).map { |position| format('%s%02d', prefix, position) }
  assert(added.map { |row| row.fetch('id') } == expected, "Missing or unexpected reviewed proposal: #{prefix}")
  categories = earlier.map { |row| row.fetch('category') }.uniq
  added.each do |row|
    id = row.fetch('id')
    assert(categories.include?(row.fetch('category')), "Proposal created a new category: #{id}")
    assert(row.fetch('author') == 'Zuzler' && row.fetch('review_required') == false, "Missing attribution or review: #{id}")
    assert(row.fetch('source').start_with?(pack == potter ? 'J.K. Rowling:' : 'https://'), "Missing source: #{id}")
    answers = [row.fetch('correct'), *row.fetch('wrong')]
    assert(answers.length == 4 && answers.map { |value| value.strip.downcase }.uniq.length == 4,
      "Missing or ambiguous choices: #{id}")
  end
end

questions = general.data.fetch('questions')
by_id = questions.to_h { |row| [row.fetch('id'), row] }
assert(!by_id.key?('1z10_281cbf9bc456d7ce'), 'Self-answering spelling question returned')
assert(by_id.fetch('polqa_01139').values_at('category', 'correct') == ['Kultura', 'literatury'],
  'Kościelscy category still gives the answer away')
assert(by_id.fetch('polqa_01468').values_at('category', 'correct') == ['Życie codzienne', 'spam'], 'Wrong spam category or answer')
assert(by_id.fetch('1z10_62fe83239e0adf39').fetch('correct') == 'Hajle Syllasje I', 'Regnal numeral changed')
assert(by_id.fetch('community_zz_20261108a_03').values_at('prompt', 'correct') ==
  ['Jak brzmi ukraińska nazwa miasta znanego po polsku jako Stanisławów?', 'Iwano-Frankiwsk'],
  'Reviewed geography wording or answer changed')
older_general = questions.reject { |row| row.fetch('id').start_with?('community_zz_20261108') }
older_general = QuizEditorialBaseline.before_november_8_review(older_general)
assert(original_checksum(general, older_general) == 'b857e9337d332f807de6619e586bae0d79e764240c2ec0152e306838ea3cca16',
  'Unreviewed changes to existing general questions')

older_potter = potter.data.fetch('questions').reject { |row| row.fetch('id').start_with?('community_hp_zz_20261108_') }
old_source = 'J.K. Rowling: siedem powieści o Harrym Potterze; propozycja LordKiller, redakcja Power Games'
assert(original_checksum(potter, older_potter, source: old_source) == '7592f7682d77cdee9d9f372593d23b673c71a18e517b5608b434537bac984b93',
  'Unreviewed changes to existing Potter questions')
puts 'PASS reviewed community additions, rejected items, source attribution, and preservation of both earlier question sets'
