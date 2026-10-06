# Testy

Strukturę katalogów opisano względem `test/`; polecenia uruchamiaj z katalogu
głównego repozytorium. Scenariusze są pogrupowane według właściciela zachowania.
Każda z 32 gier
ma katalog `games/<id>/`; w jego nazwach plików nie powtarzamy ID gry.
Testy reguł, botów, interfejsu, tłumaczeń i narzędzi konkretnej gry są razem.

| Katalog | Zakres |
| --- | --- |
| `games/` | Scenariusze konkretnej gry, np. `games/spades/planner_test.rb` |
| `models/` | Wspólne replaye, boty, symulacja, RNG i własność stanu |
| `session/` | Wykonawca partii, polityki automatyczne, deadline i zegary |
| `transport/` | LiveSessions, zapis, discovery, synchronizacja i odzyskiwanie |
| `realtime/` | Kanały Communications, dostawa, routing, ping i P2P |
| `ui/` | Wspólne formularze, powierzchnie, historia, karty, dźwięki i skróty |
| `room/` | Lobby, stół, uczestnicy, widget, zaproszenia i powiadomienia |
| `persistence/` | Archiwa, odtwarzanie zapisów i magazyny prywatnych odpowiedzi |
| `statistics/` | Statystyki, telemetria i obecność |
| `localization/` | Wspólny katalog, kodowanie, tłumaczenia i teksty zasad |
| `host/` | Natywny cykl aplikacji, sceny i przeładowanie rozszerzeń hosta |
| `tooling/` | Runner, generatory, kompilatory, trening i granice pakowania |
| `integration/` | Wspólne kontrakty i scenariusze obejmujące kilka gier |
| `support/`, `fixtures/` | Definicje atrap, pomocniki i dane; bez automatycznego wykonywania |

W samym `test/` są tylko `run.rb`, `code_quality_test.rb`,
`game_imports_test.rb` i `model_contract_test.rb`: wykonanie testów,
kontrola granic kodu, ładowanie runtime i korpus referencyjny wszystkich gier.

## Uruchamianie

```console
ruby test/run.rb test/games/spades --report tmp/spades-results.json
ruby test/run.rb test/games/monopoly/staged_trade_screen_test.rb
ruby test/run.rb test/transport test/session --list
ruby test/run.rb --suite tooling --list
```

Runner przyjmuje katalogi, ścieżki plików i wzorce. Katalog przeszukuje
rekurencyjnie, bez `support/` i `fixtures/`; nakładające się wybory tego
samego scenariusza są scalane. Bez argumentów wybiera wszystkie scenariusze.
Podczas bieżących porządków uruchamiamy tylko celowane przypadki, zgodnie
z ograniczeniem w `AGENTS.md`.

Każdy skrypt działa w osobnym procesie. Domyślny timeout to 180 s;
`--timeout` pozwala go zmienić. Runner kontynuuje po błędzie i zapisuje
raport JSON również dla niepowodzeń. Timeout, błąd i pominięcie oznaczają
niezerowy wynik; `--allow-skip` dopuszcza pominięcia jawnie, ale ich nie
przemianowuje na sukcesy. Brak źródeł hosta lub zależności nie jest sukcesem.
Testy hosta korzystają z jednego `ELTEN_HOST_SOURCE`; pin i instalację gemów
opisuje [BUILDING.md](BUILDING.md).

Sześć rozłącznych zestawów CI (`models`, `transport`, `ui`, `native`,
`tooling`, `integration`) opisuje warstwę wykonania. Folder gry opisuje
właściciela, więc jedna gra może mieć testy w kilku zestawach CI.
Nie łącz `--suite` z listą ścieżek. `tooling/runner_selection_test.rb`
sprawdza kompletność i rozłączność zestawów oraz domyślne odkrywanie.

## Dodawanie i utrzymanie

