# Historia zmian

## Poprawki po buildzie 218 (niewydane)

- Przejrzano wszystkie 6571 pytań Wiedźmina względem 2542 bieżących rewizji
  Wiedźmin Wiki. Usunięto 6187 pytań, poprawiono 35 i pozostawiono 384.
- Trzy warianty nadal korzystają z jednej bazy bez kopiowania pytań: pełny ma
  384, gry 144, a książki i ekranizacje 240 pytań. Szczegóły i kompletne
  manifesty audytu znajdują się w `content/QUIZ_WITCHER_AUDIT.md`.

- Przejściowy błąd połączenia nie zamyka ekranu pokoju ani partii. Zachowany
  jest ostatni poprawny stan i tekst czatu do czasu odzyskania połączenia.
- Ujednolicono odzyskiwanie niepewnych ruchów ludzi, botów i automatycznych
  przejść, np. przygotowania następnego pytania quizu. Ponowienie zachowuje
  ten sam ruch i wynik losowania, a powtórzony wpis nie jest stosowany drugi raz.
- Powiadomienia nie skracają przerwy wymaganej po błędzie 429. Nie dodano
  okresowego odpytywania podczas prawidłowej rozgrywki. Sprawdzono celowane
  awarie transportu i interfejsu; szczegóły: `docs/CONNECTION_RECOVERY_AFTER_218.md`.
- Przebudowano wymiany w Monopoly: najpierw wybiera się gracza z listy, a
  następnie ustala pieniądze i nieruchomości w dwóch listach pól wyboru.
  Escape wraca do wyboru partnera, a rozpoczęcie układania oferty jest widoczne
  dla pozostałych osób przy stole.
- Cała oferta wymiany jest zapisywana w jednym zwartym zdarzeniu, mieszczącym
  wszystkie nieruchomości także na planszach 60-polowych. Zbyt duże zdarzenie
  jest odrzucane kontrolowanie zamiast zamykać Game Room.
- Skrót I podaje numer pola razem z jego nazwą. Zwykłe listy posiadłości
  pokazują przy ulicach, ile pól danej grupy ma ich właściciel.
- Uproszczono komunikaty płatności między graczami i wpłat do puli Darmowego
  parkingu.
- Skompletowanie nowej grupy kolorystycznej odtwarza `hit1.ogg`, niezależnie
  od tego, czy nastąpiło przez zakup, aukcję, wymianę czy bankructwo.

## 1.1.7 — build 218 (kandydat do testów)

- Polski zestaw Wiedźmin ma teraz trzy warianty: pełne 6571 pytań, 3292
  pytania o gry oraz 3279 pytań o książki i ekranizacje.
- Ponownie sprawdzono przypisanie medium wszystkich 6571 pytań. Poprawiono
  2351 klasyfikacji względem dostarczonej mapy pomocniczej, także wśród jej
  pozycji o średniej i wysokiej pewności.
- Doprecyzowano naturalnie 5810 niejednoznacznych pytań, bez zmiany ich ID,
  odpowiedzi, poziomu trudności ani kategorii tematycznej. Audyt nie jest
  pełną weryfikacją merytoryczną wszystkich odpowiedzi.
- Zestawy szczegółowe są tworzone leniwie ze wspólnej bazy, bez kopiowania
  całych pytań do osobnych plików. Każdy zestaw ma wersję danych 2, własną
  liczbę pytań i sumę kontrolną.
- Dodano sprawdzenie kompletności podziału, braku duplikatów, polskich nazw,
  rozpoczęcia i odtworzenia partii oraz binarnego wczytywania z paczki.
- Zachowano wszystkie poprawki buildu 217. Nie zmieniono zasad Quiz Party,
  punktacji, botów, transportu ani lokalnego zapisu ukrytych odpowiedzi.

## 1.1.7 — build 217 (kandydat do testów)

- Naprawiono zbędny zapis podczas sprzątania już usuniętych odpowiedzi.
- Błąd sprzątania lokalnej kopii odpowiedzi nie przerywa punktowania quizu
  ani przejścia do kolejnego pytania.
- Gdy Windows blokuje podmianę głównego pliku odpowiedzi, gra może użyć
  trwałego zapisu awaryjnego. Jeżeli również on zawiedzie, odpowiedź nie
  zostanie wysłana bez kopii potrzebnej do późniejszego ujawnienia.
