# Generated from tools/data/rulebooks/war.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class War
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:battle, GameRoomRules.translate("Play your top card"),
            GameRoomRules.translate("War is a card game for two to eight players. The whole deck is dealt out, and every player keeps their cards in a face-down pile. Players do not choose cards: in each battle, everyone plays the top card of their own pile, one after another."),
            GameRoomRules.translate("The highest card wins the battle and takes all the cards from the table. Aces are highest, then kings, queens, jacks, tens and so on down to the lowest card in the deck. Suits do not matter. The cards taken go to the bottom of the winner's pile in random order.")),
          rule_section(:war, GameRoomRules.translate("War: equal highest cards"),
            GameRoomRules.translate("If two or more players share the highest card, a war starts between them. Each of them places one hidden card and then plays the next card face up. The highest of the new cards takes everything from the table, including the hidden cards and the cards of players who did not take part in the war. If the new cards are equal again, the war continues in the same way. When a war is won, the winner hears every hidden card taken, first the opponents' and then their own, and then the other cards from the table."),
            GameRoomRules.translate("A player with only one card left plays it face up without a hidden card. A player with no cards cannot continue the war; if only one participant can continue, they take the table. If nobody can continue, the cards stay on the table and go to the winner of the next battle.")),
          rule_section(:deck, GameRoomRules.translate("Choosing the deck"),
            GameRoomRules.translate("The Deck option chooses a short deck of 24 cards, from nine to ace, or a full deck of 52 cards, from two to ace. The short deck is the default and gives a much quicker game. If the cards cannot be divided equally, some players start with one card more.")),
          rule_section(:ending, GameRoomRules.translate("End of the game"),
            GameRoomRules.translate("A player who has no cards left after a battle is out of the game. The last player with cards wins."),
            GameRoomRules.translate("War can last very long, so the table has a battle limit, from 20 to 300 battles, 20 by default. When the limit is reached, the player with the most cards wins. If several players have the same highest number of cards, the game ends in a draw.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Enter: play your top card."),
            GameRoomRules.translate("Space: play your top card."),
            GameRoomRules.translate("C: read the cards on the table, your own first, then each opponent's."),
            GameRoomRules.translate("E: read each player's card count."),
            GameRoomRules.translate("V: read the result of the last battle."),
            GameRoomRules.translate("T: read whose turn it is."),
            GameRoomRules.translate("Ctrl+T: read the number of the current battle and the battle limit."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:aim, "C\u00EDl hry",
              "Ve h\u0159e War se sna\u017E\u00ED\u0161 z\u00EDskat karty ostatn\u00EDch hr\u00E1\u010D\u016F. Dva a\u017E osm hr\u00E1\u010D\u016F si rozd\u011Bl\u00ED 24 karet od dev\u00EDtek po esa. Po\u0159ad\u00ED karet si nevyb\u00EDr\u00E1\u0161: v\u017Edy hraje\u0161 tu, kter\u00E1 je zrovna na \u0159ad\u011B."),
            rule_section(:play, "Porovn\u00E1v\u00E1n\u00ED karet",
              "A\u017E p\u0159ijde tv\u016Fj tah, stiskni Enter. Jakmile ka\u017Ed\u00FD vylo\u017E\u00ED jednu kartu, nejvy\u0161\u0161\u00ED z nich vyhraje v\u0161echny karty tohoto souboje. Hodnoty od nejni\u017E\u0161\u00ED jsou dev\u00EDtka, des\u00EDtka, kluk, d\u00E1ma, kr\u00E1l a eso; barva nehraje roli.",
              "Z\u00EDskan\u00E9 karty se v n\u00E1hodn\u00E9m po\u0159ad\u00ED za\u0159ad\u00ED pod karty, kter\u00E9 ti je\u0161t\u011B zb\u00FDvaj\u00ED, a za\u010D\u00EDn\u00E1 nov\u00FD souboj. Kl\u00E1vesa C p\u0159e\u010Dte pr\u00E1v\u011B vylo\u017Een\u00E9 karty, V p\u0159ipomene v\u00FDsledek p\u0159edchoz\u00EDho souboje."),
            rule_section(:tie, "V\u00E1lka p\u0159i shod\u011B",
              "Kdy\u017E m\u00E1 nejvy\u0161\u0161\u00ED hodnotu n\u011Bkolik hr\u00E1\u010D\u016F, za\u010D\u00EDn\u00E1 v\u00E1lka. \u00DA\u010Dastn\u00ED se j\u00ED jen tito hr\u00E1\u010Di, ale hraj\u00ED o v\u0161echny karty, kter\u00E9 se v souboji dosud se\u0161ly.",
              "Ve sv\u00E9m tahu znovu stiskni Enter. P\u0159id\u00E1\u0161 jednu kartu skrytou a jednu odkrytou. Nejvy\u0161\u0161\u00ED odkryt\u00E1 karta z\u00EDsk\u00E1 cel\u00FD souboj v\u010Detn\u011B skryt\u00FDch karet; dal\u0161\u00ED shoda vyvol\u00E1 dal\u0161\u00ED v\u00E1lku.",
              "Zb\u00FDv\u00E1-li ti jedin\u00E1 karta, pou\u017Eije\u0161 ji k porovn\u00E1n\u00ED bez skryt\u00E9 karty. Bez karet pokra\u010Dovat nem\u016F\u017Ee\u0161. Jakmile m\u016F\u017Ee pokra\u010Dovat u\u017E jen jeden hr\u00E1\u010D, bere v\u0161e. Nem\u00E1-li dost karet nikdo, ko\u0159ist z\u016Fstane do p\u0159\u00ED\u0161t\u00EDho souboje."),
            rule_section(:ending, "Vy\u0159azen\u00ED a v\u00EDt\u011Bzstv\u00ED",
              "Po vyhodnocen\u00ED souboje vypadnou hr\u00E1\u010Di bez karet. Posledn\u00ED zb\u00FDvaj\u00EDc\u00ED hr\u00E1\u010D vyhr\u00E1v\u00E1; kdyby nezbyly karty nikomu, je rem\u00EDza.",
              "Z\u00E1kladn\u00ED hra m\u00E1 nejv\u00FD\u0161 20 souboj\u016F. Pokud se d\u0159\u00EDv nerozhodne, vyhraje ten, kdo m\u00E1 nejv\u00EDc karet. O nejvy\u0161\u0161\u00ED po\u010Det se lze d\u011Blit, a tedy remizovat. Po\u010Dty karet zjist\u00ED\u0161 kl\u00E1vesou E, \u010D\u00EDslo souboje a limit pomoc\u00ED Ctrl+T."),
            rule_section(:variants, "Bal\u00ED\u010Dek a d\u00E9lka hry",
              "P\u0159ed za\u010D\u00E1tkem lze v nastaven\u00ED stolu vybrat jin\u00FD bal\u00ED\u010Dek a del\u0161\u00ED hru:",
              "- Pln\u00FD bal\u00ED\u010Dek m\u00E1 52 karet od dvojek po esa. Hodnoty rostou podle \u010D\u00EDsla, za des\u00EDtkou n\u00E1sleduj\u00ED kluk, d\u00E1ma, kr\u00E1l a eso.",
              "- Limit lze zv\u00FD\u0161it z 20 a\u017E na 300 souboj\u016F. I po tomto limitu rozhoduje nejv\u011Bt\u0161\u00ED po\u010Det karet."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "Enter: zahr\u00E1t vrchn\u00ED kartu.",
              "Mezern\u00EDk: zahr\u00E1t vrchn\u00ED kartu.",
              "C: p\u0159e\u010D\u00EDst vylo\u017Een\u00E9 karty, nejd\u0159\u00EDv vlastn\u00ED, pak soupe\u0159ovy.",
              "E: p\u0159e\u010D\u00EDst po\u010Dty karet hr\u00E1\u010D\u016F.",
              "V: p\u0159e\u010D\u00EDst v\u00FDsledek minul\u00E9ho souboje.",
              "T: ozn\u00E1mit, kdo je na tahu.",
              "Ctrl+T: p\u0159e\u010D\u00EDst \u010D\u00EDslo souboje a celkov\u00FD limit.")
          ]
        when "en"
          [
            rule_section(:aim, "The aim",
              "Win the other players' cards. Two to eight people share a 24-card deck, from 9 up to ace. You play cards in the order received, using the next card each time."),
            rule_section(:play, "Playing a battle",
              "Press Enter on your turn. Once everyone has played one card, the highest wins the whole group. Ranks ascend from 9, 10, jack, queen and king to ace. Suits do not matter.",
              "Won cards are put in random order beneath your remaining cards, ready for later battles. C reads cards currently on the table; V repeats the previous result."),
            rule_section(:tie, "War on a tie",
              "A tie for the highest card starts a war. Only the tied players take part, but all cards from the battle remain at stake.",
              "On your turn in a war, press Enter again to contribute one hidden card and one revealed card. The highest revealed card wins the entire pile, including hidden cards. Another tie starts another war.",
              "With only one card left, play it as the revealed card without adding a hidden one. A player with no cards cannot continue. If only one player has enough to keep going, they take the pile immediately. If nobody can continue, the pile carries over to the next battle."),
            rule_section(:ending, "Ending the game",
              "After a battle is settled, players without cards are eliminated. The last player left wins. If nobody has cards left, the game is a draw.",
              "A game lasts at most 20 battles. If nobody has won by then, the largest card count wins; equal largest counts draw. E reads everyone's card count, and Ctrl+T reads the battle number and limit."),
            rule_section(:variants, "Deck and length",
              "The host can change these before starting:",
              "- Use a full 52-card deck, from 2 to ace. Number cards still ascend normally, followed by jack, queen, king and ace.",
              "- Increase the battle limit from 20, up to 300. The largest card count still decides at the limit."),
            rule_section(:controls, "Keyboard shortcuts",
              "Enter: play your top card.",
              "Space: play your top card.",
              "C: read table cards, yours first.",
              "E: read card counts.",
              "V: read the last battle result.",
              "T: read whose turn it is.",
              "Ctrl+T: read the battle number and limit.")
          ]
        when "es"
          [
            rule_section(:aim, "Objetivo",
              "En War intentas capturar las cartas de los otros jugadores. Juegan de dos a ocho personas, reparti\u00E9ndose una baraja de 24 cartas, del nueve al as. No eliges qu\u00E9 carta jugar: las usas en el orden recibido, una tras otra."),
            rule_section(:play, "Los enfrentamientos",
              "Pulsa Enter cuando te toque. Una vez que todos han puesto una carta, la m\u00E1s alta se lleva todas las de ese enfrentamiento. De menor a mayor van nueve, diez, jota, reina, rey y as. Los palos no influyen.",
              "Las cartas capturadas se colocan en orden aleatorio debajo de las que a\u00FAn ten\u00EDas. Despu\u00E9s empieza otro enfrentamiento. C consulta las cartas actuales de la mesa y V el resultado del anterior."),
            rule_section(:tie, "Guerra tras un empate",
              "Un empate en la carta m\u00E1s alta inicia una guerra. Solo participan quienes jugaron ese valor, pero se disputan todas las cartas del enfrentamiento.",
              "Cuando te toque en una guerra, pulsa Enter de nuevo. A\u00F1ades una carta boca abajo y otra descubierta. La descubierta m\u00E1s alta gana todo, incluidas las cartas ocultas. Otro empate provoca otra guerra.",
              "Si solo te queda una carta, se usa descubierta, sin a\u00F1adir una oculta. Quien no tenga cartas no puede continuar. Si solo a una persona le quedan suficientes para seguir, gana todo inmediatamente. Si nadie puede, las cartas pendientes pasan al siguiente enfrentamiento."),
            rule_section(:ending, "Final de partida",
              "Al resolverse un enfrentamiento se elimina a quienes no tienen cartas. Si solo queda una persona, gana. Si todos se quedan sin cartas, hay empate.",
              "La partida dura como m\u00E1ximo 20 enfrentamientos. Si no se ha decidido antes, gana quien tenga m\u00E1s cartas; varios m\u00E1ximos iguales empatan. E cuenta las cartas y Ctrl+T consulta el n\u00FAmero de enfrentamiento y el l\u00EDmite."),
            rule_section(:variants, "Baraja y duraci\u00F3n",
              "Antes de empezar puedes cambiar estas opciones:",
              "- Baraja completa: 52 cartas, del dos al as. El orden sigue siendo los n\u00FAmeros, jota, reina, rey y as.",
              "- L\u00EDmite de enfrentamientos: puedes aumentarlo desde 20 hasta 300. Al alcanzarlo gana quien tenga m\u00E1s cartas."),
            rule_section(:controls, "Teclas de referencia",
              "Enter: jugar la carta superior.",
              "Espacio: jugar la carta superior.",
              "C: leer las cartas de la mesa, primero las tuyas y despu\u00E9s las rivales.",
              "E: contar las cartas de los jugadores.",
              "V: consultar el \u00FAltimo enfrentamiento.",
              "T: consultar de qui\u00E9n es el turno.",
              "Ctrl+T: consultar el enfrentamiento actual y su l\u00EDmite.")
          ]
        when "pl"
          [
            rule_section(:aim, "Cel gry",
              "W wojnie pr\u00F3bujesz zdoby\u0107 karty pozosta\u0142ych graczy. Graj\u0105 od dw\u00F3ch do o\u015Bmiu os\u00F3b, a ka\u017Cdy dostaje cz\u0119\u015B\u0107 talii 24 kart, od dziewi\u0105tki do asa. Grasz kartami w otrzymanej kolejno\u015Bci: przy ka\u017Cdym ruchu zagrasz nast\u0119pn\u0105."),
            rule_section(:play, "Przebieg gry",
              "W swojej turze naci\u015Bnij Enter. Gdy wszyscy zagraj\u0105 po jednej karcie, osoba z najwy\u017Csz\u0105 bierze wszystkie karty z tego starcia. Od najni\u017Cszej s\u0105 to dziewi\u0105tka, dziesi\u0105tka, walet, dama, kr\u00F3l i as. Kolory nie wp\u0142ywaj\u0105 na wynik.",
              "Zdobyte karty trafiaj\u0105 w losowej kolejno\u015Bci pod sp\u00F3d twoich pozosta\u0142ych kart. Nast\u0119pnie rozgrywacie kolejne starcie. Klawiszem C sprawdzisz karty obecnie wy\u0142o\u017Cone na stole, a klawiszem V wynik poprzedniego starcia."),
            rule_section(:tie, "Wojna po remisie",
              "Remis na najwy\u017Cszej karcie rozpoczyna wojn\u0119. Uczestnicz\u0105 w niej tylko osoby, kt\u00F3re zagra\u0142y t\u0119 warto\u015B\u0107, ale walcz\u0105 o wszystkie karty z dotychczasowego starcia.",
              "Gdy podczas wojny przyjdzie twoja kolej, ponownie naci\u015Bnij Enter. Do\u0142o\u017Cysz jedn\u0105 kart\u0119 zakryt\u0105 i jedn\u0105 odkryt\u0105. Gracz z najwy\u017Csz\u0105 odkryt\u0105 kart\u0105 zabiera wszystkie karty z tego starcia, tak\u017Ce zakryte. Kolejny remis oznacza nast\u0119pn\u0105 wojn\u0119.",
              "Je\u015Bli zosta\u0142a ci tylko jedna karta, zagrywasz j\u0105 do por\u00F3wnania, bez dok\u0142adania zakrytej. Kto nie ma ju\u017C kart, nie mo\u017Ce kontynuowa\u0107. Gdy tylko jednej osobie wystarczy ich do dalszej gry, od razu zabiera ca\u0142o\u015B\u0107. Je\u015Bli nie wystarczy nikomu, zdobycz przechodzi do nast\u0119pnego starcia."),
            rule_section(:ending, "Koniec gry",
              "Po rozstrzygni\u0119ciu starcia gracze bez kart odpadaj\u0105. Je\u015Bli zosta\u0142 tylko jeden, wygrywa. Gdyby bez kart zostali wszyscy, gra ko\u0144czy si\u0119 remisem.",
              "Partia trwa najwy\u017Cej 20 star\u0107. Je\u017Celi wcze\u015Bniej nie zostanie wy\u0142oniony zwyci\u0119zca, wygrywa gracz z najwi\u0119ksz\u0105 liczb\u0105 kart; r\u00F3wna najwi\u0119ksza liczba oznacza remis. E podaje liczb\u0119 kart ka\u017Cdego gracza, a Ctrl+T numer starcia i limit."),
            rule_section(:variants, "Inna talia i d\u0142ugo\u015B\u0107 gry",
              "W ustawieniach sto\u0142u przed gr\u0105 mo\u017Cna zmieni\u0107 tali\u0119 oraz d\u0142ugo\u015B\u0107 partii:",
              "- Pe\u0142na talia zawiera 52 karty, od dw\u00F3jki do asa. Warto\u015Bci por\u00F3wnuje si\u0119 tak samo: po kolejnych numerach nast\u0119puj\u0105 walet, dama, kr\u00F3l i as.",
              "- Limit star\u0107 mo\u017Cna zwi\u0119kszy\u0107 z 20 do najwy\u017Cej 300. Po jego osi\u0105gni\u0119ciu nadal wygrywa osoba z najwi\u0119ksz\u0105 liczb\u0105 kart."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "Enter: zagraj wierzchni\u0105 kart\u0119.",
              "Spacja: zagraj wierzchni\u0105 kart\u0119.",
              "C: odczytaj karty na stole, najpierw swoje, potem przeciwnik\u00F3w.",
              "E: odczytaj liczby kart graczy.",
              "V: odczytaj wynik ostatniego starcia.",
              "T: odczytaj, czyja jest tura.",
              "Ctrl+T: odczytaj numer bie\u017C\u0105cego starcia i limit star\u0107.")
          ]
        when "ru"
          [
            rule_section(:aim, "\u0426\u0435\u043B\u044C \u0438\u0433\u0440\u044B",
              "\u0412 \u00AB\u0412\u043E\u0439\u043D\u0435\u00BB \u043D\u0443\u0436\u043D\u043E \u0437\u0430\u0431\u0440\u0430\u0442\u044C \u043A\u0430\u0440\u0442\u044B \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u043E\u0432. \u041E\u0442 \u0434\u0432\u0443\u0445 \u0434\u043E \u0432\u043E\u0441\u044C\u043C\u0438 \u0438\u0433\u0440\u043E\u043A\u043E\u0432 \u0434\u0435\u043B\u044F\u0442 \u043A\u043E\u043B\u043E\u0434\u0443 \u0438\u0437 24 \u043A\u0430\u0440\u0442 \u2014 \u043E\u0442 \u0434\u0435\u0432\u044F\u0442\u043A\u0438 \u0434\u043E \u0442\u0443\u0437\u0430. \u0412\u044B\u0431\u0438\u0440\u0430\u0442\u044C \u043A\u0430\u0440\u0442\u0443 \u0434\u043B\u044F \u0445\u043E\u0434\u0430 \u043D\u0435 \u043F\u0440\u0438\u0445\u043E\u0434\u0438\u0442\u0441\u044F: \u043A\u0430\u0440\u0442\u044B \u0440\u0430\u0437\u044B\u0433\u0440\u044B\u0432\u0430\u044E\u0442\u0441\u044F \u043F\u043E \u043F\u043E\u0440\u044F\u0434\u043A\u0443, \u043A\u0430\u0436\u0434\u044B\u0439 \u0440\u0430\u0437 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0430\u044F."),
            rule_section(:play, "\u041E\u0431\u044B\u0447\u043D\u043E\u0435 \u0441\u0440\u0430\u0436\u0435\u043D\u0438\u0435",
              "\u0412 \u0441\u0432\u043E\u0439 \u0445\u043E\u0434 \u043D\u0430\u0436\u043C\u0438\u0442\u0435 Enter. \u041A\u043E\u0433\u0434\u0430 \u043A\u0430\u0436\u0434\u044B\u0439 \u0432\u044B\u043B\u043E\u0436\u0438\u0442 \u043F\u043E \u043A\u0430\u0440\u0442\u0435, \u043E\u0431\u043B\u0430\u0434\u0430\u0442\u0435\u043B\u044C \u0441\u0430\u043C\u043E\u0439 \u0441\u0442\u0430\u0440\u0448\u0435\u0439 \u0437\u0430\u0431\u0438\u0440\u0430\u0435\u0442 \u0432\u0441\u0435 \u043A\u0430\u0440\u0442\u044B \u0441\u0440\u0430\u0436\u0435\u043D\u0438\u044F. \u041F\u043E\u0440\u044F\u0434\u043E\u043A \u043E\u0442 \u043C\u043B\u0430\u0434\u0448\u0435\u0439 \u043A \u0441\u0442\u0430\u0440\u0448\u0435\u0439: \u0434\u0435\u0432\u044F\u0442\u043A\u0430, \u0434\u0435\u0441\u044F\u0442\u043A\u0430, \u0432\u0430\u043B\u0435\u0442, \u0434\u0430\u043C\u0430, \u043A\u043E\u0440\u043E\u043B\u044C, \u0442\u0443\u0437. \u041C\u0430\u0441\u0442\u044C \u0437\u043D\u0430\u0447\u0435\u043D\u0438\u044F \u043D\u0435 \u0438\u043C\u0435\u0435\u0442.",
              "\u0412\u044B\u0438\u0433\u0440\u0430\u043D\u043D\u044B\u0435 \u043A\u0430\u0440\u0442\u044B \u0432 \u0441\u043B\u0443\u0447\u0430\u0439\u043D\u043E\u043C \u043F\u043E\u0440\u044F\u0434\u043A\u0435 \u043A\u043B\u0430\u0434\u0443\u0442\u0441\u044F \u043F\u043E\u0441\u043B\u0435 \u0432\u0430\u0448\u0438\u0445 \u043E\u0441\u0442\u0430\u0432\u0448\u0438\u0445\u0441\u044F \u043A\u0430\u0440\u0442, \u0438 \u043D\u0430\u0447\u0438\u043D\u0430\u0435\u0442\u0441\u044F \u043D\u043E\u0432\u043E\u0435 \u0441\u0440\u0430\u0436\u0435\u043D\u0438\u0435. \u041D\u0430\u0436\u043C\u0438\u0442\u0435 C, \u0447\u0442\u043E\u0431\u044B \u0443\u0437\u043D\u0430\u0442\u044C, \u043A\u0430\u043A\u0438\u0435 \u043A\u0430\u0440\u0442\u044B \u0441\u0435\u0439\u0447\u0430\u0441 \u043D\u0430 \u0441\u0442\u043E\u043B\u0435, \u0438\u043B\u0438 V, \u0447\u0442\u043E\u0431\u044B \u0443\u0441\u043B\u044B\u0448\u0430\u0442\u044C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442 \u043F\u0440\u0435\u0434\u044B\u0434\u0443\u0449\u0435\u0433\u043E \u0441\u0440\u0430\u0436\u0435\u043D\u0438\u044F."),
            rule_section(:tie, "\u0421\u043F\u043E\u0440 \u0437\u0430 \u043E\u0434\u0438\u043D\u0430\u043A\u043E\u0432\u044B\u0435 \u043A\u0430\u0440\u0442\u044B",
              "\u0415\u0441\u043B\u0438 \u0441\u0430\u043C\u044B\u0435 \u0441\u0442\u0430\u0440\u0448\u0438\u0435 \u043A\u0430\u0440\u0442\u044B \u043E\u043A\u0430\u0437\u0430\u043B\u0438\u0441\u044C \u043E\u0434\u0438\u043D\u0430\u043A\u043E\u0432\u044B\u043C\u0438, \u043D\u0430\u0447\u0438\u043D\u0430\u0435\u0442\u0441\u044F \u0432\u043E\u0439\u043D\u0430. \u0412 \u043D\u0435\u0439 \u0443\u0447\u0430\u0441\u0442\u0432\u0443\u044E\u0442 \u0442\u043E\u043B\u044C\u043A\u043E \u0432\u043B\u0430\u0434\u0435\u043B\u044C\u0446\u044B \u044D\u0442\u0438\u0445 \u043A\u0430\u0440\u0442, \u043D\u043E \u0440\u0430\u0437\u044B\u0433\u0440\u044B\u0432\u0430\u044E\u0442\u0441\u044F \u0432\u0441\u0435 \u043A\u0430\u0440\u0442\u044B \u0443\u0436\u0435 \u043D\u0430\u0447\u0430\u0442\u043E\u0433\u043E \u0441\u0440\u0430\u0436\u0435\u043D\u0438\u044F.",
              "\u041A\u043E\u0433\u0434\u0430 \u0441\u043D\u043E\u0432\u0430 \u043F\u0440\u0438\u0434\u0451\u0442 \u0432\u0430\u0448 \u0445\u043E\u0434, \u043D\u0430\u0436\u043C\u0438\u0442\u0435 Enter. \u0412\u044B \u043F\u043E\u043B\u043E\u0436\u0438\u0442\u0435 \u043E\u0434\u043D\u0443 \u043A\u0430\u0440\u0442\u0443 \u0437\u0430\u043A\u0440\u044B\u0442\u043E\u0439 \u0438 \u0435\u0449\u0451 \u043E\u0434\u043D\u0443 \u043E\u0442\u043A\u0440\u044B\u0442\u043E\u0439. \u0421\u0430\u043C\u0430\u044F \u0441\u0442\u0430\u0440\u0448\u0430\u044F \u043E\u0442\u043A\u0440\u044B\u0442\u0430\u044F \u043A\u0430\u0440\u0442\u0430 \u0437\u0430\u0431\u0438\u0440\u0430\u0435\u0442 \u0432\u0441\u044E \u0441\u0442\u0430\u0432\u043A\u0443, \u0432\u043A\u043B\u044E\u0447\u0430\u044F \u0437\u0430\u043A\u0440\u044B\u0442\u044B\u0435 \u043A\u0430\u0440\u0442\u044B. \u0415\u0441\u043B\u0438 \u0441\u043D\u043E\u0432\u0430 \u043D\u0438\u0447\u044C\u044F, \u0432\u043E\u0439\u043D\u0430 \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0430\u0435\u0442\u0441\u044F \u0442\u0435\u043C \u0436\u0435 \u0441\u043F\u043E\u0441\u043E\u0431\u043E\u043C.",
              "\u0421 \u0435\u0434\u0438\u043D\u0441\u0442\u0432\u0435\u043D\u043D\u043E\u0439 \u043E\u0441\u0442\u0430\u0432\u0448\u0435\u0439\u0441\u044F \u043A\u0430\u0440\u0442\u043E\u0439 \u0432\u044B \u0438\u0433\u0440\u0430\u0435\u0442\u0435 \u0435\u0451 \u043E\u0442\u043A\u0440\u044B\u0442\u043E, \u043D\u0435 \u0434\u043E\u0431\u0430\u0432\u043B\u044F\u044F \u0437\u0430\u043A\u0440\u044B\u0442\u0443\u044E. \u0411\u0435\u0437 \u043A\u0430\u0440\u0442 \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0430\u0442\u044C \u043D\u0435\u043B\u044C\u0437\u044F. \u0415\u0441\u043B\u0438 \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0438\u0442\u044C \u0441\u043F\u043E\u0441\u043E\u0431\u0435\u043D \u0442\u043E\u043B\u044C\u043A\u043E \u043E\u0434\u0438\u043D \u0438\u0433\u0440\u043E\u043A, \u043E\u043D \u0441\u0440\u0430\u0437\u0443 \u0437\u0430\u0431\u0438\u0440\u0430\u0435\u0442 \u0432\u0441\u0451. \u0415\u0441\u043B\u0438 \u043A\u0430\u0440\u0442 \u043D\u0435 \u0445\u0432\u0430\u0442\u0430\u0435\u0442 \u043D\u0438\u043A\u043E\u043C\u0443, \u043D\u0430\u043A\u043E\u043F\u043B\u0435\u043D\u043D\u044B\u0435 \u043A\u0430\u0440\u0442\u044B \u043E\u0441\u0442\u0430\u044E\u0442\u0441\u044F \u0434\u043B\u044F \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0435\u0433\u043E \u0441\u0440\u0430\u0436\u0435\u043D\u0438\u044F."),
            rule_section(:ending, "\u041A\u0442\u043E \u043F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442",
              "\u041F\u043E\u0441\u043B\u0435 \u0437\u0430\u0432\u0435\u0440\u0448\u0435\u043D\u0438\u044F \u0441\u0440\u0430\u0436\u0435\u043D\u0438\u044F \u0438\u0433\u0440\u043E\u043A\u0438 \u0431\u0435\u0437 \u043A\u0430\u0440\u0442 \u0432\u044B\u0431\u044B\u0432\u0430\u044E\u0442. \u041F\u043E\u0441\u043B\u0435\u0434\u043D\u0438\u0439 \u043E\u0441\u0442\u0430\u0432\u0448\u0438\u0439\u0441\u044F \u0438\u0433\u0440\u043E\u043A \u043F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442. \u0415\u0441\u043B\u0438 \u0431\u0435\u0437 \u043A\u0430\u0440\u0442 \u043E\u043A\u0430\u0436\u0443\u0442\u0441\u044F \u0432\u0441\u0435, \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442 \u2014 \u043D\u0438\u0447\u044C\u044F.",
              "\u041F\u043E \u0443\u043C\u043E\u043B\u0447\u0430\u043D\u0438\u044E \u043F\u0430\u0440\u0442\u0438\u044F \u043E\u0433\u0440\u0430\u043D\u0438\u0447\u0435\u043D\u0430 20 \u0441\u0440\u0430\u0436\u0435\u043D\u0438\u044F\u043C\u0438. \u0415\u0441\u043B\u0438 \u0440\u0430\u043D\u044C\u0448\u0435 \u043F\u043E\u0431\u0435\u0434\u0438\u0442\u0435\u043B\u044C \u043D\u0435 \u043E\u043F\u0440\u0435\u0434\u0435\u043B\u0438\u043B\u0441\u044F, \u043F\u043E \u043E\u043A\u043E\u043D\u0447\u0430\u043D\u0438\u0438 \u043B\u0438\u043C\u0438\u0442\u0430 \u0441\u0440\u0430\u0432\u043D\u0438\u0432\u0430\u044E\u0442 \u043A\u043E\u043B\u0438\u0447\u0435\u0441\u0442\u0432\u043E \u043A\u0430\u0440\u0442. \u0411\u043E\u043B\u044C\u0448\u0435 \u0432\u0441\u0435\u0445 \u2014 \u043F\u043E\u0431\u0435\u0434\u0430, \u043E\u0434\u0438\u043D\u0430\u043A\u043E\u0432\u044B\u0439 \u043B\u0443\u0447\u0448\u0438\u0439 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442 \u2014 \u043D\u0438\u0447\u044C\u044F. \u041A\u043B\u0430\u0432\u0438\u0448\u0430 E \u0441\u043E\u043E\u0431\u0449\u0430\u0435\u0442 \u0447\u0438\u0441\u043B\u043E \u043A\u0430\u0440\u0442 \u0443 \u0438\u0433\u0440\u043E\u043A\u043E\u0432, \u0430 Ctrl+T \u2014 \u043D\u043E\u043C\u0435\u0440 \u0441\u0440\u0430\u0436\u0435\u043D\u0438\u044F \u0438 \u043F\u0440\u0435\u0434\u0435\u043B \u043F\u0430\u0440\u0442\u0438\u0438."),
            rule_section(:variants, "\u041A\u043E\u043B\u043E\u0434\u0430 \u0438 \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0438\u0442\u0435\u043B\u044C\u043D\u043E\u0441\u0442\u044C",
              "\u0414\u043E \u043D\u0430\u0447\u0430\u043B\u0430 \u043F\u0430\u0440\u0442\u0438\u0438 \u0432 \u043D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0430\u0445 \u0441\u0442\u043E\u043B\u0430 \u043C\u043E\u0436\u043D\u043E \u0438\u0437\u043C\u0435\u043D\u0438\u0442\u044C \u0434\u0432\u0430 \u0443\u0441\u043B\u043E\u0432\u0438\u044F:",
              "- \u041F\u043E\u043B\u043D\u0430\u044F \u043A\u043E\u043B\u043E\u0434\u0430 \u0441\u043E\u0434\u0435\u0440\u0436\u0438\u0442 52 \u043A\u0430\u0440\u0442\u044B, \u043E\u0442 \u0434\u0432\u043E\u0439\u043A\u0438 \u0434\u043E \u0442\u0443\u0437\u0430. \u0421\u0442\u0430\u0440\u0448\u0438\u043D\u0441\u0442\u0432\u043E \u0442\u043E \u0436\u0435: \u043F\u043E\u0441\u043B\u0435 \u043A\u0430\u0440\u0442 \u0441 \u0447\u0438\u0441\u043B\u0430\u043C\u0438 \u0438\u0434\u0443\u0442 \u0432\u0430\u043B\u0435\u0442, \u0434\u0430\u043C\u0430, \u043A\u043E\u0440\u043E\u043B\u044C \u0438 \u0442\u0443\u0437.",
              "- \u041B\u0438\u043C\u0438\u0442 \u0441\u0440\u0430\u0436\u0435\u043D\u0438\u0439 \u043C\u043E\u0436\u043D\u043E \u0443\u0432\u0435\u043B\u0438\u0447\u0438\u0442\u044C \u0441 20 \u0434\u043E 300. \u041F\u043E \u0434\u043E\u0441\u0442\u0438\u0436\u0435\u043D\u0438\u0438 \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u043E\u0433\u043E \u043F\u0440\u0435\u0434\u0435\u043B\u0430 \u043F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u0438\u0433\u0440\u043E\u043A \u0441 \u043D\u0430\u0438\u0431\u043E\u043B\u044C\u0448\u0438\u043C \u0447\u0438\u0441\u043B\u043E\u043C \u043A\u0430\u0440\u0442."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0448\u0438 \u0443\u043F\u0440\u0430\u0432\u043B\u0435\u043D\u0438\u044F",
              "Enter: \u0441\u044B\u0433\u0440\u0430\u0442\u044C \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0443\u044E \u043A\u0430\u0440\u0442\u0443.",
              "\u041F\u0440\u043E\u0431\u0435\u043B: \u0441\u044B\u0433\u0440\u0430\u0442\u044C \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0443\u044E \u043A\u0430\u0440\u0442\u0443.",
              "C: \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u043A\u0430\u0440\u0442\u044B \u043D\u0430 \u0441\u0442\u043E\u043B\u0435 \u2014 \u0441\u043D\u0430\u0447\u0430\u043B\u0430 \u0441\u0432\u043E\u044E, \u0437\u0430\u0442\u0435\u043C \u043A\u0430\u0440\u0442\u044B \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u043E\u0432.",
              "E: \u0443\u0437\u043D\u0430\u0442\u044C \u043A\u043E\u043B\u0438\u0447\u0435\u0441\u0442\u0432\u043E \u043A\u0430\u0440\u0442 \u0443 \u043A\u0430\u0436\u0434\u043E\u0433\u043E \u0438\u0433\u0440\u043E\u043A\u0430.",
              "V: \u0443\u0437\u043D\u0430\u0442\u044C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442 \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0435\u0433\u043E \u0441\u0440\u0430\u0436\u0435\u043D\u0438\u044F.",
              "T: \u0443\u0437\u043D\u0430\u0442\u044C, \u0447\u0435\u0439 \u0441\u0435\u0439\u0447\u0430\u0441 \u0445\u043E\u0434.",
              "Ctrl+T: \u0443\u0437\u043D\u0430\u0442\u044C \u043D\u043E\u043C\u0435\u0440 \u0442\u0435\u043A\u0443\u0449\u0435\u0433\u043E \u0441\u0440\u0430\u0436\u0435\u043D\u0438\u044F \u0438 \u043B\u0438\u043C\u0438\u0442.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
