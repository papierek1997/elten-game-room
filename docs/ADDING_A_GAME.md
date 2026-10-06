# Dodawanie gry

## 1. Wybierz istniejący model

Najpierw sprawdź wspólne klasy. Gra planszowa z ruchem figura–pole powinna
dziedziczyć po `GameRoomGames::TurnBasedBoardGame`. Inne gry dziedziczą po
`GameRoomGames::Base`, ale nadal korzystają z `GameSurfaces`, układu, skrótów,
historii, punktacji, rund i botów.

Nie twórz nowej warstwy tylko dlatego, że jedna gra potrzebuje dodatkowej
akcji. Najpierw spróbuj rozszerzyć specyfikację powierzchni albo dodać mały,
wielokrotnego użytku element do istniejącego szkieletu.

## 2. Zaimplementuj model

Utwórz plik `games/<id>.rb` i zaimplementuj co najmniej:

- `id`, `name` i `rule_sections`;
- `minimum_players` i `maximum_players`;
- `option_definitions`, jeśli gra ma warianty;
- zdarzenia rozpoczynające partię;
- `replay`, który deterministycznie odtwarza stan;
- `surface_spec`, który opisuje dostępny interfejs;
- `action_for`, który sprawdza kolej, rodzaj akcji i wszystkie reguły;
- czytelne wpisy historii i komunikaty błędów.

Zdarzenie powinno zawierać dane konieczne do odtworzenia ruchu, ale nie dane,
które można bezpiecznie wyliczyć ze stanu. Prywatne informacje, takie jak ręce
kart albo odpowiedzi przed ujawnieniem, muszą korzystać z istniejących
mechanizmów ukrytych danych.

## 3. Podłącz wspólny interfejs

Wybierz właściwą powierzchnię z `lib/game_surfaces/`:

- `piece_board` dla planszy z figurami;
- `pawn_track` dla toru pionków;
- `dice_tray` dla kości;
- powierzchnię kart dla ręki i stosu;
- `answer_sheet` albo `review_surface` dla odpowiedzi i oceniania;
- `command_panel` dla niewielkiego zestawu poleceń.

Historia, lista użytkowników, pomoc F1, zasady Ctrl+F1 i ogólny układ ekranu są
wspólne. Skróty charakterystyczne dla rodziny gry dodawaj do wspólnego
szkieletu tylko wtedy, gdy ich znaczenie jest rzeczywiście takie samo.

### Wyszukiwanie grywalnych kart

Rzeczywista ręka karciana powinna implementować `playable_card_navigation` i
zwracać `card_navigation_spec`. Specyfikacja podaje identyfikator kontrolki ręki
oraz grupuje wszystkie aktualnie legalne akcje według stabilnego identyfikatora
fizycznej karty. Nie wolno grupować według opisu ruchu: as liczony jako 1 lub 11
to jedna karta z dwoma sposobami użycia.

Wspólna warstwa dodaje `Z` i `Shift+Z`, przechodzi cyklicznie po wskazanych
kartach i wypowiada nową pozycję bez odświeżania formularza i bez sieci. Gra
podaje też zbiór kart dopuszczonych do automatycznego ruchu. Ruch zostanie
wykonany tylko przy dokładnie jednej grywalnej fizycznej karcie, dokładnie jednej
legalnej akcji oraz jawnej zgodzie gry. W przeciwnym razie zmienia się wyłącznie
kursor.

Nie zezwalaj na automatyczny ruch, jeżeli po karcie pozostaje wybór koloru,
celu, wartości, meldunku, deklaracji albo pakietu. W fazach, w których pomoc nie
ma sensu lub dawałaby przewagę w wyścigu reakcji, zwracaj `nil`. Samo wskazanie
karty nie może omijać `action_for`, zmieniać stanu ani wysyłać żądania.

Sama kontrolka obsługująca paczki nie jest powodem wyłączenia automatycznego
zagrania. Jeżeli reprezentuje zwykłą pojedynczą kartę jako jednoelementową
tablicę, sprawdź rzeczywiste alternatywy legalnego ruchu. Makao blokuje automat
przy możliwości zagrania kilku kart razem albo wyborze deklaracji; zwykłą,
jedyną grywalną kartę bez tych alternatyw może zagrać automatycznie.
Nawigacja Z/Shift+Z odczytuje wyłącznie wskazaną kartę, bez nagłówka ręki.

## 4. Dodaj bota opcjonalnie

Ustaw `supports_bots?`, wystaw pełną listę legalnych akcji i zarejestruj
strategię. Bot może używać heurystyk lub przeszukiwania, ale wybrana akcja musi
wrócić do zwykłego `action_for`; strategia nie może sama dopisywać zdarzeń.

Gra turowa pozostawia `session_runner? == true`: wspólny
`GameRoomSessionRunner` planuje, sprawdza aktualność i zapisuje decyzję.
Nie dodawaj drugiego wykonawcy do `GameScreen` ani kontrolki gry.
Gra realtime wyłącza ten runner tylko wtedy, gdy jej klient ma własną
pętlę fizyki i botów; automatyczny zapis punktu nadal przechodzi zwykłą
granicą zatwierdzania akcji. Narzędzia treningowe i raporty trzymaj w `tools/`,
nie w bibliotekach ładowanych przez zainstalowaną grę.

Sprawdź osobno:

- brak legalnego ruchu;
- koniec rundy i koniec partii;
- kilka botów wykonujących kolejne ruchy;
- informację niepełną i pełną, jeśli gra ma wariant bota „oracle”.

## 5. Zarejestruj grę

Dodaj `require_relative` oraz klasę do `GameRoomGames::CATALOG` w
`games/catalog.rb`. `__app.rb` korzysta z tego samego katalogu przez
`GAME_REGISTRY`. Rejestr wywołuje `rule_book`, dlatego brak zasad zostanie
wykryty przy starcie.

## Tłumaczenia interfejsu i zasad

Angielskie komunikaty oznaczaj `_`, `n_`, `p_` lub `np_`, a w głównym module
pliku włącz `using GameRoomLocalization::Translations`. Zasady mają osobną
strukturę angielską w `tools/data/rulebooks` i przypisanie opcji do rozdziałów
w `tools/rulebook_option_chapters.json`; generuj je przez
`ruby tools/compile-rulebooks.rb`. Następnie `ruby tools/translations.rb update`
dopisze wiadomości do katalogów. Tłumacz edytuje wyłącznie `locale/PL.po`
lub PO innego języka; `compile PL` tworzy MO oraz polskie widoki zgodności.
Nie dodawaj nowych ręcznie utrzymywanych fragmentów tłumaczeń JSON.
Szczegóły: `docs/TRANSLATIONS.md`.

## 6. Napisz testy

Minimalny zestaw obejmuje:

- prawidłowy start dla skrajnych liczb graczy;
- legalny i nielegalny ruch;
- pełne zakończenie partii;
- deterministyczny replay;
- powierzchnię i podstawowe skróty;
- oba kierunki wyszukiwania grywalnych kart, brak ruchu, zawijanie listy oraz
  przypadek jednej i wielu akcji tej samej fizycznej karty;
- bota, jeśli jest obsługiwany;
- regresję dla każdego naprawianego błędu.

Na końcu uruchom `ruby test/run.rb`.
