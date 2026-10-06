# Redakcja pytań quizowych

Pytanie ma brzmieć tak, jakby przygotowała je osoba znająca temat i umiejąca
o nim opowiadać. Gracz powinien zastanawiać się nad odpowiedzią, nie nad tym,
co autor miał na myśli. Trzy błędne odpowiedzi są równie ważne jak pytanie
i odpowiedź poprawna: mają sprawdzać wiedzę, a nie zdradzać rozwiązanie.

Te zasady obowiązują przy tworzeniu, importowaniu, rozbudowie, ratowaniu
starych zestawów i tłumaczeniu pytań, niezależnie od języka. Przeczytaj cały
dokument przed rozpoczęciem takiej pracy. Dotyczy on także treści z PR-ów
i gotowych baz. Nie upoważnia do przepisywania istniejących zestawów przy
okazji innych zmian ani do zmieniania tekstów, które użytkownik polecił
zachować. Szczegółowe polecenia użytkownika mają pierwszeństwo.

## Zakres i sposób pracy z materiałem

Najpierw ustal źródła, temat, język, odbiorców i zakres zmian. Rozróżniaj:

- Nowe pytania: samodzielna redakcja na podstawie sprawdzonych faktów.
- Adaptację gotowej bazy: zachowanie dobrego brzmienia, z poprawkami tylko
  w uzgodnionym zakresie. Nie przerabiaj dobrego pytania po to, żeby było inne.
- Ratowanie słabego zestawu: stare pytanie jest tropem do sprawdzenia,
  nie źródłem prawdy. Po weryfikacji napisz od nowa pytanie i wszystkie
  odpowiedzi, bez podmieniania kilku słów w dawnym szablonie.
- Tłumaczenie: zachowanie sprawdzanego faktu i sensu wszystkich odpowiedzi,
  ale naturalna konstrukcja w języku docelowym, nie kopia szyku oryginału.

Zapoznaj się z zaakceptowanymi pytaniami z danego zestawu. Traktuj je jako
wzór poziomu, tonu i szczegółowości, nie jako szablon do seryjnego powielania.
Nie narzucaj własnego limitu pytań ani nie uzupełniaj zestawu słabymi pozycjami
dla osiągnięcia liczby. Przy dużym materiale pracuj w partiach pozwalających
przeczytać i sprawdzić każdą pozycję.

## Fakty i źródła

Każde nowe pytanie musi mieć sprawdzoną podstawę. Znajdź w dozwolonym źródle
fragment potwierdzający dokładnie to, o co pytasz. Przeczytaj jego kontekst:
trafienie nazwy w wyszukiwarce nie potwierdza jeszcze osoby, wydarzenia,
związku przyczynowego ani czasu.

- W materiałach literackich odróżniaj zdarzenie od plotki, przypuszczenia,
  relacji bohatera, legendy lub treści obrazu. W razie potrzeby pytaj
  „Według opowieści…”, zamiast przedstawiać relację jako bezsporny fakt.
- Nie mieszaj książek, gier, ekranizacji, wydań i alternatywnych historii.
  Tytuł lub inne doprecyzowanie dodaj tam, gdzie rzeczywiście rozstrzyga
  zakres. W zestawie książkowym również błędne odpowiedzi nie mogą być
  zapożyczeniami z wykluczonych adaptacji.
- Jeżeli użytkownik ograniczył źródła do dostarczonych książek, sprawdzaj
  właśnie w nich. Wiedza modelu, wiki ani inne pytanie z quizu ich nie zastępują.
- Przy danych zmiennych w czasie podaj potrzebną datę lub okres i sprawdź
  źródło dla tego okresu. Unikaj pytań o „obecnego” rekordzistę bez daty.
- Poprawiaj oczywiste literówki w dozwolonym zakresie. Nie odtwarzaj
  nieczytelnej transkrypcji na podstawie domysłu. Nierozstrzygnięty tekst
  odłóż do wyjaśnienia lub odrzuć, zamiast dopowiadać brakujące wydarzenie.
