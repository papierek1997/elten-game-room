# Generated from tools/data/rulebooks/tic_tac_toe.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class TicTacToe
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:line, GameRoomRules.translate("A small board, three marks to win"),
            GameRoomRules.translate("In Tic-tac-toe, two players try to make a line of three of their own marks. The board has three rows and three columns. The first player uses X and makes the first move; the other uses O."),
            GameRoomRules.translate("On your turn, choose one empty square and place your mark there. Then it is your opponent's turn. Once placed, a mark stays where it is: you cannot move it or replace an opponent's mark."),
            GameRoomRules.translate("A line can run across a row, down a column or along either diagonal. For example, owning the top-left, centre and bottom-right squares wins the game. The game ends as soon as a line is completed, even if other squares are still empty. If the board fills up without a winning line, the result is a draw."),
            GameRoomRules.translate("Power Games uses this 3 by 3 version without additional rule variants. You may play against another person or a bot.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse squares."),
            GameRoomRules.translate("Enter: place your mark on the selected empty square."),
            GameRoomRules.translate("T: read whose turn it is."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:aim, "C\u00EDl hry",
              "Pi\u0161kvorky hraj\u00ED dva hr\u00E1\u010Di na dev\u00EDti pol\u00EDch ve t\u0159ech \u0159\u00E1dc\u00EDch a t\u0159ech sloupc\u00EDch. Sna\u017E\u00ED\u0161 se spojit t\u0159i sv\u00E9 zna\u010Dky do \u0159ady, sloupce nebo \u00FAhlop\u0159\u00ED\u010Dky."),
            rule_section(:play, "Pokl\u00E1d\u00E1n\u00ED zna\u010Dek",
              "Za\u010D\u00EDn\u00E1 prvn\u00ED hr\u00E1\u010D s k\u0159\u00ED\u017Eky, druh\u00FD m\u00E1 kole\u010Dka. St\u0159\u00EDd\u00E1te se a p\u0159i ka\u017Ed\u00E9m tahu obsad\u00EDte jednu volnou pozici.",
              "Na pole p\u0159ejdi \u0161ipkami a svou zna\u010Dku polo\u017E Enterem. U\u017E polo\u017Een\u00E9 zna\u010Dky se neposouvaj\u00ED. M\u00E1-li soupe\u0159 dv\u011B zna\u010Dky v jedn\u00E9 \u0159ad\u011B, sloupci nebo \u00FAhlop\u0159\u00ED\u010Dce, m\u016F\u017Ee\u0161 obsadit t\u0159et\u00ED pole a zabr\u00E1nit mu tak ve v\u00EDt\u011Bzstv\u00ED."),
            rule_section(:ending, "V\u00EDt\u011Bzstv\u00ED a rem\u00EDza",
              "Jakmile n\u011Bkdo spoj\u00ED t\u0159i sv\u00E9 zna\u010Dky, vyhr\u00E1v\u00E1 a hra kon\u010D\u00ED. Zapln\u00EDte-li v\u0161echna pole bez v\u00EDt\u011Bzn\u00E9 trojice, je to rem\u00EDza."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "\u0160ipky: proch\u00E1zet hrac\u00ED plochu.",
              "Enter: polo\u017Eit zna\u010Dku na vybran\u00E9 voln\u00E9 pole.",
              "T: ozn\u00E1mit, kdo je na tahu.")
          ]
        when "en"
          [
            rule_section(:aim, "The aim",
              "Tic-tac-toe is played by two people on a three-by-three grid. Make a row, column or diagonal of three of your own marks to win."),
            rule_section(:play, "Taking a turn",
              "The first player uses crosses and makes the opening move; the other uses noughts. Take turns marking one empty square.",
              "Move to a square with the arrows and press Enter to mark it. Marks stay where they are placed. If your opponent has two in a line, taking the third square can block their win."),
            rule_section(:ending, "The result",
              "The game ends as soon as either player makes a line of three. If the grid fills without a winning line, it is a draw."),
            rule_section(:controls, "Keyboard shortcuts",
              "Arrows: explore the grid.",
              "Enter: mark the selected empty square.",
              "T: read whose turn it is.")
          ]
        when "es"
          [
            rule_section(:aim, "Objetivo",
              "Tres en raya es un juego para dos personas en un tablero de tres filas y tres columnas. Debes colocar tres s\u00EDmbolos tuyos en una misma fila, columna o diagonal."),
            rule_section(:play, "C\u00F3mo jugar",
              "El primer jugador usa cruces y empieza. El segundo usa c\u00EDrculos. En cada turno colocas tu s\u00EDmbolo en una casilla vac\u00EDa y despu\u00E9s juega el rival.",
              "Elige la casilla con las flechas y pulsa Enter. Los s\u00EDmbolos colocados no se mueven. Si el rival ya tiene dos en una l\u00EDnea, puedes ocupar la tercera casilla para impedir su victoria."),
            rule_section(:ending, "Victoria y empate",
              "La partida termina en cuanto alguien forma una l\u00EDnea con tres s\u00EDmbolos propios. Si se llena el tablero sin conseguirlo, hay empate."),
            rule_section(:controls, "Teclas de referencia",
              "Flechas: recorrer las casillas.",
              "Enter: colocar tu s\u00EDmbolo en la casilla vac\u00EDa elegida.",
              "T: consultar de qui\u00E9n es el turno.")
          ]
        when "pl"
          [
            rule_section(:aim, "Cel gry",
              "K\u00F3\u0142ko i krzy\u017Cyk to gra dla dw\u00F3ch os\u00F3b na dziewi\u0119ciu polach u\u0142o\u017Conych w trzy rz\u0119dy i trzy kolumny. Wygrywasz, gdy ustawisz trzy swoje znaki w jednym rz\u0119dzie, jednej kolumnie albo na przek\u0105tnej."),
            rule_section(:play, "Przebieg gry",
              "Pierwszy gracz stawia krzy\u017Cyki i zaczyna parti\u0119. Drugi stawia k\u00F3\u0142ka. W ka\u017Cdej turze zajmujesz jedno puste pole swoim znakiem, a potem ruch wykonuje przeciwnik.",
              "Wybierz pole strza\u0142kami i naci\u015Bnij Enter, \u017Ceby postawi\u0107 znak. Postawionych znak\u00F3w nie mo\u017Cna przesuwa\u0107. Je\u015Bli przeciwnik ma ju\u017C dwa znaki w jednej linii, mo\u017Cesz zaj\u0105\u0107 trzecie pole, \u017Ceby nie pozwoli\u0107 mu wygra\u0107."),
            rule_section(:ending, "Zwyci\u0119stwo i remis",
              "Partia ko\u0144czy si\u0119 od razu, gdy kto\u015B u\u0142o\u017Cy trzy swoje znaki w linii. Je\u015Bli wszystkie pola zostan\u0105 zaj\u0119te i nikomu si\u0119 to nie uda, jest remis."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "Strza\u0142ki: przegl\u0105daj pola planszy.",
              "Enter: postaw sw\u00F3j znak na wybranym pustym polu.",
              "T: odczytaj, czyja jest tura.")
          ]
        when "ru"
          [
            rule_section(:aim, "\u0426\u0435\u043B\u044C \u0438\u0433\u0440\u044B",
              "\u0412 \u043A\u0440\u0435\u0441\u0442\u0438\u043A\u0438-\u043D\u043E\u043B\u0438\u043A\u0438 \u0438\u0433\u0440\u0430\u044E\u0442 \u0432\u0434\u0432\u043E\u0451\u043C \u043D\u0430 \u043F\u043E\u043B\u0435 \u0438\u0437 \u0442\u0440\u0451\u0445 \u0440\u044F\u0434\u043E\u0432 \u0438 \u0442\u0440\u0451\u0445 \u0441\u0442\u043E\u043B\u0431\u0446\u043E\u0432 \u2014 \u0432\u0441\u0435\u0433\u043E \u0434\u0435\u0432\u044F\u0442\u044C \u043A\u043B\u0435\u0442\u043E\u043A. \u041D\u0443\u0436\u043D\u043E \u0440\u0430\u043D\u044C\u0448\u0435 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u0430 \u0441\u043E\u0431\u0440\u0430\u0442\u044C \u0442\u0440\u0438 \u0441\u0432\u043E\u0438\u0445 \u0437\u043D\u0430\u043A\u0430 \u043F\u043E\u0434\u0440\u044F\u0434 \u043F\u043E \u0433\u043E\u0440\u0438\u0437\u043E\u043D\u0442\u0430\u043B\u0438, \u0432\u0435\u0440\u0442\u0438\u043A\u0430\u043B\u0438 \u0438\u043B\u0438 \u0434\u0438\u0430\u0433\u043E\u043D\u0430\u043B\u0438."),
            rule_section(:play, "\u041A\u0430\u043A \u0438\u0433\u0440\u0430\u0442\u044C",
              "\u041F\u0435\u0440\u0432\u044B\u0439 \u0438\u0433\u0440\u043E\u043A \u0441\u0442\u0430\u0432\u0438\u0442 \u043A\u0440\u0435\u0441\u0442\u0438\u043A\u0438 \u0438 \u0445\u043E\u0434\u0438\u0442 \u043F\u0435\u0440\u0432\u044B\u043C, \u0432\u0442\u043E\u0440\u043E\u0439 \u0441\u0442\u0430\u0432\u0438\u0442 \u043D\u043E\u043B\u0438\u043A\u0438. \u041F\u043E \u043E\u0447\u0435\u0440\u0435\u0434\u0438 \u0437\u0430\u043D\u0438\u043C\u0430\u0439\u0442\u0435 \u043F\u043E \u043E\u0434\u043D\u043E\u0439 \u0441\u0432\u043E\u0431\u043E\u0434\u043D\u043E\u0439 \u043A\u043B\u0435\u0442\u043A\u0435 \u0441\u0432\u043E\u0438\u043C \u0437\u043D\u0430\u043A\u043E\u043C.",
              "\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u043A\u043B\u0435\u0442\u043A\u0443 \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0438 \u043D\u0430\u0436\u043C\u0438\u0442\u0435 Enter. \u0423\u0436\u0435 \u043F\u043E\u0441\u0442\u0430\u0432\u043B\u0435\u043D\u043D\u044B\u0439 \u0437\u043D\u0430\u043A \u043F\u0435\u0440\u0435\u043C\u0435\u0441\u0442\u0438\u0442\u044C \u043D\u0435\u043B\u044C\u0437\u044F. \u0421\u043B\u0435\u0434\u0438\u0442\u0435 \u0438 \u0437\u0430 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u043E\u043C: \u0435\u0441\u043B\u0438 \u0434\u0432\u0430 \u0435\u0433\u043E \u0437\u043D\u0430\u043A\u0430 \u0441\u0442\u043E\u044F\u0442 \u0432 \u043E\u0434\u043D\u043E\u043C \u0440\u044F\u0434\u0443, \u043C\u043E\u0436\u043D\u043E \u0437\u0430\u043D\u044F\u0442\u044C \u0442\u0440\u0435\u0442\u044C\u044E \u043A\u043B\u0435\u0442\u043A\u0443 \u0438 \u043D\u0435 \u0434\u0430\u0442\u044C \u0435\u043C\u0443 \u0432\u044B\u0438\u0433\u0440\u0430\u0442\u044C."),
            rule_section(:ending, "\u041F\u043E\u0431\u0435\u0434\u0430 \u0438 \u043D\u0438\u0447\u044C\u044F",
              "\u0422\u0440\u0438 \u043E\u0434\u0438\u043D\u0430\u043A\u043E\u0432\u044B\u0445 \u0437\u043D\u0430\u043A\u0430 \u0432 \u043E\u0434\u043D\u043E\u0439 \u043B\u0438\u043D\u0438\u0438 \u043D\u0435\u043C\u0435\u0434\u043B\u0435\u043D\u043D\u043E \u0437\u0430\u043A\u0430\u043D\u0447\u0438\u0432\u0430\u044E\u0442 \u043F\u0430\u0440\u0442\u0438\u044E \u043F\u043E\u0431\u0435\u0434\u043E\u0439 \u0438\u0445 \u0432\u043B\u0430\u0434\u0435\u043B\u044C\u0446\u0430. \u0415\u0441\u043B\u0438 \u0432\u0441\u0435 \u043A\u043B\u0435\u0442\u043A\u0438 \u0437\u0430\u043D\u044F\u0442\u044B, \u0430 \u043D\u0443\u0436\u043D\u043E\u0439 \u043B\u0438\u043D\u0438\u0438 \u043D\u0435\u0442 \u043D\u0438 \u0443 \u043A\u043E\u0433\u043E, \u043E\u0431\u044A\u044F\u0432\u043B\u044F\u0435\u0442\u0441\u044F \u043D\u0438\u0447\u044C\u044F."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0448\u0438 \u0443\u043F\u0440\u0430\u0432\u043B\u0435\u043D\u0438\u044F",
              "\u0421\u0442\u0440\u0435\u043B\u043A\u0438: \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u0442\u044C \u043A\u043B\u0435\u0442\u043A\u0438 \u043F\u043E\u043B\u044F.",
              "Enter: \u043F\u043E\u0441\u0442\u0430\u0432\u0438\u0442\u044C \u0441\u0432\u043E\u0439 \u0437\u043D\u0430\u043A \u0432 \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u0443\u044E \u0441\u0432\u043E\u0431\u043E\u0434\u043D\u0443\u044E \u043A\u043B\u0435\u0442\u043A\u0443.",
              "T: \u0443\u0437\u043D\u0430\u0442\u044C, \u0447\u0435\u0439 \u0441\u0435\u0439\u0447\u0430\u0441 \u0445\u043E\u0434.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
