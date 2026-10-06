# Instrukcje dla agentów pracujących nad ELTEN Game Room

## Bieżący kontrakt

- Źródła wymagają finalnego ELTEN-a 3.0.4; kontrakt integracji opisuje
  [HOST_API.md](docs/HOST_API.md).
- Zasady utrzymania: [ARCHITECTURE.md](docs/ARCHITECTURE.md); indeks
  aktualnych kontraktów i instrukcji: [INDEX.md](docs/INDEX.md).
  Historia zmian jest w Git; nie jest poleceniem cofania obecnego kodu.
- LiveSessions jest jedynym backendem stołów/ruchów. Nie przywracać dawnych
  tabel ani Signals. Tabele Krowy/lobby/rejestru/subskrypcji nadal są potrzebne.
- Dziennej Krowy nie przeliczać z aktualnego indeksu lub rozmiaru słownika.
  Pierwszy zapis `krowa_daily_assignments` według serwerowego ID utrwala słowo
  dnia (północ czasu polskiego). Nowe słowa uczestniczą w następnym losowaniu,
  nie zmieniają trwającej zagadki. Brak dawnego przypisania to brak wiedzy,
  nie powód do zgadywania historycznego słowa. Szyfrowanie chroni zwykły widok,
  nie stanowi zabezpieczenia przed zmodyfikowanym klientem.
- Zachować oba zabezpieczenia starego zamknięcia, epoki obsady, niezmienność
  historii, uzgadnianie niepewnych zapisów i ochronę prywatnych faz.
- Zwykła partia ma jednego wykonawcę, planowanie poza blokadą zapisu, ponowną
  walidację przed zapisem i most prezentacji na aktywnym wątku UI. Realtime
  ma osobną pętlę. Nie dodawać pracy UI/klawiatury do workera ani pollingu.
- Nie przywracać drugiego schedulera botów w `GameScreen`: gry turowe
  wykonuje `GameRoomSessionRunner`, boty realtime ich własny klient. Testy
  zapisu i potwierdzania ruchów bota muszą przechodzić przez aktywnego wykonawcę.
- Cofnięcie zamrożenia nieudanego zapisu wymaga potwierdzenia własnej granicy,
  tej samej partii i aktualnego gospodarza. Nie odblokowywać nowszego zapisu.
  Przyjęcie zaproszenia i zwykłe wyjście współdzielą ochronę przekazania
  prywatnej fazy i ponawiają ją tuż przed zwolnieniem obecnego stołu.
- Kolejność partii wynika z `__stack_sequence`, nie z losowego identyfikatora.
  Zdalny obserwator Ponga prezentuje pełne snapshoty, bez odtwarzania od zera
  historii odbić, której nie otrzymał. Nadal weryfikuje nadawcę i epokę.
- Błąd programu nie jest rozłączeniem: zachować diagnostykę i zatrzymać
  ponawianie wadliwej akcji. Celowy fallback ma być jawny i ograniczony.
- Cache prezentacji nie może pomijać zdarzeń ani dzielić mutowalnych modeli;
  sprawdzać również `nil` stanu w grach planszowych, obsadę i nowe sesje.
- Trening/eksperymenty umieszczać poza runtime w `tools/`. Testy współdzielą
  pomocniki z `test/support/`, nie scenariusze innych `*_test.rb`.
- Testy hosta korzystają z jednego `ELTEN_HOST_SOURCE`. Brak zależności,
  pominięcie lub timeout nie oznacza sukcesu. Po pierwszym pełnym przebiegu
  użytkownik polecił dalsze testy tylko zmienionych przypadków (25 września).
  Nie powtarzać teraz całego runnera. Dla dalszych czternastu punktów użytkownik
  zatwierdził próby żywych klientów i wczytanie kodu do pamięci, nie instalację,
  nową paczkę lub publikację. Nie rozszerzać tej zgody na inne operacje.
- Historyczne aplikatory quizu usunięto wraz z jednorazowymi audytami.
  Nie przywracać ich jako wrapperów zgodności. Nie powtarzać odsiewania
  pytań ani zmieniać audio/baz w ramach porządkowania kodu.

## Granice po dalszym audycie utrzymywalności

- Walidator historii jest czysty: indeksuje wyłącznie wcześniejsze zaakceptowane
  początki partii. Po zmianie uporządkowanych rekordów ponownie sprawdza historię;
  nie uznawać odrzuconego lub późniejszego początku za uprawnienie do ruchu.
- Retencja nieaktywnych stołów nie usuwa aktywnej sesji, operacji w toku ani
  nieuzgodnionego zapisu. Przy callbacku i publikacji walidacji sprawdzać tożsamość
  sesji/kolekcji pod blokadą: powtórzony licznik nie dowodzi tej samej generacji.
- Edytor opcji i wiązania skrótów mają osobne odpowiedzialności. Nie dopisywać
  do nich zapisu ruchów ani drugiego wykonawcy sesji. Reguły faz, lokalne opcje
  i efekty dźwiękowe deklaruje gra, zamiast nowej listy ID w szkielecie.
- Klient realtime resetuje własne pola; wspólny kod zarządza cyklem kanału,
  pingiem i sekwencją zapowiedzi, nie wspólną fizyką. Testować zastępstwo gracza,
  gospodarza-obserwatora, zamknięcie starego kanału i ponowną rejestrację pingu.