Nowy scenariusz umieszczaj przy grze lub warstwie, której kontrakt sprawdza.
Nazywaj go zachowaniem, nie numerem buildu. Zbliżone przypadki korzystające
z tych samych fixture mogą być w jednym pliku; nie łącz scenariuszy
wymagających sprzecznych globalnych atrap lub świeżego procesu.

Pomocniki z `support/` nie wykonują scenariuszy przy imporcie. Wspólne
definicje wydzielaj z `*_test.rb`. Agregaty binarne uruchamiają dzieci
przez ten sam runner, z osobnymi procesami, preloadem i językiem. W raporcie
pokrycia agregat i jego dzieci nie są niezależnymi dodatkowymi testami.

Usunięto kontrole jednorazowych audytów Quizu wymagające zewnętrznych
raportów oraz testową implementację dawnego `TurnGate`. Bieżące sumy,
pytania po korektach, książkowy zestaw Wiedźmina i eksport są w `games/quiz/`.
Fixture starej klawiatury i rozszerzeń hosta nadal służą regresjom aktualizacji
w jednym procesie; są aktywnym kontraktem, nie porzuconym backendem.

Korpusy oczekiwanych zachowań są w `fixtures/contracts/`. Generator tworzy
historie i decyzje Spades z jawnego checkoutu referencyjnego:

```console
ruby test/fixtures/generate_contracts.rb --source REFERENCE_CHECKOUT --write NEW_DIRECTORY
```

Odmawia nadpisania istniejącego katalogu. Nowa wersja wymaga przeglądu różnic;
nie aktualizujemy wzorców po czerwonym teście. Kontrola jakości porównuje kod
z `fixtures/quality_baseline.json`; samą kontrolę sprawdza `tooling/quality_checks_test.rb`.

Korpus `contracts/v1` pochodzi z niezmienionego `0c86d03` (Ruby 4.0.5, EN).
Obejmuje 30 gier turowych, do 16 pierwszych legalnych ruchów, syntetyczne osoby,
ziarno 137 i lokalny magazyn sekretów. Checkpointy sprawdzają pola replaya,
kolejność akcji, wykonawcę i osiem dalszych wartości RNG bez zużywania
generatora gry. Historyczne klucze Categories/Quiz oparte na `String#hash`
są sprawdzane według wzoru i normalizowane do SHA-256 tylko do porównania.
Statki, Państwa-miasta, Krowa, Scrabble i Taboo mają tylko checkpoint
początkowy; wymagają również dedykowanych testów wyborów i danych. Korpus
nie zastępuje testów UI, sieci, realtime, pełnych partii ani wszystkich opcji.

`fixtures/polish_messages.json` zawiera niezależne oczekiwane teksty dla
regresji tłumaczeń, pogrupowane według sprawdzanego zachowania. Pochodzą
z dotychczasowych kontroli słownictwa i historii wydań; CLI tłumaczeń nigdy
ich nie regeneruje. Wczytuje je `support/translation_reference.rb`.
`fixtures/changelog_checksums.json` zachowuje dokładne brzmienie i kolejność
wpisów EN/PL wydań 238–240 jako sumy SHA-256 tablic JSON. Starsze wydania
mają wzorce tekstów w `polish_messages.json`. Zmiana wzorca wymaga przeglądu
konkretnych wpisów; kompilacja tłumaczeń nie aktualizuje tych danych.
Kontrakt katalogów, manifestów i obu natywnych builderów ELTEN-a sprawdza
`tooling/locale_build_contract_test.rb` na tymczasowej aplikacji testowej.

`fixtures/quiz/questions.json` przechowuje zatwierdzone liczby, wersje, sumy
logiczne pytań, wykluczone ID i wybrane przypisania mediów.
`fixtures/audio_ball/recordings.json` wiąże bieżące nagrania z plikami
źródłowymi i sumami; licencje opisuje `THIRD_PARTY_NOTICES.md`. Te wzorce
zastępują zależność testów od dawnych raportów, nie są automatycznie
aktualizowane przy niepowodzeniu testu.
