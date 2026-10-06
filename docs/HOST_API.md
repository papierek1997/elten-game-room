# Integracja z ELTEN-em 3.0.4

Wymagane API pochodzi z finalnego tagu `3.0.4`, commit
`3418d67dea40ee116f4a8ba545b1c409fd04706f`. Testy natywne używają jednego
`ELTEN_HOST_SOURCE` wskazującego zgodny checkout. API 3.0.5 RC 1 nie jest
podstawą tej integracji. Polecenia: [BUILDING.md](BUILDING.md).

## Adaptery natywnych usług

1. `GameRoomClock` czyta publiczny `EltenAPI::ServerClock`, bez własnego
   HTTP, odświeżania, retry i kotwicy zegara. Adapter zachowuje wynik liczbowy
   oraz `ClockUnavailable`, gdy host nie ma próbki. Nie wymusza synchronizacji
   prywatnymi metodami hosta. Zegar powiadomień również tylko deleguje;
   ustawienia subskrypcji mogą załadować się przed pierwszą próbką, a wysyłka
   i prezentacja czekają na gotowość. Przeliczenie epoki i zamrożenia partii
   pozostaje w `GameRoomSessionClock`.
2. Cichy powrót formularza używa natywnych `resume_for_refresh` i
   `wait_without_announcement`. Usuwa własny znacznik pomijania fokusu,
   aby pierwszy ręczny ruch po odświeżeniu był odczytany.
3. Skróty i menu kontekstowe ekranu należą do `FormBindings`. Kolejne wiązanie
   usuwa rejestracje poprzedniego ekranu, bez proxy gromadzących callbacki.
   Wewnętrzne handlery kontrolki i timer klienta realtime zachowują swoich
   właścicieli. Reset podczas callbacku nie uruchamia już usuniętych handlerów.
4. Krótkie operacje `GameRoomBackground::Work` wykonuje `Tasks.start`.
   Adapter zachowuje jednorazowy wynik `[wartość, błąd]`, zajętość także dla
   nieodebranego wyniku i powiązanie z runtime. Host dopuszcza cztery żywe
   zadania na UUID; kolejka aplikacji mieści do 128 oczekujących operacji,
   dopuszczanych FIFO w obrębie tego UUID. Obsługują ją istniejące aktualizacje
   właścicieli, bez nowego wątku, timera czy pollingu. Zamknięcie odrzuca wynik
   i zadanie oczekujące; rozpoczętego niepewnego zapisu nie przerywa ani nie
   ponawia. Rejestr zasobów sprząta także zadania przy zamknięciu runtime.
5. Lista uczestników i lista stołów widgetu korzystają z
   `ListBox#update_options(keys:)`. Kluczem jest osoba/ID stołu, nie etykieta.
   Zmiana roli, kolejności, nazwy albo ruch kursora podczas odczytu nie
   przenosi zaznaczenia na inny istniejący rekord.
6. Dispatch callbacków widocznego formularza należy do pętli
   finalnego hosta. Dostarcza je również aktywnej scenie równoległej przed
   aktualizacją kontrolek. Formularz utrzymuje tylko własne prace discovery,
   retencję i sprzątanie zakończonych przekierowanych uruchomień. Wykonawca
   przykrytej gry oraz kontrola przed zapisem nadal mogą opróżnić własny
   endpoint. Jeden formularz z pomocą nie podwaja natywnego limitu callbacków.
7. Timer realtime dziedziczy natywny lifecycle `FormTimer`. Bramka
   zegara meczu zapewnia natychmiastowy pierwszy tick; kolejne terminy liczą się
   od początku poprzedniego ticku, bez nadrabiania zaległych klatek. Zwykły
   timer powtarzalny hosta liczy odstęp po zakończeniu callbacku, więc sama
   zamiana na timer o takim samym interwale zmieniłaby tempo gry.
8. Odczyty kandydatów rejestru i subskrypcji stosują projekcję kolumn z
   zachowaniem autora wiersza. Własne duplikaty preferencji usuwa `delete_many`;
   statystyki zapisuje `insert_many` porcjami po najwyżej 25 rekordów, z budżetem
   czasu między potwierdzonymi porcjami. Pozostałe operacje zbiorcze obejmują
   najwyżej 100 rekordów. Potwierdzenie musi obejmować cały przesłany zbiór; częściowy wynik,
   konflikt, błędne ID i utrata odpowiedzi nie są sukcesem. Ponowienie czyta
   przyjęte rekordy przed wysłaniem brakujących. Zmiana konta lub anulowanie
   nie rozpoczyna kolejnej paczki; nie cofa żądania już przyjętego przez serwer.
   Cache jest ograniczony do 15 s / 4096 wierszy i unieważniany również po
   niepewnym zapisie. Własne preferencje są odczytywane świeżo.

Lokalny parser reguł liczby mnogiej stosuje
dzielenie całkowite i resztę zgodne z C/gettext dla ujemnych wartości pośrednich.
Tłumaczenia aplikacji nie zależą od prywatnego katalogu hosta.

## Własne kontrakty aplikacji

### Pojemność stołów LiveSessions

Usługa dopuszcza pojemność od 2 do 8. Maksimum transportu, lobby, modelu
i formatu archiwum wynosi 8. Nowe stoły i stoły wznawianych
partii mają stałą pojemność 8, także w 1000 mil. Boty i obserwatorzy również
zajmują miejsca w lobby. Zapis wymagający więcej miejsc jest odrzucany przed
utworzeniem stołu, z czytelnym komunikatem; sam zapis pozostaje nienaruszony.
Gospodarz nieobecny w zapisanej obsadzie wymaga dodatkowego miejsca obserwatora.
Testowy broker musi odrzucać żądania pojemności poza zakresem usługi.

### Pozostałe mechanizmy

Pozostają własne mechanizmy potrzebne do kontraktów gry: jeden wykonawca sesji,
projekcje i walidacja historii, uzgadnianie zapisów, prywatne odpowiedzi,
odrębny lifecycle realtime, deterministyczne tasowanie i kopie modeli.
Most mowy/audio przykrytej gry oraz uporządkowane wejście Audio Balla nadal
są potrzebne. Native scene dispatch nie zastępuje prezentacji za obcym oknem
ani nie przenosi aktualizacji kontrolek do workera.
