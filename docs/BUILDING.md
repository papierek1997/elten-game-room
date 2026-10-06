# Testowanie i budowanie

## Testy bez ELTEN-a

Testy logiki gier są samodzielnymi skryptami Ruby. Testy narzędzi tłumaczeń
wymagają dodatkowo standardowego gema GetText:

```console
bundle install --gemfile tools/Gemfile.i18n
```

Zalecana jest wersja Ruby 4.0, zgodna ze środowiskiem bieżącego ELTEN-a.
Testy kontraktów hosta wymagają także jego zgodnych źródeł (obecnie ELTEN
3.0.4). Ustaw `ELTEN_HOST_SOURCE` na katalog zawierający `src/` i `locale/`.
W CI źródła hosta są przypięte do konkretnego commita w workflow testów.
Aktualny pin to `3418d67dea40ee116f4a8ba545b1c409fd04706f` (wydanie 3.0.4).
Wcześniejsze RC1 nie dostarcza wymaganego kontraktu równoległych scen.

```console
ruby test/run.rb --report tmp/test-results.json
```

Runner uruchamia skrypty w osobnych procesach i po błędzie kontynuuje,
zapisując wynik każdego z nich. Domyślny limit to 180 sekund na skrypt;
można go zmienić przez `--timeout`. Błąd, timeout i niezatwierdzone pominięcie
zwracają niezerowy kod. Brak wymaganej zależności nie jest sukcesem.
Katalogi, nazwy lub wzorce plików podane na końcu polecenia ograniczają
zakres do wybranych prób, np. `test/games/spades` albo
`test/transport/game_sync_test.rb test/transport/transport_test.rb`.
Katalogi są przeszukiwane rekurencyjnie, z pominięciem pomocników i fixture.
Układ gier i wspólnych warstw opisuje [docs/TESTING.md](TESTING.md).
`--suite models|transport|ui|native|tooling|integration` wybiera jedną warstwę;
`--list` pokazuje zakres. Nie łącz `--suite` z ręczną listą plików. CI zachowuje
raport również po błędzie. Podczas bieżących porządków obowiązuje zapisane
w `AGENTS.md` ograniczenie do testów dotkniętych zmianą.

## Generatory kodu wykonawczego

```console
ruby tools/compile-rulebooks.rb --check
ruby tools/generate-krowa-nouns.rb --check
ruby test/code_quality_test.rb
```

Zasady pochodzą z `tools/data/rulebooks/*.json`, a lista właścicieli i wyjść z
`tools/rulebook_sources.json`. Kompilator zapisuje tylko
`games/generated/rulebooks/`; nie podmienia metod w utrzymywanym kodzie gry.
Profile plansz Monopoly nadal powstają z bieżących definicji plansz.
Gettext obejmuje generowane reguły. Po zmianie tekstów zaktualizuj katalogi
zgodnie z instrukcją tłumaczeń poniżej.

Kontrola `--check` obu generatorów kończy się błędem przy niezgodności,
bez naprawiania plików.

### Źródło rzeczowników Krowy

Pierwsze 98 178 wierszy `tools/data/krowa_nouns.txt` zachowują dokładny tekst
`GameRoomKrowa::NounData::WORDS` z commita `0c86d03`,
bez sortowania, deduplikacji ani zmiany wyrazów. SHA-256 tekstu UTF-8 z LF:
`5e9e97a7681e662e97527a794846f965a0b789e1f47b3c06c5fc8404490d0389`.
Nie udało się ustalić wejść dawnego `generate_noun_data.ps1`, wskazanego
w nagłówku oryginału. To zachowany stan repozytorium umożliwiający odtworzenie
Ruby, bez rekonstrukcji dawnej selekcji słownika lub zmiany autorstwa i licencji.
TXT i generator pozostają poza instalatorem; runtime używa wygenerowanego Ruby.
Na końcu listy dopisano dziewięć haseł zatwierdzonych przez autora projektu:
łam, zacios, zaciosy, prosię, silnia, silnie, afro, szmat i ksero.
5 października 2026 dopisano następne 60 zatwierdzonych haseł (34 i później
kolejne 26), bez zmiany wcześniejszej kolejności. Aktualny plik zawiera
98 247 wierszy; sprawdzają
to generator i jego test. Dopisanie rzeczownika nie tworzy lokalnej
definicji: objaśnienia są pobierane z SJP dotychczasową ścieżką na żądanie.

