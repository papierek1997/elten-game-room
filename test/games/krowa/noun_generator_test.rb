require_relative '../../support/assertions'
require_relative '../../../tools/generate-krowa-nouns'
include GameRoomTest::Assertions

result = GameRoomNounGenerator.run(check: true)
assert_equal(85_069, result[:entries])
retired = File.read(File.join(GameRoomNounGenerator::ROOT, 'tools/data/krowa_retired_nouns.txt'), encoding: 'UTF-8')
assert_equal(90, retired.lines.length)
assert_raises(RuntimeError) { GameRoomNounGenerator.render("kot\n", retired: "kot\n") }
assert_raises(RuntimeError) { GameRoomNounGenerator.render("kot\n", retired: "pies\npies\n") }
source = File.read(File.join(GameRoomNounGenerator::ROOT, 'tools/data/krowa_nouns.txt'), encoding: 'UTF-8')
lines = source.lines
additions = %w[łam zacios zaciosy prosię silnia silnie afro szmat ksero
  szamanka szamanki sokownik sokowniki geomanta geomantka geomanci geomantki
  mop mopy bus busy pub puby tarta tarty świrus świrusy świruska świruski
  token tokeny geomancje geomancja
  nekromanta nekromanci nekromantka nekromantki nekromancja nekromancje
  ranking rankingi odsłona odsłony billing billingi kasting kastingi
  halling hallingi hosting hostingi leasing leasingi lifting liftingi
  ścierak ścieraki roaming roamingi szpring szpringi pluszak pluszaki oscypek oscypki]
new_additions = %w[wyjec wyjce oktagon oktagony pentagon pentagony żyrantka żyrantki
  logistyk logistycy meleks meleksy biorytm biorytmy pozorant pozoranci
  pozorantka pozorantki pangram pangramy kebab kebaby balik baliki kamerka
  kamerki guru abnegatka abnegatki karpatka karpatki makiełka makiełki
  woliera woliery frykas okruch kampus kampusy guziec guźce baniak baniaki
  miruna miruny wątpia marker markery burger burgery granola granole
  spalarnia spalarnie rolkarz rolkarze rolkarka rolkarki polar polary koran
  tora lokum login prompter promptery neutrino neutrina]
assert_equal(68, new_additions.length)
next_additions = %w[limonka limonki elfka elfowie elfki krasnolud krasnoludka krasnoludowie ork orkowie goblin goblinka gobliny goblinki ogr ogrzyca ogry ogrzyce gnomka gnomki niziołek niziołka niziołkowie niziołki satyrowie faunowie wampirzyca wampirzyce żywiołak żywiołaki golem golemy smoczyca smoczyce wiwerna wiwerny piksel piksele klastry parser parsery interpreter interpretery emulator emulatory interfejs interfejsy repozytorium repozytoria hiperłącze hiperłącza aplet aplety widżet widżety enkoder enkodery iterator iteratory rekurencja rekurencje permutacja permutacje kwantyl kwantyle wariancja wariancje fraktal fraktale mikroprocesor regulator regulatory transponder transpondery przekaźnik przekaźniki siłownik siłowniki tomograf tomografy hadron hadrony nukleotyd nukleotydy piroliza pirolizy grafen grafeny synapsa synapsy rybosom rybosomy lizosom lizosomy peroksysom peroksysomy mitochondrium chromatyda chromatydy polipeptyd polipeptydy genom genomy allel allele patogen patogeny mikrobiom mikrobiomy symbiont symbionty supernowa supernowe spektrogram spektrogramy tomogram tomogramy]
assert_equal(117, next_additions.length)
latest_additions = %w[alias aliasy podolog podolodzy podolożka podolożki wibrys wibrysy kodek kodeki polik poliki]
current_additions = %w[tonik włam włamy funk kuluar schód zmywarka zmywarki bankomat bankomaty baner banery kofta kofty]
removed = %w[quadrivium quadrivia quantum quanta quarto quattrocento quattrocenta quebracho quebracha
  quiz quizy quorum requiem roquefort calvados calvadosy calypso chevrolet chevrolety collectivum
  collectiva collie colt colty concertino concertina confetti conradysta conradyści continuum continua
  corrida corridy corso corsa cosecans cosecansy cosinus cosinusy cosinusoida cosinusoidy cotangens
  cotangensy cotangensoida cotangensoidy coupú cowboy cowboye cracoviana crawl crawle credo diuszesa
  diuszesy divertimento divertimenta hiszpański hiszpańskie hiszpańszczyzna hiszpańszczyzny hitlerowiec
  hitlerowcy hitleryzm hitleryzmy hiv hiw hiwy hizop hizopy novum recitativo recto stradivarius
  stradivariusy vacat vacaty vademecum varia variútús varsaviana varsavianista varsavianiści
  varsavianistka varsavianistki vedetta vedetty vendetta vendetty veto veta vis visy volksdeutsch
  volksdeutsche volkswagen volkswageny volley volleye volt volty volta volvo vol exodus exodusy
  exposú expres expresy sollux solluksy taxi fractocumulus fractocumulusy fractostratus fractostratusy]
words = lines.map(&:chomp)
followup_additions = %w[kilt kilty ploter plotery skaner skanery toner tonery ociekacz ociekacze]
contributions = new_additions + next_additions + latest_additions + current_additions + followup_additions
assert_equal(contributions, words.last(contributions.length))
assert_equal(words.uniq, words)
(additions + contributions).each { |word| assert_equal(1, words.count(word)) }
(removed + %w[cytacik cytaciki owocek owocki]).each { |word| assert_equal(0, words.count(word)) }
assert(words.all? { |word| word.match?(/\A[[:alpha:]]+\z/u) }, 'Dictionary contains non-word fields')
assert_equal(GameRoomNounGenerator.render("word\nwords\n"), GameRoomNounGenerator.render("word\nwords\n"))
assert_raises(RuntimeError) { GameRoomNounGenerator.render("KROWA_NOUNS\n") }
[" KROWA_NOUNS\n", "\tKROWA_NOUNS\n", " \t\n"].each do |text|
  assert_raises(RuntimeError) { GameRoomNounGenerator.render(text) }
end

puts 'PASS Krowa requested nouns, removals, clean dictionary format, stable generation and heredoc validation'
