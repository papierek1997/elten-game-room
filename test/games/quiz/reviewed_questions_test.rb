# encoding: UTF-8
require 'json'
require 'digest'
require_relative "../../../content/languages"
require_relative "../../../content/quiz_pl_wikidata"
require_relative "../../../content/quiz_witcher_pl"
def assert(value, message); raise message unless value; end
reference = JSON.parse(File.read(File.expand_path('../../fixtures/quiz/questions.json', __dir__), encoding: 'UTF-8'))
pack_ids = %w[quiz.wikidata.pl quiz.witcher.books.pl]
data = pack_ids.to_h do |id|
  expected = reference.fetch('packs').fetch(id)
  pack = GameRoomContent.registry.pack(id)
  questions = pack.data.fetch('questions')
  ids = questions.map { |question| question.fetch('id') }
  assert(pack.version == expected.fetch('version') && pack.verified?, "#{id}: version/checksum")
  assert(ids.length == expected.fetch('count') && ids.uniq == ids, "#{id}: count/duplicate IDs")
  [id, questions.to_h { |question| [question.fetch('id'), question] }]
end
general = data.fetch('quiz.wikidata.pl')
assert(general.values.none? { |question| question['review_required'] }, 'Unresolved editorial notes entered the released set')
# Confirmed key mistakes must not return; the actual wording is preserved.
{
  'polqa_00547' => ['Ile wież stoi na szachownicy na początku partii?', '4'],
  'polqa_01101' => ['Jak nazywa się równoległobok, którego długości wszystkich boków są równe?', 'romb'],
  'polqa_01779' => ['Na jakim instrumencie gra fletnista?', 'na fletni']
}.each do |id, (prompt, answer)|
  question = general.fetch(id)
  assert(question.fetch('prompt') == prompt && question.fetch('correct') == answer, "#{id}: approved PolQA decision changed")
end
%w[polqa_00012 polqa_00233].each do |id|
  assert(!general.key?(id), "#{id}: a faulty premise requiring a rewritten prompt returned")