- Sprawdź prawa do wykorzystania materiału i zachowaj autorstwo oraz
  wymagane informacje o pochodzeniu. Publiczna dostępność nie oznacza
  zgody na skopiowanie całego zestawu; przeredagowanie nie znosi licencji.

W notatkach redakcyjnych powiąż każde nowe lub zmienione pytanie ze źródłem:
tytułem i rozdziałem, stroną konkretnego wydania, zakresem linii pliku albo
adresem i wskazanym fragmentem. Zapisz krótko, jaki fakt został potwierdzony.
Przy numerach linii określ plik i sposób ich liczenia. Dowód ma umożliwiać
ponowne odnalezienie fragmentu, nie być samym zapewnieniem „sprawdzono”.

Prywatne teksty książek, długie cytaty i robocze raporty nie trafiają do
instalatora ani automatycznie do repozytorium. Raport przechowuj w ignorowanym
`tmp/` albo w uzgodnionym katalogu poza repo. W danych zachowaj wymagane
pochodzenie i licencję zgodnie z [informacją o źródłach](../content/QUIZ_DATA_NOTICE.md).

## Naturalne brzmienie

Pisz zwyczajnym, poprawnym językiem quizu: konkretnie, bez urzędowego tonu,
ozdobników i zbędnych wstępów. Naturalność nie oznacza potocznych wtrętów,
żartów dopisywanych na siłę ani celowego pozostawiania błędów.

- Zaczynaj od właściwego pytania. Zamiast „W kontekście wydarzeń
  przedstawionych w utworze, jaka postać pełniła funkcję dowódcy…” zazwyczaj
  wystarczy „Kto dowodził…?”. Zachowaj jednak kontekst potrzebny do odpowiedzi.
- Pytaj wprost o czynność lub relację. „Kim była żona X?” brzmi lepiej niż
  „Jaką osobę przypisano X w charakterze małżonka?”. Nie myl przy tym
  małżeństwa, partnerstwa i pokrewieństwa.
- Unikaj konstrukcji z eksportu danych, np. „X — zawód tej postaci?”
  lub „Do jakiej kategorii przynależności państwowej przypisano X?”.
  Dobierz pojęcie do źródła: obywatelstwo, narodowość, miejsce urodzenia
  i służba konkretnemu władcy nie znaczą tego samego.
- Nie dodawaj do każdej pozycji „w uniwersum”, „w książkach z cyklu”,
  „spośród wymienionych” czy „jak wiadomo”. Nie są to zakazane wyrażenia;
  zostają tylko wtedy, gdy w danym pytaniu coś wyjaśniają.
- Nie wymuszaj różnorodności samym zastępowaniem „kto” przez „jaka postać”.
  Krótkie pytania „Kto…?”, „Gdzie…?” i „Dlaczego…?” są normalne.
  Różnorodność ma wynikać głównie z treści i sposobu sprawdzania wiedzy.
- Nie przycinaj tekstu do telegraficznych urywków. Dwa proste zdania bywają
  czytelniejsze niż jedno zdanie z kilkoma wtrąceniami.
- Nie podnoś trudności zagmatwaną składnią. Rzadziej znany fakt może dać
  trudne pytanie, ale polecenie nadal powinno być jasne.

Przeczytaj pytanie i odpowiedzi tak, jak usłyszy je gracz, bez oglądania
notatki ze źródłem. Jeśli sam musisz wrócić do początku, aby rozpoznać
podmiot lub sens zdania, popraw redakcję.

## Jednoznaczne pytanie

Pytanie musi działać samodzielnie, także po wylosowaniu między pytaniami
o zupełnie innych sprawach. Nie odsyłaj do „poprzedniego pytania”,
„wspomnianego bohatera”, „tego miasta” ani „powyższych wydarzeń”, jeśli
odniesienie nie znajduje się w tej samej pozycji.

