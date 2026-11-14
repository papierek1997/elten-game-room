# Generated from tools/data/rulebooks/jass.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class JassTable
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:play, GameRoomRules.translate("Jass"),
            GameRoomRules.translate("Play in two partnerships. The opening player chooses trumps or passes the choice to their partner. The winner of each trick leads the next."),
            GameRoomRules.translate("Each player has nine cards. Follow a trump lead if you can. On a plain-suit lead, you may follow suit or trump. If you cannot follow, you may discard. When a trump is already down, avoid playing a lower trump if another legal card is available. The highest trump wins, or the highest card of the suit led if there are no trumps. The trump jack ranks first and scores 20, and the trump nine ranks second and scores 14. Aces score 11, tens 10, kings 4, queens 3 and other jacks 2. The last trick adds five points. The match target is 1,000.")),
          rule_section(:controls, GameRoomRules.translate("Keyboard"),
            GameRoomRules.translate("Use the arrow keys to choose a trump suit or card and press Enter."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:play, "Jass",
              "Hraje se ve dvojic\u00EDch. Prvn\u00ED hr\u00E1\u010D vybere trumfy nebo p\u0159enech\u00E1 volbu spoluhr\u00E1\u010Di. V\u00EDt\u011Bz zdvihu vyn\u00E1\u0161\u00ED do dal\u0161\u00EDho.",
              "Ka\u017Ed\u00FD dostane dev\u011Bt karet. Na vynesen\u00FD trumf p\u0159iznejte trumf, pokud ho m\u00E1te. Na jinou barvu m\u016F\u017Eete p\u0159iznat barvu nebo zahr\u00E1t trumf. Pokud barvu nem\u00E1te, m\u016F\u017Eete odhodit jinou kartu. Ni\u017E\u0161\u00ED trumf ne\u017E ten ve zdvihu zahrajte jen tehdy, kdy\u017E nem\u00E1te jin\u00FD dovolen\u00FD tah. Zdvih bere nejvy\u0161\u0161\u00ED trumf, jinak nejvy\u0161\u0161\u00ED karta vynesen\u00E9 barvy. Nejsiln\u011Bj\u0161\u00ED trumfov\u00FD kluk m\u00E1 20 bod\u016F a druh\u00E1 trumfov\u00E1 dev\u00EDtka 14. Eso m\u00E1 11, des\u00EDtka 10, kr\u00E1l 4, d\u00E1ma 3 a ostatn\u00ED kluci 2. Posledn\u00ED zdvih p\u0159id\u00E1 p\u011Bt bod\u016F. Hraje se do 1000 bod\u016F."),
            rule_section(:controls, "Ovl\u00E1d\u00E1n\u00ED",
              "\u0160ipkami vyberte trumfy nebo kartu a potvr\u010Fte Enterem.")
          ]
        when "en"
          [
            rule_section(:play, "Jass",
              "Play in two partnerships. The opening player chooses trumps or passes the choice to their partner. The winner of each trick leads the next.",
              "Each player has nine cards. Follow a trump lead if you can. On a plain-suit lead, you may follow suit or trump. If you cannot follow, you may discard. When a trump is already down, avoid playing a lower trump if another legal card is available. The highest trump wins, or the highest card of the suit led if there are no trumps. The trump jack ranks first and scores 20, and the trump nine ranks second and scores 14. Aces score 11, tens 10, kings 4, queens 3 and other jacks 2. The last trick adds five points. The match target is 1,000."),
            rule_section(:controls, "Keyboard",
              "Use the arrow keys to choose a trump suit or card and press Enter.")
          ]
        when "es"
          [
            rule_section(:play, "Jass",
              "Se juega por parejas. Quien abre elige el triunfo o cede la elecci\u00F3n a su pareja. Quien gana una baza abre la siguiente.",
              "Cada jugador recibe nueve cartas. Si se abre con triunfo, juega un triunfo si tienes alguno. Si se abre con otro palo, puedes seguir el palo o jugar un triunfo. Si no tienes el palo de salida, puedes descartar. Solo puedes jugar un triunfo inferior al que ya hay en la baza si no tienes otra jugada legal. Gana el triunfo m\u00E1s alto o, si no hay triunfos, la carta m\u00E1s alta del palo de salida. La jota de triunfo es la m\u00E1s alta y vale 20. El nueve de triunfo es el segundo y vale 14. El as vale 11, el diez 10, el rey 4, la dama 3 y las dem\u00E1s jotas 2. La \u00FAltima baza suma cinco puntos. La meta es llegar a 1000."),
            rule_section(:controls, "Teclado",
              "Elige el triunfo o la carta con las flechas y confirma con Intro.")
          ]
        when "pl"
          [
            rule_section(:play, "Jass",
              "Gracie w dw\u00F3ch parach. Partnerzy siedz\u0105 naprzeciw siebie. Talia sk\u0142ada si\u0119 z 36 kart, od sz\u00F3stki do asa w ka\u017Cdym kolorze. Ka\u017Cdy dostaje dziewi\u0119\u0107 kart. Gracz po rozdaj\u0105cym wybiera zasady rozdania albo przekazuje wyb\u00F3r partnerowi, kt\u00F3ry musi zdecydowa\u0107. Do pierwszej lewy wychodzi gracz po rozdaj\u0105cym, nawet je\u015Bli wyb\u00F3r przekaza\u0142 partnerowi.",
              "Pierwsza karta ustala kolor lewy. Do\u0142\u00F3\u017C do tego koloru, je\u015Bli mo\u017Cesz, lub zagraj atut. Je\u015Bli nie masz koloru wyj\u015Bcia, mo\u017Cesz te\u017C zrzuci\u0107 inn\u0105 kart\u0119. Gdy wyj\u015Bcie by\u0142o poza atutem i kto\u015B ju\u017C zagra\u0142 atut, ni\u017Cszy atut wolno zagra\u0107 tylko wtedy, gdy brak innego legalnego ruchu. Do wyj\u015Bcia w atucie do\u0142\u00F3\u017C atut, je\u015Bli go masz. Najwy\u017Cszy atut bierze lew\u0119. Bez atutu wygrywa najwy\u017Csza karta w kolorze wyj\u015Bcia. Zwyci\u0119zca wychodzi do kolejnej lewy.",
              "Si\u0142a atut\u00F3w od najwy\u017Cszego to walet (20 punkt\u00F3w), dziewi\u0105tka (14), as (11), kr\u00F3l (4), dama (3), dziesi\u0105tka (10), \u00F3semka, si\u00F3demka i sz\u00F3stka (po zero). Poza atutem kolejno\u015B\u0107 to as (11), kr\u00F3l (4), dama (3), walet (2), dziesi\u0105tka (10), dziewi\u0105tka, \u00F3semka, si\u00F3demka i sz\u00F3stka (po zero). Ostatnia lewa daje 5 dodatkowych punkt\u00F3w. Razem w rozdaniu jest 157 punkt\u00F3w.",
              "W odmianie Schieber mo\u017Cesz te\u017C wybra\u0107 Obenabe lub Undenufe. Obie s\u0105 bez atutu. W Obenabe lew\u0119 bierze najwy\u017Csza karta koloru wyj\u015Bcia. \u00D3semka daje 8 punkt\u00F3w. W Undenufe lew\u0119 bierze najni\u017Csza karta koloru wyj\u015Bcia, as daje zero, a sz\u00F3stka 11 punkt\u00F3w. \u00D3semka nadal daje 8. W obu trybach obowi\u0105zuje dok\u0142adanie do koloru, je\u015Bli masz jego kart\u0119.",
              "Punkty trafiaj\u0105 do pary, kt\u00F3ra zdoby\u0142a lew\u0119. Po rozdaniu rozdaje nast\u0119pny gracz. Cel meczu ustawiasz na 1000, 1500, 2000 albo 2500 punkt\u00F3w."),
            rule_section(:controls, "Klawiatura",
              "Podczas wyboru widzisz r\u0119k\u0119. Enter lub B otwiera menu wyboru atutu, trybu bez atutu albo przekazania decyzji partnerowi, zale\u017Cnie od dost\u0119pnych opcji. Strza\u0142kami wybierz i zatwierd\u017A Enterem. Podczas rozgrywki Enter zagrywa kart\u0119.",
              "- H odczytuje r\u0119k\u0119. C odczytuje karty na stole, a Ctrl+C je przegl\u0105da. F podaje zasady rozdania i kolor wyj\u015Bcia, a R i V podaj\u0105, kto wybiera atut albo kto go wybra\u0142 i jaki tryb obowi\u0105zuje.",
              "- S podaje wynik meczu, Shift+S punkty rozdania, a T kolej gracza.",
              "- Z i Shift+Z przechodz\u0105 do nast\u0119pnej lub poprzedniej legalnej karty. Shift+C sortuje wed\u0142ug koloru, Shift+H wed\u0142ug warto\u015Bci, a Shift+M przywraca kolejno\u015B\u0107 otrzymania kart.")
          ]
        when "ru"
          [
            rule_section(:play, "\u042F\u0441\u0441",
              "\u0418\u0433\u0440\u0430\u0439\u0442\u0435 \u043F\u0430\u0440\u0430\u043C\u0438. \u041F\u0435\u0440\u0432\u044B\u0439 \u0438\u0433\u0440\u043E\u043A \u0432\u044B\u0431\u0438\u0440\u0430\u0435\u0442 \u043A\u043E\u0437\u044B\u0440\u044C \u0438\u043B\u0438 \u043F\u0435\u0440\u0435\u0434\u0430\u0451\u0442 \u0432\u044B\u0431\u043E\u0440 \u043F\u0430\u0440\u0442\u043D\u0451\u0440\u0443. \u041F\u043E\u0431\u0435\u0434\u0438\u0442\u0435\u043B\u044C \u0432\u0437\u044F\u0442\u043A\u0438 \u043E\u0442\u043A\u0440\u044B\u0432\u0430\u0435\u0442 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0443\u044E.",
              "\u041A\u0430\u0436\u0434\u044B\u0439 \u043F\u043E\u043B\u0443\u0447\u0430\u0435\u0442 \u0434\u0435\u0432\u044F\u0442\u044C \u043A\u0430\u0440\u0442. \u0415\u0441\u043B\u0438 \u0445\u043E\u0434 \u0441\u0434\u0435\u043B\u0430\u043D \u0441 \u043A\u043E\u0437\u044B\u0440\u044F, \u043F\u043E\u043B\u043E\u0436\u0438\u0442\u0435 \u043A\u043E\u0437\u044B\u0440\u044C, \u0435\u0441\u043B\u0438 \u043E\u043D \u0443 \u0432\u0430\u0441 \u0435\u0441\u0442\u044C. \u041D\u0430 \u0445\u043E\u0434 \u0441 \u0434\u0440\u0443\u0433\u043E\u0439 \u043C\u0430\u0441\u0442\u0438 \u043C\u043E\u0436\u043D\u043E \u043E\u0442\u0432\u0435\u0442\u0438\u0442\u044C \u0442\u043E\u0439 \u0436\u0435 \u043C\u0430\u0441\u0442\u044C\u044E \u0438\u043B\u0438 \u043A\u043E\u0437\u044B\u0440\u0435\u043C. \u0415\u0441\u043B\u0438 \u043C\u0430\u0441\u0442\u0438 \u0445\u043E\u0434\u0430 \u043D\u0435\u0442, \u043C\u043E\u0436\u043D\u043E \u0441\u0431\u0440\u043E\u0441\u0438\u0442\u044C \u0434\u0440\u0443\u0433\u0443\u044E \u043A\u0430\u0440\u0442\u0443. \u041C\u043B\u0430\u0434\u0448\u0438\u0439 \u043A\u043E\u0437\u044B\u0440\u044C \u043C\u043E\u0436\u043D\u043E \u043F\u043E\u043B\u043E\u0436\u0438\u0442\u044C \u043D\u0430 \u0441\u0442\u0430\u0440\u0448\u0438\u0439, \u0442\u043E\u043B\u044C\u043A\u043E \u0435\u0441\u043B\u0438 \u0434\u0440\u0443\u0433\u043E\u0433\u043E \u0440\u0430\u0437\u0440\u0435\u0448\u0451\u043D\u043D\u043E\u0433\u043E \u0445\u043E\u0434\u0430 \u043D\u0435\u0442. \u0412\u0437\u044F\u0442\u043A\u0443 \u0431\u0435\u0440\u0451\u0442 \u0441\u0442\u0430\u0440\u0448\u0438\u0439 \u043A\u043E\u0437\u044B\u0440\u044C, \u0430 \u0431\u0435\u0437 \u043A\u043E\u0437\u044B\u0440\u0435\u0439 \u2014 \u0441\u0442\u0430\u0440\u0448\u0430\u044F \u043A\u0430\u0440\u0442\u0430 \u043C\u0430\u0441\u0442\u0438 \u0445\u043E\u0434\u0430. \u041A\u043E\u0437\u044B\u0440\u043D\u044B\u0439 \u0432\u0430\u043B\u0435\u0442 \u0441\u0442\u0430\u0440\u0448\u0435 \u0432\u0441\u0435\u0445 \u0438 \u0441\u0442\u043E\u0438\u0442 20 \u043E\u0447\u043A\u043E\u0432. \u0421\u043B\u0435\u0434\u043E\u043C \u0438\u0434\u0451\u0442 \u043A\u043E\u0437\u044B\u0440\u043D\u0430\u044F \u0434\u0435\u0432\u044F\u0442\u043A\u0430 \u0437\u0430 14 \u043E\u0447\u043A\u043E\u0432. \u0422\u0443\u0437 \u0441\u0442\u043E\u0438\u0442 11, \u0434\u0435\u0441\u044F\u0442\u043A\u0430 10, \u043A\u043E\u0440\u043E\u043B\u044C 4, \u0434\u0430\u043C\u0430 3, \u043E\u0441\u0442\u0430\u043B\u044C\u043D\u044B\u0435 \u0432\u0430\u043B\u0435\u0442\u044B 2. \u041F\u043E\u0441\u043B\u0435\u0434\u043D\u044F\u044F \u0432\u0437\u044F\u0442\u043A\u0430 \u0434\u0430\u0451\u0442 \u0435\u0449\u0451 \u043F\u044F\u0442\u044C \u043E\u0447\u043A\u043E\u0432. \u0426\u0435\u043B\u044C \u043C\u0430\u0442\u0447\u0430 \u2014 \u043D\u0430\u0431\u0440\u0430\u0442\u044C 1000 \u043E\u0447\u043A\u043E\u0432."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0430\u0442\u0443\u0440\u0430",
              "\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u043A\u043E\u0437\u044B\u0440\u044C \u0438\u043B\u0438 \u043A\u0430\u0440\u0442\u0443 \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0438 \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u0435 \u043A\u043B\u0430\u0432\u0438\u0448\u0435\u0439 Enter.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
