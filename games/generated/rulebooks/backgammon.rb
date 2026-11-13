# Generated from tools/data/rulebooks/backgammon.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Backgammon
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:play, GameRoomRules.translate("Backgammon"),
            GameRoomRules.translate("In the classic game you have fifteen checkers. Nackgammon changes their starting positions and Hypergammon uses three checkers per player. Move towards point 1. Each die gives a separate move. Doubles give four moves."),
            GameRoomRules.translate("A point with two or more opposing checkers is blocked. You can hit a lone opposing checker. Re-enter any checkers on the bar before moving others. Once all your checkers are in your home board, points 1 through 6, you may bear them off. The first to remove all their checkers wins.")),
          rule_section(:controls, GameRoomRules.translate("Keyboard"),
            GameRoomRules.translate("Press Enter to roll or confirm the selected move. Use the arrows to select a move. Press V to inspect the board."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:play, "Vrhc\u00E1by",
              "V klasick\u00E9 h\u0159e m\u00E1te patn\u00E1ct kamen\u016F. Nackgammon m\u011Bn\u00ED jejich v\u00FDchoz\u00ED rozlo\u017Een\u00ED a v Hypergammonu m\u00E1te t\u0159i kameny. Postupujte k bodu 1. Ka\u017Ed\u00E1 kostka ur\u010Duje jeden pohyb. Dvojice stejn\u00FDch hodnot d\u00E1v\u00E1 \u010Dty\u0159i pohyby.",
              "Na bod se dv\u011Bma nebo v\u00EDce soupe\u0159ov\u00FDmi kameny nesm\u00EDte vstoupit. Osamocen\u00FD soupe\u0159\u016Fv k\u00E1men m\u016F\u017Eete vyhodit. Nejprve vra\u0165te do hry sv\u00E9 vyhozen\u00E9 kameny. A\u017E budete m\u00EDt v\u0161echny v dom\u00E1c\u00ED \u010Dtvrtin\u011B na bodech 1 a\u017E 6, m\u016F\u017Eete je vyv\u00E1d\u011Bt. Vyhraje hr\u00E1\u010D, kter\u00FD vyvede v\u0161echny jako prvn\u00ED."),
            rule_section(:controls, "Ovl\u00E1d\u00E1n\u00ED",
              "Enter h\u00E1z\u00ED nebo potvrzuje vybran\u00FD tah. Tah vyberte \u0161ipkami. Kl\u00E1vesa V otev\u0159e p\u0159ehled desky.")
          ]
        when "en"
          [
            rule_section(:play, "Backgammon",
              "In the classic game you have fifteen checkers. Nackgammon changes their starting positions and Hypergammon uses three checkers per player. Move towards point 1. Each die gives a separate move. Doubles give four moves.",
              "A point with two or more opposing checkers is blocked. You can hit a lone opposing checker. Re-enter any checkers on the bar before moving others. Once all your checkers are in your home board, points 1 through 6, you may bear them off. The first to remove all their checkers wins."),
            rule_section(:controls, "Keyboard",
              "Press Enter to roll or confirm the selected move. Use the arrows to select a move. Press V to inspect the board.")
          ]
        when "es"
          [
            rule_section(:play, "Backgammon",
              "En la modalidad cl\u00E1sica tienes quince fichas. Nackgammon cambia su posici\u00F3n inicial y Hypergammon se juega con tres por persona. Avanza hacia el punto 1. Cada dado indica un movimiento. Si salen dobles, puedes hacer cuatro movimientos.",
              "Un punto ocupado por dos o m\u00E1s fichas rivales est\u00E1 bloqueado. Puedes capturar una ficha rival que est\u00E9 sola. Antes de mover otras fichas, vuelve a introducir las que tengas en la barra. Cuando todas est\u00E9n en tu cuadrante interior, del punto 1 al 6, puedes retirarlas. Gana quien retire primero todas sus fichas."),
            rule_section(:controls, "Teclado",
              "Pulsa Intro para tirar o confirmar el movimiento elegido. Elige con las flechas. Pulsa V para consultar el tablero.")
          ]
        when "pl"
          [
            rule_section(:play, "Tryktrak",
              "Gracie we dwoje. Wygrywa osoba, kt\u00F3ra pierwsza zdejmie wszystkie swoje pionki. Plansza ma 24 pola. Ka\u017Cdy gracz liczy je od w\u0142asnego domu. Twoje pole 24 to pole 1 przeciwnika. Przesuwasz pionki od wy\u017Cszych numer\u00F3w ku ni\u017Cszym, a tw\u00F3j dom obejmuje pola od 1 do 6.",
              "Na pocz\u0105tku gra losuje po jednej ko\u015Bci dla ka\u017Cdego gracza. Przy remisie rzut si\u0119 powtarza. Wy\u017Cszy wynik daje pierwsz\u0105 tur\u0119, w kt\u00F3rej zwyci\u0119zca u\u017Cywa obu wylosowanych warto\u015Bci. W nast\u0119pnych turach gracz rzuca dwiema ko\u015B\u0107mi. Ka\u017Cda ko\u015B\u0107 daje osobny ruch. Przy dublecie mo\u017Cesz u\u017Cy\u0107 tej samej warto\u015Bci cztery razy.",
              "Mo\u017Cesz przesun\u0105\u0107 dwa r\u00F3\u017Cne pionki albo ten sam pionek dwa razy. Przy rzucie 5 i 3 ruch o osiem p\u00F3l sk\u0142ada si\u0119 z dw\u00F3ch krok\u00F3w. Pole po pierwszym kroku musi by\u0107 dost\u0119pne. Gra pokazuje tylko ruchy, kt\u00F3re pozwalaj\u0105 wykorzysta\u0107 mo\u017Cliwie najwi\u0119cej ko\u015Bci. Gdy z dw\u00F3ch r\u00F3\u017Cnych ko\u015Bci mo\u017Cesz u\u017Cy\u0107 tylko jednej i obie daj\u0105 jaki\u015B ruch, musisz u\u017Cy\u0107 wy\u017Cszej.",
              "Dwa lub wi\u0119cej pionk\u00F3w przeciwnika zamykaj\u0105 pole. Je\u015Bli wyl\u0105dujesz na samotnym pionku przeciwnika, zbijasz go na band\u0119. W swojej turze najpierw wprowadzasz zbite pionki do domu przeciwnika. Na przyk\u0142ad ko\u015B\u0107 3 pozwala wej\u015B\u0107 na twoje pole 22, je\u015Bli jest dost\u0119pne. Je\u015Bli ko\u015Bci nie pozwalaj\u0105 na \u017Caden ruch, kolej przechodzi na przeciwnika.",
              "Gdy wszystkie twoje pionki pozostaj\u0105ce na planszy s\u0105 w domu, mo\u017Cesz je zdejmowa\u0107. Ko\u015B\u0107 4 zdejmuje pionek z pola 4. Gdy na polu 4 i na wszystkich wy\u017Cszych polach nie masz pionk\u00F3w, mo\u017Cesz u\u017Cy\u0107 tej ko\u015Bci do zdj\u0119cia pionka z najwy\u017Cszego zaj\u0119tego pola poni\u017Cej 4.",
              "Zwyci\u0119zca dostaje 1 punkt, je\u015Bli przeciwnik zdj\u0105\u0142 co najmniej jeden pionek. Gdy przeciwnik nie zdj\u0105\u0142 \u017Cadnego, zwyci\u0119zca dostaje 2 punkty. Dostaje 3, je\u015Bli przeciwnik dodatkowo ma pionek na bandzie lub w domu zwyci\u0119zcy."),
            rule_section(:variants, "Warianty",
              "- Klasyczny. Ka\u017Cdy zaczyna z 15 pionkami. Dwa stoj\u0105 na polu 24, pi\u0119\u0107 na 13, trzy na 8 i pi\u0119\u0107 na 6.",
              "- Nackgammon. Po dwa pionki stoj\u0105 na polach 24 i 23, po cztery na 13 i 6, a trzy na 8.",
              "- Hypergammon. Ka\u017Cdy zaczyna z trzema pionkami, po jednym na polach 24, 23 i 22.",
              "- LongGammon. Wszystkie 15 pionk\u00F3w zaczyna na polu 24. Obowi\u0105zuj\u0105 zwyk\u0142e zasady bicia i ruchu.",
              "- Regu\u0142a egipska. Pionki startuj\u0105 jak w klasycznym Tryktraku. Na jednym polu planszy mo\u017Ce sta\u0107 najwy\u017Cej pi\u0119\u0107 twoich pionk\u00F3w. Limit nie dotyczy bandy ani pionk\u00F3w zdj\u0119tych z planszy."),
            rule_section(:match, "Mecz i kostka dubluj\u0105ca",
              "Ustaw cel punktowy przy tworzeniu sto\u0142u. Zero oznacza jedn\u0105 parti\u0119. W meczu punkty z kolejnych partii sumuj\u0105 si\u0119, a wygrywa pierwszy gracz, kt\u00F3ry osi\u0105gnie cel. S odczytuje wynik.",
              "Je\u015Bli w\u0142\u0105czysz kostk\u0119 dubluj\u0105c\u0105, ka\u017Cda partia zaczyna si\u0119 od stawki 1. Przed rzutem w swojej turze wybierz strza\u0142kami propozycj\u0119 podwojenia i zatwierd\u017A Enterem. Przeciwnik wybiera przyj\u0119cie albo odrzucenie. Po przyj\u0119ciu stawka ro\u015Bnie dwukrotnie, a kolejny dubel mo\u017Ce zaproponowa\u0107 tylko przyjmuj\u0105cy. Maksymalna stawka wynosi 64.",
              "Po odmowie oferuj\u0105cy wygrywa parti\u0119 za stawk\u0119 sprzed propozycji. Po zdj\u0119ciu wszystkich pionk\u00F3w punkty bazowe od 1 do 3 mno\u017Cy si\u0119 przez aktualn\u0105 stawk\u0119. Gdy po raz pierwszy komu\u015B brakuje jednego punktu do wygrania meczu, w nast\u0119pnej partii obowi\u0105zuje regu\u0142a Crawforda i podwajanie jest wy\u0142\u0105czone."),
            rule_section(:controls, "Klawiatura",
              "Enter rzuca ko\u015B\u0107mi. Po rzucie plansza podaje ko\u015Bci do wykorzystania. Strza\u0142kami znajd\u017A pionek i wybierz jego pole Enterem. Przejd\u017A na pole docelowe i potwierd\u017A Enterem. Escape cofa wyb\u00F3r pionka. V otwiera podgl\u0105d planszy.",
              "- D odczytuje ko\u015Bci pozosta\u0142e do wykorzystania w bie\u017C\u0105cej turze.",
              "W podgl\u0105dzie pod V pola s\u0105 liczone z twojej strony. G\u00F3rny rz\u0105d biegnie od 24 do 13, dolny od 1 do 12, w obu od lewej do prawej. Strza\u0142ki w lewo i w prawo zmieniaj\u0105 pole w rz\u0119dzie. Strza\u0142ki w g\u00F3r\u0119 i w d\u00F3\u0142 przechodz\u0105 na pole naprzeciwko. Nag\u0142\u00F3wek podaje liczb\u0119 pionk\u00F3w na bandzie i zdj\u0119tych z planszy.",
              "Na lewo od pola 24 jest banda, a na lewo od pola 1 s\u0105 zdj\u0119te pionki. Gdy masz pionek na bandzie, przejd\u017A od razu na pole wej\u015Bcia i naci\u015Bnij Enter. Aby zdj\u0105\u0107 pionek, wybierz go Enterem, a potem naci\u015Bnij Enter na polu zdj\u0119tych pionk\u00F3w. Je\u015Bli jedynym legalnym ruchem tego pionka jest zej\u015Bcie z planszy, wystarczy nacisn\u0105\u0107 Enter dwa razy na jego polu. Je\u015Bli obie ko\u015Bci pozwalaj\u0105 na to samo zej\u015Bcie, gra u\u017Cyje wy\u017Cszej legalnej warto\u015Bci.",
              "Po rzucie gra og\u0142asza oczka. Przy rzucie otwieraj\u0105cym podaje wynik ka\u017Cdego gracza. Po ruchu og\u0142asza gracza, pole startowe i docelowe oraz ewentualne zbicie. B odczytuje liczb\u0119 pionk\u00F3w na bandzie, a Z liczb\u0119 zdj\u0119tych pionk\u00F3w obu graczy.")
          ]
        when "ru"
          [
            rule_section(:play, "\u041D\u0430\u0440\u0434\u044B",
              "\u0412 \u043A\u043B\u0430\u0441\u0441\u0438\u0447\u0435\u0441\u043A\u043E\u043C \u0432\u0430\u0440\u0438\u0430\u043D\u0442\u0435 \u0443 \u043A\u0430\u0436\u0434\u043E\u0433\u043E \u043F\u044F\u0442\u043D\u0430\u0434\u0446\u0430\u0442\u044C \u0448\u0430\u0448\u0435\u043A. \u0412 \u043D\u0430\u043A\u0433\u0430\u043C\u043C\u043E\u043D\u0435 \u043C\u0435\u043D\u044F\u0435\u0442\u0441\u044F \u043D\u0430\u0447\u0430\u043B\u044C\u043D\u0430\u044F \u0440\u0430\u0441\u0441\u0442\u0430\u043D\u043E\u0432\u043A\u0430, \u0430 \u0432 \u0433\u0438\u043F\u0435\u0440\u0433\u0430\u043C\u043C\u043E\u043D\u0435 \u0443 \u043A\u0430\u0436\u0434\u043E\u0433\u043E \u0442\u0440\u0438 \u0448\u0430\u0448\u043A\u0438. \u0414\u0432\u0438\u0433\u0430\u0439\u0442\u0435\u0441\u044C \u043A \u043F\u0443\u043D\u043A\u0442\u0443 1. \u041A\u0430\u0436\u0434\u044B\u0439 \u043A\u0443\u0431\u0438\u043A \u0437\u0430\u0434\u0430\u0451\u0442 \u043E\u0442\u0434\u0435\u043B\u044C\u043D\u044B\u0439 \u0445\u043E\u0434. \u0414\u0443\u0431\u043B\u044C \u0434\u0430\u0451\u0442 \u0447\u0435\u0442\u044B\u0440\u0435 \u0445\u043E\u0434\u0430.",
              "\u041F\u0443\u043D\u043A\u0442 \u0441 \u0434\u0432\u0443\u043C\u044F \u0438\u043B\u0438 \u0431\u043E\u043B\u0435\u0435 \u0448\u0430\u0448\u043A\u0430\u043C\u0438 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u0430 \u0437\u0430\u043A\u0440\u044B\u0442. \u041E\u0434\u0438\u043D\u043E\u0447\u043D\u0443\u044E \u0448\u0430\u0448\u043A\u0443 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u0430 \u043C\u043E\u0436\u043D\u043E \u043F\u043E\u0431\u0438\u0442\u044C. \u0421\u043D\u0430\u0447\u0430\u043B\u0430 \u0432\u0435\u0440\u043D\u0438\u0442\u0435 \u043D\u0430 \u0434\u043E\u0441\u043A\u0443 \u0441\u0432\u043E\u0438 \u043F\u043E\u0431\u0438\u0442\u044B\u0435 \u0448\u0430\u0448\u043A\u0438. \u041A\u043E\u0433\u0434\u0430 \u0432\u0441\u0435 \u043E\u043D\u0438 \u043E\u043A\u0430\u0436\u0443\u0442\u0441\u044F \u0432 \u0434\u043E\u043C\u0435, \u043D\u0430 \u043F\u0443\u043D\u043A\u0442\u0430\u0445 \u0441 1 \u043F\u043E 6, \u043D\u0430\u0447\u0438\u043D\u0430\u0439\u0442\u0435 \u0438\u0445 \u0441\u043D\u0438\u043C\u0430\u0442\u044C. \u041F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u0442\u043E\u0442, \u043A\u0442\u043E \u043F\u0435\u0440\u0432\u044B\u043C \u0441\u043D\u0438\u043C\u0435\u0442 \u0432\u0441\u0435 \u0441\u0432\u043E\u0438 \u0448\u0430\u0448\u043A\u0438."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0430\u0442\u0443\u0440\u0430",
              "Enter \u0431\u0440\u043E\u0441\u0430\u0435\u0442 \u043A\u0443\u0431\u0438\u043A\u0438 \u0438\u043B\u0438 \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0430\u0435\u0442 \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u044B\u0439 \u0445\u043E\u0434. \u0425\u043E\u0434 \u0432\u044B\u0431\u0438\u0440\u0430\u044E\u0442 \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438. \u041A\u043B\u0430\u0432\u0438\u0448\u0430 V \u043E\u0442\u043A\u0440\u044B\u0432\u0430\u0435\u0442 \u043E\u0431\u0437\u043E\u0440 \u0434\u043E\u0441\u043A\u0438.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
