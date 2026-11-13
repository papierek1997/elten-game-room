# Generated from tools/data/rulebooks/french_tarot.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class FrenchTarotTable
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:play, GameRoomRules.translate("French Tarot"),
            GameRoomRules.translate("Four players bid. The highest bidder plays against the other three. With Petite or Garde, take the kitty and discard six cards. With Garde sans, the kitty counts for the taker. With Garde contre, it counts for the defenders."),
            GameRoomRules.translate("Follow suit if you can. Otherwise trump if possible, and overtrump when you can. You may play the Excuse regardless of suit. After 18 tricks, the contract depends on the points and oudlers captured.")),
          rule_section(:controls, GameRoomRules.translate("Keyboard"),
            GameRoomRules.translate("Choose a bid or card with the arrows and press Enter."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:play, "Francouzsk\u00FD tarot",
              "\u010Cty\u0159i hr\u00E1\u010Di licituj\u00ED. Nejvy\u0161\u0161\u00ED nab\u00EDdka ur\u010D\u00ED hr\u00E1\u010De, kter\u00FD hraje proti zb\u00FDvaj\u00EDc\u00EDm t\u0159em. P\u0159i Petite a Garde vezm\u011Bte talon a odlo\u017Ete \u0161est karet. P\u0159i Garde sans se talon po\u010D\u00EDt\u00E1 vydra\u017Eiteli, p\u0159i Garde contre obran\u011B.",
              "P\u0159iznejte barvu, pokud m\u016F\u017Eete. Jinak zahrajte trumf, pokud ho m\u00E1te. Je-li to mo\u017En\u00E9, p\u0159ebijte vy\u0161\u0161\u00EDm trumfem. Excuse m\u016F\u017Eete zahr\u00E1t bez ohledu na barvu. Po 18 zdviz\u00EDch z\u00E1vis\u00ED v\u00FDsledek na z\u00EDskan\u00FDch bodech a po\u010Dtu oudler\u016F."),
            rule_section(:controls, "Ovl\u00E1d\u00E1n\u00ED",
              "\u0160ipkami vyberte nab\u00EDdku nebo kartu a potvr\u010Fte Enterem.")
          ]
        when "en"
          [
            rule_section(:play, "French Tarot",
              "Four players bid. The highest bidder plays against the other three. With Petite or Garde, take the kitty and discard six cards. With Garde sans, the kitty counts for the taker. With Garde contre, it counts for the defenders.",
              "Follow suit if you can. Otherwise trump if possible, and overtrump when you can. You may play the Excuse regardless of suit. After 18 tricks, the contract depends on the points and oudlers captured."),
            rule_section(:controls, "Keyboard",
              "Choose a bid or card with the arrows and press Enter.")
          ]
        when "es"
          [
            rule_section(:play, "Tarot franc\u00E9s",
              "Cuatro jugadores pujan. Quien hace la oferta m\u00E1s alta juega contra los otros tres. En Petite y Garde recoge el tal\u00F3n y descarta seis cartas. En Garde sans el tal\u00F3n punt\u00FAa para quien gan\u00F3 la subasta, y en Garde contre para la defensa.",
              "Sigue el palo si puedes. Si no, juega un triunfo si lo tienes. Supera el triunfo m\u00E1s alto si puedes. Puedes jugar la Excuse con cualquier palo de salida. Tras 18 bazas, el contrato se resuelve seg\u00FAn los puntos y los oudlers conseguidos."),
            rule_section(:controls, "Teclado",
              "Elige una oferta o una carta con las flechas y confirma con Intro.")
          ]
        when "pl"
          [
            rule_section(:play, "Rozdanie i licytacja",
              "Gracie w czw\u00F3rk\u0119. Ka\u017Cdy dostaje 18 kart, a pozosta\u0142e sze\u015B\u0107 tworzy talon. Jedna osoba zostaje rozgrywaj\u0105cym, a pozosta\u0142e trzy graj\u0105 razem jako obrona.",
              "Najpierw przejrzyj karty strza\u0142kami lub odczytaj r\u0119k\u0119 klawiszem H. W swojej kolejce naci\u015Bnij B, wybierz Pas albo kontrakt i zatwierd\u017A Enterem. Mo\u017Cesz wybra\u0107 tylko kontrakt wy\u017Cszy od zg\u0142oszonego. Je\u015Bli wszyscy spasuj\u0105, karty zostan\u0105 rozdane ponownie.",
              "Od najni\u017Cszego do najwy\u017Cszego kontrakty to Petite, Garde, Garde sans i Garde contre. W Petite oraz Garde bierzesz talon, a potem odk\u0142adasz sze\u015B\u0107 kart. Od\u0142o\u017Cone karty licz\u0105 si\u0119 na twoj\u0105 korzy\u015B\u0107. Kr\u00F3le i trzy karty specjalne zostaj\u0105 w r\u0119ce. Atuty odk\u0142adasz tylko wtedy, gdy brakuje zwyk\u0142ych kart do od\u0142o\u017Cenia.",
              "W Garde sans talon pozostaje zakryty i przy rozliczeniu liczy si\u0119 dla ciebie. W Garde contre jego punkty przypadaj\u0105 obronie."),
            rule_section(:trumps, "Jak zagra\u0107 lew\u0119",
              "Ka\u017Cdy zagrywa po jednej karcie. Pierwsza karta poza Wym\u00F3wk\u0105 wyznacza kolor wyj\u015Bcia. Wybierz kart\u0119 strza\u0142kami i zagraj j\u0105 Enterem.",
              "Je\u015Bli wyszed\u0142 kier i masz cho\u0107 jednego kiera, zagraj kiera, nawet je\u015Bli kto\u015B ju\u017C u\u017Cy\u0142 atutu. Gdy brakuje ci kiera, zagraj atut, je\u015Bli go masz. Je\u015Bli na stole jest ju\u017C atut 12, musisz zagra\u0107 wy\u017Cszy atut, o ile taki masz. Je\u015Bli masz tylko ni\u017Csze atuty, wybierz dowolny z nich. Gdy brakuje ci zar\u00F3wno koloru wyj\u015Bcia, jak i atut\u00F3w, zagraj dowoln\u0105 kart\u0119.",
              "Gdy kto\u015B zacznie lew\u0119 atutem, zagrywasz atut i przebijasz najwy\u017Cszy na stole, je\u015Bli mo\u017Cesz. Lew\u0119 bierze najwy\u017Cszy atut. Je\u015Bli \u017Caden atut nie pad\u0142, wygrywa najwy\u017Csza karta koloru wyj\u015Bcia. Od najsilniejszej figury kolejno\u015B\u0107 to kr\u00F3l, dama, rycerz, walet, a dalej karty od dziesi\u0105tki do asa. Zwyci\u0119zca lewy zaczyna nast\u0119pn\u0105.",
              "Atut 21 jest najsilniejszy. Atut 1, zwany Ma\u0142ym, jest najs\u0142abszy. Wym\u00F3wk\u0119 mo\u017Cesz zagra\u0107 w dowolnej lewie. Przed ostatni\u0105 lew\u0105 zostaje po stronie zagrywaj\u0105cego. Je\u015Bli lew\u0119 we\u017Amie druga strona, dostaje w zamian p\u00F3\u0142 punktu. W ostatniej lewie Wym\u00F3wk\u0119 bierze zwyci\u0119zca lewy."),
            rule_section(:scoring, "Punkty i wynik kontraktu",
              "Rozgrywaj\u0105cy stara si\u0119 zdoby\u0107 tyle punkt\u00F3w, ile wymaga jego kontrakt. Pr\u00F3g zale\u017Cy od liczby zdobytych oudler\u00F3w. Oudlery to Ma\u0142y, atut 21 i Wym\u00F3wka. Ka\u017Cdy jest wart 4,5 punktu.",
              "- Bez oudlera potrzeba 56 punkt\u00F3w.",
              "- Z jednym oudlerem potrzeba 51 punkt\u00F3w.",
              "- Z dwoma oudlerami potrzeba 41 punkt\u00F3w.",
              "- Z trzema oudlerami potrzeba 36 punkt\u00F3w.",
              "Kr\u00F3l daje 4,5 punktu, dama 3,5, rycerz 2,5, a walet 1,5. Pozosta\u0142e karty daj\u0105 po p\u00F3\u0142 punktu.",
              "Po 18 lewach gra por\u00F3wnuje zdobyte punkty z progiem. Do r\u00F3\u017Cnicy, liczonej bez znaku, dodaje 25. Nast\u0119pnie mno\u017Cy wynik przez 1 dla Petite, 2 dla Garde, 4 dla Garde sans albo 6 dla Garde contre.",
              "Je\u015Bli w Garde potrzebujesz 41 punkt\u00F3w i zdob\u0119dziesz 44, wygrywasz o 3. Gra dodaje 3 do 25 i mno\u017Cy przez 2, co daje 56. Ka\u017Cdy obro\u0144ca traci 56, a ty zyskujesz 168. Przy przegranej kontraktu punkty p\u0142yn\u0105 w drug\u0105 stron\u0119.",
              "Domy\u015Blnie partia trwa jedno rozegrane rozdanie. W ustawieniach sto\u0142u mo\u017Cesz zmieni\u0107 limit rozda\u0144 lub ustawi\u0107 pr\u00F3g punkt\u00F3w. Wpisz zero, aby wy\u0142\u0105czy\u0107 dany limit. Gdy ustawisz oba limity, partia ko\u0144czy si\u0119 po rozdaniu, w kt\u00F3rym spe\u0142niono pierwszy z nich. Rozdania zako\u0144czone samymi pasami nie wliczaj\u0105 si\u0119 do limitu. Wygrywa gracz z najwy\u017Csz\u0105 sum\u0105 punkt\u00F3w."),
            rule_section(:controls, "Klawiatura",
              "- H odczytuje r\u0119k\u0119.",
              "- B otwiera wyb\u00F3r kontraktu lub pasa.",
              "- Strza\u0142ki zmieniaj\u0105 wyb\u00F3r. Enter zatwierdza, a Escape zamyka wyb\u00F3r kontraktu.",
              "- C odczytuje karty na stole. F podaje kolor wyj\u015Bcia, a T m\u00F3wi, czyja jest kolej.",
              "- S odczytuje wynik po rozliczonych rozdaniach. Shift+S odczytuje punkty z zako\u0144czonych lew bie\u017C\u0105cego rozdania. Talon liczy si\u0119 przy ko\u0144cowym rozliczeniu.")
          ]
        when "ru"
          [
            rule_section(:play, "\u0424\u0440\u0430\u043D\u0446\u0443\u0437\u0441\u043A\u0438\u0439 \u0442\u0430\u0440\u043E",
              "\u0427\u0435\u0442\u044B\u0440\u0435 \u0438\u0433\u0440\u043E\u043A\u0430 \u0442\u043E\u0440\u0433\u0443\u044E\u0442\u0441\u044F. \u0421\u0434\u0435\u043B\u0430\u0432\u0448\u0438\u0439 \u0441\u0442\u0430\u0440\u0448\u0443\u044E \u0437\u0430\u044F\u0432\u043A\u0443 \u0438\u0433\u0440\u0430\u0435\u0442 \u043F\u0440\u043E\u0442\u0438\u0432 \u043E\u0441\u0442\u0430\u043B\u044C\u043D\u044B\u0445 \u0442\u0440\u043E\u0438\u0445. \u041F\u0440\u0438 Petite \u0438 Garde \u0432\u043E\u0437\u044C\u043C\u0438\u0442\u0435 \u043F\u0440\u0438\u043A\u0443\u043F \u0438 \u043E\u0442\u043B\u043E\u0436\u0438\u0442\u0435 \u0448\u0435\u0441\u0442\u044C \u043A\u0430\u0440\u0442. \u041F\u0440\u0438 Garde sans \u043F\u0440\u0438\u043A\u0443\u043F \u0437\u0430\u0441\u0447\u0438\u0442\u044B\u0432\u0430\u0435\u0442\u0441\u044F \u0440\u0430\u0437\u044B\u0433\u0440\u044B\u0432\u0430\u044E\u0449\u0435\u043C\u0443, \u043F\u0440\u0438 Garde contre \u2014 \u0437\u0430\u0449\u0438\u0442\u043D\u0438\u043A\u0430\u043C.",
              "\u041F\u043E \u0432\u043E\u0437\u043C\u043E\u0436\u043D\u043E\u0441\u0442\u0438 \u043A\u043B\u0430\u0434\u0438\u0442\u0435 \u043A\u0430\u0440\u0442\u0443 \u043C\u0430\u0441\u0442\u0438 \u0445\u043E\u0434\u0430. \u0415\u0441\u043B\u0438 \u044D\u0442\u043E\u0439 \u043C\u0430\u0441\u0442\u0438 \u043D\u0435\u0442, \u0441\u044B\u0433\u0440\u0430\u0439\u0442\u0435 \u043A\u043E\u0437\u044B\u0440\u0435\u043C, \u0435\u0441\u043B\u0438 \u043E\u043D \u0435\u0441\u0442\u044C. \u041F\u0435\u0440\u0435\u0431\u0435\u0439\u0442\u0435 \u043A\u043E\u0437\u044B\u0440\u044C \u0441\u0442\u0430\u0440\u0448\u0438\u043C, \u0435\u0441\u043B\u0438 \u043C\u043E\u0436\u0435\u0442\u0435. \u041A\u0430\u0440\u0442\u0443 Excuse \u043C\u043E\u0436\u043D\u043E \u0441\u044B\u0433\u0440\u0430\u0442\u044C \u043F\u0440\u0438 \u043B\u044E\u0431\u043E\u0439 \u043C\u0430\u0441\u0442\u0438 \u0445\u043E\u0434\u0430. \u041F\u043E\u0441\u043B\u0435 18 \u0432\u0437\u044F\u0442\u043E\u043A \u0438\u0441\u0445\u043E\u0434 \u043A\u043E\u043D\u0442\u0440\u0430\u043A\u0442\u0430 \u043E\u043F\u0440\u0435\u0434\u0435\u043B\u044F\u0435\u0442\u0441\u044F \u043D\u0430\u0431\u0440\u0430\u043D\u043D\u044B\u043C\u0438 \u043E\u0447\u043A\u0430\u043C\u0438 \u0438 \u0447\u0438\u0441\u043B\u043E\u043C \u0432\u0437\u044F\u0442\u044B\u0445 \u0443\u0434\u043B\u0435\u0440\u043E\u0432."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0430\u0442\u0443\u0440\u0430",
              "\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0437\u0430\u044F\u0432\u043A\u0443 \u0438\u043B\u0438 \u043A\u0430\u0440\u0442\u0443 \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0438 \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u0435 \u043A\u043B\u0430\u0432\u0438\u0448\u0435\u0439 Enter.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