- Symulacja strategii jest leniwa. Nowa strategia bez deklaracji nadal dostaje
  dotychczasowy kontekst; rezygnacja z symulacji wymaga jawnego kontraktu.
  Porównywać wybrane akcje, ich kolejność oraz dalszy stan RNG, nie sam wynik gry.
- Odczyt kandydatów rejestru/subskrypcji używa ograniczonego snapshotu tabeli:
  do 15 s i 4096 wierszy, bez zapytania dla pustej listy. Własne ustawienia czytać
  świeżo, po zapisie unieważniać cache również przy niepewnym wyniku. Błąd nie
  oznacza pustych preferencji. Nie wymyślać operatora grupowego API ani żądania
  dla każdego użytkownika; zmiany innych kont mają jawne opóźnienie do 15 s.
- Pomocniki testów nie uruchamiają cudzych scenariuszy przy imporcie. Agregaty
  binarne izolują scenariusze, a raport nie liczy ich dzieci ponownie jako
  niezależnego dodatkowego pokrycia. Pierwsze niepowodzenia zachowywać osobno.

## Sposób pracy

- Wieloetapowy formularz, który najpierw zapisuje akcję pomocniczą, musi
  przekazać nowy replay i rewizję do dalszej obsługi tego samego formularza.
  Nie usuwać kontroli `StaleView` ani dopuszczać zapisu ze starego widoku.
  Regresja: `test/games/monopoly/staged_trade_screen_test.rb` (także anulowanie,
  ponowne otwarcie, człowiek/bot i dalsza tura). Zwykłe modalne wybory,
  które nie zapisują pośredniego zdarzenia, nie wymagają takiego obejścia.
- Po zastąpieniu uczestnika bot analizuje projekcję historii według obecnych
  miejsc przez `GameRoomParticipantDecisionEvents`; niezmienny zaakceptowany
  log i historyczne komunikaty zachowują dawnych autorów. Testować pełny
  i przyrostowy planer oraz dalszy stan RNG. Cache historycznej prezentacji
  uwzględnia cały prefiks zdarzeń, opcje i obsadę, nie tylko liczbę/ostatnie ID.
- Nie rozwijać wszystkich kandydatów ruchu tylko po to, by ustalić wykonawcę
  lub zbudować ekran. Zawężenie listy prezentacji nie może zawężać decyzji
  bota ani prawdziwych legalnych ruchów. Błąd odczytu członkostwa nie oznacza
  odejścia wszystkich osób; zachować błąd zamiast zwracać pustą listę.
- Prywatne odpowiedzi koordynować między instancjami tego samego natywnego
  Programu współdzielącymi plik. Usunięcie słowa Krowy musi przetrwać replay:
  znacznik dodania wiązać ze źródłowym zdarzeniem, nie sumą całej sesji.
- Zmianę gospodarza i zastępstwo sprawdzać ponownie na granicy zapisu,
  nie tylko przed otwarciem wyboru osoby: w czasie dialogu bot lub człowiek
  może zatwierdzić prywatny wybór. Zastępstwo rozróżnia konkretną osobę
  od cudzych oczekujących sekretów; nie znosić ochrony wszystkich prywatnych faz.
  Skróty podsumowujące wcześniejsze lewy lub bitwy korzystają z historycznych
  komunikatów, nie z nazw obecnej obsady. Gry z jednoczesnymi decyzjami
  deklarują `required_decision_key`, zamiast omijać ustawienia własnym `ding`.

Własne okna aplikacji używają `GameRoomUI::Form` lub
`GameSurfaces::RefreshAwareForm` z referencją `program:`. Wspólny szkielet
zapewnia lokalne F1 jako tekst tylko do odczytu oraz F2/F3 i Shift+F2/F3
do głośności. Historia używa GameRoomHistory::View, a nawigacja
GameRoomHistory.bind; index/check to pozycje znaków, entry_index to wpis.
Nie dubluj tych klawiszy w klasach gier, nie zmieniaj źródeł ani zapisanych
QuickActions ELTEN-a. Dynamiczną pomoc gry i pokoju aktualizuj przez te same
definicje co rzeczywiste skróty (`GameRoomContextHelp`), nie dopisuj na stałe
tipsów zależnych od fazy. Szczegóły: `docs/UI.md`.

- Najpierw odtwórz problem i wskaż warstwę, która jest jego właścicielem.
- Działający model za Wiadomościami/forum NIE dowodzi bieżącej mowy/audio.
  Prezentację przykrytej gry obsługuje GameRoomBackgroundPresentation na
  aktywnym wątku UI, w runtime właściwej aplikacji; worker tylko publikuje
  skopiowane dane. Nie aktualizować formularza gry ani klawiatury z tej
  ścieżki. Zachować wspólne kursory zdarzeń/czatu, kolejkę dźwięków,
  nieprzerywającą mowę i deduplikację po powrocie/rewanżu. ID sesji są
  losowe, nie monotoniczne. Rejestracje sprzątać przy zamknięciu, most
  hosta ma przeżyć reload bez closure starej aplikacji i bez narastania.
  Żywy test wymaga potwierdzenia wyjścia mowy ORAZ działającego audio
  jeszcze za natywnym oknem, nie tylko porównania stanów po powrocie.
  Regresje: game_background_presentation_test i game_background_native_input_test;
  szczegóły docs/BACKGROUND_GAME_EXECUTION.md.