Sprawdź przed przyjęciem:

- Czy pytasz o jeden konkretny fakt? Jeśli łączysz fakty, cała odpowiedź
  musi dawać się jednoznacznie ocenić.
- Czy wiadomo, o którą osobę, bitwę, wersję utworu lub etap fabuły chodzi?
  Dodaj potrzebne nazwisko, miejsce, okres lub tytuł, nie streszczenie sceny.
- Czy słowa „pierwszy”, „największy”, „jedyny” albo „najstarszy” mają jasną
  miarę i zakres? Nie zamieniaj oceny lub spornego pierwszeństwa w pewnik.
- Czy „dlaczego” pyta o przyczynę podaną w źródle, a nie dowolną interpretację?
- Czy pytanie nie zawiera już rozwiązania lub nie eliminuje części odpowiedzi?
- Czy odpowiedź nie zależy od wyróżnienia kolorem, kursywą, układem strony
  lub inną wskazówką niesłyszalną w syntezie?

Nie zostawiaj w treści trzech wyliczonych możliwości, jeżeli gra przedstawia
cztery odpowiedzi. Gracz nie powinien móc odrzucić czwartej tylko dlatego,
że nie było jej w pytaniu. Redaguj minimalnie: „Która z trzech rzek…” może
stać się „Która z rzek…”. Po usunięciu wyliczenia sprawdź jednak ponownie
jednoznaczność — pierwotne możliwości mogły zawężać sens pytania.

Unikaj podwójnych przeczeń. Pytania „Który… nie…” można stosować oszczędnie,
jeżeli przeczenie jest wyraźne również w odczycie. Nie opieraj rozstrzygnięcia
na przeoczeniu drobnego słowa.

## Cztery odpowiedzi

Standard zestawów to jedna poprawna i trzy różne błędne odpowiedzi. Każdą
z trzech trzeba umieć obronić jako prawdopodobną pomyłkę, a następnie
wykluczyć w dokładnym zakresie pytania.

1. Zachowaj wspólny rodzaj odpowiedzi. Na pytanie o miasto podaj miasta,
   o zawód — zawody, o władcę — osoby, które sensownie można pomylić.
   Nie mieszaj nazwy państwa z nazwą kontynentu, chyba że pytanie faktycznie
   dopuszcza taki wspólny poziom odpowiedzi.
2. Dopasuj kontekst: epokę, region, dziedzinę, rolę, uniwersum i potrzebne
   cechy osoby. Jeśli pytanie mówi o mężu bohaterki, nie dodawaj kobiety
   jako łatwej do wyeliminowania odpowiedzi. Nie wnioskuj jednak o płci
   z samego imienia — sprawdź konkretną osobę.
3. Dopasuj gramatykę wszystkich czterech propozycji do pytania: przypadek,
   liczbę, rodzaj i przyimek. Żadna nie może odpadać wyłącznie językowo.
4. Zachowaj podobny stopień szczegółowości i styl. Nie otaczaj jednego
   pełnego, precyzyjnego opisu trzema ogólnikami. Długości nie muszą być
   identyczne; nie wydłużaj nazw sztucznymi dopiskami dla równego wyglądu.
5. Sprawdź, czy nie są to aliasy, synonimy, różne pisownie tej samej nazwy
   albo odpowiedzi częściowo zawierające się w sobie. „Włochy” i „Italia”
   nie tworzą dwóch niezależnych możliwości w pytaniu o państwo.
6. Sprawdź wszystkie odpowiedzi po zmianie kolejności. Nie używaj „obie
   powyższe”, „A i C”, „żadna z pozostałych” ani podobnych odwołań do listy.
7. Nie wymyślaj fałszywych osób, miejsc ani terminów tylko po to, by wypełnić
   wolne miejsca. Wyjątkiem może być pytanie rzeczywiście sprawdzające
   rozpoznanie nieistniejącego pojęcia, jeśli taki charakter jest jasny.