end
# Reviewed source decisions: preserve wording except for approved minimal
# choice-list edits, corrected keys, distinct distractors and the Polsat negation.
reviewed_general = {
  # Zuzler's 2026-10-31 report: the question must work without a musical clip.
  '1z10_127f900846145478' => {
    'prompt' => 'W której operze Jacques’a Offenbacha można usłyszeć słynną barkarolę?',
    'correct' => 'W Opowieściach Hoffmanna',
    'wrong' => ['W Carmen', 'W Fauście', 'W Traviacie']
  },
  # Reports reviewed on 2026-10-28: explicit dates, precise definitions,
  # matching grammar and correctly written book titles. The second carat
  # question is excluded by the pinned fixture; retain the stronger wording.
  '1z10_1da2080e7bccf707' => {
    'prompt' => 'Kto napisał „Folwark zwierzęcy” i „Rok 1984”?',
    'correct' => 'George Orwell',
    'wrong' => ['Aldous Huxley', 'Ray Bradbury', 'Herbert George Wells']
  },
  '1z10_a4eeb972b17be78e' => {
    'prompt' => 'Na czym polega noc polarna?',
    'correct' => 'Słońce nie wschodzi przez co najmniej 24 godziny',
    'wrong' => ['Słońce nie zachodzi przez co najmniej 24 godziny',
      'Księżyc pozostaje widoczny przez całą dobę', 'Słońce zachodzi tylko na kilka minut każdej doby']
  },
  '1z10_71913973088a420e' => {
    'prompt' => 'Kto wygrał wybory prezydenckie we Francji w 2017 roku?',
    'correct' => 'Emmanuel Macron',
    'wrong' => ['François Hollande', 'Nicolas Sarkozy', 'Édouard Philippe']
  },
  '1z10_5a7501fff49cd44e' => {
    'prompt' => 'Kim był święty Mateusz Ewangelista, zanim został apostołem?',
    'correct' => 'Celnikiem', 'wrong' => ['Rybakiem', 'Cieślą', 'Lekarzem']
  },
  '1z10_375d099dbae7c729' => {
    'prompt' => 'Kto w 2019 roku stanął na czele Komisji Europejskiej?',
    'correct' => 'Ursula von der Leyen',
    'wrong' => ['Christine Lagarde', 'Roberta Metsola', 'Kaja Kallas']
  },
  'polqa_06007' => {
    'prompt' => 'Jaka jest maksymalna liczba wypukłych punktów w jednym znaku tradycyjnego pisma Braille’a?',
    'correct' => '6', 'wrong' => ['4', '5', '7']
  },
  'polqa_03286' => {
    'prompt' => 'Jak nazywa się jednostka masy używana w obrocie kamieniami szlachetnymi?',
    'correct' => 'karat', 'wrong' => ['uncja', 'gran', 'funt']
  },
  # Reports from Zuzler and Paulinux: grammar, a giveaway qualifier and a
  # subtraction sign that may be silent when punctuation speech is disabled.
  'polqa_01372' => {
    'prompt' => 'Jaką dziedzinę sztuki uprawiał Gerard Wilk?',
    'correct' => 'taniec', 'wrong' => ['rzeźbę', 'malarstwo', 'śpiew']
  },
  'polqa_02589' => {
    'prompt' => 'Ile to jest 45 minus 15?',
    'correct' => '30', 'wrong' => ['20', '25', '35']
  },
  'polqa_03507' => {
    'prompt' => 'Jak nazywają się boczne pasy na mundurowych spodniach?',
    'correct' => 'lampasy', 'wrong' => ['epolety', 'galony', 'szamerunki']
  },
  'community_b96_20261023_01' => {
    'category' => 'Kultura', 'author' => 'bratczyk96',
    'prompt' => 'Który teleturniej prowadził Hubert Urbański w Polsacie, zanim został gospodarzem „Milionerów”?',
    'correct' => 'Piramida', 'wrong' => ['Rekiny kart', '100% dla stu', 'Magia liter']
  },
  'community_b96_20261023_02' => {
    'category' => 'Język', 'author' => 'bratczyk96',
    'prompt' => 'Z którym regionem Polski kojarzy się używanie formy „daj dla mnie” zamiast „daj mi”?',
    'correct' => 'Z Podlasiem', 'wrong' => ['Ze Śląskiem', 'Z Podkarpaciem', 'Z Małopolską']
  },
  'community_b96_20261023_03' => {
    'category' => 'Literatura', 'author' => 'bratczyk96',
    'prompt' => 'Kto napisał wiersz „Maja maleńkaja ajczyna”, opowiadający o rodzinnej Białostocczyźnie?',
    'correct' => 'Wiktor Szwed', 'wrong' => ['Mira Łuksza', 'Barbara Goralczuk', 'Janka Kupała']
  },
  'community_b96_20261023_04' => {
    'category' => 'Życie codzienne', 'author' => 'bratczyk96',
    'prompt' => 'Jak nazywa się czekolada z wizerunkiem dziewczynki w chustce, produkowana przez rosyjską fabrykę Krasnyj Oktiabr?',
    'correct' => 'Alionka', 'wrong' => ['Babajewski', 'Spartak', 'Komunarka']
  },
  'community_b96_20261023_05' => {
    'category' => 'Język', 'author' => 'bratczyk96',
    'prompt' => 'Kliocki to rosyjska nazwa jakiej potrawy?',
    'correct' => 'Klusek', 'wrong' => ['Ciasta', 'Wędliny', 'Zupy']
  },
  'polqa_00006' => {
    'source_dataset' => 'PolQA', 'category' => 'Geografia',
    'prompt' => 'W którym państwie leży Bombaj?',
    'correct' => 'w Indiach',
    'wrong' => ['w Pakistanie', 'w Bangladeszu', 'w Nepalu']
  },
  '1z10_d29b6adc8a8b1fab' => {
    'source_dataset' => '1z10/MAUPQA', 'category' => 'Historia',
    'prompt' => 'Który polityk najdłużej pełnił funkcję prezydenta Rzeczypospolitej Polskiej?',
    'correct' => 'August Zaleski',
    'wrong' => ['Ignacy Mościcki', 'Aleksander Kwaśniewski', 'Władysław Raczkiewicz']
  },
  '1z10_eda89a6663bc42f1' => {
    'source_dataset' => '1z10/MAUPQA', 'category' => 'Kultura',
    'prompt' => 'Na którym instrumencie muzycznym grał fizyk Albert Einstein?',
    'correct' => 'Na skrzypcach',
    'wrong' => ['Na klarnecie', 'Na trąbce', 'Na flecie']
  },
  # This question must work without the original programme's audio clip.
  '1z10_9c1ef9355dd49ef6' => {
    'source_dataset' => '1z10/MAUPQA', 'category' => 'Kultura',
    'prompt' => 'Który zespół nagrał album „The Wall”?',
    'correct' => 'Pink Floyd',
    'wrong' => ['The Who', 'Genesis', 'Yes']
  },
  '1z10_9853d8cf4752e84f' => {
    'prompt' => 'Jako kto pracuje Aleksandra „Sasza” Załuska, bohaterka cyklu powieści Katarzyny Bondy?',
    'correct' => 'Jako profilerka',
    'wrong' => ['Jako prokuratorka', 'Jako dziennikarka', 'Jako adwokatka']
  },
  'community_tc_20261021_01' => {
    'source_dataset' => 'Power Games community', 'category' => 'Nauka', 'author' => 'turekcom',
    'prompt' => 'Od nazwiska którego fizyka pochodzi nazwa promieniowania, przez które czarna dziura może tracić masę?',
    'correct' => 'Stephena Hawkinga',
    'wrong' => ['Maxa Plancka', 'Erwina Schrödingera', 'Freemana Dysona']
  },
  '1z10_dad26f6ca36159da' => {
    'source_dataset' => '1z10/MAUPQA', 'category' => 'Geografia',
    'prompt' => 'Ile gwiazd widnieje na fladze Panamy?',
    'correct' => 'Dwie',
    'wrong' => ['Jedna', 'Więcej niż dwie', 'Żadna']
  },
  # Player reports reviewed on 2026-10-16: two wording fixes, one correct key.
  '1z10_66fe39b19778f94e' => {
    'prompt' => 'Która z tych rzeczy nie nadaje się do jedzenia?',
    'correct' => 'Tablet', 'wrong' => ['Suflet', 'Omlet', 'Kotlet']
  },
  '1z10_c081732881fc3741' => {
    'prompt' => 'Na który miesiąc przypada maksimum aktywności roju Geminidów?',
    'correct' => 'Na grudzień', 'wrong' => ['Na sierpień', 'Na październik', 'Na listopad']
  },
  '1z10_313528395bdfcd68' => {
    'prompt' => 'Jak miał na imię ksiądz Jandołowicz, jeden z przywódców konfederacji barskiej, tytułowy bohater dramatu Słowackiego?',
    'correct' => 'Marek', 'wrong' => ['Piotr', 'Józef', 'Jan']
  },
  # Further player reports: past tense, a missing question, a clue and a typo.
  'polqa_01133' => {
    'prompt' => 'Z którego państwa pochodził papież Franciszek?',
    'correct' => 'z Argentyny', 'wrong' => ['z Brazylii', 'z Chile', 'z Urugwaju']
  },
  '1z10_47bcb3b74ed92e61' => {
    'prompt' => 'Jak nazywał się pakt zawarty przez Niemcy, Włochy i Japonię w 1940 roku?',
    'correct' => 'Pakt trzech', 'wrong' => ['Pakt stalowy', 'Pakt antykominternowski', 'Pakt czterech']
  },
  '1z10_569a7a907e4db13e' => {
    'prompt' => 'Jak nazywa się dokument uchwalony w 1964 roku, określający podstawowe zasady ochrony i konserwacji zabytków architektury?',
    'correct' => 'Karta Wenecka', 'wrong' => ['Karta Ateńska', 'Karta Florencka', 'Karta Waszyngtońska']
  },
  'polqa_02012' => {
    'prompt' => 'Jak nazywa się rzemieślnik zajmujący się naprawą i pokrywaniem dachów?',
    'correct' => 'dekarz', 'wrong' => ['cieśla', 'zdun', 'murarz']
  },
  'milionerzy_c894a05703b826b0' => {
    'source_dataset' => 'Milionerzy/Polsat', 'category' => 'Geografia',
    'prompt' => 'Nie można powiedzieć o Morzu Martwym, że jest:',
    'correct' => 'częścią Morza Czerwonego',
    'wrong' => ['mocno zasolone', 'położone w depresji', 'wydłużone południkowo']
  }
}
reviewed_general.each do |id, expected|
  question = general.fetch(id)
  expected.each { |field, value| assert(question.fetch(field) == value, "#{id}: reviewed #{field} changed") }