- Gry turowe wykonują polityki automatyczne i boty przez wspólny
  GameRoomSessionRunner zarówno z widocznym, jak i przykrytym formularzem.
  Nie dodawaj drugiej pętli automatów w klasie gry lub GameScreen.
  Model/polityki nie mogą wołać UI, mowy, loop_update ani czytać kontrolek.
  Planowanie jest poza blokadą zapisu; przed zapisem trzeba dostarczyć
  gotowe callbacki i sprawdzić aktualną sesję/rewizję. Nie blokuj nim UNO
  interception, Makao ani czatu. Niestandardowy konstruktor zachowaj w
  build_session_game, szkic oznacz automatic_surface_identity, a wyjątki
  równoległego wejścia zawęź przez concurrent_session_input? do jednej
  rundy/fazy/operacji. Reguły nadal sprawdza action_for. Nie przenoś
  całego GameScreen lub game_client do Thread.new. Realtime ma własną fizykę
  i boty w jednym zegarowym timerze na aktywnym UI, również za innym oknem.
  SessionRunner zapisuje jedynie uzgodnione punkty przez standardowe reguły;
  nie wykonuje fizyki ani wejścia. Menu i przykrycie neutralizują klawisze,
  ale nie zatrzymują synchronizacji. Przy zmianach testuj wiele instancji,
  backoff/niepewny zapis, powrót, deadline, freeze/rewanż i zakończenie.
  Testy: game_session_runner*_test.rb i game_session_screen_test.rb.
- Pytanie o opuszczenie stołu otwieraj przed zakończeniem `GameScreen#run`.
  Do skutecznego wyjścia zachowaj wykonawcę, klienta realtime i prezentację;
  „Nie”, Escape lub nieudana operacja nie mogą ich odtwarzać od nowa.
  Nadal używaj wspólnej kontroli wyjścia i jej ponownej walidacji po dialogu.
  Potwierdzone wyjście zwraca `:left_table`, bez drugiego pytania w lobby;
  zamknięcie przez serwer nie pyta. Regresja: `game_leave_confirmation_test.rb`.
- Uruchomienie nad Konferencją może umieścić Game Room na równoległym wątku
  UI. Finalny ELTEN 3.0.4 dostarcza callbacki aktywnej sceny w swojej pętli;
  nie dodawaj drugiego dispatchu w formularzu. Własne okna nadal używają
  wspólnego Form z `program:` do porządkowania discovery/retencji i uruchomień.
  Zachowaj osobny drain wykonawcy przykrytej gry i przed zapisem. Nie zastępuj
  tych granic globalnym tickiem ani odpytywaniem serwera.
  Sprawdzaj uruchomienie główne i równoległe,
  powrót z innego okna, boty, rewanż oraz niezmienność szkicu/fokusu czatu.
  Regresje: test/host/parallel_scene_events_test.rb i parallel_scene_native_test.rb;
  `ELTEN_HOST_SOURCE` ma wskazywać źródła pasujące do badanego hosta.
- Rozszerzenie przypięte do globalnego obiektu hosta przeżywa aktualizację
  aplikacji bez restartu ELTEN-a. Znacznik „już zainstalowano” nie może
  pozostawiać closure ze starą przestrzenią aplikacji lub formatem danych.
  Przy takich zmianach testuj starą paczkę -> nową w jednym procesie,
  również powtórne przeładowanie, brak narastania wrapperów i odtwarzania
  starego wejścia. Czysty start i samo binarne wczytanie tego nie sprawdzają.
  Regresja Audio Balla: `test/games/audio_ball/keyboard_reload_test.rb`.
- `Replay#state` jest opcjonalne: Kółko i krzyżyk oraz Czwórki przechowują
  pozycję w polach `board`/`players` i zwracają `state: nil`. Wspólne hooki
  nie mogą wymagać Hasha stanu; opcje partii pochodzą również z ActionContext.
  Przy ich zmianach testuj prawdziwy replay klas gier, nie tylko sztucznie
  zbudowany Hash. Regresja opóźnienia botów: `test/models/bot_delay_replay_test.rb`.
- Kodowanie tekstów UI sprawdzaj również w paczce: ELTEN może wczytać źródła
  jako ASCII-8BIT, a brak tłumaczenia w `_()` pozostawia taki tekst bez zmiany.
  Nawet angielska etykieta z myślnikiem „—”, znakiem „×” lub innym znakiem
  spoza ASCII może wtedy wywołać Encoding::CompatibilityError przy doklejeniu
  przez kontrolkę polskiego/rosyjskiego opisu roli lub stanu. Teksty i etykiety
  przekazywane do kontrolek oraz składane komunikaty normalizuj do UTF-8 przez
  `GameRoomContent.utf8`, przed łączeniem/formatowaniem. Nie zmieniaj ID,
  wartości opcji ani binarnych danych, nie nadpisuj globalnego gettext ani
  kontrolek ELTEN-a i nie maskuj problemu usuwaniem znaków diakrytycznych.
  Etykiety `OptionDefinition` i `OptionChoice` normalizuje wspólny szkielet;
  nowe ustawienia mają go używać. Test musi przejść przez rzeczywiste
  tworzenie formularza i odczyt fokusu/stanu, także brakujące tłumaczenie
  Game Roomu obok tłumaczenia hosta. Nie wymuszaj UTF-8 w atrapach `_()` lub
  kontrolek, jeśli host tego nie robi — ukrywa to regresje. Używaj
  `test/localization/game_option_encoding_test.rb` (źródła binarne; EN, PL oraz angielski
  tekst z rosyjskim hostem), a przy kolejnym pakowaniu także argumentu
  ze ścieżką gotowej paczki. Sam zwykły `require` albo test wyłącznie PL
  nie wystarcza do potwierdzenia zgodności.