8. Nie uznawaj odpowiedzi za fałszywą dlatego, że nie wystąpiła w jednym
   znalezionym fragmencie. Sprawdź realną możliwość drugiego rozwiązania.
   Jeśli pozostaje nierozstrzygnięta, zawęź pytanie zgodnie ze źródłem,
   wymień tę odpowiedź lub odłóż pozycję.

Przykład do oceny konstrukcji, nie polecenie dodania pytania:

> W którym państwie leży uzdrowisko Karlowe Wary?
>
> A. Czechy
> B. Słowacja
> C. Austria
> D. Węgry
>
> Poprawna odpowiedź: A.

Wszystkie propozycje są państwami z sensownego kontekstu geograficznego.
Zestaw „Czechy, Bałtyk, Europa, Warszawa” sprawdzałby przede wszystkim
rozpoznanie kategorii, nie położenie uzdrowiska.

Pytania faktycznie dwuwariantowe, np. tak/nie, nie nadają się do tego formatu.
Nie dokładaj „czasami” i „nie wiadomo” jako pozornie innych odpowiedzi.
Odrzuć takie pozycje. Jeśli nie da się znaleźć trzech uczciwych pomyłek,
nie ratuj pytania absurdalnymi propozycjami.

## Różnorodność i powtórzenia

Przeglądaj nie tylko pojedyncze pytania, ale również sąsiadujące fragmenty
i cały zestaw. Kilkadziesiąt poprawnych pytań o to, kto kogo spotkał, może
tworzyć monotonny quiz.

W zależności od materiału uwzględniaj postacie i ich relacje, wydarzenia,
politykę, ustroje, wojny, geografię, kulturę, codzienność, przyrodę, wiedzę
o świecie i znaczenie pojęć. Nie dopisuj kategorii, dla których źródło
nie dostarcza dobrych pytań. Nazwy kategorii powinny być krótkie i zrozumiałe,
a podział na tyle szeroki, by pomagał graczowi, nie rozdrabniał zestawu.

Porównuj sprawdzany fakt, nie tylko identyczne zdania. „Kto zabił X?”
i „Z czyjej ręki zginął X?” to powtórzenie. Pytanie o sprawcę i pytanie
o miejsce tej samej śmierci mogą być odrębne, jeśli oba fakty są istotne
i jedno pytanie nie służy wyłącznie rozbiciu drugiego na drobiazgi.

Nie usuwaj automatycznie wszystkich pytań o tę samą postać ani wszystkich
o tej samej poprawnej odpowiedzi. Sprawdź ich sens. Przy rozbudowie porównaj
nowe propozycje zarówno między sobą, jak i z istniejącą bazą.

Zakończ rozbudowę, gdy pozostają głównie powtórzenia, niepewne fakty albo
przypadkowe szczegóły bez ciekawego kontekstu. Nie twierdź, że osiągnięto
matematycznie maksymalną liczbę pytań. Podawaj rzeczywisty zakres przeglądu.

## Zasady wspólne dla języków

Zestaw ma być naturalny w swoim języku, nie tylko zrozumiały po tłumaczeniu.
Język pytań jest zasobem gry i nie musi być językiem jej interfejsu.
Dodanie polskiego zestawu nie nakazuje tworzenia jego wersji we wszystkich
językach UI. Każda rzeczywiście przygotowana wersja podlega pełnej redakcji.

- Zachowuj znaki diakrytyczne, pisownię nazw i normalną interpunkcję języka.
  Nie usuwaj akcentów ani nie zapisuj całego pytania wielkimi literami.
- Stosuj przyjęte nazwy geograficzne oraz nazwy z właściwego wydania
  literackiego. Nie tłumacz samodzielnie imion i tytułów, które mają już
  ustaloną lokalną postać. W obrębie zestawu zachowuj konsekwencję.
- Czytaj pytanie wraz z każdą odpowiedzią. W językach fleksyjnych tłumaczenie
  samych nazw bez odmiany może zdradzić poprawną odpowiedź.
