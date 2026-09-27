# encoding: UTF-8
# Review copies only: the signed application still loads the Ruby data packs.
require 'digest'
require 'fileutils'
require_relative '../content/languages'
require_relative '../content/quiz_general_en'
require_relative '../content/quiz_general_ru'
require_relative '../content/quiz_pl_wikidata'
require_relative '../content/quiz_witcher_pl'

module QuizTextExport
  DIRECTORY = File.expand_path('../docs/quiz-questions', __dir__)
  NAMES = {
    'quiz.general.en' => 'general-knowledge-en.txt',
    'quiz.general.ru' => 'obshchie-znaniya-ru.txt',
    'quiz.wikidata.pl' => 'wiedza-ogolna-pl.txt',
    'quiz.witcher.pl' => 'wiedzmin-pelny-pl.txt',
    'quiz.witcher.g.pl' => 'wiedzmin-gry-pl.txt',
    'quiz.witcher.b.pl' => 'wiedzmin-ksiazki-i-ekranizacje-pl.txt'
  }.freeze
  module_function

  def answers(question)
    values = [question.fetch('correct'), *question.fetch('wrong')]
    raise ArgumentError, 'Expected four distinct answers' unless values.size == 4 && values.uniq.size == 4
    # Stable shuffled positions; no dependence on the application's RNG or a
    # changing export timestamp. Internal IDs are never printed in the TXT.
    values.sort_by { |answer| Digest::SHA256.hexdigest(question.fetch('id') + "\0" + answer) }
  end

  def render(pack)
    heading = if pack.language_id.start_with?('en')
      'Correct answer'
    elsif pack.language_id.start_with?('ru')
      'Правильный ответ'
    else
      'Poprawna odpowiedź'
    end
    lines = [pack.title, '']
    pack.data.fetch('questions').each do |question|
      values = answers(question)
      lines << question.fetch('prompt')
      values.each_with_index { |answer, index| lines << "#{('A'.ord + index).chr}. #{answer}" }
      index = values.index(question.fetch('correct'))
      lines << "#{heading}: #{('A'.ord + index).chr}. #{question.fetch('correct')}"
      lines << ''
    end
    lines.join("\n") + "\n"
  end

  def files
    GameRoomContent.registry.packs.select { |pack| pack.kind.to_s == 'quiz' }.to_h do |pack|
      [NAMES.fetch(pack.id) { pack.id.gsub(/[^a-zA-Z0-9_-]/, '-') + '.txt' }, render(pack)]
    end
  end

  def export(check: false, directory: DIRECTORY)
    content = files
    stale = content.keys.select do |name|
      path = File.join(directory, name)
      !File.file?(path) || File.binread(path) != content.fetch(name).b
    end
    extra = Dir[File.join(directory, '*.txt')].map { |path| File.basename(path) } - content.keys
    raise "Unexpected old export files: #{extra.join(', ')}" unless extra.empty?
    if check
      raise "Out-of-date quiz lists: #{stale.join(', ')}; run ruby tools/export-quiz-text.rb" unless stale.empty?
    else
      FileUtils.mkdir_p(directory)
      stale.each { |name| File.write(File.join(directory, name), content.fetch(name), encoding: 'UTF-8', mode: 'wb') }
    end
    content.keys
  end
end

if $PROGRAM_NAME == __FILE__
  raise ArgumentError, 'Usage: ruby tools/export-quiz-text.rb [--check]' unless (ARGV - ['--check']).empty?
  puts "Quiz review lists: #{QuizTextExport.export(check: ARGV.include?('--check')).size} files"
end
