# Generated from tools/data/rulebooks/cat_head_tail.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class CatHeadTail
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:rules, GameRoomRules.translate("Cat, head, tail is a dice game for two to eight players created by TD Programs."),
            GameRoomRules.translate("It is a simple game based on PIG from RS Games containing several differences, which are described below:\nFirst of all, instead of six, the die has eight sides.\n1 loses all points collected so far and ends the turn;\n2 is automatically added to the bank, but the same player may continue playing;\n7 is Head (the cat's head), which does absolutely nothing;\n8 is tail (the cat's tail), which randomly adds or subtracts 8 points.\nThe target score is selected when creating the table; the default is 100.\nAfter the last player's turn in the round ends, the highest score wins. If several players have the same highest score, the game ends in a draw.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: choose an option.\nEnter: confirm the selection.\nS: read scores.\nC: read the number of points in hand.\nT: check whose turn it is."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:goal, "C\u00EDl hry",
              "V Cat, Head, Tail h\u00E1z\u00ED\u0161 osmist\u011Bnnou kostkou a vol\u00ED\u0161, jak dlouho bude\u0161 riskovat. Body z tahu m\u016F\u017Ee\u0161 ulo\u017Eit do banku nebo pokra\u010Dovat v h\u00E1zen\u00ED. Kdy\u017E ale padne jedni\u010Dka, tah kon\u010D\u00ED a neulo\u017Een\u00E9 body ztrat\u00ED\u0161.",
              "Hra je pro dva a\u017E osm hr\u00E1\u010D\u016F. K v\u00EDt\u011Bzstv\u00ED pot\u0159ebuje\u0161 m\u00EDt v banku nejm\u00E9n\u011B 100 bod\u016F a p\u0159ekonat ostatn\u00ED."),
            rule_section(:turn, "Hody a ukl\u00E1d\u00E1n\u00ED bod\u016F",
              "Na za\u010D\u00E1tku tahu vyber \u0161ipkami hod kostkou a potvr\u010F Enterem. \u010C\u00EDsla od 3 do 6 p\u0159idaj\u00ED pr\u00E1v\u011B tolik bod\u016F do tohoto tahu. Pak se rozhodni, jestli hod\u00ED\u0161 znovu, nebo vybere\u0161 ulo\u017Een\u00ED bod\u016F. Ulo\u017Een\u00ED potvrzen\u00E9 Enterem p\u0159i\u010Dte v\u00FDsledek tahu do banku a p\u0159ed\u00E1 \u0159adu dal\u0161\u00EDmu hr\u00E1\u010Di.",
              "Kdy\u017E padne 4 a potom 5, m\u00E1\u0161 p\u0159ipraven\u00FDch 9 bod\u016F. Zastav\u00ED\u0161-li se, ulo\u017E\u00ED\u0161 je. Pokud m\u00EDsto toho hod\u00ED\u0161 jedni\u010Dku, t\u011Bchto 9 ztrat\u00ED\u0161; d\u0159\u00EDve ulo\u017Een\u00FDch bod\u016F se ztr\u00E1ta net\u00FDk\u00E1.",
              "Kl\u00E1vesa C p\u0159e\u010Dte body pr\u00E1v\u011B prob\u00EDhaj\u00EDc\u00EDho tahu, S ulo\u017Een\u00E9 v\u00FDsledky v\u0161ech hr\u00E1\u010D\u016F."),
            rule_section(:dice, "Zvl\u00E1\u0161tn\u00ED v\u00FDsledky hodu",
              "Dal\u0161\u00ED \u010Dty\u0159i st\u011Bny kostky maj\u00ED vlastn\u00ED \u00FA\u010Dinky:",
              "- Jedni\u010Dka vynuluje body tohoto tahu a ukon\u010D\u00ED ho. Vynuluje i z\u00E1porn\u00FD v\u00FDsledek.",
              "- Dvojka p\u0159id\u00E1 2 body p\u0159\u00EDmo do banku a dovol\u00ED pokra\u010Dovat. Pozd\u011Bj\u0161\u00ED jedni\u010Dka tyto body nevezme.",
              "- Sedmi\u010Dka je ko\u010Di\u010D\u00ED hlava. Body nijak nezm\u011Bn\u00ED; d\u00E1l se rozhoduje\u0161 mezi hodem a ulo\u017Een\u00EDm.",
              "- Osmi\u010Dka je ko\u010Di\u010D\u00ED ocas. N\u00E1hodn\u011B p\u0159id\u00E1 8 bod\u016F do tahu, nebo z n\u011Bj 8 odebere. Ani t\u00EDm tah nekon\u010D\u00ED.",
              "Ko\u010Di\u010D\u00ED ocas m\u016F\u017Ee srazit v\u00FDsledek tahu pod nulu. Kdy\u017E ho takto ulo\u017E\u00ED\u0161, ubere\u0161 si body z banku. Dal\u0161\u00EDmi hody se m\u016F\u017Ee\u0161 pokusit ztr\u00E1tu dohnat; jedni\u010Dka by cel\u00FD z\u00E1porn\u00FD v\u00FDsledek tahu vymazala."),
            rule_section(:finish, "Dohra a v\u00EDt\u011Bzstv\u00ED",
              "Jakmile m\u00E1 n\u011Bkdo na konci sv\u00E9ho tahu v banku aspo\u0148 100 bod\u016F, dohrajete aktu\u00E1ln\u00ED kolo tah\u016F. Na \u0159adu je\u0161t\u011B p\u0159ijdou ti, kdo v n\u011Bm dosud nehr\u00E1li.",
              "Ve \u010Dty\u0159ech hr\u00E1\u010D\u00EDch tedy po dosa\u017Een\u00ED c\u00EDle druh\u00FDm hr\u00E1\u010Dem hraje je\u0161t\u011B t\u0159et\u00ED a \u010Dtvrt\u00FD. Potom se porovnaj\u00ED banky: nejvy\u0161\u0161\u00ED v\u00FDsledek vyhr\u00E1v\u00E1, p\u0159i shod\u011B nejvy\u0161\u0161\u00EDch v\u00FDsledk\u016F je rem\u00EDza."),
            rule_section(:options, "Jin\u00FD bodov\u00FD c\u00EDl",
              "P\u0159ed hrou m\u016F\u017Ee\u0161 v nastaven\u00ED stolu nahradit 100 bod\u016F jin\u00FDm kladn\u00FDm c\u00EDlem. P\u0159ed kone\u010Dn\u00FDm porovn\u00E1n\u00EDm se i tak dohraje cel\u00E9 rozehran\u00E9 kolo tah\u016F."),
            rule_section(:credits, "P\u016Fvod hry",
              "Cat, Head, Tail vytvo\u0159ilo TD Programs. Vych\u00E1z\u00ED z PIG od RS Games, pou\u017E\u00EDv\u00E1 v\u0161ak osmist\u011Bnnou kostku a \u00FA\u010Dinky popsan\u00E9 v t\u011Bchto pravidlech."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "\u0160ipky: zvolit hod nebo ulo\u017Een\u00ED bod\u016F.",
              "Enter: prov\u00E9st vybranou akci.",
              "C: p\u0159e\u010D\u00EDst body aktu\u00E1ln\u00EDho tahu.",
              "S: p\u0159e\u010D\u00EDst body v banku.",
              "D: p\u0159e\u010D\u00EDst posledn\u00ED hod.",
              "T: ozn\u00E1mit, kdo je na tahu.")
          ]
        when "en"
          [
            rule_section(:goal, "The game",
              "Cat, head, tail is a dice game about deciding when to stop. Roll an eight-sided die to build a turn score, then bank it before a 1 wipes it out.",
              "Two to eight players compete to bank at least 100 points and finish with the highest score."),
            rule_section(:turn, "Rolling and banking",
              "On your turn, use the arrows to choose Roll the die and press Enter. Rolls from 3 to 6 add that many points to your turn score. After a roll, you can roll again or choose to bank your points and confirm with Enter. Banking adds the turn score to your bank and passes play to the next person.",
              "For example, a 4 followed by a 5 leaves 9 points waiting to be banked. Stop now and you keep them. Risk another roll and get a 1, and you lose those 9 points, but not anything banked on earlier turns.",
              "C reads your current turn score; S reads everyone's banked scores."),
            rule_section(:dice, "Special rolls",
              "The other four faces work differently:",
              "- A 1 clears the turn score and ends your turn immediately. This also clears a negative turn score.",
              "- A 2 goes straight into your bank. You can keep playing, and a later 1 cannot take those 2 points away.",
              "- A 7 is the cat's head. It changes no score, leaving you free to roll again or bank.",
              "- An 8 is the cat's tail. It randomly adds 8 to your turn score or subtracts 8. You can keep playing afterwards.",
              "The tail can leave you below zero for the turn. Banking a negative score reduces your bank. You can try to recover with more rolls; a 1 wipes out the negative turn score instead."),
            rule_section(:finish, "Ending the game",
              "When someone ends a turn with at least 100 banked points, finish the current round of turns. Anyone who has not yet had their turn in that round still gets to play.",
              "With four players, for instance, if the second reaches the target, the third and fourth take their turns. Then compare banked scores: the highest wins, and a tie for the lead means a draw."),
            rule_section(:options, "Changing the target",
              "Before starting, the host can change the target from 100 to another positive number. The current round of turns is still completed before deciding the result."),
            rule_section(:credits, "Origins",
              "Cat, head, tail was created by TD Programs. It is based on PIG from RS Games, with an eight-sided die and the effects described here."),
            rule_section(:controls, "Keyboard shortcuts",
              "Arrows: choose rolling or banking.",
              "Enter: carry out the selected action.",
              "C: read the turn score.",
              "S: read banked scores.",
              "D: read the last roll.",
              "T: check whose turn it is.")
          ]
        when "es"
          [
            rule_section(:goal, "Objetivo",
              "En Cat, Head, Tail lanzas un dado de ocho caras y decides hasta d\u00F3nde arriesgarte. Puedes seguir tirando para reunir puntos o guardarlos en tu banco y terminar el turno. Si sale un 1, el turno acaba y pierdes lo que a\u00FAn no hab\u00EDas guardado.",
              "Juegan de dos a ocho personas. Tu objetivo es alcanzar al menos 100 puntos en el banco y terminar con m\u00E1s que los dem\u00E1s."),
            rule_section(:turn, "Tirar o guardar los puntos",
              "En tu turno, elige lanzar el dado con las flechas y pulsa Enter. Los resultados del 3 al 6 a\u00F1aden su n\u00FAmero a los puntos del turno. Despu\u00E9s puedes volver a lanzar o elegir guardar los puntos y confirmar con Enter. Al guardarlos pasan al banco y juega la siguiente persona.",
              "Por ejemplo, un 4 seguido de un 5 te deja 9 puntos pendientes. Si te plantas, guardas los 9. Si vuelves a tirar y sale un 1, pierdes esos 9, pero conservas todo lo que hab\u00EDas guardado en turnos anteriores.",
              "C permite consultar los puntos del turno y S los bancos de todos los jugadores."),
            rule_section(:dice, "Las caras especiales",
              "El 1, el 2, el 7 y el 8 tienen efectos distintos:",
              "- El 1 deja en cero los puntos del turno y lo termina inmediatamente. Tambi\u00E9n lo hace si el turno ten\u00EDa una puntuaci\u00F3n negativa.",
              "- El 2 a\u00F1ade dos puntos directamente al banco. No termina el turno y un 1 posterior no puede quitar esos puntos.",
              "- El 7 es la cabeza del gato. No cambia ning\u00FAn resultado: sigues pudiendo tirar o guardar.",
              "- El 8 es la cola del gato. Al azar, suma 8 puntos al turno o resta 8. Despu\u00E9s puedes seguir jugando.",
              "La cola puede dejar el turno por debajo de cero. Si guardas ese resultado, restar\u00E1s puntos del banco. Puedes intentar recuperarlos con m\u00E1s tiradas; un 1 tambi\u00E9n elimina por completo el resultado negativo de ese turno."),
            rule_section(:finish, "Final de la partida",
              "Si alguien termina su turno con al menos 100 puntos en el banco, se completa la ronda de turnos actual. Solo juegan quienes a\u00FAn no hab\u00EDan tenido su turno en ella.",
              "Por ejemplo, si el segundo de cuatro jugadores alcanza la meta, todav\u00EDa juegan el tercero y el cuarto. Despu\u00E9s gana quien tenga m\u00E1s puntos en el banco. Si varias personas comparten el m\u00E1ximo, hay empate."),
            rule_section(:options, "Cambiar la meta",
              "Antes de empezar puedes sustituir la meta de 100 por cualquier otra cantidad positiva en los ajustes de la mesa. Tambi\u00E9n con esa meta se completa la ronda de turnos antes de comparar los resultados."),
            rule_section(:credits, "Origen del juego",
              "Cat, Head, Tail fue creado por TD Programs. Se basa en PIG de RS Games, con un dado de ocho caras y los efectos descritos en estas reglas."),
            rule_section(:controls, "Teclas de referencia",
              "Flechas: elegir entre lanzar y guardar los puntos.",
              "Enter: realizar la acci\u00F3n elegida.",
              "C: consultar los puntos del turno.",
              "S: consultar los bancos de los jugadores.",
              "D: consultar la \u00FAltima tirada.",
              "T: consultar de qui\u00E9n es el turno.")
          ]
        when "pl"
          [
            rule_section(:goal, "Cel gry",
              "W Cat, head, tail rzucasz o\u015Bmio\u015Bcienn\u0105 ko\u015Bci\u0105 i decydujesz, kiedy zapisa\u0107 zdobyte punkty. Mo\u017Cesz ryzykowa\u0107 kolejne rzuty albo przenie\u015B\u0107 wynik tury do banku. Jedynka ko\u0144czy tur\u0119 i kasuje to, czego jeszcze nie zapisa\u0142e\u015B.",
              "Gra jest dla dw\u00F3ch do o\u015Bmiu os\u00F3b. Starasz si\u0119 zgromadzi\u0107 co najmniej 100 punkt\u00F3w w banku i mie\u0107 ich wi\u0119cej ni\u017C pozostali."),
            rule_section(:turn, "Rzucanie i zapisywanie punkt\u00F3w",
              "W swojej turze wybierz strza\u0142kami \u201ERzu\u0107 ko\u015Bci\u0105\u201D i naci\u015Bnij Enter. Wyniki od 3 do 6 zwi\u0119kszaj\u0105 punkty bie\u017C\u0105cej tury o wyrzucon\u0105 liczb\u0119. Po rzucie mo\u017Cesz zagra\u0107 ponownie lub wybra\u0107 zapis punkt\u00F3w i potwierdzi\u0107 go Enterem. Zapis dodaje wynik tury do banku, po czym kolej przechodzi do nast\u0119pnej osoby.",
              "Za\u0142\u00F3\u017Cmy, \u017Ce wypada 4, a potem 5. Masz teraz 9 punkt\u00F3w do zapisania. Je\u017Celi si\u0119 zatrzymasz, trafi\u0105 do banku. Je\u015Bli zaryzykujesz i wypadnie 1, stracisz te 9, ale zachowasz punkty zapisane w poprzednich turach.",
              "Klawiszem C sprawdzisz punkty zdobyte w tej turze, a klawiszem S \u2014 zapisane wyniki graczy."),
            rule_section(:dice, "Pozosta\u0142e wyniki ko\u015Bci",
              "Jedynka, dw\u00F3jka, si\u00F3demka i \u00F3semka dzia\u0142aj\u0105 inaczej:",
              "- Jedynka zeruje punkty bie\u017C\u0105cej tury i od razu j\u0105 ko\u0144czy. Dzia\u0142a tak r\u00F3wnie\u017C wtedy, gdy wynik tury jest ujemny.",
              "- Dw\u00F3jka dopisuje 2 punkty bezpo\u015Brednio do banku. Nie ko\u0144czy tury, a jej punkt\u00F3w nie odbierze p\u00F3\u017Aniejsza jedynka.",
              "- Si\u00F3demka to g\u0142owa kota. Nie zmienia \u017Cadnego wyniku, wi\u0119c nadal decydujesz, czy rzuca\u0107, czy zapisywa\u0107.",
              "- \u00D3semka to ogon kota. Losowo dodaje 8 punkt\u00F3w do wyniku tury albo odejmuje 8. Po niej tak\u017Ce mo\u017Cesz gra\u0107 dalej.",
              "Przez ogon kota wynik tury mo\u017Ce spa\u015B\u0107 poni\u017Cej zera. Je\u017Celi zapiszesz taki wynik, zmniejszysz liczb\u0119 punkt\u00F3w w banku. Mo\u017Cesz pr\u00F3bowa\u0107 odrobi\u0107 strat\u0119 nast\u0119pnymi rzutami; jedynka usunie ca\u0142y ujemny wynik tej tury."),
            rule_section(:finish, "Koniec gry",
              "Gdy na koniec swojej tury kto\u015B ma w banku co najmniej 100 punkt\u00F3w, doka\u0144czacie bie\u017C\u0105c\u0105 kolejk\u0119. Graj\u0105 jeszcze osoby, kt\u00F3re nie mia\u0142y w niej swojej tury.",
              "Je\u017Celi spo\u015Br\u00F3d czterech graczy druga osoba osi\u0105gnie cel, zagraj\u0105 jeszcze trzecia i czwarta. Nast\u0119pnie wygrywa osoba z najwy\u017Cszym wynikiem w banku. Przy r\u00F3wnych najwy\u017Cszych wynikach jest remis."),
            rule_section(:options, "Inny cel punktowy",
              "W ustawieniach sto\u0142u przed gr\u0105 mo\u017Cna zmieni\u0107 cel ze 100 na inn\u0105 dodatni\u0105 liczb\u0119 punkt\u00F3w. Nadal ko\u0144czycie bie\u017C\u0105c\u0105 kolejk\u0119 tur przed por\u00F3wnaniem wynik\u00F3w."),
            rule_section(:credits, "Pochodzenie gry",
              "Cat, head, tail stworzy\u0142o TD Programs. Gra opiera si\u0119 na PIG z RS Games, ale u\u017Cywa o\u015Bmio\u015Bciennej ko\u015Bci i opisanych tutaj efekt\u00F3w."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "Strza\u0142ki: wybierz rzut albo zapis punkt\u00F3w.",
              "Enter: wykonaj wybran\u0105 czynno\u015B\u0107.",
              "C: odczytaj punkty bie\u017C\u0105cej tury.",
              "S: odczytaj wyniki w bankach.",
              "D: odczytaj ostatni rzut.",
              "T: sprawd\u017A, czyja jest tura.")
          ]
        when "ru"
          [
            rule_section(:goal, "\u0426\u0435\u043B\u044C \u0438\u0433\u0440\u044B",
              "\u0412 Cat, Head, Tail \u0432\u044B \u0431\u0440\u043E\u0441\u0430\u0435\u0442\u0435 \u0432\u043E\u0441\u044C\u043C\u0438\u0433\u0440\u0430\u043D\u043D\u044B\u0439 \u043A\u0443\u0431\u0438\u043A \u0438 \u0440\u0435\u0448\u0430\u0435\u0442\u0435, \u043A\u043E\u0433\u0434\u0430 \u043E\u0441\u0442\u0430\u043D\u043E\u0432\u0438\u0442\u044C\u0441\u044F. \u041C\u043E\u0436\u043D\u043E \u0440\u0438\u0441\u043A\u043D\u0443\u0442\u044C \u0438 \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0438\u0442\u044C \u0431\u0440\u043E\u0441\u043A\u0438 \u0438\u043B\u0438 \u0441\u043E\u0445\u0440\u0430\u043D\u0438\u0442\u044C \u043E\u0447\u043A\u0438 \u0445\u043E\u0434\u0430 \u0432 \u0441\u0432\u043E\u0451\u043C \u0431\u0430\u043D\u043A\u0435. \u0412\u044B\u043F\u0430\u0432\u0448\u0430\u044F \u0435\u0434\u0438\u043D\u0438\u0446\u0430 \u0437\u0430\u043A\u0430\u043D\u0447\u0438\u0432\u0430\u0435\u0442 \u0445\u043E\u0434 \u0438 \u0441\u0442\u0438\u0440\u0430\u0435\u0442 \u0432\u0441\u0451, \u0447\u0442\u043E \u0432\u044B \u0435\u0449\u0451 \u043D\u0435 \u0441\u043E\u0445\u0440\u0430\u043D\u0438\u043B\u0438.",
              "\u0418\u0433\u0440\u0430\u044E\u0442 \u043E\u0442 \u0434\u0432\u0443\u0445 \u0434\u043E \u0432\u043E\u0441\u044C\u043C\u0438 \u0447\u0435\u043B\u043E\u0432\u0435\u043A. \u0412\u0430\u0448\u0430 \u0446\u0435\u043B\u044C \u2014 \u043D\u0430\u043A\u043E\u043F\u0438\u0442\u044C \u0432 \u0431\u0430\u043D\u043A\u0435 \u043D\u0435 \u043C\u0435\u043D\u044C\u0448\u0435 100 \u043E\u0447\u043A\u043E\u0432 \u0438 \u043E\u0431\u043E\u0439\u0442\u0438 \u043E\u0441\u0442\u0430\u043B\u044C\u043D\u044B\u0445."),
            rule_section(:turn, "\u0411\u0440\u043E\u0441\u043A\u0438 \u0438 \u0441\u043E\u0445\u0440\u0430\u043D\u0435\u043D\u0438\u0435 \u043E\u0447\u043A\u043E\u0432",
              "\u0412 \u0441\u0432\u043E\u0439 \u0445\u043E\u0434 \u0432\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0431\u0440\u043E\u0441\u043E\u043A \u043A\u0443\u0431\u0438\u043A\u0430 \u0438 \u043D\u0430\u0436\u043C\u0438\u0442\u0435 Enter. \u0417\u043D\u0430\u0447\u0435\u043D\u0438\u044F \u043E\u0442 3 \u0434\u043E 6 \u0434\u043E\u0431\u0430\u0432\u043B\u044F\u044E\u0442\u0441\u044F \u043A \u043E\u0447\u043A\u0430\u043C \u0442\u0435\u043A\u0443\u0449\u0435\u0433\u043E \u0445\u043E\u0434\u0430. \u041F\u043E\u0441\u043B\u0435 \u0431\u0440\u043E\u0441\u043A\u0430 \u0440\u0435\u0448\u0438\u0442\u0435, \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0430\u0442\u044C \u043B\u0438: \u0441\u043D\u043E\u0432\u0430 \u0432\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0431\u0440\u043E\u0441\u043E\u043A \u043B\u0438\u0431\u043E \u0441\u043E\u0445\u0440\u0430\u043D\u0435\u043D\u0438\u0435 \u043E\u0447\u043A\u043E\u0432 \u0438 \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u0435 Enter. \u041F\u0440\u0438 \u0441\u043E\u0445\u0440\u0430\u043D\u0435\u043D\u0438\u0438 \u043E\u0447\u043A\u0438 \u0445\u043E\u0434\u0430 \u043F\u0435\u0440\u0435\u0445\u043E\u0434\u044F\u0442 \u0432 \u0431\u0430\u043D\u043A, \u0430 \u0445\u043E\u0434 \u2014 \u043A \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0435\u043C\u0443 \u0438\u0433\u0440\u043E\u043A\u0443.",
              "\u041D\u0430\u043F\u0440\u0438\u043C\u0435\u0440, \u043F\u043E\u0441\u043B\u0435 \u0447\u0435\u0442\u0432\u0451\u0440\u043A\u0438 \u0438 \u043F\u044F\u0442\u0451\u0440\u043A\u0438 \u0432\u044B \u043C\u043E\u0436\u0435\u0442\u0435 \u0441\u043E\u0445\u0440\u0430\u043D\u0438\u0442\u044C 9 \u043E\u0447\u043A\u043E\u0432. \u0415\u0441\u043B\u0438 \u0432\u043C\u0435\u0441\u0442\u043E \u044D\u0442\u043E\u0433\u043E \u0431\u0440\u043E\u0441\u0438\u0442\u0435 \u0435\u0449\u0451 \u0440\u0430\u0437 \u0438 \u0432\u044B\u043F\u0430\u0434\u0435\u0442 \u0435\u0434\u0438\u043D\u0438\u0446\u0430, \u044D\u0442\u0438 9 \u043F\u0440\u043E\u043F\u0430\u0434\u0443\u0442. \u041E\u0447\u043A\u0438, \u0441\u043E\u0445\u0440\u0430\u043D\u0451\u043D\u043D\u044B\u0435 \u0432 \u043F\u0440\u0435\u0434\u044B\u0434\u0443\u0449\u0438\u0445 \u0445\u043E\u0434\u0430\u0445, \u043E\u0441\u0442\u0430\u043D\u0443\u0442\u0441\u044F \u043D\u0430 \u043C\u0435\u0441\u0442\u0435.",
              "\u041A\u043B\u0430\u0432\u0438\u0448\u0430 C \u0441\u043E\u043E\u0431\u0449\u0430\u0435\u0442 \u043E\u0447\u043A\u0438 \u0442\u0435\u043A\u0443\u0449\u0435\u0433\u043E \u0445\u043E\u0434\u0430, \u0430 S \u2014 \u0441\u043A\u043E\u043B\u044C\u043A\u043E \u043A\u0430\u0436\u0434\u044B\u0439 \u0443\u0436\u0435 \u0441\u043E\u0445\u0440\u0430\u043D\u0438\u043B \u0432 \u0431\u0430\u043D\u043A\u0435."),
            rule_section(:dice, "\u041E\u0441\u043E\u0431\u044B\u0435 \u0433\u0440\u0430\u043D\u0438 \u043A\u0443\u0431\u0438\u043A\u0430",
              "\u0423 \u0435\u0434\u0438\u043D\u0438\u0446\u044B, \u0434\u0432\u043E\u0439\u043A\u0438, \u0441\u0435\u043C\u0451\u0440\u043A\u0438 \u0438 \u0432\u043E\u0441\u044C\u043C\u0451\u0440\u043A\u0438 \u043E\u0441\u043E\u0431\u044B\u0435 \u0434\u0435\u0439\u0441\u0442\u0432\u0438\u044F:",
              "- \u0415\u0434\u0438\u043D\u0438\u0446\u0430 \u043E\u0431\u043D\u0443\u043B\u044F\u0435\u0442 \u043E\u0447\u043A\u0438 \u0442\u0435\u043A\u0443\u0449\u0435\u0433\u043E \u0445\u043E\u0434\u0430 \u0438 \u0441\u0440\u0430\u0437\u0443 \u0435\u0433\u043E \u0437\u0430\u043A\u0430\u043D\u0447\u0438\u0432\u0430\u0435\u0442. \u041E\u043D\u0430 \u043E\u0431\u043D\u0443\u043B\u044F\u0435\u0442 \u0434\u0430\u0436\u0435 \u043E\u0442\u0440\u0438\u0446\u0430\u0442\u0435\u043B\u044C\u043D\u044B\u0439 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442.",
              "- \u0414\u0432\u043E\u0439\u043A\u0430 \u0434\u043E\u0431\u0430\u0432\u043B\u044F\u0435\u0442 2 \u043E\u0447\u043A\u0430 \u043F\u0440\u044F\u043C\u043E \u0432 \u0431\u0430\u043D\u043A, \u043D\u0435 \u0437\u0430\u043A\u0430\u043D\u0447\u0438\u0432\u0430\u044F \u0445\u043E\u0434. \u042D\u0442\u0438 \u043E\u0447\u043A\u0438 \u0443\u0436\u0435 \u043D\u0435 \u043F\u043E\u0442\u0435\u0440\u044F\u044E\u0442\u0441\u044F, \u0434\u0430\u0436\u0435 \u0435\u0441\u043B\u0438 \u043F\u043E\u0442\u043E\u043C \u0432\u044B\u043F\u0430\u0434\u0435\u0442 \u0435\u0434\u0438\u043D\u0438\u0446\u0430.",
              "- \u0421\u0435\u043C\u0451\u0440\u043A\u0430 \u2014 \u043A\u043E\u0448\u0430\u0447\u044C\u044F \u0433\u043E\u043B\u043E\u0432\u0430. \u041E\u043D\u0430 \u043D\u0438\u0447\u0435\u0433\u043E \u043D\u0435 \u043C\u0435\u043D\u044F\u0435\u0442: \u043C\u043E\u0436\u043D\u043E \u0431\u0440\u043E\u0441\u0430\u0442\u044C \u0434\u0430\u043B\u044C\u0448\u0435 \u0438\u043B\u0438 \u0441\u043E\u0445\u0440\u0430\u043D\u0438\u0442\u044C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442.",
              "- \u0412\u043E\u0441\u044C\u043C\u0451\u0440\u043A\u0430 \u2014 \u043A\u043E\u0448\u0430\u0447\u0438\u0439 \u0445\u0432\u043E\u0441\u0442. \u041E\u043D \u0441\u043B\u0443\u0447\u0430\u0439\u043D\u044B\u043C \u043E\u0431\u0440\u0430\u0437\u043E\u043C \u043F\u0440\u0438\u0431\u0430\u0432\u043B\u044F\u0435\u0442 \u043A \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0443 \u0445\u043E\u0434\u0430 8 \u043E\u0447\u043A\u043E\u0432 \u0438\u043B\u0438 \u0432\u044B\u0447\u0438\u0442\u0430\u0435\u0442 8. \u041F\u043E\u0441\u043B\u0435 \u044D\u0442\u043E\u0433\u043E \u0445\u043E\u0434 \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0430\u0435\u0442\u0441\u044F.",
              "\u0418\u0437-\u0437\u0430 \u043A\u043E\u0448\u0430\u0447\u044C\u0435\u0433\u043E \u0445\u0432\u043E\u0441\u0442\u0430 \u043E\u0447\u043A\u0438 \u0445\u043E\u0434\u0430 \u043C\u043E\u0433\u0443\u0442 \u0443\u0439\u0442\u0438 \u0432 \u043C\u0438\u043D\u0443\u0441. \u0415\u0441\u043B\u0438 \u0441\u043E\u0445\u0440\u0430\u043D\u0438\u0442\u044C \u0442\u0430\u043A\u043E\u0439 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442, \u0431\u0430\u043D\u043A \u0443\u043C\u0435\u043D\u044C\u0448\u0438\u0442\u0441\u044F. \u041C\u043E\u0436\u043D\u043E \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0430\u0442\u044C \u0431\u0440\u043E\u0441\u043A\u0438, \u043F\u044B\u0442\u0430\u044F\u0441\u044C \u043E\u0442\u044B\u0433\u0440\u0430\u0442\u044C\u0441\u044F; \u0432\u044B\u043F\u0430\u0432\u0448\u0430\u044F \u0435\u0434\u0438\u043D\u0438\u0446\u0430 \u0442\u0430\u043A\u0436\u0435 \u0438\u0437\u0431\u0430\u0432\u0438\u0442 \u043E\u0442 \u043E\u0442\u0440\u0438\u0446\u0430\u0442\u0435\u043B\u044C\u043D\u043E\u0433\u043E \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0430, \u043E\u0431\u043D\u0443\u043B\u0438\u0432 \u0432\u0435\u0441\u044C \u0445\u043E\u0434."),
            rule_section(:finish, "\u0417\u0430\u0432\u0435\u0440\u0448\u0435\u043D\u0438\u0435 \u043F\u0430\u0440\u0442\u0438\u0438",
              "\u041A\u0430\u043A \u0442\u043E\u043B\u044C\u043A\u043E \u0443 \u043A\u043E\u0433\u043E-\u0442\u043E \u0432 \u043A\u043E\u043D\u0446\u0435 \u0445\u043E\u0434\u0430 \u043E\u043A\u0430\u0436\u0435\u0442\u0441\u044F \u043D\u0435 \u043C\u0435\u043D\u044C\u0448\u0435 100 \u043E\u0447\u043A\u043E\u0432 \u0432 \u0431\u0430\u043D\u043A\u0435, \u043E\u0441\u0442\u0430\u0451\u0442\u0441\u044F \u0434\u043E\u0438\u0433\u0440\u0430\u0442\u044C \u0442\u0435\u043A\u0443\u0449\u0438\u0439 \u043A\u0440\u0443\u0433. \u0421\u0432\u043E\u0439 \u0445\u043E\u0434 \u043F\u043E\u043B\u0443\u0447\u0430\u044E\u0442 \u0442\u0435, \u043A\u0442\u043E \u0435\u0449\u0451 \u043D\u0435 \u0445\u043E\u0434\u0438\u043B \u0432 \u044D\u0442\u043E\u043C \u043A\u0440\u0443\u0433\u0435.",
              "\u041D\u0430\u043F\u0440\u0438\u043C\u0435\u0440, \u0435\u0441\u043B\u0438 \u0438\u0437 \u0447\u0435\u0442\u044B\u0440\u0451\u0445 \u0438\u0433\u0440\u043E\u043A\u043E\u0432 \u0446\u0435\u043B\u0438 \u0434\u043E\u0441\u0442\u0438\u0433 \u0432\u0442\u043E\u0440\u043E\u0439, \u043F\u043E\u0441\u043B\u0435 \u043D\u0435\u0433\u043E \u0445\u043E\u0434\u044F\u0442 \u0442\u0440\u0435\u0442\u0438\u0439 \u0438 \u0447\u0435\u0442\u0432\u0451\u0440\u0442\u044B\u0439. \u0417\u0430\u0442\u0435\u043C \u0441\u0440\u0430\u0432\u043D\u0438\u0432\u0430\u044E\u0442 \u0431\u0430\u043D\u043A\u0438: \u0441\u0430\u043C\u044B\u0439 \u0431\u043E\u043B\u044C\u0448\u043E\u0439 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442 \u043F\u0440\u0438\u043D\u043E\u0441\u0438\u0442 \u043F\u043E\u0431\u0435\u0434\u0443, \u0430 \u0440\u0430\u0432\u0435\u043D\u0441\u0442\u0432\u043E \u043B\u0443\u0447\u0448\u0438\u0445 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u043E\u0432 \u043E\u0437\u043D\u0430\u0447\u0430\u0435\u0442 \u043D\u0438\u0447\u044C\u044E."),
            rule_section(:options, "\u0414\u0440\u0443\u0433\u0430\u044F \u0446\u0435\u043B\u044C \u043F\u043E \u043E\u0447\u043A\u0430\u043C",
              "\u041F\u0435\u0440\u0435\u0434 \u043F\u0430\u0440\u0442\u0438\u0435\u0439 \u0432 \u043D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0430\u0445 \u0441\u0442\u043E\u043B\u0430 \u043C\u043E\u0436\u043D\u043E \u0437\u0430\u043C\u0435\u043D\u0438\u0442\u044C \u0446\u0435\u043B\u044C \u0432 100 \u043E\u0447\u043A\u043E\u0432 \u043B\u044E\u0431\u044B\u043C \u0434\u0440\u0443\u0433\u0438\u043C \u043F\u043E\u043B\u043E\u0436\u0438\u0442\u0435\u043B\u044C\u043D\u044B\u043C \u0447\u0438\u0441\u043B\u043E\u043C. \u041F\u0435\u0440\u0435\u0434 \u0438\u0442\u043E\u0433\u043E\u0432\u044B\u043C \u0441\u0440\u0430\u0432\u043D\u0435\u043D\u0438\u0435\u043C \u0432\u0441\u0451 \u0440\u0430\u0432\u043D\u043E \u0434\u043E\u0438\u0433\u0440\u044B\u0432\u0430\u0435\u0442\u0441\u044F \u043D\u0430\u0447\u0430\u0442\u044B\u0439 \u043A\u0440\u0443\u0433 \u0445\u043E\u0434\u043E\u0432."),
            rule_section(:credits, "\u0410\u0432\u0442\u043E\u0440\u044B \u0438 \u043F\u0440\u043E\u0438\u0441\u0445\u043E\u0436\u0434\u0435\u043D\u0438\u0435",
              "Cat, Head, Tail \u0441\u043E\u0437\u0434\u0430\u043D\u0430 TD Programs \u043D\u0430 \u043E\u0441\u043D\u043E\u0432\u0435 PIG \u0438\u0437 RS Games. \u0417\u0434\u0435\u0441\u044C \u0438\u0441\u043F\u043E\u043B\u044C\u0437\u0443\u0435\u0442\u0441\u044F \u0432\u043E\u0441\u044C\u043C\u0438\u0433\u0440\u0430\u043D\u043D\u044B\u0439 \u043A\u0443\u0431\u0438\u043A \u0441 \u043E\u043F\u0438\u0441\u0430\u043D\u043D\u044B\u043C\u0438 \u0432\u044B\u0448\u0435 \u043E\u0441\u043E\u0431\u044B\u043C\u0438 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0430\u043C\u0438."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0448\u0438 \u0443\u043F\u0440\u0430\u0432\u043B\u0435\u043D\u0438\u044F",
              "\u0421\u0442\u0440\u0435\u043B\u043A\u0438: \u0432\u044B\u0431\u0440\u0430\u0442\u044C \u0431\u0440\u043E\u0441\u043E\u043A \u0438\u043B\u0438 \u0441\u043E\u0445\u0440\u0430\u043D\u0435\u043D\u0438\u0435 \u043E\u0447\u043A\u043E\u0432.",
              "Enter: \u0432\u044B\u043F\u043E\u043B\u043D\u0438\u0442\u044C \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u043E\u0435 \u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0435.",
              "C: \u0443\u0437\u043D\u0430\u0442\u044C \u043E\u0447\u043A\u0438 \u0442\u0435\u043A\u0443\u0449\u0435\u0433\u043E \u0445\u043E\u0434\u0430.",
              "S: \u0443\u0437\u043D\u0430\u0442\u044C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u044B \u0432 \u0431\u0430\u043D\u043A\u0430\u0445.",
              "D: \u043F\u043E\u0432\u0442\u043E\u0440\u0438\u0442\u044C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442 \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0435\u0433\u043E \u0431\u0440\u043E\u0441\u043A\u0430.",
              "T: \u0443\u0437\u043D\u0430\u0442\u044C, \u0447\u0435\u0439 \u0441\u0435\u0439\u0447\u0430\u0441 \u0445\u043E\u0434.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