- Poprawka dotyczy wspólnego zapisu Quiz Party i Państw-Miast; nie zmienia
  zasad, wyników, botów ani protokołu synchronizacji. Szczegóły i ograniczenia:
  `docs/HIDDEN_SUBMISSIONS_217.md`. Zachowano cały build 216.

## 1.1.7 — build 216 (kandydat do testów)

- Lokalnie dodano Quiz Party wraz z poprawkami spóźnionych odpowiedzi,
  limitów czasu, awaryjnego kończenia pytania i gospodarza-obserwatora.
- Dodano polskie komunikaty, poprawiono prezentację wyników i oczyszczono
  wskazane problemy w pytaniach. Duże bazy wczytują się dopiero przy użyciu.
- Szczegóły i ograniczenia danych: `docs/QUIZ_PR3_FIXES.md`.
- Zachowano wszystkie poprawki buildów 214 i 215. Uzupełniono odtwarzanie
  automatycznych działań gospodarza-obserwatora w imieniu gracza.
- Wydanie do ręcznych testów; PR pozostaje niescalony na GitHubie. Pochodzenie
  polskich baz pytań nadal wymaga wyjaśnienia przed szerszą dystrybucją.

## 1.1.6 — build 215 (kandydat do testów)

- Naprawiono wejście do Makao przed rozdaniem i w trybie obserwatora: skrót D
  zawsze ma bezpieczny komunikat, także przy pustej ręce.
- Dźwięki należące do jednego zdarzenia mogą ponownie zabrzmieć równocześnie,
  na przykład zagranie karty razem z jej efektem albo wynikiem rozdania.
- Dodano globalny tryb obserwatora pod Ctrl+Shift+O. Użytkownik pozostaje przy
  stole, zachowuje czat i historię, ale nie jest liczony jako gracz w następnym
  rozdaniu. Ponowne użycie skrótu przywraca udział w następnej grze. Trwająca
  partia nie zmienia składu.
- Zaproszenia do stołu wygasają po pięciu minutach we wszystkich obsługiwanych
  ścieżkach.
- UNO: C odczytuje wyłącznie kartę na stole, a V wyłącznie aktualny kolor.
- Zachowano sekwencje i poprawki intercepcji z buildu 214.

## 1.1.6 — build 213 (kandydat do testów)

- Ujednolicono kursor w kontrolkach ręki: po zagraniu wybierana jest najbliższa
  pozostała karta powyżej, a przy zagraniu pierwszej — następna. Po dobraniu
  kursor przechodzi na ostatnią otrzymaną kartę, również przy kilku kartach.
  Bez wybranego sortowania nowe karty trafiają na dół. Wybrane sortowanie UNO
  pozostaje zachowane. Odczytywana jest nazwa nowej karty pod kursorem, tylko
  podczas przeglądania ręki; bez przeładowania formularza i przerywania czatu.
  Pozostałe rodzaje kontrolek i zakończenie gry zachowują dotychczasową obsługę.
- UNO: sortowanie według przykładu QC — żółty, czerwony, niebieski, zielony;
  wartości 0–9, zmiana kierunku, pominięcie, dobierz dwie, dzikie karty.
  Shift+C i Shift+H nadal przełączają kierunek, Shift+D przywraca kolejność ręki.
- Włączono wcześniej uzgodnione poprawki audytu zasad i botów. Spades lepiej
  szacuje gwarantowane lewy, uwzględnia samotnego asa pik, dokładne końcówki
  oraz ryzyko zerwania zera partnera. No Hell i Suicide są rozłączne.
- Poprawiono model publicznego musika Tysiąca, recykling talii Ninety-Nine,
  wybór pewnej wygranej w Farkle i Yahtzee, skutki kart UNO, żądania i wyjątki
  Makao, pule i wymianę Pokera oraz finanse i decyzje handlowe Monopoly.
- Dopracowano legalne zagrożenia Chińczyka, analizę szachów, wielobicia
  warcabów, ocenę Reversi i gróźb w Czwórkach. Poprawiono pamięć wyników
  wspólnego planera. Sprawdzono wszystkie osiągalne pozycje kółka i krzyżyka;
  doprecyzowano komunikaty Państw-Miast.