- Tasowanie musi być zgodne z ELTEN-em: host nadpisuje `Array#shuffle`
  i `shuffle!` metodami bez argumentów. Nie używaj ich w kodzie partii ani
  planerów, zwłaszcza `shuffle(random: ...)`. Dla nowych wywołań stosuj
  `GameRoomRandom.shuffle(values, random: Random.new(seed))`, przekazując
  wspólne ziarno zapisane w zdarzeniu, nie nowy losowy seed podczas replaya.
  Zachowuj istniejące deterministyczne pomocniki (`CardGame#shuffled_cards`,
  `GameRoomDominoTiles.shuffle`, pomocniki planerów) i ich konwersję ziarna;
  nie migruj starych gier przy okazji, jeśli zmieniłoby to zapisane partie.
  Nie naprawiaj zgodności usunięciem argumentu random, `srand`, globalnym
  `rand` ani zmianą klasy Array w działającym ELTEN-ie. Testuj z
  `test/support/elten_array_shuffle.rb`, kontrolując rozdanie, ponowne
  tasowanie/wymianę, replay oraz kolejne użycie tego samego RNG. Sam test
  na zwykłym Rubym poza hostem nie wystarcza. Przy pakowaniu uruchom również
  binarne wczytanie z tą symulacją API; źródła i gotową paczkę rozróżniaj.
- Wprowadzaj małe, spójne poprawki i dodawaj celowany test regresji.
- Korzystaj z nowego, event-driven API ELTEN-a. Nie pisz ręcznych pętli UI.
- Rozszerzaj wspólny szkielet, gdy zachowanie jest wspólne dla rodziny gier;
  nie kopiuj tej samej obsługi do wielu klas gry.
- Nie przenoś reguł gry do `GameScreen` ani szczegółów interfejsu do transportu.
- Nie omijaj `action_for`, `GameRepository` i odtwarzania zdarzeń.
- Nowe karcianki mają korzystać ze wspólnej obsługi ręki, nie kopiować kursora:
  stabilne, unikalne ID kart, `hand_order` w faktycznej kolejności dobierania
  oraz `hand_epoch` identyfikujące właściciela i rozdanie. Szczegóły są w
  `docs/CARD_HAND.md`. Innych list, plansz i kości nie oznaczać jako
  ręki; ich zachowanie i odczyty nie mogą być zmieniane przez ten mechanizm.
- Nowa gra z rzeczywistą ręką kart implementuje `playable_card_navigation` i
  grupuje wszystkie legalne akcje według stabilnego ID fizycznej karty. `Z` i
  `Shift+Z` zapewnia wspólny szkielet. Automatyczny ruch wolno oznaczyć tylko,
  gdy karta nie wymaga dalszego wyboru, deklaracji, meldunku ani pakietu.
- Ręczne sortowanie ręki udostępnia `hand_sorting_available?` i wspólne
  `hand_sort_shortcuts`. Karty dostarczają semantyczne `sort_keys` dla
  colour/number/none, nigdy tłumaczone etykiety jako klucz. Domyślnego
  układu nie zmieniać przy samym dodaniu tej możliwości. Sortowanie widoku
  nie sortuje stanu partii, paczki ani kolejności zaznaczania układu;
  kontrolki CardTable/PacketCardSurface zachowują fizyczne ID i kursor.
  Sprawdzać konflikty skrótów i faktyczną obecność ręki na danym ekranie.
- Trwałą eliminację udostępnia `eliminated_from_game?`, oddzielnie od
  końca rundy, pasa, rozłączenia i all-in. Wspólny selektor dźwięków
  wykrywa przejście do tego stanu i respektuje ostateczny wynik/remis.
  Nie odtwarzać ponownie efektu porażki na końcu ani podczas replaya.
- Niezależne skutki jednego ruchu mogą mieć równoczesne efekty audio.
  Zbierać je niezależnie, nie przez wzajemnie wykluczające if/elsif;
  zachować deduplikację zdarzeń, akceptację ruchu i głośność gry.
- Tekst zasad ze znakami spoza ASCII tłumaczyć lokalnym
  `GameRoomRules.translate`: słownik hosta może przechowywać binarne klucze
  MO. Samo istnienie tłumaczenia i UTF-8 wyniku nie dowodzi, że klucz się
  dopasował. Testować rzeczywisty słownik albo wierną atrapę binarną.
- Bot wybiera akcję, ale wykonuje ją przez standardową ścieżkę gry.
- Stan stołu i partii synchronizuje stos LiveSessions. Publiczne stoły wyszukuj
  przez discovery i dołączaj do nich bezpośrednio; nie przywracaj bootstrapu
  ani synchronizacji przez Signals.
- Unikaj okresowego odpytywania i pełnej odbudowy formularza. Aktualizacja nie
  może przesuwać fokusu ani powodować zbędnych komunikatów czy dźwięków.

## Gry czasu rzeczywistego — opóźnienia i Communications

