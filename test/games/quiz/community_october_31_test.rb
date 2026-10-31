# encoding: UTF-8
require_relative '../../../content/languages'
require_relative '../../../content/quiz_pl_wikidata'

def assert(value, message); raise message unless value; end

questions = GameRoomContent.registry.pack('quiz.wikidata.pl').data.fetch('questions')
indexed = questions.to_h { |q| [q.fetch('id'), q] }
# Approved content from two Zuzler submissions. Four semantic duplicates were
# rejected; the two questions about cat breeds were combined into one item.
# These literal expectations are separate from the editorial import script.
expected = [
  ['Historia', 'Jak nazywały się protesty na Ukrainie, które rozpoczęły się po wyborach prezydenckich w listopadzie 2004 roku?',
    'Pomarańczowa rewolucja', ['Jaśminowa rewolucja', 'Aksamitna rewolucja', 'Rewolucja róż']],
  ['Geografia', 'Jakie wyroby są szczególnie kojarzone z Bolesławcem na Dolnym Śląsku?',
    'Naczynia ceramiczne', ['Wyroby z bursztynu', 'Wyroby ze szkła kryształowego', 'Koronki']],
  ['Język', 'Kogo w gwarze poznańskiej nazywa się „szkiełami”?',
    'Policjantów', ['Kolejarzy', 'Kupców', 'Kierowców']],
  ['Życie codzienne', 'W której sieci sklepów można w 2026 roku kupić produkty marki Kraina Wędlin?',
    'W Biedronce', ['W Lidlu', 'W Aldi', 'W Kauflandzie']],
  ['Przyroda', 'Norweski leśny, rosyjski niebieski i turecki van to rasy jakich zwierząt?',
    'Kotów', ['Psów', 'Królików', 'Koni']],
  ['Geografia', 'Które z tych miast nie jest w 2026 roku stolicą województwa?',
    'Częstochowa', ['Katowice', 'Kielce', 'Kraków']],
  ['Przyroda', 'Z której części świata pochodzi fasola zwyczajna?',
    'Z Ameryki', ['Z Azji', 'Z Afryki', 'Z Europy']],
  ['Religia', 'W którym miesiącu przypada wspomnienie św. Floriana, patrona strażaków?',
    'W maju', ['W czerwcu', 'W październiku', 'W listopadzie']],
  ['Religia', 'Kiedy obchodzimy święto Matki Bożej Gromnicznej?',
    '2 lutego', ['15 sierpnia', '13 maja', '8 grudnia']],
  ['Język', 'Jakiego pochodzenia jest imię Hanna?',
    'Hebrajskiego', ['Germańskiego', 'Greckiego', 'Łacińskiego']],
  ['Język', 'Z jakiego języka pochodzi imię Marcin?',
    'Z łaciny', ['Z greki', 'Z hebrajskiego', 'Z niemieckiego']],
  ['Język', 'Który z tych języków zapisuje się standardowo alfabetem łacińskim?',
    'Słoweński', ['Rosyjski', 'Bułgarski', 'Białoruski']],
  ['Język', 'Który z tych języków należy do grupy wschodniosłowiańskiej?',
    'Łemkowski', ['Dolnołużycki', 'Kaszubski', 'Czeski']],
  ['Język', 'Gdzie farerski jest językiem urzędowym?',
    'Na Wyspach Owczych', ['Na Grenlandii', 'Na Islandii', 'Na Wyspach Alandzkich']],
  ['Język', 'Do której grupy języków należy kaszubski?',
    'Do słowiańskich', ['Do germańskich', 'Do romańskich', 'Do ugrofińskich']],
  ['Historia', 'Na terenie którego dzisiejszego państwa mieszkali Słowińcy?',
    'Polski', ['Słowacji', 'Słowenii', 'Ukrainy']],
  ['Przyroda', 'Czym jest eustoma?',
    'Rośliną kwitnącą', ['Grzybem', 'Motylem', 'Ślimakiem']],
  ['Życie codzienne', 'W którym roku po raz pierwszy wyemitowano powieść radiową „W Jezioranach”?',
    '1960', ['1970', '1965', '1955']],
  ['Religia', 'Kiedy w Kościele katolickim przypada wspomnienie świętych Joachima i Anny?',
    '26 lipca', ['26 sierpnia', '25 lipca', '25 sierpnia']],
  ['Religia', 'Czyją patronką jest święta Cecylia?',
    'Muzyków', ['Piekarzy', 'Stolarzy', 'Rolników']],
  ['Religia', 'Która z tych świętych jest patronką osób niewidomych?',
    'Święta Łucja', ['Święta Zuzanna', 'Święta Cecylia', 'Święta Anna']],
  ['Literatura', 'W którym roku Olga Tokarczuk odebrała Literacką Nagrodę Nobla?',
    '2019', ['2020', '2017', '2018']],
  ['Nauka', 'Jakie dwa metale są głównymi składnikami mosiądzu?',
    'Miedź i cynk', ['Miedź i cyna', 'Miedź i nikiel', 'Ołów i cyna']],
  ['Życie codzienne', 'Kiedy w Polsce tradycyjnie obchodzą imieniny Adam i Ewa?',
    '24 grudnia', ['1 września', '24 czerwca', '1 kwietnia']],
  ['Przyroda', 'Z krzyżówki jakich zwierząt rodzi się osłomuł?',
    'Ogiera i oślicy', ['Osła i klaczy', 'Ogiera i samicy zebry', 'Samca zebry i oślicy']],
  ['Życie codzienne', 'Kiedy w Polsce obchodzimy Dzień Mężczyzn?',
    '10 marca', ['9 marca', '30 września', '29 września']],
  ['Życie codzienne', 'W jakiej kolejności obchodzimy w Polsce te święta, licząc od początku roku?',
    'Dzień Babci, Dzień Dziadka, Dzień Kobiet',
    ['Dzień Babci, Dzień Kobiet, Dzień Dziadka', 'Dzień Dziadka, Dzień Babci, Dzień Kobiet', 'Dzień Dziadka, Dzień Kobiet, Dzień Babci']]
]