- Zachowano ograniczenia obliczeń, ale domykanie wielobicia może wydłużyć
  trudne decyzje warcabowe: zmierzona pozycja 10×10 zajmuje około 8,9 s zamiast
  6,0 s. To nie jest obietnica jednakowej szybkości we wszystkich pozycjach.
- Celowane regresje obejmują decyzje i reguły z audytu, sortowanie, kursor,
  niezmienność czatu i innych kontrolek oraz binarne ładowanie paczki.
  Próby na prawdziwych klientach pozostają do wykonania przez użytkownika.

## 1.1.6 — build 212 (kandydat do testów)

- Uporządkowano komunikaty Monopoly: kto płaci i komu, rzeczywista wpłata
  i pozostały dług, skutki kart, zakupy, kolory grup, handel, aukcje i więzienie.
  Usunięto zbędne automatyczne odczyty sald. Ceny i budynki nadal są na listach.
- Monopoly: B podczas aukcji pozwala wpisać własną całkowitą ofertę. Dodano
  ustawiany czas jednej decyzji; 0 oznacza brak limitu, upływ czasu daje pas.
  Bankructwo następuje automatycznie w turze zadłużonego gracza, gdy nie ma już
  budynków do sprzedaży ani nieruchomości do zastawienia. Oferty handlu nie
  powstrzymują bankructwa. Zachowano kolejność tur przy powstaniu długu.
- UNO: krótkie „Za późno!” z zachowaniem kary, poprawione komunikaty dobierania,
  ruletki kolorów, buzzera, kwestionowania +4 i dodatkowych skutków kart.
- Poker: R pyta krótko „Podbij o:”, G przy samej wysokiej karcie mówi
  „Nie masz układu”. Poprawiono kwoty all-in i podbić, odczyt kart dobieranego,
  wpłaty obowiązkowe, opis wygranych pul i przyczyny niedozwolonych działań.
- Yahtzee: osobne komunikaty otrzymania premii 35 i 100 punktów.
- Makao: czytelniejsze deklaracje, kary i pozostałe kolejki postoju;
  P odczytuje przygotowany pakiet w kolejności zaznaczenia.
- Pomoc F1 wspólnego ekranu nie gromadzi już powtórzonych skrótów podczas
  odświeżeń. Uzupełniono polskie tłumaczenia, zasady i celowane regresje.

## 1.1.6 — build 211 (kandydat do testów)

- UNO: intercepcje działają podczas tury człowieka i komputera, również
  w czasie ustawionego opóźnienia bota. Wyjątek w obsłudze ruchów dotyczy tylko UNO.
- UNO: przy włączonych intercepcjach niepasująca karta zagrana Enterem poza
  własną turą daje „Za późno” i 3 punkty karne. Karta zostaje w ręce, kolejka
  się nie zmienia. Nie rozróżnia się przypadkowego i celowego naciśnięcia.
  O karze decyduje stan po wcześniejszych zdarzeniach; nie restartuje ona
  opóźnienia bota. Uzupełniono zasady i tłumaczenia.
- Monopoly: krótkie komunikaty budowy, sprzedaży budynków, zastawiania i
  wykupu zastawu, wspólne dla mowy i historii. Domy i hotele są rozróżniane.
  Listy zarządzania nadal pokazują ceny i liczbę budynków.

## 1.1.6 — build 210 (kandydat do testów)

- Poprawiono błąd UTF-8/ASCII-8BIT uniemożliwiający instalację buildu 209.
  Dane regionalnych plansz Monopoly mają jawne kodowanie UTF-8, również
  podczas wczytywania z podpisanej paczki. Nie zmieniono zasad ani ekonomii.
- Dodano regresję wczytywania binarnych źródeł z polskimi tłumaczeniami,
  obejmującą inicjalizację programu, zasady 16 gier i dane 19 plansz.
- Ujednolicono numer buildu zgłaszany przez program z numerem w paczce.
  Wszystkie pozostałe zmiany buildu 209 są zachowane.

## 1.1.6 — build 209 (kandydat do testów)

- Przepisano zasady wszystkich 16 gier: pełny przebieg, punktacja, zakończenie,
  warianty i działanie ustawień. Opisy mają nagłówki wewnątrz jednego tekstu.