- Zapowiedź głosowa nie jest potwierdzeniem gotowości sieciowej. W Pongu
  nie uzależniaj serwu od końcowego znacznika syntezy u któregokolwiek gracza
  ani nie dodawaj po nim kolejnej pauzy: obowiązuje zwykły termin jak w singlu.
  Test z atrapą, która sama podaje końcowy indeks, nie sprawdza niezawodności
  rzeczywistego syntezatora. Uwzględniaj także całkowity brak tego indeksu,
  przerwanie mowy i różne wyjścia syntezy. Patrz `docs/REALTIME.md`.
- Korzystaj ze wspólnego `Channel`/`EventChannel`. Przed implementacją
  rozpisz całą drogę akcji: wejście, kolejka, relay, odbiór, zastosowanie
  i prezentacja. Ustal, kto ma prawo rozstrzygać każde zdarzenie.
- Opcjonalne P2P Ponga/Audio Balla korzysta z natywnego `p2p: :full` i
  `p2p_participants_limit`, nie z własnych gniazd lub dodatkowego pośrednika.
  Zachowaj relay po wyłączeniu, ustawienie po reconnect/zmianie gospodarza
  i limit obejmujący obserwatorów (domyślnie 8, 0 bez limitu). Nie zmieniaj
  globalnej zgody ELTEN-a na P2P. `routing: :peers` nie oznacza fizycznego P2P,
  a ping relay nie mierzy bezpośredniego połączenia. Regresje: `realtime_p2p_*`.
- Ctrl+F4 odróżnia pomiar HTTP, UDP do serwera pośredniczącego i RTT do
  poszczególnych uczestników P2P. Ścieżkę odczytuj z natywnego
  `Session#p2p_status`, nie z opcji stołu; po wygaśnięciu P2P nie odczytuj
  starego RTT jako bieżącego. Mieszane połączenia opisuj osobno. Odczyt
  nie wysyła dodatkowych sond ani nie uruchamia połączeń lub callbacków.
  Regresje: `test/realtime/ping_p2p_test.rb`, `test/localization/ping_p2p_dictionary_test.rb`.
- Koordynowanie meczu przez gospodarza, także będącego obserwatorem, nie
  oznacza przekazywania przez niego każdej wiadomości. Dla akcji rozstrzyganych przez uprawnionego
  nadawcę wybieraj rozsyłanie przez relay bez dodatkowego skoku przez hosta.
  Model wymagający zatwierdzenia przez hosta musi mieć uzasadnienie i pomiar;
  nie przełączaj automatycznie wszystkich gier na `routing: :peers`.
- Nie czekaj na sieć ani dysk w klatce UI. Gotową akcję wysyłaj w tle od
  razu, bez czekania na okresowy pakiet lub następną klatkę. Zastępowalne
  pozycje mogą zachowywać tylko najnowszą wartość; ważnych akcji nie gub.
- Zachowuj uwierzytelnienie nadawcy, ID meczu/generacji, kolejność,
  deduplikację, ograniczone kolejki i pełne potwierdzenia wymaganych osób.
  Odbiorca chwilowo nieobecny nie znika z wymagań dostawy. Kolejna partia
  dostaje nowego klienta; stare zadania i powtórne zaproszenia nie mogą
  naruszać nowego połączenia. Odzyskiwanie ma działać bez Entera gracza.
- LiveSessions przechowuje trwały stan stołu i wyniki; nie uzależniaj
  każdego ruchu ani bezpiecznej lokalnej prezentacji od trwałego zapisu.
  Nie przyspieszaj kosztem uprawnień do punktów lub zgodności rozstrzygnięć.
- Mierz osobno HTTP, relay RTT, kolejki/UI, zastosowanie akcji i trwały
  zapis; nie odejmuj surowych zegarów różnych komputerów. Sprawdzaj ludzi
  i boty, różne miejsca, gospodarza-obserwatora, rewanż,
  utratę/duplikację/kolejność, tło i reconnect.
  Cztery kopie jednego komputera nie zastępują różnych łączy. Nie maskuj
  transportu zmianą fizyki ani nie uznawaj niewyjaśnionych zacięć za naprawione.

Kontrakt dostawy i zasady pomiarów: `docs/REALTIME.md`.

## Weryfikacja

- Dobrowolna aktualizacja przy starcie: tylko przy zimnym wejściu po objęciu
  blokady jednej instancji, przed dołączeniem do stołu. Porównuj numery buildów
  (nie samą różnicę wersji); nie obniżaj testowego buildu. Odmowa, błąd i limit
  czasu katalogu nie blokują uruchomienia. Natywny instalator ELTEN-a musi
  wykonać się dopiero po finalizacji starego Program, poza jego runtime.
  Zachowuj cel wejścia i blokadę kolejnych uruchomień podczas pobierania;
  po przeładowaniu rozwiązuj klasę po UUID, nigdy przez stary obiekt klasy.
  Testuj wszystkie ścieżki wejścia, odmowę/anulowanie/awarię i powrót po
  instalacji. Nie aktualizuj aktywnej partii ani publicznego katalogu w testach.


Wspólne funkcje stołu opisują `docs/ARCHITECTURE.md`, `docs/UI.md`
i `docs/PRIVATE_STATE.md`:

- Wariant/ustawienia Ctrl+R pochodzą z `table_options_announcement` i tych
  samych definicji co dokument ustawień. Nie utrzymuj drugiej listy reguł.
