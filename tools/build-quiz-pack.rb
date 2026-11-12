require "digest"
require "json"
require "optparse"
require_relative "support/quiz_input"
require_relative "support/quiz_pack_writer"

options = {
  language: "pl-PL",
  license: "CC0-1.0",
  version: 1,
  author: "ELTEN Game Room"
}

OptionParser.new do |parser|
  parser.on("--json PATH") { |value| options[:json] = value }
  parser.on("--out PATH") { |value| options[:out] = value }
  parser.on("--set-id ID") { |value| options[:set_id] = value }
  parser.on("--pack-id ID") { |value| options[:pack_id] = value }
  parser.on("--title TITLE") { |value| options[:title] = value }
  parser.on("--language ID") { |value| options[:language] = value }
  parser.on("--license NAME") { |value| options[:license] = value }
  parser.on("--source TEXT") { |value| options[:source] = value }
  parser.on("--author NAME") { |value| options[:author] = value }
  parser.on("--version NUMBER") { |value| options[:version] = value.to_i }
  parser.on("--translated") { options[:translated] = true }
end.parse!

%i[json out set_id pack_id title].each do |key|
  abort "missing --#{key.to_s.tr('_', '-')}" if options[key].to_s.empty?
end

raw = JSON.parse(File.read(options[:json], encoding: "utf-8"))
questions = raw.is_a?(Array) ? raw : (raw["questions"] || raw["pytania"])
abort "the JSON file contains no questions" if !questions.is_a?(Array) || questions.empty?

LEVELS = %w[easy medium hard].freeze

seen_ids = {}
problems = []
prepared = questions.each_with_index.map do |question, index|
  category = QuizInput.text(question["category"])
  level = question["level"].to_s.strip
  prompt = QuizInput.text(question["prompt"])
  correct = QuizInput.text(question["correct"])
  wrong = Array(question["wrong"]).map { |value| QuizInput.text(value) }.reject(&:empty?)
  issue = QuizInput.problem({ "prompt" => prompt, "correct" => correct, "wrong" => wrong })
  problems << "question #{index + 1}: #{issue}" if issue

  problems << "question #{index + 1} has no category" if category.empty?
  problems << "question #{index + 1} has no prompt" if prompt.empty?
  problems << "question #{index + 1} has no correct answer" if correct.empty?
  problems << "question #{index + 1} (#{prompt}) has #{wrong.length} wrong answers instead of 3" if wrong.length != 3
  problems << "question #{index + 1} (#{prompt}) has an unknown level #{level.inspect}" if !LEVELS.include?(level)
  all = ([correct] + wrong).map(&:downcase)
  problems << "question #{index + 1} (#{prompt}) repeats an answer" if all.uniq.length != all.length

  id = Digest::SHA256.hexdigest("#{options[:set_id]}|#{category}|#{prompt}")[0, 12]
  problems << "question #{index + 1} (#{prompt}) duplicates #{seen_ids[id]}" if seen_ids.key?(id)
  seen_ids[id] = prompt

  {
    id: id,
    category: category,
    level: level,
    prompt: prompt,
    correct: correct,
    wrong: wrong,
    source: question["source"] || options[:source]
  }
end

if !problems.empty?
  warn "the pack was not written, #{problems.length} problem(s) found:"
  problems.first(30).each { |problem| warn "  #{problem}" }
  exit 1
end

prepared.sort_by! { |question| [question[:category], LEVELS.index(question[:level]), question[:prompt]] }

QuizPackWriter.write(options[:out], {
  id: options[:pack_id], set_id: options[:set_id], kind: :quiz,
  language_id: options[:language], version: options[:version], title: options[:title],
  game_ids: ["quiz"], author: options[:author], license: options[:license]
}, prepared, source: options[:source], translated: options[:translated])

counts = prepared.group_by { |question| question[:category] }.transform_values(&:length)
levels = prepared.group_by { |question| question[:level] }.transform_values(&:length)
puts "wrote #{options[:out]}: #{prepared.length} questions"
puts "  categories: #{counts.sort.map { |name, count| "#{name}=#{count}" }.join(', ')}"
puts "  levels: #{LEVELS.map { |name| "#{name}=#{levels[name] || 0}" }.join(', ')}"
