# Generated from tools/data/rulebooks/hearts.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class HeartsTable
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:play, GameRoomRules.translate("Playing Hearts"),
            GameRoomRules.translate("Four people play individually with a 52-card deck. Everyone receives thirteen cards. Avoid winning hearts and the queen of spades: every heart is one penalty point and that queen is thirteen. Other cards score nothing. Aces are highest, then kings, queens and so on down to twos. There are no trumps."),
            GameRoomRules.translate("Before the first deal, pass three cards to the left. In the next deals, pass right, then across, then keep all cards. This four-deal cycle repeats. Press Enter on each card you want to pass. Once the pass is confirmed, that card disappears from your hand. When everyone has passed three, the exchange is completed and you hear the cards you received. The player holding the two of clubs leads it to the first trick."),
            GameRoomRules.translate("Take turns playing one card and follow the suit led if possible. Without that suit, discard any card, except that on the first trick you must avoid penalty cards if you have a safe card. The highest card of the suit led wins the trick and leads next. You may lead hearts only after someone has discarded a heart, unless your hand contains only hearts.")),
          rule_section(:scoring, GameRoomRules.translate("Scoring and the winner"),
            GameRoomRules.translate("After all thirteen tricks, add the penalties to each player\u2019s total. If one player takes all thirteen hearts and the queen of spades, that player scores zero and every opponent scores 26 instead. Once anyone reaches at least 100, the player with the lowest total wins. If the lowest total is tied, play another deal.")),
          rule_section(:controls, GameRoomRules.translate("Controls"),
            GameRoomRules.translate("Arrows: browse cards or menu choices."),
            GameRoomRules.translate("Enter: select a card to pass before play, or play the selected card during a trick."),
            GameRoomRules.translate("F: read the suit led."),
            GameRoomRules.translate("V: read passing progress or whether hearts have been broken."),
            GameRoomRules.translate("Shift+S: read penalty points in this deal."),
            GameRoomRules.translate("H: read your hand."),
            GameRoomRules.translate("C: read the cards on the table."),
            GameRoomRules.translate("Ctrl+C: browse those cards."),
            GameRoomRules.translate("S: read the scores."),
            GameRoomRules.translate("T: read whose turn it is."),
            GameRoomRules.translate("Z: find the next playable card."),
            GameRoomRules.translate("Shift+Z: find the previous playable card."),
            GameRoomRules.translate("Shift+C: sort your hand by suit."),
            GameRoomRules.translate("Shift+H: sort your hand by rank."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:play, "Jak hr\u00E1t Srdce",
              "Srdce hraj\u00ED \u010Dty\u0159i hr\u00E1\u010Di ka\u017Ed\u00FD za sebe s bal\u00ED\u010Dkem 52 karet. Ka\u017Ed\u00FD dostane t\u0159in\u00E1ct. Vyh\u00FDbej se srdc\u00EDm a pikov\u00E9 d\u00E1m\u011B: ka\u017Ed\u00E9 srdce d\u00E1v\u00E1 jeden trestn\u00FD bod a tato d\u00E1ma t\u0159in\u00E1ct. Ostatn\u00ED karty neboduj\u00ED. Nejvy\u0161\u0161\u00ED je eso, pak kr\u00E1l, d\u00E1ma a dal\u0161\u00ED a\u017E po dvojku. Trumfy nejsou.",
              "V prvn\u00EDm rozd\u00E1n\u00ED p\u0159edej t\u0159i karty doleva. V dal\u0161\u00EDch doprava, naproti a potom si v\u0161echny nech. Tento \u010Dty\u0159d\u00EDln\u00FD cyklus se opakuje. Na ka\u017Ed\u00E9 kart\u011B, kterou chce\u0161 p\u0159edat, stiskni Enter. Po potvrzen\u00ED karta zmiz\u00ED z tv\u00E9 ruky. A\u017E v\u0161ichni p\u0159edaj\u00ED t\u0159i, karty se vym\u011Bn\u00ED a usly\u0161\u00ED\u0161 p\u0159ijat\u00E9 karty. Hr\u00E1\u010D s k\u0159\u00ED\u017Eovou dvojkou j\u00ED za\u010D\u00EDn\u00E1 prvn\u00ED zdvih.",
              "St\u0159\u00EDd\u00E1te se po jedn\u00E9 kart\u011B a mus\u00ED\u0161 p\u0159iznat vynesenou barvu, pokud ji m\u00E1\u0161. Jinak m\u016F\u017Ee\u0161 odhodit cokoli, ale v prvn\u00EDm zdvihu mus\u00ED\u0161 zvolit netrestnou kartu, m\u00E1\u0161-li ji. Nejvy\u0161\u0161\u00ED karta vynesen\u00E9 barvy bere zdvih a za\u010D\u00EDn\u00E1 dal\u0161\u00ED. Srdce sm\u00ED\u0161 vyn\u00E9st a\u017E po odhozen\u00ED srdce do jin\u00E9 barvy, nebo kdy\u017E m\u00E1\u0161 jen srdce."),
            rule_section(:scoring, "Bodov\u00E1n\u00ED a v\u00EDt\u011Bzstv\u00ED",
              "Po t\u0159in\u00E1cti zdviz\u00EDch se trestn\u00E9 body p\u0159i\u010Dtou k celkov\u00E9mu sk\u00F3re. Z\u00EDsk\u00E1-li jeden hr\u00E1\u010D v\u0161ech t\u0159in\u00E1ct srdc\u00ED i pikovou d\u00E1mu, dostane nulu a ka\u017Ed\u00FD soupe\u0159 26 bod\u016F. Jakmile n\u011Bkdo dos\u00E1hne alespo\u0148 100, vyhr\u00E1v\u00E1 nejni\u017E\u0161\u00ED sk\u00F3re. P\u0159i shod\u011B na nejni\u017E\u0161\u00EDm sk\u00F3re se hraje dal\u0161\u00ED rozd\u00E1n\u00ED."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "\u0160ipky: proch\u00E1zej karty nebo nab\u00EDdku.",
              "Enter: vyber kartu k p\u0159ed\u00E1n\u00ED nebo zahraj kartu do zdvihu.",
              "F: p\u0159e\u010Dti vynesenou barvu.",
              "V: zjisti stav p\u0159ed\u00E1v\u00E1n\u00ED nebo zda jsou srdce otev\u0159en\u00E1.",
              "Shift+S: p\u0159e\u010Dti trestn\u00E9 body za rozd\u00E1n\u00ED.",
              "H: p\u0159e\u010Dti svou ruku.",
              "C: p\u0159e\u010Dti karty na stole.",
              "Ctrl+C: prohl\u00E9dni si tyto karty.",
              "S: p\u0159e\u010Dti sk\u00F3re.",
              "T: zjisti, kdo je na tahu.",
              "Z: najdi dal\u0161\u00ED hratelnou kartu.",
              "Shift+Z: najdi p\u0159edchoz\u00ED hratelnou kartu.",
              "Shift+C: se\u0159a\u010F ruku podle barev.",
              "Shift+H: se\u0159a\u010F ruku podle hodnot.")
          ]
        when "en"
          [
            rule_section(:play, "Playing Hearts",
              "Four people play individually with a 52-card deck. Everyone receives thirteen cards. Avoid winning hearts and the queen of spades: every heart is one penalty point and that queen is thirteen. Other cards score nothing. Aces are highest, then kings, queens and so on down to twos. There are no trumps.",
              "Before the first deal, pass three cards to the left. In the next deals, pass right, then across, then keep all cards. This four-deal cycle repeats. Press Enter on each card you want to pass. Once the pass is confirmed, that card disappears from your hand. When everyone has passed three, the exchange is completed and you hear the cards you received. The player holding the two of clubs leads it to the first trick.",
              "Take turns playing one card and follow the suit led if possible. Without that suit, discard any card, except that on the first trick you must avoid penalty cards if you have a safe card. The highest card of the suit led wins the trick and leads next. You may lead hearts only after someone has discarded a heart, unless your hand contains only hearts."),
            rule_section(:scoring, "Scoring and the winner",
              "After all thirteen tricks, add the penalties to each player\u2019s total. If one player takes all thirteen hearts and the queen of spades, that player scores zero and every opponent scores 26 instead. Once anyone reaches at least 100, the player with the lowest total wins. If the lowest total is tied, play another deal."),
            rule_section(:controls, "Controls",
              "Arrows: browse cards or menu choices.",
              "Enter: select a card to pass before play, or play the selected card during a trick.",
              "F: read the suit led.",
              "V: read passing progress or whether hearts have been broken.",
              "Shift+S: read penalty points in this deal.",
              "H: read your hand.",
              "C: read the cards on the table.",
              "Ctrl+C: browse those cards.",
              "S: read the scores.",
              "T: read whose turn it is.",
              "Z: find the next playable card.",
              "Shift+Z: find the previous playable card.",
              "Shift+C: sort your hand by suit.",
              "Shift+H: sort your hand by rank.")
          ]
        when "es"
          [
            rule_section(:play, "C\u00F3mo jugar a Corazones",
              "Cuatro personas juegan individualmente con 52 cartas; cada una recibe trece. Evita llevarte corazones y la dama de picas: cada coraz\u00F3n da un punto de penalizaci\u00F3n y esa dama trece. Las dem\u00E1s cartas no punt\u00FAan. El as es la m\u00E1s alta, seguido del rey, la dama y las dem\u00E1s hasta el dos. No hay triunfos.",
              "En la primera mano pasa tres cartas a la izquierda; en las siguientes, a la derecha, enfrente y despu\u00E9s conserva todas. Este ciclo de cuatro manos se repite. Pulsa Intro sobre cada carta que quieras pasar. La carta desaparece de tu mano al confirmarse el pase. Cuando todos hayan pasado tres, se intercambian y oyes las que has recibido. Quien tenga el dos de tr\u00E9boles sale con \u00E9l a la primera baza.",
              "Jugad una carta por turno y asistid al palo si pod\u00E9is. Sin ese palo puedes descartar cualquiera, salvo en la primera baza, donde debes evitar cartas de penalizaci\u00F3n si tienes otra. Gana la carta m\u00E1s alta del palo de salida y su jugador sale a la siguiente. Solo puedes salir de corazones despu\u00E9s de que alguien descarte uno, a menos que solo tengas corazones."),
            rule_section(:scoring, "Puntuaci\u00F3n y victoria",
              "Tras las trece bazas se suman las penalizaciones. Si alguien recoge los trece corazones y la dama de picas, recibe cero y cada rival 26 puntos. Cuando alguien llega al menos a 100, gana quien tenga el total m\u00E1s bajo. Si empatan los totales m\u00E1s bajos, se juega otra mano."),
            rule_section(:controls, "Controles",
              "Flechas: recorrer cartas u opciones.",
              "Intro: elegir una carta para pasar o jugar la carta seleccionada en una baza.",
              "F: leer el palo de salida.",
              "V: consultar el intercambio o si se han abierto los corazones.",
              "Shift+S: leer las penalizaciones de esta mano.",
              "H: leer tu mano.",
              "C: leer las cartas de la mesa.",
              "Ctrl+C: consultar esas cartas.",
              "S: leer las puntuaciones.",
              "T: leer a qui\u00E9n le toca.",
              "Z: buscar la siguiente carta que puedes jugar.",
              "May\u00FAs+Z: buscar la carta jugable anterior.",
              "May\u00FAs+C: ordenar tu mano por palos.",
              "May\u00FAs+H: ordenar tu mano por valores.",
              "May\u00FAs+M: restaurar el orden en que recibiste las cartas.")
          ]
        when "pl"
          [
            rule_section(:play, "Jak gra\u0107 w Kierki",
              "W Kierki graj\u0105 cztery osoby, ka\u017Cda na w\u0142asny wynik. Talia ma 52 karty, wi\u0119c ka\u017Cdy dostaje trzyna\u015Bcie. Unikaj zabierania kier\u00F3w i damy pik: ka\u017Cdy kier daje punkt karny, a dama pik trzyna\u015Bcie. Pozosta\u0142e karty nie daj\u0105 punkt\u00F3w. Najsilniejszy jest as, potem kr\u00F3l, dama i dalsze karty a\u017C do dw\u00F3jki. Nie ma atutu.",
              "Przed rozgrywk\u0105 pierwszego rozdania przeka\u017C trzy karty w lewo. W kolejnych rozdaniach przekazuj w prawo, naprzeciwko, a potem zachowaj ca\u0142\u0105 r\u0119k\u0119. Ten cykl czterech rozda\u0144 si\u0119 powtarza. Naci\u015Bnij Enter na karcie, kt\u00F3r\u0105 chcesz przekaza\u0107. Po potwierdzeniu znika ona z twojej r\u0119ki. Gdy wszyscy przeka\u017C\u0105 po trzy, nast\u0119puje wymiana i us\u0142yszysz otrzymane karty. Osoba z dw\u00F3jk\u0105 trefl wychodzi ni\u0105 do pierwszej lewy.",
              "Zagrywajcie po jednej karcie, dok\u0142adaj\u0105c do koloru wyj\u015Bcia, je\u015Bli go macie. Gdy go nie masz, mo\u017Cesz zrzuci\u0107 dowoln\u0105 kart\u0119. Wyj\u0105tkiem jest pierwsza lewa: nie wolno w niej zrzuci\u0107 karty karnej, je\u015Bli masz inn\u0105. Najwy\u017Csza karta koloru wyj\u015Bcia bierze lew\u0119, a jej zwyci\u0119zca zaczyna nast\u0119pn\u0105. W kierach wolno wyj\u015B\u0107 dopiero po zagraniu kiera do innego koloru, chyba \u017Ce masz same kiery."),
            rule_section(:scoring, "Punktacja i zwyci\u0119stwo",
              "Po trzynastu lewach gra dopisuje punkty karne do wynik\u00F3w graczy. Je\u015Bli jedna osoba zbierze wszystkie trzyna\u015Bcie kier\u00F3w i dam\u0119 pik, sama dostaje zero, a ka\u017Cdy przeciwnik po 26 punkt\u00F3w. Gdy kto\u015B ma co najmniej 100, wygrywa osoba z najni\u017Cszym wynikiem. Je\u015Bli na najni\u017Cszym wyniku jest remis, gracie kolejne rozdanie."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "Strza\u0142ki: przegl\u0105daj karty lub pozycje menu.",
              "Enter: wybierz kart\u0119 do przekazania przed rozgrywk\u0105 albo zagraj wskazan\u0105 kart\u0119 podczas lewy.",
              "F: odczytaj kolor wyj\u015Bcia.",
              "V: sprawd\u017A przekazywanie kart albo czy kiery s\u0105 ju\u017C otwarte.",
              "Shift+S: odczytaj punkty karne rozdania.",
              "H: odczytaj swoj\u0105 r\u0119k\u0119.",
              "C: odczytaj karty na stole.",
              "Ctrl+C: przejrzyj te karty.",
              "S: odczytaj wyniki.",
              "T: sprawd\u017A, czyja jest tura.",
              "Z: znajd\u017A nast\u0119pn\u0105 kart\u0119, kt\u00F3r\u0105 mo\u017Cna zagra\u0107.",
              "Shift+Z: znajd\u017A poprzedni\u0105 kart\u0119, kt\u00F3r\u0105 mo\u017Cna zagra\u0107.",
              "Shift+C: sortuj r\u0119k\u0119 wed\u0142ug kolor\u00F3w.",
              "Shift+H: sortuj r\u0119k\u0119 wed\u0142ug warto\u015Bci.")
          ]
        when "ru"
          [
            rule_section(:play, "\u041A\u0430\u043A \u0438\u0433\u0440\u0430\u0442\u044C \u0432 \u0447\u0435\u0440\u0432\u044B",
              "\u0427\u0435\u0442\u0432\u0435\u0440\u043E \u0438\u0433\u0440\u0430\u044E\u0442 \u043A\u0430\u0436\u0434\u044B\u0439 \u0437\u0430 \u0441\u0435\u0431\u044F \u043A\u043E\u043B\u043E\u0434\u043E\u0439 \u0438\u0437 52 \u043A\u0430\u0440\u0442. \u041A\u0430\u0436\u0434\u044B\u0439 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u0442\u0440\u0438\u043D\u0430\u0434\u0446\u0430\u0442\u044C. \u0418\u0437\u0431\u0435\u0433\u0430\u0439\u0442\u0435 \u0447\u0435\u0440\u0432\u0435\u0439 \u0438 \u043F\u0438\u043A\u043E\u0432\u043E\u0439 \u0434\u0430\u043C\u044B: \u043A\u0430\u0436\u0434\u0430\u044F \u0447\u0435\u0440\u0432\u0430 \u0434\u0430\u0451\u0442 \u043E\u0434\u043D\u043E \u0448\u0442\u0440\u0430\u0444\u043D\u043E\u0435 \u043E\u0447\u043A\u043E, \u044D\u0442\u0430 \u0434\u0430\u043C\u0430 \u2014 \u0442\u0440\u0438\u043D\u0430\u0434\u0446\u0430\u0442\u044C. \u0414\u0440\u0443\u0433\u0438\u0435 \u043A\u0430\u0440\u0442\u044B \u043E\u0447\u043A\u043E\u0432 \u043D\u0435 \u0434\u0430\u044E\u0442. \u0422\u0443\u0437 \u0441\u0442\u0430\u0440\u0448\u0435 \u043A\u043E\u0440\u043E\u043B\u044F, \u0437\u0430\u0442\u0435\u043C \u0434\u0430\u043C\u0430 \u0438 \u043E\u0441\u0442\u0430\u043B\u044C\u043D\u044B\u0435 \u0434\u043E \u0434\u0432\u043E\u0439\u043A\u0438. \u041A\u043E\u0437\u044B\u0440\u0435\u0439 \u043D\u0435\u0442.",
              "\u0412 \u043F\u0435\u0440\u0432\u043E\u0439 \u0441\u0434\u0430\u0447\u0435 \u043F\u0435\u0440\u0435\u0434\u0430\u0439\u0442\u0435 \u0442\u0440\u0438 \u043A\u0430\u0440\u0442\u044B \u043D\u0430\u043B\u0435\u0432\u043E, \u0432 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0438\u0445 \u2014 \u043D\u0430\u043F\u0440\u0430\u0432\u043E, \u043D\u0430\u043F\u0440\u043E\u0442\u0438\u0432, \u0437\u0430\u0442\u0435\u043C \u043E\u0441\u0442\u0430\u0432\u044C\u0442\u0435 \u0432\u0441\u0435 \u043A\u0430\u0440\u0442\u044B. \u0426\u0438\u043A\u043B \u0438\u0437 \u0447\u0435\u0442\u044B\u0440\u0451\u0445 \u0441\u0434\u0430\u0447 \u043F\u043E\u0432\u0442\u043E\u0440\u044F\u0435\u0442\u0441\u044F. \u0427\u0442\u043E\u0431\u044B \u043F\u0435\u0440\u0435\u0434\u0430\u0442\u044C \u043A\u0430\u0440\u0442\u0443, \u0432\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0435\u0451 \u0438 \u043D\u0430\u0436\u043C\u0438\u0442\u0435 Enter. \u041F\u043E\u0441\u043B\u0435 \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0435\u043D\u0438\u044F \u043E\u043D\u0430 \u0438\u0441\u0447\u0435\u0437\u043D\u0435\u0442 \u0438\u0437 \u0432\u0430\u0448\u0435\u0439 \u0440\u0443\u043A\u0438. \u041A\u043E\u0433\u0434\u0430 \u0432\u0441\u0435 \u043F\u0435\u0440\u0435\u0434\u0430\u0434\u0443\u0442 \u043F\u043E \u0442\u0440\u0438, \u043E\u0431\u043C\u0435\u043D \u0437\u0430\u0432\u0435\u0440\u0448\u0438\u0442\u0441\u044F \u0438 \u0432\u044B \u0443\u0441\u043B\u044B\u0448\u0438\u0442\u0435 \u043F\u043E\u043B\u0443\u0447\u0435\u043D\u043D\u044B\u0435 \u043A\u0430\u0440\u0442\u044B. \u0412\u043B\u0430\u0434\u0435\u043B\u0435\u0446 \u0434\u0432\u043E\u0439\u043A\u0438 \u0442\u0440\u0435\u0444 \u043D\u0430\u0447\u0438\u043D\u0430\u0435\u0442 \u0435\u044E \u043F\u0435\u0440\u0432\u0443\u044E \u0432\u0437\u044F\u0442\u043A\u0443.",
              "\u0425\u043E\u0434\u0438\u0442\u0435 \u043F\u043E \u043E\u0434\u043D\u043E\u0439 \u043A\u0430\u0440\u0442\u0435 \u0432 \u043C\u0430\u0441\u0442\u044C \u043F\u0435\u0440\u0432\u043E\u0439 \u043A\u0430\u0440\u0442\u044B, \u0435\u0441\u043B\u0438 \u043C\u043E\u0436\u0435\u0442\u0435. \u0411\u0435\u0437 \u044D\u0442\u043E\u0439 \u043C\u0430\u0441\u0442\u0438 \u043C\u043E\u0436\u043D\u043E \u0441\u0431\u0440\u043E\u0441\u0438\u0442\u044C \u043B\u044E\u0431\u0443\u044E \u043A\u0430\u0440\u0442\u0443, \u043D\u043E \u0432 \u043F\u0435\u0440\u0432\u043E\u0439 \u0432\u0437\u044F\u0442\u043A\u0435 \u043D\u0435\u043B\u044C\u0437\u044F \u0441\u0431\u0440\u0430\u0441\u044B\u0432\u0430\u0442\u044C \u0448\u0442\u0440\u0430\u0444\u043D\u0443\u044E, \u0435\u0441\u043B\u0438 \u0435\u0441\u0442\u044C \u0434\u0440\u0443\u0433\u0430\u044F. \u0421\u0442\u0430\u0440\u0448\u0430\u044F \u043A\u0430\u0440\u0442\u0430 \u043C\u0430\u0441\u0442\u0438 \u0445\u043E\u0434\u0430 \u0431\u0435\u0440\u0451\u0442 \u0432\u0437\u044F\u0442\u043A\u0443, \u0435\u0451 \u0432\u043B\u0430\u0434\u0435\u043B\u0435\u0446 \u0445\u043E\u0434\u0438\u0442 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0438\u043C. \u0421 \u0447\u0435\u0440\u0432\u0435\u0439 \u043C\u043E\u0436\u043D\u043E \u0445\u043E\u0434\u0438\u0442\u044C \u043F\u043E\u0441\u043B\u0435 \u0441\u0431\u0440\u043E\u0441\u0430 \u0447\u0435\u0440\u0432\u044B \u043D\u0430 \u0434\u0440\u0443\u0433\u0443\u044E \u043C\u0430\u0441\u0442\u044C \u0438\u043B\u0438 \u0435\u0441\u043B\u0438 \u043E\u0441\u0442\u0430\u043B\u0438\u0441\u044C \u0442\u043E\u043B\u044C\u043A\u043E \u0447\u0435\u0440\u0432\u044B."),
            rule_section(:scoring, "\u041E\u0447\u043A\u0438 \u0438 \u043F\u043E\u0431\u0435\u0434\u0430",
              "\u041F\u043E\u0441\u043B\u0435 \u0442\u0440\u0438\u043D\u0430\u0434\u0446\u0430\u0442\u0438 \u0432\u0437\u044F\u0442\u043E\u043A \u0448\u0442\u0440\u0430\u0444\u043D\u044B\u0435 \u043E\u0447\u043A\u0438 \u0434\u043E\u0431\u0430\u0432\u043B\u044F\u044E\u0442\u0441\u044F \u043A \u043E\u0431\u0449\u0435\u043C\u0443 \u0441\u0447\u0451\u0442\u0443. \u0421\u043E\u0431\u0440\u0430\u0432\u0448\u0438\u0439 \u0432\u0441\u0435 \u0442\u0440\u0438\u043D\u0430\u0434\u0446\u0430\u0442\u044C \u0447\u0435\u0440\u0432\u0435\u0439 \u0438 \u043F\u0438\u043A\u043E\u0432\u0443\u044E \u0434\u0430\u043C\u0443 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u043D\u043E\u043B\u044C, \u0430 \u043A\u0430\u0436\u0434\u044B\u0439 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A \u2014 26 \u043E\u0447\u043A\u043E\u0432. \u041A\u043E\u0433\u0434\u0430 \u043A\u0442\u043E-\u0442\u043E \u0434\u043E\u0441\u0442\u0438\u0433\u0430\u0435\u0442 100, \u043F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u0438\u0433\u0440\u043E\u043A \u0441 \u043D\u0430\u0438\u043C\u0435\u043D\u044C\u0448\u0438\u043C \u0441\u0447\u0451\u0442\u043E\u043C. \u041F\u0440\u0438 \u0440\u0430\u0432\u0435\u043D\u0441\u0442\u0432\u0435 \u043D\u0430\u0438\u043C\u0435\u043D\u044C\u0448\u0438\u0445 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u043E\u0432 \u0438\u0433\u0440\u0430\u0435\u0442\u0441\u044F \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0430\u044F \u0441\u0434\u0430\u0447\u0430."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0448\u0438 \u0443\u043F\u0440\u0430\u0432\u043B\u0435\u043D\u0438\u044F",
              "\u0421\u0442\u0440\u0435\u043B\u043A\u0438: \u043F\u0440\u043E\u0441\u043C\u0430\u0442\u0440\u0438\u0432\u0430\u0442\u044C \u043A\u0430\u0440\u0442\u044B \u0438\u043B\u0438 \u043F\u0443\u043D\u043A\u0442\u044B \u043C\u0435\u043D\u044E.",
              "Enter: \u0432\u044B\u0431\u0440\u0430\u0442\u044C \u043A\u0430\u0440\u0442\u0443 \u0434\u043B\u044F \u043F\u0435\u0440\u0435\u0434\u0430\u0447\u0438 \u0438\u043B\u0438 \u0441\u044B\u0433\u0440\u0430\u0442\u044C \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u0443\u044E \u043A\u0430\u0440\u0442\u0443 \u0432\u043E \u0432\u0437\u044F\u0442\u043A\u0443.",
              "F: \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u043C\u0430\u0441\u0442\u044C \u0445\u043E\u0434\u0430.",
              "V: \u0443\u0437\u043D\u0430\u0442\u044C \u0441\u043E\u0441\u0442\u043E\u044F\u043D\u0438\u0435 \u043F\u0435\u0440\u0435\u0434\u0430\u0447\u0438 \u0438\u043B\u0438 \u043E\u0442\u043A\u0440\u044B\u0442\u044B \u043B\u0438 \u0447\u0435\u0440\u0432\u044B.",
              "Shift+S: \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u0448\u0442\u0440\u0430\u0444\u043D\u044B\u0435 \u043E\u0447\u043A\u0438 \u0437\u0430 \u0441\u0434\u0430\u0447\u0443.",
              "H: \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u0441\u0432\u043E\u044E \u0440\u0443\u043A\u0443.",
              "C: \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u043A\u0430\u0440\u0442\u044B \u043D\u0430 \u0441\u0442\u043E\u043B\u0435.",
              "Ctrl+C: \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u0442\u044C \u044D\u0442\u0438 \u043A\u0430\u0440\u0442\u044B.",
              "S: \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u0441\u0447\u0451\u0442.",
              "T: \u0443\u0437\u043D\u0430\u0442\u044C, \u0447\u0435\u0439 \u0445\u043E\u0434.",
              "Z: \u043D\u0430\u0439\u0442\u0438 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0443\u044E \u0434\u043E\u043F\u0443\u0441\u0442\u0438\u043C\u0443\u044E \u043A\u0430\u0440\u0442\u0443.",
              "Shift+Z: \u043D\u0430\u0439\u0442\u0438 \u043F\u0440\u0435\u0434\u044B\u0434\u0443\u0449\u0443\u044E \u0434\u043E\u043F\u0443\u0441\u0442\u0438\u043C\u0443\u044E \u043A\u0430\u0440\u0442\u0443.",
              "Shift+C: \u043E\u0442\u0441\u043E\u0440\u0442\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u0440\u0443\u043A\u0443 \u043F\u043E \u043C\u0430\u0441\u0442\u044F\u043C.",
              "Shift+H: \u043E\u0442\u0441\u043E\u0440\u0442\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u0440\u0443\u043A\u0443 \u043F\u043E \u0434\u043E\u0441\u0442\u043E\u0438\u043D\u0441\u0442\u0432\u0443.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
