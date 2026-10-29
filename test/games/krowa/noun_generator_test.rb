require_relative '../../support/assertions'
require_relative '../../../tools/generate-krowa-nouns'
include GameRoomTest::Assertions

result = GameRoomNounGenerator.run(check: true)
assert_equal(85_135, result[:entries])
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
assert_equal(new_additions, lines.map(&:chomp).slice(84_938,68))
next_additions = %w[limonka limonki elfka elfowie elfki krasnolud krasnoludka krasnoludowie ork orkowie goblin goblinka gobliny goblinki ogr ogrzyca ogry ogrzyce gnomka gnomki niziołek niziołka niziołkowie niziołki satyrowie faunowie wampirzyca wampirzyce żywiołak żywiołaki golem golemy smoczyca smoczyce wiwerna wiwerny piksel piksele klastry parser parsery interpreter interpretery emulator emulatory interfejs interfejsy repozytorium repozytoria hiperłącze hiperłącza aplet aplety widżet widżety enkoder enkodery iterator iteratory rekurencja rekurencje permutacja permutacje kwantyl kwantyle wariancja wariancje fraktal fraktale mikroprocesor regulator regulatory transponder transpondery przekaźnik przekaźniki siłownik siłowniki tomograf tomografy hadron hadrony nukleotyd nukleotydy piroliza pirolizy grafen grafeny synapsa synapsy rybosom rybosomy lizosom lizosomy peroksysom peroksysomy mitochondrium chromatyda chromatydy polipeptyd polipeptydy genom genomy allel allele patogen patogeny mikrobiom mikrobiomy symbiont symbionty supernowa supernowe spektrogram spektrogramy tomogram tomogramy]
assert_equal(117, next_additions.length)
assert_equal(next_additions, lines.map(&:chomp).slice(85_006,117))
latest_additions = %w[alias aliasy podolog podolodzy podolożka podolożki wibrys wibrysy kodek kodeki polik poliki]
assert_equal(latest_additions, lines.last(12).map(&:chomp))
words = lines.map(&:chomp)
assert_equal(words.uniq, words)
(additions + new_additions + next_additions + latest_additions).each { |word| assert_equal(1, words.count(word)) }
%w[cytacik cytaciki owocek owocki].each { |word| assert_equal(0, words.count(word)) }
assert_equal(GameRoomNounGenerator.render("word\nwords\n"), GameRoomNounGenerator.render("word\nwords\n"))
assert_raises(RuntimeError) { GameRoomNounGenerator.render("KROWA_NOUNS\n") }
[" KROWA_NOUNS\n", "\tKROWA_NOUNS\n", " \t\n"].each do |text|
  assert_raises(RuntimeError) { GameRoomNounGenerator.render(text) }
end

puts 'PASS Krowa noun source provenance, stable generation and heredoc validation'
