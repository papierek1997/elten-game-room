# Generated from tools/data/rulebooks/hearts.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class HeartsTable
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:play, GameRoomRules.translate("Hearts"),
            GameRoomRules.translate("Avoid taking hearts and the queen of spades. Each heart costs one point and the queen costs 13. The lowest score wins once someone reaches 100 and there is a sole leader. Taking all penalty cards gives each opponent 26 instead."),
            GameRoomRules.translate("Pass three cards left, right and across in successive deals, then keep your hand on the fourth. The two of clubs opens. Follow suit when possible. On the first trick, avoid penalty cards if you can. You may lead hearts after one has been played or when you hold only hearts. The highest card of the led suit takes the trick.")),
          rule_section(:controls, GameRoomRules.translate("Keyboard"),
            GameRoomRules.translate("Choose a card with the arrows and press Enter to pass or play it."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:play, "Srdce",
              "Za ka\u017Ed\u00E9 srdce dostanete trestn\u00FD bod a za pikovou d\u00E1mu t\u0159in\u00E1ct. Kdo vezme v\u0161echny trestn\u00E9 karty, p\u0159id\u00E1 ka\u017Ed\u00E9mu soupe\u0159i 26 bod\u016F. Jakmile n\u011Bkdo dos\u00E1hne 100 bod\u016F, vyhr\u00E1v\u00E1 hr\u00E1\u010D s nejni\u017E\u0161\u00EDm sk\u00F3re, pokud ho m\u00E1 jako jedin\u00FD.",
              "V prvn\u00EDch t\u0159ech rozd\u00E1n\u00EDch p\u0159edejte t\u0159i karty postupn\u011B doleva, doprava a naproti. Ve \u010Dtvrt\u00E9m si karty nechte a pak cyklus opakujte. Prvn\u00ED zdvih za\u010D\u00EDn\u00E1 dvojkou k\u0159\u00ED\u017E\u016F. M\u00E1te-li vynesenou barvu, p\u0159iznejte ji. V prvn\u00EDm zdvihu se vyhn\u011Bte trestn\u00FDm kart\u00E1m, pokud to jde. Srdce m\u016F\u017Eete vyn\u00E9st po zahr\u00E1n\u00ED prvn\u00EDho srdce nebo pokud m\u00E1te jen srdce. Zdvih bere nejvy\u0161\u0161\u00ED karta vynesen\u00E9 barvy."),
            rule_section(:controls, "Ovl\u00E1d\u00E1n\u00ED",
              "Vyberte kartu \u0161ipkami a potvr\u010Fte Enterem. Podle f\u00E1ze ji p\u0159ed\u00E1te nebo zahrajete.")
          ]
        when "en"
          [
            rule_section(:play, "Hearts",
              "Avoid taking hearts and the queen of spades. Each heart costs one point and the queen costs 13. The lowest score wins once someone reaches 100 and there is a sole leader. Taking all penalty cards gives each opponent 26 instead.",
              "Pass three cards left, right and across in successive deals, then keep your hand on the fourth. The two of clubs opens. Follow suit when possible. On the first trick, avoid penalty cards if you can. You may lead hearts after one has been played or when you hold only hearts. The highest card of the led suit takes the trick."),
            rule_section(:controls, "Keyboard",
              "Choose a card with the arrows and press Enter to pass or play it.")
          ]
        when "es"
          [
            rule_section(:play, "Corazones",
              "Cada coraz\u00F3n suma un punto de penalizaci\u00F3n y la dama de picas suma trece. Si recoges todas las cartas de penalizaci\u00F3n, cada rival recibe 26 puntos. Cuando alguien alcanza 100, gana quien tenga la puntuaci\u00F3n m\u00E1s baja si nadie la iguala.",
              "En las tres primeras manos pasa tres cartas a la izquierda, a la derecha y enfrente, respectivamente. En la cuarta te quedas con tus cartas. Despu\u00E9s se repite el ciclo. Abre el dos de tr\u00E9boles. Sigue el palo si puedes. En la primera baza evita las cartas de penalizaci\u00F3n si tienes otra opci\u00F3n. Puedes salir de corazones cuando ya se haya jugado uno o si solo te quedan corazones. La carta m\u00E1s alta del palo de salida gana la baza."),
            rule_section(:controls, "Teclado",
              "Elige una carta con las flechas y pulsa Intro para pasarla o jugarla, seg\u00FAn la fase.")
          ]
        when "pl"
          [
            rule_section(:play, "Kierki",
              "Cztery osoby graj\u0105 indywidualnie pe\u0142n\u0105 tali\u0105 52 kart, po 13 na r\u0119k\u0119. Wygrywa najni\u017Cszy wynik. Kier daje jeden punkt karny, a dama pik trzyna\u015Bcie. Pozosta\u0142e karty nie daj\u0105 punkt\u00F3w.",
              "W pierwszym rozdaniu przekazujesz trzy wybrane karty w lewo, w drugim w prawo, w trzecim naprzeciwko. W czwartym zachowujesz r\u0119k\u0119. Potem cykl wraca do pocz\u0105tku. Wymiana nast\u0119puje po wyborze kart przez wszystkich.",
              "Pierwsz\u0105 lew\u0119 zaczyna posiadacz dw\u00F3jki trefl i musi j\u0105 zagra\u0107. Dok\u0142adaj do koloru pierwszej karty, je\u015Bli mo\u017Cesz. Gdy go nie masz, wybierz kart\u0119 z innego koloru. W pierwszej lewie karta karna jest dozwolona tylko wtedy, gdy nie masz legalnej karty bez punkt\u00F3w.",
              "Kierem mo\u017Cesz wyj\u015B\u0107 dopiero po zagraniu pierwszego kiera w rozdaniu. Je\u015Bli zosta\u0142y ci same kiery, mo\u017Cesz nimi wyj\u015B\u0107 wcze\u015Bniej. Nie ma atut\u00F3w. Lew\u0119 bierze najwy\u017Csza karta koloru wyj\u015Bcia. As jest najwy\u017Cszy, dw\u00F3jka najni\u017Csza. Zwyci\u0119zca lewy wychodzi do nast\u0119pnej.",
              "Po trzynastu lewach ka\u017Cdy dolicza punkty karne z zabranych kart. Je\u015Bli jedna osoba zbierze wszystkie trzyna\u015Bcie kier\u00F3w i dam\u0119 pik, dostaje zero, a pozostali po 26. Nie trzeba wzi\u0105\u0107 wszystkich lew. Kiedy kto\u015B osi\u0105gnie co najmniej 100 punkt\u00F3w, wygrywa osoba z najni\u017Cszym wynikiem. Je\u015Bli kilka os\u00F3b dzieli najni\u017Cszy wynik, gra trwa do rozstrzygni\u0119cia."),
            rule_section(:controls, "Klawiatura",
              "Wybierz kart\u0119 strza\u0142kami i zatwierd\u017A Enterem, \u017Ceby j\u0105 przekaza\u0107 lub zagra\u0107.",
              "- H odczytuje r\u0119k\u0119. C odczytuje karty na stole, a Ctrl+C pozwala je przejrze\u0107.",
              "- S podaje punkty karne. T m\u00F3wi, czyja jest kolej. V podczas przekazywania kart podaje kierunek i liczb\u0119 wybranych kart.",
              "- F odczytuje kolor wyj\u015Bcia. Shift+S podaje punkty karne bie\u017C\u0105cego rozdania.",
              "- Z i Shift+Z przechodz\u0105 do kolejnej lub poprzedniej dost\u0119pnej karty. Shift+C sortuje wed\u0142ug koloru, Shift+H wed\u0142ug warto\u015Bci, a Shift+M przywraca kolejno\u015B\u0107 otrzymania.",
              "Podczas gry us\u0142yszysz zagrania, zwyci\u0119zc\u0119 lewy i punkty karne. Ka\u017Cde zagranie kiera ma dodatkowy d\u017Awi\u0119k. Dama pik ma osobny sygna\u0142. Po rozdaniu gra odczytuje punkty rozdania i \u0142\u0105czny wynik ka\u017Cdego gracza.")
          ]
        when "ru"
          [
            rule_section(:play, "\u0427\u0435\u0440\u0432\u044B",
              "\u041A\u0430\u0436\u0434\u0430\u044F \u0447\u0435\u0440\u0432\u0430 \u043F\u0440\u0438\u043D\u043E\u0441\u0438\u0442 \u043E\u0434\u043D\u043E \u0448\u0442\u0440\u0430\u0444\u043D\u043E\u0435 \u043E\u0447\u043A\u043E, \u0430 \u043F\u0438\u043A\u043E\u0432\u0430\u044F \u0434\u0430\u043C\u0430 \u2014 \u0442\u0440\u0438\u043D\u0430\u0434\u0446\u0430\u0442\u044C. \u0415\u0441\u043B\u0438 \u0432\u044B \u0441\u043E\u0431\u0440\u0430\u043B\u0438 \u0432\u0441\u0435 \u0448\u0442\u0440\u0430\u0444\u043D\u044B\u0435 \u043A\u0430\u0440\u0442\u044B, \u043A\u0430\u0436\u0434\u044B\u0439 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u043F\u043E 26 \u043E\u0447\u043A\u043E\u0432. \u041A\u043E\u0433\u0434\u0430 \u043A\u0442\u043E-\u043B\u0438\u0431\u043E \u043D\u0430\u0431\u0438\u0440\u0430\u0435\u0442 100 \u043E\u0447\u043A\u043E\u0432, \u0432\u044B\u0438\u0433\u0440\u044B\u0432\u0430\u0435\u0442 \u0438\u0433\u0440\u043E\u043A \u0441 \u043D\u0430\u0438\u043C\u0435\u043D\u044C\u0448\u0438\u043C \u0441\u0447\u0451\u0442\u043E\u043C, \u0435\u0441\u043B\u0438 \u043E\u043D \u043E\u0434\u0438\u043D.",
              "\u0412 \u043F\u0435\u0440\u0432\u044B\u0445 \u0442\u0440\u0451\u0445 \u0441\u0434\u0430\u0447\u0430\u0445 \u043F\u0435\u0440\u0435\u0434\u0430\u0439\u0442\u0435 \u043F\u043E \u0442\u0440\u0438 \u043A\u0430\u0440\u0442\u044B \u0438\u0433\u0440\u043E\u043A\u0443 \u0441\u043B\u0435\u0432\u0430, \u0441\u043F\u0440\u0430\u0432\u0430 \u0438 \u043D\u0430\u043F\u0440\u043E\u0442\u0438\u0432. \u0412 \u0447\u0435\u0442\u0432\u0451\u0440\u0442\u043E\u0439 \u043E\u0441\u0442\u0430\u0432\u044C\u0442\u0435 \u0441\u0432\u043E\u0438 \u043A\u0430\u0440\u0442\u044B. \u0417\u0430\u0442\u0435\u043C \u0446\u0438\u043A\u043B \u043F\u043E\u0432\u0442\u043E\u0440\u044F\u0435\u0442\u0441\u044F. \u041F\u0435\u0440\u0432\u0443\u044E \u0432\u0437\u044F\u0442\u043A\u0443 \u043E\u0442\u043A\u0440\u044B\u0432\u0430\u0435\u0442 \u0434\u0432\u043E\u0439\u043A\u0430 \u0442\u0440\u0435\u0444. \u041A\u043B\u0430\u0434\u0438\u0442\u0435 \u043A\u0430\u0440\u0442\u0443 \u043C\u0430\u0441\u0442\u0438 \u0445\u043E\u0434\u0430, \u0435\u0441\u043B\u0438 \u043E\u043D\u0430 \u0443 \u0432\u0430\u0441 \u0435\u0441\u0442\u044C. \u0412 \u043F\u0435\u0440\u0432\u043E\u0439 \u0432\u0437\u044F\u0442\u043A\u0435 \u0438\u0437\u0431\u0435\u0433\u0430\u0439\u0442\u0435 \u0448\u0442\u0440\u0430\u0444\u043D\u044B\u0445 \u043A\u0430\u0440\u0442, \u0435\u0441\u043B\u0438 \u0435\u0441\u0442\u044C \u0434\u0440\u0443\u0433\u043E\u0439 \u0445\u043E\u0434. \u0412\u044B\u0445\u043E\u0434\u0438\u0442\u044C \u0441 \u0447\u0435\u0440\u0432\u0435\u0439 \u043C\u043E\u0436\u043D\u043E \u043F\u043E\u0441\u043B\u0435 \u043F\u0435\u0440\u0432\u043E\u0439 \u0441\u044B\u0433\u0440\u0430\u043D\u043D\u043E\u0439 \u0447\u0435\u0440\u0432\u044B \u0438\u043B\u0438 \u0435\u0441\u043B\u0438 \u0443 \u0432\u0430\u0441 \u043E\u0441\u0442\u0430\u043B\u0438\u0441\u044C \u0442\u043E\u043B\u044C\u043A\u043E \u0447\u0435\u0440\u0432\u044B. \u0412\u0437\u044F\u0442\u043A\u0443 \u0431\u0435\u0440\u0451\u0442 \u0441\u0442\u0430\u0440\u0448\u0430\u044F \u043A\u0430\u0440\u0442\u0430 \u043C\u0430\u0441\u0442\u0438 \u0445\u043E\u0434\u0430."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0430\u0442\u0443\u0440\u0430",
              "\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u043A\u0430\u0440\u0442\u0443 \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0438 \u043D\u0430\u0436\u043C\u0438\u0442\u0435 Enter, \u0447\u0442\u043E\u0431\u044B \u043F\u0435\u0440\u0435\u0434\u0430\u0442\u044C \u0438\u043B\u0438 \u0441\u044B\u0433\u0440\u0430\u0442\u044C \u0435\u0451 \u0432 \u0437\u0430\u0432\u0438\u0441\u0438\u043C\u043E\u0441\u0442\u0438 \u043E\u0442 \u044D\u0442\u0430\u043F\u0430 \u0441\u0434\u0430\u0447\u0438.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
