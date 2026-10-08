# Generated from tools/data/rulebooks/four_in_a_row.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class FourInARow
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:falling, GameRoomRules.translate("Build a line from falling pieces"),
            GameRoomRules.translate("Two players take turns dropping pieces into a board with seven columns and six rows. Your aim is to join at least four of your own pieces in a straight line. The first player at the table starts."),
            GameRoomRules.translate("Each turn consists of choosing one column. Your piece falls to the lowest empty square in that column. You cannot leave it suspended higher up: if the column is empty, it lands at the bottom; if it already holds two pieces, yours rests on top of them. A full column cannot accept another piece."),
            GameRoomRules.translate("A winning line may be horizontal, vertical or diagonal. All its pieces must touch: a gap or an opponent's piece breaks the line. Completing a line ends the game immediately. If all 42 squares fill up without a winner, the game is drawn."),
            GameRoomRules.translate("There are no optional board sizes or alternative placement rules in this game. Either player can be a bot.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse the board."),
            GameRoomRules.translate("Enter: drop a piece into the selected column."),
            GameRoomRules.translate("T: read whose turn it is."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:aim, "C\u00EDl hry",
              "Ve h\u0159e \u010Cty\u0159i v \u0159ad\u011B soupe\u0159\u00ED dva hr\u00E1\u010Di, ka\u017Ed\u00FD s jinou barvou kamen\u016F. Vyhraje\u0161, kdy\u017E spoj\u00ED\u0161 alespo\u0148 \u010Dty\u0159i sv\u00E9 kameny vodorovn\u011B, svisle nebo \u0161ikmo."),
            rule_section(:play, "Vhazov\u00E1n\u00ED kamen\u016F",
              "Hrac\u00ED plocha m\u00E1 sedm sloupc\u016F a \u0161est \u0159\u00E1dk\u016F. P\u0159edstav si ji postavenou na v\u00FD\u0161ku: vhozen\u00FD k\u00E1men pad\u00E1 dol\u016F, dokud se nezastav\u00ED na dn\u011B sloupce nebo na jin\u00E9m kameni.",
              "Za\u010D\u00EDn\u00E1 prvn\u00ED hr\u00E1\u010D. Potom se st\u0159\u00EDd\u00E1te a ka\u017Ed\u00FD vhod\u00ED jeden k\u00E1men. \u0160ipkami vlevo a vpravo vyber sloupec a stiskni Enter. V\u00FD\u0161ku nevyb\u00EDr\u00E1\u0161, k\u00E1men obsad\u00ED nejni\u017E\u0161\u00ED voln\u00E9 pole.",
              "\u0160ipkami m\u016F\u017Ee\u0161 tak\u00E9 prozkoumat celou plochu a zjistit, kde u\u017E kameny le\u017E\u00ED. Do pln\u00E9ho sloupce dal\u0161\u00ED k\u00E1men nepat\u0159\u00ED; zvol jin\u00FD."),
            rule_section(:ending, "Jak hra skon\u010D\u00ED",
              "\u010Cty\u0159i spojen\u00E9 kameny stejn\u00E9 barvy znamenaj\u00ED okam\u017Eit\u00E9 v\u00EDt\u011Bzstv\u00ED. Pokud je obsazeno v\u0161ech 42 pol\u00ED a nikdo takovou nep\u0159eru\u0161enou \u0159adu nem\u00E1, hra kon\u010D\u00ED rem\u00EDzou."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "\u0160ipky: proch\u00E1zet hrac\u00ED plochu.",
              "Enter: vhodit k\u00E1men do vybran\u00E9ho sloupce.",
              "T: ozn\u00E1mit, kdo je na tahu.")
          ]
        when "en"
          [
            rule_section(:aim, "The aim",
              "Two players take turns dropping counters into a grid. Make a continuous line of at least four of your own colour, horizontally, vertically or diagonally, to win."),
            rule_section(:play, "Dropping a counter",
              "The board has seven columns and six rows. Counters fall to the bottom of a column, stopping on the floor or on the counter already below them.",
              "The first player opens, and you then take turns dropping one counter each. Choose a column with Left or Right arrow and press Enter. You choose the column, not the height: your counter falls into its lowest empty space.",
              "Use the arrow keys to explore the board and check existing lines. A full column cannot take another counter."),
            rule_section(:ending, "Winning and drawing",
              "A line of four wins immediately. If all 42 spaces fill up without a winning line, the game is a draw."),
            rule_section(:controls, "Keyboard shortcuts",
              "Arrows: explore the board.",
              "Enter: drop a counter into the selected column.",
              "T: read whose turn it is.")
          ]
        when "es"
          [
            rule_section(:aim, "Objetivo",
              "En Cuatro en raya se enfrentan dos personas, cada una con un color de fichas. Debes formar una l\u00EDnea de al menos cuatro fichas de tu color, en horizontal, vertical o diagonal."),
            rule_section(:play, "Dejar caer las fichas",
              "El tablero tiene siete columnas y seis filas. Est\u00E1 en posici\u00F3n vertical: cada ficha cae hasta el fondo de su columna o hasta quedar apoyada sobre otra.",
              "Empieza el primer jugador y despu\u00E9s os altern\u00E1is, colocando una ficha por turno. Elige una columna con las flechas izquierda y derecha y pulsa Enter. No eliges la altura: la ficha ocupa la casilla libre m\u00E1s baja.",
              "Con las flechas tambi\u00E9n puedes explorar todo el tablero para revisar las fichas colocadas. Si una columna est\u00E1 llena, debes escoger otra."),
            rule_section(:ending, "Victoria y empate",
              "Ganas en cuanto formas una l\u00EDnea de cuatro fichas propias sin huecos. Si se ocupan las cuarenta y dos casillas sin que nadie consiga esa l\u00EDnea, la partida acaba en empate."),
            rule_section(:controls, "Teclas de referencia",
              "Flechas: recorrer el tablero.",
              "Enter: dejar caer una ficha en la columna elegida.",
              "T: consultar de qui\u00E9n es el turno.")
          ]
        when "pl"
          [
            rule_section(:aim, "Cel gry",
              "W Czw\u00F3rkach graj\u0105 dwie osoby. Ka\u017Cda ma sw\u00F3j kolor pionk\u00F3w i pr\u00F3buje u\u0142o\u017Cy\u0107 przynajmniej cztery obok siebie: poziomo, pionowo lub po przek\u0105tnej."),
            rule_section(:play, "Wrzucanie pionk\u00F3w",
              "Plansza ma siedem kolumn i sze\u015B\u0107 rz\u0119d\u00F3w. Jest ustawiona pionowo, dlatego pionki opadaj\u0105 na d\u00F3\u0142 kolumny. Nowy pionek zatrzymuje si\u0119 na dnie albo na pionku, kt\u00F3ry ju\u017C tam stoi.",
              "Gracze na zmian\u0119 wrzucaj\u0105 po jednym pionku; zaczyna pierwszy gracz. Strza\u0142kami w lewo i w prawo wybierz kolumn\u0119, a potem naci\u015Bnij Enter. Nie wybierasz wysoko\u015Bci: pionek sam zajmie najni\u017Csze wolne pole.",
              "Strza\u0142kami mo\u017Cesz r\u00F3wnie\u017C przegl\u0105da\u0107 ca\u0142\u0105 plansz\u0119 i sprawdza\u0107 u\u0142o\u017Cenie pionk\u00F3w. Gdy kolumna jest ju\u017C pe\u0142na, trzeba wybra\u0107 inn\u0105."),
            rule_section(:ending, "Zako\u0144czenie partii",
              "Wygrywasz natychmiast po ustawieniu czterech swoich pionk\u00F3w w jednej linii bez przerw. Je\u015Bli wszystkie czterdzie\u015Bci dwa pola zostan\u0105 zaj\u0119te i nikt nie ma takiej linii, partia ko\u0144czy si\u0119 remisem."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "Strza\u0142ki: przegl\u0105daj plansz\u0119.",
              "Enter: wrzu\u0107 pionek do wybranej kolumny.",
              "T: odczytaj, czyja jest tura.")
          ]
        when "ru"
          [
            rule_section(:aim, "\u0426\u0435\u043B\u044C \u0438\u0433\u0440\u044B",
              "\u0412 \u00AB\u0427\u0435\u0442\u044B\u0440\u0435 \u0432 \u0440\u044F\u0434\u00BB \u0434\u0432\u0430 \u0438\u0433\u0440\u043E\u043A\u0430 \u043F\u043E \u043E\u0447\u0435\u0440\u0435\u0434\u0438 \u043E\u043F\u0443\u0441\u043A\u0430\u044E\u0442 \u0444\u0438\u0448\u043A\u0438 \u0441\u0432\u043E\u0435\u0433\u043E \u0446\u0432\u0435\u0442\u0430 \u0432 \u043F\u043E\u043B\u0435. \u041F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u0442\u043E\u0442, \u043A\u0442\u043E \u043F\u0435\u0440\u0432\u044B\u043C \u0441\u043E\u0431\u0435\u0440\u0451\u0442 \u0445\u043E\u0442\u044F \u0431\u044B \u0447\u0435\u0442\u044B\u0440\u0435 \u0444\u0438\u0448\u043A\u0438 \u043F\u043E\u0434\u0440\u044F\u0434 \u043F\u043E \u0433\u043E\u0440\u0438\u0437\u043E\u043D\u0442\u0430\u043B\u0438, \u0432\u0435\u0440\u0442\u0438\u043A\u0430\u043B\u0438 \u0438\u043B\u0438 \u0434\u0438\u0430\u0433\u043E\u043D\u0430\u043B\u0438."),
            rule_section(:play, "\u041A\u0430\u043A \u0441\u0442\u0430\u0432\u0438\u0442\u044C \u0444\u0438\u0448\u043A\u0438",
              "\u041F\u043E\u043B\u0435 \u0441\u043E\u0441\u0442\u043E\u0438\u0442 \u0438\u0437 \u0441\u0435\u043C\u0438 \u0441\u0442\u043E\u043B\u0431\u0446\u043E\u0432 \u043F\u043E \u0448\u0435\u0441\u0442\u044C \u043A\u043B\u0435\u0442\u043E\u043A \u0438 \u0441\u0442\u043E\u0438\u0442 \u0432\u0435\u0440\u0442\u0438\u043A\u0430\u043B\u044C\u043D\u043E. \u041F\u043E\u044D\u0442\u043E\u043C\u0443 \u0444\u0438\u0448\u043A\u0430 \u043F\u0430\u0434\u0430\u0435\u0442 \u0432\u043D\u0438\u0437: \u043B\u0438\u0431\u043E \u043D\u0430 \u0434\u043D\u043E \u0441\u0442\u043E\u043B\u0431\u0446\u0430, \u043B\u0438\u0431\u043E \u043D\u0430 \u0443\u0436\u0435 \u043D\u0430\u0445\u043E\u0434\u044F\u0449\u0443\u044E\u0441\u044F \u0442\u0430\u043C \u0444\u0438\u0448\u043A\u0443.",
              "\u041D\u0430\u0447\u0438\u043D\u0430\u0435\u0442 \u043F\u0435\u0440\u0432\u044B\u0439 \u0438\u0433\u0440\u043E\u043A, \u0437\u0430\u0442\u0435\u043C \u0445\u043E\u0434\u044B \u0447\u0435\u0440\u0435\u0434\u0443\u044E\u0442\u0441\u044F. \u0421\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0432\u043B\u0435\u0432\u043E \u0438 \u0432\u043F\u0440\u0430\u0432\u043E \u0432\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0441\u0442\u043E\u043B\u0431\u0435\u0446 \u0438 \u043D\u0430\u0436\u043C\u0438\u0442\u0435 Enter, \u0447\u0442\u043E\u0431\u044B \u043E\u043F\u0443\u0441\u0442\u0438\u0442\u044C \u0432 \u043D\u0435\u0433\u043E \u043E\u0434\u043D\u0443 \u0444\u0438\u0448\u043A\u0443. \u0412\u044B\u0441\u043E\u0442\u0443 \u0432\u044B\u0431\u0438\u0440\u0430\u0442\u044C \u043D\u0435 \u043D\u0443\u0436\u043D\u043E \u2014 \u0444\u0438\u0448\u043A\u0430 \u0437\u0430\u0439\u043C\u0451\u0442 \u0441\u0430\u043C\u0443\u044E \u043D\u0438\u0436\u043D\u044E\u044E \u0441\u0432\u043E\u0431\u043E\u0434\u043D\u0443\u044E \u043A\u043B\u0435\u0442\u043A\u0443.",
              "\u0421\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u043C\u043E\u0436\u043D\u043E \u0442\u0430\u043A\u0436\u0435 \u043E\u0441\u043C\u043E\u0442\u0440\u0435\u0442\u044C \u0432\u0441\u0451 \u043F\u043E\u043B\u0435 \u0438 \u0443\u0437\u043D\u0430\u0442\u044C, \u0433\u0434\u0435 \u0441\u0442\u043E\u044F\u0442 \u0444\u0438\u0448\u043A\u0438. \u0412 \u0437\u0430\u043F\u043E\u043B\u043D\u0435\u043D\u043D\u044B\u0439 \u0441\u0442\u043E\u043B\u0431\u0435\u0446 \u0434\u043E\u0431\u0430\u0432\u043B\u044F\u0442\u044C \u043D\u0435\u043B\u044C\u0437\u044F; \u0432\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0434\u0440\u0443\u0433\u043E\u0439."),
            rule_section(:ending, "\u041A\u043E\u043D\u0435\u0446 \u043F\u0430\u0440\u0442\u0438\u0438",
              "\u041A\u0430\u043A \u0442\u043E\u043B\u044C\u043A\u043E \u0443 \u0438\u0433\u0440\u043E\u043A\u0430 \u043F\u043E\u044F\u0432\u043B\u044F\u0435\u0442\u0441\u044F \u043D\u0435\u043F\u0440\u0435\u0440\u044B\u0432\u043D\u0430\u044F \u043B\u0438\u043D\u0438\u044F \u0438\u0437 \u0447\u0435\u0442\u044B\u0440\u0451\u0445 \u0441\u0432\u043E\u0438\u0445 \u0444\u0438\u0448\u0435\u043A, \u043E\u043D \u043F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442. \u0415\u0441\u043B\u0438 \u0437\u0430\u043D\u044F\u0442\u044B \u0432\u0441\u0435 42 \u043A\u043B\u0435\u0442\u043A\u0438 \u0438 \u0442\u0430\u043A\u043E\u0439 \u043B\u0438\u043D\u0438\u0438 \u043D\u0438 \u0443 \u043A\u043E\u0433\u043E \u043D\u0435\u0442, \u043F\u0430\u0440\u0442\u0438\u044F \u0437\u0430\u043A\u0430\u043D\u0447\u0438\u0432\u0430\u0435\u0442\u0441\u044F \u0432\u043D\u0438\u0447\u044C\u044E."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0448\u0438 \u0443\u043F\u0440\u0430\u0432\u043B\u0435\u043D\u0438\u044F",
              "\u0421\u0442\u0440\u0435\u043B\u043A\u0438: \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u0442\u044C \u043F\u043E\u043B\u0435.",
              "Enter: \u043E\u043F\u0443\u0441\u0442\u0438\u0442\u044C \u0444\u0438\u0448\u043A\u0443 \u0432 \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u044B\u0439 \u0441\u0442\u043E\u043B\u0431\u0435\u0446.",
              "T: \u0443\u0437\u043D\u0430\u0442\u044C, \u0447\u0435\u0439 \u0441\u0435\u0439\u0447\u0430\u0441 \u0445\u043E\u0434.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
