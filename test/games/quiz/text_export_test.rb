# encoding: UTF-8
require 'tmpdir'
require_relative "../../../tools/export-quiz-text"
require_relative "../../../tools/support/release_files"
def assert(value, message); raise message unless value; end

files = QuizTextExport.files
packs = GameRoomContent.registry.packs.select { |pack| pack.kind.to_s == 'quiz' }
assert(packs.size == 4, 'Expected three general sets and the new books-only Witcher set')
assert(files.size == packs.size, 'Not every quiz set was exported')
assert(!GameRoomReleaseFiles.allowed?('tools/export-quiz-text.rb'), 'Exporter must not enter the installer')
files.each_key { |name| assert(!GameRoomReleaseFiles.allowed?("docs/quiz-questions/#{name}"), 'Review TXT must not enter the installer') }
packs.each do |pack|
  text = files.fetch(QuizTextExport::NAMES.fetch(pack.id))
  assert(text.encoding == Encoding::UTF_8 && text.valid_encoding?, 'Invalid TXT encoding')
  blocks = text.split("\n\n").drop(1)
  questions = pack.data.fetch('questions')
  assert(blocks.size == questions.size, 'Missing or duplicated question blocks')
  questions.zip(blocks).each_with_index do |(q, block), index|
    lines = block.lines.map(&:chomp)
    assert(lines.first == (index + 1).to_s, 'Question numbers must be consecutive and start at 1 in each set')
    assert(lines.size == 7 && lines[1] == q.fetch('prompt'), 'Question text changed')
    options = lines[2,4].map { |line| line.sub(/\A[A-D]\. /, '') }
    assert(options.sort == [q['correct'], *q['wrong']].sort, 'Answer set changed')
    letter = ('A'.ord + options.index(q['correct'])).chr
    assert(lines.last.end_with?(": #{letter}. #{q['correct']}"), 'Incorrect answer key')
    assert(!block.include?(q['id']), 'An internal question ID was exposed')
  end
end
sample_questions = packs.first.data.fetch('questions').first(3)
sample_pack = Struct.new(:language_id, :title, :data).new(packs.first.language_id, 'Numbering test', {})
numbering_cases = {
  'initial' => sample_questions.first(2),
  'append' => sample_questions,
  'remove middle' => sample_questions.values_at(0, 2),
  'remove first' => sample_questions.drop(1),
  'reorder' => sample_questions.values_at(2, 0, 1),
  'empty' => []
}
numbering_cases.each do |scenario, questions|
  sample_pack.data = { 'questions' => questions }
  blocks = QuizTextExport.render(sample_pack).split("\n\n").drop(1)
  assert(blocks.size == questions.size, "Question count changed after #{scenario}")
  blocks.each_with_index do |block, index|
    lines = block.lines.map(&:chomp)
    assert(lines.first == (index + 1).to_s, "Numbering has gaps or duplicates after #{scenario}")
    assert(lines[1] == questions[index].fetch('prompt'), "Question order changed after #{scenario}")
  end
end
Dir.mktmpdir('quiz-text-export-') do |dir|
  QuizTextExport.export(directory: dir)
  before = Dir.glob('*.txt', base: dir).to_h do |name|
    path = File.join(dir, name)
    [path, File.binread(path)]
  end
  assert(before.size == files.size, 'Export did not create every expected file')
  QuizTextExport.export(directory: dir)
  assert(before.all? { |path, bytes| bytes == File.binread(path) }, 'Non-deterministic export')
  QuizTextExport.export(check: true, directory: dir)
  File.write(before.keys.first, 'stale')
  begin
    QuizTextExport.export(check: true, directory: dir)
    raise 'Stale export was accepted'
  rescue RuntimeError => error
    raise unless error.message.start_with?('Out-of-date quiz lists:')
  end
  File.binwrite(before.keys.first, before.values.first)
  File.write(File.join(dir, 'obsolete-set.txt'), 'must be reviewed before removal')
  begin
    QuizTextExport.export(check: true, directory: dir)
    raise 'Unknown export file was ignored'
  rescue RuntimeError => error
    raise unless error.message == 'Unexpected old export files: obsolete-set.txt'
  end
end
QuizTextExport.export(check: true)
puts 'Quiz TXT: every set, consecutive numbers, complete answers, stable ordering, no IDs and up-to-date copies: OK'
