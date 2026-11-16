# Generated from tools/data/rulebooks/quiz.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class QuizParty
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:question, GameRoomRules.translate("Everyone answers the same question"),
            GameRoomRules.translate("Quiz Party is for two to eight participants, with bots available. Each question has four proposed answers and one is marked correct in the question set. Everyone answers independently. Use the arrows to choose an answer and Enter to submit it. Your submission is final for that question and stays hidden until the answering period closes."),
            GameRoomRules.translate("A correct answer gives one point. A wrong answer or no answer gives zero; there are no negative points. Answering first earns no extra points, provided everyone answers within the time allowed. You can therefore use the available time to think instead of racing to press Enter.")),
          rule_section(:round, GameRoomRules.translate("One category lasts for three questions"),
            GameRoomRules.translate("A round consists of three questions. At its start, the game draws three available categories and one participant chooses which will be used for all three questions. The right to choose moves between players in successive rounds."),
            GameRoomRules.translate("After everyone answers or time expires, the game reveals the answers and awards points, then prepares the next question. Preparing a question is not another answer choice: wait for the new question to appear. Once all three have been settled, the round summary is available and the next category selection begins unless the match has ended.")),
          rule_section(:sets, GameRoomRules.translate("Choose the content, not the interface language"),
            GameRoomRules.translate("When creating or configuring the table, first choose a question language and then a set offered in that language. The set label gives the number of questions supplied. This choice does not change anyone's interface: a Polish interface can still display questions from an English or Italian set. The language and set are shared by the whole table."),
            GameRoomRules.translate("The Polish Witcher \u2014 books set contains questions about Andrzej Sapkowski's stories and novels, not games or screen adaptations. It covers the whole plot, including endings. Questions from Droga, z kt\u00F3rej si\u0119 nie wraca and the alternative Co\u015B si\u0119 ko\u0144czy, co\u015B si\u0119 zaczyna always name the story.")),
          rule_section(:time, GameRoomRules.translate("Answer time and the finishing line"),
            GameRoomRules.translate("Time for one answer defaults to 20 seconds. The offered choices are 5\u201310 seconds one second apart, then 15\u201360 in steps of five. This limit applies separately to each question. The target defaults to 15 points; the list also offers 20, 25, 30, 40 and 50."),
            GameRoomRules.translate("Reaching the target does not cut short a round. Finish all three questions, then the highest score wins. If the highest scores are equal, play another complete round and check again, continuing until one player leads. Bots sometimes know an answer and otherwise guess; adding one does not make every answer perfect. Saving a partly played Quiz Party match is not supported.")),
          rule_section(:reports, GameRoomRules.translate("Reporting a question"),
            GameRoomRules.translate("If you spot a mistake, press Ctrl+B to mark the current question or Ctrl+Shift+B to mark the previous one. You can keep playing straight away."),
            GameRoomRules.translate("When you leave the table, you will be asked whether you want to report the marked questions. Choose Yes, describe the problem with each question and press Send. The question and its answers are included automatically. Choosing No discards the marks; they are not saved for later."),
            GameRoomRules.translate("The report form also shows the answer marked as correct in the set.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: choose a category or answer."),
            GameRoomRules.translate("Enter: submit the highlighted choice."),
            GameRoomRules.translate("T: read the question."),
            GameRoomRules.translate("Ctrl+Alt+T: read the remaining answer time."),
            GameRoomRules.translate("V: read the round summary."),
            GameRoomRules.translate("S: read scores."),
            GameRoomRules.translate("Ctrl+B: mark the current question for reporting."),
            GameRoomRules.translate("Ctrl+Shift+B: mark the previous question for reporting."))
        ]
      end

      def localized_rule_sections
        case GameRoomLocalization.primary_language
        when "cs"
          [
            rule_section(:goal, "C\u00EDl kv\u00EDzu",
              "V kv\u00EDzu odpov\u00EDd\u00E1te na ot\u00E1zky ze zvolen\u00E9ho oboru. U ka\u017Ed\u00E9 jsou \u010Dty\u0159i mo\u017Enosti a pr\u00E1v\u011B jedna spr\u00E1vn\u00E1. Spr\u00E1vn\u00E1 odpov\u011B\u010F p\u0159inese bod, chybn\u00E1 \u017E\u00E1dn\u00FD neodebere, tak\u017Ee stoj\u00ED za to zkusit odpov\u011Bd\u011Bt i p\u0159i nejistot\u011B.",
              "Hr\u00E1t mohou dva a\u017E osm hr\u00E1\u010D\u016F, v\u010Detn\u011B bot\u016F. V\u0161ichni dostanou stejnou ot\u00E1zku a odpov\u00EDdaj\u00ED samostatn\u011B. Rychlej\u0161\u00ED stisknut\u00ED Enteru \u017E\u00E1dnou v\u00FDhodu v bodov\u00E1n\u00ED ned\u00E1v\u00E1."),
            rule_section(:round, "Kategorie a odpov\u011Bdi",
              "Na za\u010D\u00E1tku kola jeden hr\u00E1\u010D vyb\u00EDr\u00E1 ze t\u0159\u00ED n\u00E1hodn\u011B nab\u00EDdnut\u00FDch kategori\u00ED. Jsi-li na \u0159ad\u011B ty, vyber \u0161ipkami a potvr\u010F Enterem. V tomto kole v\u00E1s \u010Dekaj\u00ED t\u0159i ot\u00E1zky z vybran\u00E9 kategorie; v p\u0159\u00ED\u0161t\u00EDm kole vol\u00ED dal\u0161\u00ED hr\u00E1\u010D.",
              "Na ka\u017Edou ot\u00E1zku m\u00E1\u0161 20 sekund. Projdi odpov\u011Bdi \u0161ipkami a svou volbu potvr\u010F Enterem. Potvrzenou odpov\u011B\u010F u\u017E nezm\u011Bn\u00ED\u0161 a ostatn\u00ED ji neuvid\u00ED, dokud neodpov\u011Bd\u00ED v\u0161ichni nebo nevypr\u0161\u00ED \u010Das.",
              "Ot\u00E1zku zopakuje T, zb\u00FDvaj\u00EDc\u00ED \u010Das p\u0159e\u010Dte Ctrl+Alt+T. P\u011Bt sekund p\u0159ed koncem zazn\u00ED varov\u00E1n\u00ED. Bez v\u010Dasn\u00E9 odpov\u011Bdi dostane\u0161 nulu.",
              "Po vypr\u0161en\u00ED \u010Dasu nebo odesl\u00E1n\u00ED v\u0161ech odpov\u011Bd\u00ED se dozv\u00EDte \u0159e\u0161en\u00ED a kdo z\u00EDskal bod. T\u0159et\u00ED ot\u00E1zkou kolo kon\u010D\u00ED. P\u0159ed dal\u0161\u00EDm kolem je p\u011Btisekundov\u00E1 p\u0159est\u00E1vka. Souhrn kola p\u0159ipomene V, celkov\u00E9 v\u00FDsledky p\u0159e\u010Dte S."),
            rule_section(:finish, "V\u00EDt\u011Bzstv\u00ED a rozst\u0159el",
              "Hraje se alespo\u0148 do 15 bod\u016F. I kdy\u017E n\u011Bkdo c\u00EDle dos\u00E1hne u\u017E prvn\u00ED ot\u00E1zkou kola, zodpov\u00EDte je\u0161t\u011B zb\u00FDvaj\u00EDc\u00ED ot\u00E1zky. Potom vyhr\u00E1v\u00E1 hr\u00E1\u010D s nejvy\u0161\u0161\u00EDm sou\u010Dtem.",
              "P\u0159i shod\u011B na prvn\u00EDm m\u00EDst\u011B p\u0159ijde dal\u0161\u00ED cel\u00E9 kolo t\u0159\u00ED ot\u00E1zek. Pokra\u010Dujete, dokud po dokon\u010Den\u00E9m kole nez\u016Fstane jedin\u00FD vedouc\u00ED hr\u00E1\u010D."),
            rule_section(:content, "Jazyk a sada ot\u00E1zek",
              "V nastaven\u00ED stolu vyber jazyk ot\u00E1zek a potom sadu, z n\u00ED\u017E chcete hr\u00E1t. Dostupn\u00E9 kategorie z\u00E1visej\u00ED na sad\u011B.",
              "Sady o knih\u00E1ch a jin\u00FDch p\u0159\u00EDb\u011Bz\u00EDch mohou prozrazovat d\u011Bj v\u010Detn\u011B konce."),
            rule_section(:options, "\u010Cas a bodov\u00FD c\u00EDl",
              "P\u0159ed hrou lze v nastaven\u00ED stolu zm\u011Bnit \u010Das na odpov\u011B\u010F i c\u00EDlov\u00FD po\u010Det bod\u016F. St\u00E1le se dohr\u00E1v\u00E1 cel\u00E9 rozehran\u00E9 kolo, i kdy\u017E n\u011Bkdo c\u00EDle dos\u00E1hne d\u0159\u00EDv."),
            rule_section(:reports, "Hl\u00E1\u0161en\u00ED chyb v ot\u00E1zk\u00E1ch",
              "Kdy\u017E si v\u0161imne\u0161 chyby, stiskni Ctrl+B pro ozna\u010Den\u00ED aktu\u00E1ln\u00ED ot\u00E1zky nebo Ctrl+Shift+B pro ozna\u010Den\u00ED p\u0159edchoz\u00ED. M\u016F\u017Ee\u0161 hned pokra\u010Dovat ve h\u0159e.",
              "Po odchodu od stolu se program zept\u00E1, zda chce\u0161 ozna\u010Den\u00E9 ot\u00E1zky nahl\u00E1sit. Vyber \u201EAno\u201C, u ka\u017Ed\u00E9 popi\u0161 probl\u00E9m a stiskni \u201EOdeslat\u201C. Ot\u00E1zka i odpov\u011Bdi se p\u0159ipoj\u00ED automaticky. Volba \u201ENe\u201C ozna\u010Den\u00ED zru\u0161\u00ED; na pozd\u011Bji se neukl\u00E1daj\u00ED.",
              "Formul\u00E1\u0159 hl\u00E1\u0161en\u00ED ukazuje tak\u00E9 odpov\u011B\u010F ozna\u010Denou v sad\u011B jako spr\u00E1vnou."),
            rule_section(:controls, "Kl\u00E1vesov\u00E9 zkratky",
              "\u0160ipky: vybrat kategorii nebo odpov\u011B\u010F.",
              "Enter: potvrdit volbu.",
              "T: p\u0159e\u010D\u00EDst ot\u00E1zku a odpov\u011Bdi.",
              "Ctrl+Alt+T: p\u0159e\u010D\u00EDst zb\u00FDvaj\u00EDc\u00ED \u010Das.",
              "V: p\u0159e\u010D\u00EDst souhrn kola.",
              "S: p\u0159e\u010D\u00EDst sk\u00F3re.",
              "Ctrl+B: ozna\u010Dit aktu\u00E1ln\u00ED ot\u00E1zku k nahl\u00E1\u0161en\u00ED.",
              "Ctrl+Shift+B: ozna\u010Dit p\u0159edchoz\u00ED ot\u00E1zku k nahl\u00E1\u0161en\u00ED.")
          ]
        when "en"
          [
            rule_section(:goal, "The aim",
              "Answer questions from your chosen subject. Each has four choices and one correct answer. A correct answer earns a point; a wrong one loses nothing, so it is worth trying even when unsure.",
              "Two to eight players, including bots, can play. Everyone answers the same question independently. Being the first to press Enter earns no extra points."),
            rule_section(:round, "Choosing and answering",
              "Each round, one player chooses from three randomly offered categories. When it is your choice, use the arrows and confirm with Enter. The round contains three questions from that category; the next player chooses in the next round.",
              "For each question, you have 20 seconds. Browse the four answers with the arrows and press Enter to submit one. You cannot change it afterwards, and your choice stays secret until everyone answers or time runs out.",
              "T repeats the question; Ctrl+Alt+T reads the remaining time. A warning sounds with five seconds left. Missing the deadline scores zero.",
              "When everyone has answered or the timer expires, the correct answer and point winners are announced. The third question ends the round, followed by a five-second break before the next one. V reads the round summary and S reads scores."),
            rule_section(:finish, "Winning",
              "The target is at least 15 points, but always finish the current three-question round before deciding the winner. The player with the highest total wins.",
              "If the lead is tied, play another three-question round. Keep going until one player has the highest score at the end of a round."),
            rule_section(:content, "Question language and pack",
              "Choose the question language, then a question pack in the table settings. The pack determines which categories are available.",
              "Packs about books and other stories may contain spoilers, including endings."),
            rule_section(:options, "Time and target",
              "The host can change answer time and the target score before play. The current round is still completed even if someone reaches the target sooner."),
            rule_section(:reports, "Reporting a question",
              "If you spot a mistake, press Ctrl+B to mark the current question or Ctrl+Shift+B to mark the previous one. You can keep playing straight away.",
              "When you leave the table, you will be asked whether you want to report the marked questions. Choose Yes, describe the problem with each question and press Send. The question and its answers are included automatically. Choosing No discards the marks; they are not saved for later.",
              "The report form also shows the answer marked as correct in the set."),
            rule_section(:controls, "Keyboard shortcuts",
              "Arrows: choose a category or answer.",
              "Enter: confirm your choice.",
              "T: read the question and choices.",
              "Ctrl+Alt+T: read answer time remaining.",
              "V: read the round summary.",
              "S: read scores.",
              "Ctrl+B: mark the current question for reporting.",
              "Ctrl+Shift+B: mark the previous question for reporting.")
          ]
        when "es"
          [
            rule_section(:goal, "Objetivo",
              "En Quiz respondes preguntas de un tema elegido. Cada pregunta ofrece cuatro respuestas y solo una es correcta. Acertar da un punto; fallar no resta, as\u00ED que merece la pena intentar responder aunque tengas dudas.",
              "Pueden jugar de dos a ocho personas, incluidos bots. Todos reciben la misma pregunta y responden por separado. No obtiene ventaja quien pulsa Enter antes."),
            rule_section(:round, "Elegir categor\u00EDa y responder",
              "Al empezar una ronda, una persona elige entre tres categor\u00EDas sorteadas. Si te toca, rec\u00F3rrelas con las flechas y confirma con Enter. Esa ronda tendr\u00E1 tres preguntas de la categor\u00EDa elegida. En la siguiente elige otra persona.",
              "Tienes 20 segundos por pregunta. Recorre las cuatro respuestas con las flechas y confirma una con Enter. Ya no podr\u00E1s cambiarla. Tu elecci\u00F3n permanece oculta hasta que todos contesten o termine el plazo.",
              "T repite la pregunta y Ctrl+Alt+T indica cu\u00E1nto tiempo queda. Oir\u00E1s un aviso a cinco segundos del final. No responder a tiempo da cero puntos.",
              "Cuando todos hayan respondido o se agote el tiempo, se anuncia la respuesta correcta y qui\u00E9n ha ganado un punto. La tercera pregunta cierra la ronda. Antes de la siguiente hay una pausa de cinco segundos. V consulta el resumen de la ronda y S las puntuaciones."),
            rule_section(:finish, "Victoria y empate",
              "La meta es al menos 15 puntos. Aunque alguien llegue tras la primera pregunta de una ronda, se juegan las preguntas restantes. Al final gana quien tenga m\u00E1s puntos.",
              "Si el primer puesto est\u00E1 empatado, se juega otra ronda de tres preguntas. Se contin\u00FAa hasta que, al terminar una ronda, una sola persona tenga la puntuaci\u00F3n m\u00E1s alta."),
            rule_section(:content, "Idioma y preguntas",
              "En los ajustes de la mesa elige primero el idioma de las preguntas y despu\u00E9s el conjunto con el que jugar. Las categor\u00EDas disponibles dependen de ese conjunto.",
              "Los conjuntos sobre libros y otras historias pueden revelar detalles de la trama, incluidos sus finales."),
            rule_section(:options, "Tiempo y meta de puntos",
              "Puedes cambiar el tiempo de respuesta y la meta de puntos en los ajustes de la mesa. Siempre se completa la ronda empezada, aunque alguien alcance antes la meta."),
            rule_section(:reports, "Avisar de un error en una pregunta",
              "Si encuentras un error, pulsa Ctrl+B para marcar la pregunta actual o Ctrl+Shift+B para marcar la anterior. Puedes seguir jugando sin detenerte.",
              "Al salir de la mesa, el programa te preguntar\u00E1 si quieres enviar las preguntas marcadas al autor. Elige \u00ABS\u00ED\u00BB, describe el problema de cada una y pulsa \u00ABEnviar\u00BB. La pregunta y sus respuestas se incluyen autom\u00E1ticamente. Si eliges \u00ABNo\u00BB, se descartan las marcas; no se guardan para m\u00E1s tarde.",
              "El formulario tambi\u00E9n muestra la respuesta que el conjunto considera correcta."),
            rule_section(:controls, "Teclas de referencia",
              "Flechas: elegir categor\u00EDa o respuesta.",
              "Enter: confirmar la elecci\u00F3n.",
              "T: leer la pregunta y las respuestas.",
              "Ctrl+Alt+T: consultar el tiempo restante.",
              "V: consultar el resumen de la ronda.",
              "S: consultar los resultados.",
              "Ctrl+B: marcar la pregunta actual para avisar de un error.",
              "Ctrl+Shift+B: marcar la pregunta anterior para avisar de un error.")
          ]
        when "pl"
          [
            rule_section(:goal, "Cel gry",
              "W Quizie odpowiadacie na pytania z wybranej dziedziny. Ka\u017Cde ma cztery odpowiedzi i tylko jedna jest poprawna. Za trafny wyb\u00F3r dostajesz punkt. B\u0142\u0119dna odpowied\u017A niczego nie odejmuje, wi\u0119c warto spr\u00F3bowa\u0107, nawet gdy nie jeste\u015B pewien.",
              "W tej grze mo\u017Ce uczestniczy\u0107 od dw\u00F3ch do o\u015Bmiu os\u00F3b, r\u00F3wnie\u017C z botami. Wszyscy dostaj\u0105 to samo pytanie i odpowiadaj\u0105 niezale\u017Cnie. Wynik nie zale\u017Cy od tego, kto pierwszy naci\u015Bnie Enter."),
            rule_section(:round, "Wyb\u00F3r kategorii i odpowiadanie",
              "Na pocz\u0105tku rundy jedna osoba wybiera kategori\u0119 spo\u015Br\u00F3d trzech wylosowanych propozycji. Gdy wyb\u00F3r kategorii nale\u017Cy do ciebie, wska\u017C j\u0105 strza\u0142kami i zatwierd\u017A Enterem. W tej rundzie odpowiecie na trzy pytania z wybranej kategorii. W nast\u0119pnej rundzie wybiera kolejna osoba.",
              "Przy ka\u017Cdym pytaniu masz 20 sekund na decyzj\u0119. Strza\u0142kami przejrzyj cztery odpowiedzi i zatwierd\u017A wybran\u0105 Enterem. Od tej chwili nie mo\u017Cesz jej zmieni\u0107. Twoja decyzja pozostaje ukryta, dop\u00F3ki wszyscy nie odpowiedz\u0105 albo nie sko\u0144czy si\u0119 czas.",
              "Je\u017Celi chcesz us\u0142ysze\u0107 pytanie ponownie, naci\u015Bnij T. Ctrl+Alt+T przypomina pozosta\u0142y czas. Na pi\u0119\u0107 sekund przed ko\u0144cem us\u0142yszysz sygna\u0142 ostrzegawczy. Nieudzielenie odpowiedzi w terminie daje zero punkt\u00F3w.",
              "Gdy wszyscy odpowiedz\u0105 albo up\u0142ynie czas, poznacie poprawn\u0105 odpowied\u017A i dowiecie si\u0119, kto zdoby\u0142 punkt. Po trzecim pytaniu ko\u0144czy si\u0119 runda. Przed kolejn\u0105 jest pi\u0119\u0107 sekund przerwy. Podsumowanie rundy sprawdzisz klawiszem V, a wyniki graczy klawiszem S."),
            rule_section(:finish, "Wygrana i remis",
              "Celem jest zdobycie co najmniej 15 punkt\u00F3w. Nawet je\u015Bli kto\u015B osi\u0105gnie ten wynik po pierwszym pytaniu rundy, i tak odpowiadacie na pozosta\u0142e pytania. Potem zwyci\u0119\u017Ca osoba z najwy\u017Csz\u0105 sum\u0105.",
              "Przy remisie na pierwszym miejscu rozgrywacie kolejn\u0105 rund\u0119 trzech pyta\u0144. Gracie dalej, a\u017C po zako\u0144czeniu rundy jedna osoba b\u0119dzie mia\u0142a wi\u0119cej punkt\u00F3w ni\u017C pozostali."),
            rule_section(:content, "J\u0119zyk i zestaw pyta\u0144",
              "W ustawieniach sto\u0142u wybierz j\u0119zyk pyta\u0144, a potem zestaw, z kt\u00F3rego chcecie gra\u0107. Od zestawu zale\u017C\u0105 dost\u0119pne kategorie.",
              "Zestawy dotycz\u0105ce ksi\u0105\u017Cek i innych historii mog\u0105 zawiera\u0107 pytania zdradzaj\u0105ce fabu\u0142\u0119, tak\u017Ce zako\u0144czenia."),
            rule_section(:options, "Czas odpowiedzi i cel punktowy",
              "W ustawieniach sto\u0142u mo\u017Cecie zmieni\u0107 czas na odpowied\u017A oraz liczb\u0119 punkt\u00F3w potrzebn\u0105 do wygranej. Nadal trzeba doko\u0144czy\u0107 rozpocz\u0119t\u0105 rund\u0119, nawet je\u015Bli kto\u015B wcze\u015Bniej zdob\u0119dzie wymagan\u0105 liczb\u0119 punkt\u00F3w."),
            rule_section(:reports, "Zg\u0142aszanie b\u0142\u0119d\u00F3w w pytaniach",
              "Je\u015Bli zauwa\u017Cysz b\u0142\u0105d, naci\u015Bnij Ctrl+B, aby oznaczy\u0107 bie\u017C\u0105ce pytanie, albo Ctrl+Shift+B, aby oznaczy\u0107 poprzednie. Mo\u017Cesz od razu gra\u0107 dalej.",
              "Po opuszczeniu sto\u0142u program zapyta, czy chcesz zg\u0142osi\u0107 oznaczone pytania. Wybierz \u201ETak\u201D, opisz problem przy ka\u017Cdym z nich i naci\u015Bnij \u201EWy\u015Blij\u201D. Pytanie i odpowiedzi zostan\u0105 do\u0142\u0105czone automatycznie. Wyb\u00F3r \u201ENie\u201D usuwa oznaczenia; nie s\u0105 zachowywane na p\u00F3\u017Aniej.",
              "Formularz zg\u0142oszenia pokazuje te\u017C poprawn\u0105 odpowied\u017A wed\u0142ug zestawu."),
            rule_section(:controls, "Skr\u00F3ty klawiszowe",
              "Strza\u0142ki: wybierz kategori\u0119 lub odpowied\u017A.",
              "Enter: zatwierd\u017A wyb\u00F3r.",
              "T: odczytaj pytanie i odpowiedzi.",
              "Ctrl+Alt+T: odczytaj pozosta\u0142y czas na odpowied\u017A.",
              "V: odczytaj podsumowanie rundy.",
              "S: odczytaj wyniki.",
              "Ctrl+B: oznacz bie\u017C\u0105ce pytanie do zg\u0142oszenia.",
              "Ctrl+Shift+B: oznacz poprzednie pytanie do zg\u0142oszenia.")
          ]
        when "ru"
          [
            rule_section(:goal, "\u0426\u0435\u043B\u044C \u0438\u0433\u0440\u044B",
              "\u0412 \u0432\u0438\u043A\u0442\u043E\u0440\u0438\u043D\u0435 \u0432\u044B \u043E\u0442\u0432\u0435\u0447\u0430\u0435\u0442\u0435 \u043D\u0430 \u0432\u043E\u043F\u0440\u043E\u0441\u044B \u043F\u043E \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u043E\u0439 \u0442\u0435\u043C\u0435. \u0423 \u043A\u0430\u0436\u0434\u043E\u0433\u043E \u0432\u043E\u043F\u0440\u043E\u0441\u0430 \u0447\u0435\u0442\u044B\u0440\u0435 \u0432\u0430\u0440\u0438\u0430\u043D\u0442\u0430 \u043E\u0442\u0432\u0435\u0442\u0430, \u0438\u0437 \u043A\u043E\u0442\u043E\u0440\u044B\u0445 \u0432\u0435\u0440\u0435\u043D \u0442\u043E\u043B\u044C\u043A\u043E \u043E\u0434\u0438\u043D. \u0417\u0430 \u043F\u0440\u0430\u0432\u0438\u043B\u044C\u043D\u044B\u0439 \u043E\u0442\u0432\u0435\u0442 \u043D\u0430\u0447\u0438\u0441\u043B\u044F\u0435\u0442\u0441\u044F \u043E\u0447\u043A\u043E, \u0437\u0430 \u043E\u0448\u0438\u0431\u043A\u0443 \u043D\u0438\u0447\u0435\u0433\u043E \u043D\u0435 \u0441\u043D\u0438\u043C\u0430\u044E\u0442. \u041F\u043E\u044D\u0442\u043E\u043C\u0443 \u0438\u043C\u0435\u0435\u0442 \u0441\u043C\u044B\u0441\u043B \u043F\u043E\u043F\u0440\u043E\u0431\u043E\u0432\u0430\u0442\u044C, \u0434\u0430\u0436\u0435 \u0435\u0441\u043B\u0438 \u0432\u044B \u043D\u0435 \u0443\u0432\u0435\u0440\u0435\u043D\u044B.",
              "\u0423\u0447\u0430\u0441\u0442\u0432\u0443\u044E\u0442 \u043E\u0442 \u0434\u0432\u0443\u0445 \u0434\u043E \u0432\u043E\u0441\u044C\u043C\u0438 \u0438\u0433\u0440\u043E\u043A\u043E\u0432, \u0432 \u0442\u043E\u043C \u0447\u0438\u0441\u043B\u0435 \u0431\u043E\u0442\u044B. \u0412\u043E\u043F\u0440\u043E\u0441 \u0434\u043B\u044F \u0432\u0441\u0435\u0445 \u043E\u0434\u0438\u043D, \u043D\u043E \u043A\u0430\u0436\u0434\u044B\u0439 \u0432\u044B\u0431\u0438\u0440\u0430\u0435\u0442 \u043E\u0442\u0432\u0435\u0442 \u0441\u0430\u043C\u043E\u0441\u0442\u043E\u044F\u0442\u0435\u043B\u044C\u043D\u043E. \u041D\u0435\u0432\u0430\u0436\u043D\u043E, \u043A\u0442\u043E \u0440\u0430\u043D\u044C\u0448\u0435 \u043D\u0430\u0436\u0430\u043B Enter: \u0441\u043A\u043E\u0440\u043E\u0441\u0442\u044C \u043E\u0442\u0432\u0435\u0442\u0430 \u043D\u0430 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442 \u043D\u0435 \u0432\u043B\u0438\u044F\u0435\u0442."),
            rule_section(:round, "\u0412\u044B\u0431\u043E\u0440 \u0442\u0435\u043C\u044B \u0438 \u043E\u0442\u0432\u0435\u0442\u044B",
              "\u0412 \u043D\u0430\u0447\u0430\u043B\u0435 \u0440\u0430\u0443\u043D\u0434\u0430 \u043E\u0434\u0438\u043D \u0438\u0433\u0440\u043E\u043A \u0432\u044B\u0431\u0438\u0440\u0430\u0435\u0442 \u0442\u0435\u043C\u0443 \u0438\u0437 \u0442\u0440\u0451\u0445 \u0441\u043B\u0443\u0447\u0430\u0439\u043D\u043E \u043F\u0440\u0435\u0434\u043B\u043E\u0436\u0435\u043D\u043D\u044B\u0445. \u041A\u043E\u0433\u0434\u0430 \u0432\u044B\u0431\u0438\u0440\u0430\u0435\u0442\u0435 \u0432\u044B, \u043D\u0430\u0439\u0434\u0438\u0442\u0435 \u0442\u0435\u043C\u0443 \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0438 \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u0435 Enter. \u0412 \u044D\u0442\u043E\u043C \u0440\u0430\u0443\u043D\u0434\u0435 \u0431\u0443\u0434\u0443\u0442 \u0442\u0440\u0438 \u0432\u043E\u043F\u0440\u043E\u0441\u0430 \u043D\u0430 \u044D\u0442\u0443 \u0442\u0435\u043C\u0443. \u0412 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0435\u043C \u0440\u0430\u0443\u043D\u0434\u0435 \u043F\u0440\u0430\u0432\u043E \u0432\u044B\u0431\u043E\u0440\u0430 \u043F\u0435\u0440\u0435\u0439\u0434\u0451\u0442 \u0434\u0430\u043B\u044C\u0448\u0435 \u043F\u043E \u043E\u0447\u0435\u0440\u0435\u0434\u0438.",
              "\u041D\u0430 \u043A\u0430\u0436\u0434\u044B\u0439 \u0432\u043E\u043F\u0440\u043E\u0441 \u0434\u0430\u0451\u0442\u0441\u044F 20 \u0441\u0435\u043A\u0443\u043D\u0434. \u041F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0438\u0442\u0435 \u0447\u0435\u0442\u044B\u0440\u0435 \u043E\u0442\u0432\u0435\u0442\u0430 \u0441\u0442\u0440\u0435\u043B\u043A\u0430\u043C\u0438 \u0438 \u043D\u0430\u0436\u043C\u0438\u0442\u0435 Enter \u043D\u0430 \u0432\u044B\u0431\u0440\u0430\u043D\u043D\u043E\u043C. \u041F\u043E\u0441\u043B\u0435 \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0435\u043D\u0438\u044F \u0438\u0437\u043C\u0435\u043D\u0438\u0442\u044C \u0435\u0433\u043E \u043D\u0435\u043B\u044C\u0437\u044F. \u0412\u0430\u0448 \u0432\u044B\u0431\u043E\u0440 \u0441\u043A\u0440\u044B\u0442, \u043F\u043E\u043A\u0430 \u043D\u0435 \u043E\u0442\u0432\u0435\u0442\u044F\u0442 \u0432\u0441\u0435 \u0438\u043B\u0438 \u043D\u0435 \u0438\u0441\u0442\u0435\u0447\u0451\u0442 \u0432\u0440\u0435\u043C\u044F.",
              "\u041A\u043B\u0430\u0432\u0438\u0448\u0430 T \u043F\u043E\u0432\u0442\u043E\u0440\u044F\u0435\u0442 \u0432\u043E\u043F\u0440\u043E\u0441, \u0430 Ctrl+Alt+T \u0441\u043E\u043E\u0431\u0449\u0430\u0435\u0442 \u043E\u0441\u0442\u0430\u0432\u0448\u0435\u0435\u0441\u044F \u0432\u0440\u0435\u043C\u044F. \u0417\u0430 \u043F\u044F\u0442\u044C \u0441\u0435\u043A\u0443\u043D\u0434 \u0434\u043E \u043A\u043E\u043D\u0446\u0430 \u043F\u0440\u043E\u0437\u0432\u0443\u0447\u0438\u0442 \u043F\u0440\u0435\u0434\u0443\u043F\u0440\u0435\u0436\u0434\u0435\u043D\u0438\u0435. \u0415\u0441\u043B\u0438 \u043D\u0435 \u0443\u0441\u043F\u0435\u0442\u044C \u043E\u0442\u0432\u0435\u0442\u0438\u0442\u044C, \u0437\u0430 \u0432\u043E\u043F\u0440\u043E\u0441 \u0431\u0443\u0434\u0435\u0442 \u043D\u043E\u043B\u044C \u043E\u0447\u043A\u043E\u0432.",
              "\u041A\u043E\u0433\u0434\u0430 \u043E\u0442\u0432\u0435\u0442\u044B \u0441\u043E\u0431\u0440\u0430\u043D\u044B \u0438\u043B\u0438 \u0432\u0440\u0435\u043C\u044F \u0437\u0430\u043A\u043E\u043D\u0447\u0438\u043B\u043E\u0441\u044C, \u0438\u0433\u0440\u0430 \u043E\u0431\u044A\u044F\u0432\u043B\u044F\u0435\u0442 \u0432\u0435\u0440\u043D\u044B\u0439 \u043E\u0442\u0432\u0435\u0442 \u0438 \u0438\u043C\u0435\u043D\u0430 \u043F\u043E\u043B\u0443\u0447\u0438\u0432\u0448\u0438\u0445 \u043E\u0447\u043A\u043E. \u0422\u0440\u0435\u0442\u0438\u0439 \u0432\u043E\u043F\u0440\u043E\u0441 \u0437\u0430\u0432\u0435\u0440\u0448\u0430\u0435\u0442 \u0440\u0430\u0443\u043D\u0434. \u041F\u0435\u0440\u0435\u0434 \u0441\u043B\u0435\u0434\u0443\u044E\u0449\u0438\u043C \u0440\u0430\u0443\u043D\u0434\u043E\u043C \u0435\u0441\u0442\u044C \u043F\u044F\u0442\u0438\u0441\u0435\u043A\u0443\u043D\u0434\u043D\u0430\u044F \u043F\u0430\u0443\u0437\u0430. \u041A\u043B\u0430\u0432\u0438\u0448\u0430 V \u043F\u043E\u0432\u0442\u043E\u0440\u044F\u0435\u0442 \u0438\u0442\u043E\u0433\u0438 \u0440\u0430\u0443\u043D\u0434\u0430, \u0430 S \u0441\u043E\u043E\u0431\u0449\u0430\u0435\u0442 \u043E\u0431\u0449\u0438\u0439 \u0441\u0447\u0451\u0442."),
            rule_section(:finish, "\u041F\u043E\u0431\u0435\u0434\u0430 \u0438 \u0434\u043E\u043F\u043E\u043B\u043D\u0438\u0442\u0435\u043B\u044C\u043D\u044B\u0439 \u0440\u0430\u0443\u043D\u0434",
              "\u0414\u043B\u044F \u043F\u043E\u0431\u0435\u0434\u044B \u043D\u0443\u0436\u043D\u043E \u043D\u0430\u0431\u0440\u0430\u0442\u044C \u0445\u043E\u0442\u044F \u0431\u044B 15 \u043E\u0447\u043A\u043E\u0432. \u041D\u0430\u0447\u0430\u0442\u044B\u0439 \u0440\u0430\u0443\u043D\u0434 \u0432\u0441\u0435\u0433\u0434\u0430 \u0434\u043E\u0438\u0433\u0440\u044B\u0432\u0430\u0435\u0442\u0441\u044F: \u0434\u0430\u0436\u0435 \u0435\u0441\u043B\u0438 \u043A\u0442\u043E-\u0442\u043E \u0434\u043E\u0441\u0442\u0438\u0433 \u0446\u0435\u043B\u0438 \u043D\u0430 \u043F\u0435\u0440\u0432\u043E\u043C \u0432\u043E\u043F\u0440\u043E\u0441\u0435, \u043E\u0441\u0442\u0430\u044E\u0442\u0441\u044F \u0435\u0449\u0451 \u0434\u0432\u0430. \u0417\u0430\u0442\u0435\u043C \u043F\u043E\u0431\u0435\u0436\u0434\u0430\u0435\u0442 \u0438\u0433\u0440\u043E\u043A \u0441 \u043D\u0430\u0438\u0431\u043E\u043B\u044C\u0448\u0438\u043C \u043E\u0431\u0449\u0438\u043C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u043E\u043C.",
              "\u0415\u0441\u043B\u0438 \u043F\u0435\u0440\u0432\u043E\u0435 \u043C\u0435\u0441\u0442\u043E \u0434\u0435\u043B\u044F\u0442 \u043D\u0435\u0441\u043A\u043E\u043B\u044C\u043A\u043E \u0438\u0433\u0440\u043E\u043A\u043E\u0432, \u043F\u0440\u043E\u0432\u043E\u0434\u0438\u0442\u0441\u044F \u0435\u0449\u0451 \u043E\u0434\u0438\u043D \u0440\u0430\u0443\u043D\u0434 \u0438\u0437 \u0442\u0440\u0451\u0445 \u0432\u043E\u043F\u0440\u043E\u0441\u043E\u0432. \u0422\u0430\u043A \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0430\u0435\u0442\u0441\u044F, \u043F\u043E\u043A\u0430 \u043F\u043E \u0438\u0442\u043E\u0433\u0430\u043C \u0440\u0430\u0443\u043D\u0434\u0430 \u043D\u0435 \u043E\u043F\u0440\u0435\u0434\u0435\u043B\u0438\u0442\u0441\u044F \u0435\u0434\u0438\u043D\u0441\u0442\u0432\u0435\u043D\u043D\u044B\u0439 \u043B\u0438\u0434\u0435\u0440."),
            rule_section(:content, "\u042F\u0437\u044B\u043A \u0438 \u043D\u0430\u0431\u043E\u0440 \u0432\u043E\u043F\u0440\u043E\u0441\u043E\u0432",
              "\u0412 \u043D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0430\u0445 \u0441\u0442\u043E\u043B\u0430 \u0441\u043D\u0430\u0447\u0430\u043B\u0430 \u0432\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u044F\u0437\u044B\u043A \u0432\u043E\u043F\u0440\u043E\u0441\u043E\u0432, \u0437\u0430\u0442\u0435\u043C \u043D\u0430\u0431\u043E\u0440. \u041E\u0442 \u043D\u0430\u0431\u043E\u0440\u0430 \u0437\u0430\u0432\u0438\u0441\u0438\u0442, \u043A\u0430\u043A\u0438\u0435 \u0442\u0435\u043C\u044B \u0434\u043E\u0441\u0442\u0443\u043F\u043D\u044B \u0434\u043B\u044F \u0438\u0433\u0440\u044B.",
              "\u0412\u043E\u043F\u0440\u043E\u0441\u044B \u043E \u043A\u043D\u0438\u0433\u0430\u0445 \u0438 \u0434\u0440\u0443\u0433\u0438\u0445 \u0438\u0441\u0442\u043E\u0440\u0438\u044F\u0445 \u043C\u043E\u0433\u0443\u0442 \u0440\u0430\u0441\u043A\u0440\u044B\u0432\u0430\u0442\u044C \u0441\u044E\u0436\u0435\u0442, \u0432 \u0442\u043E\u043C \u0447\u0438\u0441\u043B\u0435 \u043A\u043E\u043D\u0446\u043E\u0432\u043A\u0443."),
            rule_section(:options, "\u0412\u0440\u0435\u043C\u044F \u0438 \u0446\u0435\u043B\u044C \u043F\u043E \u043E\u0447\u043A\u0430\u043C",
              "\u0412 \u043D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0430\u0445 \u0441\u0442\u043E\u043B\u0430 \u043C\u043E\u0436\u043D\u043E \u0438\u0437\u043C\u0435\u043D\u0438\u0442\u044C \u0432\u0440\u0435\u043C\u044F \u043D\u0430 \u043E\u0442\u0432\u0435\u0442 \u0438 \u0447\u0438\u0441\u043B\u043E \u043E\u0447\u043A\u043E\u0432 \u0434\u043B\u044F \u043F\u043E\u0431\u0435\u0434\u044B. \u041F\u0440\u0438 \u043B\u044E\u0431\u043E\u0439 \u0446\u0435\u043B\u0438 \u043D\u0430\u0447\u0430\u0442\u044B\u0439 \u0440\u0430\u0443\u043D\u0434 \u0434\u043E\u0438\u0433\u0440\u044B\u0432\u0430\u0435\u0442\u0441\u044F \u043F\u043E\u043B\u043D\u043E\u0441\u0442\u044C\u044E, \u0434\u0430\u0436\u0435 \u0435\u0441\u043B\u0438 \u043D\u0443\u0436\u043D\u044B\u0435 \u043E\u0447\u043A\u0438 \u0443\u0436\u0435 \u043D\u0430\u0431\u0440\u0430\u043D\u044B."),
            rule_section(:reports, "\u0421\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u044F \u043E\u0431 \u043E\u0448\u0438\u0431\u043A\u0430\u0445 \u0432 \u0432\u043E\u043F\u0440\u043E\u0441\u0430\u0445",
              "\u0415\u0441\u043B\u0438 \u0432\u044B \u0437\u0430\u043C\u0435\u0442\u0438\u043B\u0438 \u043E\u0448\u0438\u0431\u043A\u0443, \u043D\u0430\u0436\u043C\u0438\u0442\u0435 Ctrl+B, \u0447\u0442\u043E\u0431\u044B \u043E\u0442\u043C\u0435\u0442\u0438\u0442\u044C \u0442\u0435\u043A\u0443\u0449\u0438\u0439 \u0432\u043E\u043F\u0440\u043E\u0441, \u0438\u043B\u0438 Ctrl+Shift+B, \u0447\u0442\u043E\u0431\u044B \u043E\u0442\u043C\u0435\u0442\u0438\u0442\u044C \u043F\u0440\u0435\u0434\u044B\u0434\u0443\u0449\u0438\u0439. \u041F\u043E\u0441\u043B\u0435 \u044D\u0442\u043E\u0433\u043E \u043C\u043E\u0436\u043D\u043E \u0441\u0440\u0430\u0437\u0443 \u043F\u0440\u043E\u0434\u043E\u043B\u0436\u0430\u0442\u044C \u0438\u0433\u0440\u0443.",
              "\u041F\u0440\u0438 \u0432\u044B\u0445\u043E\u0434\u0435 \u0438\u0437-\u0437\u0430 \u0441\u0442\u043E\u043B\u0430 \u043F\u0440\u043E\u0433\u0440\u0430\u043C\u043C\u0430 \u043F\u0440\u0435\u0434\u043B\u043E\u0436\u0438\u0442 \u0441\u043E\u043E\u0431\u0449\u0438\u0442\u044C \u043E\u0431 \u043E\u0442\u043C\u0435\u0447\u0435\u043D\u043D\u044B\u0445 \u0432\u043E\u043F\u0440\u043E\u0441\u0430\u0445. \u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u00AB\u0414\u0430\u00BB, \u043E\u043F\u0438\u0448\u0438\u0442\u0435 \u043F\u0440\u043E\u0431\u043B\u0435\u043C\u0443 \u0441 \u043A\u0430\u0436\u0434\u044B\u043C \u0432\u043E\u043F\u0440\u043E\u0441\u043E\u043C \u0438 \u043D\u0430\u0436\u043C\u0438\u0442\u0435 \u00AB\u041E\u0442\u043F\u0440\u0430\u0432\u0438\u0442\u044C\u00BB. \u0412\u043E\u043F\u0440\u043E\u0441 \u0438 \u0432\u0430\u0440\u0438\u0430\u043D\u0442\u044B \u043E\u0442\u0432\u0435\u0442\u0430 \u0431\u0443\u0434\u0443\u0442 \u0434\u043E\u0431\u0430\u0432\u043B\u0435\u043D\u044B \u0430\u0432\u0442\u043E\u043C\u0430\u0442\u0438\u0447\u0435\u0441\u043A\u0438. \u0415\u0441\u043B\u0438 \u0432\u044B\u0431\u0440\u0430\u0442\u044C \u00AB\u041D\u0435\u0442\u00BB, \u043E\u0442\u043C\u0435\u0442\u043A\u0438 \u0431\u0443\u0434\u0443\u0442 \u0443\u0434\u0430\u043B\u0435\u043D\u044B: \u043D\u0430 \u043F\u043E\u0442\u043E\u043C \u043E\u043D\u0438 \u043D\u0435 \u0441\u043E\u0445\u0440\u0430\u043D\u044F\u044E\u0442\u0441\u044F.",
              "\u0412 \u0444\u043E\u0440\u043C\u0435 \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u044F \u0442\u0430\u043A\u0436\u0435 \u043F\u043E\u043A\u0430\u0437\u0430\u043D \u043E\u0442\u0432\u0435\u0442, \u043E\u0442\u043C\u0435\u0447\u0435\u043D\u043D\u044B\u0439 \u0432 \u043D\u0430\u0431\u043E\u0440\u0435 \u043A\u0430\u043A \u043F\u0440\u0430\u0432\u0438\u043B\u044C\u043D\u044B\u0439."),
            rule_section(:controls, "\u041A\u043B\u0430\u0432\u0438\u0448\u0438 \u0443\u043F\u0440\u0430\u0432\u043B\u0435\u043D\u0438\u044F",
              "\u0421\u0442\u0440\u0435\u043B\u043A\u0438: \u0432\u044B\u0431\u0440\u0430\u0442\u044C \u0442\u0435\u043C\u0443 \u0438\u043B\u0438 \u043E\u0442\u0432\u0435\u0442.",
              "Enter: \u043F\u043E\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u044C \u0432\u044B\u0431\u043E\u0440.",
              "T: \u043F\u043E\u0432\u0442\u043E\u0440\u0438\u0442\u044C \u0432\u043E\u043F\u0440\u043E\u0441 \u0438 \u0432\u0430\u0440\u0438\u0430\u043D\u0442\u044B \u043E\u0442\u0432\u0435\u0442\u0430.",
              "Ctrl+Alt+T: \u0443\u0437\u043D\u0430\u0442\u044C \u043E\u0441\u0442\u0430\u0432\u0448\u0435\u0435\u0441\u044F \u0432\u0440\u0435\u043C\u044F \u043D\u0430 \u043E\u0442\u0432\u0435\u0442.",
              "V: \u0443\u0437\u043D\u0430\u0442\u044C \u0438\u0442\u043E\u0433\u0438 \u0440\u0430\u0443\u043D\u0434\u0430.",
              "S: \u0443\u0437\u043D\u0430\u0442\u044C \u0441\u0447\u0451\u0442.",
              "Ctrl+B: \u043E\u0442\u043C\u0435\u0442\u0438\u0442\u044C \u0442\u0435\u043A\u0443\u0449\u0438\u0439 \u0432\u043E\u043F\u0440\u043E\u0441 \u0434\u043B\u044F \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u044F \u043E\u0431 \u043E\u0448\u0438\u0431\u043A\u0435.",
              "Ctrl+Shift+B: \u043E\u0442\u043C\u0435\u0442\u0438\u0442\u044C \u043F\u0440\u0435\u0434\u044B\u0434\u0443\u0449\u0438\u0439 \u0432\u043E\u043F\u0440\u043E\u0441 \u0434\u043B\u044F \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u044F \u043E\u0431 \u043E\u0448\u0438\u0431\u043A\u0435.")
          ]
        end
      end
    end
    include GeneratedRulebook
  end
end
