require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Monopoly
    module Evaluation
      public

      def bot_observation(replay, actor)
        state = replay.state
        { "phase" => state[:phase], "current_player" => state[:current_player], "positions" => state[:positions],
          "cash" => state[:cash], "owners" => state[:owners], "houses" => state[:houses],
          "mortgaged" => state[:mortgaged], "jackpot" => state[:jackpot] }
      end

      def bot_action_score(replay, actor, action, context: nil)
        state = replay.state
        player = player_key(state, actor)
        cash = state[:cash][player]
        square = state[:board][action["property"].to_i]
        reserve = monopoly_cash_reserve(state, player)
        case action["action"]
        when "roll" then cash < 0 ? -20_000 : 100
        when "buy"
          property = current_square(state, actor)
          cash - property[:price] >= reserve / 2 || trade_property_value(state, property[:index], player) >= property[:price] * 2 ? 500 : -20
        when "decline" then 0
        when "build"
          return -100 if cash - square[:house_cost] < reserve
          level = state[:houses][square[:index]]
          traffic = monopoly_expected_visits(state, square[:index], player)
          income = square[:rents][level + 1] - (level.zero? ? square[:rents][0] * 2 : square[:rents][level])
          # Hotels release four houses. Preserve a house shortage unless the
          # extra income on this particular street justifies releasing them.
          shortage = level == 4 && available_houses(state) <= 4
          200 + income.to_f / square[:house_cost] * (20 + traffic * 100) - (shortage ? 60 : 0)
        when "mortgage", "sell"
          return -200 if cash >= 0
          proceeds, lost_income = monopoly_liquidation_effect(state, player, square, action["action"])
          excess = [cash + proceeds, 0].max.to_f / [proceeds, 1].max
          1000 - lost_income * 100.0 / [proceeds, 1].max - excess * 15
        when "unmortgage" then cash - unmortgage_cost(square) >= reserve ? 250 : -100
        when "bankrupt" then -10_000
        when "auction_bid"
          limit = [trade_property_value(state, state[:auction_square], player), cash - reserve / 2].min
          action["amount"].to_i <= limit ? 100 : -100
        when "pay_jail", "use_jail_card"
          undeveloped = state[:board].count { |s| s[:price] && !state[:owners][s[:index]] }
          want_exit = undeveloped >= 6 || reserve < board_payment(state, 200)
          return 50 unless want_exit
          action["action"] == "use_jail_card" ? 210 : (cash - board_payment(state, 50) >= reserve ? 200 : 40)
        when "request_rent" then 1_000
        when "waive_rent" then -1_000
        when "trade_offer"
          offer = parse_trade_offer(state, action["offer"])
          return -30_000 if offer == nil || state[:rejected_trades]["#{player}|#{action['offer']}"]
          offer[:from] = player
          return -30_000 if !valid_trade_offer?(state, offer)
          # One proposal in a turn, at least two circuits between proposals to
          # the same person. These are strategy limits, not restrictions on humans.
          return -30_000 if state[:trade_offered_turn][player] == state[:turn_number]
          previous = state[:trade_target_turn][[player, offer[:target]]]
          return -30_000 if previous && state[:turn_number] - previous < state[:players].length * 2
          target_gain = trade_gain(state, offer, offer[:target])
          target_cash = state[:cash][offer[:target]] + offer[:give_cash] - offer[:receive_cash]
          return -30_000 if target_gain < money(state, 10) || target_cash < monopoly_cash_reserve(state, offer[:target])
          if cash < 0 && offer[:receive_cash] > 0 && offer[:receive_cash] >= -cash &&
              offer[:receive_cash] >= offer_properties(offer, :give).sum { |index| state[:board][index][:mortgage] }
            1100
          else
            gain = trade_gain(state, offer, player)
            gain > money(state, 50) && cash + offer[:receive_cash] - offer[:give_cash] >= reserve ? 200 + gain.to_f / money(state, 1) : (cash < 0 ? -30_000 : -100)
          end
        when "trade_accept" then monopoly_trade_safe?(state, player) ? 500 : -500
        when "trade_reject" then monopoly_trade_safe?(state, player) ? -100 : 300
        else 0
        end
      end

      private

      def monopoly_liquidation_effect(state, player, square, action)
        if action == "sell" && hotel_liquidation?(state, square)
          group = colour_group_squares(state, square[:group])
          proceeds = group.sum { |property| property[:house_cost] * state[:houses][property[:index]] / 2 }
          lost_income = group.sum do |property|
            level = state[:houses][property[:index]]
            (property[:rents][level] - property[:rents][0] * 2) * monopoly_expected_visits(state, property[:index], player)
          end
        elsif action == "sell"
          level = state[:houses][square[:index]]
          proceeds = square[:house_cost] / 2
          after = level == 1 ? square[:rents][0] * 2 : square[:rents][level - 1]
          lost_income = (square[:rents][level] - after) * monopoly_expected_visits(state, square[:index], player)
        else
          proceeds = square[:mortgage]
          lost_income = monopoly_expected_rent(state, square, player) * monopoly_expected_visits(state, square[:index], player)
        end
        [proceeds, [lost_income, 0].max]
      end

      def monopoly_cash_reserve(state, player)
        # Keep one owned forecast snapshot, not mutable state references or a
        # hash alone. Every input affecting rents/exposure is compared again;
        # hypothetical trades and in-place property changes invalidate it too.
        inputs = state.values_at(:board, :board_data, :options, :players, :positions,
          :jail, :bankrupt, :owners, :houses, :mortgaged)
        unless @monopoly_reserve_inputs.eql?(inputs)
          @monopoly_reserve_inputs = GameRoomSnapshot.copy(inputs)
          @monopoly_reserves = {}
        end
        return @monopoly_reserves[player] if @monopoly_reserves.key?(player)

        @monopoly_reserves[player] = calculate_monopoly_cash_reserve(state, player)
      end

      def calculate_monopoly_cash_reserve(state, player)
        rents = state[:board].filter_map do |square|
          owner = state[:owners][square[:index]]
          monopoly_expected_rent(state, square, owner) if owner && !same_user?(owner, player) && !state[:mortgaged][square[:index]]
        end
        baseline = [board_payment(state, 100) + rents.max(3).sum / 3, board_payment(state, 500)].min
        exposure = monopoly_landing_probabilities(state).fetch(player, {}).sum do |index, probability|
          square = state[:board][index]
          owner = state[:owners][index]
          rent = owner && !same_user?(owner, player) && !state[:mortgaged][index] ? monopoly_expected_rent(state, square, owner) : 0
          probability * rent
        end
        [baseline, board_payment(state, 100) + (exposure * 2).ceil].max
      end

      def monopoly_expected_rent(state, square, owner)
        return 0 if state[:options]["no_rent_in_jail"] && state[:jail][owner].to_i > 0
        # The last roll is not the next visitor's utility rent multiplier.
        forecast = square[:type] == :utility ? state.merge(last_roll: 7) : state
        rent_for(forecast, square, owner).to_i
      end

      def monopoly_landing_probabilities(state)
        key = [state[:positions], state[:jail], state[:bankrupt], state[:board].length].inspect
        return @monopoly_landings if @monopoly_landing_key == key
        @monopoly_landing_key = key
        @monopoly_landings = state[:players].to_h do |player|
          distribution = Hash.new(0.0)
          unless state[:bankrupt][player]
            1.upto(6) do |first|
              1.upto(6) do |second|
                next if state[:jail][player].to_i > 1 && first != second
                index = (state[:positions][player] + first + second) % state[:board].length
                distribution[index] += 1.0 / 36
              end
            end
          end
          [player, distribution]
        end
      end

      def monopoly_expected_visits(state, index, owner)
        monopoly_landing_probabilities(state).sum do |player, probabilities|
          !same_user?(player, owner) && !state[:bankrupt][player] ? probabilities.fetch(index, 0.0) + 2.0 / state[:board].length : 0.0
        end
      end

      def monopoly_trade_safe?(state, player)
        offer = state[:trade_offer]
        return false unless offer && same_user?(offer[:target], player) && valid_trade_offer?(state, offer)
        # A legal unencumbered gift does not spend the recipient's reserve.
        # Being poor must not turn a strictly beneficial gift into a refusal.
        return true if offer_properties(offer, :receive).empty? && offer[:receive_cash].zero?
        return false if trade_gain(state, offer, player) < 0
        cash = state[:cash][player] + offer[:give_cash] - offer[:receive_cash]
        after = state.merge(owners: state[:owners].dup)
        offer_properties(offer, :give).each { |index| after[:owners][index] = player }
        offer_properties(offer, :receive).each { |index| after[:owners][index] = offer[:from] }
        return false if cash < monopoly_cash_reserve(after, player)
        own_gain = trade_gain(state, offer, player)
        rival_gain = trade_gain(state, offer, offer[:from])
        own_gain + board_payment(state, 100) >= rival_gain * 0.5
      end

      def trade_property_value(state, index, player)
        square = state[:board][index]
        value = square[:price].to_i
        if square[:type] == :property
          group = colour_group_squares(state, square[:group])
          others = group.reject { |property| property[:index] == index }
          owned = others.count { |property| same_user?(state[:owners][property[:index]], player) }
          # Even a solitary deed retains an option to build a group. Its face
          # price is not its liquidation value in a negotiated player trade.
          value += square[:price].to_i / 3
          value += owned * square[:price] / 2
          value += square[:price] if owned == others.length
          rivals = others.filter_map do |property|
            owner = state[:owners][property[:index]]
            owner if owner != nil && !same_user?(owner, player)
          end
          largest_rival_group = rivals.group_by { |owner| owner.to_s.downcase }.values.map(&:length).max.to_i
          if !others.empty? && largest_rival_group == others.length
            # This is the last block against an opponent's monopoly, not a
            # generic markup. Re-evaluating after the offer also credits the
            # specific buyer's newly completed group in trade_gain.
            value += group.sum { |property| property[:price].to_i } / 2
          end
        elsif square[:type] == :railroad
          value += square[:price].to_i / 4
          value += owned_squares(state, player).count { |property| property[:type] == :railroad && property[:index] != index } * money(state, 50)
        elsif square[:type] == :utility
          value += square[:price].to_i / 4
          value += square[:price].to_i / 2 if owned_squares(state, player).any? { |property| property[:type] == :utility && property[:index] != index }
        end
        value
      end

      def trade_gain(state, offer, player)
        incoming, outgoing = same_user?(offer[:from], player) ? [:receive, :give] : [:give, :receive]
        after = state.merge(owners: state[:owners].dup)
        offer_properties(offer, :give).each { |index| after[:owners][index] = offer[:target] }
        offer_properties(offer, :receive).each { |index| after[:owners][index] = offer[:from] }
        # Only the transferred colour groups, railroads or utilities change
        # value. Repricing every unrelated holding for each hypothetical offer
        # made a late turn considerably more expensive than an early turn.
        affected = (offer_properties(offer, :give) + offer_properties(offer, :receive)).flat_map do |index|
          square = state[:board][index]
          square[:type] == :property ? colour_group_squares(state, square[:group]) :
            state[:board].select { |other| other[:type] == square[:type] }
        end.uniq { |square| square[:index] }
        offer["#{incoming}_cash".to_sym] - offer["#{outgoing}_cash".to_sym] +
          affected.sum { |s| same_user?(after[:owners][s[:index]], player) ? trade_property_value(after, s[:index], player) : 0 } -
          affected.sum { |s| same_user?(state[:owners][s[:index]], player) ? trade_property_value(state, s[:index], player) : 0 }
      end

      def net_worth(state, player)
        state[:cash][player].to_i + owned_squares(state, player).sum { |square| square[:price].to_i + state[:houses][square[:index]].to_i * square[:house_cost].to_i }
      end
    end

    include Evaluation
  end
end