- Okno zasad zawiera „Zasady” i „Skróty klawiszowe w grze”; przy stole trzecią
  pozycją są „Ustawienia tego stołu”. Pokazuje tylko włączone dodatki oraz
  właściwe dla wariantu wartości, bez wyliczania wyłączonych checkboxów.
- Zebrano skróty każdej gry i wspólne zasady obsługi czatu, historii oraz
  komend planszowych. Dotychczasowy Ctrl+F1 pozostaje bez drugiego powiązania.
- W zasadach Monopoly opisano wszystkie 19 plansz z ich rzeczywistym
  rozmiarem, kapitałem, walutą, pensją i zapasem budynków.
- Sprawdzono komplet ustawień własnego Makao i ich lokalne zapamiętywanie.
  Podgląd stołu uwzględnia też włączone reguły gotowych profili, mimo że
  ich checkboxy są ukryte w edytorze. Same profile pozostają niezmienione.

- Monopoly: po wejściu na minus pozostali rozgrywają swoje tury; gracz
  rozwiązuje dług w następnej własnej turze, przed rzutem.
- Monopoly: listy budowania, sprzedaży i zastawów pozostają otwarte, dopóki
  są dostępne działania. Podają koszty/przychody i liczbę budynków. Brak
  możliwości działania jest oznajmiany; Escape wraca do głównego pola gry.
- Monopoly: jawny komunikat podatku i salda; poprawione zaokrąglanie kosztu
  wykupu zastawu. Zasada równomiernego budowania i sprzedaży pozostaje.
- Monopoly: bot uwzględnia obie strony wymiany, nie zasypuje ofertami i nie
  wraca do odrzuconych propozycji.
- UNO: ustawienie opóźnienia ruchów botów 1–5 sekund, domyślnie 1 sekunda,
  z ograniczeniem względem czasu na myślenie. Nie opóźnia ludzi ani aktualizacji.
- Poker: bot nie traktuje czekania jako bezwartościowego i nie podbija tak
  chętnie przeciętnych układów. Zachowuje podbicia mocnych rąk oraz pasowanie.

## 1.1.6 — build 208 (kandydat do testów)

- Yahtzee: para i dwie pary liczą sumę wszystkich pięciu kości; mizeria
  liczy 36 minus suma. Dostosowano opis zasad i ocenę tych kategorii u bota.
- Monopoly: przed wyborem zakupu słychać nieruchomość, kolor i cenę;
  wybory to „Kup” i „Nie kupuj”. Kolory są również w wymianach.
  Zdobycie pełnej grupy jest ogłaszane po zmianie właścicieli nieruchomości.
- Monopoly: przetłumaczono pola specjalne oraz nazwy stacji, przedsiębiorstw
  i pól neutralnych, zachowując regionalne nazwy własne ulic. Polska plansza
  ma polskie znaki. Kontrola tłumaczeń obejmuje również dane plansz.
- UNO: po dobraniu kary bez legalnej karty tura kończy się automatycznie.
  Wynik rozdania podaje zwycięzcę oraz osobno przyznane każdemu punkty.
- UNO: Shift+C przełącza sortowanie kolorami rosnąco/malejąco, Shift+H
  wartościami rosnąco/malejąco. Kierunek zachowuje się przy odświeżeniu.
- Poker: ogłaszane są preflop, flop, turn i river, wraz z nowymi kartami
  wspólnymi, również przy all-in. Poker dobierany ogłasza pierwszą licytację,
  wymianę i drugą licytację; oba warianty zachowują podsumowanie odsłonięcia.

## 1.1.6 — build 207 (kandydat do testów)

- Monopoly: zastąpiono zastępcze nazwy osiemnastu edycji układami odczytanymi
  z QC. Sześć plansz ma 60 pól. Dodano różne kapitały i waluty, pełne czynsze
  dodatkowych grup, sześć stacji, cztery przedsiębiorstwa oraz większy bank
  budynków. Ruch do więzienia respektuje daną planszę, także indonezyjską.
  Przeliczono kwoty kart, opłat i rezerwy botów. To nadal adaptacje, nie
  deklaracja zgodności 1:1 wszystkich opłat z QC; szczegóły w
  `docs/MONOPOLY_REGIONAL_BOARDS.md`.
