# Generated from tools/data/rulebooks/mille_bornes.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class MilleBornes
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:race, GameRoomRules.translate("The race to exactly 1000 miles"),
            GameRoomRules.translate("Travel exactly 1000 miles before your opponents. Distance cards cover 25, 50, 75, 100 or 200 miles. You cannot pass the finish line. Each player or team may play at most two 200-mile cards in a round."),
            GameRoomRules.translate("Everyone starts stopped with six cards. On your turn, draw a card, then play or discard one. You may discard even when a legal play is available. Nobody may take a discarded card. With an empty draw pile, continue with your remaining cards. The round ends immediately when somebody reaches 1000 miles or any player has no cards left.")),
          rule_section(:hazards, GameRoomRules.translate("Hazards and remedies"),
            GameRoomRules.translate("Play a green light to start driving. A red light stops an opponent. Out of gas requires fuel, a flat tire requires a spare tire, and an accident requires repairs. After these three remedies, you also need a green light before driving again."),
            GameRoomRules.translate("A speed limit allows only 25- and 50-mile cards until an end of speed limit is played. A speed limit can also affect a stopped car. Without attack accumulation, you cannot impose another main hazard on an already stopped opponent. You cannot attack your own team.")),
          rule_section(:safeties, GameRoomRules.translate("Permanent protection"),
            GameRoomRules.translate("An extra tank protects against running out of gas, puncture-proof tires protect against flat tires, and the driving ace protects against accidents and counterflow. Right of way protects against red lights and speed limits and removes the need for green lights. A safety removes the corresponding current problem and protects you until the round ends."),
            GameRoomRules.translate("Playing a safety earns 100 points and gives you another turn. Teammates share protection but keep separate hands.")),
          rule_section(:dirty_tricks, GameRoomRules.translate("Dirty tricks"),
            GameRoomRules.translate("Immediately after an attack, play the matching safety from your hand, even outside your normal turn. This opportunity ends when the next player draws or plays. Moving the cursor or opening information does not end it."),
            GameRoomRules.translate("A dirty trick cancels the attack and preserves the previous driving state. It earns 300 bonus points in addition to the safety's 100 points. Draw a replacement card if one is available, then take an extra turn with its normal draw. Play continues with the player after you; intervening players are skipped. A safety played later gives ordinary protection without this bonus."),
            GameRoomRules.translate("With the bot move delay set to 0, the next bot may draw immediately after the attack is presented, before you can react. Set a nonzero bot move delay for more comfortable dirty tricks. No reaction time is guaranteed: the opportunity still ends when the next player draws or plays.")),
          rule_section(:scoring, GameRoomRules.translate("Mileage and victory bonuses"),
            GameRoomRules.translate("Your current mileage contributes to your score. Normally, distance cards add miles; under counterflow, they subtract miles without going below zero. Each safety scores 100 points; a dirty trick adds 300. Reaching exactly 1000 miles earns a 300-point victory bonus. Reaching the finish with an empty draw pile adds another 300 points."),
            GameRoomRules.translate("The round winner earns another 500 points if every opponent or opposing team still has zero miles, and another 300 points if the winning side has played all four safeties. No victory bonuses are awarded when a hand becomes empty. Scores carry over between rounds.")),
          rule_section(:teams, GameRoomRules.translate("Individual and team races"),
            GameRoomRules.translate("Teammates share mileage, hazards, protection and points. Each player keeps a separate hand and takes a separate turn. Four players may form two pairs. Six may form two teams of three or three pairs. Eight may form two teams of four or four pairs. Nine may form three teams of three.")),
          rule_section(:variants, GameRoomRules.translate("Optional rules"),
            GameRoomRules.translate("Attack accumulation allows several different problems at once, including attacks on an already stopped car. Resolve every blocking problem before driving. An identical active problem cannot be added twice."),
            GameRoomRules.translate("Discard recycling refills an exhausted draw pile by shuffling discarded cards. Cards in hands or already played on the track are not recycled."),
            GameRoomRules.translate("Add safety cards is on by default: the standard deck contains 106 cards, including the four safeties. Turning it off removes those four cards, leaving 102 cards without permanent protection or dirty tricks. Optional counterflow cards are added separately. Existing games without this setting still include safeties."),
            GameRoomRules.translate("Counterflow is optional and off by default. Add counterflow cards normally adds 4 counterflow attacks and 6 end of counterflow cards, matching the standard speed-limit and end-of-speed-limit counts. These are approved local defaults, not verified QuentinC Playroom deck counts. Existing games retain their explicitly saved counts. Custom deck lets you change both counts separately."),
            GameRoomRules.translate("A counterflow attack can affect an opponent even while stopped. It is independent of speed limits and mechanical hazards and does not require attack accumulation. An already active counterflow cannot be added twice. Driving ace prevents this attack, removes an active counterflow and can be played immediately as a dirty trick against it."),
            GameRoomRules.translate("Under counterflow, each otherwise legal 25-, 50-, 75-, 100- or 200-mile card subtracts its distance instead of adding it. Mileage cannot fall below zero: 100 miles minus a 200-mile card becomes 0, and playing a distance card at 0 leaves it at 0. You must still be able to drive: green-light requirements, blocking hazards, speed limits and the maximum of two 200-mile cards per round still apply, including when those cards subtract miles."),
            GameRoomRules.translate("End of counterflow removes only the counterflow effect. It does not remove a speed limit, a red light or a mechanical hazard, and does not itself require an extra green light. Any green light or remedy still required for another reason remains necessary.")),
          rule_section(:instant_repair, GameRoomRules.translate("Instant repair"),
            GameRoomRules.translate("Add instant repair cards is optional and off by default. When enabled, it adds two instant repair cards to the standard deck. Custom deck lets you change their count; the switch still decides whether they are included."),
            GameRoomRules.translate("After drawing on your normal turn, play an instant repair on your own car or team and choose exactly one problem to remove: a red light, no initial green light, out of gas, a flat tire, an accident, a speed limit or counterflow. One card resolves only the selected problem, even when several problems have accumulated."),
            GameRoomRules.translate("Removing a red light or the lack of an initial green light allows driving only if no other problem blocks it. Repairing a fuel, tire or accident problem still requires a green light unless you have Right of way. Other problems remain unchanged. Instant repair is not a safety or an immediate response to an attack: it grants no immunity, extra turn, or 100- or 300-point bonus.")),
          rule_section(:custom_deck, GameRoomRules.translate("Custom deck"),
            GameRoomRules.translate("Custom deck allows a separate count for every card type: all five distances, every remedy and hazard, each safety, counterflow, end of counterflow and instant repair. Choose an integer from 0 to 100 for each type. Add safety cards, Add counterflow cards and Add instant repair cards still control inclusion: a disabled group stays out of the deck even if its saved counts are positive. The limit of two 200-mile cards per player or team per round does not change."),
            GameRoomRules.translate("The included cards must provide at least six cards per player for the initial deal and allow some points to be scored: include a safety, or distance cards together with a green light, Right of way or instant repair. This does not guarantee that 1000 miles can be reached. Invalid custom decks cannot start. Changing table settings does not rewrite an existing game's deck or replay. Custom deck is off by default; turning it off restores standard counts for new games.")),
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: browse your hand or card choices."),
            GameRoomRules.translate("Enter: play the selected card or confirm the chosen opponent. After drawing, an unplayable card opens a discard confirmation; No or Escape leaves it in your hand without making a move."),
            GameRoomRules.translate("Escape: cancel the current card or opponent choice."),
            GameRoomRules.translate("Space: draw a card."),
            GameRoomRules.translate("J: ask to discard the selected hand card after drawing, even if it is playable. No or Escape cancels without making a move."),
            GameRoomRules.translate("Delete: choose a card to discard."),
            GameRoomRules.translate("H: read your hand."),
            GameRoomRules.translate("I: read your mileage, hazards and safeties."),
            GameRoomRules.translate("Shift+I: read every car's mileage, hazards and safeties."),
            GameRoomRules.translate("S: read scores."),
            GameRoomRules.translate("T: read whose turn it is."),
            GameRoomRules.translate("Z: find the next playable card on your turn, outside the dirty-trick window."),
            GameRoomRules.translate("Shift+Z: find the previous playable card on your turn, outside the dirty-trick window."),
            GameRoomRules.translate("Shift+C: sort by card type; press again to reverse the order."),
            GameRoomRules.translate("Shift+H: sort by distance or card value; press again to reverse the order."),
            GameRoomRules.translate("Shift+M: restore the order in which cards were received."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