end
roman_century = /(?<![[:alpha:]])[IVXL]+(?:\.|-|\s+(?:i|do|–)\s+[IVXL]+)*\s*(?:-?wieczn|wiek|w\.|stuleci)/
general.each do |id, question|
  [question.fetch('prompt'), question.fetch('correct'), *question.fetch('wrong')].each do |text|
    assert(!text.match?(roman_century), "#{id}: century written in Roman numerals")
  end
end
{
  'polqa_00368' => ['W którym wieku panował Henryk VIII?', 'w 16. wieku'],
  'polqa_06837' => ['Na przełomie których wieków komponował Niemiec Ryszard Strauss?', '19. i 20.'],
  'polqa_02428' => ['W którym wieku Rzymianie ostatecznie zniszczyli Kartaginę?', 'w 2. p.n.e.'],
  'polqa_04406' => ['Jak brzmi nazwisko tancerza polskiego urodzonego w 1944 roku, solisty m.in. baletu Teatru Wielkiego w Warszawie i Baletu XX Wieku?', 'Wilk']
}.each do |id, (prompt, answer)|
  question = general.fetch(id)
  assert(question.fetch('prompt') == prompt && question.fetch('correct') == answer, "#{id}: Arabic century wording changed")
end
books = data.fetch('quiz.witcher.books.pl')
# PR33 adds reviewed questions without rewriting the approved 1,275-question
# collection. This is an editorial baseline, not an engine compatibility rule.
assert(Digest::SHA256.hexdigest(JSON.generate(books.values.first(1275))) ==
  '1dea687b13de02096b580e1a17844d804e7ab85cff7ffbcd57842bccf14c70d4', 'Existing Witcher questions changed during the addition')
{
  'c40074bb72b4' => ['Czyje miecze Geralt odbiera od Voronoffa w „Rozdrożu kruków”?', 'Prestona Holta'],
  '0c34230f8d5e' => ['Jak Geralt zabija czarodzieja Sorela Degerlunda w książce „Sezon burz”?', 'Dusi go, łamiąc mu kark'],
  'd1410c85633f' => ['Jak Calanthe chce sprawdzić Geralta, gdy przybywa on po dziecko Pavetty w „Coś więcej”?', 'Każe mu wskazać obiecane dziecko wśród bawiących się dzieci'],
  '5809230663c7' => ['Dlaczego Filippa nie zaprosiła do Loży Istredda ani Carduina?', 'Bo dopuszcza do niej wyłącznie kobiety'],
  '7907afa1bc1f' => ['Który wiedźmin spędza w Kaer Morhen swoją pierwszą zimę w „Krwi elfów”?', 'Coen'],
  '2bd126d2a1d7' => ['Komu według relacji Jaskra formalnie przypadają rządy w Redanii po śmierci Vizimira?', 'Królowej Hedwig']
}.each do |id, (prompt, answer)|
  question = books.fetch(id)
  assert(question.fetch('prompt') == prompt && question.fetch('correct') == answer, "#{id}: reviewed literary fact changed")
end
assert(books.fetch('89469160efbf').fetch('prompt').include?('hybrydy ogrów i trolli'), 'Degerlund helpers became demons again')
assert(!books.fetch('de4f553014d2').fetch('wrong').include?('Borch Trzy Kawki'), 'Two names of the same dragon returned as distinct answers')
puts 'Reviewed quiz questions: fixture counts/versions, Arabic centuries and Polish literary source decisions: OK'
