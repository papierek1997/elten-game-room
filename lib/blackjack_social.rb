module GameRoomGames
  module BlackjackSocial
    using GameRoomLocalization::Translations
    private
    def social?(state); state[:options]["variant"] == "social"; end

    def social_deal(state,seed,event_id,history)
      dealer = state[:dealing_player]
      state[:round] += 1
      state[:deck] = shuffled_cards(standard_deck,seed)
      state[:dealer] = []
      order = state[:players].rotate(state[:players].index(dealer)+1) & auction_contenders(state)
      state[:hands] = order.to_h do |player|
        cards = [state[:deck].shift,state[:deck].shift]
        [player,[{cards:cards,bet:state[:auction][:contributions][player],split:false,done:hand_total(cards)==21}]]
      end
      state.merge!(phase: :playing,current_player:order.first,hand_index:0)
      add_history(history,event_id,dealer,:deal,_("Round %{round}. %{player} deals the cards.") % {round:state[:round],player:participant_name(dealer)})
      announce_dealt_hands(state, event_id, history)
      advance_hand(state)
    end

    def social_settle(state,event_id,history,uncontested: false)
      returns = Hash.new(0)
      auction_pots(state).each do |pot|
        eligible = uncontested ? pot[:eligible] : pot[:eligible].select { |p| hand_total(state[:hands].fetch(p).first[:cards]) <= 21 }
        if eligible.empty?
          pot[:contributors].each { |p| returns[p] += pot[:slice] }
          next
        end
        best = eligible.map { |p| hand_total(state[:hands][p].first[:cards]) }.max unless uncontested
        winners = uncontested ? eligible : eligible.select { |p| hand_total(state[:hands][p].first[:cards]) == best }
        share,odd = pot[:amount].divmod(winners.size)
        winners.each_with_index { |p,i| returns[p] += share + (i < odd ? 1 : 0) }
      end
      returns.each { |player, amount| state[:chips][player] += amount }
      state[:eliminated] = state[:players].select { |p| state[:chips][p] == 0 }
      state[:auction][:contributions].each do |player, paid|
        change = returns[player] - paid
        add_history(history, event_id, player, change.positive? ? :pot : :settlement,
          blackjack_balance_text(player, [change], state[:chips][player]))
      end
      complete_blackjack_round(state, event_id, history)
    end
  end
end
