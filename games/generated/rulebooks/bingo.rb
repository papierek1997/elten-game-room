# Generated from tools/data/rulebooks/bingo.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Bingo
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:aim, GameRoomRules.translate("Bingo tickets and goals"),
            GameRoomRules.translate("Each player receives one ticket. Balls are called without replacement. Complete the announced pattern. All tickets use the same calls; players completing the final goal together share a draw.")),
          rule_section(:variants, GameRoomRules.translate("Variants"),
            GameRoomRules.translate("30-ball: a 3 by 3 ticket, three numbers from each range 1\u201310, 11\u201320 and 21\u201330. Cover all nine to win. There is no free square."),
            GameRoomRules.translate("75-ball: a 5 by 5 ticket. B, I, N, G and O use ranges 1\u201315, 16\u201330, 31\u201345, 46\u201360 and 61\u201375. The centre is free. 80-ball uses a 4 by 4 ticket with columns 1\u201320, 21\u201340, 41\u201360 and 61\u201380. For these variants choose any horizontal, vertical or diagonal line, four corners or full house at table creation."),
            GameRoomRules.translate("90-ball: three rows and nine columns, five numbers per row and fifteen per ticket. Columns cover 1\u20139, 10\u201319, through 70\u201379 and 80\u201390; numbers increase down each column. Play for one horizontal line, then two, then full house on the same ticket. Earlier winners are announced; full house decides the match.")),
          rule_section(:marking, GameRoomRules.translate("Marking and calling bingo"),
            GameRoomRules.translate("Automatic mode marks tickets and detects winning patterns. Calls are paced at 3\u201330 seconds, default five. Manual mode waits for every player to finish the call. Mark only called numbers on your ticket, then claim bingo or confirm ready. Claims from that call are checked together, so network speed does not select a winner. A wrong claim changes nothing."),
            GameRoomRules.translate("After a 90-ball stage win in manual mode, the next goal can be claimed on the same call; otherwise confirm ready again to continue drawing. Called numbers may be marked later. An empty drum without a valid claim ends in a draw. The per-call ready barrier is a Power Games accessibility adaptation. Tickets and calls use the shared server-backed game executor.")),
          rule_section(:controls, GameRoomRules.translate("Controls"),
            GameRoomRules.translate("Use arrows to read the ticket. In manual mode Enter marks a called number, M enters a number, B claims bingo and R confirms ready. The actions list also has Claim bingo and Ready. L repeats the last ball; D browses calls. Tab changes fields. F1 shows current shortcuts, Ctrl+F1 the rules. History, chat and volume use the normal Power Games keys."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:aim, "Karta a c\u00EDl hry",
              "Ka\u017Ed\u00FD dostane jednu kartu a v\u0161ichni sly\u0161\u00ED stejn\u00E1 \u010D\u00EDsla. V\u00FDchoz\u00ED hra m\u00E1 90 m\u00ED\u010Dk\u016F. Nejd\u0159\u00EDv jde o jeden \u00FApln\u00FD \u0159\u00E1dek, potom o dva \u0159\u00E1dky a nakonec o celou kartu. Vyhr\u00E1v\u00E1 ten, kdo ji vypln\u00ED prvn\u00ED. Pokud ji v\u00EDce hr\u00E1\u010D\u016F vypln\u00ED p\u0159i stejn\u00E9m \u010D\u00EDsle, d\u011Bl\u00ED se o v\u00FDhru.",
              "Kartu proch\u00E1z\u00ED\u0161 \u0161ipkami. Ve v\u00FDchoz\u00ED h\u0159e se \u010D\u00EDsla ozna\u010Duj\u00ED automaticky a hra hl\u00E1s\u00ED v\u00EDt\u011Bze jednotliv\u00FDch etap. \u010C\u00EDsla se neopakuj\u00ED. L p\u0159e\u010Dte posledn\u00ED \u010D\u00EDslo, D otev\u0159e seznam v\u0161ech vylosovan\u00FDch \u010D\u00EDsel."),
            rule_section(:marking, "Ru\u010Dn\u00ED ozna\u010Dov\u00E1n\u00ED",
              "V ru\u010Dn\u00EDm re\u017Eimu naje\u010F \u0161ipkami na vylosovan\u00E9 \u010D\u00EDslo na kart\u011B a stiskni Enter. \u010C\u00EDslo m\u016F\u017Ee\u0161 tak\u00E9 napsat po stisknut\u00ED M. Ozna\u010Dit lze i \u010D\u00EDsla z d\u0159\u00EDv\u011Bj\u0161\u00EDho losov\u00E1n\u00ED.",
              "Pokud m\u00E1\u0161 po\u017Eadovan\u00FD obrazec, ohlas bingo kl\u00E1vesou B. Jinak stiskni R, a\u017E bude\u0161 s ozna\u010Dov\u00E1n\u00EDm hotov\u00FD. Dal\u0161\u00ED \u010D\u00EDslo se losuje, a\u017E skon\u010D\u00ED v\u0161ichni. Hl\u00E1\u0161en\u00ED u stejn\u00E9ho \u010D\u00EDsla se posuzuj\u00ED spole\u010Dn\u011B, tak\u017Ee rychlost stisku B nerozhoduje.",
              "Po v\u00FDh\u0159e za jeden \u010Di dva \u0159\u00E1dky u 90 m\u00ED\u010Dk\u016F zkontroluj dal\u0161\u00ED c\u00EDl. Pokud ho u\u017E m\u00E1\u0161, ohlas ho je\u0161t\u011B u stejn\u00E9ho \u010D\u00EDsla. Jinak znovu stiskni R. Pokud m\u00ED\u010Dky dojdou a nikdo spr\u00E1vn\u011B neohl\u00E1s\u00ED posledn\u00ED obrazec, hra skon\u010D\u00ED rem\u00EDzou."),
            rule_section(:variants, "Varianty binga",
              "P\u0159i vytv\u00E1\u0159en\u00ED stolu m\u016F\u017Ee\u0161 nastavit odstup mezi automatick\u00FDmi losov\u00E1n\u00EDmi. V\u00FDchoz\u00ED odstup je p\u011Bt sekund.",
              "- 90 m\u00ED\u010Dk\u016F: t\u0159i \u0159\u00E1dky po p\u011Bti \u010D\u00EDslech v dev\u00EDti sloupc\u00EDch. V\u00FDhry za jeden a dva \u0159\u00E1dky se hl\u00E1s\u00ED pr\u016Fb\u011B\u017En\u011B; rozhoduje cel\u00E1 karta.",
              "- 75 m\u00ED\u010Dk\u016F: p\u011Bt \u0159\u00E1dk\u016F a sloupce B, I, N, G, O. Voln\u00FD st\u0159ed se po\u010D\u00EDt\u00E1 od za\u010D\u00E1tku.",
              "- 80 m\u00ED\u010Dk\u016F: \u010Dty\u0159i \u0159\u00E1dky a \u010Dty\u0159i sloupce. U 75 a 80 m\u00ED\u010Dk\u016F zvol\u00ED\u0161 \u0159\u00E1dek, sloupec \u010Di \u00FAhlop\u0159\u00ED\u010Dku, \u010Dty\u0159i rohy, nebo celou kartu.",
              "- 30 m\u00ED\u010Dk\u016F: t\u0159i \u0159\u00E1dky a t\u0159i sloupce bez voln\u00E9ho pole. Vyhr\u00E1v\u00E1 cel\u00E1 karta."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "L: p\u0159e\u010D\u00EDst posledn\u00ED \u010D\u00EDslo",
              "D: proch\u00E1zet vylosovan\u00E1 \u010D\u00EDsla",
              "Enter na kart\u011B: ozna\u010Dit \u010D\u00EDslo v ru\u010Dn\u00EDm re\u017Eimu",
              "M: zadat \u010D\u00EDslo k ozna\u010Den\u00ED",
              "B: ohl\u00E1sit bingo",
              "R: ukon\u010Dit ozna\u010Dov\u00E1n\u00ED")
          ]
        when "en"
          [
            rule_section(:aim, "Tickets and goals",
              "Each player gets one ticket and hears the same calls. The default game uses 90 balls. It plays for one complete row, then two rows, then a full ticket. The first full ticket wins; players who complete it on the same call share the win.",
              "Use the arrows to inspect your ticket. By default, numbers are marked as they are called and the game announces winners automatically. Numbers are not repeated. L reads the last ball; D opens the list of called numbers."),
            rule_section(:marking, "Manual marking",
              "In a manual game, move to a called number with the arrows and press Enter to mark it. You can also press M and type the number. A number called earlier may still be marked.",
              "Press B if your marks complete the pattern. Otherwise press R when you have finished marking. The next ball waits for everyone. Claims on the same ball are checked together; pressing B faster does not break a tie.",
              "After a line or two-line win in 90-ball bingo, check the next goal. If you already have that pattern, claim it on the same ball; otherwise press R again. If there are no balls left and nobody claims the final pattern, the game draws."),
            rule_section(:variants, "Bingo variants",
              "When creating the table, you can change the interval between automatic calls. The default is five seconds.",
              "- 90 balls: three rows with five numbers in each, spread across nine columns. The one- and two-row winners are announced on the way; the full ticket decides the game.",
              "- 75 balls: five rows and five columns, B, I, N, G and O. The free centre counts from the start.",
              "- 80 balls: four rows and four columns. In the 75- and 80-ball games, choose a row, column or diagonal, four corners, or a full ticket.",
              "- 30 balls: three rows and three columns, with no free space. A full ticket wins."),
            rule_section(:controls, "Keyboard shortcuts",
              "L: read the last ball",
              "D: browse called numbers",
              "Enter on a ticket: mark a number in manual mode",
              "M: enter a number to mark",
              "B: claim bingo",
              "R: finish marking")
          ]
        when "es"
          [
            rule_section(:aim, "Cart\u00F3n y objetivos",
              "Cada persona recibe un cart\u00F3n y oye las mismas bolas. La partida normal usa 90 bolas. Primero se juega a completar una fila, luego dos y por \u00FAltimo todo el cart\u00F3n. Gana quien lo complete antes. Si varios lo consiguen con la misma bola, comparten la victoria.",
              "Recorre el cart\u00F3n con las flechas. Por defecto, el juego marca los n\u00FAmeros y anuncia autom\u00E1ticamente qui\u00E9n completa cada objetivo. Los n\u00FAmeros no se repiten. L lee la \u00FAltima bola y D abre la lista de n\u00FAmeros cantados."),
            rule_section(:marking, "Marcado manual",
              "Si marcas a mano, despl\u00E1zate con las flechas hasta un n\u00FAmero cantado de tu cart\u00F3n y pulsa Intro. Tambi\u00E9n puedes pulsar M y escribir el n\u00FAmero. Puedes marcar n\u00FAmeros que salieron en bolas anteriores.",
              "Si ya tienes la figura pedida, canta bingo con B. Si no, pulsa R cuando termines de marcar. La siguiente bola espera a que todos hayan terminado. Los bingos cantados en la misma bola se comprueban juntos, as\u00ED que no tienes que pulsar B antes que los dem\u00E1s.",
              "Tras ganar una o dos filas con 90 bolas, comprueba el siguiente objetivo. Si ya lo tienes, puedes cantarlo con la misma bola; si no, vuelve a pulsar R. Si no quedan bolas y nadie canta correctamente la figura final, hay empate."),
            rule_section(:variants, "Modalidades de bingo",
              "Al crear la mesa puedes ajustar el intervalo entre bolas en el modo autom\u00E1tico. Por defecto son cinco segundos.",
              "- 90 bolas: tres filas con cinco n\u00FAmeros cada una, repartidos en nueve columnas. Se anuncian las victorias de una y dos filas; el cart\u00F3n completo decide la partida.",
              "- 75 bolas: cinco filas y columnas B, I, N, G y O. La casilla libre del centro cuenta desde el principio.",
              "- 80 bolas: cuatro filas y cuatro columnas. En las partidas de 75 y 80 bolas puedes elegir una fila, columna o diagonal, las cuatro esquinas o el cart\u00F3n completo.",
              "- 30 bolas: tres filas y tres columnas, sin casilla libre. Gana el cart\u00F3n completo."),
            rule_section(:controls, "Atajos de teclado",
              "L: leer la \u00FAltima bola",
              "D: consultar los n\u00FAmeros cantados",
              "Intro en el cart\u00F3n: marcar un n\u00FAmero en el modo manual",
              "M: escribir el n\u00FAmero que quieres marcar",
              "B: cantar bingo",
              "R: terminar de marcar")
          ]
        when "pl"
          [
            rule_section(:aim, "Kupon i cel gry",
              "Ka\u017Cdy dostaje kupon, a wszyscy s\u0142ysz\u0105 te same losowania. Domy\u015Blnie gracie 90 kulkami: najpierw o jeden pe\u0142ny wiersz, potem o dwa wiersze i wreszcie o ca\u0142y kupon. Wygrywa osoba, kt\u00F3ra pierwsza zape\u0142ni ca\u0142y kupon. Je\u015Bli kilka os\u00F3b zrobi to przy tej samej kulce, jest remis.",
              "Strza\u0142kami przegl\u0105dasz sw\u00F3j kupon. W domy\u015Blnej grze liczby zaznaczaj\u0105 si\u0119 automatycznie i gra sama og\u0142asza zwyci\u0119zc\u00F3w kolejnych etap\u00F3w. Kulki nie powtarzaj\u0105 si\u0119. Klawiszem L odczytasz ostatni\u0105, a D otworzysz list\u0119 wszystkich wylosowanych liczb."),
            rule_section(:marking, "R\u0119czne zaznaczanie",
              "W r\u0119cznym bingo strza\u0142kami wybierz na kuponie wylosowan\u0105 liczb\u0119 i naci\u015Bnij Enter, \u017Ceby j\u0105 zaznaczy\u0107. Mo\u017Cesz te\u017C wpisa\u0107 liczb\u0119 po naci\u015Bni\u0119ciu M. Wolno zaznaczy\u0107 liczby z wcze\u015Bniejszych losowa\u0144.",
              "Gdy masz wymagany uk\u0142ad, zg\u0142o\u015B bingo klawiszem B. W przeciwnym razie naci\u015Bnij R, \u017Ceby zako\u0144czy\u0107 zaznaczanie. Kolejne losowanie zacznie si\u0119, gdy wszyscy sko\u0144cz\u0105. Zg\u0142oszenia z tej samej kulki rozpatrywane s\u0105 razem; nie trzeba naciska\u0107 B szybciej od innych.",
              "Po wygranej linii lub dw\u00F3ch w grze na 90 kulek sprawd\u017A nowy cel. Je\u015Bli masz ju\u017C potrzebny uk\u0142ad, mo\u017Cesz zg\u0142osi\u0107 go przy tej samej kulce. Je\u015Bli nie, zn\u00F3w naci\u015Bnij R. Gdy kulki si\u0119 sko\u0144cz\u0105 bez poprawnego zg\u0142oszenia fina\u0142owego uk\u0142adu, jest remis."),
            rule_section(:variants, "Odmiany bingo",
              "Przy tworzeniu sto\u0142u mo\u017Cesz zmieni\u0107 odst\u0119p mi\u0119dzy kulkami w trybie automatycznym. Domy\u015Blnie wynosi 5 sekund.",
              "- 90 kulek: kupon ma trzy wiersze po pi\u0119\u0107 liczb, rozmieszczonych w dziewi\u0119ciu kolumnach. Zwyci\u0119stwa za jeden i dwa wiersze s\u0105 og\u0142aszane po drodze; o wygranej decyduje ca\u0142y kupon.",
              "- 75 kulek: kupon ma pi\u0119\u0107 wierszy i kolumny B, I, N, G, O. \u015Arodkowe pole jest wolne i zalicza si\u0119 od pocz\u0105tku.",
              "- 80 kulek: kupon ma cztery wiersze i cztery kolumny. W grze na 75 i 80 kulek wybierasz cel: wiersz, kolumna lub przek\u0105tna, cztery naro\u017Cniki albo ca\u0142y kupon.",
              "- 30 kulek: kupon ma trzy wiersze i trzy kolumny, bez wolnego pola. Wygrywa ca\u0142y kupon."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "L: odczytaj ostatni\u0105 kulk\u0119",
              "D: przegl\u0105daj wylosowane liczby",
              "Enter na kuponie: zaznacz wybran\u0105 liczb\u0119 w trybie r\u0119cznym",
              "M: wpisz liczb\u0119 do zaznaczenia",
              "B: zg\u0142o\u015B bingo",
              "R: zako\u0144cz zaznaczanie")
          ]
        when "ru"
          [
            rule_section(:aim, "\u041A\u0430\u0440\u0442\u043E\u0447\u043A\u0430 \u0438 \u0446\u0435\u043B\u044C \u0438\u0433\u0440\u044B",
              "\u041A\u0430\u0436\u0434\u044B\u0439 \u0438\u0433\u0440\u043E\u043A \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u043A\u0430\u0440\u0442\u043E\u0447\u043A\u0443. \u0412\u0441\u0435 \u0441\u043B\u044B\u0448\u0430\u0442 \u043E\u0434\u043D\u0438 \u0438 \u0442\u0435 \u0436\u0435 \u0447\u0438\u0441\u043B\u0430. \u041F\u043E \u0443\u043C\u043E\u043B\u0447\u0430\u043D\u0438\u044E \u0438\u0433\u0440\u0430\u044E\u0442 \u0441 90 \u0448\u0430\u0440\u0430\u043C\u0438: \u0441\u043D\u0430\u0447\u0430\u043B\u0430 \u043D\u0443\u0436\u043D\u043E \u0437\u0430\u043F\u043E\u043B\u043D\u0438\u0442\u044C \u043E\u0434\u043D\u0443 \u0441\u0442\u0440\u043E\u043A\u0443, \u0437\u0430\u0442\u0435\u043C \u0434\u0432\u0435, \u0430 \u0432 \u043A\u043E\u043D\u0446\u0435 \u0432\u0441\u044E \u043A\u0430\u0440\u0442\u043E\u0447\u043A\u0443. \u041F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u0442\u043E\u0442, \u043A\u0442\u043E \u043F\u0435\u0440\u0432\u044B\u043C \u0437\u0430\u043F\u043E\u043B\u043D\u0438\u0442 \u043A\u0430\u0440\u0442\u043E\u0447\u043A\u0443. \u0417\u0430\u043F\u043E\u043B\u043D\u0438\u0432\u0448\u0438\u0435 \u0435\u0451 \u043D\u0430 \u043E\u0434\u043D\u043E\u043C \u0448\u0430\u0440\u0435 \u0434\u0435\u043B\u044F\u0442 \u043F\u043E\u0431\u0435\u0434\u0443.",
              "\u041F\u0440\u043E\u0441\u043C\u0430\u0442\u0440\u0438\u0432\u0430\u0439 \u043A\u0430\u0440\u0442\u043E\u0447\u043A\u0443 \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438. \u041F\u043E \u0443\u043C\u043E\u043B\u0447\u0430\u043D\u0438\u044E \u0438\u0433\u0440\u0430 \u0441\u0430\u043C\u0430 \u043E\u0442\u043C\u0435\u0447\u0430\u0435\u0442 \u0432\u044B\u043F\u0430\u0432\u0448\u0438\u0435 \u0447\u0438\u0441\u043B\u0430 \u0438 \u043E\u0431\u044A\u044F\u0432\u043B\u044F\u0435\u0442 \u043F\u043E\u0431\u0435\u0434\u0438\u0442\u0435\u043B\u0435\u0439 \u044D\u0442\u0430\u043F\u043E\u0432. \u0427\u0438\u0441\u043B\u0430 \u043D\u0435 \u043F\u043E\u0432\u0442\u043E\u0440\u044F\u044E\u0442\u0441\u044F. L \u0447\u0438\u0442\u0430\u0435\u0442 \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0438\u0439 \u0448\u0430\u0440, D \u043E\u0442\u043A\u0440\u044B\u0432\u0430\u0435\u0442 \u0441\u043F\u0438\u0441\u043E\u043A \u0432\u044B\u043F\u0430\u0432\u0448\u0438\u0445 \u0447\u0438\u0441\u0435\u043B."),
            rule_section(:marking, "\u0420\u0443\u0447\u043D\u044B\u0435 \u043E\u0442\u043C\u0435\u0442\u043A\u0438",
              "\u0412 \u0440\u0443\u0447\u043D\u043E\u043C \u0440\u0435\u0436\u0438\u043C\u0435 \u0432\u044B\u0431\u0435\u0440\u0438 \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0432\u044B\u043F\u0430\u0432\u0448\u0435\u0435 \u0447\u0438\u0441\u043B\u043E \u043D\u0430 \u043A\u0430\u0440\u0442\u043E\u0447\u043A\u0435 \u0438 \u043D\u0430\u0436\u043C\u0438 Enter. \u041C\u043E\u0436\u043D\u043E \u0442\u0430\u043A\u0436\u0435 \u043D\u0430\u0436\u0430\u0442\u044C M \u0438 \u0432\u0432\u0435\u0441\u0442\u0438 \u0447\u0438\u0441\u043B\u043E. \u0420\u0430\u0437\u0440\u0435\u0448\u0435\u043D\u043E \u043E\u0442\u043C\u0435\u0447\u0430\u0442\u044C \u0438 \u0447\u0438\u0441\u043B\u0430, \u0432\u044B\u043F\u0430\u0432\u0448\u0438\u0435 \u0440\u0430\u043D\u044C\u0448\u0435.",
              "\u0415\u0441\u043B\u0438 \u043D\u0443\u0436\u043D\u0430\u044F \u0444\u0438\u0433\u0443\u0440\u0430 \u0441\u043E\u0431\u0440\u0430\u043D\u0430, \u0437\u0430\u044F\u0432\u0438 \u0431\u0438\u043D\u0433\u043E \u043A\u043B\u0430\u0432\u0438\u0448\u0435\u0439 B. \u0418\u043D\u0430\u0447\u0435 \u043D\u0430\u0436\u043C\u0438 R, \u043A\u043E\u0433\u0434\u0430 \u0437\u0430\u043A\u043E\u043D\u0447\u0438\u0448\u044C \u043E\u0442\u043C\u0435\u0447\u0430\u0442\u044C \u0447\u0438\u0441\u043B\u0430. \u0421\u043B\u0435\u0434\u0443\u044E\u0449\u0438\u0439 \u0448\u0430\u0440 \u0436\u0434\u0451\u0442 \u0432\u0441\u0435\u0445 \u0438\u0433\u0440\u043E\u043A\u043E\u0432. \u0417\u0430\u044F\u0432\u043A\u0438 \u043D\u0430 \u043E\u0434\u043D\u043E\u043C \u0448\u0430\u0440\u0435 \u043F\u0440\u043E\u0432\u0435\u0440\u044F\u044E\u0442\u0441\u044F \u0432\u043C\u0435\u0441\u0442\u0435: \u0441\u043A\u043E\u0440\u043E\u0441\u0442\u044C \u043D\u0430\u0436\u0430\u0442\u0438\u044F B \u043D\u0435 \u0434\u0430\u0451\u0442 \u043F\u0440\u0435\u0438\u043C\u0443\u0449\u0435\u0441\u0442\u0432\u0430.",
              "\u041F\u043E\u0441\u043B\u0435 \u043F\u043E\u0431\u0435\u0434\u044B \u0437\u0430 \u043E\u0434\u043D\u0443 \u0438\u043B\u0438 \u0434\u0432\u0435 \u0441\u0442\u0440\u043E\u043A\u0438 \u0432 \u0438\u0433\u0440\u0435 \u0441 90 \u0448\u0430\u0440\u0430\u043C\u0438 \u043F\u0440\u043E\u0432\u0435\u0440\u044C \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0443\u044E \u0446\u0435\u043B\u044C. \u0415\u0441\u043B\u0438 \u043E\u043D\u0430 \u0443\u0436\u0435 \u0432\u044B\u043F\u043E\u043B\u043D\u0435\u043D\u0430, \u0437\u0430\u044F\u0432\u0438 \u0435\u0451 \u043D\u0430 \u0442\u043E\u043C \u0436\u0435 \u0448\u0430\u0440\u0435. \u0418\u043D\u0430\u0447\u0435 \u0441\u043D\u043E\u0432\u0430 \u043D\u0430\u0436\u043C\u0438 R. \u0415\u0441\u043B\u0438 \u0448\u0430\u0440\u044B \u0437\u0430\u043A\u043E\u043D\u0447\u0438\u043B\u0438\u0441\u044C, \u0430 \u0444\u0438\u043D\u0430\u043B\u044C\u043D\u0443\u044E \u0444\u0438\u0433\u0443\u0440\u0443 \u043D\u0438\u043A\u0442\u043E \u043F\u0440\u0430\u0432\u0438\u043B\u044C\u043D\u043E \u043D\u0435 \u0437\u0430\u044F\u0432\u0438\u043B, \u0431\u0443\u0434\u0435\u0442 \u043D\u0438\u0447\u044C\u044F."),
            rule_section(:variants, "\u0412\u0430\u0440\u0438\u0430\u043D\u0442\u044B \u0431\u0438\u043D\u0433\u043E",
              "\u041F\u0440\u0438 \u0441\u043E\u0437\u0434\u0430\u043D\u0438\u0438 \u0441\u0442\u043E\u043B\u0430 \u043C\u043E\u0436\u043D\u043E \u043D\u0430\u0441\u0442\u0440\u043E\u0438\u0442\u044C \u0438\u043D\u0442\u0435\u0440\u0432\u0430\u043B \u043C\u0435\u0436\u0434\u0443 \u0448\u0430\u0440\u0430\u043C\u0438 \u0432 \u0430\u0432\u0442\u043E\u043C\u0430\u0442\u0438\u0447\u0435\u0441\u043A\u043E\u043C \u0440\u0435\u0436\u0438\u043C\u0435. \u041F\u043E \u0443\u043C\u043E\u043B\u0447\u0430\u043D\u0438\u044E \u043E\u043D \u0440\u0430\u0432\u0435\u043D \u043F\u044F\u0442\u0438 \u0441\u0435\u043A\u0443\u043D\u0434\u0430\u043C.",
              "- 90 \u0448\u0430\u0440\u043E\u0432: \u0432 \u043A\u0430\u0440\u0442\u043E\u0447\u043A\u0435 \u0442\u0440\u0438 \u0441\u0442\u0440\u043E\u043A\u0438 \u043F\u043E \u043F\u044F\u0442\u044C \u0447\u0438\u0441\u0435\u043B, \u0440\u0430\u0441\u043F\u0440\u0435\u0434\u0435\u043B\u0451\u043D\u043D\u044B\u0445 \u043F\u043E \u0434\u0435\u0432\u044F\u0442\u0438 \u0441\u0442\u043E\u043B\u0431\u0446\u0430\u043C. \u0418\u0433\u0440\u0430 \u043E\u0431\u044A\u044F\u0432\u043B\u044F\u0435\u0442 \u043F\u043E\u0431\u0435\u0434\u0438\u0442\u0435\u043B\u0435\u0439 \u0437\u0430 \u043E\u0434\u043D\u0443 \u0438 \u0434\u0432\u0435 \u0441\u0442\u0440\u043E\u043A\u0438, \u0430 \u0438\u0441\u0445\u043E\u0434 \u0440\u0435\u0448\u0430\u0435\u0442 \u043F\u043E\u043B\u043D\u0430\u044F \u043A\u0430\u0440\u0442\u043E\u0447\u043A\u0430.",
              "- 75 \u0448\u0430\u0440\u043E\u0432: \u043F\u044F\u0442\u044C \u0441\u0442\u0440\u043E\u043A \u0438 \u0441\u0442\u043E\u043B\u0431\u0446\u044B B, I, N, G, O. \u0421\u0432\u043E\u0431\u043E\u0434\u043D\u0430\u044F \u043A\u043B\u0435\u0442\u043A\u0430 \u0432 \u0446\u0435\u043D\u0442\u0440\u0435 \u0441\u0447\u0438\u0442\u0430\u0435\u0442\u0441\u044F \u043E\u0442\u043C\u0435\u0447\u0435\u043D\u043D\u043E\u0439 \u0441 \u043D\u0430\u0447\u0430\u043B\u0430.",
              "- 80 \u0448\u0430\u0440\u043E\u0432: \u0447\u0435\u0442\u044B\u0440\u0435 \u0441\u0442\u0440\u043E\u043A\u0438 \u0438 \u0447\u0435\u0442\u044B\u0440\u0435 \u0441\u0442\u043E\u043B\u0431\u0446\u0430. \u0412 \u0438\u0433\u0440\u0430\u0445 \u0441 75 \u0438 80 \u0448\u0430\u0440\u0430\u043C\u0438 \u043C\u043E\u0436\u043D\u043E \u0432\u044B\u0431\u0440\u0430\u0442\u044C \u0441\u0442\u0440\u043E\u043A\u0443, \u0441\u0442\u043E\u043B\u0431\u0435\u0446 \u0438\u043B\u0438 \u0434\u0438\u0430\u0433\u043E\u043D\u0430\u043B\u044C, \u0447\u0435\u0442\u044B\u0440\u0435 \u0443\u0433\u043B\u0430 \u043B\u0438\u0431\u043E \u043F\u043E\u043B\u043D\u0443\u044E \u043A\u0430\u0440\u0442\u043E\u0447\u043A\u0443.",
              "- 30 \u0448\u0430\u0440\u043E\u0432: \u0442\u0440\u0438 \u0441\u0442\u0440\u043E\u043A\u0438 \u0438 \u0442\u0440\u0438 \u0441\u0442\u043E\u043B\u0431\u0446\u0430 \u0431\u0435\u0437 \u0441\u0432\u043E\u0431\u043E\u0434\u043D\u043E\u0439 \u043A\u043B\u0435\u0442\u043A\u0438. \u041F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u043F\u043E\u043B\u043D\u0430\u044F \u043A\u0430\u0440\u0442\u043E\u0447\u043A\u0430."),
            rule_section(:controls, "\u0413\u043E\u0440\u044F\u0447\u0438\u0435 \u043A\u043B\u0430\u0432\u0438\u0448\u0438",
              "L: \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0438\u0439 \u0448\u0430\u0440",
              "D: \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u0442\u044C \u0432\u044B\u043F\u0430\u0432\u0448\u0438\u0435 \u0447\u0438\u0441\u043B\u0430",
              "Enter \u043D\u0430 \u043A\u0430\u0440\u0442\u043E\u0447\u043A\u0435: \u043E\u0442\u043C\u0435\u0442\u0438\u0442\u044C \u0447\u0438\u0441\u043B\u043E \u0432\u0440\u0443\u0447\u043D\u0443\u044E",
              "M: \u0432\u0432\u0435\u0441\u0442\u0438 \u0447\u0438\u0441\u043B\u043E \u0434\u043B\u044F \u043E\u0442\u043C\u0435\u0442\u043A\u0438",
              "B: \u0437\u0430\u044F\u0432\u0438\u0442\u044C \u0431\u0438\u043D\u0433\u043E",
              "R: \u0437\u0430\u043A\u043E\u043D\u0447\u0438\u0442\u044C \u043E\u0442\u043C\u0435\u0447\u0430\u0442\u044C \u0447\u0438\u0441\u043B\u0430")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
