# Generated from tools/data/rulebooks/roulette.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Roulette
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:aim, GameRoomRules.translate("Roulette"),
            GameRoomRules.translate("This game uses virtual chips only. Place any number of bets within your balance before finishing your turn. Players bet in order; after everyone is ready, no further bets can be changed for this spin. The outcome comes from native server randomness, not the spinner\u2019s choice.")),
          rule_section(:modes, GameRoomRules.translate("Casino and social tables"),
            GameRoomRules.translate("Casino mode uses an automatic croupier and fixed casino payouts, with no player bank balance. Social mode requires two players: the spinner rotates among solvent seats. Space spins after betting. The shared pool is divided between winning claims in proportion to their nominal casino returns, including returned stake. These are pool shares, not guaranteed casino odds. If nobody has a winning claim, every stake is refunded. This shared-pool settlement is a Power Games social rule. Choose starting chips and 1\u2013100 spins. Highest remaining balance wins after the last spin; equal best balances draw. Betting uses whole chips; balances can include half chips. A balance below one chip cannot bet again.")),
          rule_section(:bets, GameRoomRules.translate("Wheels, bets and payouts"),
            GameRoomRules.translate("European roulette has 0\u201336. American roulette also has 00. French roulette has one zero and la partage: zero returns half of red, black, odd, even, low and high stakes. Zero and double zero are neither red/black, odd/even nor low/high. Casino profit odds are 35:1 for a number, 17:1 for a split, 11:1 for a street or trio, 8:1 for four numbers, 6:1 for the American first five, 5:1 for six numbers, 2:1 for a dozen or column and 1:1 for an outside even-money bet. Winning stakes are also returned. Only adjacent legal groups on the layout are offered. In social mode these nominal returns are weights for pool division.")),
          rule_section(:controls, GameRoomRules.translate("Controls"),
            GameRoomRules.translate("Open a bet type with the arrows and Enter. Enter on a bet opens the amount field with up to ten chips suggested. Confirm that amount or change it. R finishes your betting turn, C removes and refunds your current bets, V reads them and S reads balances. Space spins in social mode when all are ready. T reads the turn; F1 lists shortcuts; Ctrl+F1 opens rules. Sounds play locally and respect Power Games volume."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:aim, "S\u00E1zen\u00ED a v\u00FDsledek",
              "Ve sv\u00E9m tahu m\u016F\u017Ee\u0161 vsadit virtu\u00E1ln\u00ED \u017Eetony na jedno \u010D\u00EDslo nebo na skupinu. \u0160ipkami vyber druh s\u00E1zky a otev\u0159i ho Enterem. Pak vyber s\u00E1zku a stiskni Enter pro zad\u00E1n\u00ED \u010D\u00E1stky. Nab\u00EDdnutou \u010D\u00E1stku m\u016F\u017Ee\u0161 ponechat nebo zm\u011Bnit a potvrdit Enterem. S\u00E1zek m\u016F\u017Ee\u0161 podat v\u00EDc, pokud ti sta\u010D\u00ED \u017Eetony.",
              "Dokud jsi na tahu, kl\u00E1vesou C st\u00E1hne\u0161 v\u0161echny sv\u00E9 s\u00E1zky a z\u00EDsk\u00E1\u0161 vklady zp\u011Bt. Kl\u00E1vesou R s\u00E1zen\u00ED ukon\u010D\u00ED\u0161. Jakmile skon\u010D\u00ED v\u0161ichni, kolo se rozto\u010D\u00ED samo. Vyhr\u00E1vaj\u00ED s\u00E1zky, kter\u00E9 obsahuj\u00ED vylosovan\u00E9 \u010D\u00EDslo.",
              "Po domluven\u00E9m po\u010Dtu rozto\u010Den\u00ED vyhr\u00E1v\u00E1 nejvy\u0161\u0161\u00ED z\u016Fstatek. P\u0159i shod\u011B je rem\u00EDza. S\u00E1z\u00ED se cel\u00FDmi \u017Eetony, v\u00FDplata m\u016F\u017Ee obsahovat polovinu \u017Eetonu. Hra skon\u010D\u00ED d\u0159\u00EDv, pokud u\u017E nikdo nem\u016F\u017Ee s\u00E1zet nebo u spole\u010Densk\u00E9ho stolu m\u016F\u017Ee s\u00E1zet jen jeden hr\u00E1\u010D."),
            rule_section(:bets, "Kola a v\u00FDplaty",
              "Evropsk\u00E9 kolo m\u00E1 \u010D\u00EDsla 0 a\u017E 36, americk\u00E9 p\u0159id\u00E1v\u00E1 00. Nuly nepat\u0159\u00ED do s\u00E1zek na barvu, sud\u00E9 \u010Di lich\u00E9 ani doln\u00ED \u010Di horn\u00ED polovinu. U francouzsk\u00E9ho kola se p\u0159i nule vrac\u00ED polovina takov\u00E9 s\u00E1zky.",
              "P\u0159i v\u00FDh\u0159e dostane\u0161 zp\u011Bt vklad a k n\u011Bmu zisk podle s\u00E1zky:",
              "- Jedno \u010D\u00EDslo: 35 ku 1; dv\u011B sousedn\u00ED: 17 ku 1; t\u0159i: 11 ku 1; \u010Dty\u0159i: 8 ku 1.",
              "- \u0160est \u010D\u00EDsel: 5 ku 1; prvn\u00ED p\u011Btice na americk\u00E9m kole: 6 ku 1.",
              "- Tucet nebo sloupec: 2 ku 1; barva, sud\u00E9 \u010Di lich\u00E9 nebo polovina \u010D\u00EDsel: 1 ku 1."),
            rule_section(:modes, "Spole\u010Densk\u00FD st\u016Fl",
              "U spole\u010Densk\u00E9ho stolu hraj\u00ED alespo\u0148 dva. Po skon\u010Den\u00ED s\u00E1zek rozto\u010D\u00ED ur\u010Den\u00FD hr\u00E1\u010D kolo mezern\u00EDkem. V t\u00E9to \u00FAloze se st\u0159\u00EDdaj\u00ED hr\u00E1\u010Di, kte\u0159\u00ED je\u0161t\u011B mohou s\u00E1zet.",
              "V\u0161echny s\u00E1zky tvo\u0159\u00ED spole\u010Dn\u00FD bank. Velikost pod\u00EDlu ur\u010Duje, kolik by tvoje s\u00E1zka vr\u00E1tila v kasinu. Pokud \u017E\u00E1dn\u00E1 s\u00E1zka nic nevr\u00E1t\u00ED, dostane ka\u017Ed\u00FD zp\u011Bt sv\u00E9 vklady."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "C: st\u00E1hnout vlastn\u00ED s\u00E1zky",
              "R: skon\u010Dit s\u00E1zen\u00ED",
              "V: p\u0159e\u010D\u00EDst vlastn\u00ED s\u00E1zky",
              "S: zjistit z\u016Fstatky",
              "Mezern\u00EDk: rozto\u010Dit kolo u spole\u010Densk\u00E9ho stolu")
          ]
        when "en"
          [
            rule_section(:aim, "Betting and winning",
              "On your turn, bet virtual chips on a number or a group of numbers. Use the arrows to choose a bet type and open it with Enter. Select a bet and press Enter to enter the stake. You can keep the suggested amount or change it, then confirm with Enter. You can place several bets as long as you have enough chips.",
              "Before ending your turn, press C to withdraw your bets and get the stakes back. Press R when you are done betting. Once all players finish, the wheel spins automatically. Bets covering the winning number are paid.",
              "The highest balance after the agreed spins wins. Equal highest balances draw. Bets use whole chips; payouts can include half a chip. Play ends early if nobody can still bet, or if only one player can bet at a social table."),
            rule_section(:bets, "Wheels and payouts",
              "The European wheel has 0\u201336; the American wheel adds 00. Neither zero is part of a colour, odd/even or low/high bet. With the French wheel you get half of such a bet back if the ball lands on zero.",
              "A winning bet returns your stake and pays a profit at the following rates:",
              "- One number: 35 to 1; two neighbours: 17 to 1; three: 11 to 1; four: 8 to 1.",
              "- Six numbers: 5 to 1; the first five on an American wheel: 6 to 1.",
              "- A dozen or column: 2 to 1; a colour, odd/even or low/high: 1 to 1."),
            rule_section(:modes, "Social table",
              "At a social table, at least two people play. Once betting is closed, the player assigned to spin presses Space. This rotates among players who can still bet.",
              "All stakes go into a shared pot. You get a share in proportion to the amount your bet would return at a casino table. If none of the bets returns anything, all players get their stakes back."),
            rule_section(:controls, "Keyboard shortcuts",
              "C: withdraw your bets",
              "R: finish betting",
              "V: read your bets",
              "S: read balances",
              "Space: spin at a social table")
          ]
        when "es"
          [
            rule_section(:aim, "Apuestas y resultado",
              "En tu turno puedes apostar fichas virtuales a un n\u00FAmero o a un grupo. Elige el tipo de apuesta con las flechas y pulsa Intro para abrirlo. Selecciona una apuesta y pulsa Intro para indicar el importe. Puedes conservar la cantidad propuesta o cambiarla; confirma con Intro. Puedes hacer varias apuestas si tienes fichas suficientes.",
              "Antes de ceder el turno, C retira todas tus apuestas y devuelve las fichas. Pulsa R cuando hayas terminado. Despu\u00E9s de todas las apuestas, la rueda gira sola. Cobran las apuestas que incluyen el n\u00FAmero en el que cae la bola.",
              "Gana quien tenga m\u00E1s fichas al terminar las tiradas acordadas. Si coinciden los mejores saldos, hay empate. Las apuestas se hacen en fichas enteras; los pagos pueden incluir media ficha. La partida termina antes si nadie puede apostar, o si en la mesa social solo puede hacerlo una persona."),
            rule_section(:bets, "Ruedas y pagos",
              "La rueda europea va del 0 al 36; la americana a\u00F1ade el 00. Ninguno de los ceros cuenta para las apuestas de color, paridad o mitad baja o alta. En la francesa, si sale cero se devuelve la mitad de esas apuestas.",
              "Si aciertas, recuperas lo apostado y ganas lo siguiente:",
              "- Un n\u00FAmero: 35 a 1; dos vecinos: 17 a 1; tres: 11 a 1; cuatro: 8 a 1.",
              "- Seis n\u00FAmeros: 5 a 1; los cinco primeros de la rueda americana: 6 a 1.",
              "- Docena o columna: 2 a 1; color, paridad o mitad: 1 a 1."),
            rule_section(:modes, "Mesa social",
              "Juegan al menos dos personas. Cuando todos terminan de apostar, quien tenga asignado el giro pulsa Espacio. Ese turno va rotando entre quienes a\u00FAn pueden apostar.",
              "Las apuestas forman un bote com\u00FAn. La parte que te toca es proporcional a lo que te devolver\u00EDa tu apuesta en el casino. Si ninguna apuesta devuelve nada, cada cual recupera lo que puso."),
            rule_section(:controls, "Atajos de teclado",
              "C: retirar tus apuestas",
              "R: terminar de apostar",
              "V: leer tus apuestas",
              "S: consultar los saldos",
              "Espacio: girar la rueda en la mesa social")
          ]
        when "pl"
          [
            rule_section(:aim, "Obstawianie i wynik",
              "W swojej turze mo\u017Cesz postawi\u0107 wirtualne \u017Cetony na pojedynczy numer albo grup\u0119 numer\u00F3w. Strza\u0142kami wybierz rodzaj zak\u0142adu i otw\u00F3rz go Enterem. Wybierz zak\u0142ad i naci\u015Bnij Enter, aby wpisa\u0107 stawk\u0119. Mo\u017Cesz pozostawi\u0107 proponowan\u0105 kwot\u0119 albo j\u0105 zmieni\u0107, a potem zatwierdzi\u0107 Enterem. Wolno stawia\u0107 kilka zak\u0142ad\u00F3w, ale \u0142\u0105cznie nie wi\u0119cej, ni\u017C masz \u017Ceton\u00F3w.",
              "Przed ko\u0144cem swojej tury klawiszem C mo\u017Cesz zdj\u0105\u0107 wszystkie swoje zak\u0142ady i odzyska\u0107 stawki. Klawisz R ko\u0144czy obstawianie. Gdy wszyscy sko\u0144cz\u0105, ko\u0142o kr\u0119ci si\u0119 automatycznie, a zak\u0142ady obejmuj\u0105ce wylosowany numer wygrywaj\u0105.",
              "Po ustalonej liczbie obrot\u00F3w wygrywa osoba z najwi\u0119ksz\u0105 liczb\u0105 \u017Ceton\u00F3w. R\u00F3wne najwy\u017Csze salda daj\u0105 remis. Zak\u0142ady przyjmowane s\u0105 od jednego \u017Cetonu; wyp\u0142ata mo\u017Ce zawiera\u0107 po\u0142\u00F3wk\u0119. Mecz ko\u0144czy si\u0119 wcze\u015Bniej, je\u015Bli nikt nie mo\u017Ce ju\u017C obstawia\u0107, a przy stole towarzyskim tak\u017Ce wtedy, gdy mo\u017Ce to robi\u0107 tylko jedna osoba."),
            rule_section(:bets, "Ko\u0142a i wyp\u0142aty",
              "Europejskie ko\u0142o ma numery od 0 do 36; ameryka\u0144skie ma tak\u017Ce 00. Zero i 00 nie nale\u017C\u0105 do zak\u0142ad\u00F3w na kolor, parzysto\u015B\u0107 ani zakres 1\u201318 lub 19\u201336. Przy kole francuskim na zerze odzyskujesz po\u0142ow\u0119 stawki z takiego zak\u0142adu.",
              "Przy wygranej odzyskujesz stawk\u0119 i dostajesz zysk wed\u0142ug zak\u0142adu:",
              "- Jeden numer: 35 do 1; dwa s\u0105siednie: 17 do 1; trzy: 11 do 1; cztery: 8 do 1.",
              "- Sze\u015B\u0107 numer\u00F3w: 5 do 1; pierwsza pi\u0105tka na kole ameryka\u0144skim: 6 do 1.",
              "- Tuzin albo kolumna: 2 do 1; kolor, parzysto\u015B\u0107 lub po\u0142owa numer\u00F3w: 1 do 1."),
            rule_section(:modes, "St\u00F3\u0142 towarzyski",
              "W grze towarzyskiej potrzeba co najmniej dw\u00F3ch os\u00F3b. Po zako\u0144czeniu obstawiania jedna z nich kr\u0119ci ko\u0142em Spacj\u0105. Zadanie przechodzi na kolejn\u0105 osob\u0119, kt\u00F3ra mo\u017Ce jeszcze obstawia\u0107.",
              "Gracze dziel\u0105 mi\u0119dzy siebie pul\u0119 wszystkich stawek. Im wi\u0119kszy zwrot da\u0142by tw\u00F3j zak\u0142ad w kasynie, tym wi\u0119ksz\u0105 cz\u0119\u015B\u0107 puli dostaniesz. Je\u015Bli \u017Caden zak\u0142ad nie daje zwrotu, ka\u017Cdy odzyskuje swoje stawki."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "C: wycofaj swoje zak\u0142ady",
              "R: zako\u0144cz obstawianie",
              "V: odczytaj swoje zak\u0142ady",
              "S: sprawd\u017A salda",
              "Spacja: zakr\u0119\u0107 ko\u0142em przy stole towarzyskim")
          ]
        when "ru"
          [
            rule_section(:aim, "\u0421\u0442\u0430\u0432\u043A\u0438 \u0438 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442",
              "\u0412 \u0441\u0432\u043E\u0439 \u0445\u043E\u0434 \u043C\u043E\u0436\u043D\u043E \u043F\u043E\u0441\u0442\u0430\u0432\u0438\u0442\u044C \u0432\u0438\u0440\u0442\u0443\u0430\u043B\u044C\u043D\u044B\u0435 \u0444\u0438\u0448\u043A\u0438 \u043D\u0430 \u043D\u043E\u043C\u0435\u0440 \u0438\u043B\u0438 \u0433\u0440\u0443\u043F\u043F\u0443 \u043D\u043E\u043C\u0435\u0440\u043E\u0432. \u0412\u044B\u0431\u0435\u0440\u0438 \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0442\u0438\u043F \u0441\u0442\u0430\u0432\u043A\u0438 \u0438 \u043E\u0442\u043A\u0440\u043E\u0439 \u0435\u0433\u043E \u043A\u043B\u0430\u0432\u0438\u0448\u0435\u0439 Enter. \u0417\u0430\u0442\u0435\u043C \u0432\u044B\u0431\u0435\u0440\u0438 \u0441\u0442\u0430\u0432\u043A\u0443 \u0438 \u043D\u0430\u0436\u043C\u0438 Enter, \u0447\u0442\u043E\u0431\u044B \u0432\u0432\u0435\u0441\u0442\u0438 \u0441\u0443\u043C\u043C\u0443. \u041C\u043E\u0436\u043D\u043E \u043E\u0441\u0442\u0430\u0432\u0438\u0442\u044C \u043F\u0440\u0435\u0434\u043B\u043E\u0436\u0435\u043D\u043D\u0443\u044E \u0441\u0443\u043C\u043C\u0443 \u0438\u043B\u0438 \u0438\u0437\u043C\u0435\u043D\u0438\u0442\u044C \u0435\u0451, \u0430 \u0437\u0430\u0442\u0435\u043C \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u044C \u043A\u043B\u0430\u0432\u0438\u0448\u0435\u0439 Enter. \u0421\u0442\u0430\u0432\u043E\u043A \u043C\u043E\u0436\u0435\u0442 \u0431\u044B\u0442\u044C \u043D\u0435\u0441\u043A\u043E\u043B\u044C\u043A\u043E, \u0435\u0441\u043B\u0438 \u0445\u0432\u0430\u0442\u0430\u0435\u0442 \u0444\u0438\u0448\u0435\u043A.",
              "\u041F\u043E\u043A\u0430 \u0445\u043E\u0434 \u0442\u0432\u043E\u0439, \u043A\u043B\u0430\u0432\u0438\u0448\u0430 C \u0441\u043D\u0438\u043C\u0430\u0435\u0442 \u0432\u0441\u0435 \u0442\u0432\u043E\u0438 \u0441\u0442\u0430\u0432\u043A\u0438 \u0438 \u0432\u043E\u0437\u0432\u0440\u0430\u0449\u0430\u0435\u0442 \u0444\u0438\u0448\u043A\u0438. \u041A\u043B\u0430\u0432\u0438\u0448\u0430 R \u0437\u0430\u0432\u0435\u0440\u0448\u0430\u0435\u0442 \u0441\u0442\u0430\u0432\u043A\u0438. \u041A\u043E\u0433\u0434\u0430 \u0432\u0441\u0435 \u0437\u0430\u043A\u043E\u043D\u0447\u0430\u0442, \u0440\u0443\u043B\u0435\u0442\u043A\u0430 \u0437\u0430\u043F\u0443\u0441\u043A\u0430\u0435\u0442\u0441\u044F \u0430\u0432\u0442\u043E\u043C\u0430\u0442\u0438\u0447\u0435\u0441\u043A\u0438. \u0421\u0442\u0430\u0432\u043A\u0430 \u0432\u044B\u0438\u0433\u0440\u044B\u0432\u0430\u0435\u0442, \u0435\u0441\u043B\u0438 \u0432 \u043D\u0435\u0451 \u0432\u0445\u043E\u0434\u0438\u0442 \u0432\u044B\u043F\u0430\u0432\u0448\u0438\u0439 \u043D\u043E\u043C\u0435\u0440.",
              "\u041F\u043E\u0441\u043B\u0435 \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0435\u0433\u043E \u0432\u0440\u0430\u0449\u0435\u043D\u0438\u044F \u0432\u044B\u0438\u0433\u0440\u044B\u0432\u0430\u0435\u0442 \u043D\u0430\u0438\u0431\u043E\u043B\u044C\u0448\u0438\u0439 \u043E\u0441\u0442\u0430\u0442\u043E\u043A \u0444\u0438\u0448\u0435\u043A. \u0420\u0430\u0432\u043D\u044B\u0435 \u043D\u0430\u0438\u0431\u043E\u043B\u044C\u0448\u0438\u0435 \u043E\u0441\u0442\u0430\u0442\u043A\u0438 \u0434\u0430\u044E\u0442 \u043D\u0438\u0447\u044C\u044E. \u0421\u0442\u0430\u0432\u044F\u0442 \u0446\u0435\u043B\u044B\u0435 \u0444\u0438\u0448\u043A\u0438, \u043D\u043E \u0432\u044B\u043F\u043B\u0430\u0442\u0430 \u043C\u043E\u0436\u0435\u0442 \u0432\u043A\u043B\u044E\u0447\u0430\u0442\u044C \u043F\u043E\u043B\u043E\u0432\u0438\u043D\u0443 \u0444\u0438\u0448\u043A\u0438. \u0418\u0433\u0440\u0430 \u0437\u0430\u043A\u0430\u043D\u0447\u0438\u0432\u0430\u0435\u0442\u0441\u044F \u0440\u0430\u043D\u044C\u0448\u0435, \u0435\u0441\u043B\u0438 \u043D\u0438\u043A\u0442\u043E \u043D\u0435 \u043C\u043E\u0436\u0435\u0442 \u0441\u0442\u0430\u0432\u0438\u0442\u044C, \u0430 \u0437\u0430 \u0442\u043E\u0432\u0430\u0440\u0438\u0449\u0435\u0441\u043A\u0438\u043C \u0441\u0442\u043E\u043B\u043E\u043C \u2014 \u0438 \u0435\u0441\u043B\u0438 \u043E\u0441\u0442\u0430\u043B\u0441\u044F \u0442\u043E\u043B\u044C\u043A\u043E \u043E\u0434\u0438\u043D \u0442\u0430\u043A\u043E\u0439 \u0438\u0433\u0440\u043E\u043A."),
            rule_section(:bets, "\u041A\u043E\u043B\u0451\u0441\u0430 \u0438 \u0432\u044B\u043F\u043B\u0430\u0442\u044B",
              "\u041D\u0430 \u0435\u0432\u0440\u043E\u043F\u0435\u0439\u0441\u043A\u043E\u043C \u043A\u043E\u043B\u0435\u0441\u0435 \u0447\u0438\u0441\u043B\u0430 \u043E\u0442 0 \u0434\u043E 36, \u043D\u0430 \u0430\u043C\u0435\u0440\u0438\u043A\u0430\u043D\u0441\u043A\u043E\u043C \u0435\u0441\u0442\u044C \u0435\u0449\u0451 00. \u041D\u0443\u043B\u0438 \u043D\u0435 \u0432\u0445\u043E\u0434\u044F\u0442 \u0432 \u0441\u0442\u0430\u0432\u043A\u0438 \u043D\u0430 \u0446\u0432\u0435\u0442, \u0447\u0451\u0442\u043D\u043E\u0441\u0442\u044C \u0438\u043B\u0438 \u043D\u0438\u0436\u043D\u044E\u044E \u0438 \u0432\u0435\u0440\u0445\u043D\u044E\u044E \u043F\u043E\u043B\u043E\u0432\u0438\u043D\u044B. \u041D\u0430 \u0444\u0440\u0430\u043D\u0446\u0443\u0437\u0441\u043A\u043E\u043C \u043A\u043E\u043B\u0435\u0441\u0435 \u043F\u0440\u0438 \u0432\u044B\u043F\u0430\u0434\u0435\u043D\u0438\u0438 \u043D\u0443\u043B\u044F \u0432\u043E\u0437\u0432\u0440\u0430\u0449\u0430\u0435\u0442\u0441\u044F \u043F\u043E\u043B\u043E\u0432\u0438\u043D\u0430 \u0442\u0430\u043A\u043E\u0439 \u0441\u0442\u0430\u0432\u043A\u0438.",
              "\u041F\u0440\u0438 \u0432\u044B\u0438\u0433\u0440\u044B\u0448\u0435 \u0441\u0442\u0430\u0432\u043A\u0430 \u0432\u043E\u0437\u0432\u0440\u0430\u0449\u0430\u0435\u0442\u0441\u044F, \u0430 \u043A \u043D\u0435\u0439 \u043F\u0440\u0438\u0431\u0430\u0432\u043B\u044F\u0435\u0442\u0441\u044F \u0432\u044B\u0438\u0433\u0440\u044B\u0448:",
              "- \u041E\u0434\u0438\u043D \u043D\u043E\u043C\u0435\u0440: 35 \u043A 1; \u0434\u0432\u0430 \u0441\u043E\u0441\u0435\u0434\u043D\u0438\u0445: 17 \u043A 1; \u0442\u0440\u0438: 11 \u043A 1; \u0447\u0435\u0442\u044B\u0440\u0435: 8 \u043A 1.",
              "- \u0428\u0435\u0441\u0442\u044C \u043D\u043E\u043C\u0435\u0440\u043E\u0432: 5 \u043A 1; \u043F\u0435\u0440\u0432\u0430\u044F \u043F\u044F\u0442\u0451\u0440\u043A\u0430 \u043D\u0430 \u0430\u043C\u0435\u0440\u0438\u043A\u0430\u043D\u0441\u043A\u043E\u043C \u043A\u043E\u043B\u0435\u0441\u0435: 6 \u043A 1.",
              "- \u0414\u044E\u0436\u0438\u043D\u0430 \u0438\u043B\u0438 \u043A\u043E\u043B\u043E\u043D\u043A\u0430: 2 \u043A 1; \u0446\u0432\u0435\u0442, \u0447\u0451\u0442\u043D\u043E\u0441\u0442\u044C \u0438\u043B\u0438 \u043F\u043E\u043B\u043E\u0432\u0438\u043D\u0430 \u043D\u043E\u043C\u0435\u0440\u043E\u0432: 1 \u043A 1."),
            rule_section(:modes, "\u0422\u043E\u0432\u0430\u0440\u0438\u0449\u0435\u0441\u043A\u0438\u0439 \u0441\u0442\u043E\u043B",
              "\u041D\u0443\u0436\u043D\u043E \u043D\u0435 \u043C\u0435\u043D\u044C\u0448\u0435 \u0434\u0432\u0443\u0445 \u0438\u0433\u0440\u043E\u043A\u043E\u0432. \u041A\u043E\u0433\u0434\u0430 \u0432\u0441\u0435 \u0437\u0430\u043A\u043E\u043D\u0447\u0430\u0442 \u0441\u0442\u0430\u0432\u043A\u0438, \u043D\u0430\u0437\u043D\u0430\u0447\u0435\u043D\u043D\u044B\u0439 \u0438\u0433\u0440\u043E\u043A \u0437\u0430\u043F\u0443\u0441\u043A\u0430\u0435\u0442 \u0440\u0443\u043B\u0435\u0442\u043A\u0443 \u043F\u0440\u043E\u0431\u0435\u043B\u043E\u043C. \u0412 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0438\u0439 \u0440\u0430\u0437 \u044D\u0442\u043E \u0434\u0435\u043B\u0430\u0435\u0442 \u0434\u0440\u0443\u0433\u043E\u0439 \u0438\u0433\u0440\u043E\u043A, \u0443 \u043A\u043E\u0442\u043E\u0440\u043E\u0433\u043E \u0445\u0432\u0430\u0442\u0430\u0435\u0442 \u0444\u0438\u0448\u0435\u043A \u043D\u0430 \u0441\u0442\u0430\u0432\u043A\u0443.",
              "\u0412\u0441\u0435 \u0441\u0442\u0430\u0432\u043A\u0438 \u043E\u0431\u0440\u0430\u0437\u0443\u044E\u0442 \u043E\u0431\u0449\u0438\u0439 \u0431\u0430\u043D\u043A. \u0414\u043E\u043B\u044F \u0438\u0433\u0440\u043E\u043A\u0430 \u043F\u0440\u043E\u043F\u043E\u0440\u0446\u0438\u043E\u043D\u0430\u043B\u044C\u043D\u0430 \u0442\u043E\u043C\u0443, \u0441\u043A\u043E\u043B\u044C\u043A\u043E \u0432\u0435\u0440\u043D\u0443\u043B\u0430 \u0431\u044B \u0435\u0433\u043E \u0441\u0442\u0430\u0432\u043A\u0430 \u0432 \u043A\u0430\u0437\u0438\u043D\u043E. \u0415\u0441\u043B\u0438 \u043D\u0438 \u043E\u0434\u043D\u0430 \u0441\u0442\u0430\u0432\u043A\u0430 \u043D\u0435 \u0434\u0430\u0451\u0442 \u0432\u043E\u0437\u0432\u0440\u0430\u0442\u0430, \u043A\u0430\u0436\u0434\u044B\u0439 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u0441\u0432\u043E\u0439 \u0432\u0437\u043D\u043E\u0441 \u043E\u0431\u0440\u0430\u0442\u043D\u043E."),
            rule_section(:controls, "\u0413\u043E\u0440\u044F\u0447\u0438\u0435 \u043A\u043B\u0430\u0432\u0438\u0448\u0438",
              "C: \u0441\u043D\u044F\u0442\u044C \u0441\u0432\u043E\u0438 \u0441\u0442\u0430\u0432\u043A\u0438",
              "R: \u0437\u0430\u043A\u043E\u043D\u0447\u0438\u0442\u044C \u0441\u0442\u0430\u0432\u043A\u0438",
              "V: \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u0441\u0432\u043E\u0438 \u0441\u0442\u0430\u0432\u043A\u0438",
              "S: \u0443\u0437\u043D\u0430\u0442\u044C \u043E\u0441\u0442\u0430\u0442\u043A\u0438 \u0444\u0438\u0448\u0435\u043A",
              "\u041F\u0440\u043E\u0431\u0435\u043B: \u0437\u0430\u043F\u0443\u0441\u0442\u0438\u0442\u044C \u0440\u0443\u043B\u0435\u0442\u043A\u0443 \u0437\u0430 \u0442\u043E\u0432\u0430\u0440\u0438\u0449\u0435\u0441\u043A\u0438\u043C \u0441\u0442\u043E\u043B\u043E\u043C")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
