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
      add_history(history,event_id,dealer,:deal,_("Round %{round}: %{player} deals; everyone plays against the other players.") % {round:state[:round],player:participant_name(dealer)})
      advance_hand(state)
    end

    def social_settle(state,event_id,history,uncontested: false)
      auction_pots(state).each do |pot|
        eligible = uncontested ? pot[:eligible] : pot[:eligible].select { |p| hand_total(state[:hands].fetch(p).first[:cards]) <= 21 }
        if eligible.empty?
          pot[:contributors].each { |p| state[:chips][p] += pot[:slice] }
          next
        end
        best = eligible.map { |p| hand_total(state[:hands][p].first[:cards]) }.max unless uncontested
        winners = uncontested ? eligible : eligible.select { |p| hand_total(state[:hands][p].first[:cards]) == best }
        share,odd = pot[:amount].divmod(winners.size)
        winners.each_with_index { |p,i| state[:chips][p] += share + (i < odd ? 1 : 0) }
      end
      state[:eliminated] = state[:players].select { |p| state[:chips][p] == 0 }
      state[:players].each { |p| add_history(history,event_id,p,:settlement,_("%{player} has %{chips} chips.") % {player:participant_name(p),chips:state[:chips][p]/2.0}) }
      if state[:round] >= state[:options]["round_limit"] || state[:eliminated].size >= state[:players].size-1
        best = state[:chips].values.max
        winners = state[:players].select { |p| state[:chips][p] == best }
        state.merge!(phase: :finished,current_player:nil,winner:winners.one? ? winners.first : nil,draw:!winners.one?)
        history << result_history(event_id:event_id,winner:state[:winner],draw:state[:draw])
      else
        prepare_auction(state)
      end
    end
  end
end
