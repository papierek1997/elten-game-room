# Generated from tools/data/rulebooks/balut.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Balut
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:play, GameRoomRules.translate("Your turn"),
            GameRoomRules.translate("Two to eight players take turns filling their own score sheets. Each sheet has seven rows of four spaces, so you have 28 turns. The aim is to earn the most game points from combinations and completed rows. Press Enter to roll five dice. You may record the result or reroll selected dice up to twice. A result that does not qualify for the chosen row fills its next space with zero.")),
          rule_section(:points, GameRoomRules.translate("The seven rows"),
            GameRoomRules.translate("In Fours, Fives and Sixes, sum only the dice showing the named value. Chance takes the sum of all five dice. A straight is five consecutive values, and a full house is three of one value and two of another. Both score the sum of all five dice. Five equal dice score 50 in Balut regardless of their value. If Balut is full, five sixes can still score 30 in Sixes or Chance.")),
          rule_section(:total, GameRoomRules.translate("Final score"),
            GameRoomRules.translate("You earn two points for each of these row totals you reach: 52 in Fours, 65 in Fives, 78 in Sixes and 100 in Chance. Four straights earn four points, four full houses earn three and each Balut earns two. Add up all entries. Below 300, subtract two points. At 300\u2013349, subtract one. At 350\u2013399, make no adjustment. Starting at 400, add one point for each 50 above 350, up to six at 650. The highest final score wins. The maximum is 29 points.")),
          rule_section(:controls, GameRoomRules.translate("Keyboard"),
            GameRoomRules.translate("Enter: roll all five dice to begin your turn. Later, reroll the selected dice or open scoring if none are selected. In the score sheet, record the selected row. After the third roll, the sheet appears automatically."),
            GameRoomRules.translate("1\u20136: select one die showing that value for a reroll."),
            GameRoomRules.translate("Shift+1\u20136: keep one selected die showing that value."),
            GameRoomRules.translate("Arrows: choose a row with Up and Down; inspect its entries and totals with Left and Right. Full rows are omitted from the scoring view."),
            GameRoomRules.translate("B: open the score sheet in a separate window."),
            GameRoomRules.translate("Escape: close the separate score-sheet window without recording a result."),
            GameRoomRules.translate("Space: read the dice and, in the rolling field, their selection state."),
            GameRoomRules.translate("D: read the last roll."),
            GameRoomRules.translate("V: browse your score sheet."),
            GameRoomRules.translate("Shift+V: browse another player's score sheet."),
            GameRoomRules.translate("F: browse your unfilled rows."),
            GameRoomRules.translate("S: read game points."),
            GameRoomRules.translate("Shift+S: read the sum of recorded scores."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:play, "Tah",
              "Dva a\u017E osm hr\u00E1\u010D\u016F se st\u0159\u00EDd\u00E1 ve vypl\u0148ov\u00E1n\u00ED vlastn\u00EDch tabulek. Ka\u017Ed\u00E1 m\u00E1 sedm \u0159\u00E1dk\u016F po \u010Dty\u0159ech pol\u00ED\u010Dk\u00E1ch, tak\u017Ee odehrajete 28 tah\u016F. Vyhr\u00E1v\u00E1 nejvy\u0161\u0161\u00ED po\u010Det hern\u00EDch bod\u016F za kombinace a dokon\u010Den\u00E9 \u0159\u00E1dky. Kl\u00E1vesou Enter ho\u010Fte p\u011Bti kostkami. V\u00FDsledek m\u016F\u017Eete zapsat nebo vybran\u00E9 kostky je\u0161t\u011B dvakr\u00E1t p\u0159ehodit. Pokud hod nespl\u0148uje podm\u00EDnku \u0159\u00E1dku, jeho dal\u0161\u00ED pol\u00ED\u010Dko obsad\u00EDte nulou."),
            rule_section(:points, "\u0158\u00E1dky tabulky",
              "Ve \u010Dty\u0159k\u00E1ch, p\u011Btk\u00E1ch a \u0161estk\u00E1ch se\u010Dt\u011Bte jen kostky s p\u0159\u00EDslu\u0161nou hodnotou. V \u0161anci se po\u010D\u00EDt\u00E1 v\u0161ech p\u011Bt kostek. Postupku tvo\u0159\u00ED p\u011Bt po sob\u011B jdouc\u00EDch hodnot, full house trojice a dvojice. U obou zapi\u0161te sou\u010Det v\u0161ech kostek. P\u011Bt stejn\u00FDch kostek d\u00E1v\u00E1 v \u0159\u00E1dku Balut 50 bez ohledu na hodnotu. Je-li \u0159\u00E1dek pln\u00FD, p\u011Bt \u0161estek m\u016F\u017Eete zapsat za 30 do \u0161estek nebo \u0161ance."),
            rule_section(:total, "Kone\u010Dn\u00FD v\u00FDsledek",
              "Dva body z\u00EDsk\u00E1te za ka\u017Ed\u00FD dosa\u017Een\u00FD limit: 52 ve \u010Dty\u0159k\u00E1ch, 65 v p\u011Btk\u00E1ch, 78 v \u0161estk\u00E1ch a 100 v \u0161anci. \u010Cty\u0159i postupky d\u00E1vaj\u00ED \u010Dty\u0159i body, \u010Dty\u0159i full house t\u0159i body a ka\u017Ed\u00FD Balut dva body. Se\u010Dt\u011Bte tak\u00E9 v\u0161echny z\u00E1pisy. Pod 300 ode\u010Dt\u011Bte dva body, p\u0159i 300 a\u017E 349 jeden. P\u0159i 350 a\u017E 399 se v\u00FDsledek nem\u011Bn\u00ED. Od 400 z\u00EDsk\u00E1te bod a za ka\u017Ed\u00FDch dal\u0161\u00EDch 50 dal\u0161\u00ED bod, nejv\u00FD\u0161e \u0161est od 650. Vyhr\u00E1v\u00E1 nejvy\u0161\u0161\u00ED v\u00FDsledek, maximum je 29 bod\u016F."),
            rule_section(:controls, "Ovl\u00E1d\u00E1n\u00ED",
              "Enter: za\u010Dn\u011Bte tah hodem p\u011Bti kostkami. Pot\u00E9 p\u0159eho\u010Fte vybran\u00E9 kostky, nebo otev\u0159ete z\u00E1pis, pokud nejsou \u017E\u00E1dn\u00E9 vybr\u00E1ny. V tabulce zapi\u0161te v\u00FDsledek do zvolen\u00E9ho \u0159\u00E1dku. Po t\u0159et\u00EDm hodu se tabulka zobraz\u00ED automaticky.",
              "1\u20136: vybrat jednu kostku s touto hodnotou k p\u0159ehozen\u00ED.",
              "Shift+1\u20136: zru\u0161it v\u00FDb\u011Br jedn\u00E9 kostky s touto hodnotou.",
              "\u0160ipky: nahoru a dol\u016F vol\u00ED \u0159\u00E1dek, vlevo a vpravo proch\u00E1zej\u00ED z\u00E1pisy a sou\u010Dty. Pln\u00E9 \u0159\u00E1dky se v nab\u00EDdce z\u00E1pisu vynech\u00E1vaj\u00ED.",
              "B: otev\u0159\u00EDt tabulku v samostatn\u00E9m okn\u011B.",
              "Escape: zav\u0159\u00EDt samostatn\u00E9 okno tabulky bez z\u00E1pisu v\u00FDsledku.",
              "Mezern\u00EDk: p\u0159e\u010D\u00EDst kostky a v poli hodu tak\u00E9 jejich v\u00FDb\u011Br.",
              "D: p\u0159e\u010D\u00EDst posledn\u00ED hod.",
              "V: prohl\u00E9dnout vlastn\u00ED tabulku.",
              "Shift+V: prohl\u00E9dnout tabulku jin\u00E9ho hr\u00E1\u010De.",
              "F: prohl\u00E9dnout vlastn\u00ED nevypln\u011Bn\u00E9 \u0159\u00E1dky.",
              "S: p\u0159e\u010D\u00EDst hern\u00ED body.",
              "Shift+S: p\u0159e\u010D\u00EDst sou\u010Det zapsan\u00FDch bod\u016F.")
          ]
        when "en"
          [
            rule_section(:play, "Your turn",
              "Two to eight players take turns filling their own score sheets. Each sheet has seven rows of four spaces, so you have 28 turns. The aim is to earn the most game points from combinations and completed rows. Press Enter to roll five dice. You may record the result or reroll selected dice up to twice. A result that does not qualify for the chosen row fills its next space with zero."),
            rule_section(:points, "The seven rows",
              "In Fours, Fives and Sixes, sum only the dice showing the named value. Chance takes the sum of all five dice. A straight is five consecutive values, and a full house is three of one value and two of another. Both score the sum of all five dice. Five equal dice score 50 in Balut regardless of their value. If Balut is full, five sixes can still score 30 in Sixes or Chance."),
            rule_section(:total, "Final score",
              "You earn two points for each of these row totals you reach: 52 in Fours, 65 in Fives, 78 in Sixes and 100 in Chance. Four straights earn four points, four full houses earn three and each Balut earns two. Add up all entries. Below 300, subtract two points. At 300\u2013349, subtract one. At 350\u2013399, make no adjustment. Starting at 400, add one point for each 50 above 350, up to six at 650. The highest final score wins. The maximum is 29 points."),
            rule_section(:controls, "Keyboard",
              "Enter: roll all five dice to begin your turn. Later, reroll the selected dice or open scoring if none are selected. In the score sheet, record the selected row. After the third roll, the sheet appears automatically.",
              "1\u20136: select one die showing that value for a reroll.",
              "Shift+1\u20136: keep one selected die showing that value.",
              "Arrows: choose a row with Up and Down; inspect its entries and totals with Left and Right. Full rows are omitted from the scoring view.",
              "B: open the score sheet in a separate window.",
              "Escape: close the separate score-sheet window without recording a result.",
              "Space: read the dice and, in the rolling field, their selection state.",
              "D: read the last roll.",
              "V: browse your score sheet.",
              "Shift+V: browse another player's score sheet.",
              "F: browse your unfilled rows.",
              "S: read game points.",
              "Shift+S: read the sum of recorded scores.")
          ]
        when "es"
          [
            rule_section(:play, "Tu turno",
              "De dos a ocho jugadores rellenan sus propias tablas por turnos. Cada tabla tiene siete filas de cuatro casillas, as\u00ED que dispones de 28 turnos. El objetivo es conseguir la mayor puntuaci\u00F3n por combinaciones y filas completadas. Pulsa Intro para lanzar los cinco dados. Puedes anotar el resultado o volver a tirar algunos dados hasta dos veces. Si la tirada no cumple la condici\u00F3n de la fila elegida, su siguiente casilla se rellena con cero."),
            rule_section(:points, "Las siete filas",
              "En cuatros, cincos y seises solo sumas los dados del valor indicado. En azar sumas los cinco. Una escalera son cinco valores consecutivos y un full consta de un tr\u00EDo y una pareja. Ambos valen la suma de los cinco dados. Cinco dados iguales valen 50 en Balut, sea cual sea su valor. Si esa fila est\u00E1 llena, cinco seises a\u00FAn pueden valer 30 en seises o en azar."),
            rule_section(:total, "Resultado final",
              "Ganas dos puntos por cada m\u00EDnimo alcanzado: 52 en cuatros, 65 en cincos, 78 en seises y 100 en azar. Cuatro escaleras dan cuatro puntos, cuatro fulls dan tres y cada Balut da dos. Suma tambi\u00E9n todas las anotaciones. Por debajo de 300 resta dos puntos. Entre 300 y 349 resta uno. Entre 350 y 399 no hay ajuste. A partir de 400 suma un punto y otro por cada 50 adicionales, hasta seis a partir de 650. Gana quien tenga m\u00E1s puntos. El m\u00E1ximo es 29."),
            rule_section(:controls, "Teclado",
              "Intro: comenzar el turno tirando cinco dados. Despu\u00E9s, volver a tirar los dados seleccionados o abrir la tabla si no hay ninguno seleccionado. En la tabla, anotar en la fila elegida. Tras la tercera tirada, la tabla aparece autom\u00E1ticamente.",
              "1\u20136: seleccionar un dado de ese valor para volver a tirarlo.",
              "May\u00FAs+1\u20136: desmarcar un dado seleccionado de ese valor.",
              "Flechas: arriba y abajo eligen la fila; izquierda y derecha recorren sus anotaciones y totales. Las filas completas no aparecen al anotar.",
              "B: abrir la tabla en una ventana aparte.",
              "Escape: cerrar la ventana aparte de la tabla sin anotar el resultado.",
              "Espacio: o\u00EDr los dados y, en el campo de tirada, cu\u00E1les est\u00E1n seleccionados.",
              "D: o\u00EDr la \u00FAltima tirada.",
              "V: consultar tu tabla.",
              "May\u00FAs+V: consultar la tabla de otro jugador.",
              "F: consultar tus filas sin completar.",
              "S: o\u00EDr los puntos de juego.",
              "May\u00FAs+S: o\u00EDr la suma de las anotaciones.")
          ]
        when "pl"
          [
            rule_section(:play, "Balut",
              "W grze mo\u017Ce uczestniczy\u0107 od dw\u00F3ch do o\u015Bmiu os\u00F3b. Ka\u017Cdy ma w\u0142asn\u0105 tabel\u0119 z siedmioma kategoriami po cztery pola. W ka\u017Cdej z 28 tur wpisujesz jeden wynik. Pierwszy rzut obejmuje wszystkie pi\u0119\u0107 ko\u015Bci. Potem mo\u017Cesz zapisa\u0107 wynik albo dwa razy przerzuci\u0107 wybrane ko\u015Bci. Po zape\u0142nieniu tabel wygrywa osoba z najwi\u0119ksz\u0105 liczb\u0105 punkt\u00F3w za uk\u0142ady i premie."),
            rule_section(:points, "Punktacja",
              "Pi\u0119\u0107 jednakowych ko\u015Bci daje wpis 50 i dwa punkty ko\u0144cowe. Po czterech Balutach wykorzystaj kolejne takie rzuty w innych wierszach. Najwy\u017Cszy wynik ko\u0144cowy to 29.",
              "W Czw\u00F3rkach, Pi\u0105tkach i Sz\u00F3stkach sumujesz tylko ko\u015Bci o nazwanej warto\u015Bci. W Szansie sumujesz wszystkie pi\u0119\u0107 ko\u015Bci. Mo\u017Cesz wpisa\u0107 zero w wolnym polu, gdy rzut nie daje punkt\u00F3w w wybranej kategorii."),
            rule_section(:thresholds, "Premie za kategorie",
              "Za co najmniej 52 w Czw\u00F3rkach, 65 w Pi\u0105tkach, 78 w Sz\u00F3stkach i 100 w Szansie otrzymujesz po dwa punkty ko\u0144cowe.",
              "Cztery strity daj\u0105 cztery punkty, a cztery fulle daj\u0105 trzy. Strit to pi\u0119\u0107 kolejnych warto\u015Bci, a full to tr\u00F3jka i para. W obu wierszach wpisujesz sum\u0119 oczek.",
              "Po wype\u0142nieniu wiersza Balut pi\u0119\u0107 sz\u00F3stek nadal mo\u017Cesz wpisa\u0107 jako 30 w Sz\u00F3stkach lub Szansie, je\u015Bli masz tam wolne pole.",
              "Przyk\u0142ad. Cztery czw\u00F3rki w jednym rzucie daj\u0105 wpis 16. Je\u015Bli powt\u00F3rzysz ten wynik, suma Czw\u00F3rek wzro\u015Bnie do 32, a punkty za kategori\u0119 pozostan\u0105 na zerze. Dopiero po osi\u0105gni\u0119ciu 52 oczek w tym wierszu dostaniesz dwa punkty do wyniku gry."),
            rule_section(:total, "Suma punkt\u00F3w",
              "Do wyniku gry doliczasz punkty zale\u017Cne od sumy wszystkich wpis\u00F3w.",
              "- 0\u2013299 \u2014 minus 2 punkty",
              "- 300\u2013349 \u2014 minus 1 punkt",
              "- 350\u2013399 \u2014 0 punkt\u00F3w",
              "- 400\u2013449 \u2014 1 punkt",
              "- 450\u2013499 \u2014 2 punkty",
              "- 500\u2013549 \u2014 3 punkty",
              "- 550\u2013599 \u2014 4 punkty",
              "- 600\u2013649 \u2014 5 punkt\u00F3w",
              "- 650 i wi\u0119cej \u2014 6 punkt\u00F3w"),
            rule_section(:controls, "Klawiatura",
              "Enter: rozpocznij tur\u0119 rzutem pi\u0119cioma ko\u015B\u0107mi. P\u00F3\u017Aniej przerzu\u0107 zaznaczone ko\u015Bci albo otw\u00F3rz tabel\u0119 zapisu, je\u015Bli \u017Cadna nie jest zaznaczona. W tabeli zapisz wynik w wybranym wierszu. Po trzecim rzucie tabela pojawia si\u0119 automatycznie.",
              "1\u20136: zaznacz do przerzutu jedn\u0105 ko\u015B\u0107 o tej warto\u015Bci.",
              "Shift+1\u20136: odznacz jedn\u0105 wybran\u0105 ko\u015B\u0107 o tej warto\u015Bci.",
              "Strza\u0142ki: g\u00F3ra i d\u00F3\u0142 wybieraj\u0105 wiersz, a lewo i prawo pozwalaj\u0105 sprawdzi\u0107 jego wpisy oraz podsumowania. Pe\u0142ne wiersze s\u0105 pomijane w tabeli zapisu.",
              "B: otw\u00F3rz tabel\u0119 punktacji w osobnym oknie.",
              "Escape: zamknij osobne okno tabeli bez zapisania wyniku.",
              "Spacja: odczytaj ko\u015Bci, a w polu rzutu tak\u017Ce ich zaznaczenie.",
              "D: odczytaj ostatni rzut.",
              "V: przejrzyj swoj\u0105 tabel\u0119.",
              "Shift+V: przejrzyj tabel\u0119 innego gracza.",
              "F: przejrzyj w\u0142asne niewype\u0142nione wiersze.",
              "S: odczytaj punkty do wyniku gry.",
              "Shift+S: odczytaj sum\u0119 zapisanych punkt\u00F3w.")
          ]
        when "ru"
          [
            rule_section(:play, "\u0412\u0430\u0448 \u0445\u043E\u0434",
              "\u041E\u0442 \u0434\u0432\u0443\u0445 \u0434\u043E \u0432\u043E\u0441\u044C\u043C\u0438 \u0438\u0433\u0440\u043E\u043A\u043E\u0432 \u043F\u043E \u043E\u0447\u0435\u0440\u0435\u0434\u0438 \u0437\u0430\u043F\u043E\u043B\u043D\u044F\u044E\u0442 \u0441\u0432\u043E\u0438 \u0442\u0430\u0431\u043B\u0438\u0446\u044B. \u0412 \u043A\u0430\u0436\u0434\u043E\u0439 \u0442\u0430\u0431\u043B\u0438\u0446\u0435 \u0441\u0435\u043C\u044C \u0441\u0442\u0440\u043E\u043A \u043F\u043E \u0447\u0435\u0442\u044B\u0440\u0435 \u043A\u043B\u0435\u0442\u043A\u0438, \u043F\u043E\u044D\u0442\u043E\u043C\u0443 \u0443 \u0432\u0430\u0441 28 \u0445\u043E\u0434\u043E\u0432. \u0426\u0435\u043B\u044C \u2014 \u043D\u0430\u0431\u0440\u0430\u0442\u044C \u0431\u043E\u043B\u044C\u0448\u0435 \u0432\u0441\u0435\u0445 \u0438\u0433\u0440\u043E\u0432\u044B\u0445 \u043E\u0447\u043A\u043E\u0432 \u0437\u0430 \u043A\u043E\u043C\u0431\u0438\u043D\u0430\u0446\u0438\u0438 \u0438 \u0437\u0430\u043F\u043E\u043B\u043D\u0435\u043D\u043D\u044B\u0435 \u0441\u0442\u0440\u043E\u043A\u0438. \u041D\u0430\u0436\u043C\u0438\u0442\u0435 Enter, \u0447\u0442\u043E\u0431\u044B \u0431\u0440\u043E\u0441\u0438\u0442\u044C \u043F\u044F\u0442\u044C \u043A\u0443\u0431\u0438\u043A\u043E\u0432. \u041C\u043E\u0436\u043D\u043E \u0437\u0430\u043F\u0438\u0441\u0430\u0442\u044C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442 \u0438\u043B\u0438 \u0435\u0449\u0451 \u0434\u0432\u0430 \u0440\u0430\u0437\u0430 \u043F\u0435\u0440\u0435\u0431\u0440\u043E\u0441\u0438\u0442\u044C \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u044B\u0435 \u043A\u0443\u0431\u0438\u043A\u0438. \u0415\u0441\u043B\u0438 \u0431\u0440\u043E\u0441\u043E\u043A \u043D\u0435 \u043F\u043E\u0434\u0445\u043E\u0434\u0438\u0442 \u0434\u043B\u044F \u0441\u0442\u0440\u043E\u043A\u0438, \u0435\u0451 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0430\u044F \u043A\u043B\u0435\u0442\u043A\u0430 \u0437\u0430\u043F\u043E\u043B\u043D\u044F\u0435\u0442\u0441\u044F \u043D\u0443\u043B\u0451\u043C."),
            rule_section(:points, "\u0421\u0435\u043C\u044C \u0441\u0442\u0440\u043E\u043A",
              "\u0412 \u0441\u0442\u0440\u043E\u043A\u0430\u0445 \u0447\u0435\u0442\u0432\u0451\u0440\u043E\u043A, \u043F\u044F\u0442\u0451\u0440\u043E\u043A \u0438 \u0448\u0435\u0441\u0442\u0451\u0440\u043E\u043A \u0441\u043B\u043E\u0436\u0438\u0442\u0435 \u0442\u043E\u043B\u044C\u043A\u043E \u0437\u043D\u0430\u0447\u0435\u043D\u0438\u044F \u043F\u043E\u0434\u0445\u043E\u0434\u044F\u0449\u0438\u0445 \u043A\u0443\u0431\u0438\u043A\u043E\u0432. \u0412 \u0441\u0442\u0440\u043E\u043A\u0435 \u00AB\u0428\u0430\u043D\u0441\u00BB \u0441\u043B\u043E\u0436\u0438\u0442\u0435 \u0432\u0441\u0435 \u043F\u044F\u0442\u044C. \u0421\u0442\u0440\u0438\u0442 \u2014 \u044D\u0442\u043E \u043F\u044F\u0442\u044C \u0447\u0438\u0441\u0435\u043B \u043F\u043E\u0434\u0440\u044F\u0434, \u0430 \u0444\u0443\u043B\u043B-\u0445\u0430\u0443\u0441 \u2014 \u0442\u0440\u043E\u0439\u043A\u0430 \u0438 \u043F\u0430\u0440\u0430. \u0412 \u043E\u0431\u043E\u0438\u0445 \u0441\u043B\u0443\u0447\u0430\u044F\u0445 \u0437\u0430\u043F\u0438\u0448\u0438\u0442\u0435 \u0441\u0443\u043C\u043C\u0443 \u0432\u0441\u0435\u0445 \u043A\u0443\u0431\u0438\u043A\u043E\u0432. \u041F\u044F\u0442\u044C \u043E\u0434\u0438\u043D\u0430\u043A\u043E\u0432\u044B\u0445 \u043A\u0443\u0431\u0438\u043A\u043E\u0432 \u0434\u0430\u044E\u0442 50 \u0432 \u0441\u0442\u0440\u043E\u043A\u0435 \u00AB\u0411\u0430\u043B\u0443\u0442\u00BB \u043D\u0435\u0437\u0430\u0432\u0438\u0441\u0438\u043C\u043E \u043E\u0442 \u0447\u0438\u0441\u043B\u0430 \u043D\u0430 \u043D\u0438\u0445. \u0415\u0441\u043B\u0438 \u044D\u0442\u0430 \u0441\u0442\u0440\u043E\u043A\u0430 \u0437\u0430\u043F\u043E\u043B\u043D\u0435\u043D\u0430, \u043F\u044F\u0442\u044C \u0448\u0435\u0441\u0442\u0451\u0440\u043E\u043A \u043C\u043E\u0436\u043D\u043E \u0437\u0430\u043F\u0438\u0441\u0430\u0442\u044C \u043A\u0430\u043A 30 \u0432 \u0448\u0435\u0441\u0442\u0451\u0440\u043A\u0438 \u0438\u043B\u0438 \u0432 \u00AB\u0428\u0430\u043D\u0441\u00BB."),
            rule_section(:total, "\u0418\u0442\u043E\u0433\u043E\u0432\u044B\u0439 \u0441\u0447\u0451\u0442",
              "\u041D\u0430\u0447\u0438\u0441\u043B\u0438\u0442\u0435 \u043F\u043E \u0434\u0432\u0430 \u043E\u0447\u043A\u0430 \u0437\u0430 \u043A\u0430\u0436\u0434\u044B\u0439 \u0434\u043E\u0441\u0442\u0438\u0433\u043D\u0443\u0442\u044B\u0439 \u043F\u043E\u0440\u043E\u0433: 52 \u0432 \u0447\u0435\u0442\u0432\u0451\u0440\u043A\u0430\u0445, 65 \u0432 \u043F\u044F\u0442\u0451\u0440\u043A\u0430\u0445, 78 \u0432 \u0448\u0435\u0441\u0442\u0451\u0440\u043A\u0430\u0445 \u0438 100 \u0432 \u00AB\u0428\u0430\u043D\u0441\u0435\u00BB. \u0427\u0435\u0442\u044B\u0440\u0435 \u0441\u0442\u0440\u0438\u0442\u0430 \u0434\u0430\u044E\u0442 \u0447\u0435\u0442\u044B\u0440\u0435 \u043E\u0447\u043A\u0430, \u0447\u0435\u0442\u044B\u0440\u0435 \u0444\u0443\u043B\u043B-\u0445\u0430\u0443\u0441\u0430 \u2014 \u0442\u0440\u0438, \u0430 \u043A\u0430\u0436\u0434\u044B\u0439 \u0431\u0430\u043B\u0443\u0442 \u2014 \u0434\u0432\u0430. \u0421\u043B\u043E\u0436\u0438\u0442\u0435 \u0442\u0430\u043A\u0436\u0435 \u0432\u0441\u0435 \u0437\u0430\u043F\u0438\u0441\u0438 \u0432 \u0442\u0430\u0431\u043B\u0438\u0446\u0435. \u041F\u0440\u0438 \u0441\u0443\u043C\u043C\u0435 \u043C\u0435\u043D\u044C\u0448\u0435 300 \u0432\u044B\u0447\u0442\u0438\u0442\u0435 \u0434\u0432\u0430 \u043E\u0447\u043A\u0430, \u043E\u0442 300 \u0434\u043E 349 \u2014 \u043E\u0434\u043D\u043E. \u041E\u0442 350 \u0434\u043E 399 \u043F\u043E\u043F\u0440\u0430\u0432\u043A\u0438 \u043D\u0435\u0442. \u0417\u0430 400 \u0434\u043E\u0431\u0430\u0432\u044C\u0442\u0435 \u043E\u0434\u043D\u043E \u043E\u0447\u043A\u043E \u0438 \u0435\u0449\u0451 \u043F\u043E \u043E\u0434\u043D\u043E\u043C\u0443 \u0437\u0430 \u043A\u0430\u0436\u0434\u044B\u0435 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0438\u0435 50, \u043C\u0430\u043A\u0441\u0438\u043C\u0443\u043C \u0448\u0435\u0441\u0442\u044C \u043F\u0440\u0438 \u0441\u0443\u043C\u043C\u0435 \u043E\u0442 650. \u041F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u0438\u0433\u0440\u043E\u043A \u0441 \u043D\u0430\u0438\u0431\u043E\u043B\u044C\u0448\u0438\u043C \u0438\u0442\u043E\u0433\u043E\u0432\u044B\u043C \u0441\u0447\u0451\u0442\u043E\u043C. \u041C\u0430\u043A\u0441\u0438\u043C\u0443\u043C \u2014 29 \u043E\u0447\u043A\u043E\u0432."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0430\u0442\u0443\u0440\u0430",
              "Enter: \u043D\u0430\u0447\u0430\u0442\u044C \u0445\u043E\u0434 \u0431\u0440\u043E\u0441\u043A\u043E\u043C \u043F\u044F\u0442\u0438 \u043A\u0443\u0431\u0438\u043A\u043E\u0432. \u0417\u0430\u0442\u0435\u043C \u043F\u0435\u0440\u0435\u0431\u0440\u043E\u0441\u0438\u0442\u044C \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u044B\u0435 \u043A\u0443\u0431\u0438\u043A\u0438 \u0438\u043B\u0438 \u043E\u0442\u043A\u0440\u044B\u0442\u044C \u0442\u0430\u0431\u043B\u0438\u0446\u0443, \u0435\u0441\u043B\u0438 \u043D\u0438 \u043E\u0434\u0438\u043D \u043D\u0435 \u0432\u044B\u0431\u0440\u0430\u043D. \u0412 \u0442\u0430\u0431\u043B\u0438\u0446\u0435 \u0437\u0430\u043F\u0438\u0441\u0430\u0442\u044C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442 \u0432 \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u0443\u044E \u0441\u0442\u0440\u043E\u043A\u0443. \u041F\u043E\u0441\u043B\u0435 \u0442\u0440\u0435\u0442\u044C\u0435\u0433\u043E \u0431\u0440\u043E\u0441\u043A\u0430 \u0442\u0430\u0431\u043B\u0438\u0446\u0430 \u043F\u043E\u044F\u0432\u043B\u044F\u0435\u0442\u0441\u044F \u0430\u0432\u0442\u043E\u043C\u0430\u0442\u0438\u0447\u0435\u0441\u043A\u0438.",
              "1\u20136: \u0432\u044B\u0431\u0440\u0430\u0442\u044C \u0434\u043B\u044F \u043F\u0435\u0440\u0435\u0431\u0440\u043E\u0441\u0430 \u043E\u0434\u0438\u043D \u043A\u0443\u0431\u0438\u043A \u0441 \u0442\u0430\u043A\u0438\u043C \u0437\u043D\u0430\u0447\u0435\u043D\u0438\u0435\u043C.",
              "Shift+1\u20136: \u0441\u043D\u044F\u0442\u044C \u0432\u044B\u0431\u043E\u0440 \u043E\u0434\u043D\u043E\u0433\u043E \u043A\u0443\u0431\u0438\u043A\u0430 \u0441 \u0442\u0430\u043A\u0438\u043C \u0437\u043D\u0430\u0447\u0435\u043D\u0438\u0435\u043C.",
              "\u0421\u0442\u0440\u0435\u043B\u043A\u0438: \u0432\u0432\u0435\u0440\u0445 \u0438 \u0432\u043D\u0438\u0437 \u0432\u044B\u0431\u0438\u0440\u0430\u044E\u0442 \u0441\u0442\u0440\u043E\u043A\u0443, \u0432\u043B\u0435\u0432\u043E \u0438 \u0432\u043F\u0440\u0430\u0432\u043E \u043F\u043E\u0437\u0432\u043E\u043B\u044F\u044E\u0442 \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u0442\u044C \u0435\u0451 \u0437\u0430\u043F\u0438\u0441\u0438 \u0438 \u0438\u0442\u043E\u0433\u0438. \u0417\u0430\u043F\u043E\u043B\u043D\u0435\u043D\u043D\u044B\u0435 \u0441\u0442\u0440\u043E\u043A\u0438 \u043D\u0435 \u043F\u0440\u0435\u0434\u043B\u0430\u0433\u0430\u044E\u0442\u0441\u044F \u0434\u043B\u044F \u0437\u0430\u043F\u0438\u0441\u0438.",
              "B: \u043E\u0442\u043A\u0440\u044B\u0442\u044C \u0442\u0430\u0431\u043B\u0438\u0446\u0443 \u0432 \u043E\u0442\u0434\u0435\u043B\u044C\u043D\u043E\u043C \u043E\u043A\u043D\u0435.",
              "Escape: \u0437\u0430\u043A\u0440\u044B\u0442\u044C \u043E\u0442\u0434\u0435\u043B\u044C\u043D\u043E\u0435 \u043E\u043A\u043D\u043E \u0442\u0430\u0431\u043B\u0438\u0446\u044B \u0431\u0435\u0437 \u0437\u0430\u043F\u0438\u0441\u0438 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0430.",
              "\u041F\u0440\u043E\u0431\u0435\u043B: \u043F\u0440\u043E\u0441\u043B\u0443\u0448\u0430\u0442\u044C \u043A\u0443\u0431\u0438\u043A\u0438, \u0430 \u0432 \u043F\u043E\u043B\u0435 \u0431\u0440\u043E\u0441\u043A\u0430 \u0442\u0430\u043A\u0436\u0435 \u0438\u0445 \u0432\u044B\u0431\u043E\u0440.",
              "D: \u043F\u0440\u043E\u0441\u043B\u0443\u0448\u0430\u0442\u044C \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0438\u0439 \u0431\u0440\u043E\u0441\u043E\u043A.",
              "V: \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u0442\u044C \u0441\u0432\u043E\u044E \u0442\u0430\u0431\u043B\u0438\u0446\u0443.",
              "Shift+V: \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u0442\u044C \u0442\u0430\u0431\u043B\u0438\u0446\u0443 \u0434\u0440\u0443\u0433\u043E\u0433\u043E \u0438\u0433\u0440\u043E\u043A\u0430.",
              "F: \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u0442\u044C \u0441\u0432\u043E\u0438 \u043D\u0435\u0437\u0430\u043F\u043E\u043B\u043D\u0435\u043D\u043D\u044B\u0435 \u0441\u0442\u0440\u043E\u043A\u0438.",
              "S: \u043F\u0440\u043E\u0441\u043B\u0443\u0448\u0430\u0442\u044C \u0438\u0433\u0440\u043E\u0432\u044B\u0435 \u043E\u0447\u043A\u0438.",
              "Shift+S: \u043F\u0440\u043E\u0441\u043B\u0443\u0448\u0430\u0442\u044C \u0441\u0443\u043C\u043C\u0443 \u0437\u0430\u043F\u0438\u0441\u0430\u043D\u043D\u044B\u0445 \u043E\u0447\u043A\u043E\u0432.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
