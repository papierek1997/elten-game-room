# Prywatne odpowiedzi i zapis partii

## Lokalne zobowiązania odpowiedzi

`ProgramStorage` pomija zapis niezmienionego stanu, także ponowne `discard`
po usunięciu wpisu. Transakcja odczyt–modyfikacja–zapis jest koordynowana
między ekranami. Zwykły plik to `hidden_submissions.json`; przy błędzie I/O
magazyn próbuje `hidden_submissions.json.recovery.json` w tym samym prywatnym
katalogu aplikacji. Host ustala i sprawdza ścieżkę raz na plik w danej
wczytanej aplikacji. Kolejne odczyty i zapisy używają tej ścieżki bez ponownego
rozpakowywania instalatora. Zawartość pliku nie jest buforowana. Zapis powstaje
w pliku tymczasowym i zastępuje docelowy plik dopiero po zamknięciu zapisu,
tak samo jak w natywnym magazynie hosta.

Snapshot zawiera rosnące `storage_revision`. Odczyt wybiera najnowszy kompletny
stan, więc stary plik główny nie cofa usunięcia potwierdzonego w kopii awaryjnej.
Kolejny udany zapis główny zastępuje starszą kopię. Plik bez rewizji ma rewizję 0.
Nie usuwaj ani nie skracaj oryginału, aby wymusić podmianę.

Nowa odpowiedź trafia do gry dopiero po trwałym zapisie. Poprzednie wersje
i nonce pozostają dostępne dla już zaakceptowanego zobowiązania. Awaria obu
ścieżek przygotowania zwraca kontrolowany błąd bez planu zdarzenia. Błąd
sprzątania zwraca `false`, zamiast przerywać postęp gry; lokalny wpis może
pozostać do następnej udanej próby. Po podwójnej awarii zapis ma sekundę
backoffu i jedno ostrzeżenie do odzyskania, bez usypiania ani nowej pętli.

Koordynacja obejmuje instancje tego samego natywnego Programu współdzielące
plik w procesie. Oddzielne procesy ELTEN-a zapisujące do jednego profilu
nie są wspieranym układem wielu autorów. Format lokalnego magazynu nie
zmienia protokołu commit/reveal ani rozstrzygnięć partii.

## Granice zmiany stołu i obsady

Przekazanie gospodarza, zastępstwo gracza i opuszczenie stołu ponownie
sprawdzają prywatną fazę na granicy zapisu, także po dialogu wyboru osoby.
Zastępstwo rozróżnia sekret tej osoby od cudzych oczekujących zobowiązań.
Przyjęcie zaproszenia korzysta z tej samej ochrony co zwykłe wyjście.

## Archiwum konta

`AccountSavedGames` zapisuje standardową historię przez prywatne pliki
konta. `saved_game_schema_version` wersjonuje format. Gra określa
`save_game_error` dla niebezpiecznych faz albo wyłącza zapis przez
`supports_saved_games?`. Nazwy kontrolerów w konkretnych polach zdarzeń
odtwarza `restored_event_value`; nie zastępuj dowolnych tekstów historii.

Zamknięcie stołu i zastąpienie uczestników wymaga potwierdzonego zapisu
archiwum. Niepewny wynik zachowuje zamrożenie. Cofnięcie zamrożenia
wymaga tej samej partii, aktualnego gospodarza i potwierdzenia własnej
granicy zapisu; nie odblokowuje nowszej operacji.

Regresje magazynu odpowiedzi i archiwum znajdują się w `test/persistence/`;
scenariusze prywatnych faz także w testach Quizu, Państw-miast i Statków.
