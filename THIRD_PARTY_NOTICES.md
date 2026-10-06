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
