# encoding: UTF-8
require_relative "../../../content/languages"
require_relative "../../../content/quiz_general_ru"

def assert(value, message)
  raise message unless value
end

language = GameRoomContent.registry.language('ru-RU')
assert(language != nil, 'Russian language profile is missing')
assert(language.alphabet.include?('ё'), 'Russian alphabet omits ё')

pack = GameRoomContent.registry.pack('quiz.general.ru')
questions = pack.data.fetch('questions')
assert(pack.version == 2 && pack.entry_count == 67 && questions.length == 67 && pack.verified?, 'Russian version, count or checksum is incorrect')
assert(questions.map { |question| question.fetch('id') }.uniq.length == questions.length, 'Russian question IDs are not unique')
assert(questions.map { |question| question.fetch('category') }.uniq.length >= 3, 'Russian set has too few categories for a round draw')

questions.each do |question|
  answers = [question.fetch('correct'), *question.fetch('wrong')]
  assert(answers.length == 4 && answers.uniq.length == 4, "Question #{question.fetch('id')} does not have four distinct answers")
  assert(%w[easy medium hard].include?(question.fetch('level')), "Question #{question.fetch('id')} has an invalid level")
end

text = questions.flat_map do |question|
  [question.fetch('prompt'), question.fetch('correct'), *question.fetch('wrong')]
end.join("\n")

# These words occur in the editorial set and must retain ё. This catches the
# common accidental replacement without pretending that every Russian е is ё.
required_yo_spellings = ['её', 'Пётр', 'Фёдор', 'полёт', 'погребён', 'Освобождённый']
required_yo_spellings.each { |word| assert(text.include?(word), "Russian text lost ё in #{word}") }

forbidden_ye_spellings = ['ее «энергетической', 'Петр I', 'Федор Достоевский', 'полет человека', 'погребен извержением', 'Освобожденный Иерусалим']
forbidden_ye_spellings.each { |word| assert(!text.include?(word), "Russian text uses е instead of ё in #{word}") }

community = questions.select { |question| question.fetch('id').start_with?('monstricek_20261116_') }
accepted = (1..37).to_a - [1, 2, 17, 21, 28, 31]
assert(community.map { |question| question['id'].split('_').last.to_i } == accepted,
  'Russian community review lost an accepted item or restored an excluded one')
assert(community.all? { |question| !question.fetch('source').empty? }, 'Community questions lost their source references')
by_id = questions.to_h { |question| [question.fetch('id'), question] }
spit = by_id.fetch('monstricek_20261116_23')
assert(spit['wrong'].none? { |answer| answer.match?(/Вислинск|Фрише/) }, 'Synonymous Baltic Spit names returned as wrong answers')
assert(by_id.fetch('monstricek_20261116_34')['prompt'].include?('1519'), 'Initial expedition leadership was confused with voyage completion')
assert(by_id.fetch('monstricek_20261116_07')['prompt'].include?('часть руки'), 'The polysemy question is ambiguous again')
assert(pack.license.include?('community') && pack.author.include?('monstricek'), 'Community rights and attribution were lost')

puts 'Russian quiz content: profile, structure, checksum and ё spellings: OK'
