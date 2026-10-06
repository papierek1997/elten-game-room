# Dokumentacja

## Dla graczy

- [Power Games — przewodnik po programie](../README.md): pierwsze kroki,
  stoły, zaproszenia, widget, ustawienia, zapis partii i najważniejsze skróty.

## Planowane poprawki

- [Nowy plan poprawek Game Roomu](NEXT_FIXES_PLAN.md):
  zakres do wdrożenia i oznaczone kwestie do doprecyzowania.

## Utrzymanie

- [Architektura](ARCHITECTURE.md): przepływ danych, warstwy i ich właściciele.
- [API hosta](HOST_API.md): kontrakt finalnego ELTEN-a 3.0.4.
- [Budowanie](BUILDING.md): zależności, testy, generatory i staging.
- [Dodawanie gry](ADDING_A_GAME.md): integracja modelu, UI, treści i botów.
- [Własność snapshotów](SNAPSHOT_OWNERSHIP.md) i [benchmarki](BENCHMARKS.md).
- [Narzędzia](TOOLS.md), [testy](TESTING.md)
  i [tłumaczenia](TRANSLATIONS.md): bieżące polecenia i układ katalogów.
- [Trening botów](BOT_TRAINING.md): ocena strategii i obsługa narzędzi Spades.

## Kontrakty funkcji

- [Formularze i pomoc](UI.md), [ręka kart](CARD_HAND.md)
  i [samouczek audio](AUDIO_TUTORIAL.md).
- [Wykonanie i prezentacja w tle](BACKGROUND_GAME_EXECUTION.md).
- [Realtime](REALTIME.md) i [Audio Ball](AUDIO_BALL.md).
- [Prywatne odpowiedzi i zapis partii](PRIVATE_STATE.md).
- [Drużyny, role i fokus](TEAMS_ROLES_AND_FOCUS.md).
- [Języki interfejsu](INTERFACE_LANGUAGES.md).
- [Statystyki](STATISTICS.md) i ich [fragment schematu](STATISTICS_TABLES.json).
- [Pochodzenie i ograniczenia plansz Monopoly](MONOPOLY_REGIONAL_BOARDS.md).

## Utrzymywane treści

[Zasady redakcji pytań quizowych](QUIZ_EDITORIAL.md) są obowiązkowe przy
tworzeniu, imporcie, rozbudowie i tłumaczeniu zestawów. Obejmują naturalny
język, źródła, trzy wiarygodne błędne odpowiedzi, powtórzenia oraz przegląd
każdej pozycji, ze wskazówkami dla polskiego, angielskiego, czeskiego,
hiszpańskiego, rosyjskiego i kolejnych języków.

[tools/data/rulebooks/](../tools/data/rulebooks/) zawiera źródła zasad dla
kompilatora `tools/compile-rulebooks.rb`. Gra ładuje wygenerowane Ruby
z `games/generated/rulebooks/` oraz tłumaczenia MO; JSON pozostaje poza paczką.
Polskie teksty źródeł są odświeżane z PO; procedurę opisuje
[docs/TRANSLATIONS.md](TRANSLATIONS.md).

Historia zmian aplikacji ma jedno źródło:
[game_room_changelog.rb](../lib/game_room_changelog.rb), tłumaczone przez PO/MO
i wyświetlane w „Co nowego”. Nie utrzymujemy osobnych kopii Markdown wydań.

[Czytelne pytania quizu](quiz-questions/) są eksportem z `content/` na potrzeby
redakcji. Gra czyta zestawy Ruby w `content/`; TXT nie są jej źródłem danych.
Każdy TXT odpowiada zestawowi i zawiera numer, pytanie, odpowiedzi
A–D oraz wskazanie poprawnej odpowiedzi, bez technicznych ID. Numeracja zaczyna
się od 1 w każdym zestawie; kolejność odpowiedzi jest stała i może różnić się
od partii. Zestaw „Wiedźmin — książki” zastępuje wszystkie dawne zestawy
Wiedźmina; nie obejmuje gier ani ekranizacji. Aby zgłosić błąd, podaj
nazwę zestawu i treść pytania. Edytuj dane w `content/`, następnie uruchom:

```console
ruby tools/export-quiz-text.rb
ruby tools/export-quiz-text.rb --check
```

Eksporty mają UTF-8, zachowują pochodzenie i licencje zestawów; nie trafiają
do instalatora. Polecenie `--check` sprawdza aktualność bez zapisu.

Raporty testów, audytów, pomiarów i jednorazowych eksperymentów zapisuj
w ignorowanym `tmp/` albo poza repozytorium. Historię zmian zachowuje Git;
bieżące kontrakty aktualizuj w dokumentach powyżej.
