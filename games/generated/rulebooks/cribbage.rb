# Generated from tools/data/rulebooks/cribbage.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class CribbageTable
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:play, GameRoomRules.translate("Playing Cribbage"),
            GameRoomRules.translate("Cribbage is for two players. Be the first to reach 121 points. Each deal gives you six cards; select two with Enter to put them in the crib, a separate four-card hand that will score for the dealer. The dealer changes after each deal."),
            GameRoomRules.translate("After both players discard, the starter is turned up. If it is a jack, the dealer immediately scores two. The nondealer then plays first. Take turns laying down one card without taking the running total above 31. Aces count one, number cards their number, and jacks, queens and kings ten."),
            GameRoomRules.translate("Choose Go when none of your cards fits. The other player may keep playing. When neither can continue, the last player to lay a card scores one and the total resets to zero. Reaching exactly 31 gives two points instead. After the reset, the other player leads if they still have cards.")),
          rule_section(:scoring, GameRoomRules.translate("Scoring and counting"),
            GameRoomRules.translate("During play, a total of 15 scores two. Two, three or four consecutive cards of the same rank score 2, 6 or 12. A run of at least three consecutive ranks at the end of the sequence scores its length, regardless of their playing order. For example, 3, 5, 4 scores three."),
            GameRoomRules.translate("After all cards are played, count the nondealer\u2019s hand, the dealer\u2019s hand and finally the crib, always adding the starter. Every combination totalling 15 and every pair scores two. Count each longest run of at least three for its length; duplicate cards may form several runs. Four same-suit hand cards score four, or five with a matching starter. A crib flush requires all five cards. A jack matching the starter\u2019s suit adds one."),
            GameRoomRules.translate("The game shows the cards to count. Press Enter and give their score. If your count is wrong, you receive no more than the correct score and your opponent receives the difference. The match ends as soon as either player reaches 121, including during play or counting.")),
          rule_section(:controls, GameRoomRules.translate("Controls"),
            GameRoomRules.translate("Arrows: browse cards or menu choices."),
            GameRoomRules.translate("Enter: discard or play the selected card; when counting, open the score field. Select Go when no card fits."),
            GameRoomRules.translate("D: read the starter."),
            GameRoomRules.translate("V: read who owns the crib."),
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
            rule_section(:play, "Jak hr\u00E1t Cribbage",
              "Cribbage hraj\u00ED dva hr\u00E1\u010Di. Vyhr\u00E1v\u00E1 ten, kdo prvn\u00ED z\u00EDsk\u00E1 121 bod\u016F. Ka\u017Ed\u00FD dostane \u0161est karet. Dv\u011B vyber Enterem a odlo\u017E do cribu, samostatn\u00E9 \u010Dtve\u0159ice karet bodovan\u00E9 pro rozd\u00E1vaj\u00EDc\u00EDho. V rozd\u00E1v\u00E1n\u00ED se st\u0159\u00EDd\u00E1te.",
              "Po odlo\u017Een\u00ED karet se oto\u010D\u00ED startovn\u00ED karta. Je-li to kluk, rozd\u00E1vaj\u00EDc\u00ED ihned z\u00EDsk\u00E1 dva body. Za\u010D\u00EDn\u00E1 druh\u00FD hr\u00E1\u010D. St\u0159\u00EDd\u00E1te se v pokl\u00E1d\u00E1n\u00ED jedn\u00E9 karty, ani\u017E sou\u010Det p\u0159ekro\u010D\u00ED 31. Eso m\u00E1 hodnotu jedna, \u010D\u00EDseln\u00E9 karty sv\u00E9 \u010D\u00EDslo a kluk, d\u00E1ma a kr\u00E1l deset.",
              "Pokud se \u017E\u00E1dn\u00E1 karta nevejde, zvol Go. Soupe\u0159 m\u016F\u017Ee pokra\u010Dovat. Kdy\u017E nem\u016F\u017Ee p\u0159ilo\u017Eit ani jeden, z\u00EDsk\u00E1 hr\u00E1\u010D posledn\u00ED karty jeden bod a sou\u010Det se vynuluje. P\u0159esn\u00FDch 31 d\u00E1v\u00E1 m\u00EDsto toho dva body. Po vynulov\u00E1n\u00ED za\u010D\u00EDn\u00E1 druh\u00FD hr\u00E1\u010D, pokud je\u0161t\u011B m\u00E1 karty."),
            rule_section(:scoring, "Bodov\u00E1n\u00ED a po\u010D\u00EDt\u00E1n\u00ED",
              "P\u0159i vykl\u00E1d\u00E1n\u00ED d\u00E1v\u00E1 sou\u010Det 15 dva body. Dv\u011B, t\u0159i nebo \u010Dty\u0159i po sob\u011B zahran\u00E9 karty stejn\u00E9 hodnoty d\u00E1vaj\u00ED 2, 6 nebo 12 bod\u016F. Postupka nejm\u00E9n\u011B t\u0159\u00ED posledn\u00EDch karet d\u00E1v\u00E1 bod za kartu bez ohledu na po\u0159ad\u00ED. Nap\u0159\u00EDklad 3, 5, 4 d\u00E1v\u00E1 t\u0159i body.",
              "Po zahr\u00E1n\u00ED v\u0161ech karet se po\u010D\u00EDt\u00E1 ruka druh\u00E9ho hr\u00E1\u010De, ruka rozd\u00E1vaj\u00EDc\u00EDho a nakonec crib, v\u017Edy se startovn\u00ED kartou. Ka\u017Ed\u00E1 kombinace se sou\u010Dtem 15 a ka\u017Ed\u00E1 dvojice d\u00E1vaj\u00ED dva body. Ka\u017Ed\u00E1 nejdel\u0161\u00ED postupka od t\u0159\u00ED karet d\u00E1v\u00E1 bod za kartu; stejn\u00E9 hodnoty mohou vytvo\u0159it v\u00EDce postupek. \u010Cty\u0159i karty stejn\u00E9 barvy v ruce d\u00E1vaj\u00ED \u010Dty\u0159i body, se shodnou startovn\u00ED kartou p\u011Bt. V cribu mus\u00ED barva souhlasit u v\u0161ech p\u011Bti. Kluk barvy startovn\u00ED karty p\u0159id\u00E1v\u00E1 bod.",
              "Hra uk\u00E1\u017Ee karty k po\u010D\u00EDt\u00E1n\u00ED. Stiskni Enter a zadej sk\u00F3re. P\u0159i chyb\u011B dostane\u0161 nejv\u00FD\u0161e spr\u00E1vn\u00E9 sk\u00F3re a rozd\u00EDl z\u00EDsk\u00E1 soupe\u0159. Hra kon\u010D\u00ED ihned po dosa\u017Een\u00ED 121 bod\u016F, i b\u011Bhem vykl\u00E1d\u00E1n\u00ED nebo po\u010D\u00EDt\u00E1n\u00ED."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "\u0160ipky: proch\u00E1zej karty nebo nab\u00EDdku.",
              "Enter: odlo\u017E nebo zahraj vybranou kartu; p\u0159i po\u010D\u00EDt\u00E1n\u00ED otev\u0159i pole sk\u00F3re. Pokud se \u017E\u00E1dn\u00E1 karta nevejde, zvol Go.",
              "D: p\u0159e\u010Dti startovn\u00ED kartu.",
              "V: zjisti, komu pat\u0159\u00ED crib.",
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
            rule_section(:play, "Playing Cribbage",
              "Cribbage is for two players. Be the first to reach 121 points. Each deal gives you six cards; select two with Enter to put them in the crib, a separate four-card hand that will score for the dealer. The dealer changes after each deal.",
              "After both players discard, the starter is turned up. If it is a jack, the dealer immediately scores two. The nondealer then plays first. Take turns laying down one card without taking the running total above 31. Aces count one, number cards their number, and jacks, queens and kings ten.",
              "Choose Go when none of your cards fits. The other player may keep playing. When neither can continue, the last player to lay a card scores one and the total resets to zero. Reaching exactly 31 gives two points instead. After the reset, the other player leads if they still have cards."),
            rule_section(:scoring, "Scoring and counting",
              "During play, a total of 15 scores two. Two, three or four consecutive cards of the same rank score 2, 6 or 12. A run of at least three consecutive ranks at the end of the sequence scores its length, regardless of their playing order. For example, 3, 5, 4 scores three.",
              "After all cards are played, count the nondealer\u2019s hand, the dealer\u2019s hand and finally the crib, always adding the starter. Every combination totalling 15 and every pair scores two. Count each longest run of at least three for its length; duplicate cards may form several runs. Four same-suit hand cards score four, or five with a matching starter. A crib flush requires all five cards. A jack matching the starter\u2019s suit adds one.",
              "The game shows the cards to count. Press Enter and give their score. If your count is wrong, you receive no more than the correct score and your opponent receives the difference. The match ends as soon as either player reaches 121, including during play or counting."),
            rule_section(:controls, "Controls",
              "Arrows: browse cards or menu choices.",
              "Enter: discard or play the selected card; when counting, open the score field. Select Go when no card fits.",
              "D: read the starter.",
              "V: read who owns the crib.",
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
            rule_section(:play, "C\u00F3mo jugar al Cribbage",
              "Cribbage es para dos jugadores. Gana quien llegue primero a 121 puntos. Recibes seis cartas; selecciona dos con Intro para dejarlas en el crib, una mano aparte de cuatro cartas que puntuar\u00E1 para quien reparte. El reparto se alterna en cada mano.",
              "Tras los descartes se descubre la carta inicial. Si es una jota, quien reparte gana dos puntos. Empieza el otro jugador. Jugad una carta por turno sin superar 31 en el total acumulado. El as vale uno, las cartas num\u00E9ricas su n\u00FAmero y las figuras diez.",
              "Elige Paso si ninguna carta cabe. El rival puede seguir jugando. Cuando ninguno pueda continuar, quien jug\u00F3 la \u00FAltima carta gana un punto y el total vuelve a cero. Alcanzar exactamente 31 da dos puntos en su lugar. Tras reiniciar, sale el otro jugador si a\u00FAn tiene cartas."),
            rule_section(:scoring, "Puntuaci\u00F3n y recuento",
              "Durante el juego, sumar 15 da dos puntos. Dos, tres o cuatro cartas consecutivas del mismo valor dan 2, 6 o 12 puntos. Una escalera de al menos tres valores consecutivos al final de la secuencia punt\u00FAa su longitud, sin importar el orden de juego: 3, 5, 4 da tres puntos.",
              "Al acabar las cartas, se cuentan la mano de quien no reparte, la de quien reparte y el crib, siempre con la carta inicial. Cada combinaci\u00F3n que sume 15 y cada pareja dan dos puntos. Cada escalera m\u00E1xima de tres o m\u00E1s cartas punt\u00FAa su longitud; las cartas repetidas pueden formar varias escaleras. Cuatro cartas del mismo palo en la mano dan cuatro puntos, o cinco con la inicial del mismo palo. En el crib deben coincidir las cinco. Una jota del palo de la inicial a\u00F1ade un punto.",
              "El juego muestra las cartas que debes contar. Pulsa Intro e indica la puntuaci\u00F3n. Si te equivocas, recibes como m\u00E1ximo la puntuaci\u00F3n correcta y el rival recibe la diferencia. La partida termina en cuanto alguien llega a 121, tambi\u00E9n durante el juego o el recuento."),
            rule_section(:controls, "Controles",
              "Flechas: recorrer cartas u opciones.",
              "Intro: descartar o jugar la carta elegida; durante el recuento, abrir el campo de puntuaci\u00F3n. Elige Paso si ninguna carta cabe.",
              "D: leer la carta inicial.",
              "V: leer a qui\u00E9n pertenece el crib.",
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
            rule_section(:play, "Jak gra\u0107 w Cribbage",
              "W Cribbage graj\u0105 dwie osoby. Wygrywa ta, kt\u00F3ra pierwsza zdob\u0119dzie 121 punkt\u00F3w. Dostajesz sze\u015B\u0107 kart. Wybierz dwie Enterem, aby od\u0142o\u017Cy\u0107 je do cribu, czyli osobnego czterokartowego uk\u0142adu, kt\u00F3ry zapunktuje dla rozdaj\u0105cego. Po ka\u017Cdym rozdaniu rozdaje druga osoba.",
              "Gdy obie osoby od\u0142o\u017C\u0105 karty, gra odkrywa kart\u0119 startow\u0105. Je\u015Bli to walet, rozdaj\u0105cy od razu dostaje dwa punkty. Pierwszy zagrywa przeciwnik rozdaj\u0105cego. Zagrywajcie po jednej karcie na zmian\u0119, nie przekraczaj\u0105c sumy 31. As jest wart jeden, karty liczbowe tyle, ile wskazuj\u0105, a walet, dama i kr\u00F3l po dziesi\u0119\u0107.",
              "Wybierz Pas, gdy \u017Cadna twoja karta nie mie\u015Bci si\u0119 w limicie. Druga osoba mo\u017Ce dalej zagrywa\u0107. Gdy obie nie mog\u0105 ju\u017C do\u0142o\u017Cy\u0107, gracz, kt\u00F3ry po\u0142o\u017Cy\u0142 ostatni\u0105 kart\u0119, dostaje punkt, a suma wraca do zera. Dok\u0142adnie 31 daje zamiast tego dwa punkty. Po wyzerowaniu zaczyna druga osoba, je\u015Bli ma jeszcze karty."),
            rule_section(:scoring, "Punktacja i liczenie uk\u0142ad\u00F3w",
              "Podczas zagrywania suma 15 daje dwa punkty. Dwie, trzy lub cztery kolejne karty tej samej warto\u015Bci daj\u0105 odpowiednio 2, 6 lub 12 punkt\u00F3w. Sekwencja co najmniej trzech kolejnych warto\u015Bci na ko\u0144cu zagrywanych kart daje punkt za ka\u017Cd\u0105 kart\u0119, niezale\u017Cnie od kolejno\u015Bci ich po\u0142o\u017Cenia. Na przyk\u0142ad 3, 5, 4 daje trzy punkty.",
              "Po zagraniu wszystkich kart policzcie r\u0119k\u0119 przeciwnika rozdaj\u0105cego, r\u0119k\u0119 rozdaj\u0105cego, a na ko\u0144cu crib. Za ka\u017Cdym razem dodajcie kart\u0119 startow\u0105. Ka\u017Cda kombinacja daj\u0105ca 15 i ka\u017Cda para daj\u0105 dwa punkty. Liczy si\u0119 ka\u017Cd\u0105 najd\u0142u\u017Csz\u0105 sekwencj\u0119 od trzech kart: punkt za kart\u0119. Powt\u00F3rzone warto\u015Bci mog\u0105 tworzy\u0107 kilka sekwencji. Cztery karty jednego koloru w r\u0119ce daj\u0105 cztery punkty, a zgodna karta startowa pi\u0105ty. W cribie kolor wymaga wszystkich pi\u0119ciu kart. Walet w kolorze karty startowej daje dodatkowy punkt.",
              "Gra pokazuje karty do podliczenia. Naci\u015Bnij Enter i podaj wynik. Je\u015Bli si\u0119 pomylisz, nie dostaniesz wi\u0119cej ni\u017C prawid\u0142owy wynik, a r\u00F3\u017Cnic\u0119 otrzyma przeciwnik. Mecz ko\u0144czy si\u0119 od razu po zdobyciu 121 punkt\u00F3w, r\u00F3wnie\u017C podczas zagrywania lub liczenia uk\u0142ad\u00F3w."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "Strza\u0142ki: przegl\u0105daj karty lub pozycje menu.",
              "Enter: od\u0142\u00F3\u017C lub zagraj wybran\u0105 kart\u0119; podczas liczenia otw\u00F3rz pole wyniku. Gdy \u017Cadna karta nie mie\u015Bci si\u0119 w limicie, wybierz Pas.",
              "D: odczytaj kart\u0119 startow\u0105.",
              "V: sprawd\u017A, kto liczy crib.",
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
            rule_section(:play, "\u041A\u0430\u043A \u0438\u0433\u0440\u0430\u0442\u044C \u0432 \u043A\u0440\u0438\u0431\u0431\u0435\u0434\u0436",
              "\u0412 \u043A\u0440\u0438\u0431\u0431\u0435\u0434\u0436 \u0438\u0433\u0440\u0430\u044E\u0442 \u0434\u0432\u043E\u0435. \u041F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u043F\u0435\u0440\u0432\u044B\u0439 \u043D\u0430\u0431\u0440\u0430\u0432\u0448\u0438\u0439 121 \u043E\u0447\u043A\u043E. \u041A\u0430\u0436\u0434\u044B\u0439 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u0448\u0435\u0441\u0442\u044C \u043A\u0430\u0440\u0442. \u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0434\u0432\u0435 \u043A\u043B\u0430\u0432\u0438\u0448\u0435\u0439 Enter \u0438 \u043E\u0442\u043B\u043E\u0436\u0438\u0442\u0435 \u0438\u0445 \u0432 \u043A\u0440\u0438\u0431 \u2014 \u043E\u0442\u0434\u0435\u043B\u044C\u043D\u0443\u044E \u0440\u0443\u043A\u0443 \u0438\u0437 \u0447\u0435\u0442\u044B\u0440\u0451\u0445 \u043A\u0430\u0440\u0442, \u043E\u0447\u043A\u0438 \u043A\u043E\u0442\u043E\u0440\u043E\u0439 \u043F\u043E\u043B\u0443\u0447\u0438\u0442 \u0441\u0434\u0430\u044E\u0449\u0438\u0439. \u041F\u043E\u0441\u043B\u0435 \u043A\u0430\u0436\u0434\u043E\u0439 \u0441\u0434\u0430\u0447\u0438 \u0441\u0434\u0430\u044E\u0449\u0438\u0439 \u043C\u0435\u043D\u044F\u0435\u0442\u0441\u044F.",
              "\u041F\u043E\u0441\u043B\u0435 \u0441\u0431\u0440\u043E\u0441\u0430 \u043E\u0442\u043A\u0440\u044B\u0432\u0430\u0435\u0442\u0441\u044F \u0441\u0442\u0430\u0440\u0442\u043E\u0432\u0430\u044F \u043A\u0430\u0440\u0442\u0430. \u0415\u0441\u043B\u0438 \u044D\u0442\u043E \u0432\u0430\u043B\u0435\u0442, \u0441\u0434\u0430\u044E\u0449\u0438\u0439 \u0441\u0440\u0430\u0437\u0443 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u0434\u0432\u0430 \u043E\u0447\u043A\u0430. \u041F\u0435\u0440\u0432\u044B\u043C \u0445\u043E\u0434\u0438\u0442 \u0434\u0440\u0443\u0433\u043E\u0439 \u0438\u0433\u0440\u043E\u043A. \u041F\u043E \u043E\u0447\u0435\u0440\u0435\u0434\u0438 \u0432\u044B\u043A\u043B\u0430\u0434\u044B\u0432\u0430\u0439\u0442\u0435 \u043F\u043E \u043A\u0430\u0440\u0442\u0435, \u043D\u0435 \u043F\u0440\u0435\u0432\u044B\u0448\u0430\u044F \u043E\u0431\u0449\u0443\u044E \u0441\u0443\u043C\u043C\u0443 31. \u0422\u0443\u0437 \u0441\u0442\u043E\u0438\u0442 \u043E\u0434\u043D\u043E \u043E\u0447\u043A\u043E, \u0447\u0438\u0441\u043B\u043E\u0432\u044B\u0435 \u043A\u0430\u0440\u0442\u044B \u2014 \u0441\u0432\u043E\u0451 \u0447\u0438\u0441\u043B\u043E, \u0432\u0430\u043B\u0435\u0442, \u0434\u0430\u043C\u0430 \u0438 \u043A\u043E\u0440\u043E\u043B\u044C \u2014 \u0434\u0435\u0441\u044F\u0442\u044C.",
              "\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u041F\u0430\u0441, \u0435\u0441\u043B\u0438 \u043D\u0438 \u043E\u0434\u043D\u0430 \u043A\u0430\u0440\u0442\u0430 \u043D\u0435 \u0443\u043A\u043B\u0430\u0434\u044B\u0432\u0430\u0435\u0442\u0441\u044F \u0432 \u043F\u0440\u0435\u0434\u0435\u043B. \u0421\u043E\u043F\u0435\u0440\u043D\u0438\u043A \u043C\u043E\u0436\u0435\u0442 \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0438\u0442\u044C \u0432\u044B\u043A\u043B\u0430\u0434\u044B\u0432\u0430\u0442\u044C \u043A\u0430\u0440\u0442\u044B. \u041A\u043E\u0433\u0434\u0430 \u043E\u0431\u0430 \u0431\u043E\u043B\u044C\u0448\u0435 \u043D\u0435 \u043C\u043E\u0433\u0443\u0442 \u0445\u043E\u0434\u0438\u0442\u044C, \u0441\u044B\u0433\u0440\u0430\u0432\u0448\u0438\u0439 \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u044E\u044E \u043A\u0430\u0440\u0442\u0443 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u043E\u0434\u043D\u043E \u043E\u0447\u043A\u043E, \u0430 \u0441\u0443\u043C\u043C\u0430 \u0441\u0431\u0440\u0430\u0441\u044B\u0432\u0430\u0435\u0442\u0441\u044F. \u0420\u043E\u0432\u043D\u043E 31 \u0434\u0430\u0451\u0442 \u0432\u043C\u0435\u0441\u0442\u043E \u044D\u0442\u043E\u0433\u043E \u0434\u0432\u0430 \u043E\u0447\u043A\u0430. \u041F\u043E\u0441\u043B\u0435 \u0441\u0431\u0440\u043E\u0441\u0430 \u0445\u043E\u0434\u0438\u0442 \u0434\u0440\u0443\u0433\u043E\u0439 \u0438\u0433\u0440\u043E\u043A, \u0435\u0441\u043B\u0438 \u0443 \u043D\u0435\u0433\u043E \u043E\u0441\u0442\u0430\u043B\u0438\u0441\u044C \u043A\u0430\u0440\u0442\u044B."),
            rule_section(:scoring, "\u041D\u0430\u0447\u0438\u0441\u043B\u0435\u043D\u0438\u0435 \u0438 \u043F\u043E\u0434\u0441\u0447\u0451\u0442 \u043E\u0447\u043A\u043E\u0432",
              "\u041F\u0440\u0438 \u0432\u044B\u043A\u043B\u0430\u0434\u044B\u0432\u0430\u043D\u0438\u0438 \u0441\u0443\u043C\u043C\u0430 15 \u0434\u0430\u0451\u0442 \u0434\u0432\u0430 \u043E\u0447\u043A\u0430. \u0414\u0432\u0435, \u0442\u0440\u0438 \u0438\u043B\u0438 \u0447\u0435\u0442\u044B\u0440\u0435 \u043A\u0430\u0440\u0442\u044B \u043E\u0434\u043D\u043E\u0433\u043E \u0434\u043E\u0441\u0442\u043E\u0438\u043D\u0441\u0442\u0432\u0430 \u043F\u043E\u0434\u0440\u044F\u0434 \u0434\u0430\u044E\u0442 2, 6 \u0438\u043B\u0438 12 \u043E\u0447\u043A\u043E\u0432. \u041F\u043E\u0441\u043B\u0435\u0434\u043E\u0432\u0430\u0442\u0435\u043B\u044C\u043D\u043E\u0441\u0442\u044C \u0438\u0437 \u0442\u0440\u0451\u0445 \u0438 \u0431\u043E\u043B\u0435\u0435 \u0441\u043E\u0441\u0435\u0434\u043D\u0438\u0445 \u0434\u043E\u0441\u0442\u043E\u0438\u043D\u0441\u0442\u0432 \u0432 \u043A\u043E\u043D\u0446\u0435 \u0440\u044F\u0434\u0430 \u0434\u0430\u0451\u0442 \u043F\u043E \u043E\u0447\u043A\u0443 \u0437\u0430 \u043A\u0430\u0440\u0442\u0443 \u043D\u0435\u0437\u0430\u0432\u0438\u0441\u0438\u043C\u043E \u043E\u0442 \u043F\u043E\u0440\u044F\u0434\u043A\u0430 \u0432\u044B\u043A\u043B\u0430\u0434\u044B\u0432\u0430\u043D\u0438\u044F: 3, 5, 4 \u0434\u0430\u044E\u0442 \u0442\u0440\u0438 \u043E\u0447\u043A\u0430.",
              "\u041A\u043E\u0433\u0434\u0430 \u043A\u0430\u0440\u0442\u044B \u0441\u044B\u0433\u0440\u0430\u043D\u044B, \u043F\u043E\u0434\u0441\u0447\u0438\u0442\u044B\u0432\u0430\u044E\u0442\u0441\u044F \u0440\u0443\u043A\u0430 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u0430 \u0441\u0434\u0430\u044E\u0449\u0435\u0433\u043E, \u0440\u0443\u043A\u0430 \u0441\u0434\u0430\u044E\u0449\u0435\u0433\u043E \u0438 \u043A\u0440\u0438\u0431, \u043A\u0430\u0436\u0434\u044B\u0439 \u0440\u0430\u0437 \u0441\u043E \u0441\u0442\u0430\u0440\u0442\u043E\u0432\u043E\u0439 \u043A\u0430\u0440\u0442\u043E\u0439. \u041A\u0430\u0436\u0434\u0430\u044F \u043A\u043E\u043C\u0431\u0438\u043D\u0430\u0446\u0438\u044F \u0441 \u0441\u0443\u043C\u043C\u043E\u0439 15 \u0438 \u043A\u0430\u0436\u0434\u0430\u044F \u043F\u0430\u0440\u0430 \u0434\u0430\u044E\u0442 \u0434\u0432\u0430 \u043E\u0447\u043A\u0430. \u0421\u0447\u0438\u0442\u0430\u0435\u0442\u0441\u044F \u043A\u0430\u0436\u0434\u0430\u044F \u0441\u0430\u043C\u0430\u044F \u0434\u043B\u0438\u043D\u043D\u0430\u044F \u043F\u043E\u0441\u043B\u0435\u0434\u043E\u0432\u0430\u0442\u0435\u043B\u044C\u043D\u043E\u0441\u0442\u044C \u043E\u0442 \u0442\u0440\u0451\u0445 \u043A\u0430\u0440\u0442: \u043F\u043E \u043E\u0447\u043A\u0443 \u0437\u0430 \u043A\u0430\u0440\u0442\u0443; \u043E\u0434\u0438\u043D\u0430\u043A\u043E\u0432\u044B\u0435 \u0434\u043E\u0441\u0442\u043E\u0438\u043D\u0441\u0442\u0432\u0430 \u043C\u043E\u0433\u0443\u0442 \u0441\u043E\u0437\u0434\u0430\u0432\u0430\u0442\u044C \u043D\u0435\u0441\u043A\u043E\u043B\u044C\u043A\u043E \u043F\u043E\u0441\u043B\u0435\u0434\u043E\u0432\u0430\u0442\u0435\u043B\u044C\u043D\u043E\u0441\u0442\u0435\u0439. \u0427\u0435\u0442\u044B\u0440\u0435 \u043A\u0430\u0440\u0442\u044B \u043E\u0434\u043D\u043E\u0439 \u043C\u0430\u0441\u0442\u0438 \u0432 \u0440\u0443\u043A\u0435 \u0434\u0430\u044E\u0442 \u0447\u0435\u0442\u044B\u0440\u0435 \u043E\u0447\u043A\u0430, \u0430 \u0441\u0442\u0430\u0440\u0442\u043E\u0432\u0430\u044F \u0442\u043E\u0439 \u0436\u0435 \u043C\u0430\u0441\u0442\u0438 \u2014 \u043F\u044F\u0442\u043E\u0435. \u0412 \u043A\u0440\u0438\u0431\u0435 \u0434\u043E\u043B\u0436\u043D\u044B \u0441\u043E\u0432\u043F\u0430\u0434\u0430\u0442\u044C \u043C\u0430\u0441\u0442\u0438 \u0432\u0441\u0435\u0445 \u043F\u044F\u0442\u0438 \u043A\u0430\u0440\u0442. \u0412\u0430\u043B\u0435\u0442 \u043C\u0430\u0441\u0442\u0438 \u0441\u0442\u0430\u0440\u0442\u043E\u0432\u043E\u0439 \u043A\u0430\u0440\u0442\u044B \u0434\u043E\u0431\u0430\u0432\u043B\u044F\u0435\u0442 \u043E\u0434\u043D\u043E \u043E\u0447\u043A\u043E.",
              "\u0418\u0433\u0440\u0430 \u043F\u043E\u043A\u0430\u0437\u044B\u0432\u0430\u0435\u0442 \u043A\u0430\u0440\u0442\u044B \u0434\u043B\u044F \u043F\u043E\u0434\u0441\u0447\u0451\u0442\u0430. \u041D\u0430\u0436\u043C\u0438\u0442\u0435 Enter \u0438 \u0443\u043A\u0430\u0436\u0438\u0442\u0435 \u043E\u0447\u043A\u0438. \u041F\u0440\u0438 \u043E\u0448\u0438\u0431\u043A\u0435 \u0432\u0430\u043C \u0437\u0430\u0441\u0447\u0438\u0442\u044B\u0432\u0430\u0435\u0442\u0441\u044F \u043D\u0435 \u0431\u043E\u043B\u044C\u0448\u0435 \u043F\u0440\u0430\u0432\u0438\u043B\u044C\u043D\u043E\u0433\u043E \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0430, \u0430 \u0440\u0430\u0437\u043D\u0438\u0446\u0443 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A. \u041C\u0430\u0442\u0447 \u0437\u0430\u043A\u0430\u043D\u0447\u0438\u0432\u0430\u0435\u0442\u0441\u044F \u0441\u0440\u0430\u0437\u0443 \u043F\u0440\u0438 \u0434\u043E\u0441\u0442\u0438\u0436\u0435\u043D\u0438\u0438 121 \u043E\u0447\u043A\u0430, \u0432 \u0442\u043E\u043C \u0447\u0438\u0441\u043B\u0435 \u043F\u0440\u0438 \u0432\u044B\u043A\u043B\u0430\u0434\u044B\u0432\u0430\u043D\u0438\u0438 \u0438 \u043F\u043E\u0434\u0441\u0447\u0451\u0442\u0435."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0448\u0438 \u0443\u043F\u0440\u0430\u0432\u043B\u0435\u043D\u0438\u044F",
              "\u0421\u0442\u0440\u0435\u043B\u043A\u0438: \u043F\u0440\u043E\u0441\u043C\u0430\u0442\u0440\u0438\u0432\u0430\u0442\u044C \u043A\u0430\u0440\u0442\u044B \u0438\u043B\u0438 \u043F\u0443\u043D\u043A\u0442\u044B \u043C\u0435\u043D\u044E.",
              "Enter: \u043E\u0442\u043B\u043E\u0436\u0438\u0442\u044C \u0438\u043B\u0438 \u0441\u044B\u0433\u0440\u0430\u0442\u044C \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u0443\u044E \u043A\u0430\u0440\u0442\u0443; \u043F\u0440\u0438 \u043F\u043E\u0434\u0441\u0447\u0451\u0442\u0435 \u043E\u0442\u043A\u0440\u044B\u0442\u044C \u043F\u043E\u043B\u0435 \u043E\u0447\u043A\u043E\u0432. \u0415\u0441\u043B\u0438 \u043D\u0438 \u043E\u0434\u043D\u0430 \u043A\u0430\u0440\u0442\u0430 \u043D\u0435 \u043F\u043E\u0434\u0445\u043E\u0434\u0438\u0442, \u0432\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u041F\u0430\u0441.",
              "D: \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u0441\u0442\u0430\u0440\u0442\u043E\u0432\u0443\u044E \u043A\u0430\u0440\u0442\u0443.",
              "V: \u0443\u0437\u043D\u0430\u0442\u044C, \u043A\u043E\u043C\u0443 \u043F\u0440\u0438\u043D\u0430\u0434\u043B\u0435\u0436\u0438\u0442 \u043A\u0440\u0438\u0431.",
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