## Tłumaczenia interfejsu

Edytuj jeden plik PO na język, np. `locale/PL.po`. Po edycji uruchom
`ruby tools/translations.rb compile PL`, następnie
`ruby tools/translations.rb check PL`. MO i polskie pola dokumentów zasad
powstają z PO. Wpisy historii zmian edytuj w `lib/game_room_changelog.rb`,
a ich tłumaczenia w PO; są wyświetlane bezpośrednio przez aplikację.
Słowniki wyrazów, pytania i karty gier pozostają odrębnymi zasobami.
Pełna instrukcja: `docs/TRANSLATIONS.md`.

Zachowaj płaskie `locale/<LANG>.mo`: natywne buildery zapisują katalogi
jako rekordy języka z dwuliterowym kodem, a runtime w trybie źródłowym
szuka właśnie tej ścieżki. PO/POT nie trafiają do stagingu.
`test/tooling/locale_build_contract_test.rb` sprawdza oba manifesty,
staging oraz faktyczne `build-eltenapp.rb` i `build-eltsetup.rb` z
`ELTEN_HOST_SOURCE`, używając tymczasowej aplikacji z katalogami Game Roomu.
Sprawdza pakiety natywnym czytnikiem i porównuje bajty wszystkich MO.
Nie tworzy wydania gry ani nie używa kluczy podpisujących.
Ten test wymaga również `rubyzip` i `zstd-ruby`, zgodnie z Gemfile hosta;
CI instaluje wersje 3.2.2 i 2.0.6 w zestawie `native`.

Manifest w `__app.rb` musi zachować LF, zgodnie z `.gitattributes`:
parser ELTEN-a 3.0.4 nie akceptuje CRLF przy końcowym `=end Elten3AppInfo`.
Na Windows ograniczony token może dodatkowo zwrócić pusty wynik absolutnego
globu używanego przez builder. Taki wynik oznacza błąd testu, nie poprawny
pakiet; samego istnienia pliku ani sygnatury nie traktujemy jako weryfikacji.

## Uruchomienie ze źródeł

Do testu integracyjnego umieść katalog aplikacji tak, aby `__app.rb` znajdował
się w katalogu programu deweloperskiego ELTEN-a, na przykład
`dev_apps/game_platform/`. Uruchom ELTEN-a ze źródeł lub w trybie debugowania i
otwórz ELTEN Game Room z menu programów.

Używaj oddzielnego profilu testowego, jeśli test może zmieniać dane stołów.
Nie kopiuj profilu, logów ani ustawień MCP do repozytorium.

## Paczka niepodpisana

### Domyślny format nagrań

Wszystkie efekty, głosy, pętle i muzyka w `Audio/` mają format **Ogg Opus,
144 kb/s VBR, 48 kHz, ramki 20 ms**, tryb audio i complexity 10.
Zachowuj oryginalne mono/stereo, poziom głośności, pełne nagranie i metadane.
Nie zwiększaj mono do stereo, nie usuwaj autorstwa i nie normalizuj przy okazji.

```console
ruby tools/encode_audio.rb C:/originals/new-sound.wav C:/src/elten-game-room/Audio/new-sound.opus
```