- Monopoly: karty ruchu wybierają rzeczywiste miejsca danej planszy, w tym
  jej najdroższą ulicę i ulicę za więzieniem. Niepotwierdzone opłaty i premie
  odnoszą się do miejscowej wypłaty za Start, a naprawy dodatkowych drogich
  budynków uwzględniają ich koszt. Zachowano potwierdzone dane QC.
- Poker: w obu wariantach R pozwala wpisać własne podbicie, niezależne od kwoty
  wyrównania. Poprawiono ante, strit A–2–3–4–5, limity all-in, wymianę kart
  przy ośmiu osobach oraz udział gracza all-in w wymianie.
- UNO: naprawiono zwykłe szóstki, deklarowanie UNO, kary, odzyskiwanie talii,
  zakończenie rozdania i rozpoczęcie kolejki po eliminacji No Mercy.
- Makao: poprawiono pakiety i ich kolejność, deklarację Makao, działanie asa,
  Jokera i czwórek oraz dobieranie i kontrolę wielkości rozdania.
- Yahtzee: poprawiono sumy punktów i komunikaty o zachowanych oraz przerzucanych
  kościach. Spacja tylko powtarza aktualny stan.
- Monopoly: poprawiono czynsze, rozliczanie długów i bankructwa, wyjście z
  więzienia oraz zaliczanie Startu. Dodano osobne talie Szansy i Kasy Społecznej,
  zapas domów i hoteli oraz formularz własnych wymian pieniędzy i nieruchomości.
- Poprawiono decyzje botów wszystkich pięciu gier: planowanie przerzutów,
  ocenę wymiany i zakładów, wykorzystanie pakietów, kolorów i gotówki.
- Podłączono dźwięki akcji nowych gier. Po rozdaniu UNO zwycięzca słyszy win1,
  pozostali uczestnicy lose1; zakończenie całej partii zachowuje dźwięk finałowy.
- Dodano polskie komunikaty i celowany zestaw testów pięciu gier.

## 1.1.6 — build 206

- ponownie sprawdzono pięć nowych gier punkt po punkcie według uzgodnionych
  zasad i interfejsów;
- w UNO poprawiono odpowiedzi na kary, wybór gracza przy siódemce, powrót do
  kolejnego rozdania po eliminacji rundowej No Mercy oraz działanie wariantów
  Classic, No Mercy, Flip, przechwyceń, zera i siódemki, buzzera i czasu na ruch;
- długie rozgrywki botów w UNO są sprawdzane jako test stabilności wielu
  kolejnych legalnych ruchów, bez sztucznego wymagania zakończenia partii;
- w Makao pierwsza karta przygotowanego pakietu musi pasować do karty na stole;
  Joker może reprezentować każdą kartę, a król kier broni przed królem
  atakującym zgodnie z uzgodnionym wariantem;
- w Yahtzee oddzielono premię za kolejne Yahtzee od zasady Jokera i poprawiono
  kolejność wyboru kategorii przy Jokerze;
- w Pokerze poprawiono ocenę układu z mniej niż pięciu kart, all-in, zasady
  heads-up, otwarcie w pokerze dobieranym oraz opis wpisowego zamiast ukrytych
  ciemnych;
- w Monopoly uzupełniono karty specjalne, czynsz za przedsiębiorstwa, jackpot,
  równomierne budowanie i sprzedawanie oraz bezpieczny, krótki zapis wymian;
- wszystkie dziewiętnaście plansz Monopoly ma komplet nazw nieruchomości, w tym
  plansza polska;
- uzupełniono polskie tłumaczenia oraz testy reguł, interfejsów i długich
  sekwencji ruchów nowych gier.

## 1.1.6 — build 205

- ustawienia stołu potrafią teraz wspólnie ukrywać pola, które nie dotyczą
  wybranego wariantu; zastosowano to w Pokerze, Państwach-Miastach, UNO i
  profilach Makao;
- poprawiono uruchamianie Pokera w Ruby używanym przez ELTEN-a; tasowanie kart
  jest nadal deterministyczne, ale nie korzysta już z nieobsługiwanego
  argumentu, który zapętlał komunikat o zmianie stanu gry;
- w Yahtzee główne pole pokazuje tylko rzut kośćmi lub listę kategorii, cyfry
  od 1 do 6 wybierają kości według ich wartości, znaki od `!` do `^` je
  zachowują, a Spacja odczytuje kości i stan wyboru;
