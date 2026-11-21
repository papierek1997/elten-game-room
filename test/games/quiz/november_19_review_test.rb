# encoding: UTF-8
require_relative '../../../content/languages'
require_relative '../../../content/quiz_pl_wikidata'
require_relative '../../support/quiz_editorial_baseline'

def assert(value, message); raise message unless value; end

pack = GameRoomContent.registry.pack('quiz.wikidata.pl')
questions = pack.data.fetch('questions')
fixture = JSON.parse(File.read(File.expand_path('../../fixtures/quiz/november_19_review.json', __dir__), encoding: 'UTF-8'))
by_id = questions.to_h { |row| [row.fetch('id'), row] }
fixture.fetch('changes').each do |change|
  change.fetch('after').each do |field, value|
    assert(by_id.fetch(change.fetch('id')).fetch(field) == value, "Reported correction missing: #{change['id']}.#{field}")
  end
end
additions = questions.select { |row| row.fetch('id').start_with?('community_zz_20261119_') }
assert(additions == fixture.fetch('additions'), 'Reviewed proposals, answers, attribution or ordering changed')
expected_positions = [2, 3, 4, 6, 7, 9, 10, 12, 13, 14, 16]
assert(additions.map { |row| row.fetch('id') } == expected_positions.map { |n| format('community_zz_20261119_%02d', n) },
  'Rejected duplicates or the ambiguous vinyl proposal entered the set')
original = JSON.generate(questions)
earlier = QuizEditorialBaseline.before_november_19_review(questions)
assert(JSON.generate(questions) == original, 'Historical restoration modified the active data')
old_pack = GameRoomContent::Pack.new(id: pack.id, set_id: pack.set_id, kind: pack.kind,
  language_id: pack.language_id, title: pack.title, game_ids: pack.game_ids,
  version: 24, data: pack.data.merge('questions' => earlier))
assert(earlier.size == 14976 && old_pack.checksum == '7b9a417ee0590cd544985b1abeb873a163be8331562ce566179f385a73ab29fb',
  'Unreviewed changes to the previous Polish general set')
categories = earlier.map { |row| row.fetch('category') }.uniq
additions.each do |row|
  assert(categories.include?(row.fetch('category')), 'A proposal created a new category')
  assert(row.fetch('author') == 'Zuzler' && row.fetch('source_dataset') == 'Power Games community', 'Lost contributor provenance')
  assert(row.fetch('source').start_with?('https://') && !row.fetch('source_license').include?('CC0'), 'Missing reference or invented license')
  assert(row.fetch('review_required') == false, 'An unresolved proposal was accepted')
end

# These history helpers must not conceal a later unintended answer/provenance
# edit, a different suffix, a missing addition, or a reordered import.
variants = [
  questions.map { |row| row['id'] == additions.last.fetch('id') ? row.merge('correct' => 'Unapproved change') : row },
  questions + [additions.last.merge('id' => 'unapproved_extra')],
  questions[0...-1],
  questions[0...-2] + questions.last(2).reverse
]
variants.each do |altered|
  begin
    QuizEditorialBaseline.before_november_19_review(altered)
    raise 'The baseline concealed an unapproved addition'
  rescue RuntimeError => error
    raise unless error.message.start_with?('Unapproved quiz addition:')
  end
end
fixture.fetch('changes').each do |change|
  field = change.fetch('after').keys.first
  altered = questions.map { |row| row['id'] == change.fetch('id') ? row.merge(field => 'Unapproved change') : row }
  begin
    QuizEditorialBaseline.before_november_19_review(altered)
    raise 'The baseline concealed an unapproved correction'
  rescue RuntimeError => error
    raise unless error.message == "Unapproved quiz edit: #{change.fetch('id')}.#{field}"
  end
end
puts 'PASS four reported corrections, eleven reviewed proposals and exact preservation of the prior pack'
