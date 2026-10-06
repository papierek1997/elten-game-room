# Informacje o składnikach zewnętrznych

## Polski zestaw pytań ogólnych

Od wersji 2.0.4.4 zestaw „Wiedza ogólna” korzysta z PolQA i części 1z10
zbioru MAUPQA (IPI PAN, CC BY-SA 4.0) oraz pytań z archiwum Milionerów
Polsatu, użytych na podstawie potwierdzenia uprawnień przez właściciela
aplikacji. Licencja CC BY-SA nie obejmuje automatycznie tego ostatniego
podzbioru. Autorstwo, źródła, zakres redakcji i warunki poszczególnych
części opisano w `content/QUIZ_PL_GENERAL_SOURCES.txt`.

## Unicode normalization

Katalog `lib/vendor/unicode_normalize/` zawiera implementację normalizacji
Unicode pochodzącą z Ruby, używaną przez Game Room z własnymi tabelami
Unicode 17.0.0. Lokalna adaptacja usuwa wymaganie konkretnej wersji Unicode
hosta i zastępuje niejawne parametry bloków jawnymi, zgodnymi ze starszym
Ruby. Dane normalizacji pozostają bez zmian; nie zmieniamy klasy `Encoding`
w ELTEN-ie ani nie wyłączamy normalizacji znaków.
Odpowiednie informacje licencyjne znajdują się w nagłówkach tych plików oraz w
`LICENSES/RUBY.txt` i `LICENSES/RUBY-BSDL.txt`.

## Statki i Mankala

Gry autorstwa **Dawida Piepera** włączone z jego propozycji dla tego projektu:

