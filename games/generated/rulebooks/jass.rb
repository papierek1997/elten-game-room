# Generated from tools/data/rulebooks/jass.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class JassTable
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:play, GameRoomRules.translate("Playing Jass"),
            GameRoomRules.translate("Four players form two partnerships, with partners sitting across the table. Each receives nine cards from a 36-card deck, six through ace in each suit. The player after the dealer chooses trumps or lets their partner choose. That partner must decide. The opening lead stays with the player after the dealer. After each deal, the next player deals."),
            GameRoomRules.translate("The first card sets the suit led. On a trump lead, follow with a trump if possible. On another suit, follow suit or play a trump; without that suit you may discard. You may play a lower trump than one already down only if no other legal card remains. The highest trump wins, or the highest card of the suit led if there are no trumps. The trick winner leads next.")),
          rule_section(:scoring, GameRoomRules.translate("Card order and points"),
            GameRoomRules.translate("Trumps rank jack, nine, ace, king, queen, ten, eight, seven, six. The jack is worth twenty and the nine fourteen. In other suits the order is ace, king, queen, jack, ten, nine, eight, seven, six. Aces score 11, tens 10, kings 4, queens 3 and non-trump jacks 2; other cards score zero. The last trick adds five. There are 157 points per deal.")),
          rule_section(:settings, GameRoomRules.translate("Variants and the score target"),
            GameRoomRules.translate("The Trumps variant offers four trump suits. Schieber also offers Obenabe and Undenufe, both without trumps. In Obenabe the highest card of the suit led wins and eights score eight. In Undenufe the lowest card wins; sixes score eleven, aces zero and eights eight. In either mode you must follow suit if possible."),
            GameRoomRules.translate("Each trick\u2019s points go to its winner\u2019s partnership. Choose a match target of 1000, 1500, 2000 or 2500 when creating the table. The match ends at the end of the deal in which a partnership reaches the target.")),
          rule_section(:controls, GameRoomRules.translate("Controls"),
            GameRoomRules.translate("Arrows: browse cards or menu choices."),
            GameRoomRules.translate("Enter: choose the deal rules before play, or play a card during tricks."),
            GameRoomRules.translate("B: open the available trump and no-trump choices."),
            GameRoomRules.translate("F: read the deal rules and suit led."),
            GameRoomRules.translate("R: read who chooses trumps or which mode was chosen."),
            GameRoomRules.translate("V: repeat the deal rules."),
            GameRoomRules.translate("Shift+S: read this deal\u2019s points."),
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
            rule_section(:play, "Jak hr\u00E1t Jass",
              "\u010Cty\u0159i hr\u00E1\u010Di tvo\u0159\u00ED dv\u011B dvojice, spoluhr\u00E1\u010Di sed\u00ED naproti sob\u011B. Ka\u017Ed\u00FD dostane dev\u011Bt karet z bal\u00ED\u010Dku 36, od \u0161estky po eso. Hr\u00E1\u010D po rozd\u00E1vaj\u00EDc\u00EDm zvol\u00ED trumfy nebo p\u0159enech\u00E1 volbu spoluhr\u00E1\u010Di, kter\u00FD u\u017E mus\u00ED rozhodnout. Prvn\u00ED zdvih v\u017Edy za\u010D\u00EDn\u00E1 hr\u00E1\u010D po rozd\u00E1vaj\u00EDc\u00EDm. V dal\u0161\u00EDm rozd\u00E1n\u00ED rozd\u00E1v\u00E1 dal\u0161\u00ED hr\u00E1\u010D.",
              "Prvn\u00ED karta ur\u010Duje barvu. Na trumfov\u00FD v\u00FDnos mus\u00ED\u0161 p\u0159iznat trumf, m\u00E1\u0161-li ho. Na jinou barvu m\u016F\u017Ee\u0161 p\u0159iznat nebo trumfovat; bez n\u00ED sm\u00ED\u0161 odhodit. Ni\u017E\u0161\u00ED trumf ne\u017E u\u017E zahran\u00FD sm\u00ED\u0161 d\u00E1t jen tehdy, nem\u00E1\u0161-li jinou dovolenou kartu. Bere nejvy\u0161\u0161\u00ED trumf, jinak nejvy\u0161\u0161\u00ED karta vynesen\u00E9 barvy. V\u00EDt\u011Bz za\u010D\u00EDn\u00E1 dal\u0161\u00ED zdvih."),
            rule_section(:scoring, "Po\u0159ad\u00ED karet a body",
              "Trumfy maj\u00ED po\u0159ad\u00ED kluk, dev\u00EDtka, eso, kr\u00E1l, d\u00E1ma, des\u00EDtka, osmi\u010Dka, sedmi\u010Dka, \u0161estka. Kluk d\u00E1v\u00E1 dvacet bod\u016F a dev\u00EDtka \u010Dtrn\u00E1ct. V ostatn\u00EDch barv\u00E1ch je po\u0159ad\u00ED eso, kr\u00E1l, d\u00E1ma, kluk, des\u00EDtka, dev\u00EDtka, osmi\u010Dka, sedmi\u010Dka, \u0161estka. Eso d\u00E1v\u00E1 11, des\u00EDtka 10, kr\u00E1l 4, d\u00E1ma 3 a netrumfov\u00FD kluk 2 body, ostatn\u00ED nulu. Posledn\u00ED zdvih p\u0159id\u00E1v\u00E1 p\u011Bt, celkem je 157 bod\u016F."),
            rule_section(:settings, "Varianty a bodov\u00FD c\u00EDl",
              "Varianta s trumfy nab\u00EDz\u00ED \u010Dty\u0159i barvy. Schieber p\u0159id\u00E1v\u00E1 Obenabe a Undenufe bez trumf\u016F. V Obenabe vyhr\u00E1v\u00E1 nejvy\u0161\u0161\u00ED karta vynesen\u00E9 barvy a osmi\u010Dky d\u00E1vaj\u00ED osm bod\u016F. V Undenufe bere nejni\u017E\u0161\u00ED karta; \u0161estky d\u00E1vaj\u00ED jeden\u00E1ct, esa nulu a osmi\u010Dky osm. V obou re\u017Eimech mus\u00ED\u0161 p\u0159iznat barvu, pokud ji m\u00E1\u0161.",
              "Body za zdvih z\u00EDsk\u00E1 dvojice jeho v\u00EDt\u011Bze. P\u0159i tvorb\u011B stolu zvol c\u00EDl 1000, 1500, 2000 nebo 2500 bod\u016F. Hra kon\u010D\u00ED na konci rozd\u00E1n\u00ED, v n\u011Bm\u017E dvojice c\u00EDle dos\u00E1hne."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "\u0160ipky: proch\u00E1zej karty nebo nab\u00EDdku.",
              "Enter: zvol pravidla rozd\u00E1n\u00ED nebo zahraj kartu do zdvihu.",
              "B: otev\u0159i dostupn\u00E9 trumfy a re\u017Eimy bez trumf\u016F.",
              "F: p\u0159e\u010Dti pravidla rozd\u00E1n\u00ED a vynesenou barvu.",
              "R: zjisti, kdo vol\u00ED trumfy nebo jak\u00FD re\u017Eim byl zvolen.",
              "V: zopakuj pravidla rozd\u00E1n\u00ED.",
              "Shift+S: p\u0159e\u010Dti body za rozd\u00E1n\u00ED.",
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
            rule_section(:play, "Playing Jass",
              "Four players form two partnerships, with partners sitting across the table. Each receives nine cards from a 36-card deck, six through ace in each suit. The player after the dealer chooses trumps or lets their partner choose. That partner must decide. The opening lead stays with the player after the dealer. After each deal, the next player deals.",
              "The first card sets the suit led. On a trump lead, follow with a trump if possible. On another suit, follow suit or play a trump; without that suit you may discard. You may play a lower trump than one already down only if no other legal card remains. The highest trump wins, or the highest card of the suit led if there are no trumps. The trick winner leads next."),
            rule_section(:scoring, "Card order and points",
              "Trumps rank jack, nine, ace, king, queen, ten, eight, seven, six. The jack is worth twenty and the nine fourteen. In other suits the order is ace, king, queen, jack, ten, nine, eight, seven, six. Aces score 11, tens 10, kings 4, queens 3 and non-trump jacks 2; other cards score zero. The last trick adds five. There are 157 points per deal."),
            rule_section(:settings, "Variants and the score target",
              "The Trumps variant offers four trump suits. Schieber also offers Obenabe and Undenufe, both without trumps. In Obenabe the highest card of the suit led wins and eights score eight. In Undenufe the lowest card wins; sixes score eleven, aces zero and eights eight. In either mode you must follow suit if possible.",
              "Each trick\u2019s points go to its winner\u2019s partnership. Choose a match target of 1000, 1500, 2000 or 2500 when creating the table. The match ends at the end of the deal in which a partnership reaches the target."),
            rule_section(:controls, "Controls",
              "Arrows: browse cards or menu choices.",
              "Enter: choose the deal rules before play, or play a card during tricks.",
              "B: open the available trump and no-trump choices.",
              "F: read the deal rules and suit led.",
              "R: read who chooses trumps or which mode was chosen.",
              "V: repeat the deal rules.",
              "Shift+S: read this deal\u2019s points.",
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
            rule_section(:play, "C\u00F3mo jugar al Jass",
              "Cuatro jugadores forman dos parejas sentadas frente a frente. Cada uno recibe nueve cartas de una baraja de 36, del seis al as. Quien sigue al repartidor elige triunfo o cede la elecci\u00F3n a su compa\u00F1ero, que debe decidir. La primera salida sigue correspondiendo a quien va despu\u00E9s del repartidor. El reparto rota en cada mano.",
              "La primera carta fija el palo. Si se sale de triunfo, debes asistir con triunfo si puedes. En otro palo, puedes asistir o jugar triunfo; sin ese palo puedes descartar. Solo puedes jugar un triunfo inferior al ya jugado si no queda otra jugada legal. Gana el triunfo m\u00E1s alto o, si no hay, la carta m\u00E1s alta del palo de salida. Quien gana sale a la siguiente."),
            rule_section(:scoring, "Orden de las cartas y puntos",
              "Los triunfos se ordenan jota, nueve, as, rey, dama, diez, ocho, siete y seis. La jota vale veinte y el nueve catorce. En los dem\u00E1s palos: as, rey, dama, jota, diez, nueve, ocho, siete y seis. El as da 11, el diez 10, el rey 4, la dama 3 y la jota no triunfal 2; las dem\u00E1s cartas cero. La \u00FAltima baza a\u00F1ade cinco, para un total de 157 por mano."),
            rule_section(:settings, "Variantes y objetivo de puntos",
              "La variante con triunfo ofrece los cuatro palos. Schieber a\u00F1ade Obenabe y Undenufe, ambos sin triunfo. En Obenabe gana la carta m\u00E1s alta del palo de salida y los ochos valen ocho. En Undenufe gana la m\u00E1s baja; los seises valen once, los ases cero y los ochos ocho. En ambos modos debes asistir al palo si puedes.",
              "Los puntos de cada baza van a la pareja de quien la gane. Al crear la mesa elige un objetivo de 1000, 1500, 2000 o 2500. La partida termina al acabar la mano en la que una pareja alcance el objetivo."),
            rule_section(:controls, "Controles",
              "Flechas: recorrer cartas u opciones.",
              "Intro: elegir las reglas antes de jugar o jugar una carta en una baza.",
              "B: abrir las opciones de triunfo y sin triunfo.",
              "F: leer las reglas de la mano y el palo de salida.",
              "R: leer qui\u00E9n elige triunfo o qu\u00E9 modo se ha elegido.",
              "V: repetir las reglas de la mano.",
              "May\u00FAs+S: leer los puntos de esta mano.",
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
            rule_section(:play, "Jak gra\u0107 w Jassa",
              "Cztery osoby graj\u0105 w dw\u00F3ch parach, z partnerami naprzeciw siebie. Ka\u017Cdy dostaje dziewi\u0119\u0107 kart z talii 36 kart, od sz\u00F3stki do asa. Osoba po rozdaj\u0105cym wybiera atut albo przekazuje wyb\u00F3r partnerowi, kt\u00F3ry musi zdecydowa\u0107. Do pierwszej lewy zawsze wychodzi osoba po rozdaj\u0105cym. Po ka\u017Cdym rozdaniu rozdaje nast\u0119pny gracz.",
              "Pierwsza karta ustala kolor lewy. Do wyj\u015Bcia w atucie trzeba do\u0142o\u017Cy\u0107 atut, je\u015Bli go masz. Do innego koloru mo\u017Cesz do\u0142o\u017Cy\u0107 albo zagra\u0107 atut. Gdy nie masz koloru wyj\u015Bcia, mo\u017Cesz te\u017C zrzuci\u0107 inn\u0105 kart\u0119. Ni\u017Cszy atut od ju\u017C po\u0142o\u017Conego wolno zagra\u0107 tylko przy braku innego legalnego ruchu. Wygrywa najwy\u017Cszy atut, a bez atutu najwy\u017Csza karta koloru wyj\u015Bcia. Zwyci\u0119zca wychodzi do nast\u0119pnej lewy."),
            rule_section(:scoring, "Si\u0142a kart i punkty",
              "Atuty od najsilniejszego to walet, dziewi\u0105tka, as, kr\u00F3l, dama, dziesi\u0105tka, \u00F3semka, si\u00F3demka i sz\u00F3stka. Walet daje dwadzie\u015Bcia punkt\u00F3w, a dziewi\u0105tka czterna\u015Bcie. Poza atutem kolejno\u015B\u0107 to as, kr\u00F3l, dama, walet, dziesi\u0105tka, dziewi\u0105tka, \u00F3semka, si\u00F3demka i sz\u00F3stka. As daje 11, dziesi\u0105tka 10, kr\u00F3l 4, dama 3, a walet poza atutem 2 punkty. Pozosta\u0142e karty daj\u0105 zero. Ostatnia lewa dodaje pi\u0119\u0107, wi\u0119c w rozdaniu jest razem 157 punkt\u00F3w."),
            rule_section(:settings, "Odmiany i cel punktowy",
              "Wariant z atutem pozwala wybra\u0107 jeden z czterech kolor\u00F3w. Schieber dodaje Obenabe i Undenufe, oba bez atutu. W Obenabe wygrywa najwy\u017Csza karta koloru wyj\u015Bcia, a \u00F3semki daj\u0105 osiem punkt\u00F3w. W Undenufe wygrywa najni\u017Csza karta: sz\u00F3stki daj\u0105 jedena\u015Bcie, asy zero, a \u00F3semki osiem punkt\u00F3w. W obu trybach trzeba dok\u0142ada\u0107 do koloru, je\u015Bli go masz.",
              "Punkty za lew\u0119 trafiaj\u0105 do pary, kt\u00F3ra j\u0105 wygra\u0142a. Przy tworzeniu sto\u0142u wybierz cel meczu: 1000, 1500, 2000 albo 2500 punkt\u00F3w. Mecz ko\u0144czy si\u0119 na ko\u0144cu rozdania, w kt\u00F3rym para osi\u0105gnie ten cel."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "Strza\u0142ki: przegl\u0105daj karty lub pozycje menu.",
              "Enter: wybierz zasady rozdania przed rozgrywk\u0105 albo zagraj kart\u0119 podczas lewy.",
              "B: otw\u00F3rz dost\u0119pne kolory atutowe i tryby bez atutu.",
              "F: odczytaj zasady rozdania i kolor wyj\u015Bcia.",
              "R: sprawd\u017A, kto wybiera atut albo jaki tryb wybrano.",
              "V: przypomnij zasady rozdania.",
              "Shift+S: odczytaj punkty rozdania.",
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
            rule_section(:play, "\u041A\u0430\u043A \u0438\u0433\u0440\u0430\u0442\u044C \u0432 \u044F\u0441\u0441",
              "\u0427\u0435\u0442\u0432\u0435\u0440\u043E \u0438\u0433\u0440\u0430\u044E\u0442 \u0434\u0432\u0443\u043C\u044F \u043F\u0430\u0440\u0430\u043C\u0438, \u043F\u0430\u0440\u0442\u043D\u0451\u0440\u044B \u0441\u0438\u0434\u044F\u0442 \u043D\u0430\u043F\u0440\u043E\u0442\u0438\u0432. \u041A\u0430\u0436\u0434\u044B\u0439 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u0434\u0435\u0432\u044F\u0442\u044C \u043A\u0430\u0440\u0442 \u0438\u0437 \u043A\u043E\u043B\u043E\u0434\u044B \u0432 36 \u043A\u0430\u0440\u0442, \u043E\u0442 \u0448\u0435\u0441\u0442\u0451\u0440\u043A\u0438 \u0434\u043E \u0442\u0443\u0437\u0430. \u0418\u0433\u0440\u043E\u043A \u043F\u043E\u0441\u043B\u0435 \u0441\u0434\u0430\u044E\u0449\u0435\u0433\u043E \u0432\u044B\u0431\u0438\u0440\u0430\u0435\u0442 \u043A\u043E\u0437\u044B\u0440\u044C \u0438\u043B\u0438 \u043F\u0435\u0440\u0435\u0434\u0430\u0451\u0442 \u0432\u044B\u0431\u043E\u0440 \u043F\u0430\u0440\u0442\u043D\u0451\u0440\u0443, \u043A\u043E\u0442\u043E\u0440\u044B\u0439 \u043E\u0431\u044F\u0437\u0430\u043D \u0440\u0435\u0448\u0438\u0442\u044C. \u041F\u0435\u0440\u0432\u044B\u043C \u0432\u043E \u0432\u0437\u044F\u0442\u043A\u0443 \u0432\u0441\u0435\u0433\u0434\u0430 \u0445\u043E\u0434\u0438\u0442 \u0438\u0433\u0440\u043E\u043A \u043F\u043E\u0441\u043B\u0435 \u0441\u0434\u0430\u044E\u0449\u0435\u0433\u043E. \u041F\u043E\u0441\u043B\u0435 \u043A\u0430\u0436\u0434\u043E\u0439 \u0441\u0434\u0430\u0447\u0438 \u0441\u0434\u0430\u044E\u0449\u0438\u0439 \u043C\u0435\u043D\u044F\u0435\u0442\u0441\u044F.",
              "\u041F\u0435\u0440\u0432\u0430\u044F \u043A\u0430\u0440\u0442\u0430 \u0437\u0430\u0434\u0430\u0451\u0442 \u043C\u0430\u0441\u0442\u044C \u0445\u043E\u0434\u0430. \u041D\u0430 \u0445\u043E\u0434 \u043A\u043E\u0437\u044B\u0440\u0435\u043C \u043D\u0443\u0436\u043D\u043E \u043E\u0442\u0432\u0435\u0442\u0438\u0442\u044C \u043A\u043E\u0437\u044B\u0440\u0435\u043C, \u0435\u0441\u043B\u0438 \u043E\u043D \u0435\u0441\u0442\u044C. \u041D\u0430 \u0434\u0440\u0443\u0433\u0443\u044E \u043C\u0430\u0441\u0442\u044C \u043C\u043E\u0436\u043D\u043E \u043E\u0442\u0432\u0435\u0442\u0438\u0442\u044C \u0432 \u043C\u0430\u0441\u0442\u044C \u0438\u043B\u0438 \u043A\u043E\u0437\u044B\u0440\u0435\u043C; \u0431\u0435\u0437 \u044D\u0442\u043E\u0439 \u043C\u0430\u0441\u0442\u0438 \u0440\u0430\u0437\u0440\u0435\u0448\u0451\u043D \u0441\u0431\u0440\u043E\u0441. \u041A\u043E\u0437\u044B\u0440\u044C \u043D\u0438\u0436\u0435 \u0443\u0436\u0435 \u0441\u044B\u0433\u0440\u0430\u043D\u043D\u043E\u0433\u043E \u0440\u0430\u0437\u0440\u0435\u0448\u0451\u043D, \u0442\u043E\u043B\u044C\u043A\u043E \u0435\u0441\u043B\u0438 \u043D\u0435\u0442 \u0434\u0440\u0443\u0433\u043E\u0433\u043E \u0434\u043E\u043F\u0443\u0441\u0442\u0438\u043C\u043E\u0433\u043E \u0445\u043E\u0434\u0430. \u0411\u0435\u0440\u0451\u0442 \u0441\u0442\u0430\u0440\u0448\u0438\u0439 \u043A\u043E\u0437\u044B\u0440\u044C, \u0430 \u0431\u0435\u0437 \u043A\u043E\u0437\u044B\u0440\u0435\u0439 \u2014 \u0441\u0442\u0430\u0440\u0448\u0430\u044F \u043A\u0430\u0440\u0442\u0430 \u043C\u0430\u0441\u0442\u0438 \u0445\u043E\u0434\u0430. \u041F\u043E\u0431\u0435\u0434\u0438\u0442\u0435\u043B\u044C \u0445\u043E\u0434\u0438\u0442 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0438\u043C."),
            rule_section(:scoring, "\u0421\u0442\u0430\u0440\u0448\u0438\u043D\u0441\u0442\u0432\u043E \u043A\u0430\u0440\u0442 \u0438 \u043E\u0447\u043A\u0438",
              "\u041A\u043E\u0437\u044B\u0440\u0438 \u043F\u043E \u0443\u0431\u044B\u0432\u0430\u043D\u0438\u044E: \u0432\u0430\u043B\u0435\u0442, \u0434\u0435\u0432\u044F\u0442\u043A\u0430, \u0442\u0443\u0437, \u043A\u043E\u0440\u043E\u043B\u044C, \u0434\u0430\u043C\u0430, \u0434\u0435\u0441\u044F\u0442\u043A\u0430, \u0432\u043E\u0441\u044C\u043C\u0451\u0440\u043A\u0430, \u0441\u0435\u043C\u0451\u0440\u043A\u0430, \u0448\u0435\u0441\u0442\u0451\u0440\u043A\u0430. \u0412\u0430\u043B\u0435\u0442 \u0434\u0430\u0451\u0442 \u0434\u0432\u0430\u0434\u0446\u0430\u0442\u044C \u043E\u0447\u043A\u043E\u0432, \u0434\u0435\u0432\u044F\u0442\u043A\u0430 \u2014 \u0447\u0435\u0442\u044B\u0440\u043D\u0430\u0434\u0446\u0430\u0442\u044C. \u0412 \u0434\u0440\u0443\u0433\u0438\u0445 \u043C\u0430\u0441\u0442\u044F\u0445: \u0442\u0443\u0437, \u043A\u043E\u0440\u043E\u043B\u044C, \u0434\u0430\u043C\u0430, \u0432\u0430\u043B\u0435\u0442, \u0434\u0435\u0441\u044F\u0442\u043A\u0430, \u0434\u0435\u0432\u044F\u0442\u043A\u0430, \u0432\u043E\u0441\u044C\u043C\u0451\u0440\u043A\u0430, \u0441\u0435\u043C\u0451\u0440\u043A\u0430, \u0448\u0435\u0441\u0442\u0451\u0440\u043A\u0430. \u0422\u0443\u0437 \u0434\u0430\u0451\u0442 11, \u0434\u0435\u0441\u044F\u0442\u043A\u0430 10, \u043A\u043E\u0440\u043E\u043B\u044C 4, \u0434\u0430\u043C\u0430 3, \u043D\u0435\u043A\u043E\u0437\u044B\u0440\u043D\u044B\u0439 \u0432\u0430\u043B\u0435\u0442 2; \u043E\u0441\u0442\u0430\u043B\u044C\u043D\u044B\u0435 \u043D\u043E\u043B\u044C. \u041F\u043E\u0441\u043B\u0435\u0434\u043D\u044F\u044F \u0432\u0437\u044F\u0442\u043A\u0430 \u0434\u043E\u0431\u0430\u0432\u043B\u044F\u0435\u0442 \u043F\u044F\u0442\u044C, \u0432\u0441\u0435\u0433\u043E \u0437\u0430 \u0441\u0434\u0430\u0447\u0443 \u2014 157 \u043E\u0447\u043A\u043E\u0432."),
            rule_section(:settings, "\u0412\u0430\u0440\u0438\u0430\u043D\u0442\u044B \u0438 \u0446\u0435\u043B\u044C \u043F\u043E \u043E\u0447\u043A\u0430\u043C",
              "\u0412\u0430\u0440\u0438\u0430\u043D\u0442 \u0441 \u043A\u043E\u0437\u044B\u0440\u044F\u043C\u0438 \u043F\u0440\u0435\u0434\u043B\u0430\u0433\u0430\u0435\u0442 \u0447\u0435\u0442\u044B\u0440\u0435 \u043C\u0430\u0441\u0442\u0438. \u0428\u0438\u0431\u0435\u0440 \u0434\u043E\u0431\u0430\u0432\u043B\u044F\u0435\u0442 \u0431\u0435\u0441\u043A\u043E\u0437\u044B\u0440\u043D\u044B\u0435 \u0440\u0435\u0436\u0438\u043C\u044B \u041E\u0431\u0435\u043D\u0430\u0431\u0435 \u0438 \u0423\u043D\u0434\u0435\u043D\u0443\u0444\u0435. \u0412 \u041E\u0431\u0435\u043D\u0430\u0431\u0435 \u0431\u0435\u0440\u0451\u0442 \u0441\u0442\u0430\u0440\u0448\u0430\u044F \u043A\u0430\u0440\u0442\u0430 \u043C\u0430\u0441\u0442\u0438 \u0445\u043E\u0434\u0430, \u0432\u043E\u0441\u044C\u043C\u0451\u0440\u043A\u0438 \u0434\u0430\u044E\u0442 \u0432\u043E\u0441\u0435\u043C\u044C \u043E\u0447\u043A\u043E\u0432. \u0412 \u0423\u043D\u0434\u0435\u043D\u0443\u0444\u0435 \u0431\u0435\u0440\u0451\u0442 \u043C\u043B\u0430\u0434\u0448\u0430\u044F \u043A\u0430\u0440\u0442\u0430; \u0448\u0435\u0441\u0442\u0451\u0440\u043A\u0438 \u0434\u0430\u044E\u0442 \u043E\u0434\u0438\u043D\u043D\u0430\u0434\u0446\u0430\u0442\u044C, \u0442\u0443\u0437\u044B \u043D\u043E\u043B\u044C, \u0432\u043E\u0441\u044C\u043C\u0451\u0440\u043A\u0438 \u0432\u043E\u0441\u0435\u043C\u044C. \u0412 \u043E\u0431\u043E\u0438\u0445 \u0440\u0435\u0436\u0438\u043C\u0430\u0445 \u043D\u0443\u0436\u043D\u043E \u0445\u043E\u0434\u0438\u0442\u044C \u0432 \u043C\u0430\u0441\u0442\u044C, \u0435\u0441\u043B\u0438 \u043C\u043E\u0436\u0435\u0442\u0435.",
              "\u041E\u0447\u043A\u0438 \u0432\u0437\u044F\u0442\u043A\u0438 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u043F\u0430\u0440\u0430 \u0435\u0451 \u043F\u043E\u0431\u0435\u0434\u0438\u0442\u0435\u043B\u044F. \u041F\u0440\u0438 \u0441\u043E\u0437\u0434\u0430\u043D\u0438\u0438 \u0441\u0442\u043E\u043B\u0430 \u0432\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0446\u0435\u043B\u044C: 1000, 1500, 2000 \u0438\u043B\u0438 2500 \u043E\u0447\u043A\u043E\u0432. \u041C\u0430\u0442\u0447 \u0437\u0430\u043A\u0430\u043D\u0447\u0438\u0432\u0430\u0435\u0442\u0441\u044F \u0432 \u043A\u043E\u043D\u0446\u0435 \u0441\u0434\u0430\u0447\u0438, \u0432 \u043A\u043E\u0442\u043E\u0440\u043E\u0439 \u043F\u0430\u0440\u0430 \u0434\u043E\u0441\u0442\u0438\u0433\u043D\u0435\u0442 \u0446\u0435\u043B\u0438."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0448\u0438 \u0443\u043F\u0440\u0430\u0432\u043B\u0435\u043D\u0438\u044F",
              "\u0421\u0442\u0440\u0435\u043B\u043A\u0438: \u043F\u0440\u043E\u0441\u043C\u0430\u0442\u0440\u0438\u0432\u0430\u0442\u044C \u043A\u0430\u0440\u0442\u044B \u0438\u043B\u0438 \u043F\u0443\u043D\u043A\u0442\u044B \u043C\u0435\u043D\u044E.",
              "Enter: \u0432\u044B\u0431\u0440\u0430\u0442\u044C \u043F\u0440\u0430\u0432\u0438\u043B\u0430 \u0441\u0434\u0430\u0447\u0438 \u0438\u043B\u0438 \u0441\u044B\u0433\u0440\u0430\u0442\u044C \u043A\u0430\u0440\u0442\u0443 \u0432\u043E \u0432\u0437\u044F\u0442\u043A\u0443.",
              "B: \u043E\u0442\u043A\u0440\u044B\u0442\u044C \u0434\u043E\u0441\u0442\u0443\u043F\u043D\u044B\u0435 \u043A\u043E\u0437\u044B\u0440\u0438 \u0438 \u0431\u0435\u0441\u043A\u043E\u0437\u044B\u0440\u043D\u044B\u0435 \u0440\u0435\u0436\u0438\u043C\u044B.",
              "F: \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u043F\u0440\u0430\u0432\u0438\u043B\u0430 \u0441\u0434\u0430\u0447\u0438 \u0438 \u043C\u0430\u0441\u0442\u044C \u0445\u043E\u0434\u0430.",
              "R: \u0443\u0437\u043D\u0430\u0442\u044C, \u043A\u0442\u043E \u0432\u044B\u0431\u0438\u0440\u0430\u0435\u0442 \u043A\u043E\u0437\u044B\u0440\u044C \u0438\u043B\u0438 \u043A\u0430\u043A\u043E\u0439 \u0440\u0435\u0436\u0438\u043C \u0432\u044B\u0431\u0440\u0430\u043D.",
              "V: \u043F\u043E\u0432\u0442\u043E\u0440\u0438\u0442\u044C \u043F\u0440\u0430\u0432\u0438\u043B\u0430 \u0441\u0434\u0430\u0447\u0438.",
              "Shift+S: \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u043E\u0447\u043A\u0438 \u0437\u0430 \u0441\u0434\u0430\u0447\u0443.",
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