Narzędzie wymaga FFmpeg z libopus i FFprobe w PATH; można też podać ich
ścieżki jako trzeci i czwarty argument. Odmawia nadpisania istniejącego pliku.
Oryginał zachowaj poza paczką. Do następnego kodowania używaj oryginału,
nie poprzedniej stratnej konwersji. Poprawnego Opusa 144 VBR nie koduj ponownie.
Identyfikator zasobu pozostaje bez rozszerzenia, np. `new-sound`.

Pakowanie nie wykonuje konwersji: odrzuca inne formaty oraz plik tylko
przemianowany na `.opus`. Sprawdza nagłówek Ogg/Opus; bitrate i ramki
zapewnia profil narzędzia, nie samo rozszerzenie. Przed przyjęciem nagrań
sprawdź dekodowanie przez BASS/bassopus ELTEN-a, restart, pętle używane przez
grę, długość, poziomy i odsłuch. Kontrola techniczna nie zastępuje odsłuchu.

Celowany test `ruby test/tooling/mille_audio_continuity_test.rb` wymaga FFmpeg
i FFprobe w PATH. Dekoduje pięć nagrań dystansów, Asa drogi, czerwone światło,
przebicie i ochronę opon, dodatkowy zbiornik, ograniczenie prędkości oraz
koniec ograniczenia i jazdy pod prąd w 1000 mil. Sprawdza różne próbki,
pełne dekodowanie i ciche początki i końce (okna 50 ms co najmniej
20 dB poniżej najgłośniejszego okna). Chroni przed powrotem urwanych pętli
silnika, ale nie ocenia realizmu ani przyjemności odsłuchu.

### Staging instalatora

Paczki buduje narzędzie z repozytorium ELTEN-a, ale nie należy przekazywać
mu całego katalogu projektu. Najpierw przygotuj nowy, nieistniejący katalog
wydania poza repozytorium. Przykład:

```console
ruby C:/src/elten-game-room/tools/stage-release.rb --source C:/src/elten-game-room --destination C:/build/game-room-runtime
ruby C:/src/elten3/tools/build-eltsetup.rb --unsigned C:/build/game-room-runtime C:/build/ELTEN-Game-Room.eltsetup
```

Jawny opt-in `--workspace-staging` pozwala zamiast tego użyć wyłącznie nowego,
bezpośredniego podkatalogu `<source>/Workspace/`. Sam `Workspace` musi już
istnieć i nie może przekierowywać do innego katalogu przez symlink lub junction.
Nie wolno wskazać jego korzenia, zagnieżdżonego podkatalogu ani miejsca poza
tym Workspace, również przez alias z innego katalogu. W repozytorium Git
`git check-ignore` musi potwierdzić ignorowanie
całego `Workspace/`; narzędzie nie zmienia `.gitignore`. Przykład:

```console
ruby tools/stage-release.rb --source D:/Gameroom --destination D:/Gameroom/Workspace/runtime-test --workspace-staging --manifest D:/Gameroom/Workspace/runtime-test-inventory.json
```

Flaga wymaga `--destination`; nie służy do `--check`. Bez niej nadal obowiązuje
staging poza źródłami. Pozostają kontrole kanonicznych ścieżek, nieistniejącego
celu, limitu długości i wykazu poza stagingiem. `Workspace` i jego materiały
pomocnicze nie należą do wykazu plików wykonawczych i nie trafiają do paczki,
także przy kolejnym stagingu z tych samych źródeł.

Ruby używane do budowania musi mieć zależności wymagane przez narzędzie ELTEN-a,
w szczególności `zstd-ruby`. Najprościej użyć środowiska uruchomieniowego
przygotowanego razem ze źródłami ELTEN-a.

## Paczka podpisana

Podpisaną paczkę przygotowuje wyłącznie autor wydania:

```console
ruby C:/src/elten3/tools/build-eltsetup.rb --cert C:/private/author.crt.pem --key C:/private/author.key.pem C:/build/game-room-runtime C:/build/ELTEN-Game-Room-signed.eltsetup
```

