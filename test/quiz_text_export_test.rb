# encoding: UTF-8
require 'tmpdir'
require_relative '../tools/export-quiz-text'
require_relative '../tools/release_files'
def assert(value, message); raise message unless value; end

files = QuizTextExport.files
packs = GameRoomContent.registry.packs.select { |pack| pack.kind.to_s == 'quiz' }
assert(packs.size >= 6, 'Expected the six current quiz sets')
assert(files.size == packs.size, 'Not every quiz set was exported')
assert(!GameRoomReleaseFiles.allowed?('tools/export-quiz-text.rb'), 'Exporter must not enter the installer')
files.each_key { |name| assert(!GameRoomReleaseFiles.allowed?("docs/quiz-questions/#{name}"), 'Review TXT must not enter the installer') }
packs.each do |pack|
  text = files.fetch(QuizTextExport::NAMES.fetch(pack.id))
  assert(text.encoding == Encoding::UTF_8 && text.valid_encoding?, 'Invalid TXT encoding')
  blocks = text.split("\n\n").drop(1)
  questions = pack.data.fetch('questions')
  assert(blocks.size == questions.size, 'Missing or duplicated question blocks')
  questions.zip(blocks).each do |q, block|
    lines = block.lines.map(&:chomp)
    assert(lines.size == 6 && lines.first == q.fetch('prompt'), 'Question text changed')
    options = lines[1,4].map { |line| line.sub(/\A[A-D]\. /, '') }
    assert(options.sort == [q['correct'], *q['wrong']].sort, 'Answer set changed')
    letter = ('A'.ord + options.index(q['correct'])).chr
    assert(lines.last.end_with?(": #{letter}. #{q['correct']}"), 'Incorrect answer key')
    assert(!block.include?(q['id']), 'An internal question ID was exposed')
  end
end
Dir.mktmpdir('quiz-text-export-') do |dir|
  QuizTextExport.export(directory: dir)
  before = Dir[File.join(dir, '*.txt')].to_h { |path| [path, File.binread(path)] }
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
end
QuizTextExport.export(check: true)
puts 'Quiz TXT: every set, complete answers, stable ordering, no IDs and up-to-date copies: OK'
