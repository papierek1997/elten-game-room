# Generated from tools/data/rulebooks/blackjack_dice.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class BlackjackDice
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:play, GameRoomRules.translate("Dice variants and scoring"),
            GameRoomRules.translate("Players take turns accumulating rolls towards 21. In Two dice, use both below 16 and one die from 16. In One die, use one throughout. After the first roll you may stand. Reaching 21 or exceeding it ends your turn."),
            GameRoomRules.translate("Finish every player\u2019s turn before scoring. A unique best total not exceeding 21 earns one point, or two for exactly 21. A tied best total, including tied 21s, and an all-bust round earn no points. This match scoring also applies to the one-die variant; it replaces a playoff. Rotate the first player each round. First to the chosen target (default ten) wins.")),
          rule_section(:betting, GameRoomRules.translate("Opening contributions and betting"),
            GameRoomRules.translate("Each round starts with an automatic opening contribution from every active player: ten chips by default, or the table setting. A player with less pays their entire balance and is all-in. Then players act in seat order: check if nothing is owed, call a raise, raise, fold, or go all-in. A raise makes the others respond again. Betting closes when all players who still have chips have responded and matched the current bet, or only one player has not folded. All-in players keep their right to play without further betting. A short all-in does not reopen raising for someone who already acted unless the cumulative increase reaches a full raise."),
            GameRoomRules.translate("Use C to check or call, F to fold, A for all-in, and R or B to type your own raise. The entered amount is the increase above the current bet; any amount needed to call is added to the payment. Raises start at one chip and later must match the last full raise; a smaller final all-in is allowed. Preset raises are also in the actions list. Cards or dice start only after betting closes.")),
          rule_section(:chips, GameRoomRules.translate("Playing for chips"),
            GameRoomRules.translate("Before any dice, use Virtual chips under Round settlement to play with opening contributions and betting. Set initial chips, opening contribution and round limit when creating the table. Defaults are 100 chips, an opening contribution of ten and ten rounds. Point mode retains its scoring without chip betting."),
            GameRoomRules.translate("After betting, players who have not folded take their dice turns, including all-in players. Contributions create main and side pots: a player may win only the layers their own contribution covers. Each layer goes to its highest non-bust eligible total; tied leaders split it, with remaining whole chips assigned in round seat order. An unmatched excess is returned. A layer with no eligible non-bust total is refunded to its contributors. If everyone but one folds, the remaining player wins the contested pot without rolling. Chips in balances and pots are conserved."),
            GameRoomRules.translate("The starting seat rotates each round. A zero balance eliminates only after settlement. Play ends at the round limit or with fewer than two funded players. The highest final balance wins; tied maxima draw. S reads balances. Previously recorded chip games retain their original betting rules.")),
          rule_section(:controls, GameRoomRules.translate("Controls"),
            GameRoomRules.translate("Use the arrows to choose an action and Enter to perform it. Tab changes fields. T reads the current turn; S reads scores. F1 opens the current shortcut reference; Ctrl+F1 opens the rules. Card hands preserve physical card identity and draw order. Their cards are for inspection, not play: choose decisions in the separate actions list."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:play, "Hody a body",
              "Ve sv\u00E9m tahu h\u00E1zej mezern\u00EDkem a p\u0159i\u010D\u00EDtej si hozen\u00E9 hodnoty. Se sou\u010Dtem pod 16 h\u00E1z\u00ED\u0161 dv\u011Bma kostkami, od 16 jednou. Po hodu m\u016F\u017Ee\u0161 pokra\u010Dovat nebo zvolit Z\u016Fstat na tomto sou\u010Dtu a stisknout Enter. P\u0159i sou\u010Dtu 21 a v\u00EDc tah kon\u010D\u00ED. P\u0159ekro\u010D\u00ED\u0161-li 21, kolo nem\u016F\u017Ee\u0161 vyhr\u00E1t.",
              "Po taz\u00EDch v\u0161ech hr\u00E1\u010D\u016F z\u00EDsk\u00E1 bod nejvy\u0161\u0161\u00ED sou\u010Det do 21. Za p\u0159esn\u011B 21 jsou body dva. Kdy\u017E se nejlep\u0161\u00ED hr\u00E1\u010Di d\u011Bl\u00ED o prvn\u00ED m\u00EDsto nebo v\u0161ichni p\u0159ekro\u010D\u00ED 21, body se ned\u00E1vaj\u00ED. Za\u010D\u00EDnaj\u00EDc\u00ED se ka\u017Ed\u00E9 kolo m\u011Bn\u00ED. Vyhr\u00E1v\u00E1 ten, kdo prvn\u00ED dos\u00E1hne c\u00EDle, obvykle deseti bod\u016F.",
              "P\u0159i vytv\u00E1\u0159en\u00ED stolu m\u016F\u017Ee\u0161 zvolit hru s jedinou kostkou po celou dobu."),
            rule_section(:chips, "Hra o \u017Eetony",
              "Pokud p\u0159i vytv\u00E1\u0159en\u00ED stolu zvol\u00ED\u0161 virtu\u00E1ln\u00ED \u017Eetony, s\u00E1z\u00ED se p\u0159ed hody. Nastav po\u010D\u00E1te\u010Dn\u00ED z\u016Fstatek, vklad a po\u010Det kol m\u00EDsto bodov\u00E9ho c\u00EDle.",
              "Bank z\u00EDsk\u00E1 nejvy\u0161\u0161\u00ED sou\u010Det do 21. P\u0159i shod\u011B se bank d\u011Bl\u00ED a zbyl\u00E9 \u017Eetony se p\u0159id\u011Bl\u00ED podle po\u0159ad\u00ED v kole. Od jednoho hr\u00E1\u010De nelze vyhr\u00E1t v\u00EDc, ne\u017E kolik jsi vsadil s\u00E1m. Nedorovnan\u00E9 \u010D\u00E1sti s\u00E1zek se vracej\u00ED, stejn\u011B jako bank, na kter\u00FD nikdo nem\u00E1 platn\u00FD v\u00FDsledek.",
              "Po vyhodnocen\u00ED hr\u00E1\u010D bez \u017Eeton\u016F vypad\u00E1v\u00E1. Hra kon\u010D\u00ED po stanoven\u00E9m po\u010Dtu kol nebo kdy\u017E u\u017E nemaj\u00ED \u017Eetony alespo\u0148 dva hr\u00E1\u010Di. Vyhr\u00E1v\u00E1 nejvy\u0161\u0161\u00ED z\u016Fstatek, p\u0159i shod\u011B je rem\u00EDza."),
            rule_section(:betting, "S\u00E1zen\u00ED p\u0159ed hody",
              "Na za\u010D\u00E1tku kola ka\u017Ed\u00FD zaplat\u00ED vklad, obvykle deset \u017Eeton\u016F. Kdo m\u00E1 m\u00E9n\u011B, vlo\u017E\u00ED v\u0161echny sv\u00E9 \u017Eetony. Potom se hr\u00E1\u010Di st\u0159\u00EDdaj\u00ED v s\u00E1zen\u00ED.",
              "Kl\u00E1vesou C dorovn\u00E1\u0161 s\u00E1zku, nebo vy\u010Dk\u00E1\u0161, pokud nic nedopl\u00E1c\u00ED\u0161. Kl\u00E1vesou F odstoup\u00ED\u0161 a p\u0159ijde\u0161 o dosavadn\u00ED vklad. Kl\u00E1vesa A vsad\u00ED v\u0161echny tvoje \u017Eetony. V kole z\u016Fst\u00E1v\u00E1\u0161, ale d\u00E1l nes\u00E1z\u00ED\u0161.",
              "Chce\u0161-li zv\u00FD\u0161it s\u00E1zku, stiskni R a zadej, o kolik ji chce\u0161 zvednout. Hra p\u0159ipo\u010Dte \u010D\u00E1stku pot\u0159ebnou k dorovn\u00E1n\u00ED. Poprv\u00E9 se zvy\u0161uje nejm\u00E9n\u011B o \u017Eeton, potom nejm\u00E9n\u011B o posledn\u00ED pln\u00E9 nav\u00FD\u0161en\u00ED. Men\u0161\u00ED s\u00E1zka za v\u0161echny \u017Eetony neumo\u017En\u00ED hr\u00E1\u010Di, kter\u00FD u\u017E jednal, znovu zvy\u0161ovat, dokud se men\u0161\u00ED nav\u00FD\u0161en\u00ED nese\u010Dtou na plnou \u010D\u00E1stku.",
              "S\u00E1zen\u00ED kon\u010D\u00ED, kdy\u017E z\u016Fstane jedin\u00FD hr\u00E1\u010D nebo v\u0161ichni hr\u00E1\u010Di, kte\u0159\u00ED neodstoupili a maj\u00ED \u017Eetony, zareaguj\u00ED a dorovnaj\u00ED.",
              "Potom h\u00E1zej\u00ED hr\u00E1\u010Di, kte\u0159\u00ED neodstoupili. Jestli z\u016Fstal jedin\u00FD, z\u00EDsk\u00E1 bank bez hodu."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "Mezern\u00EDk: hodit",
              "C: p\u0159i h\u00E1zen\u00ED p\u0159e\u010D\u00EDst sou\u010Det, p\u0159i s\u00E1zen\u00ED vy\u010Dkat nebo dorovnat",
              "D: p\u0159e\u010D\u00EDst posledn\u00ED hod",
              "S: zjistit body nebo \u017Eetony",
              "T: zjistit, kdo je na tahu",
              "F: odstoupit ze s\u00E1zen\u00ED",
              "A: vsadit v\u0161e",
              "R: hodit kostkami nebo p\u0159i s\u00E1zen\u00ED zv\u00FD\u0161it s\u00E1zku",
              "B: zv\u00FD\u0161it s\u00E1zku")
          ]
        when "en"
          [
            rule_section(:play, "Rolling and scoring",
              "Press Space on your turn to roll and add the result to your total. Roll two dice below 16 and one from 16 onward. You can roll again or select Keep your total and press Enter. Reaching 21 or going over ends your turn; if you go over, you cannot win the round.",
              "After every player has had a turn, the best total up to 21 earns a point, or two for exactly 21. No one scores if the best total is tied or everyone goes over. A different player starts each round. The first to the agreed target wins; the default is ten points.",
              "You can choose to use only one die throughout the game in the table settings."),
            rule_section(:chips, "Playing for chips",
              "Choose Virtual chips under Round settlement when creating the table to bet before rolling. Set the starting balance, opening stake and number of rounds instead of a points target.",
              "The best total up to 21 wins the pot, with ties sharing it. Extra indivisible chips go to tied players in round order. You can win at most your own stake from each other player. Any amount no one matched is returned, and bets in a pot with no eligible total up to 21 are also returned.",
              "A player with no chips after settlement is out. The match ends at the round limit or when fewer than two players have chips. Highest balance wins; equal highest balances draw."),
            rule_section(:betting, "Betting before rolling",
              "Each player pays an opening stake, normally ten chips. If you cannot cover the table\u2019s opening stake, you put in what you have. Players then bet in turn.",
              "Press C to check if you owe nothing or call to match the bet. F folds: you leave the round and give up what you have paid. A puts in all your chips. You stay in the round but cannot bet again.",
              "To raise, press R and enter how much higher the bet should be. Any amount you need to call is added to your payment. The first raise is at least one chip; later raises must match the last full raise. A smaller all-in does not let a player who already acted raise again unless the smaller increases together make a full raise.",
              "Betting ends when one player remains or everyone still in the round with chips has responded and matched the bet.",
              "Players who did not fold now roll. If only one player remains, they win the pot without rolling."),
            rule_section(:controls, "Keyboard shortcuts",
              "Space: roll",
              "C: read the current total when rolling; check or call when betting",
              "D: read the last roll",
              "S: read scores or balances",
              "T: read the current turn",
              "F: fold in betting",
              "A: go all-in",
              "R: roll the dice or raise, depending on the phase",
              "B: raise when betting")
          ]
        when "es"
          [
            rule_section(:play, "Tiradas y puntuaci\u00F3n",
              "En tu turno, pulsa Espacio para tirar y sumar el resultado. Por debajo de 16 tiras dos dados; a partir de 16, uno. Puedes volver a tirar o elegir Plantarse con este total y pulsar Intro. Con 21 o m\u00E1s termina tu turno. Si te pasas, no puedes ganar la ronda.",
              "Cuando todos han jugado, el mejor total que no pase de 21 vale un punto. Si es exactamente 21, vale dos. Un empate en cabeza o que todos se pasen deja la ronda sin puntos. El primer turno cambia en cada ronda. Gana quien alcance antes el objetivo, normalmente diez puntos.",
              "Al crear la mesa puedes elegir tirar un solo dado durante toda la partida."),
            rule_section(:chips, "Partida con fichas",
              "Elige las fichas virtuales al configurar c\u00F3mo se resuelve la ronda para apostar antes de tirar. En vez de una meta de puntos, fija el saldo inicial, la entrada y el n\u00FAmero de rondas.",
              "El mejor total hasta 21 se lleva el bote. Los empatados lo reparten y las fichas sobrantes se asignan por orden de turno de la ronda. No puedes ganar de un rival m\u00E1s de lo que t\u00FA has puesto. Se devuelve lo que nadie igual\u00F3 y las apuestas de un bote sin ning\u00FAn resultado v\u00E1lido.",
              "Si despu\u00E9s de resolver el bote no te quedan fichas, quedas fuera. La partida termina tras la \u00FAltima ronda o si quedan menos de dos jugadores con fichas. Gana el saldo m\u00E1s alto; los saldos iguales en cabeza empatan."),
            rule_section(:betting, "Apuestas antes de tirar",
              "Al comenzar la ronda, todos aportan la entrada de la mesa, normalmente diez fichas. Si tienes menos, aportas todas las que te quedan. Despu\u00E9s se apuesta por turnos.",
              "Pulsa C para pasar si no tienes nada que a\u00F1adir o igualar la apuesta. Con F te retiras y pierdes lo aportado. Con A apuestas todo: sigues en la ronda, pero no puedes volver a apostar.",
              "Para subir, pulsa R e indica cu\u00E1nto quieres aumentar la apuesta. El juego a\u00F1ade lo necesario para igualarla. La primera subida es de al menos una ficha; las siguientes deben alcanzar la \u00FAltima subida completa. Un envite inferior con todas tus fichas no permite volver a subir a quien ya actu\u00F3, salvo que la suma de subidas alcance el m\u00EDnimo.",
              "Las apuestas terminan cuando solo queda un jugador o cuando todos los que siguen en juego y tienen fichas han actuado e igualado la apuesta.",
              "Despu\u00E9s tiran quienes no se han retirado. Si solo queda uno, se lleva el bote sin tirar."),
            rule_section(:controls, "Atajos de teclado",
              "Espacio: tirar los dados",
              "C: leer el total durante las tiradas; pasar o igualar en las apuestas",
              "D: leer la \u00FAltima tirada",
              "S: consultar puntos o saldos",
              "T: consultar el turno",
              "F: retirarse de las apuestas",
              "A: apostarlo todo",
              "R: tirar los dados o subir la apuesta, seg\u00FAn la fase",
              "B: subir la apuesta")
          ]
        when "pl"
          [
            rule_section(:play, "Rzuty i punktacja",
              "W swojej turze naciskasz Spacj\u0119, \u017Ceby rzuci\u0107, i dodajesz wyrzucone oczka do sumy. Poni\u017Cej 16 rzucasz dwiema ko\u015B\u0107mi, od 16 jedn\u0105. Po ka\u017Cdym rzucie mo\u017Cesz rzuci\u0107 ponownie albo wybra\u0107 \u201EZosta\u0144 przy tej sumie\u201D i potwierdzi\u0107 Enterem. Przy 21 lub wi\u0119cej tura ko\u0144czy si\u0119 sama. Je\u015Bli przekroczysz 21, nie mo\u017Cesz wygra\u0107 tej rundy.",
              "Gdy ka\u017Cdy wykona swoj\u0105 tur\u0119, najwy\u017Csza suma nieprzekraczaj\u0105ca 21 daje punkt. Za dok\u0142adnie 21 dostajesz dwa punkty. Je\u015Bli najlepszy wynik osi\u0105gn\u0119\u0142o kilka os\u00F3b lub wszyscy przekroczyli 21, nikt nie dostaje punkt\u00F3w. W ka\u017Cdej rundzie zaczyna kolejna osoba. Wygrywa ten, kto pierwszy osi\u0105gnie ustalony limit, domy\u015Blnie 10 punkt\u00F3w.",
              "Przy tworzeniu sto\u0142u mo\u017Cesz wybra\u0107 wariant, w kt\u00F3rym przez ca\u0142\u0105 gr\u0119 rzucasz tylko jedn\u0105 ko\u015Bci\u0105."),
            rule_section(:chips, "Gra o \u017Cetony",
              "W ustawieniu \u201ERozliczenie rundy\u201D mo\u017Cesz wybra\u0107 wirtualne \u017Cetony. Przed rzutami gracie wtedy o pul\u0119. Zamiast limitu punkt\u00F3w ustalasz liczb\u0119 rund, a tak\u017Ce pocz\u0105tkowe saldo i wpisowe.",
              "Najwy\u017Csza suma do 21 wygrywa pul\u0119; remisuj\u0105cy j\u0105 dziel\u0105. \u017Beton, kt\u00F3rego nie da si\u0119 podzieli\u0107, przypada wed\u0142ug kolejno\u015Bci w rundzie. Je\u015Bli kto\u015B wp\u0142aci\u0142 mniej od pozosta\u0142ych, mo\u017Ce wygra\u0107 od ka\u017Cdego najwy\u017Cej tyle, ile sam wp\u0142aci\u0142. Niewyr\u00F3wnan\u0105 cz\u0119\u015B\u0107 stawki dostaje z powrotem ten, kto j\u0105 wp\u0142aci\u0142. Je\u015Bli nikt uprawniony do danej puli nie ma wyniku do 21, wp\u0142aty do niej wracaj\u0105.",
              "Kto po rozliczeniu nie ma \u017Ceton\u00F3w, odpada. Mecz ko\u0144czy si\u0119 po ustalonej liczbie rund albo gdy mniej ni\u017C dwie osoby maj\u0105 jeszcze \u017Cetony. Wygrywa najwy\u017Csze saldo; r\u00F3wne najwy\u017Csze salda daj\u0105 remis."),
            rule_section(:betting, "Licytacja przed rzutami",
              "Ka\u017Cda runda zaczyna si\u0119 od wpisowego. Domy\u015Blnie wynosi 10 \u017Ceton\u00F3w; je\u015Bli brakuje ci do wpisowego, wp\u0142acasz wszystkie swoje \u017Cetony. Potem ka\u017Cdy po kolei decyduje, czy zosta\u0107 w rozdaniu.",
              "C pozwala zaczeka\u0107, gdy nie masz nic do dop\u0142aty, lub wyr\u00F3wna\u0107 bie\u017C\u0105c\u0105 stawk\u0119. F oznacza pas: rezygnujesz z rundy i tracisz dotychczasowe wp\u0142aty. Klawiszem A stawiasz wszystkie \u017Cetony. Nadal bierzesz udzia\u0142 w rundzie, ale nie licytujesz dalej.",
              "\u017Beby podbi\u0107, naci\u015Bnij R i wpisz, o ile chcesz zwi\u0119kszy\u0107 stawk\u0119. Gra doliczy kwot\u0119 potrzebn\u0105 do jej wyr\u00F3wnania. Pierwsze podbicie wynosi co najmniej jeden \u017Ceton, nast\u0119pne co najmniej tyle, co ostatnie pe\u0142ne podbicie. Mniejsze wej\u015Bcie za wszystko nie przywraca prawa do podbicia osobie, kt\u00F3ra ju\u017C licytowa\u0142a, dop\u00F3ki suma tych podbi\u0107 nie osi\u0105gnie pe\u0142nego podbicia.",
              "Licytacja ko\u0144czy si\u0119, gdy pozostanie jedna osoba lub wszyscy niespasowani gracze z \u017Cetonami odpowiedz\u0105 i wyr\u00F3wnaj\u0105 stawk\u0119.",
              "Po zamkni\u0119ciu licytacji rzucaj\u0105 osoby, kt\u00F3re nie spasowa\u0142y. Je\u015Bli zosta\u0142a tylko jedna, wygrywa pul\u0119 bez rzucania."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "Spacja: rzu\u0107 ko\u015B\u0107mi",
              "C: odczytaj sum\u0119 podczas rzut\u00F3w, a przy licytacji zaczekaj lub wyr\u00F3wnaj stawk\u0119",
              "D: odczytaj ostatni rzut",
              "S: sprawd\u017A punkty lub salda",
              "T: sprawd\u017A, kto wykonuje ruch",
              "F: spasuj w licytacji",
              "A: wejd\u017A za wszystko",
              "R: rzu\u0107 ko\u015B\u0107mi albo podbij stawk\u0119 w licytacji",
              "B: podbij stawk\u0119 w licytacji")
          ]
        when "ru"
          [
            rule_section(:play, "\u0411\u0440\u043E\u0441\u043A\u0438 \u0438 \u043E\u0447\u043A\u0438",
              "\u0412 \u0441\u0432\u043E\u0439 \u0445\u043E\u0434 \u043D\u0430\u0436\u043C\u0438 \u043F\u0440\u043E\u0431\u0435\u043B, \u0447\u0442\u043E\u0431\u044B \u0431\u0440\u043E\u0441\u0438\u0442\u044C \u043A\u043E\u0441\u0442\u0438 \u0438 \u043F\u0440\u0438\u0431\u0430\u0432\u0438\u0442\u044C \u0432\u044B\u043F\u0430\u0432\u0448\u0438\u0435 \u0437\u043D\u0430\u0447\u0435\u043D\u0438\u044F \u043A \u0441\u0443\u043C\u043C\u0435. \u041F\u043E\u043A\u0430 \u0441\u0443\u043C\u043C\u0430 \u043D\u0438\u0436\u0435 16, \u0431\u0440\u043E\u0441\u0430\u0435\u0448\u044C \u0434\u0432\u0435 \u043A\u043E\u0441\u0442\u0438, \u0441 16 \u2014 \u043E\u0434\u043D\u0443. \u041F\u043E\u0441\u043B\u0435 \u0431\u0440\u043E\u0441\u043A\u0430 \u043C\u043E\u0436\u043D\u043E \u0431\u0440\u043E\u0441\u0438\u0442\u044C \u0435\u0449\u0451 \u0440\u0430\u0437 \u0438\u043B\u0438 \u0432\u044B\u0431\u0440\u0430\u0442\u044C \u00AB\u041E\u0441\u0442\u0430\u043D\u043E\u0432\u0438\u0442\u044C\u0441\u044F \u043D\u0430 \u044D\u0442\u043E\u0439 \u0441\u0443\u043C\u043C\u0435\u00BB \u0438 \u043D\u0430\u0436\u0430\u0442\u044C Enter. \u041F\u0440\u0438 21 \u0438 \u0431\u043E\u043B\u044C\u0448\u0435 \u0445\u043E\u0434 \u0437\u0430\u043A\u0430\u043D\u0447\u0438\u0432\u0430\u0435\u0442\u0441\u044F. \u0421 \u043F\u0435\u0440\u0435\u0431\u043E\u0440\u043E\u043C \u0432\u044B\u0438\u0433\u0440\u0430\u0442\u044C \u0440\u0430\u0443\u043D\u0434 \u043D\u0435\u043B\u044C\u0437\u044F.",
              "\u041A\u043E\u0433\u0434\u0430 \u0432\u0441\u0435 \u0441\u0445\u043E\u0434\u044F\u0442, \u043D\u0430\u0438\u0431\u043E\u043B\u044C\u0448\u0430\u044F \u0441\u0443\u043C\u043C\u0430 \u0434\u043E 21 \u0434\u0430\u0451\u0442 \u043E\u0447\u043A\u043E, \u0440\u043E\u0432\u043D\u043E 21 \u2014 \u0434\u0432\u0430. \u0415\u0441\u043B\u0438 \u043B\u0443\u0447\u0448\u0438\u0439 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442 \u0440\u0430\u0437\u0434\u0435\u043B\u0438\u043B\u0438 \u043D\u0435\u0441\u043A\u043E\u043B\u044C\u043A\u043E \u0438\u0433\u0440\u043E\u043A\u043E\u0432 \u0438\u043B\u0438 \u0432\u0441\u0435 \u043F\u0435\u0440\u0435\u0431\u0440\u0430\u043B\u0438, \u043E\u0447\u043A\u0438 \u043D\u0435 \u043D\u0430\u0447\u0438\u0441\u043B\u044F\u044E\u0442\u0441\u044F. \u0412 \u043A\u0430\u0436\u0434\u043E\u043C \u0440\u0430\u0443\u043D\u0434\u0435 \u043D\u0430\u0447\u0438\u043D\u0430\u0435\u0442 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0438\u0439 \u0438\u0433\u0440\u043E\u043A. \u041F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u0442\u043E\u0442, \u043A\u0442\u043E \u043F\u0435\u0440\u0432\u044B\u043C \u0434\u043E\u0441\u0442\u0438\u0433\u043D\u0435\u0442 \u0446\u0435\u043B\u0438, \u043E\u0431\u044B\u0447\u043D\u043E \u0434\u0435\u0441\u044F\u0442\u0438 \u043E\u0447\u043A\u043E\u0432.",
              "\u041F\u0440\u0438 \u0441\u043E\u0437\u0434\u0430\u043D\u0438\u0438 \u0441\u0442\u043E\u043B\u0430 \u043C\u043E\u0436\u043D\u043E \u0432\u044B\u0431\u0440\u0430\u0442\u044C \u0432\u0430\u0440\u0438\u0430\u043D\u0442, \u0432 \u043A\u043E\u0442\u043E\u0440\u043E\u043C \u0432\u0441\u044E \u0438\u0433\u0440\u0443 \u0431\u0440\u043E\u0441\u0430\u044E\u0442 \u043E\u0434\u043D\u0443 \u043A\u043E\u0441\u0442\u044C."),
            rule_section(:chips, "\u0418\u0433\u0440\u0430 \u043D\u0430 \u0444\u0438\u0448\u043A\u0438",
              "\u0412\u044B\u0431\u0435\u0440\u0438 \u0432\u0438\u0440\u0442\u0443\u0430\u043B\u044C\u043D\u044B\u0435 \u0444\u0438\u0448\u043A\u0438 \u0432 \u043D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0430\u0445 \u0440\u0430\u0441\u0447\u0451\u0442\u0430 \u0440\u0430\u0443\u043D\u0434\u0430, \u0447\u0442\u043E\u0431\u044B \u043F\u0435\u0440\u0435\u0434 \u0431\u0440\u043E\u0441\u043A\u0430\u043C\u0438 \u0434\u0435\u043B\u0430\u0442\u044C \u0441\u0442\u0430\u0432\u043A\u0438. \u0412\u043C\u0435\u0441\u0442\u043E \u0446\u0435\u043B\u0438 \u0432 \u043E\u0447\u043A\u0430\u0445 \u0437\u0430\u0434\u0430\u0439 \u043D\u0430\u0447\u0430\u043B\u044C\u043D\u044B\u0439 \u0437\u0430\u043F\u0430\u0441 \u0444\u0438\u0448\u0435\u043A, \u0432\u0437\u043D\u043E\u0441 \u0438 \u0447\u0438\u0441\u043B\u043E \u0440\u0430\u0443\u043D\u0434\u043E\u0432.",
              "\u0411\u0430\u043D\u043A \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u043D\u0430\u0438\u0431\u043E\u043B\u044C\u0448\u0430\u044F \u0441\u0443\u043C\u043C\u0430 \u0434\u043E 21. \u041F\u0440\u0438 \u0440\u0430\u0432\u0435\u043D\u0441\u0442\u0432\u0435 \u0438\u0433\u0440\u043E\u043A\u0438 \u0434\u0435\u043B\u044F\u0442 \u0431\u0430\u043D\u043A, \u0430 \u043B\u0438\u0448\u043D\u0438\u0435 \u043D\u0435\u0434\u0435\u043B\u0438\u043C\u044B\u0435 \u0444\u0438\u0448\u043A\u0438 \u0434\u043E\u0441\u0442\u0430\u044E\u0442\u0441\u044F \u043F\u043E \u043F\u043E\u0440\u044F\u0434\u043A\u0443 \u0445\u043E\u0434\u043E\u0432 \u0432 \u0440\u0430\u0443\u043D\u0434\u0435. \u0423 \u043A\u0430\u0436\u0434\u043E\u0433\u043E \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u0430 \u043C\u043E\u0436\u043D\u043E \u0432\u044B\u0438\u0433\u0440\u0430\u0442\u044C \u043D\u0435 \u0431\u043E\u043B\u044C\u0448\u0435 \u0441\u043E\u0431\u0441\u0442\u0432\u0435\u043D\u043D\u043E\u0433\u043E \u0432\u0437\u043D\u043E\u0441\u0430. \u041D\u0435\u0443\u0440\u0430\u0432\u043D\u0435\u043D\u043D\u0430\u044F \u0447\u0430\u0441\u0442\u044C \u0441\u0442\u0430\u0432\u043A\u0438 \u0432\u043E\u0437\u0432\u0440\u0430\u0449\u0430\u0435\u0442\u0441\u044F, \u043A\u0430\u043A \u0438 \u0432\u0437\u043D\u043E\u0441\u044B \u0432 \u0431\u0430\u043D\u043A, \u0435\u0441\u043B\u0438 \u0443 \u0432\u0441\u0435\u0445 \u043F\u0440\u0435\u0442\u0435\u043D\u0434\u0435\u043D\u0442\u043E\u0432 \u043F\u0435\u0440\u0435\u0431\u043E\u0440.",
              "\u0418\u0433\u0440\u043E\u043A \u0431\u0435\u0437 \u0444\u0438\u0448\u0435\u043A \u043F\u043E\u0441\u043B\u0435 \u0440\u0430\u0441\u0447\u0451\u0442\u0430 \u0432\u044B\u0431\u044B\u0432\u0430\u0435\u0442. \u041C\u0430\u0442\u0447 \u0437\u0430\u043A\u0430\u043D\u0447\u0438\u0432\u0430\u0435\u0442\u0441\u044F \u043F\u043E\u0441\u043B\u0435 \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0435\u0433\u043E \u0440\u0430\u0443\u043D\u0434\u0430 \u0438\u043B\u0438 \u043A\u043E\u0433\u0434\u0430 \u0444\u0438\u0448\u043A\u0438 \u043E\u0441\u0442\u0430\u044E\u0442\u0441\u044F \u043C\u0435\u043D\u0435\u0435 \u0447\u0435\u043C \u0443 \u0434\u0432\u0443\u0445 \u0438\u0433\u0440\u043E\u043A\u043E\u0432. \u0412\u044B\u0438\u0433\u0440\u044B\u0432\u0430\u0435\u0442 \u043D\u0430\u0438\u0431\u043E\u043B\u044C\u0448\u0438\u0439 \u043E\u0441\u0442\u0430\u0442\u043E\u043A \u0444\u0438\u0448\u0435\u043A; \u043F\u0440\u0438 \u0440\u0430\u0432\u0435\u043D\u0441\u0442\u0432\u0435 \u2014 \u043D\u0438\u0447\u044C\u044F."),
            rule_section(:betting, "\u0422\u043E\u0440\u0433\u0438 \u043F\u0435\u0440\u0435\u0434 \u0431\u0440\u043E\u0441\u043A\u0430\u043C\u0438",
              "\u0412 \u043D\u0430\u0447\u0430\u043B\u0435 \u0440\u0430\u0443\u043D\u0434\u0430 \u043A\u0430\u0436\u0434\u044B\u0439 \u0432\u043D\u043E\u0441\u0438\u0442 \u043D\u0430\u0447\u0430\u043B\u044C\u043D\u0443\u044E \u0441\u0442\u0430\u0432\u043A\u0443. \u041E\u0431\u044B\u0447\u043D\u043E \u044D\u0442\u043E \u0434\u0435\u0441\u044F\u0442\u044C \u0444\u0438\u0448\u0435\u043A. \u0415\u0441\u043B\u0438 \u0444\u0438\u0448\u0435\u043A \u043C\u0435\u043D\u044C\u0448\u0435, \u0432\u043D\u0435\u0441\u0438 \u0432\u0441\u0435, \u0447\u0442\u043E \u0435\u0441\u0442\u044C. \u0417\u0430\u0442\u0435\u043C \u0438\u0433\u0440\u043E\u043A\u0438 \u0434\u0435\u043B\u0430\u044E\u0442 \u0441\u0442\u0430\u0432\u043A\u0438 \u043F\u043E \u043E\u0447\u0435\u0440\u0435\u0434\u0438.",
              "\u041D\u0430\u0436\u043C\u0438 C, \u0447\u0442\u043E\u0431\u044B \u0443\u0440\u0430\u0432\u043D\u044F\u0442\u044C \u0441\u0442\u0430\u0432\u043A\u0443 \u0438\u043B\u0438 \u043F\u0440\u043E\u043F\u0443\u0441\u0442\u0438\u0442\u044C \u0445\u043E\u0434, \u0435\u0441\u043B\u0438 \u0434\u043E\u043F\u043B\u0430\u0447\u0438\u0432\u0430\u0442\u044C \u043D\u0435 \u043D\u0443\u0436\u043D\u043E. F \u043F\u043E\u0437\u0432\u043E\u043B\u044F\u0435\u0442 \u0432\u044B\u0439\u0442\u0438 \u0438\u0437 \u0440\u0430\u0443\u043D\u0434\u0430, \u043F\u043E\u0442\u0435\u0440\u044F\u0432 \u0443\u0436\u0435 \u0432\u043D\u0435\u0441\u0451\u043D\u043D\u044B\u0435 \u0444\u0438\u0448\u043A\u0438. \u041A\u043B\u0430\u0432\u0438\u0448\u0430 A \u0441\u0442\u0430\u0432\u0438\u0442 \u0432\u0441\u0435 \u0442\u0432\u043E\u0438 \u0444\u0438\u0448\u043A\u0438: \u0442\u044B \u043E\u0441\u0442\u0430\u0451\u0448\u044C\u0441\u044F \u0432 \u0440\u0430\u0443\u043D\u0434\u0435, \u043D\u043E \u0431\u043E\u043B\u044C\u0448\u0435 \u043D\u0435 \u0442\u043E\u0440\u0433\u0443\u0435\u0448\u044C\u0441\u044F.",
              "\u0427\u0442\u043E\u0431\u044B \u043F\u043E\u0434\u043D\u044F\u0442\u044C \u0441\u0442\u0430\u0432\u043A\u0443, \u043D\u0430\u0436\u043C\u0438 R \u0438 \u0443\u043A\u0430\u0436\u0438 \u0440\u0430\u0437\u043C\u0435\u0440 \u043F\u043E\u0432\u044B\u0448\u0435\u043D\u0438\u044F. \u0418\u0433\u0440\u0430 \u043F\u0440\u0438\u0431\u0430\u0432\u0438\u0442 \u0441\u0443\u043C\u043C\u0443, \u043D\u0443\u0436\u043D\u0443\u044E \u0434\u043B\u044F \u0443\u0440\u0430\u0432\u043D\u0438\u0432\u0430\u043D\u0438\u044F. \u041F\u0435\u0440\u0432\u043E\u0435 \u043F\u043E\u0432\u044B\u0448\u0435\u043D\u0438\u0435 \u2014 \u043D\u0435 \u043C\u0435\u043D\u044C\u0448\u0435 \u043E\u0434\u043D\u043E\u0439 \u0444\u0438\u0448\u043A\u0438, \u043F\u043E\u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0438\u0435 \u2014 \u043D\u0435 \u043C\u0435\u043D\u044C\u0448\u0435 \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0435\u0433\u043E \u043F\u043E\u043B\u043D\u043E\u0433\u043E \u043F\u043E\u0432\u044B\u0448\u0435\u043D\u0438\u044F. \u041C\u0435\u043D\u044C\u0448\u0430\u044F \u0441\u0442\u0430\u0432\u043A\u0430 \u0432\u0430-\u0431\u0430\u043D\u043A \u043D\u0435 \u0434\u0430\u0451\u0442 \u043F\u043E\u0432\u0442\u043E\u0440\u043D\u043E \u043F\u043E\u0432\u044B\u0441\u0438\u0442\u044C \u0441\u0442\u0430\u0432\u043A\u0443 \u0442\u043E\u043C\u0443, \u043A\u0442\u043E \u0443\u0436\u0435 \u0445\u043E\u0434\u0438\u043B, \u043F\u043E\u043A\u0430 \u0442\u0430\u043A\u0438\u0435 \u043F\u043E\u0432\u044B\u0448\u0435\u043D\u0438\u044F \u0432 \u0441\u0443\u043C\u043C\u0435 \u043D\u0435 \u0434\u043E\u0441\u0442\u0438\u0433\u043D\u0443\u0442 \u043F\u043E\u043B\u043D\u043E\u0433\u043E.",
              "\u0422\u043E\u0440\u0433\u0438 \u0437\u0430\u043A\u0430\u043D\u0447\u0438\u0432\u0430\u044E\u0442\u0441\u044F, \u043A\u043E\u0433\u0434\u0430 \u043E\u0441\u0442\u0430\u0451\u0442\u0441\u044F \u043E\u0434\u0438\u043D \u0438\u0433\u0440\u043E\u043A \u0438\u043B\u0438 \u043A\u043E\u0433\u0434\u0430 \u0432\u0441\u0435 \u043E\u0441\u0442\u0430\u0432\u0448\u0438\u0435\u0441\u044F \u0438\u0433\u0440\u043E\u043A\u0438 \u0441 \u0444\u0438\u0448\u043A\u0430\u043C\u0438 \u043E\u0442\u0432\u0435\u0442\u0438\u043B\u0438 \u0438 \u0443\u0440\u0430\u0432\u043D\u044F\u043B\u0438 \u0441\u0442\u0430\u0432\u043A\u0443.",
              "\u0414\u0430\u043B\u044C\u0448\u0435 \u0431\u0440\u043E\u0441\u0430\u044E\u0442 \u0442\u0435, \u043A\u0442\u043E \u043D\u0435 \u0432\u044B\u0448\u0435\u043B \u0438\u0437 \u0440\u0430\u0443\u043D\u0434\u0430. \u0415\u0441\u043B\u0438 \u043E\u0441\u0442\u0430\u043B\u0441\u044F \u043E\u0434\u0438\u043D \u0438\u0433\u0440\u043E\u043A, \u043E\u043D \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u0431\u0430\u043D\u043A \u0431\u0435\u0437 \u0431\u0440\u043E\u0441\u043A\u0430."),
            rule_section(:controls, "\u0413\u043E\u0440\u044F\u0447\u0438\u0435 \u043A\u043B\u0430\u0432\u0438\u0448\u0438",
              "\u041F\u0440\u043E\u0431\u0435\u043B: \u0431\u0440\u043E\u0441\u0438\u0442\u044C \u043A\u043E\u0441\u0442\u0438",
              "C: \u0443\u0437\u043D\u0430\u0442\u044C \u0441\u0443\u043C\u043C\u0443 \u043F\u0440\u0438 \u0431\u0440\u043E\u0441\u043A\u0430\u0445, \u043F\u0440\u043E\u043F\u0443\u0441\u0442\u0438\u0442\u044C \u0445\u043E\u0434 \u0438\u043B\u0438 \u0443\u0440\u0430\u0432\u043D\u044F\u0442\u044C \u0441\u0442\u0430\u0432\u043A\u0443 \u043F\u0440\u0438 \u0442\u043E\u0440\u0433\u0430\u0445",
              "D: \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0438\u0439 \u0431\u0440\u043E\u0441\u043E\u043A",
              "S: \u0443\u0437\u043D\u0430\u0442\u044C \u043E\u0447\u043A\u0438 \u0438\u043B\u0438 \u043E\u0441\u0442\u0430\u0442\u043A\u0438 \u0444\u0438\u0448\u0435\u043A",
              "T: \u0443\u0437\u043D\u0430\u0442\u044C, \u0447\u0435\u0439 \u0445\u043E\u0434",
              "F: \u0432\u044B\u0439\u0442\u0438 \u0438\u0437 \u0442\u043E\u0440\u0433\u043E\u0432",
              "A: \u043F\u043E\u0441\u0442\u0430\u0432\u0438\u0442\u044C \u0432\u0441\u0451",
              "R: \u0431\u0440\u043E\u0441\u0438\u0442\u044C \u043A\u043E\u0441\u0442\u0438 \u0438\u043B\u0438 \u043F\u043E\u0432\u044B\u0441\u0438\u0442\u044C \u0441\u0442\u0430\u0432\u043A\u0443 \u0432\u043E \u0432\u0440\u0435\u043C\u044F \u0442\u043E\u0440\u0433\u043E\u0432",
              "B: \u043F\u043E\u0432\u044B\u0441\u0438\u0442\u044C \u0441\u0442\u0430\u0432\u043A\u0443 \u0432\u043E \u0432\u0440\u0435\u043C\u044F \u0442\u043E\u0440\u0433\u043E\u0432")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
