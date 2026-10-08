# Generated from tools/data/rulebooks/reversi.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Reversi
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:turning, GameRoomRules.translate("Turn your opponent's discs into your own"),
            GameRoomRules.translate("Reversi is played by two people on an 8 by 8 board. Four discs are already in the centre: two black and two white. The first player is black and starts. Unlike in many board games, captured discs stay on the board and change colour. You want more discs of your colour when the game ends, not necessarily after every move."),
            GameRoomRules.translate("Normally you place one disc on an empty square so that one or more opposing discs lie between the new disc and one of your existing discs. They must form an uninterrupted straight line. For example, placing black next to a row of white, white, black turns both white discs black."),
            GameRoomRules.translate("This works horizontally, vertically and diagonally. If your move encloses discs in several directions, all those discs turn at once. You do not choose which lines to capture. An empty square interrupts a line, and the newly turned discs do not trigger a second chain of captures elsewhere.")),
          rule_section(:options, GameRoomRules.translate("Passing and playing without a capture"),
            GameRoomRules.translate("Mandatory capture is enabled by default. With it, every placement must turn at least one opposing disc. If you switch it off, a move without a capture is also allowed, but the new disc must be next to an existing disc, including diagonally. You still cannot play on an occupied square or in an isolated part of the board. A move that does enclose opposing discs always turns them."),
            GameRoomRules.translate("Allow passing is also enabled by default. It lets you give the turn to your opponent even when you have a legal move. You may do this repeatedly; voluntary passes alone do not produce a draw. Switch the option off if you want players to pass only when they cannot place a disc."),
            GameRoomRules.translate("The game ends when the board is full or neither player has a legal placement under the selected rules. The player with more discs wins; equal numbers mean a draw. Having no move yourself does not end the game if your opponent can still play.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse squares."),
            GameRoomRules.translate("Enter: place a disc on the selected square."),
            GameRoomRules.translate("P: pass when the table rules allow it."),
            GameRoomRules.translate("S: read each player's number of discs."),
            GameRoomRules.translate("T: read whose turn it is."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:aim, "C\u00EDl a za\u010D\u00E1tek hry",
              "Reversi hraj\u00ED dva hr\u00E1\u010Di na desce 8 \u00D7 8. Jeden m\u00E1 \u010Dern\u00E9 kameny, druh\u00FD b\u00EDl\u00E9. Rozhoduje po\u010Det kamen\u016F na konci hry: chce\u0161, aby jich co nejv\u00EDc m\u011Blo tvou barvu.",
              "Uprost\u0159ed desky jsou na za\u010D\u00E1tku \u010Dty\u0159i kameny, dva od ka\u017Ed\u00E9 barvy. Prvn\u00ED t\u00E1hne \u010Dern\u00FD, pak se hr\u00E1\u010Di st\u0159\u00EDdaj\u00ED."),
            rule_section(:placing, "Obkl\u00ED\u010Den\u00ED a ot\u00E1\u010Den\u00ED kamen\u016F",
              "Ve sv\u00E9m tahu polo\u017E\u00ED\u0161 k\u00E1men na pr\u00E1zdn\u00E9 pole tak, aby se mezi n\u00EDm a n\u011Bkter\u00FDm tv\u00FDm d\u0159\u00EDv\u011Bj\u0161\u00EDm kamenem ocitl alespo\u0148 jeden soupe\u0159\u016Fv k\u00E1men. \u0158ada m\u016F\u017Ee v\u00E9st vodorovn\u011B, svisle i \u0161ikmo, nesm\u00ED v n\u00ED ale b\u00FDt mezera.",
              "Vyber voln\u00E9 pole \u0161ipkami a potvr\u010F Enterem. V\u0161echny takto obkl\u00ED\u010Den\u00E9 soupe\u0159ovy kameny se obr\u00E1t\u00ED na tvou barvu. Uzav\u0159e\u0161-li jedn\u00EDm tahem n\u011Bkolik \u0159ad, oto\u010D\u00ED se kameny ve v\u0161ech.",
              "Nap\u0159\u00EDklad hraje\u0161 b\u00EDl\u00FDmi a mezi b\u00EDl\u00FDm kamenem a voln\u00FDm polem le\u017E\u00ED dva \u010Dern\u00E9. Polo\u017Een\u00EDm b\u00EDl\u00E9ho na toto pole zm\u011Bn\u00ED\u0161 oba \u010Dern\u00E9 na b\u00EDl\u00E9.",
              "Oto\u010Den\u00E9 kameny samy dal\u0161\u00ED kameny neot\u00E1\u010Dej\u00ED. Po\u010D\u00EDtaj\u00ED se jen \u0159ady, kter\u00E9 uzav\u0159el pr\u00E1v\u011B polo\u017Een\u00FD k\u00E1men."),
            rule_section(:passing, "Vynech\u00E1n\u00ED tahu",
              "Nem\u00E1\u0161-li \u017E\u00E1dn\u00FD tah, kter\u00FDm bys oto\u010Dil soupe\u0159\u016Fv k\u00E1men, automaticky vynech\u00E1\u0161. Soupe\u0159 pak hraje znovu, pokud m\u00E1 kam t\u00E1hnout.",
              "V z\u00E1kladn\u00EDm nastaven\u00ED se m\u016F\u017Ee\u0161 tahu vzd\u00E1t i dobrovoln\u011B kl\u00E1vesou P. Dv\u011B dobrovoln\u00E1 vynech\u00E1n\u00ED za sebou hru neukon\u010D\u00ED, jestli\u017Ee je\u0161t\u011B existuj\u00ED p\u0159\u00EDpustn\u00E9 tahy."),
            rule_section(:ending, "V\u00FDsledek hry",
              "Hra skon\u010D\u00ED zapln\u011Bn\u00EDm desky nebo ve chv\u00EDli, kdy u\u017E nem\u016F\u017Ee t\u00E1hnout ani jeden z v\u00E1s. V\u00EDt\u011Bz\u00ED barva s v\u00EDce kameny; p\u0159i stejn\u00E9m po\u010Dtu je rem\u00EDza. Aktu\u00E1ln\u00ED po\u010Dty p\u0159e\u010Dte S."),
            rule_section(:variants, "Voliteln\u00E9 zm\u011Bny",
              "P\u0159ed hrou lze v nastaven\u00ED stolu pravidla upravit:",
              "- Z\u00E1kaz dobrovoln\u00E9ho vynech\u00E1n\u00ED znamen\u00E1, \u017Ee vynech\u00E1\u0161 pouze tehdy, kdy\u017E nem\u00E1\u0161 \u017E\u00E1dn\u00FD p\u0159\u00EDpustn\u00FD tah.",
              "- Vypnut\u00EDm povinn\u00E9ho ot\u00E1\u010Den\u00ED sm\u00ED\u0161 polo\u017Eit k\u00E1men na ka\u017Ed\u00E9 voln\u00E9 pole soused\u00EDc\u00ED stranou nebo rohem s libovoln\u00FDm kamenem. Pokud t\u00EDm z\u00E1rove\u0148 obkl\u00ED\u010D\u00ED\u0161 soupe\u0159ovy kameny, oto\u010D\u00ED se jako obvykle."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "\u0160ipky: proch\u00E1zet pole desky.",
              "Enter: polo\u017Eit k\u00E1men.",
              "P: vynechat tah, dovoluj\u00ED-li to pravidla stolu.",
              "S: p\u0159e\u010D\u00EDst po\u010Dty kamen\u016F obou hr\u00E1\u010D\u016F.",
              "T: ozn\u00E1mit, kdo je na tahu.")
          ]
        when "en"
          [
            rule_section(:aim, "The aim",
              "Reversi is played by two people on an eight-by-eight board. One plays Black, the other White. Finish with more discs of your colour to win.",
              "Four discs begin in the centre, two of each colour. Black moves first, then players alternate."),
            rule_section(:placing, "Placing and flipping discs",
              "On your turn, place one disc on an empty square so that it traps at least one enemy disc between the new disc and another of your own. The line may be horizontal, vertical or diagonal, with no gaps.",
              "Find the empty square with the arrows and press Enter. All enemy discs trapped by that placement change to your colour. A move can close several lines at once and flips the discs in all of them.",
              "For example, if two black discs lie between your white disc and an empty square, placing a white disc in that square turns both black discs white.",
              "Only lines closed by the newly placed disc count. Flipped discs do not start a chain of further flips."),
            rule_section(:passing, "Passing",
              "If you cannot place a disc that flips an opponent's disc, you pass automatically. The opponent then takes another turn if they have a legal move.",
              "By default, you may also pass voluntarily with P. Both players passing does not end the game while legal moves still exist."),
            rule_section(:ending, "The result",
              "Play ends when the board is full or neither player can make a legal move. The player with more discs wins; equal counts are a draw. S reads the disc counts."),
            rule_section(:variants, "Rule options",
              "Two settings can change play:",
              "- Disable voluntary passing to require a move whenever one is possible.",
              "- Disable mandatory capture to allow placement on any empty square adjacent, along a side or corner, to an existing disc. A placement that traps enemy discs still flips them as usual."),
            rule_section(:controls, "Keyboard shortcuts",
              "Arrows: explore the board.",
              "Enter: place a disc in the selected square.",
              "P: pass, if the table rules allow it.",
              "S: read both disc counts.",
              "T: read whose turn it is.")
          ]
        when "es"
          [
            rule_section(:aim, "Objetivo",
              "Reversi enfrenta a dos personas en un tablero de 8 por 8. Una juega con negras y otra con blancas. Gana quien termine con m\u00E1s fichas de su color.",
              "Al empezar hay cuatro fichas en el centro, dos de cada color. Las negras hacen el primer movimiento y despu\u00E9s se alternan los turnos."),
            rule_section(:placing, "Colocar y voltear fichas",
              "En cada turno colocas una ficha en una casilla vac\u00EDa. Debe encerrar al menos una ficha rival entre la nueva y otra de tu color. La l\u00EDnea puede ser horizontal, vertical o diagonal, pero no tener huecos.",
              "Llega a la casilla con las flechas y pulsa Enter. Todas las fichas rivales encerradas cambian a tu color. Si cierras varias l\u00EDneas a la vez, se voltean las fichas de todas ellas.",
              "Por ejemplo, juegas con blancas y hay dos negras entre una ficha blanca tuya y una casilla vac\u00EDa. Al poner una blanca en esa casilla, las dos negras pasan a ser blancas.",
              "Las fichas reci\u00E9n volteadas no provocan m\u00E1s cambios en cadena. Solo cuentan las l\u00EDneas que cierra la ficha que acabas de colocar."),
            rule_section(:passing, "Pasar el turno",
              "Si no tienes ninguna jugada que voltee fichas rivales, pasas autom\u00E1ticamente. El rival vuelve a jugar, si puede.",
              "Con las reglas habituales tambi\u00E9n puedes pasar voluntariamente pulsando P. Que ambos pasen no termina por s\u00ED solo la partida si a\u00FAn hay jugadas posibles."),
            rule_section(:ending, "Final y resultado",
              "La partida termina cuando el tablero est\u00E1 lleno o ninguno de los dos puede jugar. Gana quien tenga m\u00E1s fichas; con la misma cantidad hay empate. S consulta cu\u00E1ntas tiene cada uno."),
            rule_section(:variants, "Variantes",
              "Antes de jugar puedes cambiar dos reglas:",
              "- Prohibir el pase voluntario: solo pasas si no tienes ninguna jugada legal.",
              "- Quitar la obligaci\u00F3n de voltear: puedes colocar una ficha en cualquier casilla vac\u00EDa contigua por un lado o una esquina a una ficha del tablero. Si la jugada encierra fichas rivales, se voltean normalmente."),
            rule_section(:controls, "Teclas de referencia",
              "Flechas: recorrer el tablero.",
              "Enter: colocar una ficha.",
              "P: pasar, si lo permiten las reglas de la mesa.",
              "S: contar las fichas de ambos jugadores.",
              "T: consultar de qui\u00E9n es el turno.")
          ]
        when "pl"
          [
            rule_section(:aim, "Cel gry",
              "W Reversi graj\u0105 dwie osoby na planszy 8 na 8 p\u00F3l. Jedna ma czarne pionki, druga bia\u0142e. Wygrywa ten, kto na koniec b\u0119dzie mia\u0142 na planszy wi\u0119cej pionk\u00F3w swojego koloru.",
              "Na pocz\u0105tku po\u015Brodku stoj\u0105 cztery pionki, po dwa ka\u017Cdego koloru. Zaczynaj\u0105 czarne, a potem gracze wykonuj\u0105 ruchy na zmian\u0119."),
            rule_section(:placing, "Stawianie i odwracanie pionk\u00F3w",
              "W swojej turze stawiasz jeden pionek na pustym polu. Musisz przy tym zamkn\u0105\u0107 co najmniej jeden pionek przeciwnika mi\u0119dzy nowym pionkiem a innym swoim pionkiem. Ta linia mo\u017Ce biec wzd\u0142u\u017C rz\u0119du, kolumny albo przek\u0105tnej, ale nie mo\u017Ce mie\u0107 przerw.",
              "Przejd\u017A strza\u0142kami do wybranego pustego pola i naci\u015Bnij Enter. Wszystkie pionki przeciwnika zamkni\u0119te w ten spos\u00F3b zmieni\u0105 kolor na Tw\u00F3j. Je\u015Bli ruch zamyka kilka linii jednocze\u015Bnie, odwracaj\u0105 si\u0119 pionki w ka\u017Cdej z nich.",
              "Na przyk\u0142ad mi\u0119dzy Twoim pionkiem a pustym polem stoj\u0105 dwa czarne pionki. Je\u015Bli grasz bia\u0142ymi i postawisz pionek na tym pustym polu, oba czarne stan\u0105 si\u0119 bia\u0142e.",
              "Odwr\u00F3cone pionki nie wywo\u0142uj\u0105 dalszych odwr\u00F3ce\u0144. Licz\u0105 si\u0119 tylko linie zamkni\u0119te przez pionek, kt\u00F3ry w\u0142a\u015Bnie postawi\u0142e\u015B."),
            rule_section(:passing, "Pomijanie ruchu",
              "Je\u015Bli nie mo\u017Cesz wykona\u0107 ruchu odwracaj\u0105cego pionki przeciwnika, automatycznie pomijasz tur\u0119. Przeciwnik gra wtedy ponownie, o ile sam mo\u017Ce wykona\u0107 ruch.",
              "Przy zwyk\u0142ych ustawieniach mo\u017Cesz te\u017C dobrowolnie zrezygnowa\u0107 z ruchu, naciskaj\u0105c P. Samo pasowanie obu graczy nie ko\u0144czy partii, je\u015Bli nadal istniej\u0105 mo\u017Cliwe ruchy."),
            rule_section(:ending, "Koniec i wynik",
              "Gra ko\u0144czy si\u0119, gdy plansza zostanie zape\u0142niona albo \u017Caden z graczy nie mo\u017Ce ju\u017C wykona\u0107 ruchu. Wygrywa osoba, kt\u00F3ra ma wi\u0119cej pionk\u00F3w na planszy. Je\u015Bli oboje macie tyle samo, jest remis. Liczb\u0119 pionk\u00F3w sprawdzisz klawiszem S."),
            rule_section(:variants, "Zmiany zasad",
              "W ustawieniach przed gr\u0105 mo\u017Cna wprowadzi\u0107 dwie zmiany:",
              "- Mo\u017Cna zabroni\u0107 dobrowolnego pasowania. Wtedy pomijasz kolej tylko wtedy, gdy nie masz \u017Cadnego dozwolonego ruchu.",
              "- Mo\u017Cna wy\u0142\u0105czy\u0107 obowi\u0105zek odwr\u00F3cenia pionka przy ka\u017Cdym ruchu. Wolno wtedy dostawi\u0107 pionek na puste pole s\u0105siaduj\u0105ce bokiem lub rogiem z dowolnym pionkiem na planszy. Je\u015Bli taki ruch zamknie pionki przeciwnika, nadal zmieniaj\u0105 kolor jak zwykle."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "Strza\u0142ki: przegl\u0105daj pola planszy.",
              "Enter: postaw pionek na wybranym polu.",
              "P: spasuj, je\u015Bli pozwalaj\u0105 na to zasady sto\u0142u.",
              "S: odczytaj liczb\u0119 pionk\u00F3w obu graczy.",
              "T: odczytaj, czyja jest tura.")
          ]
        when "ru"
          [
            rule_section(:aim, "\u0426\u0435\u043B\u044C \u0438\u0433\u0440\u044B",
              "\u0412 \u0440\u0435\u0432\u0435\u0440\u0441\u0438 \u0434\u0432\u0430 \u0438\u0433\u0440\u043E\u043A\u0430 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u0447\u0430\u044E\u0442 \u0437\u0430 \u043A\u043B\u0435\u0442\u043A\u0438 \u0434\u043E\u0441\u043A\u0438 8 \u043D\u0430 8. \u041E\u0434\u0438\u043D \u0438\u0433\u0440\u0430\u0435\u0442 \u0447\u0451\u0440\u043D\u044B\u043C\u0438 \u0444\u0438\u0448\u043A\u0430\u043C\u0438, \u0434\u0440\u0443\u0433\u043E\u0439 \u2014 \u0431\u0435\u043B\u044B\u043C\u0438. \u041D\u0443\u0436\u043D\u043E \u0437\u0430\u043A\u043E\u043D\u0447\u0438\u0442\u044C \u043F\u0430\u0440\u0442\u0438\u044E \u0441 \u0431\u043E\u043B\u044C\u0448\u0438\u043C \u0447\u0438\u0441\u043B\u043E\u043C \u0444\u0438\u0448\u0435\u043A \u0441\u0432\u043E\u0435\u0433\u043E \u0446\u0432\u0435\u0442\u0430.",
              "\u0412 \u0446\u0435\u043D\u0442\u0440\u0435 \u0443\u0436\u0435 \u0441\u0442\u043E\u044F\u0442 \u0447\u0435\u0442\u044B\u0440\u0435 \u0444\u0438\u0448\u043A\u0438 \u2014 \u0434\u0432\u0435 \u0447\u0451\u0440\u043D\u044B\u0435 \u0438 \u0434\u0432\u0435 \u0431\u0435\u043B\u044B\u0435. \u041F\u0435\u0440\u0432\u044B\u043C\u0438 \u0445\u043E\u0434\u044F\u0442 \u0447\u0451\u0440\u043D\u044B\u0435, \u0434\u0430\u043B\u044C\u0448\u0435 \u0438\u0433\u0440\u043E\u043A\u0438 \u0447\u0435\u0440\u0435\u0434\u0443\u044E\u0442\u0441\u044F."),
            rule_section(:placing, "\u041A\u0430\u043A \u0441\u0442\u0430\u0432\u0438\u0442\u044C \u0438 \u043F\u0435\u0440\u0435\u0432\u043E\u0440\u0430\u0447\u0438\u0432\u0430\u0442\u044C \u0444\u0438\u0448\u043A\u0438",
              "\u0417\u0430 \u0445\u043E\u0434 \u0432\u044B \u0441\u0442\u0430\u0432\u0438\u0442\u0435 \u043E\u0434\u043D\u0443 \u0444\u0438\u0448\u043A\u0443 \u043D\u0430 \u0441\u0432\u043E\u0431\u043E\u0434\u043D\u0443\u044E \u043A\u043B\u0435\u0442\u043A\u0443. \u041F\u0440\u0438 \u044D\u0442\u043E\u043C \u043C\u0435\u0436\u0434\u0443 \u043D\u0435\u0439 \u0438 \u0434\u0440\u0443\u0433\u043E\u0439 \u0432\u0430\u0448\u0435\u0439 \u0444\u0438\u0448\u043A\u043E\u0439 \u0434\u043E\u043B\u0436\u043D\u0430 \u043E\u043A\u0430\u0437\u0430\u0442\u044C\u0441\u044F \u043D\u0435\u043F\u0440\u0435\u0440\u044B\u0432\u043D\u0430\u044F \u043B\u0438\u043D\u0438\u044F \u0438\u0437 \u043E\u0434\u043D\u043E\u0439 \u0438\u043B\u0438 \u043D\u0435\u0441\u043A\u043E\u043B\u044C\u043A\u0438\u0445 \u0447\u0443\u0436\u0438\u0445 \u0444\u0438\u0448\u0435\u043A. \u0422\u0430\u043A\u0430\u044F \u043B\u0438\u043D\u0438\u044F \u043C\u043E\u0436\u0435\u0442 \u0438\u0434\u0442\u0438 \u043F\u043E \u0433\u043E\u0440\u0438\u0437\u043E\u043D\u0442\u0430\u043B\u0438, \u0432\u0435\u0440\u0442\u0438\u043A\u0430\u043B\u0438 \u0438\u043B\u0438 \u0434\u0438\u0430\u0433\u043E\u043D\u0430\u043B\u0438.",
              "\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0441\u0432\u043E\u0431\u043E\u0434\u043D\u0443\u044E \u043A\u043B\u0435\u0442\u043A\u0443 \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0438 \u043D\u0430\u0436\u043C\u0438\u0442\u0435 Enter. \u0412\u0441\u0435 \u0437\u0430\u0436\u0430\u0442\u044B\u0435 \u0442\u0430\u043A\u0438\u043C \u043E\u0431\u0440\u0430\u0437\u043E\u043C \u0444\u0438\u0448\u043A\u0438 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u0430 \u043F\u0435\u0440\u0435\u0432\u0435\u0440\u043D\u0443\u0442\u0441\u044F \u0438 \u0441\u0442\u0430\u043D\u0443\u0442 \u0432\u0430\u0448\u0435\u0433\u043E \u0446\u0432\u0435\u0442\u0430. \u0415\u0441\u043B\u0438 \u043D\u043E\u0432\u044B\u0439 \u0445\u043E\u0434 \u0437\u0430\u043C\u044B\u043A\u0430\u0435\u0442 \u0441\u0440\u0430\u0437\u0443 \u043D\u0435\u0441\u043A\u043E\u043B\u044C\u043A\u043E \u043B\u0438\u043D\u0438\u0439, \u043F\u0435\u0440\u0435\u0432\u043E\u0440\u0430\u0447\u0438\u0432\u0430\u044E\u0442\u0441\u044F \u0444\u0438\u0448\u043A\u0438 \u0432\u043E \u0432\u0441\u0435\u0445 \u044D\u0442\u0438\u0445 \u043B\u0438\u043D\u0438\u044F\u0445.",
              "\u041D\u0430\u043F\u0440\u0438\u043C\u0435\u0440, \u0432\u044B \u0438\u0433\u0440\u0430\u0435\u0442\u0435 \u0431\u0435\u043B\u044B\u043C\u0438. \u041C\u0435\u0436\u0434\u0443 \u0432\u0430\u0448\u0435\u0439 \u0444\u0438\u0448\u043A\u043E\u0439 \u0438 \u0441\u0432\u043E\u0431\u043E\u0434\u043D\u043E\u0439 \u043A\u043B\u0435\u0442\u043A\u043E\u0439 \u043F\u043E\u0434\u0440\u044F\u0434 \u0441\u0442\u043E\u044F\u0442 \u0434\u0432\u0435 \u0447\u0451\u0440\u043D\u044B\u0435. \u041F\u043E\u0441\u0442\u0430\u0432\u0438\u0432 \u043D\u0430 \u044D\u0442\u0443 \u043A\u043B\u0435\u0442\u043A\u0443 \u0431\u0435\u043B\u0443\u044E \u0444\u0438\u0448\u043A\u0443, \u0432\u044B \u043F\u0440\u0435\u0432\u0440\u0430\u0442\u0438\u0442\u0435 \u043E\u0431\u0435 \u0447\u0451\u0440\u043D\u044B\u0435 \u0432 \u0431\u0435\u043B\u044B\u0435.",
              "\u0426\u0435\u043F\u043D\u043E\u0439 \u0440\u0435\u0430\u043A\u0446\u0438\u0438 \u043D\u0435\u0442: \u0443\u0436\u0435 \u043F\u0435\u0440\u0435\u0432\u0451\u0440\u043D\u0443\u0442\u044B\u0435 \u0444\u0438\u0448\u043A\u0438 \u043D\u0435 \u043F\u0435\u0440\u0435\u0432\u043E\u0440\u0430\u0447\u0438\u0432\u0430\u044E\u0442 \u0434\u0440\u0443\u0433\u0438\u0435. \u0423\u0447\u0438\u0442\u044B\u0432\u0430\u044E\u0442\u0441\u044F \u0442\u043E\u043B\u044C\u043A\u043E \u043B\u0438\u043D\u0438\u0438, \u0437\u0430\u043C\u043A\u043D\u0443\u0442\u044B\u0435 \u0444\u0438\u0448\u043A\u043E\u0439, \u043F\u043E\u0441\u0442\u0430\u0432\u043B\u0435\u043D\u043D\u043E\u0439 \u0432 \u044D\u0442\u043E\u043C \u0445\u043E\u0434\u0443."),
            rule_section(:passing, "\u041F\u0440\u043E\u043F\u0443\u0441\u043A \u0445\u043E\u0434\u0430",
              "\u0415\u0441\u043B\u0438 \u043D\u0438 \u043E\u0434\u043D\u0438\u043C \u0445\u043E\u0434\u043E\u043C \u043D\u0435\u043B\u044C\u0437\u044F \u043F\u0435\u0440\u0435\u0432\u0435\u0440\u043D\u0443\u0442\u044C \u0447\u0443\u0436\u0443\u044E \u0444\u0438\u0448\u043A\u0443, \u0432\u044B \u0430\u0432\u0442\u043E\u043C\u0430\u0442\u0438\u0447\u0435\u0441\u043A\u0438 \u043F\u0440\u043E\u043F\u0443\u0441\u043A\u0430\u0435\u0442\u0435 \u043E\u0447\u0435\u0440\u0435\u0434\u044C. \u0421\u043E\u043F\u0435\u0440\u043D\u0438\u043A \u0445\u043E\u0434\u0438\u0442 \u0441\u043D\u043E\u0432\u0430, \u0435\u0441\u043B\u0438 \u0443 \u043D\u0435\u0433\u043E \u0435\u0441\u0442\u044C \u0434\u043E\u043F\u0443\u0441\u0442\u0438\u043C\u044B\u0439 \u0445\u043E\u0434.",
              "\u041F\u043E \u0443\u043C\u043E\u043B\u0447\u0430\u043D\u0438\u044E \u043C\u043E\u0436\u043D\u043E \u0438 \u0434\u043E\u0431\u0440\u043E\u0432\u043E\u043B\u044C\u043D\u043E \u043F\u0440\u043E\u043F\u0443\u0441\u0442\u0438\u0442\u044C \u0445\u043E\u0434 \u043A\u043B\u0430\u0432\u0438\u0448\u0435\u0439 P. \u0414\u0430\u0436\u0435 \u0435\u0441\u043B\u0438 \u043E\u0431\u0430 \u0438\u0433\u0440\u043E\u043A\u0430 \u043F\u0430\u0441\u0443\u044E\u0442, \u043F\u0430\u0440\u0442\u0438\u044F \u043D\u0435 \u0437\u0430\u043A\u0430\u043D\u0447\u0438\u0432\u0430\u0435\u0442\u0441\u044F, \u043F\u043E\u043A\u0430 \u043E\u0441\u0442\u0430\u044E\u0442\u0441\u044F \u0432\u043E\u0437\u043C\u043E\u0436\u043D\u044B\u0435 \u0445\u043E\u0434\u044B."),
            rule_section(:ending, "\u0418\u0442\u043E\u0433 \u043F\u0430\u0440\u0442\u0438\u0438",
              "\u041F\u0430\u0440\u0442\u0438\u044F \u0437\u0430\u043A\u0430\u043D\u0447\u0438\u0432\u0430\u0435\u0442\u0441\u044F, \u043A\u043E\u0433\u0434\u0430 \u0434\u043E\u0441\u043A\u0430 \u0437\u0430\u043F\u043E\u043B\u043D\u0435\u043D\u0430 \u0438\u043B\u0438 \u043D\u0438 \u043E\u0434\u0438\u043D \u0438\u0433\u0440\u043E\u043A \u0431\u043E\u043B\u044C\u0448\u0435 \u043D\u0435 \u043C\u043E\u0436\u0435\u0442 \u0441\u0434\u0435\u043B\u0430\u0442\u044C \u0445\u043E\u0434. \u041F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u0442\u043E\u0442, \u0447\u044C\u0438\u0445 \u0444\u0438\u0448\u0435\u043A \u0431\u043E\u043B\u044C\u0448\u0435. \u041F\u0440\u0438 \u0440\u0430\u0432\u0435\u043D\u0441\u0442\u0432\u0435 \u043E\u0431\u044A\u044F\u0432\u043B\u044F\u0435\u0442\u0441\u044F \u043D\u0438\u0447\u044C\u044F. \u041A\u043B\u0430\u0432\u0438\u0448\u0430 S \u0441\u043E\u043E\u0431\u0449\u0430\u0435\u0442 \u0447\u0438\u0441\u043B\u043E \u0444\u0438\u0448\u0435\u043A \u0443 \u043E\u0431\u0435\u0438\u0445 \u0441\u0442\u043E\u0440\u043E\u043D."),
            rule_section(:variants, "\u0412\u0430\u0440\u0438\u0430\u043D\u0442\u044B \u043F\u0440\u0430\u0432\u0438\u043B",
              "\u041F\u0435\u0440\u0435\u0434 \u0438\u0433\u0440\u043E\u0439 \u0434\u043E\u0441\u0442\u0443\u043F\u043D\u044B \u0434\u0432\u0435 \u043E\u0442\u0434\u0435\u043B\u044C\u043D\u044B\u0435 \u043D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0438:",
              "- \u041C\u043E\u0436\u043D\u043E \u0437\u0430\u043F\u0440\u0435\u0442\u0438\u0442\u044C \u0434\u043E\u0431\u0440\u043E\u0432\u043E\u043B\u044C\u043D\u044B\u0439 \u043F\u0430\u0441. \u0422\u043E\u0433\u0434\u0430 \u0445\u043E\u0434 \u043F\u0440\u043E\u043F\u0443\u0441\u043A\u0430\u0435\u0442\u0441\u044F \u043B\u0438\u0448\u044C \u043F\u0440\u0438 \u043E\u0442\u0441\u0443\u0442\u0441\u0442\u0432\u0438\u0438 \u0434\u043E\u043F\u0443\u0441\u0442\u0438\u043C\u044B\u0445 \u0445\u043E\u0434\u043E\u0432.",
              "- \u041C\u043E\u0436\u043D\u043E \u043E\u0442\u043C\u0435\u043D\u0438\u0442\u044C \u043E\u0431\u044F\u0437\u0430\u0442\u0435\u043B\u044C\u043D\u043E\u0435 \u043F\u0435\u0440\u0435\u0432\u043E\u0440\u0430\u0447\u0438\u0432\u0430\u043D\u0438\u0435. \u0412 \u044D\u0442\u043E\u043C \u0432\u0430\u0440\u0438\u0430\u043D\u0442\u0435 \u0444\u0438\u0448\u043A\u0443 \u0440\u0430\u0437\u0440\u0435\u0448\u0435\u043D\u043E \u043F\u043E\u0441\u0442\u0430\u0432\u0438\u0442\u044C \u043D\u0430 \u043B\u044E\u0431\u0443\u044E \u0441\u0432\u043E\u0431\u043E\u0434\u043D\u0443\u044E \u043A\u043B\u0435\u0442\u043A\u0443, \u0441\u043E\u0441\u0435\u0434\u043D\u044E\u044E \u0441\u0442\u043E\u0440\u043E\u043D\u043E\u0439 \u0438\u043B\u0438 \u0443\u0433\u043B\u043E\u043C \u0441 \u0443\u0436\u0435 \u0441\u0442\u043E\u044F\u0449\u0435\u0439 \u0444\u0438\u0448\u043A\u043E\u0439 \u043B\u044E\u0431\u043E\u0433\u043E \u0446\u0432\u0435\u0442\u0430. \u0415\u0441\u043B\u0438 \u043F\u0440\u0438 \u044D\u0442\u043E\u043C \u0437\u0430\u043C\u044B\u043A\u0430\u0435\u0442\u0441\u044F \u043B\u0438\u043D\u0438\u044F \u0447\u0443\u0436\u0438\u0445 \u0444\u0438\u0448\u0435\u043A, \u043E\u043D\u0438 \u043F\u0435\u0440\u0435\u0432\u043E\u0440\u0430\u0447\u0438\u0432\u0430\u044E\u0442\u0441\u044F \u043F\u043E \u043E\u0431\u044B\u0447\u043D\u044B\u043C \u043F\u0440\u0430\u0432\u0438\u043B\u0430\u043C."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0448\u0438 \u0443\u043F\u0440\u0430\u0432\u043B\u0435\u043D\u0438\u044F",
              "\u0421\u0442\u0440\u0435\u043B\u043A\u0438: \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u0442\u044C \u0434\u043E\u0441\u043A\u0443.",
              "Enter: \u043F\u043E\u0441\u0442\u0430\u0432\u0438\u0442\u044C \u0444\u0438\u0448\u043A\u0443 \u043D\u0430 \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u0443\u044E \u043A\u043B\u0435\u0442\u043A\u0443.",
              "P: \u043F\u0440\u043E\u043F\u0443\u0441\u0442\u0438\u0442\u044C \u0445\u043E\u0434, \u0435\u0441\u043B\u0438 \u043F\u0440\u0430\u0432\u0438\u043B\u0430 \u0441\u0442\u043E\u043B\u0430 \u044D\u0442\u043E \u0440\u0430\u0437\u0440\u0435\u0448\u0430\u044E\u0442.",
              "S: \u0443\u0437\u043D\u0430\u0442\u044C \u0447\u0438\u0441\u043B\u043E \u0444\u0438\u0448\u0435\u043A \u0443 \u043E\u0431\u043E\u0438\u0445 \u0438\u0433\u0440\u043E\u043A\u043E\u0432.",
              "T: \u0443\u0437\u043D\u0430\u0442\u044C, \u0447\u0435\u0439 \u0441\u0435\u0439\u0447\u0430\u0441 \u0445\u043E\u0434.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
