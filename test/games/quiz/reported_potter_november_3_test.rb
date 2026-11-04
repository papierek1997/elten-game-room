# encoding: UTF-8
require_relative '../../../content/languages'
require_relative '../../../content/quiz_harry_potter_pl'

def assert(value, message)
  raise message unless value
end

pack = GameRoomContent.registry.pack('quiz.harry_potter.books.pl')
questions = pack.data.fetch('questions')
indexed = questions.to_h { |question| [question.fetch('id'), question] }
expected = {
  'community_hp_lk_0095' => [
    'Kogo Harry i Ron udawali za pomocą Eliksiru Wielosokowego w „Komnacie Tajemnic”?',
    'Crabbe’a i Goyle’a', 'J.K. Rowling: Harry Potter i Komnata Tajemnic'
  ],
  'community_hp_lk_0471' => [
    'Jak Neville wrócił do pokoju wspólnego, gdy Malfoy rzucił na niego urok w „Kamieniu Filozoficznym”?',
    'Skacząc ze sklejonymi nogami', 'J.K. Rowling: Harry Potter i Kamień Filozoficzny'
  ],
  'community_hp_lk_0621' => [
    'Kto zginął po podsłuchaniu rozmowy Voldemorta w domu Riddle’ów na początku „Czary Ognia”?',
    'Frank Bryce', 'J.K. Rowling: Harry Potter i Czara Ognia'
  ],
  'community_hp_lk_0708' => [
    'W „Zakonie Feniksa” Harry szuka Syriusza przez kominek Umbridge. Kto kłamie mu, że Syriusza nie ma w domu?',
    'Stworek', 'J.K. Rowling: Harry Potter i Zakon Feniksa'
  ]
}
expected.each do |id, (prompt, correct, source)|
  question = indexed.fetch(id)
  assert(question.fetch('prompt') == prompt, "Missing standalone context or restored answer clue: #{id}")
  assert(question.fetch('correct') == correct, "The report changed the verified correct answer: #{id}")
  assert(question.fetch('source') == source, "Incorrect source novel: #{id}")
end
assert(indexed.fetch('community_hp_lk_0471').fetch('wrong') == [
  'Pełzając', 'Podtrzymywany przez Harry’ego i Rona', 'Na plecach jednego z uczniów'
], 'Implausible broom/Hagrid distractors returned')
assert(questions.length == 985, 'Wording-only reports added or removed questions')
assert(pack.version == 2, 'Edited questions were published without a new data version')
puts 'PASS four Potter reports: standalone context, no occupation/house clues, plausible return methods and correct source novels'
