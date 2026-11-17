require_relative '../../../content/languages'
require_relative '../../../content/quiz_pl_wikidata'
require_relative '../../support/quiz_editorial_baseline'

def assert(value, message); raise message unless value; end

questions = GameRoomContent.registry.pack('quiz.wikidata.pl').data.fetch('questions')
original = JSON.generate(questions)
restored = QuizEditorialBaseline.before_november_review(questions)
assert(JSON.generate(questions) == original, 'Editorial baseline mutated the released questions')
assert(restored.size == questions.size + 2, 'Rejected questions were not restored for the historical audit')
assert(restored.any? { |row| row['id'] == '1z10_281cbf9bc456d7ce' }, 'Missing historical spelling question')
assert(restored.find { |row| row['id'] == 'polqa_05662' }['correct'] == 'Gutenberg', 'Historical answer not restored')
latest = QuizEditorialBaseline.before_november_17_review(questions)
assert(latest.map { |row| row.except('prompt') } == questions.map { |row| row.except('prompt') },
  'The November 17 prompt review changed answers, provenance, IDs or order')
changes = JSON.parse(File.read(File.expand_path('../../fixtures/quiz/november_17_review.json', __dir__))).fetch('changes')
assert(changes.length == 6, 'The approved November 17 wording scope changed')
changes.each do |change|
  id = change.fetch('id')
  assert(latest.find { |row| row['id'] == id }.fetch('prompt') == change.fetch('before').fetch('prompt'),
    "Missing historical prompt: #{id}")
  altered = questions.map { |row| row['id'] == id ? row.merge('prompt'=>'Unapproved change') : row }
  begin
    QuizEditorialBaseline.before_november_17_review(altered)
    raise 'An unapproved later wording change was hidden'
  rescue RuntimeError => error
    raise unless error.message == "Unapproved quiz edit: #{id}.prompt"
  end
end
changed = Marshal.load(Marshal.dump(questions))
changed.find { |row| row['id'] == 'polqa_05662' }['correct'] = 'Unapproved change'
begin
  QuizEditorialBaseline.before_november_review(changed)
  raise 'Unapproved edit was hidden by the baseline'
rescue RuntimeError => error
  raise unless error.message == 'Unapproved quiz edit: polqa_05662.correct'
end
puts 'PASS historical quiz checks undo only approved edits without mutating current content or hiding new edits'