- Nie przenoś mechanicznie idiomów, szyku ani konstrukcji „jaki jest
  nazywany…”. Jeśli zdanie wymaga przeformułowania, przeformułuj je,
  zachowując dokładnie sprawdzany fakt.
- Gry słów, homonimy, liczba liter, rymy i zagadki gramatyczne wymagają
  osobnej oceny po tłumaczeniu. Sam przekład może zniszczyć rozwiązanie
  albo stworzyć drugą poprawną odpowiedź. Nie zastępuj wtedy po cichu faktu
  innym: odłóż pytanie lub uzgodnij adaptację.
- Zwracaj uwagę na zapis dat, jednostki i liczby dziesiętne. Nie zmieniaj
  wartości przez pomylenie separatora lub systemu miar.
- Nie opieraj się wyłącznie na tłumaczeniu zwrotnym. Może ono potwierdzić
  sens, ale nie dowodzi naturalności w języku docelowym.

### Polski

Pilnuj odmiany nazwisk i nazw miejsc, zgodności rodzaju oraz rozróżnienia
relacji. „Małżonek” nie jest lepszym słowem niż „mąż” lub „żona”, jeśli źródło
mówi wprost, o kogo chodzi. Zwykle wybieraj „Gdzie urodził się…?” zamiast
„Jakie było miejsce narodzin…?” i „Czym zajmował się…?” zamiast „Jaki zawód
przypisano…?”. Nie zastępuj jednak każdego podobnego zdania jednym wzorcem.

Unikaj automatycznych kalk i nadmiaru rzeczowników odczasownikowych.
„Kto dowodził obroną miasta?” jest czytelniejsze niż „Kto był osobą
odpowiedzialną za realizację dowodzenia obroną miasta?”. Przypadek odpowiedzi
musi pasować także do „z kim”, „komu”, „przez kogo” i „z czyjego rozkazu”.

### Angielski

Stosuj naturalny szyk pytania, właściwe czasy i przedimki. „Who led…?”
lub „Where was … born?” zwykle wystarczy zamiast „Which character was
responsible for the act of leading…?”. Nie używaj w każdym pytaniu
„Which of the following…”, ale zostaw to wyrażenie tam, gdzie jest użyteczne.

Przyjmij spójną odmianę angielskiego dla zestawu, zgodną z jego źródłami
i ustaleniami. Nie zmieniaj cytowanych nazw własnych tylko dla ujednolicenia
pisowni. Jeśli „a” albo „an” przed odpowiedzią zdradza wybór, przebuduj
pytanie lub dobierz wszystkie możliwości tak, by żadna nie odpadała
z powodu samego przedimka.

### Czeski

Redaguj po czesku, nie jako polskie zdanie z wymienionymi wyrazami. Sprawdzaj
rekcję, przypadki, szyk, przyimki oraz wyrazy podobne do polskich, ale
o innym znaczeniu. Zachowuj czeskie znaki i ustalone nazwy własne.
„Kde se … narodil?” jest zwykle naturalniejsze niż rozbudowane pytanie
o „místo narození”; rodzaj czasownika dopasuj do osoby.

### Hiszpański

Zachowuj oba znaki pytania oraz akcenty, m.in. w „qué”, „quién”, „cuál”
i „dónde”, gdy pełnią funkcję pytającą. Sprawdzaj rodzajniki, rodzaj i liczbę
odpowiedzi. „¿Dónde nació…?” nie potrzebuje rozbudowanego „¿Cuál fue
el lugar de nacimiento de…?”. Dobór „qué” i „cuál” zależy od konstrukcji,
nie od jednego odpowiednika polskiego „jaki”.

Ustal neutralną lub wskazaną odmianę języka i sprawdzaj regionalizmy.
Wyraz powszechny w jednym kraju nie zawsze ma to samo znaczenie w drugim.

### Rosyjski