ids = expected.each_index.map { |i| format('community_zz_20261031_%02d', i + 1) }
actual = questions.select { |q| q.fetch('id').start_with?('community_zz_20261031_') }
assert(actual.map { |q| q.fetch('id') } == ids, 'The reviewed batch must contain exactly the 27 approved items in order')
expected.each_with_index do |content, index|
  id = ids.fetch(index)
  q = indexed.fetch(id)
  assert(q.values_at('category', 'prompt', 'correct', 'wrong') == content, "#{id}: approved wording/choices changed")
  assert(q.fetch('author') == 'Zuzler', "#{id}: contributor missing")
  assert(q.fetch('source_dataset') == 'Power Games community', "#{id}: source misattributed")
  assert(q.fetch('source_license').include?('no separate reuse license specified'), "#{id}: ungranted licence assigned")
  assert(q.fetch('review_required') == false && q.fetch('source').start_with?('https://'), "#{id}: review/source missing")
  assert(questions.count { |other| other.fetch('prompt').downcase == q.fetch('prompt').downcase } == 1, "#{id}: duplicate prompt")
end

# Rejected proposals must not replace the already correct published questions.
assert(indexed.fetch('1z10_c21da80c71d003b2').fetch('correct') == '−273,15°C', 'The erroneous zero-kelvin proposal changed the correct answer')
%w[1z10_86abf169b5582cba polqa_04418 1z10_968560c664016439 1z10_a60bf2dfe69c824b].each do |id|
  assert(indexed.key?(id), "#{id}: an existing item was removed while rejecting a duplicate")
end
puts 'Community quiz 2026-10-31: 27 reviewed additions, complete choices, provenance and retained duplicate originals: OK'