- Licznik S planszówki implementuje przez `remaining_piece_counts(replay)`
  w kolejności graczy; licz faktyczną planszę, nie wynik czy stan początkowy.
  Nie przypinaj literowych skrótów gry do edytowalnego czatu.
- Prywatność jest opcją wspólnego tworzenia stołu, nie ustawieniem każdej gry.
  Nie publikuj prywatnej aktywności. Ważność prywatnego powiadomienia musi
  pochodzić z serwerowego zaproszenia, nie z założonego terminu aplikacji.
- Zapis korzysta ze standardowego replaya i `saved_game_schema_version`.
  Nowa gra określa `save_game_error` dla niebezpiecznych faz albo wyłącza
  zapis przez `supports_saved_games?`. Jeśli wartości zdarzeń zawierają nazwy
  kontrolerów, implementuje `restored_event_value` dla tych konkretnych pól.
  Nie zastępuj graczy ani nie zamykaj stołu przed potwierdzonym zapisem archiwum na koncie.

- Uruchom celowane testy podczas pracy.
- Przed pull requestem uruchom `ruby test/run.rb`.
- Zmiana transportu wymaga testów `live_sessions_*`, `test/transport/transport_test.rb`,
  `test/transport/game_sync_test.rb` i scenariusza wielu klientów.
- Zmiana wspólnej powierzchni wymaga testu samej powierzchni oraz co najmniej
  jednej dotkniętej gry.
- Nie zmieniaj numeru wydania ani nie podpisuj paczki bez wyraźnego polecenia
  maintenera.

## Dane, których nie wolno dodawać

Nie zapisuj tokenów MCP, kluczy, certyfikatów, profili ELTEN-a, logów z danymi
prywatnymi, poświadczeń serwera ani podpisanych paczek `.eltsetup`.

Raporty, audyty, wyniki testów i podsumowania lokalnych zmian przechowuj
lokalnie w ignorowanym przez Git katalogu `tmp/`. Nie dodawaj ich do
śledzonych plików repozytorium, chyba że są konieczne do jego utrzymania
lub użytkownik wyraźnie o to poprosi.

## Zasoby dźwiękowe

Domyślny format dla każdego nowego efektu, głosu, pętli i muzyki:
Ogg Opus `.opus`, 144 kb/s VBR, 48 kHz, ramki 20 ms, libopus audio,
complexity 10. Zachowuj mono/stereo, metadane i poziomy; nie normalizuj,
nie przycinaj i nie przekodowuj wielokrotnie plików już zgodnych.
Używaj `tools/encode_audio.rb` oraz oryginału poza paczką. Samo przemianowanie
pliku nie jest konwersją. Pakowanie odrzuca inne formaty i fałszywy nagłówek
Opus, ale nie koduje ponownie; identyfikatory dźwięków pozostają bez rozszerzeń.
`tools/generate-pong-echo.rb` również produkuje Opus z deterministycznego PCM.
Szczegóły procedury: `docs/BUILDING.md`. Licencje i autorstwo zachowaj.

## Kontrakty po uzupełnieniu buildu 239

- Jedna instancja UI na proces: `GameRoomSingleInstance` przełącza natywny
  wątek, nie uruchamia `main` ponownie. Właścicielem nie jest sam widget.
  Odrzucone uruchomienie nie zamyka wspólnej puli dźwięków. Konkretne akcje
  czekają na granicę formularza, nie przerywają dialogów modalnych.
  ELTEN może pozostawić zakończony wątek przekierowanego uruchomienia na
  liście Okna. Usuwaj wyłącznie własne oznaczone i już zakończone wątki,
  na aktywnym UI po przełączeniu, także w formularzu modalnym. Nie zabijaj
  wątków i nie porządkuj cudzych okien. Sprawdzaj natywny cykl uruchomienia,
  nie tylko wartość zwróconą przez blokadę (`test/host/single_instance_native_test.rb`).
  Zimne wejście z widgetu (stół, tworzenie, preset, Ctrl+J) planuje nową
  scenę programu przez natywne `insert_scene`; nie otwieraj długotrwałego
  formularza wewnątrz callbacku Scene_Main ani na współdzielonym obiekcie
  widgetu. Core ma ustawić kontekst sceny i zakończyć jej cykl życia.
  Regresja: `test/room/widget_scene_navigation_test.rb` — także inne okno i powrót.
- `DiscoveredSession` jest związany z połączeniem, które odkryło stół.
  Wiersz przekazany przez widget lub powiadomienie nie może pożyczać tego
  połączenia nowemu oknu gry: dołączenie rozwiązuje identyfikator we własnym
  magazynie LiveSessions, którego callbacki obsługuje wykonawca partii.
  Po zmianie endpointu unieważniaj odkryte obiekty. Sprawdzaj publiczny
  i prywatny stół oraz ruch za innym oknem po zimnym wejściu z widgetu,
  nie tylko osobno nawigację i synchronizację. Regresja:
  `test/transport/live_sessions_discovery_owner_test.rb`.
- Statystyki: callbacki UI/replay tylko odkładają kopie danych do ograniczonej
  pamięci; atomowy zapis i sieć należą do workera. Błąd telemetrii nie może
  przerwać gry. Nie ignorować konfliktów innych niż sama data powtórnego
  rozstrzygnięcia tej samej partii. Retencja usuwa tylko własne wygasłe
  raporty obecności, nigdy historyczne statystyki.
