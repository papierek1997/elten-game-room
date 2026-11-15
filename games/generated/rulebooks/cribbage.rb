# Generated from tools/data/rulebooks/cribbage.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class CribbageTable
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:play, GameRoomRules.translate("Cribbage"),
            GameRoomRules.translate("Play to 121. Discard two of your six cards to the crib, which scores for the dealer. Then turn up the starter. A jack gives the dealer two points."),
            GameRoomRules.translate("Take turns playing cards without exceeding 31. Aces count one and face cards ten. Totals of 15 and 31, pairs and runs can score. Choose Go if none of your cards fits. After play, count the nondealer\u2019s hand, then the dealer\u2019s hand, then the crib. Include the starter in each count.")),
          rule_section(:controls, GameRoomRules.translate("Keyboard"),
            GameRoomRules.translate("Use the arrows to select a card or Go and press Enter."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:play, "Hra",
              "Hraje se do 121 bod\u016F. Dv\u011B ze \u0161esti karet odlo\u017Ete do cribu, kter\u00FD se po\u010D\u00EDt\u00E1 rozd\u00E1vaj\u00EDc\u00EDmu. Pot\u00E9 se oto\u010D\u00ED spole\u010Dn\u00E1 karta. Je-li to kluk, rozd\u00E1vaj\u00EDc\u00ED dostane dva body.",
              "St\u0159\u00EDdejte se v hran\u00ED karet, sou\u010Det nesm\u00ED p\u0159ekro\u010Dit 31. Eso m\u00E1 hodnotu jedna a figury deset. Body z\u00EDsk\u00E1te nap\u0159\u00EDklad za sou\u010Det 15 nebo 31, p\u00E1ry a postupky. Jestli\u017Ee \u017E\u00E1dn\u00E1 karta nep\u0159ipad\u00E1 v \u00FAvahu, zvolte Pas. Nakonec se spole\u010Dnou kartou vyhodno\u0165te nejd\u0159\u00EDve ruku soupe\u0159e rozd\u00E1vaj\u00EDc\u00EDho, potom ruku rozd\u00E1vaj\u00EDc\u00EDho a nakonec crib."),
            rule_section(:controls, "Ovl\u00E1d\u00E1n\u00ED",
              "\u0160ipkami vyberte kartu nebo Pas a potvr\u010Fte Enterem.")
          ]
        when "en"
          [
            rule_section(:play, "Cribbage",
              "Play to 121. Discard two of your six cards to the crib, which scores for the dealer. Then turn up the starter. A jack gives the dealer two points.",
              "Take turns playing cards without exceeding 31. Aces count one and face cards ten. Totals of 15 and 31, pairs and runs can score. Choose Go if none of your cards fits. After play, count the nondealer\u2019s hand, then the dealer\u2019s hand, then the crib. Include the starter in each count."),
            rule_section(:controls, "Keyboard",
              "Use the arrows to select a card or Go and press Enter.")
          ]
        when "es"
          [
            rule_section(:play, "La partida",
              "Se juega a 121 puntos. De tus seis cartas, descarta dos a la cuna, que punt\u00FAa para quien reparte. Luego se descubre la carta inicial. Si es una jota, quien reparte gana dos puntos.",
              "Jugad una carta por turno sin superar 31. El as vale uno y las figuras diez. Punt\u00FAan, entre otras jugadas, los totales de 15 y 31, las parejas y las escaleras. Pasa si no puedes jugar ninguna carta. Al acabar, cuenta primero la mano de quien no reparte, despu\u00E9s la del repartidor y por \u00FAltimo la cuna. Usa la carta inicial en los tres recuentos."),
            rule_section(:controls, "Teclado",
              "Elige una carta o pasar con las flechas y confirma con Intro.")
          ]
        when "pl"
          [
            rule_section(:play, "Cribbage",
              "Gracie do 121 punkt\u00F3w. Od\u0142\u00F3\u017C dwie z sze\u015Bciu kart do cribu. Crib zapunktuje dla rozdaj\u0105cego. Nast\u0119pnie odkrywa si\u0119 kart\u0119 startow\u0105. Je\u015Bli to walet, rozdaj\u0105cy dostaje dwa punkty.",
              "Zagrywajcie na zmian\u0119, nie przekraczaj\u0105c 31. As jest wart jeden, figury po dziesi\u0119\u0107. Punkty daj\u0105 mi\u0119dzy innymi sumy 15 i 31, pary i sekwencje. Wybierz Pas, gdy \u017Cadna karta si\u0119 nie mie\u015Bci. Po zagraniu kart policzcie kolejno r\u0119k\u0119 osoby nierozdaj\u0105cej, r\u0119k\u0119 rozdaj\u0105cego i crib. W ka\u017Cdym z tych uk\u0142ad\u00F3w uwzgl\u0119dnij kart\u0119 startow\u0105.",
              "Podczas zagrywania 15 i 31 daj\u0105 po 2 punkty. Dwie, trzy lub cztery jednakowe karty zagrane z rz\u0119du daj\u0105 odpowiednio 2, 6 lub 12 punkt\u00F3w. Sekwencja co najmniej trzech ostatnich kart daje tyle punkt\u00F3w, ile ma kart, niezale\u017Cnie od kolejno\u015Bci zagrania. Ostatnia karta przed wyzerowaniem sumy daje 1 punkt, je\u015Bli suma jest mniejsza ni\u017C 31.",
              "Przy liczeniu r\u0119ki i cribu ka\u017Cda kombinacja daj\u0105ca 15 i ka\u017Cda para daj\u0105 po 2 punkty. Ka\u017Cda najd\u0142u\u017Csza sekwencja od trzech kart daje punkt za kart\u0119. Cztery karty jednego koloru w r\u0119ce daj\u0105 4 punkty, a zgodna karta startowa daje pi\u0105ty. W cribie kolor liczy si\u0119 tylko wtedy, gdy wszystkie pi\u0119\u0107 kart ma ten sam kolor. Walet w r\u0119ce lub cribie w kolorze karty startowej daje 1 punkt."),
            rule_section(:controls, "Klawiatura",
              "Wybierz kart\u0119 lub Pas strza\u0142kami i zatwierd\u017A Enterem.",
              "- H odczytuje r\u0119k\u0119, S podaje wynik, T m\u00F3wi, czyja jest kolej. C odczytuje bie\u017C\u0105c\u0105 sum\u0119 podczas zagrywania kart.")
          ]
        when "ru"
          [
            rule_section(:play, "\u0425\u043E\u0434 \u0438\u0433\u0440\u044B",
              "\u0418\u0433\u0440\u0430\u0439\u0442\u0435 \u0434\u043E 121 \u043E\u0447\u043A\u0430. \u041E\u0442\u043B\u043E\u0436\u0438\u0442\u0435 \u0434\u0432\u0435 \u0438\u0437 \u0448\u0435\u0441\u0442\u0438 \u043A\u0430\u0440\u0442 \u0432 \u043A\u0440\u0438\u0431, \u043A\u043E\u0442\u043E\u0440\u044B\u0439 \u043F\u0440\u0438\u043D\u0435\u0441\u0451\u0442 \u043E\u0447\u043A\u0438 \u0441\u0434\u0430\u044E\u0449\u0435\u043C\u0443. \u0417\u0430\u0442\u0435\u043C \u043E\u0442\u043A\u0440\u043E\u0439\u0442\u0435 \u0441\u0442\u0430\u0440\u0442\u043E\u0432\u0443\u044E \u043A\u0430\u0440\u0442\u0443. \u0415\u0441\u043B\u0438 \u044D\u0442\u043E \u0432\u0430\u043B\u0435\u0442, \u0441\u0434\u0430\u044E\u0449\u0438\u0439 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u0434\u0432\u0430 \u043E\u0447\u043A\u0430.",
              "\u041F\u043E \u043E\u0447\u0435\u0440\u0435\u0434\u0438 \u0432\u044B\u043A\u043B\u0430\u0434\u044B\u0432\u0430\u0439\u0442\u0435 \u043A\u0430\u0440\u0442\u044B, \u043D\u0435 \u043F\u0440\u0435\u0432\u044B\u0448\u0430\u044F \u0441\u0443\u043C\u043C\u0443 31. \u0422\u0443\u0437 \u0441\u0442\u043E\u0438\u0442 \u043E\u0434\u043D\u043E \u043E\u0447\u043A\u043E, \u043A\u0430\u0440\u0442\u0438\u043D\u043A\u0438 \u2014 \u043F\u043E \u0434\u0435\u0441\u044F\u0442\u044C. \u041E\u0447\u043A\u0438 \u0434\u0430\u044E\u0442, \u043D\u0430\u043F\u0440\u0438\u043C\u0435\u0440, \u0441\u0443\u043C\u043C\u044B 15 \u0438 31, \u043F\u0430\u0440\u044B \u0438 \u043F\u043E\u0441\u043B\u0435\u0434\u043E\u0432\u0430\u0442\u0435\u043B\u044C\u043D\u043E\u0441\u0442\u0438. \u0415\u0441\u043B\u0438 \u043D\u0438 \u043E\u0434\u043D\u0430 \u043A\u0430\u0440\u0442\u0430 \u043D\u0435 \u043F\u043E\u0434\u0445\u043E\u0434\u0438\u0442, \u0432\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u00AB\u041F\u0430\u0441\u00BB. \u0412 \u043A\u043E\u043D\u0446\u0435 \u043F\u043E\u0434\u0441\u0447\u0438\u0442\u0430\u0439\u0442\u0435 \u0441\u043D\u0430\u0447\u0430\u043B\u0430 \u0440\u0443\u043A\u0443 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u0430 \u0441\u0434\u0430\u044E\u0449\u0435\u0433\u043E, \u0437\u0430\u0442\u0435\u043C \u0440\u0443\u043A\u0443 \u0441\u0434\u0430\u044E\u0449\u0435\u0433\u043E \u0438 \u043A\u0440\u0438\u0431. \u0412 \u043A\u0430\u0436\u0434\u043E\u043C \u043F\u043E\u0434\u0441\u0447\u0451\u0442\u0435 \u0443\u0447\u0438\u0442\u044B\u0432\u0430\u0439\u0442\u0435 \u0441\u0442\u0430\u0440\u0442\u043E\u0432\u0443\u044E \u043A\u0430\u0440\u0442\u0443."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0430\u0442\u0443\u0440\u0430",
              "\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u043A\u0430\u0440\u0442\u0443 \u0438\u043B\u0438 \u00AB\u041F\u0430\u0441\u00BB \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0438 \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u0435 \u043A\u043B\u0430\u0432\u0438\u0448\u0435\u0439 Enter.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
