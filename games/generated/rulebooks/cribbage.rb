# Generated from tools/data/rulebooks/cribbage.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class CribbageTable
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:play, GameRoomRules.translate("Playing Cribbage"),
            GameRoomRules.translate("Cribbage is for two to six players. The first player or team to reach the table's point target wins. In the table settings, enter a positive number under Points to win. The default is 121. The deal rotates after each hand, and the crib scores for the dealer."),
            GameRoomRules.translate("With two players, deal six to each and discard two each. With three or four, deal five to each and discard one each. With three players, add a card from the deck to the crib. With five, deal four to the dealer and five to the others. With six, deal five to the dealer and six to the others. In the last two variants everyone except the dealer discards one."),
            GameRoomRules.translate("Turn up the starter after discards. A jack scores two for the dealer. Starting after the dealer, play one card at a time without exceeding 31. Aces count one, court cards ten, and other cards their face value."),
            GameRoomRules.translate("Choose Go if no card fits. Skip players who passed or have no cards. If nobody can play, the last player to play scores one and the total resets. Reaching 31 scores two instead. The next player with cards leads.")),
          rule_section(:scoring, GameRoomRules.translate("Scoring and counting"),
            GameRoomRules.translate("During play, a total of 15 scores two. Two, three or four consecutive cards of the same rank score 2, 6 or 12. A run of at least three consecutive ranks at the end of the sequence scores its length, regardless of their playing order. For example, 3, 5, 4 scores three."),
            GameRoomRules.translate("Count all hands in seating order after the dealer, then the crib. Include the starter. Each combination totalling 15 and each pair score two. Each longest run of at least three scores one per card. A flush scores one per matching card when all hand cards match. In the crib the starter must also match. A jack matching the starter's suit adds one."),
            GameRoomRules.translate("Press Enter to submit the score. If it is wrong, the next opponent receives the difference and you receive at most the correct score. In a six-player game each hand and the crib have five cards plus the starter, and the maximum claim is 39."),
            GameRoomRules.translate("When a played card scores, you hear a short cue. Reaching exactly 31 has its own sound. A third sound signals that all cards have been played and counting is about to begin.")),
          rule_section(:teams, GameRoomRules.translate("Team play"),
            GameRoomRules.translate("Teams of two are available with four or six players; teams of three require six. Teammates share points and sit in alternating team order. Keep cards in your hand private.")),
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
              "Cribbage hraj\u00ED dva a\u017E \u0161est hr\u00E1\u010D\u016F. Vyhr\u00E1v\u00E1 hr\u00E1\u010D nebo t\u00FDm, kter\u00FD jako prvn\u00ED dos\u00E1hne c\u00EDlov\u00E9ho po\u010Dtu bod\u016F. V nastaven\u00ED stolu zadejte kladn\u00FD po\u010Det bod\u016F pot\u0159ebn\u00FDch k v\u00FDh\u0159e. V\u00FDchoz\u00ED hodnota je 121. Rozd\u00E1vaj\u00EDc\u00ED se po ka\u017Ed\u00E9m rozd\u00E1n\u00ED st\u0159\u00EDd\u00E1 a z\u00EDsk\u00E1v\u00E1 body za crib.",
              "Ve dvou se rozd\u00E1v\u00E1 po \u0161esti kart\u00E1ch a ka\u017Ed\u00FD dv\u011B odlo\u017E\u00ED. Ve t\u0159ech nebo \u010Dty\u0159ech se rozd\u00E1v\u00E1 po p\u011Bti a ka\u017Ed\u00FD jednu odlo\u017E\u00ED. Ve t\u0159ech se \u010Dtvrt\u00E1 karta do cribu vezme z bal\u00ED\u010Dku. V p\u011Bti dostane rozd\u00E1vaj\u00EDc\u00ED \u010Dty\u0159i karty a ostatn\u00ED p\u011Bt. V \u0161esti dostane rozd\u00E1vaj\u00EDc\u00ED p\u011Bt a ostatn\u00ED \u0161est. V obou posledn\u00EDch variant\u00E1ch odkl\u00E1daj\u00ED jednu kartu jen ostatn\u00ED.",
              "Po odlo\u017Een\u00ED se oto\u010D\u00ED startovn\u00ED karta. Kluk p\u0159inese rozd\u00E1vaj\u00EDc\u00EDmu dva body. Za\u010D\u00EDn\u00E1 hr\u00E1\u010D po rozd\u00E1vaj\u00EDc\u00EDm. Hraje se po jedn\u00E9 kart\u011B do sou\u010Dtu 31. Eso m\u00E1 hodnotu jedna, figury deset a ostatn\u00ED karty svou hodnotu.",
              "Zvolte Pas, pokud \u017E\u00E1dn\u00E1 karta nep\u0159ipadne v \u00FAvahu. Hr\u00E1\u010Di bez karet nebo po pasu se p\u0159eskakuj\u00ED. Jakmile nikdo nem\u016F\u017Ee pokra\u010Dovat, posledn\u00ED hr\u00E1\u010D dostane bod; p\u0159esn\u011B 31 p\u0159in\u00E1\u0161\u00ED dva body. Sou\u010Det se vynuluje a za\u010D\u00EDn\u00E1 dal\u0161\u00ED hr\u00E1\u010D s kartami."),
            rule_section(:scoring, "Bodov\u00E1n\u00ED a po\u010D\u00EDt\u00E1n\u00ED",
              "P\u0159i vykl\u00E1d\u00E1n\u00ED d\u00E1v\u00E1 sou\u010Det 15 dva body. Dv\u011B, t\u0159i nebo \u010Dty\u0159i po sob\u011B zahran\u00E9 karty stejn\u00E9 hodnoty d\u00E1vaj\u00ED 2, 6 nebo 12 bod\u016F. Postupka nejm\u00E9n\u011B t\u0159\u00ED posledn\u00EDch karet d\u00E1v\u00E1 bod za kartu bez ohledu na po\u0159ad\u00ED. Nap\u0159\u00EDklad 3, 5, 4 d\u00E1v\u00E1 t\u0159i body.",
              "Po\u010D\u00EDtejte nejprve ruce v po\u0159ad\u00ED od hr\u00E1\u010De po rozd\u00E1vaj\u00EDc\u00EDm a nakonec crib. Zapo\u010D\u00EDtejte startovn\u00ED kartu. Ka\u017Ed\u00E1 kombinace za 15 a ka\u017Ed\u00FD p\u00E1r d\u00E1vaj\u00ED dva body. Ka\u017Ed\u00E1 nejdel\u0161\u00ED postupka alespo\u0148 t\u0159\u00ED karet d\u00E1v\u00E1 bod za kartu. Barva boduje, pokud jsou v\u0161echny karty v ruce stejn\u00E9 barvy. V cribu mus\u00ED souhlasit i startovn\u00ED karta. Kluk jej\u00ED barvy p\u0159in\u00E1\u0161\u00ED bod.",
              "Stiskn\u011Bte Enter a zadejte v\u00FDsledek. P\u0159i chyb\u011B dostane rozd\u00EDl n\u00E1sleduj\u00EDc\u00ED soupe\u0159 a vy z\u00EDsk\u00E1te nejv\u00FD\u0161e spr\u00E1vn\u00E9 sk\u00F3re. V \u0161esti m\u00E1 ka\u017Ed\u00E1 ruka i crib p\u011Bt karet plus startovn\u00ED kartu a lze zadat nejv\u00FD\u0161e 39 bod\u016F.",
              "Bodovan\u00FD tah doprov\u00E1z\u00ED kr\u00E1tk\u00FD zvuk. Sou\u010Det p\u0159esn\u011B 31 m\u00E1 vlastn\u00ED zvuk. T\u0159et\u00ED sign\u00E1l zazn\u00ED po zahr\u00E1n\u00ED v\u0161ech karet, t\u011Bsn\u011B p\u0159ed po\u010D\u00EDt\u00E1n\u00EDm bod\u016F."),
            rule_section(:teams, "T\u00FDmov\u00E1 hra",
              "Dvojice jsou mo\u017En\u00E9 p\u0159i \u010Dty\u0159ech nebo \u0161esti hr\u00E1\u010D\u00EDch, trojice p\u0159i \u0161esti. T\u00FDm m\u00E1 spole\u010Dn\u00E9 sk\u00F3re a t\u00FDmy se u stolu st\u0159\u00EDdaj\u00ED. Karty neukazujte ani spoluhr\u00E1\u010D\u016Fm."),
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
              "Cribbage is for two to six players. The first player or team to reach the table's point target wins. In the table settings, enter a positive number under Points to win. The default is 121. The deal rotates after each hand, and the crib scores for the dealer.",
              "With two players, deal six to each and discard two each. With three or four, deal five to each and discard one each. With three players, add a card from the deck to the crib. With five, deal four to the dealer and five to the others. With six, deal five to the dealer and six to the others. In the last two variants everyone except the dealer discards one.",
              "Turn up the starter after discards. A jack scores two for the dealer. Starting after the dealer, play one card at a time without exceeding 31. Aces count one, court cards ten, and other cards their face value.",
              "Choose Go if no card fits. Skip players who passed or have no cards. If nobody can play, the last player to play scores one and the total resets. Reaching 31 scores two instead. The next player with cards leads."),
            rule_section(:scoring, "Scoring and counting",
              "During play, a total of 15 scores two. Two, three or four consecutive cards of the same rank score 2, 6 or 12. A run of at least three consecutive ranks at the end of the sequence scores its length, regardless of their playing order. For example, 3, 5, 4 scores three.",
              "Count all hands in seating order after the dealer, then the crib. Include the starter. Each combination totalling 15 and each pair score two. Each longest run of at least three scores one per card. A flush scores one per matching card when all hand cards match. In the crib the starter must also match. A jack matching the starter's suit adds one.",
              "Press Enter to submit the score. If it is wrong, the next opponent receives the difference and you receive at most the correct score. In a six-player game each hand and the crib have five cards plus the starter, and the maximum claim is 39.",
              "When a played card scores, you hear a short cue. Reaching exactly 31 has its own sound. A third sound signals that all cards have been played and counting is about to begin."),
            rule_section(:teams, "Team play",
              "Teams of two are available with four or six players; teams of three require six. Teammates share points and sit in alternating team order. Keep cards in your hand private."),
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
              "Pueden jugar de dos a seis personas. Gana el primer jugador o equipo que alcanza la puntuaci\u00F3n objetivo. En los ajustes de la mesa, introduce un n\u00FAmero positivo de puntos para ganar. El valor predeterminado es 121. El turno de repartir rota y el crib punt\u00FAa para quien reparte.",
              "Con dos se reparten seis cartas por persona y se descartan dos. Con tres o cuatro se reparten cinco y se descarta una. Con tres se a\u00F1ade al crib una carta del mazo. Con cinco, quien reparte recibe cuatro y el resto cinco. Con seis recibe cinco y el resto seis. En estas dos \u00FAltimas variantes solo los dem\u00E1s descartan una.",
              "Tras los descartes se descubre la carta inicial. Una jota da dos puntos a quien reparte. Empieza la siguiente persona. Se juega una carta por turno sin superar 31. El as vale uno, las figuras diez y las dem\u00E1s cartas su valor.",
              "Elige Paso si ninguna carta cabe. Se salta a quienes hayan pasado o no tengan cartas. Si nadie puede seguir, la \u00FAltima persona que jug\u00F3 suma un punto. Llegar a 31 da dos. El total vuelve a cero y empieza la siguiente persona con cartas."),
            rule_section(:scoring, "Puntuaci\u00F3n y recuento",
              "Durante el juego, sumar 15 da dos puntos. Dos, tres o cuatro cartas consecutivas del mismo valor dan 2, 6 o 12 puntos. Una escalera de al menos tres valores consecutivos al final de la secuencia punt\u00FAa su longitud, sin importar el orden de juego: 3, 5, 4 da tres puntos.",
              "Contad las manos por orden a partir de la persona que sigue a quien reparti\u00F3 y al final el crib. Incluid la carta inicial. Cada combinaci\u00F3n de 15 y cada pareja dan dos puntos. Cada escalera de longitud m\u00E1xima de tres cartas o m\u00E1s da un punto por carta. El color requiere que todas las cartas de la mano sean del mismo palo; en el crib debe coincidir tambi\u00E9n la carta inicial. Una jota del palo inicial da un punto.",
              "Pulsa Intro para declarar la puntuaci\u00F3n. Si te equivocas, el siguiente rival recibe la diferencia y t\u00FA recibes como m\u00E1ximo la puntuaci\u00F3n correcta. Con seis jugadores, cada mano y el crib tienen cinco cartas m\u00E1s la inicial, con un m\u00E1ximo de 39 puntos.",
              "Oir\u00E1s un sonido breve cuando una carta jugada d\u00E9 puntos. Llegar exactamente a 31 tiene su propio sonido. Un tercer sonido indica que se han jugado todas las cartas y va a comenzar el recuento."),
            rule_section(:teams, "Juego por equipos",
              "Se juega en parejas con cuatro o seis jugadores y en tr\u00EDos con seis. Cada equipo comparte puntuaci\u00F3n y los asientos alternan entre equipos. Oculta tus cartas tambi\u00E9n a tus compa\u00F1eros."),
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
              "W Cribbage gra od dw\u00F3ch do sze\u015Bciu os\u00F3b. Wygrywa gracz lub dru\u017Cyna, kt\u00F3ra pierwsza osi\u0105gnie cel punktowy. W ustawieniach sto\u0142u mo\u017Cna wpisa\u0107 dowoln\u0105 dodatni\u0105 liczb\u0119 punkt\u00F3w potrzebnych do wygranej. Domy\u015Blnie jest to 121. Rozdaj\u0105cy zmienia si\u0119 po ka\u017Cdym rozdaniu i otrzymuje punkty za crib.",
              "Przy dw\u00F3ch osobach ka\u017Cdy dostaje sze\u015B\u0107 kart i odk\u0142ada dwie. Przy trzech lub czterech ka\u017Cdy dostaje pi\u0119\u0107 i odk\u0142ada jedn\u0105. Przy trzech czwarta karta cribu pochodzi z talii. Przy pi\u0119ciu osobach rozdaj\u0105cy dostaje cztery karty, a pozostali po pi\u0119\u0107. Przy sze\u015Bciu rozdaj\u0105cy dostaje pi\u0119\u0107, a pozostali po sze\u015B\u0107. W dw\u00F3ch ostatnich wariantach tylko pozostali odk\u0142adaj\u0105 po jednej karcie.",
              "Po od\u0142o\u017Ceniu kart odkrywa si\u0119 kart\u0119 startow\u0105. Walet daje rozdaj\u0105cemu dwa punkty. Zaczyna osoba po rozdaj\u0105cym. Zagrywajcie kolejno po jednej karcie, bez przekraczania 31. As liczy si\u0119 za jeden, figury za dziesi\u0119\u0107, a karty liczbowe wed\u0142ug warto\u015Bci.",
              "Wybierz Pas, je\u015Bli \u017Cadna karta nie mie\u015Bci si\u0119 w limicie. Pomija si\u0119 osoby, kt\u00F3re spasowa\u0142y lub nie maj\u0105 kart. Gdy nikt nie mo\u017Ce do\u0142o\u017Cy\u0107 karty, ostatni zagrywaj\u0105cy dostaje punkt, a suma wraca do zera. Dok\u0142adnie 31 daje dwa punkty. Zaczyna nast\u0119pna osoba, kt\u00F3ra ma karty."),
            rule_section(:scoring, "Punktacja i liczenie uk\u0142ad\u00F3w",
              "Podczas zagrywania suma 15 daje dwa punkty. Dwie, trzy lub cztery kolejne karty tej samej warto\u015Bci daj\u0105 odpowiednio 2, 6 lub 12 punkt\u00F3w. Sekwencja co najmniej trzech kolejnych warto\u015Bci na ko\u0144cu zagrywanych kart daje punkt za ka\u017Cd\u0105 kart\u0119, niezale\u017Cnie od kolejno\u015Bci ich po\u0142o\u017Cenia. Na przyk\u0142ad 3, 5, 4 daje trzy punkty.",
              "Policzcie r\u0119ce w kolejno\u015Bci od osoby po rozdaj\u0105cym, a na ko\u0144cu crib. Doliczcie kart\u0119 startow\u0105. Ka\u017Cda kombinacja daj\u0105ca 15 i ka\u017Cda para s\u0105 warte dwa punkty. Ka\u017Cda najd\u0142u\u017Csza sekwencja od trzech kart daje punkt za kart\u0119. Kolor punktuje, gdy ca\u0142a r\u0119ka jest jednego koloru. W cribie karta startowa r\u00F3wnie\u017C musi pasowa\u0107. Walet w kolorze karty startowej daje punkt.",
              "Naci\u015Bnij Enter, by poda\u0107 punktacj\u0119. Przy pomy\u0142ce nast\u0119pny przeciwnik otrzymuje r\u00F3\u017Cnic\u0119, a ty dostajesz najwy\u017Cej prawid\u0142ow\u0105 liczb\u0119 punkt\u00F3w. Przy sze\u015Bciu osobach w ka\u017Cdej r\u0119ce i w cribie jest pi\u0119\u0107 kart plus karta startowa, a maksymalny wynik to 39.",
              "Za punktuj\u0105ce zagranie us\u0142yszysz kr\u00F3tki sygna\u0142. Osi\u0105gni\u0119cie dok\u0142adnie 31 ma w\u0142asny d\u017Awi\u0119k. Trzeci sygna\u0142 rozlega si\u0119 po zagraniu wszystkich kart, tu\u017C przed liczeniem uk\u0142ad\u00F3w."),
            rule_section(:teams, "Gra dru\u017Cynowa",
              "Pary s\u0105 dost\u0119pne przy czterech lub sze\u015Bciu osobach, a tr\u00F3jki przy sze\u015Bciu. Partnerzy maj\u0105 wsp\u00F3ln\u0105 punktacj\u0119 i zajmuj\u0105 miejsca na zmian\u0119 z innymi dru\u017Cynami. Nie pokazuj kart nawet partnerom."),
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
              "\u0412 \u043A\u0440\u0438\u0431\u0431\u0435\u0434\u0436 \u0438\u0433\u0440\u0430\u044E\u0442 \u043E\u0442 \u0434\u0432\u0443\u0445 \u0434\u043E \u0448\u0435\u0441\u0442\u0438 \u0447\u0435\u043B\u043E\u0432\u0435\u043A. \u041F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u0438\u0433\u0440\u043E\u043A \u0438\u043B\u0438 \u043A\u043E\u043C\u0430\u043D\u0434\u0430, \u043A\u043E\u0442\u043E\u0440\u044B\u0435 \u043F\u0435\u0440\u0432\u044B\u043C\u0438 \u043D\u0430\u0431\u0438\u0440\u0430\u044E\u0442 \u043D\u0443\u0436\u043D\u043E\u0435 \u043A\u043E\u043B\u0438\u0447\u0435\u0441\u0442\u0432\u043E \u043E\u0447\u043A\u043E\u0432. \u0412 \u043D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0430\u0445 \u0441\u0442\u043E\u043B\u0430 \u043C\u043E\u0436\u043D\u043E \u0443\u043A\u0430\u0437\u0430\u0442\u044C \u043F\u043E\u043B\u043E\u0436\u0438\u0442\u0435\u043B\u044C\u043D\u043E\u0435 \u0447\u0438\u0441\u043B\u043E \u043E\u0447\u043A\u043E\u0432 \u0434\u043B\u044F \u043F\u043E\u0431\u0435\u0434\u044B. \u041F\u043E \u0443\u043C\u043E\u043B\u0447\u0430\u043D\u0438\u044E \u044D\u0442\u043E 121. \u0421\u0434\u0430\u044E\u0449\u0438\u0439 \u043C\u0435\u043D\u044F\u0435\u0442\u0441\u044F \u043F\u043E\u0441\u043B\u0435 \u043A\u0430\u0436\u0434\u043E\u0439 \u0441\u0434\u0430\u0447\u0438 \u0438 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u043E\u0447\u043A\u0438 \u0437\u0430 \u043A\u0440\u0438\u0431.",
              "\u0412\u0434\u0432\u043E\u0451\u043C \u0440\u0430\u0437\u0434\u0430\u044E\u0442 \u043F\u043E \u0448\u0435\u0441\u0442\u044C \u043A\u0430\u0440\u0442 \u0438 \u0441\u0431\u0440\u0430\u0441\u044B\u0432\u0430\u044E\u0442 \u043F\u043E \u0434\u0432\u0435. \u0412\u0442\u0440\u043E\u0451\u043C \u0438\u043B\u0438 \u0432\u0447\u0435\u0442\u0432\u0435\u0440\u043E\u043C \u0440\u0430\u0437\u0434\u0430\u044E\u0442 \u043F\u043E \u043F\u044F\u0442\u044C \u0438 \u0441\u0431\u0440\u0430\u0441\u044B\u0432\u0430\u044E\u0442 \u043F\u043E \u043E\u0434\u043D\u043E\u0439. \u0412\u0442\u0440\u043E\u0451\u043C \u0447\u0435\u0442\u0432\u0451\u0440\u0442\u0443\u044E \u043A\u0430\u0440\u0442\u0443 \u043A\u0440\u0438\u0431\u0430 \u0431\u0435\u0440\u0443\u0442 \u0438\u0437 \u043A\u043E\u043B\u043E\u0434\u044B. \u0412\u043F\u044F\u0442\u0435\u0440\u043E\u043C \u0441\u0434\u0430\u044E\u0449\u0438\u0439 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u0447\u0435\u0442\u044B\u0440\u0435 \u043A\u0430\u0440\u0442\u044B, \u043E\u0441\u0442\u0430\u043B\u044C\u043D\u044B\u0435 \u043F\u043E \u043F\u044F\u0442\u044C. \u0412\u0448\u0435\u0441\u0442\u0435\u0440\u043E\u043C \u043E\u043D \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u043F\u044F\u0442\u044C, \u043E\u0441\u0442\u0430\u043B\u044C\u043D\u044B\u0435 \u043F\u043E \u0448\u0435\u0441\u0442\u044C. \u0412 \u0434\u0432\u0443\u0445 \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0438\u0445 \u0432\u0430\u0440\u0438\u0430\u043D\u0442\u0430\u0445 \u0441\u0434\u0430\u044E\u0449\u0438\u0439 \u043D\u0435 \u0441\u0431\u0440\u0430\u0441\u044B\u0432\u0430\u0435\u0442 \u043A\u0430\u0440\u0442\u044B, \u043E\u0441\u0442\u0430\u043B\u044C\u043D\u044B\u0435 \u0441\u0431\u0440\u0430\u0441\u044B\u0432\u0430\u044E\u0442 \u043F\u043E \u043E\u0434\u043D\u043E\u0439.",
              "\u041F\u043E\u0441\u043B\u0435 \u0441\u0431\u0440\u043E\u0441\u043E\u0432 \u043E\u0442\u043A\u0440\u044B\u0432\u0430\u044E\u0442 \u0441\u0442\u0430\u0440\u0442\u043E\u0432\u0443\u044E \u043A\u0430\u0440\u0442\u0443. \u0415\u0441\u043B\u0438 \u044D\u0442\u043E \u0432\u0430\u043B\u0435\u0442, \u0441\u0434\u0430\u044E\u0449\u0438\u0439 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u0434\u0432\u0430 \u043E\u0447\u043A\u0430. \u041D\u0430\u0447\u0438\u043D\u0430\u0435\u0442 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0438\u0439 \u0437\u0430 \u0441\u0434\u0430\u044E\u0449\u0438\u043C. \u0418\u0433\u0440\u0430\u0439\u0442\u0435 \u043F\u043E \u043E\u0434\u043D\u043E\u0439 \u043A\u0430\u0440\u0442\u0435, \u043D\u0435 \u043F\u0440\u0435\u0432\u044B\u0448\u0430\u044F 31. \u0422\u0443\u0437 \u0441\u0442\u043E\u0438\u0442 \u043E\u0434\u043D\u043E \u043E\u0447\u043A\u043E, \u043A\u0430\u0440\u0442\u0438\u043D\u043A\u0438 \u0434\u0435\u0441\u044F\u0442\u044C, \u043E\u0441\u0442\u0430\u043B\u044C\u043D\u044B\u0435 \u043A\u0430\u0440\u0442\u044B \u0441\u0447\u0438\u0442\u0430\u044E\u0442\u0441\u044F \u043F\u043E \u043D\u043E\u043C\u0438\u043D\u0430\u043B\u0443.",
              "\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u00AB\u041F\u0430\u0441\u00BB, \u0435\u0441\u043B\u0438 \u043D\u0438 \u043E\u0434\u043D\u0430 \u043A\u0430\u0440\u0442\u0430 \u043D\u0435 \u043F\u043E\u0434\u0445\u043E\u0434\u0438\u0442. \u0418\u0433\u0440\u043E\u043A\u043E\u0432 \u0431\u0435\u0437 \u043A\u0430\u0440\u0442 \u0438 \u0442\u0435\u0445, \u043A\u0442\u043E \u0441\u043F\u0430\u0441\u043E\u0432\u0430\u043B, \u043F\u0440\u043E\u043F\u0443\u0441\u043A\u0430\u044E\u0442. \u0415\u0441\u043B\u0438 \u043D\u0438\u043A\u0442\u043E \u043D\u0435 \u043C\u043E\u0436\u0435\u0442 \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0438\u0442\u044C, \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0438\u0439 \u0441\u0434\u0435\u043B\u0430\u0432\u0448\u0438\u0439 \u0445\u043E\u0434 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u043E\u0447\u043A\u043E. \u0417\u0430 \u0440\u043E\u0432\u043D\u043E 31 \u0434\u0430\u044E\u0442 \u0434\u0432\u0430. \u0421\u0443\u043C\u043C\u0430 \u043E\u0431\u043D\u0443\u043B\u044F\u0435\u0442\u0441\u044F, \u043D\u0430\u0447\u0438\u043D\u0430\u0435\u0442 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0438\u0439 \u0438\u0433\u0440\u043E\u043A \u0441 \u043A\u0430\u0440\u0442\u0430\u043C\u0438."),
            rule_section(:scoring, "\u041D\u0430\u0447\u0438\u0441\u043B\u0435\u043D\u0438\u0435 \u0438 \u043F\u043E\u0434\u0441\u0447\u0451\u0442 \u043E\u0447\u043A\u043E\u0432",
              "\u041F\u0440\u0438 \u0432\u044B\u043A\u043B\u0430\u0434\u044B\u0432\u0430\u043D\u0438\u0438 \u0441\u0443\u043C\u043C\u0430 15 \u0434\u0430\u0451\u0442 \u0434\u0432\u0430 \u043E\u0447\u043A\u0430. \u0414\u0432\u0435, \u0442\u0440\u0438 \u0438\u043B\u0438 \u0447\u0435\u0442\u044B\u0440\u0435 \u043A\u0430\u0440\u0442\u044B \u043E\u0434\u043D\u043E\u0433\u043E \u0434\u043E\u0441\u0442\u043E\u0438\u043D\u0441\u0442\u0432\u0430 \u043F\u043E\u0434\u0440\u044F\u0434 \u0434\u0430\u044E\u0442 2, 6 \u0438\u043B\u0438 12 \u043E\u0447\u043A\u043E\u0432. \u041F\u043E\u0441\u043B\u0435\u0434\u043E\u0432\u0430\u0442\u0435\u043B\u044C\u043D\u043E\u0441\u0442\u044C \u0438\u0437 \u0442\u0440\u0451\u0445 \u0438 \u0431\u043E\u043B\u0435\u0435 \u0441\u043E\u0441\u0435\u0434\u043D\u0438\u0445 \u0434\u043E\u0441\u0442\u043E\u0438\u043D\u0441\u0442\u0432 \u0432 \u043A\u043E\u043D\u0446\u0435 \u0440\u044F\u0434\u0430 \u0434\u0430\u0451\u0442 \u043F\u043E \u043E\u0447\u043A\u0443 \u0437\u0430 \u043A\u0430\u0440\u0442\u0443 \u043D\u0435\u0437\u0430\u0432\u0438\u0441\u0438\u043C\u043E \u043E\u0442 \u043F\u043E\u0440\u044F\u0434\u043A\u0430 \u0432\u044B\u043A\u043B\u0430\u0434\u044B\u0432\u0430\u043D\u0438\u044F: 3, 5, 4 \u0434\u0430\u044E\u0442 \u0442\u0440\u0438 \u043E\u0447\u043A\u0430.",
              "\u0421\u0447\u0438\u0442\u0430\u0439\u0442\u0435 \u0440\u0443\u043A\u0438 \u043F\u043E \u043F\u043E\u0440\u044F\u0434\u043A\u0443 \u043E\u0442 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0435\u0433\u043E \u0437\u0430 \u0441\u0434\u0430\u044E\u0449\u0438\u043C, \u0437\u0430\u0442\u0435\u043C \u043A\u0440\u0438\u0431. \u0423\u0447\u0438\u0442\u044B\u0432\u0430\u0439\u0442\u0435 \u0441\u0442\u0430\u0440\u0442\u043E\u0432\u0443\u044E \u043A\u0430\u0440\u0442\u0443. \u041A\u0430\u0436\u0434\u0430\u044F \u043A\u043E\u043C\u0431\u0438\u043D\u0430\u0446\u0438\u044F \u043D\u0430 15 \u0438 \u043A\u0430\u0436\u0434\u0430\u044F \u043F\u0430\u0440\u0430 \u0434\u0430\u044E\u0442 \u0434\u0432\u0430 \u043E\u0447\u043A\u0430. \u041A\u0430\u0436\u0434\u0430\u044F \u0441\u0430\u043C\u0430\u044F \u0434\u043B\u0438\u043D\u043D\u0430\u044F \u043F\u043E\u0441\u043B\u0435\u0434\u043E\u0432\u0430\u0442\u0435\u043B\u044C\u043D\u043E\u0441\u0442\u044C \u0438\u0437 \u0442\u0440\u0451\u0445 \u0438\u043B\u0438 \u0431\u043E\u043B\u0435\u0435 \u043A\u0430\u0440\u0442 \u0434\u0430\u0451\u0442 \u043E\u0447\u043A\u043E \u0437\u0430 \u043A\u0430\u0440\u0442\u0443. \u0414\u043B\u044F \u0444\u043B\u0435\u0448\u0430 \u0432\u0441\u0435 \u043A\u0430\u0440\u0442\u044B \u0440\u0443\u043A\u0438 \u0434\u043E\u043B\u0436\u043D\u044B \u0431\u044B\u0442\u044C \u043E\u0434\u043D\u043E\u0439 \u043C\u0430\u0441\u0442\u0438, \u0430 \u0432 \u043A\u0440\u0438\u0431\u0435 \u0434\u043E\u043B\u0436\u043D\u0430 \u0441\u043E\u0432\u043F\u0430\u0441\u0442\u044C \u0438 \u0441\u0442\u0430\u0440\u0442\u043E\u0432\u0430\u044F \u043A\u0430\u0440\u0442\u0430. \u0412\u0430\u043B\u0435\u0442 \u0435\u0451 \u043C\u0430\u0441\u0442\u0438 \u0434\u0430\u0451\u0442 \u043E\u0447\u043A\u043E.",
              "\u041D\u0430\u0436\u043C\u0438\u0442\u0435 Enter \u0438 \u0443\u043A\u0430\u0436\u0438\u0442\u0435 \u0447\u0438\u0441\u043B\u043E \u043E\u0447\u043A\u043E\u0432. \u041F\u0440\u0438 \u043E\u0448\u0438\u0431\u043A\u0435 \u0440\u0430\u0437\u043D\u0438\u0446\u0443 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0438\u0439 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A, \u0430 \u0432\u0430\u043C \u043D\u0430\u0447\u0438\u0441\u043B\u044F\u044E\u0442 \u043D\u0435 \u0431\u043E\u043B\u044C\u0448\u0435 \u043F\u0440\u0430\u0432\u0438\u043B\u044C\u043D\u043E\u0439 \u0441\u0443\u043C\u043C\u044B. \u0412\u0448\u0435\u0441\u0442\u0435\u0440\u043E\u043C \u0432 \u043A\u0430\u0436\u0434\u043E\u0439 \u0440\u0443\u043A\u0435 \u0438 \u0432 \u043A\u0440\u0438\u0431\u0435 \u043F\u043E \u043F\u044F\u0442\u044C \u043A\u0430\u0440\u0442 \u043F\u043B\u044E\u0441 \u0441\u0442\u0430\u0440\u0442\u043E\u0432\u0430\u044F, \u043C\u0430\u043A\u0441\u0438\u043C\u0443\u043C 39 \u043E\u0447\u043A\u043E\u0432.",
              "\u041A\u043E\u0433\u0434\u0430 \u0432\u044B\u043B\u043E\u0436\u0435\u043D\u043D\u0430\u044F \u043A\u0430\u0440\u0442\u0430 \u043F\u0440\u0438\u043D\u043E\u0441\u0438\u0442 \u043E\u0447\u043A\u0438, \u0437\u0432\u0443\u0447\u0438\u0442 \u043A\u043E\u0440\u043E\u0442\u043A\u0438\u0439 \u0441\u0438\u0433\u043D\u0430\u043B. \u0414\u043B\u044F \u0441\u0443\u043C\u043C\u044B \u0440\u043E\u0432\u043D\u043E 31 \u0435\u0441\u0442\u044C \u043E\u0442\u0434\u0435\u043B\u044C\u043D\u044B\u0439 \u0437\u0432\u0443\u043A. \u0422\u0440\u0435\u0442\u0438\u0439 \u0441\u0438\u0433\u043D\u0430\u043B \u0437\u0432\u0443\u0447\u0438\u0442 \u043F\u043E\u0441\u043B\u0435 \u0440\u043E\u0437\u044B\u0433\u0440\u044B\u0448\u0430 \u0432\u0441\u0435\u0445 \u043A\u0430\u0440\u0442, \u043F\u0435\u0440\u0435\u0434 \u043F\u043E\u0434\u0441\u0447\u0451\u0442\u043E\u043C \u043E\u0447\u043A\u043E\u0432."),
            rule_section(:teams, "\u041A\u043E\u043C\u0430\u043D\u0434\u043D\u0430\u044F \u0438\u0433\u0440\u0430",
              "\u041F\u0430\u0440\u044B \u0434\u043E\u0441\u0442\u0443\u043F\u043D\u044B \u043F\u0440\u0438 \u0447\u0435\u0442\u044B\u0440\u0451\u0445 \u0438\u043B\u0438 \u0448\u0435\u0441\u0442\u0438 \u0438\u0433\u0440\u043E\u043A\u0430\u0445, \u0442\u0440\u043E\u0439\u043A\u0438 \u043F\u0440\u0438 \u0448\u0435\u0441\u0442\u0438. \u0423 \u043A\u043E\u043C\u0430\u043D\u0434\u044B \u043E\u0431\u0449\u0438\u0435 \u043E\u0447\u043A\u0438, \u043C\u0435\u0441\u0442\u0430 \u0447\u0435\u0440\u0435\u0434\u0443\u044E\u0442\u0441\u044F \u043C\u0435\u0436\u0434\u0443 \u043A\u043E\u043C\u0430\u043D\u0434\u0430\u043C\u0438. \u041D\u0435 \u0440\u0430\u0441\u043A\u0440\u044B\u0432\u0430\u0439\u0442\u0435 \u043A\u0430\u0440\u0442\u044B \u0434\u0430\u0436\u0435 \u043F\u0430\u0440\u0442\u043D\u0451\u0440\u0430\u043C."),
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
