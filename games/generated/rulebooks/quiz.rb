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
            GameRoomRules.translate("A round consists of three questions. At its start, the game draws three available categories and one participant chooses which will be used for all three questions. The right to choose moves between players in successive rounds. Category choices include their question counts so you can see how much material they contain."),
            GameRoomRules.translate("After everyone answers or time expires, the game reveals the answers and awards points, then prepares the next question. Preparing a question is not another answer choice: wait for the new question to appear. Once all three have been settled, the round summary is available and the next category selection begins unless the match has ended.")),
          rule_section(:sets, GameRoomRules.translate("Choose the content, not the interface language"),
            GameRoomRules.translate("When creating or configuring the table, first choose a question language and then a set offered in that language. The set label gives the number of questions supplied. This choice does not change anyone's interface: a Polish interface can still display questions from an English or Italian set. The language and set are shared by the whole table."),
            GameRoomRules.translate("The Polish Witcher \u2014 books set contains questions about Andrzej Sapkowski's stories and novels, not games or screen adaptations. It covers the whole plot, including endings. Questions from Droga, z kt\u00F3rej si\u0119 nie wraca and the alternative Co\u015B si\u0119 ko\u0144czy, co\u015B si\u0119 zaczyna always name the story.")),
          rule_section(:time, GameRoomRules.translate("Answer time and the finishing line"),
            GameRoomRules.translate("Time for one answer defaults to 20 seconds. The offered choices are 5\u201310 seconds one second apart, then 15\u201360 in steps of five. This limit applies separately to each question. The target defaults to 15 points; the list also offers 20, 25, 30, 40 and 50."),
            GameRoomRules.translate("Reaching the target does not cut short a round. Finish all three questions, then the highest score wins. If the highest scores are equal, play another complete round and check again, continuing until one player leads. Bots sometimes know an answer and otherwise guess; adding one does not make every answer perfect. Saving a partly played Quiz Party match is not supported.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: choose a category or answer."),
            GameRoomRules.translate("Enter: submit the highlighted choice."),
            GameRoomRules.translate("T: read the question."),
            GameRoomRules.translate("Ctrl+T: read the remaining answer time."),
            GameRoomRules.translate("V: read the round summary."),
            GameRoomRules.translate("S: read scores."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