- w Monopoly usunięto osobne kończenie tury, dodano automatyczne przejście po
  rozstrzygnięciu pola oraz nazwę grupy kolorystycznej przy zakupie i w akcie
  własności;
- zadłużony gracz w Monopoly widzi w głównym polu wyłącznie rzut kośćmi;
  próba rzutu podaje brakującą kwotę, a dług rozwiązuje się istniejącymi
  skrótami zarządzania nieruchomościami i wymiany;
- uzupełniono polskie komunikaty nowych zachowań i testy ich wspólnego
  interfejsu.

## 1.1.6 — build 204

- dodano Monopoly z dziewiętnastoma wariantami planszy, w tym planszą polską,
  opcjonalnym jackpotem, aukcjami, ręcznym czynszem, wymianami, budowaniem,
  zastawianiem nieruchomości, więzieniem i botami;
- dodano Yahtzee z rosnącym sortowaniem kości, wyborem kości do ponownego
  rzutu, listą możliwych wyników, dodatkowymi kategoriami i osobnymi opcjami
  premii za kolejne Yahtzee oraz zasady Jokera;
- dodano UNO z podstawowym wariantem domyślnym, odpowiedziami na kary,
  opcjonalnymi przechwyceniami, zasadami zaawansowanymi, eliminacją punktową
  oraz botami;
- dodano Makao z wariantem prostym, polskim, jokerowym i własnym, pakietami
  kart, kumulowanymi karami, deklaracjami, wołaniem makao oraz botami;
- dodano Poker obejmujący Texas Hold'em i pokera dobieranego pięciokartowego,
  różne struktury licytacji, limity podbić, rosnące ciemne, pule boczne,
  wymianę kart, skróty informacyjne i boty;
- rozbudowano wspólny interfejs o powierzchnie do gier kościanych oraz
  jednoczesnego wybierania pakietu kart;
- dodano polskie tłumaczenia nazw, ustawień, zasad, działań i komunikatów
  wszystkich nowych gier.

## 1.1.5 — build 203

- poprawiono odzyskiwanie synchronizacji po nieudanych lub anulowanych akcjach
  automatycznych, w tym przejściach między etapami rundy; przed kolejną próbą
  program sprawdza rzeczywisty stan partii;
- naprawiono weryfikowanie niepewnych zapisów w LiveSessions oraz ponowne
  otwieranie nowej partii po chwilowym błędzie połączenia;
- w Państwach-Miastach poprawiono ponowne wysyłanie i ujawnianie odpowiedzi,
  także po zmianie odpowiedzi podczas niepewnego wysyłania;
- usunięto błąd losowania ostatniej dostępnej litery w Państwach-Miastach;
- rozszerzono obsługę błędów połączenia i odrzucanie nieprawidłowych danych,
  aby wadliwe wpisy nie blokowały późniejszych prawidłowych zdarzeń;
- poprawiono wychodzenie z ekranu po zamknięciu stołu przez właściciela,
  bez ponawiania pytania o opuszczenie już zamkniętego pokoju;
- nieudane wysłanie zaproszenia nie daje fałszywego potwierdzenia ani nie
  blokuje kolejnej próby; uprawnienie do zapraszania sprawdza API ELTEN-a;
- ujednolicono kontrolę liczby ludzi i botów przy dołączaniu do stołu oraz
  przyjmowaniu zaproszeń;
- rozpoczęcie nowej partii porządkuje zapis poprzednich zdarzeń na serwerze,
  zachowując bieżący stan pokoju i już odebraną lokalną historię pokoju i czatu;
- zaktualizowano testy do obecnego transportu LiveSessions oraz rozszerzono
  scenariusze wielu klientów, równoczesnych odpowiedzi i błędów sieciowych.

## 1.1.4 — build 202

- wycofano lokalne ukrywanie uczestników po zdarzeniu odejścia z LiveSession;
- wycofano specjalne filtrowanie historycznego składu przerwanej partii;
- lista uczestników ponownie korzysta bezpośrednio ze stanu przekazanego przez
  LiveSessions, tak jak w buildzie 197.

## 1.1.4 — build 201

- wycofano zmianę mastera stołu, migrację pokoju do zastępczej LiveSession
  oraz przerywanie partii po opuszczeniu jej przez aktywnego gracza;
- właściciel stołu ponownie zamyka go przy wyjściu, zgodnie z zachowaniem
  sprzed buildu 198;