Certyfikat i klucz muszą pozostać poza repozytorium. Pliki `.eltsetup` również
nie są śledzone — dystrybucja odbywa się przez katalog programów ELTEN-a.

`tools/support/release_files.rb` jest wspólną listą zawartości wydania. Zachowuje kod,
dane, audio, gotowe tłumaczenia, manifesty, licencje i informacje o źródłach.
Pomija testy, narzędzia, dokumentację roboczą, raporty importu, materiały
redakcyjne i źródłowe katalogi tłumaczeń. Te pliki pozostają w repozytorium.
Skrypt sprawdza zależności Ruby, obecność wymaganych zasobów i zgodność kopii.
Repozytoryjne `tools/stage-release.rb` przygotowuje staging i opcjonalny,
deterministyczny wykaz hashy jako plik obok stagingu:

```console
ruby tools/stage-release.rb --destination C:/build/gr --manifest C:/build/gr-inventory.json
ruby tools/stage-release.rb --source C:/build/gr --manifest C:/build/gr-inventory.json --check
```

Bez `--destination` narzędzie tylko sprawdza źródła i tworzy wskazany wykaz.
Katalog nadrzędny wykazu musi już istnieć. Wykaz musi leżeć poza stagingiem;
kontrola uwzględnia również aliasy wielkości liter na Windows i rozwiązane
ścieżki istniejących katalogów. Niepoprawne granice są odrzucane przed zapisem.
Nie podpisuje, nie instaluje i nie publikuje paczki. Dawny skrypt workspace
`../tools/build-game-room.ps1` jest zewnętrznym udogodnieniem, nie zależnością
odtworzenia stagingu. Na Windows nowy wrapper ogranicza ścieżkę stagingu do
80 znaków. Zbyt długa ścieżka może spowodować
puste wyniki globu narzędzia ELTEN-a; sama poprawna sygnatura nie dowodzi
obecności kodu w paczce.
Podawaj krótki podkatalog, nie sam korzeń dysku (np. `Z:/`): natywny builder
może wtedy zapisać bezwzględne ścieżki zamiast nazw względnych i nie rozpoznać
katalogów tłumaczeń ani dźwięków. Końcowa kontrola zawartości odrzuca taką paczkę.

## Przygotowanie wydania

Główny `README.md` i tłumaczenia `content/readme/{EN,CS,ES,RU}.md` należą do
wymaganych zasobów instalatora. Program odczytuje właściwy plik przez
`asset_path`, według języka interfejsu, po wybraniu README w menu głównym.
Nie twórz drugiej kopii tekstu w kodzie i nie dołączaj całego `docs/`.
Dokumenty są zwykłymi plikami obok kontenera kodu w `.eltsetup`.

1. Wykonaj kontrole zgodnie z zatwierdzonym zakresem. Przy zmianie samego
   pakowania sprawdź `test/tooling/release_files_test.rb` oraz celowane testy binarne,
   w tym `test/tooling/release_binary_loading_test.rb GOTOWA_PACZKA`. Testy i ich
   pomocniki pochodzą z repo; kod produkcyjny musi pochodzić z instalatora.
2. Numer wersji, build i changelog zmieniaj tylko zgodnie z poleceniem autora.
   Ponowne wydanie tego samego buildu nie wymaga nowego wpisu changelogu.
3. Przygotuj staging, zbuduj podpisaną paczkę i zweryfikuj manifesty, runtime,
   podpis autora, dokładną listę plików oraz zgodność każdego pliku ze źródłem.
   Nie maskuj braków danych wczytaniem ich z lokalnego repozytorium.
4. Wykonaj celowane wczytanie gotowej paczki, także danych ładowanych na
   żądanie, zasad, tłumaczeń i wymaganych dźwięków. Nie umieszczaj testów
   w instalatorze tylko po to, żeby przechodziły stare założenia narzędzi.
5. Instalacja, publikacja i wysyłka na GitHub wymagają osobnego polecenia.
