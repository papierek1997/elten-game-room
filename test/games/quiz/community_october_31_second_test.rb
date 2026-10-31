# encoding: UTF-8
require_relative '../../../content/languages'
require_relative '../../../content/quiz_pl_wikidata'

def assert(value, message); raise message unless value; end

pack = GameRoomContent.registry.pack('quiz.wikidata.pl')
questions = pack.data.fetch('questions')
indexed = questions.to_h { |q| [q.fetch('id'), q] }
prefix = 'community_zz_20261031b_'
prior = questions.take_while { |q| !q.fetch('id').start_with?(prefix) }
baseline = GameRoomContent::Pack.new(id: pack.id, set_id: pack.set_id, kind: pack.kind,
  language_id: pack.language_id, version: 20, title: 'General knowledge', game_ids: pack.game_ids,
  data: pack.data.merge('questions' => prior))
assert(prior.size == 14926 && baseline.checksum ==
  'be7b5c2818ae795663ed4d4193ab10cd044e08c920825db3b911d6303cc4f063',
  'An existing question, answer, category, source or order changed while adding the batch')

# Literal editorial expectations, independent of the private import ledger.
expected = [
  ['Język', 'Czym w gwarze poznańskiej jest „peja”?', 'Wszą', ['Pluskwą', 'Muchą', 'Komarem']],
  ['Język', 'Kogo w gwarze poznańskiej określa się słowem „pener”?', 'Menela', ['Eleganta', 'Skąpca', 'Żarłoka']],
  ['Geografia', 'Przez które z tych miast nie przepływa Warta?', 'Kalisz', ['Sieradz', 'Konin', 'Koło']],
  ['Życie codzienne', 'Jaką literę przypomina krzyż świętego Andrzeja?', 'X', ['T', 'Y', 'H']],
  ['Język', 'Czym są wielkopolskie „ślepe ryby”?', 'Zupą ziemniaczaną', ['Plackami ziemniaczanymi', 'Kluskami z twarogiem', 'Smażonymi śledziami']],
  ['Język', 'Które słowo jest synonimem wyrazu „rżysko”?', 'Ściernisko', ['Rykowisko', 'Pastwisko', 'Kartoflisko']],
  ['Geografia', 'W którym województwie leży Olkusz?', 'W małopolskim', ['W opolskim', 'W śląskim', 'W świętokrzyskim']],
  ['Życie codzienne', 'Z korzeni której rośliny otrzymuje się tapiokę?', 'Manioku', ['Ziemniaka', 'Batata', 'Taro']],
  ['Geografia', 'Do którego państwa należy w 2026 roku terytorium Tristan da Cunha?', 'Do Wielkiej Brytanii', ['Do Portugalii', 'Do Francji', 'Do Republiki Południowej Afryki']],
  ['Geografia', 'Częścią którego państwa jest w 2026 roku Nowa Kaledonia?', 'Francji', ['Australii', 'Wielkiej Brytanii', 'Nowej Zelandii']],
  ['Literatura', 'Która z tych książek nie jest autorstwa Stephena Kinga?', '„W drodze”', ['„Wielki marsz”', '„Bezsenność”', '„To”']],
  ['Literatura', 'Który z tych utworów nie jest autorstwa Aleksandra Fredry?', '„Cud mniemany, czyli Krakowiacy i Górale”', ['„Pan Jowialski”', '„Trzy po trzy”', '„Śluby panieńskie”']],
  ['Literatura', 'Dla której epoki literackiej charakterystyczna jest powieść poetycka?', 'Dla romantyzmu', ['Dla klasycyzmu', 'Dla Młodej Polski', 'Dla dwudziestolecia międzywojennego']],
  ['Przyroda', 'Które zęby nazywamy przedtrzonowymi w stałym uzębieniu człowieka?', 'Czwórki i piątki', ['Jedynki i dwójki', 'Szóstki i siódemki', 'Siódemki i ósemki']],
  ['Geografia', 'Którego państwa częścią jest formalnie Naddniestrze w 2026 roku?', 'Mołdawii', ['Ukrainy', 'Rumunii', 'Rosji']]
]
actual = questions.select { |q| q.fetch('id').start_with?(prefix) }
ids = expected.each_index.map { |i| format('%s%02d', prefix, i + 1) }
assert(actual.map { |q| q.fetch('id') } == ids && indexed.size == questions.size, 'Wrong scope or duplicate IDs')
allowed_categories = prior.map { |q| q.fetch('category') }.uniq
actual.each_with_index do |q, i|
  assert(q.values_at('category', 'prompt', 'correct', 'wrong') == expected.fetch(i), "#{q['id']}: approved wording or answer changed")
  assert(allowed_categories.include?(q['category']), 'Unexpected new category')
  assert(q['author'] == 'Zuzler' && q['source_dataset'] == 'Power Games community', 'Contributor/source attribution changed')
  assert(q['source_license'].include?('no separate reuse license specified') && q['review_required'] == false, 'Licence or review state incorrect')
  assert(q['source'].start_with?('https://'), 'Missing factual reference')
  choices = [q.fetch('correct'), *q.fetch('wrong')]
  assert(choices.size == 4 && choices.map(&:downcase).uniq.size == 4, 'Duplicate choices')
  assert(([q['prompt']] + choices).none? { |s| s.match?(/\p{Cyrillic}/) }, 'Mixed script in Polish text')
  assert(questions.count { |other| other['prompt'].downcase == q['prompt'].downcase } == 1, 'Duplicate prompt')
end
assert(actual.first.fetch('wrong').none? { |word| word.downcase.include?('pchł') }, 'A second valid meaning of peja was made a wrong choice')
assert(indexed.fetch('1z10_6392e2ff7e539013')['correct'].downcase.include?('barbara'), 'Rejected patron-saint duplicate removed the original')
assert(indexed.fetch('polqa_01456')['correct'].downcase == 'siekacze', 'Rejected teeth duplicate removed the original')
puts 'Community quiz 2026-10-31 second batch: 15 reviewed additions, 2 duplicate rejections, entire v20 baseline and provenance preserved: OK'
