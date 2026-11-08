# Generated from tools/data/rulebooks/dice_poker.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class DicePoker
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:aim, GameRoomRules.translate("Poker dice"),
            GameRoomRules.translate("Each player rolls five ordinary dice up to the table limit, keeping any dice between throws. Stop early or use all throws. After everyone finishes, the strongest combination earns one point; tied strongest hands each earn one. Most points after the selected rounds wins. Equal final scores draw. This round scoring is the Power Games match format.")),
          rule_section(:variants, GameRoomRules.translate("Variants and ranking"),
            GameRoomRules.translate("With straights: five equal, four equal, full house, straight, three equal, two pairs, pair, high die. A straight is 1\u20135 or 2\u20136; 2\u20136 wins. Without straights, these rolls count as high dice. Sixes normally rank highest; the aces variant ranks ones above sixes and omits straights. Compare equal categories by the repeated values, then remaining dice. There are no suits or flushes.")),
          rule_section(:turns, GameRoomRules.translate("Throws and rounds"),
            GameRoomRules.translate("Choose two or three throws per turn and 1\u201320 rounds. If the opener limit is enabled, everyone else gets at most the number of throws used by the first player in that round. The opening seat rotates each round. Dice are public, and every throw uses native server randomness. You may change which dice to keep before a later throw.")),
          rule_section(:betting, GameRoomRules.translate("Chip betting"),
            GameRoomRules.translate("Choose point scoring or virtual chips. With chips, everyone pays the opening contribution or all remaining chips if short. A poker-style betting round runs before throws and another after everyone keeps a hand. Check, call, raise by a custom amount, fold or go all-in. Folded seats do not roll; an all-in seat still completes its throws. Contribution levels create main and side pots. Each layer goes to its strongest eligible hand, splitting exact ties in seat order. Uncontested layers or layers without eligible players are refunded as appropriate. One remaining contender wins without further throws. The match stops at the round limit or with one solvent player. S reads balances, C checks/calls, F folds, A goes all-in and B or R enters a raise.")),
          rule_section(:controls, GameRoomRules.translate("Controls"),
            GameRoomRules.translate("Enter rolls. After a throw, keys 1\u20136 select another die with that face to reroll; Shift+1\u20136 keeps it. Enter rerolls selected dice; without a selection it opens the Keep hand choice. K keeps the current hand directly. Space reads dice and selection; S reads scores. F1 lists current shortcuts, Ctrl+F1 opens rules. Chat, history and volume use shared controls."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:aim, "C\u00EDl a bodov\u00E1n\u00ED",
              "S p\u011Bti kostkami sestav siln\u011Bj\u0161\u00ED kombinaci ne\u017E soupe\u0159i. Jakmile v\u0161ichni dohraj\u00ED, nejlep\u0161\u00ED kombinace z\u00EDsk\u00E1 bod. P\u0159i shod\u011B dostane bod ka\u017Ed\u00FD z hr\u00E1\u010D\u016F s nejlep\u0161\u00ED kombinac\u00ED. Po dohodnut\u00E9m po\u010Dtu kol vyhr\u00E1v\u00E1 nejvy\u0161\u0161\u00ED sk\u00F3re; p\u0159i shod\u011B je rem\u00EDza."),
            rule_section(:turns, "Hody a v\u00FDb\u011Br kostek",
              "Poprv\u00E9 ho\u010F Enterem. Mezern\u00EDk p\u0159e\u010Dte kostky. Chce\u0161-li n\u011Bkter\u00E9 hodit znovu, vyb\u00EDrej je kl\u00E1vesami 1\u20136 podle hozen\u00E9 hodnoty. Dvakr\u00E1t stisknut\u00E1 p\u011Btka vybere dv\u011B kostky s p\u011Btkou, pokud je m\u00E1\u0161. Stisk stejn\u00E9 \u010D\u00EDslice se Shiftem jednu takovou kostku z v\u00FDb\u011Bru odebere.",
              "Enter znovu hod\u00ED vybran\u00FDmi kostkami a ostatn\u00ED ponech\u00E1. Pokud ti kombinace vyhovuje, ponech ji kl\u00E1vesou K nebo ji po posledn\u00EDm hodu vyber ze seznamu. Obvykle m\u00E1\u0161 nejv\u00FD\u0161 t\u0159i hody. Je-li zapnut\u00FD limit prvn\u00EDho hr\u00E1\u010De, ostatn\u00ED maj\u00ED nejv\u00FD\u0161 tolik hod\u016F, kolik pou\u017Eil on. V dal\u0161\u00EDm kole za\u010D\u00EDn\u00E1 jin\u00FD hr\u00E1\u010D."),
            rule_section(:variants, "Kombinace a varianty",
              "Od nejsiln\u011Bj\u0161\u00ED: p\u011Bt stejn\u00FDch, \u010Dtve\u0159ice, full house, postupka, trojice, dva p\u00E1ry, p\u00E1r a nejvy\u0161\u0161\u00ED kostka. Postupka je 1\u20135 nebo 2\u20136, z nich\u017E vyhr\u00E1v\u00E1 2\u20136. U stejn\u00E9 kombinace porovnej nejprve hodnoty, kter\u00E9 ji tvo\u0159\u00ED, potom zb\u00FDvaj\u00EDc\u00ED kostky.",
              "M\u016F\u017Ee\u0161 hr\u00E1t bez postupek, p\u0159\u00EDpadn\u011B bez postupek s jedni\u010Dkami jako nejvy\u0161\u0161\u00ED hodnotou. Jinak jsou nejvy\u0161\u0161\u00ED \u0161estky."),
            rule_section(:betting, "Hra o \u017Eetony",
              "P\u0159i h\u0159e o \u017Eetony ka\u017Ed\u00FD zaplat\u00ED vklad. S\u00E1z\u00ED se p\u0159ed hody a po potvrzen\u00ED v\u0161ech kombinac\u00ED. C vy\u010Dk\u00E1 nebo dorovn\u00E1, R \u010Di B zv\u00FD\u0161\u00ED s\u00E1zku, F odstoup\u00ED a A vsad\u00ED v\u0161echno. Kdo odstoup\u00ED, neh\u00E1z\u00ED a o bank nehraje. Kdo vsad\u00ED v\u0161echno, sv\u016Fj tah dohraje.",
              "Bank z\u00EDsk\u00E1 nejlep\u0161\u00ED kombinace, p\u0159i shod\u011B se d\u011Bl\u00ED. Zbyl\u00E9 \u017Eetony se p\u0159id\u011Bluj\u00ED podle po\u0159ad\u00ED v kole. Od soupe\u0159e nem\u016F\u017Ee\u0161 vyhr\u00E1t v\u00EDc, ne\u017E kolik jsi s\u00E1m vsadil. Nedorovnan\u00E1 \u010D\u00E1st se vrac\u00ED. Pokud ostatn\u00ED odstoup\u00ED, posledn\u00ED hr\u00E1\u010D z\u00EDsk\u00E1 bank bez dal\u0161\u00EDch hod\u016F. Po posledn\u00EDm kole nebo kdy\u017E zb\u00FDv\u00E1 jedin\u00FD hr\u00E1\u010D se \u017Eetony vyhr\u00E1v\u00E1 nejvy\u0161\u0161\u00ED z\u016Fstatek. Pokud na bank nem\u00E1 n\u00E1rok nikdo, vklady se vr\u00E1t\u00ED. Shodn\u00FD nejvy\u0161\u0161\u00ED z\u016Fstatek znamen\u00E1 rem\u00EDzu."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "Enter: hodit nebo potvrdit",
              "1\u20136: vybrat kostku s touto hodnotou k nov\u00E9mu hodu",
              "Shift+1\u20136: zru\u0161it v\u00FDb\u011Br takov\u00E9 kostky",
              "Mezern\u00EDk: p\u0159e\u010D\u00EDst kostky a v\u00FDb\u011Br",
              "K: ponechat kombinaci",
              "S: zjistit body nebo z\u016Fstatky",
              "C: vy\u010Dkat nebo dorovnat",
              "F: odstoupit ze s\u00E1zen\u00ED",
              "A: vsadit v\u0161e",
              "R: zv\u00FD\u0161it s\u00E1zku",
              "B: zv\u00FD\u0161it s\u00E1zku")
          ]
        when "en"
          [
            rule_section(:aim, "Aim and scoring",
              "Make a stronger five-dice combination than the other players. The best hand earns a point after everyone plays; tied leaders each get a point. The highest score after the agreed rounds wins. Equal highest scores draw."),
            rule_section(:turns, "Rolling and choosing dice",
              "Press Enter for the first throw. Space reads the dice. To roll only some of them again, press 1\u20136 for the faces you want to reroll. Pressing 5 twice selects two fives if you have them. Shift with the same digit removes one die of that value from the selection.",
              "Enter rerolls the selected dice and keeps the rest. If you are happy with the hand, press K to keep it, or choose the hand from the list after your final throw. You normally get up to three throws. With the opener limit, nobody in the round can use more throws than the first player. A different player opens the next round."),
            rule_section(:variants, "Hands and variants",
              "From strongest to weakest: five of a kind, four of a kind, full house, straight, three of a kind, two pair, one pair, and high die. A straight is 1\u20135 or 2\u20136, with 2\u20136 higher. Within a category, compare the dice that form the combination first, then the rest.",
              "You can play without straights, or without straights and with ones ranked highest. Otherwise six is the highest face."),
            rule_section(:betting, "Playing for chips",
              "In a chip game, everyone pays the opening stake. Bet once before rolling and again after everyone keeps a hand. C checks or calls, R or B raises, F folds, and A goes all-in. If you fold, you cannot roll or win the pot. Going all-in still lets you take your dice turn.",
              "The strongest hand wins the pot and ties split it. Odd chips are handed out in round order. You cannot win more from another player than you put in yourself. Any part of a bet nobody matched is returned. If everyone but one player folds, that player gets the pot without further play. Highest balance wins at the round limit or when only one player still has chips. If nobody is eligible for a pot, the bets in it are returned. Equal highest balances draw."),
            rule_section(:controls, "Keyboard shortcuts",
              "Enter: roll or confirm",
              "1\u20136: select a die of that value to reroll",
              "Shift+1\u20136: unselect a die of that value",
              "Space: read dice and selection",
              "K: keep the current hand",
              "S: read scores or balances",
              "C: check or call",
              "F: fold in betting",
              "A: go all-in",
              "R: raise",
              "B: raise")
          ]
        when "es"
          [
            rule_section(:aim, "Objetivo y puntos",
              "Consigue con cinco dados una jugada mejor que la de tus rivales. Despu\u00E9s de todos los turnos, la mejor jugada vale un punto. Si varias empatan en cabeza, cada una suma un punto. Gana quien tenga m\u00E1s puntos al final de las rondas; a igualdad en cabeza, hay empate."),
            rule_section(:turns, "Tiradas y selecci\u00F3n de dados",
              "Pulsa Intro para la primera tirada. Espacio lee los dados. Para volver a tirar solo algunos, el\u00EDgelos con 1\u20136 seg\u00FAn su valor. Si pulsas 5 dos veces, eliges dos cincos cuando los tienes. May\u00FAs con la misma cifra quita un dado de ese valor de la selecci\u00F3n.",
              "Intro vuelve a tirar los dados elegidos y conserva los dem\u00E1s. Si la jugada te convence, cons\u00E9rvala con K o el\u00EDgela de la lista tras la \u00FAltima tirada. Normalmente dispones de hasta tres tiradas. Con el l\u00EDmite de quien abre, nadie puede tirar m\u00E1s veces que el primer jugador de esa ronda. En la siguiente ronda empieza otra persona."),
            rule_section(:variants, "Jugadas y variantes",
              "De mayor a menor: cinco iguales, p\u00F3quer, full, escalera, tr\u00EDo, doble pareja, pareja y dado alto. Las escaleras son 1\u20135 y 2\u20136; gana la segunda. Si la categor\u00EDa coincide, compara primero los valores que forman la jugada y despu\u00E9s los dem\u00E1s dados.",
              "Puedes jugar sin escaleras, o sin escaleras y con el uno como valor m\u00E1s alto. En los dem\u00E1s casos, el seis es el mayor."),
            rule_section(:betting, "Partida con fichas",
              "Con fichas, todos ponen la entrada. Se apuesta antes de tirar y otra vez tras elegir todas las jugadas. C pasa o iguala, R o B sube, F retira y A apuesta todo. Si te retiras, no tiras ni optas al bote. Si apuestas todo, puedes completar tus tiradas.",
              "La mejor jugada se lleva el bote; los empatados lo reparten y las fichas sobrantes se asignan por orden de turno. De otro jugador solo puedes ganar hasta lo que hayas aportado. Se devuelve la parte que nadie igual\u00F3. Si queda una sola persona, gana el bote sin m\u00E1s tiradas. Tras la \u00FAltima ronda, o cuando solo una persona conserva fichas, gana el saldo m\u00E1s alto. Si nadie puede ganar un bote, se devuelven sus apuestas. Si coinciden los mejores saldos, hay empate."),
            rule_section(:controls, "Atajos de teclado",
              "Intro: tirar o confirmar",
              "1\u20136: elegir un dado de ese valor para volver a tirarlo",
              "May\u00FAs+1\u20136: quitar un dado de ese valor de la selecci\u00F3n",
              "Espacio: leer los dados y la selecci\u00F3n",
              "K: conservar la jugada",
              "S: consultar puntos o saldos",
              "C: pasar o igualar",
              "F: retirarse de las apuestas",
              "A: apostarlo todo",
              "R: subir la apuesta",
              "B: subir la apuesta")
          ]
        when "pl"
          [
            rule_section(:aim, "Cel i punktacja",
              "U\u0142\u00F3\u017C z pi\u0119ciu ko\u015Bci lepszy uk\u0142ad ni\u017C przeciwnicy. Po turach wszystkich graczy zwyci\u0119zca rundy dostaje punkt. Przy remisie ka\u017Cdy z najlepszym uk\u0142adem dostaje punkt. Po ustalonej liczbie rund wygrywa najwy\u017Cszy wynik; przy r\u00F3wnym najwy\u017Cszym wyniku jest remis."),
            rule_section(:turns, "Rzuty i wyb\u00F3r ko\u015Bci",
              "Pierwszy rzut wykonujesz Enterem. Po rzucie Spacja odczytuje ko\u015Bci. Je\u015Bli chcesz rzuci\u0107 ponownie tylko wybranymi ko\u015B\u0107mi, naciskaj cyfry od 1 do 6. Na przyk\u0142ad dwukrotne naci\u015Bni\u0119cie 5 zaznacza obie pi\u0105tki, je\u015Bli tyle masz. Shift z t\u0105 sam\u0105 cyfr\u0105 usuwa zaznaczenie kolejnej takiej ko\u015Bci.",
              "Enter rzuca ponownie zaznaczonymi ko\u015B\u0107mi. Pozosta\u0142e zachowujesz. Je\u015Bli odpowiada ci obecny uk\u0142ad, zatwierd\u017A go klawiszem K; po ostatnim rzucie wybierz go z listy. Zwykle masz do trzech rzut\u00F3w. Je\u015Bli gospodarz w\u0142\u0105czy limit pierwszego gracza, wszyscy w tej rundzie maj\u0105 najwy\u017Cej tyle rzut\u00F3w, ile on wykorzysta\u0142. W kolejnej rundzie zaczyna inna osoba."),
            rule_section(:variants, "Uk\u0142ady i odmiany",
              "Od najlepszego uk\u0142adu: pi\u0119\u0107 jednakowych, kareta, ful, strit, tr\u00F3jka, dwie pary, para i wysoka ko\u015B\u0107. Strit to 1\u20135 albo 2\u20136; wygrywa 2\u20136. W tej samej kategorii por\u00F3wnaj najpierw warto\u015Bci tworz\u0105ce uk\u0142ad, a potem pozosta\u0142e ko\u015Bci.",
              "Mo\u017Cna gra\u0107 bez strit\u00F3w albo bez strit\u00F3w z jedynkami jako najwy\u017Csz\u0105 warto\u015Bci\u0105. W pozosta\u0142ych odmianach najwy\u017Csze s\u0105 sz\u00F3stki."),
            rule_section(:betting, "Gra na \u017Cetony",
              "Po wybraniu gry na \u017Cetony ka\u017Cdy wp\u0142aca wpisowe. Licytujesz dwa razy: przed pierwszym rzutem i po zatwierdzeniu wszystkich uk\u0142ad\u00F3w. C pozwala zaczeka\u0107 lub wyr\u00F3wna\u0107, R albo B podbi\u0107, F spasowa\u0107, a A postawi\u0107 wszystko. Je\u015Bli spasujesz, nie rzucasz i nie walczysz o pul\u0119. Po postawieniu wszystkiego nadal mo\u017Cesz rozegra\u0107 swoj\u0105 tur\u0119.",
              "Najlepszy uk\u0142ad wygrywa pul\u0119, a remisuj\u0105cy j\u0105 dziel\u0105. Niepodzielne \u017Cetony trafiaj\u0105 do nich wed\u0142ug kolejno\u015Bci w rundzie. Nie mo\u017Cesz wygra\u0107 od innego gracza wi\u0119cej, ni\u017C sam wp\u0142aci\u0142e\u015B. Niewyr\u00F3wnana cz\u0119\u015B\u0107 stawki wraca do w\u0142a\u015Bciciela. Gdy zostanie jedna osoba, dostaje pul\u0119 bez dalszej gry. Po ustalonej liczbie rund albo gdy tylko jedna osoba ma jeszcze \u017Cetony, wygrywa najwy\u017Csze saldo. Gdy nikt nie mo\u017Ce wygra\u0107 danej puli, wp\u0142aty do niej wracaj\u0105. R\u00F3wne najwy\u017Csze salda daj\u0105 remis."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "Enter: rzu\u0107 albo zatwierd\u017A wyb\u00F3r",
              "1\u20136: zaznacz ko\u015B\u0107 o tylu oczkach do kolejnego rzutu",
              "Shift+1\u20136: usu\u0144 zaznaczenie takiej ko\u015Bci",
              "Spacja: odczytaj ko\u015Bci i zaznaczenie",
              "K: zachowaj uk\u0142ad",
              "S: sprawd\u017A punkty lub salda",
              "C: zaczekaj lub wyr\u00F3wnaj",
              "F: spasuj w licytacji",
              "A: wejd\u017A za wszystko",
              "R: podbij",
              "B: podbij")
          ]
        when "ru"
          [
            rule_section(:aim, "\u0426\u0435\u043B\u044C \u0438\u0433\u0440\u044B \u0438 \u043E\u0447\u043A\u0438",
              "\u0421\u043E\u0431\u0435\u0440\u0438 \u043D\u0430 \u043F\u044F\u0442\u0438 \u043A\u043E\u0441\u0442\u044F\u0445 \u043A\u043E\u043C\u0431\u0438\u043D\u0430\u0446\u0438\u044E \u0441\u0438\u043B\u044C\u043D\u0435\u0435, \u0447\u0435\u043C \u0443 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u043E\u0432. \u041F\u043E\u0441\u043B\u0435 \u0445\u043E\u0434\u043E\u0432 \u0432\u0441\u0435\u0445 \u0438\u0433\u0440\u043E\u043A\u043E\u0432 \u043B\u0443\u0447\u0448\u0430\u044F \u043A\u043E\u043C\u0431\u0438\u043D\u0430\u0446\u0438\u044F \u043F\u0440\u0438\u043D\u043E\u0441\u0438\u0442 \u043E\u0447\u043A\u043E. \u0415\u0441\u043B\u0438 \u043B\u0443\u0447\u0448\u0438\u0445 \u043D\u0435\u0441\u043A\u043E\u043B\u044C\u043A\u043E, \u043A\u0430\u0436\u0434\u044B\u0439 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u043F\u043E \u043E\u0447\u043A\u0443. \u041F\u043E\u0441\u043B\u0435 \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0435\u0433\u043E \u0440\u0430\u0443\u043D\u0434\u0430 \u043F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u0442\u043E\u0442, \u0443 \u043A\u043E\u0433\u043E \u0431\u043E\u043B\u044C\u0448\u0435 \u043E\u0447\u043A\u043E\u0432. \u0420\u0430\u0432\u043D\u044B\u0439 \u043B\u0443\u0447\u0448\u0438\u0439 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442 \u0434\u0430\u0451\u0442 \u043D\u0438\u0447\u044C\u044E."),
            rule_section(:turns, "\u0411\u0440\u043E\u0441\u043A\u0438 \u0438 \u0432\u044B\u0431\u043E\u0440 \u043A\u043E\u0441\u0442\u0435\u0439",
              "\u0414\u043B\u044F \u043F\u0435\u0440\u0432\u043E\u0433\u043E \u0431\u0440\u043E\u0441\u043A\u0430 \u043D\u0430\u0436\u043C\u0438 Enter. \u041F\u0440\u043E\u0431\u0435\u043B \u0447\u0438\u0442\u0430\u0435\u0442 \u0432\u044B\u043F\u0430\u0432\u0448\u0438\u0435 \u0437\u043D\u0430\u0447\u0435\u043D\u0438\u044F. \u0427\u0442\u043E\u0431\u044B \u043F\u0435\u0440\u0435\u0431\u0440\u043E\u0441\u0438\u0442\u044C \u0442\u043E\u043B\u044C\u043A\u043E \u0447\u0430\u0441\u0442\u044C \u043A\u043E\u0441\u0442\u0435\u0439, \u0432\u044B\u0431\u0435\u0440\u0438 \u0438\u0445 \u0446\u0438\u0444\u0440\u0430\u043C\u0438 \u043E\u0442 1 \u0434\u043E 6. \u0414\u0432\u0430 \u043D\u0430\u0436\u0430\u0442\u0438\u044F 5 \u0432\u044B\u0431\u0435\u0440\u0443\u0442 \u0434\u0432\u0435 \u043F\u044F\u0442\u0451\u0440\u043A\u0438, \u0435\u0441\u043B\u0438 \u043E\u043D\u0438 \u0435\u0441\u0442\u044C. \u0422\u0430 \u0436\u0435 \u0446\u0438\u0444\u0440\u0430 \u0441 Shift \u0441\u043D\u0438\u043C\u0430\u0435\u0442 \u0432\u044B\u0431\u043E\u0440 \u0441 \u043E\u0434\u043D\u043E\u0439 \u043A\u043E\u0441\u0442\u0438 \u044D\u0442\u043E\u0433\u043E \u0434\u043E\u0441\u0442\u043E\u0438\u043D\u0441\u0442\u0432\u0430.",
              "Enter \u043F\u0435\u0440\u0435\u0431\u0440\u0430\u0441\u044B\u0432\u0430\u0435\u0442 \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u044B\u0435 \u043A\u043E\u0441\u0442\u0438, \u043E\u0441\u0442\u0430\u043B\u044C\u043D\u044B\u0435 \u043E\u0441\u0442\u0430\u044E\u0442\u0441\u044F. \u0415\u0441\u043B\u0438 \u043A\u043E\u043C\u0431\u0438\u043D\u0430\u0446\u0438\u044F \u0443\u0441\u0442\u0440\u0430\u0438\u0432\u0430\u0435\u0442, \u0441\u043E\u0445\u0440\u0430\u043D\u0438 \u0435\u0451 \u043A\u043B\u0430\u0432\u0438\u0448\u0435\u0439 K \u0438\u043B\u0438 \u0432\u044B\u0431\u0435\u0440\u0438 \u0432 \u0441\u043F\u0438\u0441\u043A\u0435 \u043F\u043E\u0441\u043B\u0435 \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0435\u0433\u043E \u0431\u0440\u043E\u0441\u043A\u0430. \u041E\u0431\u044B\u0447\u043D\u043E \u043C\u043E\u0436\u043D\u043E \u0431\u0440\u043E\u0441\u0430\u0442\u044C \u0434\u043E \u0442\u0440\u0451\u0445 \u0440\u0430\u0437. \u0415\u0441\u043B\u0438 \u0432\u043A\u043B\u044E\u0447\u0451\u043D \u043B\u0438\u043C\u0438\u0442 \u043F\u0435\u0440\u0432\u043E\u0433\u043E \u0438\u0433\u0440\u043E\u043A\u0430, \u043E\u0441\u0442\u0430\u043B\u044C\u043D\u044B\u0435 \u043C\u043E\u0433\u0443\u0442 \u0431\u0440\u043E\u0441\u0438\u0442\u044C \u043D\u0435 \u0431\u043E\u043B\u044C\u0448\u0435 \u0440\u0430\u0437, \u0447\u0435\u043C \u043E\u043D. \u0412 \u043D\u043E\u0432\u043E\u043C \u0440\u0430\u0443\u043D\u0434\u0435 \u043D\u0430\u0447\u0438\u043D\u0430\u0435\u0442 \u0434\u0440\u0443\u0433\u043E\u0439 \u0438\u0433\u0440\u043E\u043A."),
            rule_section(:variants, "\u041A\u043E\u043C\u0431\u0438\u043D\u0430\u0446\u0438\u0438 \u0438 \u0432\u0430\u0440\u0438\u0430\u043D\u0442\u044B",
              "\u041E\u0442 \u0441\u0442\u0430\u0440\u0448\u0435\u0439 \u043A \u043C\u043B\u0430\u0434\u0448\u0435\u0439: \u043F\u044F\u0442\u044C \u043E\u0434\u0438\u043D\u0430\u043A\u043E\u0432\u044B\u0445, \u043A\u0430\u0440\u0435, \u0444\u0443\u043B\u043B-\u0445\u0430\u0443\u0441, \u0441\u0442\u0440\u0438\u0442, \u0442\u0440\u043E\u0439\u043A\u0430, \u0434\u0432\u0435 \u043F\u0430\u0440\u044B, \u043F\u0430\u0440\u0430 \u0438 \u0441\u0442\u0430\u0440\u0448\u0430\u044F \u043A\u043E\u0441\u0442\u044C. \u0421\u0442\u0440\u0438\u0442 \u2014 \u044D\u0442\u043E 1\u20135 \u0438\u043B\u0438 2\u20136; \u0432\u0442\u043E\u0440\u043E\u0439 \u0441\u0442\u0430\u0440\u0448\u0435. \u041F\u0440\u0438 \u043E\u0434\u043D\u043E\u0439 \u043A\u0430\u0442\u0435\u0433\u043E\u0440\u0438\u0438 \u0441\u043D\u0430\u0447\u0430\u043B\u0430 \u0441\u0440\u0430\u0432\u043D\u0438 \u0437\u043D\u0430\u0447\u0435\u043D\u0438\u044F, \u0441\u043E\u0441\u0442\u0430\u0432\u043B\u044F\u044E\u0449\u0438\u0435 \u043A\u043E\u043C\u0431\u0438\u043D\u0430\u0446\u0438\u044E, \u0437\u0430\u0442\u0435\u043C \u043E\u0441\u0442\u0430\u043B\u044C\u043D\u044B\u0435 \u043A\u043E\u0441\u0442\u0438.",
              "\u041C\u043E\u0436\u043D\u043E \u0438\u0433\u0440\u0430\u0442\u044C \u0431\u0435\u0437 \u0441\u0442\u0440\u0438\u0442\u043E\u0432 \u0438\u043B\u0438 \u0431\u0435\u0437 \u0441\u0442\u0440\u0438\u0442\u043E\u0432 \u0441\u043E \u0441\u0442\u0430\u0440\u0448\u0435\u0439 \u0435\u0434\u0438\u043D\u0438\u0446\u0435\u0439. \u0412 \u043E\u0441\u0442\u0430\u043B\u044C\u043D\u044B\u0445 \u0432\u0430\u0440\u0438\u0430\u043D\u0442\u0430\u0445 \u0441\u0442\u0430\u0440\u0448\u0430\u044F \u2014 \u0448\u0435\u0441\u0442\u0451\u0440\u043A\u0430."),
            rule_section(:betting, "\u0418\u0433\u0440\u0430 \u043D\u0430 \u0444\u0438\u0448\u043A\u0438",
              "\u041F\u0440\u0438 \u0438\u0433\u0440\u0435 \u043D\u0430 \u0444\u0438\u0448\u043A\u0438 \u043A\u0430\u0436\u0434\u044B\u0439 \u0432\u043D\u043E\u0441\u0438\u0442 \u043D\u0430\u0447\u0430\u043B\u044C\u043D\u0443\u044E \u0441\u0442\u0430\u0432\u043A\u0443. \u041F\u0435\u0440\u0432\u044B\u0439 \u043A\u0440\u0443\u0433 \u0442\u043E\u0440\u0433\u043E\u0432 \u0438\u0434\u0451\u0442 \u0434\u043E \u0431\u0440\u043E\u0441\u043A\u043E\u0432, \u0432\u0442\u043E\u0440\u043E\u0439 \u2014 \u043A\u043E\u0433\u0434\u0430 \u0432\u0441\u0435 \u0432\u044B\u0431\u0440\u0430\u043B\u0438 \u043A\u043E\u043C\u0431\u0438\u043D\u0430\u0446\u0438\u0438. C \u043F\u043E\u0437\u0432\u043E\u043B\u044F\u0435\u0442 \u043F\u0440\u043E\u043F\u0443\u0441\u0442\u0438\u0442\u044C \u0445\u043E\u0434 \u0438\u043B\u0438 \u0443\u0440\u0430\u0432\u043D\u044F\u0442\u044C, R \u043B\u0438\u0431\u043E B \u043F\u043E\u0432\u044B\u0448\u0430\u0435\u0442, F \u0432\u044B\u0432\u043E\u0434\u0438\u0442 \u0438\u0437 \u0440\u0430\u0443\u043D\u0434\u0430, A \u0441\u0442\u0430\u0432\u0438\u0442 \u0432\u0441\u0451. \u0412\u044B\u0448\u0435\u0434\u0448\u0438\u0439 \u043D\u0435 \u0431\u0440\u043E\u0441\u0430\u0435\u0442 \u0438 \u043D\u0435 \u043F\u0440\u0435\u0442\u0435\u043D\u0434\u0443\u0435\u0442 \u043D\u0430 \u0431\u0430\u043D\u043A. \u041F\u043E\u0441\u0442\u0430\u0432\u0438\u0432\u0448\u0438\u0439 \u0432\u0441\u0435 \u0444\u0438\u0448\u043A\u0438 \u0432\u0441\u0451 \u0440\u0430\u0432\u043D\u043E \u0431\u0440\u043E\u0441\u0430\u0435\u0442.",
              "\u0411\u0430\u043D\u043A \u0437\u0430\u0431\u0438\u0440\u0430\u0435\u0442 \u0441\u0442\u0430\u0440\u0448\u0430\u044F \u043A\u043E\u043C\u0431\u0438\u043D\u0430\u0446\u0438\u044F; \u043F\u0440\u0438 \u0440\u0430\u0432\u0435\u043D\u0441\u0442\u0432\u0435 \u0431\u0430\u043D\u043A \u0434\u0435\u043B\u0438\u0442\u0441\u044F, \u0430 \u043B\u0438\u0448\u043D\u0438\u0435 \u0444\u0438\u0448\u043A\u0438 \u0432\u044B\u0434\u0430\u044E\u0442\u0441\u044F \u043F\u043E \u043F\u043E\u0440\u044F\u0434\u043A\u0443 \u0445\u043E\u0434\u043E\u0432 \u0432 \u0440\u0430\u0443\u043D\u0434\u0435. \u0423 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u0430 \u043C\u043E\u0436\u043D\u043E \u0432\u044B\u0438\u0433\u0440\u0430\u0442\u044C \u043D\u0435 \u0431\u043E\u043B\u044C\u0448\u0435 \u0441\u043E\u0431\u0441\u0442\u0432\u0435\u043D\u043D\u043E\u0433\u043E \u0432\u0437\u043D\u043E\u0441\u0430. \u041D\u0435\u0443\u0440\u0430\u0432\u043D\u0435\u043D\u043D\u0430\u044F \u0447\u0430\u0441\u0442\u044C \u0432\u043E\u0437\u0432\u0440\u0430\u0449\u0430\u0435\u0442\u0441\u044F. \u0415\u0441\u043B\u0438 \u043E\u0441\u0442\u0430\u043B\u0441\u044F \u043E\u0434\u0438\u043D \u0438\u0433\u0440\u043E\u043A, \u043E\u043D \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u0431\u0430\u043D\u043A \u0431\u0435\u0437 \u0434\u0430\u043B\u044C\u043D\u0435\u0439\u0448\u0438\u0445 \u0431\u0440\u043E\u0441\u043A\u043E\u0432. \u041F\u043E\u0441\u043B\u0435 \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0435\u0433\u043E \u0440\u0430\u0443\u043D\u0434\u0430 \u0438\u043B\u0438 \u043A\u043E\u0433\u0434\u0430 \u0444\u0438\u0448\u043A\u0438 \u0435\u0441\u0442\u044C \u0442\u043E\u043B\u044C\u043A\u043E \u0443 \u043E\u0434\u043D\u043E\u0433\u043E \u0438\u0433\u0440\u043E\u043A\u0430, \u043F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u043D\u0430\u0438\u0431\u043E\u043B\u044C\u0448\u0438\u0439 \u043E\u0441\u0442\u0430\u0442\u043E\u043A. \u0415\u0441\u043B\u0438 \u043D\u0430 \u0431\u0430\u043D\u043A \u043D\u0438\u043A\u0442\u043E \u043D\u0435 \u043F\u0440\u0435\u0442\u0435\u043D\u0434\u0443\u0435\u0442, \u0432\u0437\u043D\u043E\u0441\u044B \u0432 \u043D\u0435\u0433\u043E \u0432\u043E\u0437\u0432\u0440\u0430\u0449\u0430\u044E\u0442\u0441\u044F. \u0420\u0430\u0432\u043D\u044B\u0435 \u043D\u0430\u0438\u0431\u043E\u043B\u044C\u0448\u0438\u0435 \u043E\u0441\u0442\u0430\u0442\u043A\u0438 \u0434\u0430\u044E\u0442 \u043D\u0438\u0447\u044C\u044E."),
            rule_section(:controls, "\u0413\u043E\u0440\u044F\u0447\u0438\u0435 \u043A\u043B\u0430\u0432\u0438\u0448\u0438",
              "Enter: \u0431\u0440\u043E\u0441\u0438\u0442\u044C \u0438\u043B\u0438 \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u044C",
              "1\u20136: \u0432\u044B\u0431\u0440\u0430\u0442\u044C \u043A\u043E\u0441\u0442\u044C \u0441 \u0442\u0430\u043A\u0438\u043C \u0437\u043D\u0430\u0447\u0435\u043D\u0438\u0435\u043C \u0434\u043B\u044F \u043F\u0435\u0440\u0435\u0431\u0440\u043E\u0441\u0430",
              "Shift+1\u20136: \u0441\u043D\u044F\u0442\u044C \u0432\u044B\u0431\u043E\u0440 \u0441 \u0442\u0430\u043A\u043E\u0439 \u043A\u043E\u0441\u0442\u0438",
              "\u041F\u0440\u043E\u0431\u0435\u043B: \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u043A\u043E\u0441\u0442\u0438 \u0438 \u0432\u044B\u0431\u043E\u0440",
              "K: \u043E\u0441\u0442\u0430\u0432\u0438\u0442\u044C \u043A\u043E\u043C\u0431\u0438\u043D\u0430\u0446\u0438\u044E",
              "S: \u0443\u0437\u043D\u0430\u0442\u044C \u043E\u0447\u043A\u0438 \u0438\u043B\u0438 \u0444\u0438\u0448\u043A\u0438",
              "C: \u043F\u0440\u043E\u043F\u0443\u0441\u0442\u0438\u0442\u044C \u0445\u043E\u0434 \u0442\u043E\u0440\u0433\u043E\u0432 \u0438\u043B\u0438 \u0443\u0440\u0430\u0432\u043D\u044F\u0442\u044C",
              "F: \u0432\u044B\u0439\u0442\u0438 \u0438\u0437 \u0442\u043E\u0440\u0433\u043E\u0432",
              "A: \u043F\u043E\u0441\u0442\u0430\u0432\u0438\u0442\u044C \u0432\u0441\u0451",
              "R: \u043F\u043E\u0432\u044B\u0441\u0438\u0442\u044C \u0441\u0442\u0430\u0432\u043A\u0443",
              "B: \u043F\u043E\u0432\u044B\u0441\u0438\u0442\u044C \u0441\u0442\u0430\u0432\u043A\u0443")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