Pilnuj odmiany, rodzaju i aspektu czasowników oraz poprawnego zapisu nazw.
Nie przenoś polskiej składni ani angielskich konstrukcji rzeczownikowych.
„Где родился…?” zwykle brzmi naturalniej niż „Каково было место рождения…?”.
Nie mieszaj przypadkowo liter łacińskich z podobnymi znakami cyrylicy.
W zapisie „е” i „ё” zachowuj rozróżnienia potrzebne dla znaczenia,
wymowy i nazw własnych; nie zamieniaj znaków zbiorczo bez sprawdzenia.

### Kolejne języki

Stosuj cały wspólny proces i dopisz istotne, sprawdzone uwagi językowe do
tego dokumentu. Nie zakładaj, że zasady fleksji lub nazewnictwa z języka
pokrewnego wystarczą. Jeśli nie potrafisz rzetelnie ocenić języka docelowego,
oznacz materiał jako wymagający redakcji, zamiast przedstawiać surowe
tłumaczenie jako gotowe. Nie trzeba tworzyć osobnej kopii tego poradnika
dla każdego języka; źródło zasad pozostaje jedno.

## Obowiązkowy przegląd przed integracją

Przejdź poniższe etapy dla każdej nowej lub zmienionej pozycji. Przy dużym
zestawie zapisuj postęp, aby po wznowieniu nie pominąć części materiału.
Próbka służy uzgodnieniu stylu; nie zastępuje przeglądu pozostałych pytań.

1. Potwierdź fakt i zakres w źródle. Zapisz odnośnik redakcyjny.
2. Napisz lub popraw pytanie zgodnie z dozwolonym zakresem zmian.
3. Dobierz trzy wiarygodne pomyłki i sprawdź, dlaczego każda jest błędna.
4. Przeczytaj pytanie bez źródła i bez zaznaczenia poprawnej odpowiedzi.
   Sprawdź, czy jest samodzielne i zrozumiałe po jednym odczycie.
5. Spróbuj wykazać, że druga odpowiedź też pasuje. Poszukaj aliasu,
   innego okresu, innej wersji zdarzenia albo szerszego znaczenia słowa.
   Nierozstrzygniętej niejednoznaczności nie zatwierdzaj.
6. W osobnym przebiegu przeczytaj całą nową partię pod kątem naturalności:
   składni, monotonii, zbędnych dopisków, zgodności gramatycznej odpowiedzi
   i wskazówek zdradzających rozwiązanie.
7. Sprawdź powtórzenia znaczeniowe oraz podział tematyczny względem całej
   bazy. Potem wykonaj kontrolę techniczną i odśwież eksport dla czytelników.

Jeżeli do zadania dopuszczono innych agentów, przekaż im także te instrukcje
i granice źródeł. Wykorzystaj przegląd krzyżowy, lecz osoba łącząca zestaw
nadal odpowiada za powtórzenia i spójność całości. Sam dokument nie jest
zgodą na uruchamianie pomocników. Bez nich wykonaj osobny przebieg redakcyjny
samodzielnie; nie nazywaj go niezależną recenzją.

Wynik przeglądu pozycji to: przyjęta, poprawiona i ponownie sprawdzona,
odłożona z konkretną wątpliwością albo odrzucona z powodem. Do aktywnej bazy
trafiają wyłącznie dwie pierwsze grupy. Usunięcie już opublikowanej treści
musi pozostawać w zakresie zlecenia. Nie przerzucaj nieukończonej redakcji
na użytkownika pod hasłem „resztę można poprawić podczas grania”.

## Kontrola techniczna i włączenie zestawu

Automaty mogą znaleźć pustą odpowiedź, powtórzoną nazwę, uszkodzone kodowanie
lub nieaktualny eksport. Nie potrafią samym zaliczeniem testu potwierdzić
prawdziwości faktu, naturalności języka ani wiarygodności trzech pomyłek.
Nie stosuj listy „słów brzmiących jak AI” ani automatycznego wyniku takiego
detektora jako kryterium przyjęcia lub odrzucenia pytania.

