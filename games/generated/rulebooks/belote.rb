# Generated from tools/data/rulebooks/belote.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class BeloteTable
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:play, GameRoomRules.translate("Bidding and tricks"),
            GameRoomRules.translate("Two partnerships play to 1,000 points. With five cards in hand, choose the suit of the upcard or pass. After four passes you may choose a different suit. Eight passes trigger a redeal."),
            GameRoomRules.translate("Once trumps are chosen, everyone has eight cards. Follow suit when you can. If you cannot follow, trump unless your partner is winning. When you must trump, beat the highest trump in the trick if you can. The trick winner leads next."),
            GameRoomRules.translate("The partnership that chose trumps needs at least 82 points and must outscore the defenders. If you play the trump king while holding the trump queen and later play that queen, your side earns 20 points.")),
          rule_section(:controls, GameRoomRules.translate("Keyboard"),
            GameRoomRules.translate("Use the arrows to choose a bid, pass or card and press Enter."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:play, "Licitace a zdvihy",
              "Dv\u011B dvojice hraj\u00ED do 1000 bod\u016F. Po rozd\u00E1n\u00ED p\u011Bti karet p\u0159ijm\u011Bte barvu oto\u010Den\u00E9 karty jako trumf nebo pasujte. Po \u010Dty\u0159ech pasech lze zvolit jinou barvu. Po osmi pasech se rozd\u00E1v\u00E1 znovu.",
              "Po ur\u010Den\u00ED trumf\u016F m\u00E1 ka\u017Ed\u00FD osm karet. P\u0159izn\u00E1vejte barvu. Pokud ji nem\u00E1te, zahrajte trumf, leda\u017Ee zdvih vyhr\u00E1v\u00E1 spoluhr\u00E1\u010D. Kdy\u017E mus\u00EDte trumfovat, p\u0159ebijte nejvy\u0161\u0161\u00ED trumf, pokud m\u016F\u017Eete. V\u00EDt\u011Bz zdvihu vyn\u00E1\u0161\u00ED do dal\u0161\u00EDho.",
              "Dvojice, kter\u00E1 vybrala trumfy, pot\u0159ebuje alespo\u0148 82 bod\u016F a v\u00EDc ne\u017E soupe\u0159i. Zahrajete-li trumfov\u00E9ho kr\u00E1le a p\u0159itom m\u00E1te trumfovou d\u00E1mu, z\u00EDsk\u00E1 va\u0161e dvojice 20 bod\u016F, a\u017E zahrajete i d\u00E1mu."),
            rule_section(:controls, "Ovl\u00E1d\u00E1n\u00ED",
              "\u0160ipkami vyberte nab\u00EDdku, pas nebo kartu a potvr\u010Fte Enterem.")
          ]
        when "en"
          [
            rule_section(:play, "Bidding and tricks",
              "Two partnerships play to 1,000 points. With five cards in hand, choose the suit of the upcard or pass. After four passes you may choose a different suit. Eight passes trigger a redeal.",
              "Once trumps are chosen, everyone has eight cards. Follow suit when you can. If you cannot follow, trump unless your partner is winning. When you must trump, beat the highest trump in the trick if you can. The trick winner leads next.",
              "The partnership that chose trumps needs at least 82 points and must outscore the defenders. If you play the trump king while holding the trump queen and later play that queen, your side earns 20 points."),
            rule_section(:controls, "Keyboard",
              "Use the arrows to choose a bid, pass or card and press Enter.")
          ]
        when "es"
          [
            rule_section(:play, "Subasta y bazas",
              "Dos parejas juegan a 1000 puntos. Con cinco cartas en la mano, elige el palo de la carta descubierta como triunfo o pasa. Tras cuatro pases se puede elegir otro palo. Tras ocho pases se vuelve a repartir.",
              "Elegido el triunfo, cada jugador tiene ocho cartas. Sigue el palo si puedes. Si no puedes, juega un triunfo salvo que tu pareja vaya ganando la baza. Si tienes que jugar un triunfo, supera al m\u00E1s alto de la baza si puedes. Quien gana la baza abre la siguiente.",
              "La pareja que elige el triunfo necesita al menos 82 puntos y debe superar a la defensa. Si juegas el rey de triunfo mientras tienes la dama de triunfo, tu pareja gana 20 puntos cuando juegues tambi\u00E9n esa dama."),
            rule_section(:controls, "Teclado",
              "Elige una oferta, pasar o una carta con las flechas y confirma con Intro.")
          ]
        when "pl"
          [
            rule_section(:play, "Licytacja i lewy",
              "Gracie w dw\u00F3ch parach. Partnerzy siedz\u0105 naprzeciw siebie, wi\u0119c przy stole graj\u0105 na przemian osoby z obu dru\u017Cyn. Gra toczy si\u0119 do 1000 punkt\u00F3w. Po ka\u017Cdym rozdaniu rozdaje nast\u0119pny gracz.",
              "Ka\u017Cdy najpierw dostaje pi\u0119\u0107 kart. Gra odkrywa nast\u0119pn\u0105 kart\u0119 i proponuje jej kolor jako atut. Licytacj\u0119 zaczyna gracz po rozdaj\u0105cym. W pierwszej kolejce mo\u017Cna przyj\u0105\u0107 proponowany kolor albo spasowa\u0107. Je\u015Bli wszyscy spasuj\u0105, w drugiej kolejce mo\u017Cna wybra\u0107 dowolny inny kolor. Po o\u015Bmiu pasach nast\u0119puje nowe rozdanie.",
              "Pierwszy wyb\u00F3r atutu ko\u0144czy licytacj\u0119. Odkryta karta trafia do gracza, kt\u00F3ry wybra\u0142 atut. Gra uzupe\u0142nia r\u0119ce do o\u015Bmiu kart. Dru\u017Cyna tego gracza zobowi\u0105zuje si\u0119 zdoby\u0107 co najmniej 82 punkty i pokona\u0107 obron\u0119.",
              "Do pustej lewy mo\u017Cna wyj\u015B\u0107 dowoln\u0105 kart\u0105. Potem trzeba dok\u0142ada\u0107 do koloru wyj\u015Bcia. Je\u015Bli go nie masz, zagraj atut, chyba \u017Ce lew\u0119 wygrywa partner. Gdy trzeba zagra\u0107 atut, przebij najwy\u017Cszy atut w lewie, je\u015Bli mo\u017Cesz. Gdy nie masz ani koloru wyj\u015Bcia, ani atutu, mo\u017Cesz zrzuci\u0107 dowoln\u0105 kart\u0119. Lew\u0119 bierze najwy\u017Cszy atut, a je\u015Bli atutu nie zagrano, najwy\u017Csza karta w kolorze wyj\u015Bcia. Zwyci\u0119zca wychodzi do nast\u0119pnej lewy.",
              "Atuty od najsilniejszego: walet (20 punkt\u00F3w), dziewi\u0105tka (14), as (11), dziesi\u0105tka (10), kr\u00F3l (4), dama (3), \u00F3semka (0), si\u00F3demka (0).",
              "Karty poza atutem od najsilniejszej: as (11 punkt\u00F3w), dziesi\u0105tka (10), kr\u00F3l (4), dama (3), walet (2), dziewi\u0105tka (0), \u00F3semka (0), si\u00F3demka (0). Dziesi\u0105tka bije kr\u00F3la, dam\u0119 i waleta poza atutem.",
              "Je\u015Bli masz kr\u00F3la i dam\u0119 atutow\u0105, zagraj dowoln\u0105 z tych dw\u00F3ch kart przez Shift+Enter, aby zg\u0142osi\u0107 belote. P\u00F3\u017Aniej zagraj drug\u0105 przez Shift+Enter, aby zg\u0142osi\u0107 rebelote. Mo\u017Cesz meldowa\u0107 r\u00F3wnie\u017C przy dok\u0142adaniu do lewy, je\u015Bli zagranie jest dozwolone. Oba zg\u0142oszenia daj\u0105 dru\u017Cynie 20 punkt\u00F3w.",
              "Ostatnia lewa daje dodatkowe 10 punkt\u00F3w. Bez meldunku w kartach i ostatniej lewie jest razem 162 punkty. Przy udanym kontrakcie ka\u017Cda dru\u017Cyna zapisuje zdobyte punkty. Przy przegranej obrona dostaje 162 punkty z lew, a dru\u017Cyna licytuj\u0105ca zapisuje tylko ewentualny meldunek. Przy remisie obrona zapisuje swoje punkty, a punkty z lew dru\u017Cyny licytuj\u0105cej trafiaj\u0105 do zwyci\u0119zcy nast\u0119pnego rozstrzygni\u0119tego rozdania. Premia za meldunek nie przechodzi dalej. Za wszystkie osiem lew gra dolicza 90 punkt\u00F3w, co daje 252 punkty przed meldunkiem."),
            rule_section(:coinchee, "Belote Coinch\u00E9e",
              "W ustawieniach sto\u0142u wybierz Coinch\u00E9e. Domy\u015Blnie ka\u017Cdy dostaje od razu osiem kart. Je\u015Bli w\u0142\u0105czysz rozdawanie w dw\u00F3ch etapach, ka\u017Cdy zaczyna z pi\u0119cioma kartami. Odkryta karta trafia do zwyci\u0119zcy licytacji, ale nie ogranicza wyboru atutu. Po licytacji gra uzupe\u0142nia ka\u017Cdemu r\u0119k\u0119 do o\u015Bmiu kart. Gracz po rozdaj\u0105cym rozpoczyna licytacj\u0119.",
              "Strza\u0142kami wybierz pas albo ofert\u0119 i zatwierd\u017A Enterem. Oferta okre\u015Bla kolor atutu i liczb\u0119 punkt\u00F3w od 80 do 160, co 10. Na przyk\u0142ad 90 w kierach oznacza zobowi\u0105zanie do zdobycia co najmniej 90 punkt\u00F3w z kierami jako atutem. Ka\u017Cda nowa oferta musi mie\u0107 wy\u017Csz\u0105 liczb\u0119 punkt\u00F3w.",
              "Przeciwnik dru\u017Cyny prowadz\u0105cej licytacj\u0119 mo\u017Ce da\u0107 kontr\u0119. Kontra blokuje podbijanie i podwaja wynik rozdania. Dru\u017Cyna licytuj\u0105ca mo\u017Ce odpowiedzie\u0107 rekontr\u0105, kt\u00F3ra zwi\u0119ksza mno\u017Cnik do czterech. Trzy pasy po ostatniej ofercie, kontrze lub rekontrze ko\u0144cz\u0105 licytacj\u0119. Po czterech pasach bez oferty nast\u0119puje nowe rozdanie.",
              "Karty, lewy i meldunki dzia\u0142aj\u0105 jak w klasycznym Belote. Kontrakt wygrywa dru\u017Cyna licytuj\u0105ca, je\u015Bli osi\u0105gnie zadeklarowany pr\u00F3g i zdob\u0119dzie wi\u0119cej punkt\u00F3w od obrony. Przy sukcesie obie dru\u017Cyny zapisuj\u0105 punkty z lew. Przy pora\u017Cce, r\u00F3wnie\u017C przy remisie, obrona zapisuje 162 punkty z lew, a licytuj\u0105cy zero. Gra uwzgl\u0119dnia premi\u0119 za komplet lew oraz zg\u0142oszone meldunki, a potem mno\u017Cy zapis obu dru\u017Cyn przez dwa po kontrze albo przez cztery po rekontrze."),
            rule_section(:controls, "Klawiatura",
              "Strza\u0142kami wybierz kart\u0119 lub pozycj\u0119 menu. Enter zagrywa kart\u0119 albo zatwierdza wyb\u00F3r. Podczas licytacji widzisz r\u0119k\u0119. Enter lub B otwiera wyb\u00F3r kontraktu albo pasu w obu kolejkach licytacji. Wybierz pozycj\u0119 strza\u0142kami i zatwierd\u017A Enterem. Escape wraca do kart. W klasycznym Belote w pierwszej kolejce wybierasz kolor odkrytej karty, a w drugiej inny kolor. W Coinch\u00E9e wybierasz liczb\u0119 punkt\u00F3w i kolor, a tak\u017Ce kontr\u0119 lub rekontr\u0119, kiedy s\u0105 dost\u0119pne.",
              "- H odczytuje r\u0119k\u0119. C odczytuje karty na stole. Ctrl+C pozwala je przejrze\u0107.",
              "- D odczytuje odkryt\u0105 kart\u0119 w klasycznym Belote. F odczytuje atut i kolor wyj\u015Bcia do lewy, je\u015Bli lewa ju\u017C si\u0119 zacz\u0119\u0142a.",
              "- S odczytuje wynik meczu. Shift+S podaje punkty bie\u017C\u0105cego rozdania z lew i zg\u0142oszonych meldunk\u00F3w, przed mno\u017Cnikiem kontry. T m\u00F3wi, czyja jest kolej. R i V odczytuj\u0105 kontrakt, gracza, kt\u00F3ry wybra\u0142 atut, jego par\u0119, kolor atutu i wymagany pr\u00F3g.",
              "- Shift+Enter zagrywa wskazanego kr\u00F3la lub dam\u0119 atutow\u0105 razem z meldunkiem. Zg\u0142oszenie potwierdza d\u017Awi\u0119k.",
              "- Z przechodzi do nast\u0119pnej karty, kt\u00F3r\u0105 mo\u017Cna zagra\u0107. Shift+Z przechodzi do poprzedniej.",
              "- Shift+C sortuje r\u0119k\u0119 wed\u0142ug kolor\u00F3w. Shift+H sortuje wed\u0142ug warto\u015Bci. Ponowne naci\u015Bni\u0119cie odwraca kierunek sortowania. Shift+M przywraca kolejno\u015B\u0107 otrzymania kart.")
          ]
        when "ru"
          [
            rule_section(:play, "\u0422\u043E\u0440\u0433\u0438 \u0438 \u0432\u0437\u044F\u0442\u043A\u0438",
              "\u0414\u0432\u0435 \u043F\u0430\u0440\u044B \u0438\u0433\u0440\u0430\u044E\u0442 \u0434\u043E 1000 \u043E\u0447\u043A\u043E\u0432. \u041F\u043E\u043B\u0443\u0447\u0438\u0432 \u043F\u044F\u0442\u044C \u043A\u0430\u0440\u0442, \u0432\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u043C\u0430\u0441\u0442\u044C \u043E\u0442\u043A\u0440\u044B\u0442\u043E\u0439 \u043A\u0430\u0440\u0442\u044B \u043A\u043E\u0437\u044B\u0440\u0435\u043C \u0438\u043B\u0438 \u0441\u043F\u0430\u0441\u0443\u0439\u0442\u0435. \u041F\u043E\u0441\u043B\u0435 \u0447\u0435\u0442\u044B\u0440\u0451\u0445 \u043F\u0430\u0441\u043E\u0432 \u043C\u043E\u0436\u043D\u043E \u0432\u044B\u0431\u0440\u0430\u0442\u044C \u0434\u0440\u0443\u0433\u0443\u044E \u043C\u0430\u0441\u0442\u044C. \u041F\u043E\u0441\u043B\u0435 \u0432\u043E\u0441\u044C\u043C\u0438 \u043F\u0430\u0441\u043E\u0432 \u043A\u0430\u0440\u0442\u044B \u0441\u0434\u0430\u044E\u0442 \u0437\u0430\u043D\u043E\u0432\u043E.",
              "\u041F\u043E\u0441\u043B\u0435 \u0432\u044B\u0431\u043E\u0440\u0430 \u043A\u043E\u0437\u044B\u0440\u044F \u0443 \u043A\u0430\u0436\u0434\u043E\u0433\u043E \u0432\u043E\u0441\u0435\u043C\u044C \u043A\u0430\u0440\u0442. \u041A\u043B\u0430\u0434\u0438\u0442\u0435 \u043A\u0430\u0440\u0442\u0443 \u043C\u0430\u0441\u0442\u0438 \u0445\u043E\u0434\u0430, \u0435\u0441\u043B\u0438 \u043E\u043D\u0430 \u0443 \u0432\u0430\u0441 \u0435\u0441\u0442\u044C. \u0415\u0441\u043B\u0438 \u0435\u0451 \u043D\u0435\u0442, \u0441\u044B\u0433\u0440\u0430\u0439\u0442\u0435 \u043A\u043E\u0437\u044B\u0440\u0435\u043C, \u043A\u0440\u043E\u043C\u0435 \u0441\u043B\u0443\u0447\u0430\u044F, \u043A\u043E\u0433\u0434\u0430 \u0432\u0437\u044F\u0442\u043A\u0443 \u043F\u043E\u043A\u0430 \u0431\u0435\u0440\u0451\u0442 \u043F\u0430\u0440\u0442\u043D\u0451\u0440. \u041A\u043E\u0433\u0434\u0430 \u043D\u0443\u0436\u043D\u043E \u043A\u043E\u0437\u044B\u0440\u044F\u0442\u044C, \u043F\u0435\u0440\u0435\u0431\u0435\u0439\u0442\u0435 \u0441\u0442\u0430\u0440\u0448\u0438\u0439 \u043A\u043E\u0437\u044B\u0440\u044C \u0432\u043E \u0432\u0437\u044F\u0442\u043A\u0435, \u0435\u0441\u043B\u0438 \u043C\u043E\u0436\u0435\u0442\u0435. \u041F\u043E\u0431\u0435\u0434\u0438\u0442\u0435\u043B\u044C \u0432\u0437\u044F\u0442\u043A\u0438 \u0445\u043E\u0434\u0438\u0442 \u043F\u0435\u0440\u0432\u044B\u043C \u0432 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0435\u0439.",
              "\u041F\u0430\u0440\u0430, \u0432\u044B\u0431\u0440\u0430\u0432\u0448\u0430\u044F \u043A\u043E\u0437\u044B\u0440\u044C, \u0434\u043E\u043B\u0436\u043D\u0430 \u043D\u0430\u0431\u0440\u0430\u0442\u044C \u043D\u0435 \u043C\u0435\u043D\u044C\u0448\u0435 82 \u043E\u0447\u043A\u043E\u0432 \u0438 \u043E\u0431\u043E\u0439\u0442\u0438 \u0441\u043E\u043F\u0435\u0440\u043D\u0438\u043A\u043E\u0432. \u0415\u0441\u043B\u0438 \u0432\u044B \u0441\u044B\u0433\u0440\u0430\u043B\u0438 \u043A\u043E\u0437\u044B\u0440\u043D\u044B\u043C \u043A\u043E\u0440\u043E\u043B\u0451\u043C, \u0438\u043C\u0435\u044F \u043D\u0430 \u0440\u0443\u043A\u0430\u0445 \u043A\u043E\u0437\u044B\u0440\u043D\u0443\u044E \u0434\u0430\u043C\u0443, \u0442\u043E \u043F\u043E\u0441\u043B\u0435 \u0435\u0451 \u0440\u043E\u0437\u044B\u0433\u0440\u044B\u0448\u0430 \u0432\u0430\u0448\u0430 \u043F\u0430\u0440\u0430 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 20 \u043E\u0447\u043A\u043E\u0432."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0430\u0442\u0443\u0440\u0430",
              "\u0421\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0432\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0437\u0430\u044F\u0432\u043A\u0443, \u043F\u0430\u0441 \u0438\u043B\u0438 \u043A\u0430\u0440\u0442\u0443 \u0438 \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u0435 \u043A\u043B\u0430\u0432\u0438\u0448\u0435\u0439 Enter.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
