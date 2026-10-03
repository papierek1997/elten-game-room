# Formularze, głośność i pomoc

`F2` zmniejsza, `F3` zwiększa głośność o 10 punktów (0–100%).
`Shift+F2/F3` wybiera poprzednią/następną grupę: wszystkie, gra,
wejście/wyjście, czat, zaproszenia/powiadomienia. Wybrana grupa zaczyna od
„wszystkie” w nowej instancji programu. Poziomy są lokalnie zapamiętywane.
Poziom wszystkich jest mnożnikiem, nie nadpisuje poziomów grup.

Ustawienia pokazują pięć list poziomów 0–100%, bez zdublowanych przełączników.
Dawne wyłączenie kategorii migruje do 0%, włączenie do 100%.
Klawisze w ustawieniach edytują te same wartości robocze: Zapisz zatwierdza,
Anuluj odrzuca. W pozostałych oknach zmiana zapisuje wyłącznie lokalną
głośność. Przy granicy zakresu nie ma zbędnego zapisu.

Zasoby aplikacji są odtwarzane przez jej SoundPool z parametrem `volume`.
Nie zmienia się mowy, konferencji, interfejsu ELTEN-a ani równoległego
odtwarzania dźwięków. Prezentacja powiadomienia ma tylko ścieżkę dźwięku:
adapter odtwarza zasób z głośnością przy odczycie `sound` przez hosta podczas
dostarczenia, po sprawdzeniu wyciszenia i odrzucenia powiadomienia; zwraca nil,
aby host nie odtworzył go drugi raz. Samo mapowanie nie odtwarza dźwięku.

## F1 i rozszerzanie interfejsu

Używaj `GameRoomUI::Form` albo `GameSurfaces::RefreshAwareForm` i przekazuj
`program:` (w układzie współdzielonym ustaw `form.game_room_program`).
Nie twórz nowej własnej obsługi F1/F2/F3 dla gry. Host obsługuje te klawisze
przed zdarzeniami formularza. Jednorazowy most w dyspozytorze QuickActions
przechwytuje tylko F1, F2, F3 i Shift+F2/F3, gdy aktywna kontrolka należy do
czekającego formularza Game Roomu. Nie zapisuje ustawień skrótów ELTEN-a,
nie przechwytuje Ctrl+F1 i nie zmienia źródeł hosta. Nie przechowuje programu
w globalnym mostku. Po wyjściu lub przełączeniu okna zachowanie hosta wraca.

F1 zbiera `GameShortcut` i dynamiczne akcje tego ekranu przez
`GameRoomContextHelp`. Gra, ekran, pomoc kontrolki, historia i głośność to
kolejność listy. Duplikaty są usuwane przy zachowaniu kolejności; wymiana
definicji fazy usuwa stare wpisy. Czat nie dostaje skrótów literowych gry
ani skrótów historii zastępujących normalną edycję tekstu. Lista ma jedną
widoczną kontrolkę; Enter/Escape zamyka, po zamknięciu wraca dotychczasowy
kursor bez rekonstrukcji formularza.

## Pomoc podczas partii

F1, Ctrl+F1 i [samouczek audio](AUDIO_TUTORIAL.md) korzystają ze stosu
pomocy wspólnego formularza. Wejście trafia tylko do jego najwyższego okna;
timery rodzica nadal działają. Odświeżenie zachowuje tekst, kursor i zaznaczenie
pomocy. Wykonawca partii, terminy i prezentacja nadal działają zwykłą ścieżką.
Enter/Escape zamyka pomoc bez wykonania ruchu pod spodem. Zamknięcie gry
sprząta cały stos i audio samouczka. Powierzchnia realtime respektuje
`game_room_background_help?` już w klatce otwierającej pomoc.

## Nawigacja w zasadach

`GameRoomRules::Document` zachowuje sekcje i zwykły tekst, a
`GameRoomRules::View` dodaje natywne elementy nagłówków i łączy do `EditBox`.
Spis treści ma poziom 1, tytuły sekcji poziom 2. H i 1–6 przechodzą między
nagłówkami, K między łączami; Shift odwraca kierunek. Enter na pozycji spisu
przenosi kursor do nagłówka i czyta jego tytuł, bez otwierania przeglądarki.
Zewnętrzne adresy nadal korzystają z obsługi hosta.

Nie parsujemy zasad jako Markdown: znaki w akapitach i przetłumaczonych
tytułach pozostają dosłowne. Dokument bieżących opcji ma jeden nagłówek,
bez spisu. Skróty pozostają listą. Oba tryby pomocy (`wait` i `open_on`)
korzystają z tego samego widoku, także ze snapshotem skrótów podczas gry.
Regresja `test/ui/rules_native_navigation_test.rb` ładuje prawdziwy `EditBox`
z `ELTEN_HOST_SOURCE` i sprawdza wszystkie gry oraz języki interfejsu.

## Historia i opcje

Historia korzysta z `GameRoomHistory::View` oraz `GameRoomHistory.bind`.
`index`/`check` oznaczają pozycje znaków, `entry_index` wskazuje wpis.
Skróty poprzednich lew lub bitew odczytują historycznych autorów, bez zamiany
na nazwy aktualnej obsady.

Ctrl+R czyta `table_options_announcement` oparte na tych samych definicjach
co dokument ustawień. Licznik S planszówki korzysta z
`remaining_piece_counts(replay)` i faktycznej planszy, w kolejności graczy.
Skróty literowe gry nie obowiązują w edytowalnym czacie.

Regresje: `test/ui/volume_and_help_test.rb`, `test/ui/background_help_test.rb`,
`test/ui/background_help_native_test.rb`, `test/ui/background_help_game_screen_test.rb`
oraz testy odpowiedniej powierzchni i gry.