- zachowano lokalne odfiltrowywanie uczestników, których ELTEN pozostawia w
  wewnętrznej liście LiveSession po ich odejściu;
- po przejściu do nieaktywnej partii interfejs pokazuje aktualny skład pokoju,
  nie historyczny skład rozgrywki;
- zachowano niezależne dźwięki wejścia, wyjścia i wiadomości czatu.

## 1.1.3 — build 197

- komunikat o dołączeniu do pokoju nie jest już ucinany przez następującą po
  nim informację o oczekiwaniu na rozpoczęcie gry; dotyczy to zarówno
  dołączenia ręcznego, jak i przyjęcia zaproszenia.

## 1.1.3 — build 196

- po zakończeniu partii końcowe komunikaty nie są przerywane, a następnie
  odczytywany jest przycisk ponownego rozpoczęcia gry albo oczekiwanie na nową
  grę;
- pomoc `F1` na ekranie stołu i partii pokazuje tylko akcje dostępne w
  aktualnym menu kontekstowym, dlatego podczas partii nie wymienia `Ctrl+O`;
- pomoc `F1` w głównym menu podaje skróty przyjęcia i odrzucenia zaproszenia
  zgodnie z jego menu kontekstowym.

## 1.1.3 — build 195

- naprawiono błąd `undefined method 'chrsize' for nil`, który występował po
  użyciu klawisza na ekranie stołu wskutek pustego skrótu pozycji „Wyjdź”.

## 1.1.3 — build 194

- potwierdzenie utworzenia stołu podaje nazwę gry i nie jest przerywane przez
  odczyt pola „Rozpocznij grę”;
- menu kontekstowe pokazuje `Ctrl+F1` przy zasadach gry;
- pomoc pod `F1` korzysta z tej samej listy skrótów co globalne menu
  kontekstowe, bez dodawania drugiej obsługi `Ctrl+F1`.

## 1.1.3 — build 193

- wspólne menu kontekstowe jest dostępne z każdego pola stołu i partii;
  zawiera zaproszenia, dodawanie komputera, zasady gry i wyjście, a związane z
  nim skróty działają globalnie;
- zasady gry nie zajmują już osobnego pola pod Tabem; Ctrl+F1 pozostał bez
  zmian, natomiast Delete nadal usuwa wyłącznie komputer wskazany na liście
  użytkowników;
- wspólna kolejność pól to rozpoczęcie, restart albo oczekiwanie, następnie
  pole gry, czat, historia i na końcu użytkownicy;
- gracz niebędący właścicielem widzi przed partią informację o oczekiwaniu na
  jej rozpoczęcie, a po partii — o oczekiwaniu na nową grę;
- po zakończeniu fokus przechodzi cicho na restart albo oczekiwanie, więc
  końcowe wyniki pozostają w kolejce mowy, a zakończoną planszę nadal można
  otworzyć Tabem.

## 1.1.3 — build 192

- aplikacja pomija operacje na trwałych tabelach, gdy ELTEN nie przyznał do
  nich dostępu, dzięki czemu tryb deweloperski może nadal korzystać z
  podstawowych funkcji Game Roomu;
- ekran oczekującego stołu, aktywnej partii i zakończonej gry jest teraz jednym
  trwałym formularzem, który zachowuje fokus, pozycje list oraz zawartość czatu;
- lista użytkowników pokazuje role i — w obsługiwanych grach — bieżące wyniki;
- zapraszanie oraz dodawanie i usuwanie komputerów jest dostępne z menu
  kontekstowego listy użytkowników;
- po rozpoczęciu gry fokus trafia na pole gry, a po jej zakończeniu na listę
  użytkowników; zakończona plansza pozostaje dostępna do przeglądania.

## 1.1.3 — build 191

- stoły są publicznymi sesjami LiveSessions i znikają z lobby wraz z
  zamknięciem sesji, bez pozostawiania osieroconych rekordów;
- wyszukiwanie oraz ręczne dołączanie korzystają z natywnego discovery ELTEN-a
  3.0.3, bez pomocniczego Signal;
- skład pokoju pochodzi bezpośrednio z uczestników LiveSession, a stan pokoju,
  czat, rozpoczęcie gry i ruchy tworzą jeden uporządkowany stos;