- [PR #8 — Statki](https://github.com/papierek1997/elten-game-room/pull/8),
  źródło `f19504ba298eaefff14e86ebfda8c6e37bcf312e`;
- [PR #9 — Mankala](https://github.com/papierek1997/elten-game-room/pull/9),
  źródło `4c847c8beb5eb2dd7e4b6f45af0f7587a6ee72cd`.

Lokalna integracja obejmuje uzgodnione poprawki, polskie tłumaczenia i nowe
instrukcje. Wariant Ayoayo zachowuje reguły autora. Nie jest to deklaracja
scalenia PR-ów na GitHubie.

## Dźwięki

### 1000 mil (Mille Bornes)

Dwadzieścia trzy efekty `Audio/mille_*.opus` wykorzystują nagrania pojazdów,
hamulców, klaksonu, cieczy, powietrza, narzędzi, opony, kolizji oraz sygnał sukcesu
z Freesound, SoundBible i BigSoundBank.
Nie są to dźwięki Playroom ani RS Games. Licencje obejmują tylko wskazane
nagrania, nie wcześniejsze zasoby aplikacji.

Źródłem nagrań z Freesound były publiczne podglądy MP3 HQ, nie bezstratne mastery.
Air Wrench Short pochodzi z udostępnionego przez SoundBible pliku PCM WAV.
Nagrania Asa drogi, hamowania roweru, zwolnienia hamulca ręcznego i kierunkowskazu
pochodzą z pełnych plików WAV/BWF BigSoundBank, nie ze stratnych podglądów.
Całe nagrania przekodowano narzędziem `tools/encode_audio.rb` do Ogg Opus:
144 kb/s VBR, 48 kHz, ramki 20 ms, complexity 10, tryb audio, bez przycinania,
normalizacji, zmiany kanałów lub dodawania warstw. Efekt kolizji ma w grze
wzmocnienie odtwarzania 0,7; pliku nie normalizowano. Kolizja jest nagraniem
efektów fizycznych metalu i szkła przygotowanym przez autora, nie zapisem
rzeczywistego wypadku drogowego. As drogi ma wzmocnienie odtwarzania 0,75,
a Pierwszeństwo przejazdu 0,8. Przejazdy dla 50 i 75 mil mają wzmocnienie 0,35,
100 mil — 0,5, a klucz pneumatyczny do wymiany koła — 0,5;
25 i 200 mil zachowują wzmocnienie 1,0, a błyskawiczna naprawa używa 0,65. Ogranicza to szczyty i różnice głośności
podczas odtwarzania, bez zmiany poziomów zapisanych plików. Nowe hamowanie
ograniczenia prędkości używa 0,35, przebicie opony 0,8, a korek zbiornika
i kierunkowskaz 0,7. Ostatnie dwa nagrania mają niewielkie szczyty powyżej
pełnej skali w dekodowaniu zmiennoprzecinkowym; wzmocnienie odtwarzania
zapobiega ich przesterowaniu bez ponownego kodowania lub normalizacji.
Tankowanie ilustruje nalewanie cieczy do butelki, a spuszczanie paliwa —
odpływanie wody w metalowym zlewie; nie są to nagrania rzeczywistego paliwa.
As drogi korzysta z pełnego nagrania przejeżdżającego i trąbiącego samochodu
z cichym początkiem i końcem, Pierwszeństwo przejazdu z krótkiej
syreny policyjnej, a udana kontra kartą ochronną z muzycznego sygnału sukcesu.
Karty 25, 50 i 75 mil mają trzy różne nagrania ulicznych przejazdów samochodu,
100 mil — przejazd po mokrej drodze, a 200 mil — przejazd wyścigowy Le Mans.
Wykorzystano pełne nagrania z cichymi początkami i końcami, nie fragmenty
pętli obrotów silnika. Nie są to pomiary pięciu prędkości. Ochronę opon
ilustruje zamknięcie zatrzasku walizki ochronnej, nie pompowanie ani przebicie.
Przebicie opony korzysta z osobnego nagrania „PUNCTURE” opisanego przez autora
jako przebicie opony; wymiana koła używa klucza pneumatycznego do śruby,
a naprawa — krótkiego nagrania klucza zapadkowego. Dodatkowy zbiornik
otrzymał zamykanie korka i klapki wlewu (pełne 8,133125 s, bez skracania).
Ograniczenie prędkości ilustruje hamowanie roweru, jego koniec — zwolnienie
hamulca ręcznego samochodu. Jazda pod prąd używa klaksonu, a jej koniec —
kierunkowskazu. Są to odrębne nagrania i umowne skojarzenia z czynnościami,
nie duplikaty dźwięków dystansu, tankowania lub czerwonego światła.
Błyskawiczną naprawę ilustruje pełne, krótkie nagranie wiertarki akumulatorowej;
to metafora szybkiej usługi mechanicznej, nie nagranie wszystkich napraw samochodu.
Kontenery dwóch krótszych efektów (pierwszeństwa i kontry) przepakowano
bezstratnie do stron Ogg po 20 ms dla zgodności z dekoderem BASS ELTEN-a;
pakiety Opus, metadane i próbki dźwięku pozostały niezmienione.

| Plik w aplikacji | Oryginalny tytuł i autor | Źródło | Licencja |
| --- | --- | --- | --- |
| `Audio/mille_accident.opus` | Car Crash (with Glass) — magnuswaker | [Freesound](https://freesound.org/people/magnuswaker/sounds/592388/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_red_light.opus` | Tires Squeaking.aif — RutgerMuller | [Freesound](https://freesound.org/people/RutgerMuller/sounds/104026/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_dirty_trick.opus` | Powerup/success.wav — GabrielAraujo | [Freesound](https://freesound.org/people/GabrielAraujo/sounds/242501/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_distance_25.opus` | Car passing by — Aiwha | [Freesound](https://freesound.org/people/Aiwha/sounds/415483/) | [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/) |
| `Audio/mille_distance_50.opus` | Car Passing — Johnnyfarmer | [Freesound](https://freesound.org/people/Johnnyfarmer/sounds/209767/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_distance_200.opus` | rbh Le Mans passby 05.wav — RHumphries | [Freesound](https://freesound.org/people/RHumphries/sounds/1930/) | [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/) |
| `Audio/mille_distance_75.opus` | Car passing by.wav — hinzebeat | [Freesound](https://freesound.org/people/hinzebeat/sounds/171447/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_driving_ace.opus` | Car Honking at 90 km/h #3 — Joseph SARDIN & Axeline T. | [BigSoundBank](https://bigsoundbank.com/car-honking-at-90-km-h-3-s3438.html), [warunki licencji](https://bigsoundbank.com/licenses.html) | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_fuel_drain.opus` | Drain Gurgling 2.wav — F.M.Audio | [Freesound](https://freesound.org/people/F.M.Audio/sounds/554761/) | [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/) |
| `Audio/mille_distance_100.opus` | Passing Car (Wet road) — Breviceps | [Freesound](https://freesound.org/people/Breviceps/sounds/462862/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_counterflow.opus` | Car Horn.wav — DuranBurrus | [Freesound](https://freesound.org/people/DuranBurrus/sounds/547667/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_puncture_proof.opus` | close-latch-pelicase — Eelke | [Freesound](https://freesound.org/people/Eelke/sounds/387193/) | [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/) |
| `Audio/mille_instant_repair.opus` | power drill — AlaskaRobotics | [Freesound](https://freesound.org/people/AlaskaRobotics/sounds/551504/) | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_refuel.opus` | pour 2 — piotrkier | [Freesound](https://freesound.org/people/piotrkier/sounds/700153/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_right_of_way.opus` | Siren.ogg — egomassive; na podstawie Police Siren Yelp.mp3 — MultiMax2121 | [Freesound](https://freesound.org/people/egomassive/sounds/536773/), [nagranie pierwotne](https://freesound.org/people/MultiMax2121/sounds/156868/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_start.opus` | SFX_Car_Engine_Outside_Start.wav — GiocoSound | [Freesound](https://freesound.org/people/GiocoSound/sounds/401558/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_tire_puncture.opus` | PUNCTURE — SamuelGremaud | [Freesound](https://freesound.org/people/SamuelGremaud/sounds/457442/) | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_extra_tank.opus` | auto gas cap screw back on +lid close.wav — kyles | [Freesound](https://freesound.org/people/kyles/sounds/452546/) | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_speed_limit.opus` | Bike Brake #1 — Joseph SARDIN | [BigSoundBank](https://bigsoundbank.com/bike-brake-1-s1087.html) | [CC0-1.0](https://bigsoundbank.com/licenses.html) |
| `Audio/mille_end_speed_limit.opus` | Handbrake, released #1 — Joseph SARDIN & Axeline T. | [BigSoundBank](https://bigsoundbank.com/handbrake-released-1-s3104.html) | [CC0-1.0](https://bigsoundbank.com/licenses.html) |
| `Audio/mille_end_counterflow.opus` | Car turn signals #3 — Joseph SARDIN & Axeline T. | [BigSoundBank](https://bigsoundbank.com/car-turn-signals-3-s3108.html) | [CC0-1.0](https://bigsoundbank.com/licenses.html) |
| `Audio/mille_wheel_change.opus` | Air Wrench Short — Lightning McQue | [SoundBible](https://soundbible.com/1975-Air-Wrench-Short.html) | [CC-BY-3.0](https://creativecommons.org/licenses/by/3.0/) |
| `Audio/mille_repair.opus` | Ratchet.wav — KenRT | [Freesound](https://freesound.org/people/KenRT/sounds/319996/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |

Pełne teksty licencji: [CC0 1.0](LICENSES/CC0-1.0.txt),
[CC BY 3.0](LICENSES/CC-BY-3.0.txt) oraz [CC BY 4.0](LICENSES/CC-BY-4.0.txt).
Autorzy nie sponsorują aplikacji.
Odnośniki, autorstwo i informację o konwersji należy zachować przy dystrybucji.

### Audio Ball

Przygotowanie `Audio/audio_ball_prepare.opus` pochodzi z nagrania
„auto real older car door close rattly.wav”, **kyles**,
https://freesound.org/s/452549/, licencja **CC0 1.0**,
https://creativecommons.org/publicdomain/zero/1.0/.
Przekodowano dostarczony podgląd Vorbis do Opusa 144 kb/s VBR, 48 kHz,
ramki 20 ms; mono i poziom zachowane, bez przycinania lub zmiany wysokości.

23 września zastąpiono trzy domyślne dźwięki lotu plikami użytkownika:

- `Audio/audio_ball_up.opus` — `Freesound/ball-high.ogg`;
- `Audio/audio_ball_left.opus` — `Freesound/ball-middle.mp3`;
- `Audio/audio_ball_down.opus` — `Freesound/ball-down.ogg`.

Zmiany: miks stereo do mono (0,5 L + 0,5 R, jeśli źródło było stereo),
usunięcie ciszy wyłącznie na brzegach, wyrównanie dynamiki i głośności
względem pakietu Audiodisc, kodowanie Opus 144 kb/s VBR/48 kHz/20 ms,
libopus audio, complexity 10. Bez zmiany wysokości; oryginały nietknięte.

Obok plików użytkownika są informacje o następujących nagraniach:
„Golf Balls Rolling.wav”, **221227**, https://freesound.org/s/655487/,
**CC BY 4.0**, https://creativecommons.org/licenses/by/4.0/;
„Rolling ball”, **ChrisGrundlingh**, https://freesound.org/s/765635/,
**CC0 1.0**, https://creativecommons.org/publicdomain/zero/1.0/;
„Household_Large_Bottle_Roll_02.wav”, **StephenSaldanha**,
https://freesound.org/s/127871/, **CC BY 4.0**,
https://creativecommons.org/licenses/by/4.0/.
Zmienione nazwy plików nie wskazują jednak jednoznacznie tych źródeł;
powiązanie nagrań z autorami/licencjami wymaga potwierdzenia przed publiczną
redystrybucją. Nie przypisujemy im automatycznie licencji poprzednich plików.
Autorzy nie wyrażają tym poparcia dla gry.

### Audio Ball — pakiet Audiodisc i zatrzymanie piłki

Na polecenie użytkownika dodano sześć dostarczonych nagrań z folderu
`audiodisc`: `discUp.ogg`, `discCenter.ogg`, `discDown.ogg`,
`rocketReady.ogg`, `rocketStop.ogg` i `rocketGoal.ogg`. Ich kopie
wykonawcze to `Audio/audio_ball_audiodisc_{up,center,down,ready,stop,goal}.opus`.
Domyślne zatrzymanie piłki `Audio/audio_ball_stopped.opus` pochodzi
z dostarczonego pliku `Freesound/ball-stopped.ogg`.

Przekodowano Vorbis do Ogg Opus, 144 kb/s VBR, 48 kHz, ramki 20 ms,
libopus audio, complexity 10. Zachowano stereo i dostępne metadane;
bez normalizacji, zmiany wzmocnienia ani wysokości. Następnie na polecenie
użytkownika przycięto wyłącznie ciszę brzegową domyślnego zatrzymania piłki:
około 196 ms z początku i 39 ms z końca, z marginesem 2 ms. Dźwięków
Audiodisca nie przycinano. Oryginały pozostają niezmienione poza repozytorium.

Do tych siedmiu plików nie dostarczono identyfikatorów źródeł ani
informacji o autorach/licencjach. Pochodzenie folderu nie potwierdza
licencji CC0 ani prawa do publicznej redystrybucji. Nie obejmujemy ich
licencją kodu aplikacji; uprawnienia trzeba potwierdzić przed publikacją.
Mapowanie zasobów opisuje [AUDIO_BALL.md](docs/AUDIO_BALL.md).

### Wcześniejsze zasoby

21 września 2026 r. ujednolicono wszystkie 123 nagrania do Ogg Opus
144 kb/s VBR (48 kHz, ramki 20 ms, libopus audio, complexity 10).
Trzy podkłady Krowy miały już te parametry; pozostałe 120 plików
przekodowano z dotychczasowych źródeł WAV/Vorbis, nie przez zmianę
samego rozszerzenia. Zachowano mono/stereo, informacje o autorach
i pozostałe dostępne metadane, bez normalizacji głośności i przycinania.
Powielony rok i pełną datę w niektórych WAV-ach reprezentuje pełna data.
Oryginały zachowano poza dystrybucją. Konwersja stratna nie nadaje
nowych praw do nagrań i nie gwarantuje identycznego brzmienia.

Większość plików w katalogu `Audio/` pochodzi z opublikowanego buildu 176.
Dźwięki `connect.opus` i `disconnect.opus` zostały później zastąpione, a
`chatmsg.opus` dodany z dostarczonego przez autora zestawu dźwięków. Repozytorium
nie zawiera osobnego dokumentu potwierdzającego pierwotne źródło i licencję
tych plików. Przed objęciem zasobów jednolitą licencją należy uzupełnić tę
informację albo zastąpić je dźwiękami o jednoznacznej licencji.

Plik `hit1.opus`, używany przy skompletowaniu grupy w Monopoly, oraz plik
`notice.opus`, używany przez powiadomienia Game Roomu, pochodzą z dostarczonego
zestawu Quentin Playroom. Dla tych plików również nie ma w repozytorium
osobnego potwierdzenia licencji.

### Powiadomienie o nowym stole

`Audio/table_notice.opus` — [Menu Dual Click](https://freesound.org/s/145440/)
autorstwa **Soughtaftersounds / Varazuvi**, dostarczony z informacją o licencji
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
Informacja wskazana przez autora: **Copyright © 2011 Varazuvi™ www.varazuvi.com**.

Źródło: Freesound `145440_Menu Dual Click_preview-hq-ogg.ogg`, pobrane
23 września 2026 r. Na polecenie użytkownika zwiększono poziom o **9,6 dB**,
aby zbliżyć zmierzoną głośność do `notice`, i przekodowano do Ogg Opus
144 kb/s VBR, 48 kHz, ramki 20 ms, zachowując stereo i pełne nagranie.
Nie stosowano kompresji dynamiki ani ogranicznika; oryginał pozostał bez zmian.
Dźwięk dotyczy nowych stołów, a zaproszenia nadal używają `notice.opus`.

### Błędna odpowiedź w quizie

`Audio/quiz_wrong_answer.opus` — [Dat's Wrong!](https://freesound.org/s/587253/)
autorstwa **Beetlemuse**, na licencji
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
Nagranie dostarczył użytkownik jako
`587253_Dat's Wrong!_preview-hq-ogg.ogg` wraz z informacją licencyjną.
6 października 2026 r. przekodowano je do Ogg Opus 144 kb/s VBR, 48 kHz,
ramki 20 ms, zachowując pełne nagranie, kanały i metadane. Na polecenie
użytkownika ściszono nagranie o 10% (mnożnik amplitudy 0,9).
Oryginału nie zmieniono. Licencja tego dźwięku nie jest licencją kodu gry.

### Cat, head, tail

Gra i jej pierwotna implementacja zostały dostarczone przez **TD Programs**
(konto `td-programs`) w [PR #12](https://github.com/papierek1997/elten-game-room/pull/12),
commit `7930486d9051e557b36d392af558139921fda606`. Autor wskazuje inspirację
grą Pig z RS Games. Integracja zachowuje punktowanie autora; dopracowano
opis zasad PL/EN, decyzję bota przy zabezpieczonym remisie oraz interfejs D.

Pięć dostarczonych nagrań `Audio/cht-*.opus` zachowano bez zmiany bajtów
i bez ponownej konwersji. Zgłoszenie nie zawiera informacji o pierwotnym
źródle ani osobnych warunkach licencyjnych nagrań. Przed publiczną
dystrybucją należy uzyskać te informacje od autora; nie przypisuje się
im automatycznie licencji kodu ani nie zakłada naruszenia praw.

### Dźwięki kostek Domino i Mexican Train

Trzy nagrania autora **poenia**, dostarczone przez użytkownika wraz z
informacją o licencji [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/):

- `Audio/domino_refill.opus` — [Domino_sfx_refillPlayers](https://freesound.org/s/745031/), rozdawanie kostek;
- `Audio/domino_move_tile.opus` — [Domino_sfx_moveTile](https://freesound.org/s/745028/), zagranie kostki;
- `Audio/domino_take_chip.opus` — [Domino_sfx_takeChip](https://freesound.org/s/745032/), dobranie ze stosu.

Źródłem są pliki Freesound `preview-hq-ogg`, pobrane 18 września 2026 r.
Pierwotnie zmieniono tylko nazwy; następnie wykonano opisaną wyżej konwersję.

### Ponowne tasowanie kart

`Audio/card-shuffle.opus` — [Card Shuffle](https://freesound.org/s/201253/)
autorstwa **empraetorius**, na licencji
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
Użytkownik dostarczył plik Freesound `preview-hq-ogg` wraz z informacją
licencyjną, pobrany 18 września 2026 r. Pierwotnie zmieniono wyłącznie nazwę;
21 września przekodowano nagranie do Opusa według powyższych parametrów.

### Dodatkowe kroki debla i brzęczyk UNO

`Audio/pong_move_double.opus` pochodzi z dostarczonego przez użytkownika
pliku `pong-move-double.ogg` z jego katalogu Freesound.
`Audio/buzzer.opus` pochodzi z dostarczonego zestawu Quentin Playroom.
21 września 2026 r. przekodowano je do Opusa 144 kb/s VBR, 48 kHz,
z ramkami 20 ms, zachowując mono, metadane i poziomy, bez przycinania.
Oryginały pozostają poza dystrybucją. Nie potwierdzono odrębnych licencji
tych nagrań; nie przypisuje się im na tej podstawie licencji całego projektu.

### Nowe dźwięki Statków

Użytkownik dostarczył z własnego katalogu Freesound pliki `hit_ship1.ogg`,
`hit_ship2.ogg`, `rocket_launch1.ogg`, `rocket_launch2.ogg`, `rocket_launch3.ogg`
i `rocket_miss.ogg`. Początkowo zachowano ich nazwy i zawartość bez przekodowania;
obecne odpowiedniki mają rozszerzenie `.opus` i parametry opisane wyżej.
Nie dodawano niedostarczonego `hit_ship3.ogg`. Wśród materiałów użytkownika
są informacje licencyjne nagrań, ale nie potwierdzono jednoznacznego
przyporządkowania oryginalnych nazw do tych sześciu przemianowanych plików.
Nie przypisuje się im na tej podstawie jednej wspólnej licencji.

### Krowa — słownik i nagrania

Gra Krowa została dostarczona przez **paulinux** w PR #10 z konta GitHub
`paoscripts` (commit `50ea3081e6d6e7a59ee63eee8b7809cb643d7e50`). Bazę
rzeczowników oraz osiem nagrań `Audio/krowa-*` pierwotnie zachowano bez zmiany bajtów.
21 września 2026 r., na polecenie użytkownika, trzy podkłady muzyczne
`krowa-single`, `krowa-race` i `krowa-word-tower` przekodowano do Opusa
144 kb/s VBR stereo (48 kHz, ramki 20 ms), bez filtrów zmiany głośności. Ostatni plik
zmienił rozszerzenie z `.mp3` na `.opus`. Następnie również pięć efektów
przekodowano do tego formatu, zachowując ich liczbę kanałów; muzyki nie
kodowano ponownie. Bazy nie zmieniano. Oryginały zachowano poza dystrybucją.
Metadane podkładu Wieży słów wskazują utwór „Once Again”, Moavii, 2024,
wydawca „Free To Use Music”; zachowano je w pliku Opus. Nie zastępują
one informacji o warunkach licencyjnych.
Nie usuwano powtórzeń ani nie zmieniano kolejności słów. Zgłoszenie nie
podaje pełnego pochodzenia bazy i warunków dystrybucji nagrań; przed
publicznym rozpowszechnieniem należy uzyskać te informacje od autora.
Brak informacji nie jest stwierdzeniem naruszenia ani przypisaniem tym
zasobom licencji całego repozytorium. Definicje wyświetlane na żądanie
pochodzą z serwisu SJP.pl i wskazują to źródło w oknie.
