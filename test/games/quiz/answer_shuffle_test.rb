require_relative '../../support/ui'
require_relative '../../../games/quiz_party'

game = GameRoomGames::QuizParty.new
options = game.normalize_options('content_set_id'=>'quiz.wikidata', 'content_language_id'=>'pl-PL')
state = game.send(:initial_state, %w[Alice Bob], options)
question = game.send(:pack_questions, options).first
# Hold the drawn question fixed: changing questions must not hide a biased
# answer shuffle or a correlation with the question-selection RNG.
game.define_singleton_method(:drawable_questions) { |_state| [question] }
original = [question.fetch('correct'), *question.fetch('wrong')]
counts = [0, 0, 0, 0]
position_counts = Array.new(3) { [0, 0, 0, 0] }
orders = Hash.new(0)
triples = Hash.new(0)
current_triple = []
24_000.times do |index|
  round, position = index / 3 + 1, index % 3 + 1
  before = state.merge(round:round, position:position - 1)
  seed = index.to_s(16).rjust(32, '0')
  event = {'action'=>'question', 'value'=>"#{round},#{position},q:#{seed}"}
  parsed = game.send(:parse_seeded_question, before, event)
  raise 'Current question seed format was refused' unless parsed
  shown_state = before.merge(question_id:parsed.fetch(:question_id), position:position,
    answer_order_seed:parsed.fetch(:answer_order_seed))
  shown = game.send(:shuffled_options, shown_state)
  raise 'Shuffle dropped, duplicated or changed an answer' unless shown.sort == original.sort
  raise 'Shuffle changes during refresh' unless shown == game.send(:shuffled_options, shown_state)
  correct = game.send(:correct_option_index, shown_state)
  raise 'Displayed answers and scoring disagree' unless shown.fetch(correct) == question.fetch('correct')
  counts[correct] += 1
  position_counts[position - 1][correct] += 1
  orders[shown.map { |answer| original.index(answer) }] += 1
  current_triple << correct
  if position == 3
    triples[current_triple] += 1
    current_triple = []
  end
end
raise "Biased correct-answer positions: #{counts.inspect}" unless counts.all? { |n| n.between?(5_520, 6_480) }
raise "Bias within a round position: #{position_counts.inspect}" unless position_counts.flatten.all? { |n| n.between?(1_760, 2_240) }
raise "Only #{orders.size} of 24 permutations reachable" unless orders.size == 24
raise 'Legitimate repeated answer positions were suppressed' unless triples.size == 64

# Identical ID/round/position in distinct draws must not force the same order.
fixed = state.merge(round:1, position:0)
distinct = 128.times.map do |seed|
  event = {'action'=>'question', 'value'=>"1,1,q:#{seed.to_s(16).rjust(32, '0')}"}
  parsed = game.send(:parse_seeded_question, fixed, event)
  game.send(:shuffled_options, fixed.merge(question_id:parsed.fetch(:question_id), position:1,
    answer_order_seed:parsed.fetch(:answer_order_seed)))
end.uniq
raise 'Answer order ignores fresh server entropy' unless distinct.size > 20

puts "PASS Quiz answer shuffle: #{counts.inspect}, all 24 permutations and 64 triples; stable refresh, fresh entropy, display/scoring agreement"