- Statystyki budzą zarządzany worker zdarzeniami, nie pustym pollingiem co
  30 sekund. `GameRoomAnalyticsStorage` rozwiązuje natywne `data_path` raz
  na runtime, w tle; nie wracaj do powtarzanego parsowania paczki przez
  hostowe read_json/update_json. Zachowaj atomowy zapis, blokadę pliku,
  izolację konta i odrzucanie uszkodzonego JSON. Retry tylko zaległości:
  30/60/120/300 s, bez omijania backoffu przez nowe wpisy. Obecność:
  zmiany obsady/stanu + heartbeat 120 s po sukcesie, nie ruchy/czat/punkty.
  Czytniki obejmują bieżącą i pięć poprzednich minut; sprzątanie własnych
  starszych wierszy maksymalnie 64/15 min przy publikacji. Tryb dev nadal
  wyłącza statystyki. Test płynności musi jawnie uruchomić izolowane
  statystyki, inaczej nie sprawdza tej ścieżki. Szczegóły: docs/STATISTICS.md.
- Statystyki wysyłają zbiorczo maksymalnie 25 wpisów na porcję i oddają worker
  po przekroczeniu miękkiego budżetu między porcjami. Potwierdzać tylko
  zwrócony, sprawdzony prefiks; utrata odpowiedzi nie znosi deduplikacji ani
  kontroli konta/anulowania. Respektować większy termin `retry_after` serwera.
  Zimną wizytę datować dopiero według potwierdzonego czasu, zachowując moment
  wejścia. Nie pomijać korekty obecności po niepewnym zapisie, nawet gdy stan
  wrócił do poprzedniego. Cache raportu: 15 s/4096, świeży schemat przy każdym
  odczycie, jawne Odśwież i próba zapisu unieważniają snapshot. Regresje:
  `statistics_audit_regressions_test.rb`, `game_room_analytics_client_test.rb`.
- Odczyt statystyk i obecności nie kończy się po niepełnej stronie. Serwer
  może zwrócić 1000 rekordów mimo limitu 2000 w schemacie, a także mniej.
  Żądaj najwyżej 1000 (lub mniejszego limitu tabeli), przesuwaj offset/ID
  o faktycznie odebrane rekordy i kończ dopiero na pustej odpowiedzi albo
  potwierdzonej granicy snapshotu. Zachowaj deduplikację, daty kanoniczne,
  kontrolę postępu i anulowania; błąd dalszej strony nie jest częściowym
  sukcesem. Testowe serwery muszą umieć skracać strony niezależnie od schematu.
  Regresje: `statistics_pagination_test.rb`, `room_presence_store_test.rb`
  i `game_room_analytics_client_test.rb`. Nie „naprawiaj” liczb dopisywaniem
  startów lub ograniczaniem liczby ukończeń do liczby startów.
- Prezentacja planszy jest lokalna. Zapisuj wyłącznie jawnie dopuszczone
  flagi, a orientację względem miejsca gracza; nie zapisuj kursora i szkiców.
  Nowe stoły Chińczyka mają `enter_on_one: true`, stare zdarzenia bez tej
  opcji nadal wymagają dawnych zasad. Nie zmieniaj znaczenia starych rzutów.
- Ctrl+M i Ctrl+Shift+R dotyczą zaznaczonej osoby na liście uczestników,
  nie pola gry. Pomoc sprawdza bieżącą dostępność, a wywołanie ponownie
  weryfikuje uprawnienia i tożsamość, nie sam indeks wiersza.

## Redakcja pytań quizu

Przed tworzeniem, importem, rozbudową, poprawianiem lub tłumaczeniem zestawu
przeczytaj w całości [zasady redakcji pytań](docs/QUIZ_EDITORIAL.md) i stosuj
je do KAŻDEGO nowego lub zmienionego pytania, także z gotowej bazy lub PR-a.
Obowiązują we wszystkich językach. Sprawdź źródło, jednoznaczność, naturalne
brzmienie, trzy wiarygodne błędne odpowiedzi i powtórzenia znaczeniowe.
Wykonaj osobny przegląd językowy całej dodawanej partii; próbka i zaliczone
testy formatu nie zastępują redakcji. Nierozstrzygniętych pozycji nie dodawaj
do aktywnego zestawu. Zachowuj wyraźne ograniczenia użytkownika dotyczące
źródeł i zmian tekstu; nie przepisuj przy okazji innych zestawów. Przy nowym
języku stosuj wspólne zasady i uzupełnij sprawdzone uwagi w tym dokumencie.

## Czytelne kopie pytań quizu

- Po każdej zmianie pytań, odpowiedzi, podziału lub dodaniu zestawu uruchom
  `ruby tools/export-quiz-text.rb` i dołącz aktualne pliki `docs/quiz-questions/*.txt`.
- Pliki do czytania zawierają kolejny numer w osobnej linijce przed pytaniem
  (od 1 w każdym zestawie), treść, odpowiedzi A–D i wskazanie poprawnej
  odpowiedzi, **bez technicznych identyfikatorów pytań**. Nie edytuj ich ręcznie: źródłem
  prawdy są zestawy w `content/`. Jedynym bieżącym zestawem Wiedźmina jest
  `quiz.witcher.books.pl` (książki); nie przywracaj usuniętych zbiorów o grach
  i ekranizacjach. Pytania weryfikuj w tekstach książek, nie w adaptacjach.