- cały ruch, także akcja złożona z kilku poleceń, jest zapisywany atomowo w
  jednym wpisie stosu;
- zaproszenia korzystają z natywnego API LiveSessions zamiast własnych tabel;
- zachowano oddzielne widoki historii: Wszystko, Gra, Czat i Zdarzenia pokoju;
- tabele aplikacji nie przechowują już aktywnych stołów, członkostwa, sesji gry,
  ruchów ani zaproszeń; pozostał trwały rejestr użytkowników i ogłoszenia lobby.

## 1.1.1 — build 184

- bieżący komunikat głosowy ruchu w Warcabach używa wybranego sposobu
  prezentacji pól; po przełączeniu na współrzędne szachowe wypowiada np. A3–B4
  tak samo jak historia, zamiast numeracji pól warcabowych.

## 1.1.1 — build 183

- bot Warcabów nadal analizuje do głębokości 7 z limitem 60 000 węzłów i
  używa niezmienionej funkcji oceny, ale nie przelicza wielokrotnie tych samych
  legalnych ruchów podczas jednej gałęzi;
- wyszukiwanie korzysta z dokładnej, wewnętrznej ścieżki symulacji, pamięci
  ocen pozycji, tablicy transpozycji i kolejności ruchów z poprzedniej
  głębokości; rzeczywiste ruchy graczy i zapis zdarzeń pozostały bez zmian;
- generowanie ruchów pomija niegrywalne pola, szybciej kontynuuje wymuszone
  bicie i zapamiętuje wspólne fragmenty wielokrotnych bić;
- klucz pozycji obejmuje wszystkie dane mające wpływ na legalność i remis,
  w tym trwające bicie, ruchy bez bicia oraz historię powtórzeń.

## 1.1.1 — build 182

- pole czatu pozostaje tym samym polem podczas odświeżeń formularza i jest
  czyszczone dopiero po pomyślnym wysłaniu wiadomości;
- LiveSessions, boty i lokalne automatyczne akcje działają bez wstrzymywania
  podczas pisania, a techniczne zakończenie formularza nie pobiera i nie gubi
  następnego znaku z klawiatury.

## 1.1.1 — build 181

- zdarzenia LiveSessions i automatyczne odświeżenia czekają, gdy aktywne jest
  pole czatu, aby szybkie pisanie nie gubiło wypowiedzianych znaków; po wysłaniu
  wiadomości lub opuszczeniu pola oczekujące zmiany są przetwarzane;
- pole czatu znajduje się bezpośrednio za historią, zarówno przy otwartym stole,
  jak i podczas partii.

## 1.1.1 — build 180

- czat zachowuje pozycję kursora i zaznaczenie podczas zdalnych aktualizacji,
  a własna wysłana wiadomość jest odczytywana jeden raz;
- zwykłe skróty literowe gier nie przechwytują liter wpisywanych w edytowalnych
  polach, natomiast skróty z klawiszem Ctrl nadal działają;
- zaproszenie otwarte z powiadomienia pokazuje Przyjmij i Odrzuć na jednej
  liście obsługiwanej strzałkami;
- główne pole Chińczyka pokazuje tylko akcję rzutu, oczekiwanie albo legalne
  wybory ruchu; V otwiera listę własnych pionków, a Shift+V listę wszystkich;
- wyjście klawiszem Escape z partii zatrzymuje oczekujące komunikaty historii,
  aby ekran stołu nie odczytywał ich ponownie.

## 1.1.0 — build 176

Pierwszy stan opublikowany w tym repozytorium. Odpowiada paczce ELTEN Game Room
build 176 opublikowanej w ELTEN-ie.

Najważniejsze elementy tego stanu:

- jedenaście dostępnych gier oraz wspólny szkielet dla kolejnych;
- synchronizacja stołu i partii przez LiveSessions;
- bezpieczne dołączanie: członkostwo gracza jest zapisywane dopiero po
  pomyślnym przyjęciu do sesji;
- dostępne powierzchnie plansz, kart, kości, pytań i oceniania;
- boty oraz narzędzia do audytu strategii;
- polskie i angielskie komunikaty;
- pełna fizyczna siatka w numerycznym widoku warcabów, z dźwiękiem na polach
  niegrywalnych.

Zmiany eksperymentalne przygotowane po buildzie 176 nie należą do tej bazy.
