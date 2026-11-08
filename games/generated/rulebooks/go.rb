# Generated from tools/data/rulebooks/go.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Go
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:aim, GameRoomRules.translate("Go"),
            GameRoomRules.translate("Go originated in China and is also known as baduk and igo. Two players place black and white stones on intersections; Black starts. Orthogonally connected stones form a group. An adjacent empty intersection is a liberty. Fill every liberty to capture a group. Captures are removed before checking self-capture; suicide is forbidden.")),
          rule_section(:variants, GameRoomRules.translate("Variants and settings"),
            GameRoomRules.translate("Choose a 9 by 9, 13 by 13 or 19 by 19 board. Chinese-style area counts living stones plus surrounded empty points. Territory counts surrounded empty points plus captured and agreed dead opposing stones. White receives the selected komi. Atari Go ends at the first capture; two passes without a capture draw. All variants use positional superko: a placement may not recreate any earlier complete board position. Territory mode uses agreed dead groups and neutral seki regions, not automatic Japanese life-and-death adjudication. No automatic bent-four ruling or referee is implemented.")),
          rule_section(:scoring, GameRoomRules.translate("Ending and agreeing the score"),
            GameRoomRules.translate("Two consecutive passes enter scoring. Players alternate: select an occupied point to mark or unmark its whole group as dead. Select an empty point to mark or unmark its whole connected empty region as neutral, for seki or other agreed neutral territory. A change clears both approvals; changing a dead group also clears neutral marks. A accepts this exact proposal. Two approvals end the game. R resumes play with the stones still present and clears marks; the other player moves next. Only regions bordered by one colour score; shared or unbordered regions are neutral. In area mode living stones also count; in territory mode prisoners count instead. Higher score wins; equal scores draw. Q resigns.")),
          rule_section(:controls, GameRoomRules.translate("Controls"),
            GameRoomRules.translate("Use arrows to browse intersections and Enter to place or mark. P passes; A accepts scoring; R resumes play; Q resigns; S reads provisional or final points. T reads the current turn. Bots use a basic capture and liberties strategy, then accept scoring. F1 lists current shortcuts; Ctrl+F1 opens these rules. Shared controls provide history, chat and volume."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:aim, "Deska a tahy",
              "Obkli\u010Duj pr\u00E1zdn\u00E1 m\u00EDsta a udr\u017E na desce sv\u00E9 kameny, abys z\u00EDskal v\u00EDc bod\u016F ne\u017E soupe\u0159. Go hraj\u00ED dva hr\u00E1\u010Di na pr\u00E1zdn\u00E9 desce. Za\u010D\u00EDn\u00E1 \u010Dern\u00FD a pak se hr\u00E1\u010Di st\u0159\u00EDdaj\u00ED v pokl\u00E1d\u00E1n\u00ED kamen\u016F. \u0160ipkami naje\u010F na voln\u00FD pr\u016Fse\u010D\u00EDk a stiskni Enter. Sloupce maj\u00ED p\u00EDsmena zleva, \u0159ady \u010D\u00EDsla zdola.",
              "Stejn\u011B barevn\u00E9 kameny spojen\u00E9 pod\u00E9l \u010Dar tvo\u0159\u00ED skupinu. Voln\u00E9 sousedn\u00ED pr\u016Fse\u010D\u00EDky jsou jej\u00ED svobody. Obsazen\u00EDm posledn\u00ED svobody soupe\u0159ovu skupinu zajme\u0161. Po odebr\u00E1n\u00ED zajat\u00FDch kamen\u016F mus\u00ED m\u00EDt tvoje skupina alespo\u0148 jednu svobodu. Nesm\u00ED\u0161 tak\u00E9 obnovit d\u0159\u00EDv\u011Bj\u0161\u00ED postaven\u00ED cel\u00E9 desky."),
            rule_section(:scoring, "Vynech\u00E1n\u00ED tahu a po\u010D\u00EDt\u00E1n\u00ED",
              "M\u00EDsto polo\u017Een\u00ED kamene m\u016F\u017Ee\u0161 stisknout P. Kdy\u017E oba hr\u00E1\u010Di po sob\u011B vynechaj\u00ED tah, po\u010D\u00EDt\u00E1 se v\u00FDsledek. Enter na kameni ozna\u010D\u00ED celou skupinu jako mrtvou nebo toto ozna\u010Den\u00ED zru\u0161\u00ED. Na pr\u00E1zdn\u00E9m pr\u016Fse\u010D\u00EDku p\u0159epne neutralitu cel\u00E9 spojen\u00E9 oblasti.",
              "Kl\u00E1vesa S p\u0159e\u010Dte navr\u017Een\u00FD v\u00FDsledek, A ho potvrd\u00ED. Ka\u017Ed\u00E1 zm\u011Bna ru\u0161\u00ED oba souhlasy; zm\u011Bna mrtv\u00E9 skupiny nav\u00EDc ru\u0161\u00ED neutr\u00E1ln\u00ED ozna\u010Den\u00ED. Chce\u0161-li pokra\u010Dovat, stiskni R. Kameny z\u016Fstanou na desce, ozna\u010Den\u00ED zmiz\u00ED a hraje soupe\u0159.",
              "Ve v\u00FDchoz\u00EDm po\u010D\u00EDt\u00E1n\u00ED m\u00E1\u0161 bod za ka\u017Ed\u00FD sv\u016Fj \u017Eiv\u00FD k\u00E1men i za ka\u017Ed\u00FD pr\u00E1zdn\u00FD pr\u016Fse\u010D\u00EDk obklopen\u00FD jen tvoj\u00ED barvou. Neutr\u00E1ln\u00ED oblasti se nepo\u010D\u00EDtaj\u00ED. B\u00EDl\u00FD dost\u00E1v\u00E1 vyrovn\u00E1n\u00ED, kter\u00E9mu se \u0159\u00EDk\u00E1 komi. Jakmile oba hr\u00E1\u010Di schv\u00E1l\u00ED v\u00FDsledek, vyhr\u00E1v\u00E1 vy\u0161\u0161\u00ED sk\u00F3re. Shoda je rem\u00EDza."),
            rule_section(:variants, "Velikost desky a varianty",
              "P\u0159i vytv\u00E1\u0159en\u00ED stolu vybere\u0161 desku 9\u00D79, 13\u00D713 \u010Di 19\u00D719 a hodnotu komi.",
              "- Po\u010D\u00EDt\u00E1n\u00ED \u00FAzem\u00ED: m\u00EDsto \u017Eiv\u00FDch kamen\u016F po\u010D\u00EDtej zajat\u00E9 kameny a soupe\u0159ovy skupiny uznan\u00E9 za mrtv\u00E9. Obklopen\u00E9 pr\u00E1zdn\u00E9 pr\u016Fse\u010D\u00EDky se po\u010D\u00EDtaj\u00ED d\u00E1l.",
              "- Atari Go: vyhr\u00E1v\u00E1 prvn\u00ED zajet\u00ED. Dv\u011B vynech\u00E1n\u00ED bez zajet\u00ED znamenaj\u00ED rem\u00EDzu. S p\u0159e\u010Dte po\u010Det zajat\u00FDch kamen\u016F."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "\u0160ipky: proch\u00E1zet pr\u016Fse\u010D\u00EDky",
              "Enter: polo\u017Eit k\u00E1men nebo zm\u011Bnit ozna\u010Den\u00ED",
              "P: vynechat tah",
              "S: p\u0159e\u010D\u00EDst v\u00FDsledek nebo po\u010Det zajat\u00FDch kamen\u016F v Atari Go",
              "A: potvrdit v\u00FDsledek",
              "R: pokra\u010Dovat ve h\u0159e po vynech\u00E1n\u00ED",
              "Q: vzd\u00E1t partii")
          ]
        when "en"
          [
            rule_section(:aim, "Board and moves",
              "Surround empty areas and keep your own stones on the board to outscore your opponent. Go is played by two people on an empty board. Black goes first, and players take turns placing one stone. Move to an empty intersection with the arrows and press Enter. Columns are lettered from the left and rows numbered from the bottom.",
              "Stones of the same colour joined along the lines form a group. Empty intersections next to a group are its liberties. Filling the last liberty takes the whole opposing group off the board. You cannot leave your own group with no liberties after removing any captures, or recreate an earlier board position."),
            rule_section(:scoring, "Passing and scoring",
              "Press P instead of placing a stone to pass. Two passes in a row start scoring. Press Enter on a stone to mark its whole group dead or restore it. Enter on an empty intersection toggles whether its connected area is neutral.",
              "Press S to hear the proposed score and A to accept it. A change cancels both approvals, and changing a dead group also clears neutral markings. Press R to resume with the same stones, clear the markings and give the other player the next move.",
              "In the default game, each living stone of your colour and each empty intersection surrounded by your colour alone is worth one point. Neutral areas do not score. White gets a compensation called komi. Once both players agree, the higher score wins; equal scores draw."),
            rule_section(:variants, "Board size and variants",
              "When creating the table, choose 9\u00D79, 13\u00D713 or 19\u00D719 and set the komi.",
              "- Territory scoring: count captured stones and agreed dead enemy stones instead of living stones. You still count surrounded empty intersections.",
              "- Atari Go: the first capture wins. Two passes without a capture draw. S reads captures rather than a territory score."),
            rule_section(:controls, "Keyboard shortcuts",
              "Arrows: move through the intersections",
              "Enter: place a stone or change a scoring mark",
              "P: pass",
              "S: read the proposed score or Atari captures",
              "A: accept the score",
              "R: resume play after passing",
              "Q: resign")
          ]
        when "es"
          [
            rule_section(:aim, "Tablero y jugadas",
              "Rodea zonas vac\u00EDas y conserva tus piedras en el tablero para sumar m\u00E1s puntos que tu rival. El go se juega entre dos personas y empieza con el tablero vac\u00EDo. Juegan primero las negras; despu\u00E9s se coloca una piedra por turno. Mu\u00E9vete con las flechas a una intersecci\u00F3n libre y pulsa Intro. Las columnas llevan letras desde la izquierda y las filas se numeran desde abajo.",
              "Las piedras del mismo color unidas por las l\u00EDneas forman un grupo. Las intersecciones libres a su lado son sus libertades. Si ocupas la \u00FAltima libertad de un grupo rival, lo retiras entero. Despu\u00E9s de retirar las capturas, tu grupo debe tener alguna libertad. Tampoco puedes repetir una posici\u00F3n anterior del tablero."),
            rule_section(:scoring, "Pasar y contar los puntos",
              "Pulsa P si prefieres pasar. Dos pases seguidos abren el recuento. Intro sobre una piedra marca todo el grupo como muerto o lo recupera. En un cruce vac\u00EDo, cambia entre contar y no contar toda la regi\u00F3n conectada.",
              "Pulsa S para escuchar el resultado propuesto y A para aceptarlo. Cualquier cambio anula las dos aprobaciones; cambiar un grupo muerto tambi\u00E9n quita las marcas de regiones neutrales. R reanuda la partida: las piedras se quedan, las marcas se quitan y juega la otra persona.",
              "En el recuento inicial, cada piedra viva de tu color y cada cruce vac\u00EDo rodeado solo por tu color vale un punto. Las regiones neutrales no punt\u00FAan. Las blancas reciben una compensaci\u00F3n llamada komi. Cuando ambos aceptan el resultado, gana la mayor puntuaci\u00F3n. A igualdad, empate."),
            rule_section(:variants, "Tama\u00F1o del tablero y variantes",
              "Al crear la mesa puedes elegir un tablero de 9\u00D79, 13\u00D713 o 19\u00D719 y ajustar el komi.",
              "- Recuento por territorio: en vez de piedras vivas, cuenta las capturas y las piedras rivales declaradas muertas. Los cruces vac\u00EDos rodeados tambi\u00E9n cuentan.",
              "- Atari go: gana la primera captura. Dos pases sin capturas empatan. S lee las capturas, no el territorio."),
            rule_section(:controls, "Atajos de teclado",
              "Flechas: recorrer las intersecciones",
              "Intro: colocar una piedra o cambiar una marca",
              "P: pasar",
              "S: leer el resultado propuesto o las capturas en Atari go",
              "A: aceptar el resultado",
              "R: reanudar despu\u00E9s de pasar",
              "Q: abandonar")
          ]
        when "pl"
          [
            rule_section(:aim, "Plansza i ruchy",
              "Otaczaj puste obszary i zachowuj na planszy w\u0142asne kamienie, \u017Ceby zdoby\u0107 wi\u0119cej punkt\u00F3w od przeciwnika. W Go graj\u0105 dwie osoby. Na pocz\u0105tku plansza jest pusta. Czarne zaczynaj\u0105, a potem gracze na zmian\u0119 k\u0142ad\u0105 po jednym kamieniu. Strza\u0142kami przejd\u017A na wolne przeci\u0119cie i naci\u015Bnij Enter. Kolumny s\u0105 oznaczone literami od lewej, a wiersze numerami od do\u0142u.",
              "Kamienie tego samego koloru po\u0142\u0105czone bokami tworz\u0105 grup\u0119. Ka\u017Cde wolne przeci\u0119cie obok grupy to oddech. Gdy zabierzesz grupie przeciwnika ostatni oddech, zdejmujesz j\u0105 z planszy. Nie mo\u017Cesz do\u0142o\u017Cy\u0107 kamienia, kt\u00F3ry po ewentualnym zbiciu pozostawi twoj\u0105 grup\u0119 bez oddechu. Nie wolno te\u017C odtwarza\u0107 wcze\u015Bniejszego uk\u0142adu planszy."),
            rule_section(:scoring, "Pas i liczenie punkt\u00F3w",
              "Je\u015Bli nie chcesz k\u0142a\u015B\u0107 kamienia, naci\u015Bnij P. Gdy obaj gracze spasuj\u0105 z rz\u0119du, przechodzicie do liczenia. Wybierz kamie\u0144 i naci\u015Bnij Enter, \u017Ceby oznaczy\u0107 ca\u0142\u0105 grup\u0119 jako martw\u0105 lub przywr\u00F3ci\u0107 jej status \u017Cywej. Enter na pustym przeci\u0119ciu zmienia status ca\u0142ego po\u0142\u0105czonego obszaru na neutralny lub z powrotem na liczony.",
              "Sprawd\u017A proponowany wynik klawiszem S. Zatwierd\u017A go klawiszem A, je\u015Bli si\u0119 zgadzasz. Po ka\u017Cdej zmianie oznacze\u0144 trzeba zatwierdzi\u0107 wynik ponownie; zmiana martwych grup kasuje te\u017C oznaczenia neutralnych obszar\u00F3w. Je\u015Bli chcecie dalej gra\u0107, naci\u015Bnij R. Kamienie zostaj\u0105 na planszy, oznaczenia znikaj\u0105, a ruch ma przeciwnik.",
              "W podstawowej odmianie dostajesz punkt za ka\u017Cdy sw\u00F3j \u017Cywy kamie\u0144 oraz za ka\u017Cde puste przeci\u0119cie w obszarze otoczonym wy\u0142\u0105cznie twoim kolorem. Obszary neutralne nie daj\u0105 punkt\u00F3w. Bia\u0142e maj\u0105 dodatkowe punkty, zwane komi. Gdy obie strony zatwierdz\u0105 wynik, wygrywa wy\u017Cszy; r\u00F3wne wyniki daj\u0105 remis."),
            rule_section(:variants, "Rozmiar planszy i odmiany",
              "Przy tworzeniu sto\u0142u mo\u017Cesz wybra\u0107 plansz\u0119 9 na 9, 13 na 13 albo 19 na 19 oraz wysoko\u015B\u0107 komi.",
              "- Liczenie terytorium: zamiast \u017Cywych kamieni liczysz zbite kamienie przeciwnika oraz jego grupy uznane za martwe. Nadal doliczasz otoczone puste przeci\u0119cia.",
              "- Atari Go: wygrywa pierwsze zbicie. Dwa pasy bez zbicia oznaczaj\u0105 remis; klawisz S podaje liczb\u0119 zbi\u0107 zamiast punkt\u00F3w."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "Strza\u0142ki: przegl\u0105daj przeci\u0119cia",
              "Enter: po\u0142\u00F3\u017C kamie\u0144 albo zmie\u0144 oznaczenie",
              "P: spasuj",
              "S: sprawd\u017A proponowany wynik lub zbicia w Atari Go",
              "A: zatwierd\u017A wynik",
              "R: wr\u00F3\u0107 do gry po pasach",
              "Q: poddaj parti\u0119")
          ]
        when "ru"
          [
            rule_section(:aim, "\u0414\u043E\u0441\u043A\u0430 \u0438 \u0445\u043E\u0434\u044B",
              "\u041E\u043A\u0440\u0443\u0436\u0430\u0439 \u043F\u0443\u0441\u0442\u044B\u0435 \u043E\u0431\u043B\u0430\u0441\u0442\u0438 \u0438 \u0441\u043E\u0445\u0440\u0430\u043D\u044F\u0439 \u0441\u0432\u043E\u0438 \u043A\u0430\u043C\u043D\u0438 \u043D\u0430 \u0434\u043E\u0441\u043A\u0435, \u0447\u0442\u043E\u0431\u044B \u043D\u0430\u0431\u0440\u0430\u0442\u044C \u0431\u043E\u043B\u044C\u0448\u0435 \u043E\u0447\u043A\u043E\u0432, \u0447\u0435\u043C \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A. \u0412 \u0433\u043E \u0438\u0433\u0440\u0430\u044E\u0442 \u0432\u0434\u0432\u043E\u0451\u043C. \u0421\u043D\u0430\u0447\u0430\u043B\u0430 \u0434\u043E\u0441\u043A\u0430 \u043F\u0443\u0441\u0442\u0430. \u0427\u0451\u0440\u043D\u044B\u0435 \u0445\u043E\u0434\u044F\u0442 \u043F\u0435\u0440\u0432\u044B\u043C\u0438, \u0437\u0430\u0442\u0435\u043C \u0438\u0433\u0440\u043E\u043A\u0438 \u0441\u0442\u0430\u0432\u044F\u0442 \u043F\u043E \u043E\u0434\u043D\u043E\u043C\u0443 \u043A\u0430\u043C\u043D\u044E \u043F\u043E \u043E\u0447\u0435\u0440\u0435\u0434\u0438. \u0412\u044B\u0431\u0435\u0440\u0438 \u0441\u0432\u043E\u0431\u043E\u0434\u043D\u043E\u0435 \u043F\u0435\u0440\u0435\u0441\u0435\u0447\u0435\u043D\u0438\u0435 \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0438 \u043D\u0430\u0436\u043C\u0438 Enter. \u0421\u0442\u043E\u043B\u0431\u0446\u044B \u043E\u0431\u043E\u0437\u043D\u0430\u0447\u0435\u043D\u044B \u0431\u0443\u043A\u0432\u0430\u043C\u0438 \u0441\u043B\u0435\u0432\u0430, \u0440\u044F\u0434\u044B \u2014 \u0447\u0438\u0441\u043B\u0430\u043C\u0438 \u0441\u043D\u0438\u0437\u0443.",
              "\u041A\u0430\u043C\u043D\u0438 \u043E\u0434\u043D\u043E\u0433\u043E \u0446\u0432\u0435\u0442\u0430, \u0441\u043E\u0435\u0434\u0438\u043D\u0451\u043D\u043D\u044B\u0435 \u043B\u0438\u043D\u0438\u044F\u043C\u0438, \u043E\u0431\u0440\u0430\u0437\u0443\u044E\u0442 \u0433\u0440\u0443\u043F\u043F\u0443. \u0421\u0432\u043E\u0431\u043E\u0434\u043D\u044B\u0435 \u0441\u043E\u0441\u0435\u0434\u043D\u0438\u0435 \u043F\u0435\u0440\u0435\u0441\u0435\u0447\u0435\u043D\u0438\u044F \u2014 \u0435\u0451 \u0434\u044B\u0445\u0430\u043D\u0438\u044F. \u0417\u0430\u0439\u043C\u0438 \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0435\u0435 \u0434\u044B\u0445\u0430\u043D\u0438\u0435 \u0433\u0440\u0443\u043F\u043F\u044B \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u0430, \u0447\u0442\u043E\u0431\u044B \u0441\u043D\u044F\u0442\u044C \u0435\u0451 \u0441 \u0434\u043E\u0441\u043A\u0438. \u041F\u043E\u0441\u043B\u0435 \u0441\u043D\u044F\u0442\u0438\u044F \u0437\u0430\u0445\u0432\u0430\u0447\u0435\u043D\u043D\u044B\u0445 \u043A\u0430\u043C\u043D\u0435\u0439 \u0443 \u0442\u0432\u043E\u0435\u0439 \u0433\u0440\u0443\u043F\u043F\u044B \u0434\u043E\u043B\u0436\u043D\u043E \u043E\u0441\u0442\u0430\u0442\u044C\u0441\u044F \u0445\u043E\u0442\u044F \u0431\u044B \u043E\u0434\u043D\u043E \u0434\u044B\u0445\u0430\u043D\u0438\u0435. \u041F\u043E\u0432\u0442\u043E\u0440\u044F\u0442\u044C \u043F\u0440\u0435\u0436\u043D\u044E\u044E \u043F\u043E\u0437\u0438\u0446\u0438\u044E \u043D\u0430 \u0432\u0441\u0435\u0439 \u0434\u043E\u0441\u043A\u0435 \u043D\u0435\u043B\u044C\u0437\u044F."),
            rule_section(:scoring, "\u041F\u0430\u0441 \u0438 \u043F\u043E\u0434\u0441\u0447\u0451\u0442 \u043E\u0447\u043A\u043E\u0432",
              "\u0427\u0442\u043E\u0431\u044B \u043F\u0440\u043E\u043F\u0443\u0441\u0442\u0438\u0442\u044C \u0445\u043E\u0434, \u043D\u0430\u0436\u043C\u0438 P. \u0414\u0432\u0430 \u043F\u0430\u0441\u0430 \u043F\u043E\u0434\u0440\u044F\u0434 \u043D\u0430\u0447\u0438\u043D\u0430\u044E\u0442 \u043F\u043E\u0434\u0441\u0447\u0451\u0442. \u041D\u0430\u0436\u043C\u0438 Enter \u043D\u0430 \u043A\u0430\u043C\u043D\u0435, \u0447\u0442\u043E\u0431\u044B \u043E\u0442\u043C\u0435\u0442\u0438\u0442\u044C \u0432\u0441\u044E \u0433\u0440\u0443\u043F\u043F\u0443 \u043A\u0430\u043A \u043C\u0451\u0440\u0442\u0432\u0443\u044E \u0438\u043B\u0438 \u043E\u0442\u043C\u0435\u043D\u0438\u0442\u044C \u043E\u0442\u043C\u0435\u0442\u043A\u0443. \u041D\u0430 \u043F\u0443\u0441\u0442\u043E\u043C \u043F\u0435\u0440\u0435\u0441\u0435\u0447\u0435\u043D\u0438\u0438 Enter \u043F\u0435\u0440\u0435\u043A\u043B\u044E\u0447\u0430\u0435\u0442 \u043D\u0435\u0439\u0442\u0440\u0430\u043B\u044C\u043D\u043E\u0441\u0442\u044C \u0432\u0441\u0435\u0439 \u0441\u0432\u044F\u0437\u0430\u043D\u043D\u043E\u0439 \u043E\u0431\u043B\u0430\u0441\u0442\u0438.",
              "\u041A\u043B\u0430\u0432\u0438\u0448\u0430 S \u0447\u0438\u0442\u0430\u0435\u0442 \u043F\u0440\u0435\u0434\u043B\u043E\u0436\u0435\u043D\u043D\u044B\u0439 \u0441\u0447\u0451\u0442, A \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0430\u0435\u0442 \u0435\u0433\u043E. \u041B\u044E\u0431\u043E\u0435 \u0438\u0437\u043C\u0435\u043D\u0435\u043D\u0438\u0435 \u043E\u0442\u043C\u0435\u043D\u044F\u0435\u0442 \u043E\u0431\u0430 \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0435\u043D\u0438\u044F, \u0430 \u0438\u0437\u043C\u0435\u043D\u0435\u043D\u0438\u0435 \u043C\u0451\u0440\u0442\u0432\u043E\u0439 \u0433\u0440\u0443\u043F\u043F\u044B \u0442\u0430\u043A\u0436\u0435 \u0441\u043D\u0438\u043C\u0430\u0435\u0442 \u043E\u0442\u043C\u0435\u0442\u043A\u0438 \u043D\u0435\u0439\u0442\u0440\u0430\u043B\u044C\u043D\u044B\u0445 \u043E\u0431\u043B\u0430\u0441\u0442\u0435\u0439. \u0427\u0442\u043E\u0431\u044B \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0438\u0442\u044C \u0438\u0433\u0440\u0443, \u043D\u0430\u0436\u043C\u0438 R: \u043A\u0430\u043C\u043D\u0438 \u043E\u0441\u0442\u0430\u043D\u0443\u0442\u0441\u044F \u043D\u0430 \u0434\u043E\u0441\u043A\u0435, \u043E\u0442\u043C\u0435\u0442\u043A\u0438 \u0438\u0441\u0447\u0435\u0437\u043D\u0443\u0442, \u0430 \u0445\u043E\u0434 \u043F\u0435\u0440\u0435\u0439\u0434\u0451\u0442 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u0443.",
              "\u041F\u043E \u0443\u043C\u043E\u043B\u0447\u0430\u043D\u0438\u044E \u043E\u0447\u043A\u043E \u0434\u0430\u0451\u0442 \u043A\u0430\u0436\u0434\u044B\u0439 \u0442\u0432\u043E\u0439 \u0436\u0438\u0432\u043E\u0439 \u043A\u0430\u043C\u0435\u043D\u044C \u0438 \u043A\u0430\u0436\u0434\u043E\u0435 \u043F\u0443\u0441\u0442\u043E\u0435 \u043F\u0435\u0440\u0435\u0441\u0435\u0447\u0435\u043D\u0438\u0435 \u0432 \u043E\u0431\u043B\u0430\u0441\u0442\u0438, \u043E\u043A\u0440\u0443\u0436\u0451\u043D\u043D\u043E\u0439 \u0442\u043E\u043B\u044C\u043A\u043E \u0442\u0432\u043E\u0438\u043C \u0446\u0432\u0435\u0442\u043E\u043C. \u041D\u0435\u0439\u0442\u0440\u0430\u043B\u044C\u043D\u044B\u0435 \u043E\u0431\u043B\u0430\u0441\u0442\u0438 \u043D\u0435 \u0441\u0447\u0438\u0442\u0430\u044E\u0442\u0441\u044F. \u0411\u0435\u043B\u044B\u0435 \u043F\u043E\u043B\u0443\u0447\u0430\u044E\u0442 \u043A\u043E\u043C\u043F\u0435\u043D\u0441\u0430\u0446\u0438\u044E \u2014 \u043A\u043E\u043C\u0438. \u041F\u043E\u0441\u043B\u0435 \u0434\u0432\u0443\u0445 \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0435\u043D\u0438\u0439 \u043F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u0442\u043E\u0442, \u0443 \u043A\u043E\u0433\u043E \u0431\u043E\u043B\u044C\u0448\u0435 \u043E\u0447\u043A\u043E\u0432. \u0420\u0430\u0432\u043D\u044B\u0439 \u0441\u0447\u0451\u0442 \u0434\u0430\u0451\u0442 \u043D\u0438\u0447\u044C\u044E."),
            rule_section(:variants, "\u0420\u0430\u0437\u043C\u0435\u0440 \u0434\u043E\u0441\u043A\u0438 \u0438 \u0432\u0430\u0440\u0438\u0430\u043D\u0442\u044B",
              "\u041F\u0440\u0438 \u0441\u043E\u0437\u0434\u0430\u043D\u0438\u0438 \u0441\u0442\u043E\u043B\u0430 \u0432\u044B\u0431\u0435\u0440\u0438 \u0434\u043E\u0441\u043A\u0443 9\u00D79, 13\u00D713 \u0438\u043B\u0438 19\u00D719 \u0438 \u0440\u0430\u0437\u043C\u0435\u0440 \u043A\u043E\u043C\u0438.",
              "- \u041F\u043E\u0434\u0441\u0447\u0451\u0442 \u0442\u0435\u0440\u0440\u0438\u0442\u043E\u0440\u0438\u0438: \u0432\u043C\u0435\u0441\u0442\u043E \u0436\u0438\u0432\u044B\u0445 \u043A\u0430\u043C\u043D\u0435\u0439 \u0443\u0447\u0438\u0442\u044B\u0432\u0430\u0439 \u043F\u043B\u0435\u043D\u043D\u044B\u0445 \u0438 \u043F\u0440\u0438\u0437\u043D\u0430\u043D\u043D\u044B\u0435 \u043C\u0451\u0440\u0442\u0432\u044B\u043C\u0438 \u043A\u0430\u043C\u043D\u0438 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u0430. \u041E\u043A\u0440\u0443\u0436\u0451\u043D\u043D\u044B\u0435 \u043F\u0443\u0441\u0442\u044B\u0435 \u043F\u0435\u0440\u0435\u0441\u0435\u0447\u0435\u043D\u0438\u044F \u0442\u043E\u0436\u0435 \u0438\u0434\u0443\u0442 \u0432 \u0441\u0447\u0451\u0442.",
              "- \u0410\u0442\u0430\u0440\u0438-\u0433\u043E: \u043F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u043F\u0435\u0440\u0432\u044B\u0439 \u0437\u0430\u0445\u0432\u0430\u0442. \u0414\u0432\u0430 \u043F\u0430\u0441\u0430 \u0431\u0435\u0437 \u0437\u0430\u0445\u0432\u0430\u0442\u0430 \u0434\u0430\u044E\u0442 \u043D\u0438\u0447\u044C\u044E. S \u0441\u043E\u043E\u0431\u0449\u0430\u0435\u0442 \u0447\u0438\u0441\u043B\u043E \u0437\u0430\u0445\u0432\u0430\u0447\u0435\u043D\u043D\u044B\u0445 \u043A\u0430\u043C\u043D\u0435\u0439."),
            rule_section(:controls, "\u0413\u043E\u0440\u044F\u0447\u0438\u0435 \u043A\u043B\u0430\u0432\u0438\u0448\u0438",
              "\u0421\u0442\u0440\u0435\u043B\u043A\u0438: \u043F\u0435\u0440\u0435\u043C\u0435\u0449\u0430\u0442\u044C\u0441\u044F \u043F\u043E \u043F\u0435\u0440\u0435\u0441\u0435\u0447\u0435\u043D\u0438\u044F\u043C",
              "Enter: \u043F\u043E\u0441\u0442\u0430\u0432\u0438\u0442\u044C \u043A\u0430\u043C\u0435\u043D\u044C \u0438\u043B\u0438 \u0438\u0437\u043C\u0435\u043D\u0438\u0442\u044C \u043E\u0442\u043C\u0435\u0442\u043A\u0443",
              "P: \u043F\u0440\u043E\u043F\u0443\u0441\u0442\u0438\u0442\u044C \u0445\u043E\u0434",
              "S: \u0443\u0437\u043D\u0430\u0442\u044C \u043F\u0440\u0435\u0434\u043B\u043E\u0436\u0435\u043D\u043D\u044B\u0439 \u0441\u0447\u0451\u0442 \u0438\u043B\u0438 \u0437\u0430\u0445\u0432\u0430\u0442\u044B \u0432 \u0430\u0442\u0430\u0440\u0438-\u0433\u043E",
              "A: \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u044C \u0441\u0447\u0451\u0442",
              "R: \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0438\u0442\u044C \u0438\u0433\u0440\u0443 \u043F\u043E\u0441\u043B\u0435 \u043F\u0430\u0441\u043E\u0432",
              "Q: \u0441\u0434\u0430\u0442\u044C\u0441\u044F")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