- `ruby tools/export-quiz-text.rb --check` oraz `test/games/quiz/text_export_test.rb`
  wykrywają nieaktualne kopie. Przy nowym zestawie sprawdź także jego obecność
  w eksporcie. Nie dołączaj TXT ani narzędzia eksportu do instalatora gry.

## Pakowanie zawartości wykonawczej

- Postęp realtime pod menu i za inną sceną korzysta z jednego zegara
  `GameRoomRealtime::Progress`; nie dokładaj drugiej fizyki w workerze.
  Ukryte pole ma neutralne wejście, nie celową pauzę. Zwykły wykonawca
  zapisuje uzgodnione punkty. Propozycja punktu Ponga musi odpowiadać
  bieżącej wymianie również przed wywołaniem walidatora.
- Klient podglądu Scrabble realizuje cały kontrakt klienta GameScreen,
  nie tylko odbiór wiadomości. Testuj jego rzeczywisty start/pętlę/zamknięcie.
  Szkic zawiera tylko położone płytki, nie resztę stojaka ani prywatny wybór.

Tłumaczenia mają jeden `locale/<LANG>.po` i wynikowy `locale/<LANG>.mo`
na język oraz wspólny POT. Nie odtwarzać dawnych fragmentów JSON ani manifestu
ich eksportu. PO jest źródłem tłumaczeń także dla polskich zasad i historii
zmian aplikacji. Wpisy historii zmian są w `lib/game_room_changelog.rb`;
nie utrzymywać osobnych kopii Markdown. Zachować płaskie ścieżki MO wymagane
przez runtime ELTEN-a.
Kontrakt obu manifestów, stagingu i natywnych builderów sprawdza
`test/tooling/locale_build_contract_test.rb`; używa niepodpisanych fixture,
nie wydania gry. Manifest źródłowy w `__app.rb` zachowuje LF.

Nigdy nie przekazuj całego repozytorium do rekursywnego pakowania ELTEN-a.
Najpierw przygotuj oddzielny katalog przez `tools/stage-release.rb`.
Wspólna lista dopuszcza kod produkcyjny, dane gier, nagrania, gotowe MO,
manifesty, główny README.md z tłumaczeniami content/readme/{EN,CS,ES,RU}.md
oraz licencje i informacje o źródłach. README jest zasobem odczytywanym
w głównym menu (po Ustawieniach, przed Co nowego), według języka interfejsu.
Zachowuj jedną treść każdego języka w repo i instalatorze; nie generuj drugiej kopii w Ruby.
Testy, narzędzia, docs, AGENTS/CONTRIBUTING/CHANGELOG.md, źródłowe katalogi tłumaczeń,
raporty importu i materiały redakcyjne pozostają w repo, nie w instalatorze.
Zasady i changelog aplikacji są w przygotowanym kodzie/tłumaczeniach.
Nowy nietypowy zasób wykonawczy dodawaj jawnie do reguł pakowania wraz
z celowanym testem; nie naprawiaj brakującego pliku kopiowaniem całego repo.
Przed wydaniem sprawdzaj dokładny zbiór plików, zależności, wymagane dźwięki,
zgodność bajtów ze snapshotem, podpis i binarne wczytanie gier/treści/PL/EN.
Testy uruchamiaj z katalogu źródeł przeciw gotowej paczce. Brak testów
w paczce jest oczekiwany; brak produkcyjnego pliku nigdy nie może być
maskowany wczytaniem jego odpowiednika z dysku. Zachowaj ochronę krótkiej
ścieżki stagingu na Windows i nie wydawaj archiwum z samym manifestem.

### Dokumentacja użytkowa i wszystkie wersje językowe

Przy zmianach funkcji, skrótów, ustawień, ścieżek menu, zasad i ograniczeń
samodzielnie sprawdzaj i aktualizuj odpowiednie rozdziały README w KAŻDYM
obsługiwanym języku. Nie czekaj na przypomnienie użytkownika. Polska wersja
jest w README.md, pozostałe w content/readme/<LANG>.md; to pełne tłumaczenia,
nie skrócone opisy. Zachowuj ręczne poprawki autora i usunięte przez niego
fragmenty. Nie przywracaj usuniętej treści przy aktualizacji tłumaczeń.
Dodanie języka interfejsu wymaga również pełnego README, podłączenia wyboru
dokumentu i jawnej listy zasobów instalatora oraz rozszerzenia testów.

W README, zasadach i pozostałej dokumentacji pilnuj poprawnego Markdowna,
hierarchii i kolejności nagłówków, akapitów, list, odstępów oraz działających
odnośników i spisu treści. Nie spłaszczaj treści do jednego ciągu tekstu.
Zasady zachowują źródło JSON i natywne nagłówki ELTEN-a — nie przenoś do
ich zwykłych akapitów surowego Markdowna, którego widok nie interpretuje.
Kontroluj dokument nie tylko jako plik: sprawdź odczyt w natywnej kontrolce,
nawigację nagłówkami, Enter w spisie i powrót Escape, także z binarnie
wczytanych źródeł oraz przy polskich i innych znakach Unicode.
Test zgodności języków README musi wykrywać nowy język manifestu bez
dokumentu; sam fallback do angielskiego nie oznacza ukończonego tłumaczenia.
