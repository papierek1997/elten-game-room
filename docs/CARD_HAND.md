# Ręka kart

Kontrakt dotyczy tylko oznaczonych kontrolek rzeczywistej ręki. Plansze,
kości, listy akcji i pozostałe listy zachowują własną nawigację.

## Zachowanie

- Po zagraniu karty: najbliższa pozostała karta powyżej. Jeśli nie ma takiej,
  następna poniżej. Dla A B C D: zagranie D wybiera C, B wybiera A, A wybiera B.
- Po zagraniu pakietu pomijane są wszystkie usunięte karty.
- Dobranie ma pierwszeństwo przed zagraniem w tej samej aktualizacji; wybierana
  jest ostatnia faktycznie otrzymana karta, nie ostatnia według sortowania.
- Bez jawnie wybranego sortowania zachowany jest porządek pozostałej ręki,
  a nowe karty są dopisywane na dole. Sortowanie UNO pozostaje aktywne.
- Odczyt dotyczy tożsamości nowej karty pod kursorem. Nie dodaje etykiety
  „dobrano”; obejmuje też zmianę na inną kartę o identycznej nazwie.
- Niezmieniona ręka, ruch innej osoby i techniczne odświeżenie nie powtarzają
  odczytu. Gdy aktywny jest czat, historia albo inne pole, nie ma odczytu ręki,
  przejęcia fokusu ani zaległego komunikatu po powrocie do ręki.
- Nowe rozdanie nie jest traktowane jak dobieranie. Przygotowany pakiet lub
  wybór sposobu zagrania nie przechodzą do następnego rozdania.
- Zwykła aktualizacja ręki zachowuje istniejącą listę i formularz. Faktyczne
  przejścia faz zachowują dotychczasowe znaczenie i obsługę końca partii.
- `Z` przechodzi cyklicznie do następnej obecnie grywalnej karty, a `Shift+Z`
  do poprzedniej. Karta pod kursorem jest wypowiadana bez odbudowy formularza i
  bez żądania sieciowego. Brak takiej karty daje krótki komunikat.
- Jeżeli istnieje dokładnie jedna grywalna fizyczna karta, dokładnie jedna jej
  legalna akcja i gra jawnie zezwala na automatyzację, skrót wykonuje tę samą
  akcję co Enter przez zwykłe `action_for`. Kilka sposobów użycia tej samej
  karty zawsze oznacza jedynie ustawienie kursora.

W 1000 mil przy dokładnie dwóch graczach grywalny atak ma jednoznacznego
przeciwnika: Enter pomija listę celu, a nawigacja może automatycznie zagrać
jedyną grywalną kartę zgodnie z powyższą zasadą. W większej obsadzie wybór
celu pozostaje jawny, także gdy aktualnie tylko jeden przeciwnik jest podatny
na atak. Nie dotyczy to wyboru problemu dla błyskawicznej naprawy ani
potwierdzenia odrzucenia karty. Każdy ruch nadal przechodzi bieżące `action_for`.

## Nowe gry

Logika jest raz w `lib/game_surfaces/card_hand_cursor.rb`. CardTable i
PacketCardSurface używają jej wspólnie. Nowa gra korzysta z tych kontrolek
(lub pomocnika `CardGame#card_hand_surface`) i podaje:

- unikalne, stabilne `Card#id` dla fizycznych kart, także duplikatów;
- `hand_order`: identyfikatory w rzeczywistej kolejności ręki, z dobranymi
  kartami dopisanymi na końcu, niezależnie od prezentowanego sortowania;
- `hand_epoch`: tożsamość właściciela i rozdania, zmieniana przy nowym rozdaniu;
- normalne etykiety, wartości akcji i ewentualne klucze sortowania.
- `playable_card_navigation` z `card_navigation_spec`: identyfikator ręki,
  legalne akcje pogrupowane według fizycznego `Card#id` oraz karty, dla których
  pojedynczy, jednoznaczny ruch może zostać wykonany automatycznie.

Nie trzeba kopiować sterowania kursorem, odczytu ani obsługi odświeżenia.
`hand_order: nil` oznacza zwykłą kontrolkę poza tym mechanizmem. Na przyszłość
nie oznaczać nim talii publicznej, list akcji lub kości. Zmiana samego właściciela
oglądanej ręki także wymaga innego `hand_epoch`.

Gra nie może oznaczyć jako automatycznej karty wymagającej późniejszego wyboru,
meldunku, deklaracji, celu lub utworzenia pakietu. W takich sytuacjach wspólny
mechanizm jedynie ustawia kursor. UNO wyłącza tę funkcję całkowicie przy
Straights, Interceptions, Super interceptions i Buzzer cards. Pokerowe
zaznaczanie kart do wymiany i Monopoly nie są nawigacją legalnych zagrań.

Adnotacje istnieją w UNO, Ninety-Nine, Spades, Tysiącu, Makao i ręce do wymiany
w Pokerze. Poker nadal przechodzi po potwierdzeniu wymiany do następnej fazy:
nie dodano nowej listy ręki do licytacji ani automatycznego czytania kart w menu
zakładów. Widok końcowy również nie jest nadpisywany odczytem ręki.

GameRoomLayout ponownie wykorzystuje tylko oznaczoną rękę, także przy
otaczających ją dodatkowych polach. GameScreen kolejkuje komunikat wybranej
karty bez przerywania wcześniej ogłoszonych zdarzeń. Pozostałe powierzchnie
nie zwracają takiego komunikatu i korzystają z dotychczasowej ścieżki.

Ręczne sortowanie deklaruje `hand_sorting_available?` oraz wspólne
`hand_sort_shortcuts`. Karty dostarczają semantyczne `sort_keys` dla
colour/number/none. Sortowanie widoku nie zmienia stanu partii, kolejności
zaznaczania pakietu ani domyślnego układu. Fizyczne ID i kursor pozostają stabilne.

## Potwierdzanie akcji karty

Opcjonalne `Card#confirmation` podaje gotowe pytanie przed zwykłą akcją Entera.
Brak pytania zachowuje dotychczasowe zachowanie pozostałych karcianek.
Potwierdzenie korzysta z `GameRoomUI::Form` z właścicielem `program:`, domyślnym
wyborem „Nie” i anulowaniem przez Escape. Wybór przeciwnika nadal jest osobnym
etapem; nie zastępuje się go potwierdzeniem odrzucenia.

Skrót typu `:surface` może wywołać `selected_card_action`, przekazując
`hand_id`, mapę `actions` według fizycznych ID, szablon `confirmation`
z polem `%{card}` oraz identyfikator `shortcut`. Wspólna powierzchnia ustala
kartę pod kursorem po sortowaniu, a nie po jej etykiecie. Przy otwartym
wyborze celu wymaga jego ukończenia lub anulowania. Po potwierdzeniu zwraca
jedną akcję do normalnej ścieżki ekranu, nie emituje jej drugi raz.

Gra deklaruje wyłącznie legalne akcje i nie traktuje potwierdzenia jako
uprawnienia do zapisu: aktualna rewizja, wykonawca i `action_for` nadal
podlegają ponownej walidacji. W 1000 mil Enter proponuje odrzucenie tylko
niegrywalnej karty, którą wolno odrzucić w tej fazie; J pozwala świadomie
odrzucić również grywalną kartę. Nie zmienia to nawigacji Z ani modeli innych gier.

Regresje: `test/ui/card_hand_cursor_test.rb`, `test/ui/card_actions_test.rb`,
`test/games/uno/sort_order_test.rb` i testy dotkniętej karcianki.