- Korzystaj z istniejących formatów w `content/` i narzędzi opisanych
  w [TOOLS.md](TOOLS.md). `tools/build-quiz-pack.rb` sprawdza m.in. liczbę
  odpowiedzi, duplikaty i wymagane pola; nie jest redaktorem merytorycznym.
- Przy imporcie podawaj właściwe autorstwo, źródło i licencję. Domyślne
  `CC0-1.0` w narzędziu nie jest dowodem, że materiał ma taką licencję.
- Zachowuj tożsamość istniejących pytań tam, gdzie wymaga jej dany zestaw.
  Nie przywracaj odrzuconej pozycji pod nowym identyfikatorem. Numer pytania
  w TXT jest tylko kolejnym numerem do czytania, nie trwałym ID.
- Pytania są osobnymi zasobami, nie wpisami tłumaczeń interfejsu w PO/MO.
  Rozdzielenie opisuje [TRANSLATIONS.md](TRANSLATIONS.md). Nie zmieniaj
  języka interfejsu przy wyborze zestawu ani nie tłumacz go przy okazji.
- Uruchom celowane testy zmienionych danych, ich rejestracji i eksportu.
  Punkty odniesienia to `test/games/quiz/question_integrity_test.rb`,
  `test/games/quiz/reviewed_questions_test.rb` oraz
  `test/games/quiz/text_export_test.rb`; dla książkowego Wiedźmina także
  `test/games/quiz/witcher_books_test.rb`. Dobierz zakres do konkretnej zmiany.
- Po zatwierdzeniu danych zaktualizuj odpowiednie oczekiwane liczby, wersje
  i sumy w testach. Nie kasuj regresji ani nie zmieniaj wzorca wyłącznie
  po to, by test przestał wykrywać błąd.
- Po zmianie treści, odpowiedzi lub kategorii uruchom z katalogu repo:

```console
ruby tools/export-quiz-text.rb
ruby tools/export-quiz-text.rb --check
```

Czytelne kopie `docs/quiz-questions/*.txt` mają numery od 1, w osobnej linii
przed każdym pytaniem, odpowiedzi A–D i wskazanie rozwiązania, bez technicznych
ID. Po usunięciu pozycji numeracja musi pozostać ciągła. Nie poprawiaj TXT
ręcznie zamiast źródła. Eksporty i prywatne materiały redakcyjne nie są
zasobami instalatora.

Nowy format, sposób wyświetlania lub język sprawdź również w rzeczywistym
odczycie gry, w granicach uprawnień do testów. Przy samej korekcie treści
dobieraj kontrolę proporcjonalnie; nie przedstawiaj testu danych jako
odsłuchu ani testu żywej partii.

## Kiedy pracę można uznać za gotową

Gotowy zestaw ma potwierdzone źródła i prawa wykorzystania, sprawdzone
pojedyncze pytania, naturalną redakcję w języku docelowym, jedną poprawną
odpowiedź w każdej pozycji oraz trzy sensowne pomyłki. Nowe pozycje przeszły
przegląd znaczeniowych powtórzeń, kontrolę techniczną i aktualizację TXT.

W podsumowaniu podaj liczby przyjętych, odłożonych i odrzuconych pytań,
główne powody odrzucenia oraz rzeczywisty zakres weryfikacji. Nie obiecuj
bezbłędności ani nie nazywaj pytań pisanych z udziałem AI „niegenerowanymi
przez AI”. Oceniaj gotową treść, nie deklarację o sposobie jej powstania.

Brakujące źródło, niewyjaśniona druga odpowiedź lub nieprzejrzany język
oznaczają nieukończoną pozycję. Najpierw ją popraw, sprawdź ponownie albo
odłóż poza aktywny zestaw. Te kroki są częścią pracy autora, nie zadaniem,
które użytkownik powinien dopiero odkryć po wydaniu.
