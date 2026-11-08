module GameRoomGames
  module BlackjackAuction
    using GameRoomLocalization::Translations

    def participant_status(replay, participant, connected: true)
      if replay && !replay.finished? && replay.state[:auction]
        player = replay.players.find { |person| same_user?(person, participant) }
        if player
          return _("Fold") if replay.state[:auction][:folded][player]
          return _("all in") if replay.state[:chips][player].zero? && replay.state[:auction][:contributions].fetch(player, 0) > 0
        end
      end
      super
    end

    private

    def auction_rules?(options); options["blackjack_betting_version"] == 2; end
    def auction_amount(amount); amount % auction_unit == 0 ? (amount / auction_unit).to_i : amount.to_f / auction_unit; end

    def start_auction(state, order, event_id, history)
      state[:auction] = {order: order.dup, contributions: order.to_h { |p| [p, 0] }, folded: {}, acted: {}, acted_at: {},
        current_bet: 0, min_raise: auction_unit}
      order.each do |player|
        paid = [state[:options]["stake"] * auction_unit, state[:chips].fetch(player)].min
        state[:chips][player] -= paid
        state[:auction][:contributions][player] = paid
        add_history(history, event_id, player, :ante,
          _("%{player} pays ante: %{amount}.") % {player: participant_name(player), amount: auction_amount(paid)})
      end
      state[:auction][:current_bet] = state[:auction][:contributions].values.max || 0
      state.merge!(phase: :betting, current_player: auction_actionable(state).first)
      state[:pot] = state[:auction][:contributions].values.sum if state.key?(:pot)
      complete_auction(state, event_id, history) if auction_complete?(state)
    end

    def auction_contenders(state)
      state[:auction][:order].reject { |player| state[:auction][:folded][player] }
    end

    def auction_actionable(state); auction_contenders(state).select { |player| state[:chips][player] > 0 }; end
    def auction_call(state, player)
      [state[:auction][:current_bet] - state[:auction][:contributions].fetch(player), 0].max
    end

    def auction_raise_limits(state, player)
      auction = state[:auction]
      return nil if auction_contenders(state).size < 2 || auction_actionable(state).size < 2
      return nil if auction[:acted][player] && auction[:current_bet] - auction[:acted_at].fetch(player) < auction[:min_raise]
      call = auction_call(state, player)
      available = state[:chips][player] - call
      return nil if available <= 0
      (call + [auction[:min_raise], available].min)..state[:chips][player]
    end

    def auction_actions(replay, actor)
      state = replay.state
      return [] unless state[:phase] == :betting && same_user?(state[:current_player], actor)
      player = state[:current_player]
      return [] unless auction_actionable(state).include?(player)
      call = [auction_call(state, player), state[:chips][player]].min
      actions = [{"kind" => "command", "action" => call.zero? ? "check" : "call", "amount" => call},
        {"kind" => "command", "action" => "fold", "amount" => 0}]
      limits = auction_raise_limits(state, player)
      if limits
        pot = state[:auction][:contributions].values.sum + call
        [limits.begin, call + pot.div(2), call + pot, limits.end].map { |amount| amount.clamp(limits.begin, limits.end) }.uniq.sort.each do |amount|
          actions << {"kind" => "command", "action" => "raise", "amount" => amount}
        end
      end
      stack = state[:chips][player]
      actions << {"kind" => "command", "action" => "all_in", "amount" => stack} if stack <= call || (limits && limits.cover?(stack))
      actions
    end

    def auction_candidate(state, action, amount)
      return nil unless state[:phase] == :betting
      player = state[:current_player]
      return nil unless auction_actionable(state).include?(player)
      return {"action" => action, "amount" => amount} if action == "raise" && auction_raise_limits(state, player)&.cover?(amount)
      replay = Replay.new(state: state, players: state[:players], current_player: player, draw: false)
      auction_actions(replay, player).find { |item| item["action"] == action && item["amount"] == amount }
    end

    def auction_integer(value, maximum)
      text = value.to_s
      return nil unless text.length <= maximum.to_s.length && text.match?(/\A(?:0|[1-9][0-9]*)\z/)
      number = text.to_i
      number if number <= maximum
    end

    # Dyadic balances keep exact payouts within the native event's 64 characters.
    def auction_wire(amount)
      return amount.to_i.to_s if amount.denominator == 1
      "#{amount.numerator.to_s(36)}~#{(amount.denominator.bit_length - 1).to_s(36)}"
    end

    def auction_payment(value, state)
      values = state[:chips].values + state[:auction][:contributions].values
      text = value.is_a?(Integer) || value.is_a?(Rational) ? auction_wire(value) : value.to_s
      return nil if text.length > GameRoomEventProtocol::MAX_VALUE_LENGTH
      if text.match?(/\A(?:0|[1-9][0-9]*)\z/)
        amount = text.to_i
      elsif (match = /\A([1-9a-z][0-9a-z]*)~([1-9a-z][0-9a-z]*)\z/.match(text))
        exponent = match[2].to_i(36)
        return nil if exponent > values.map(&:denominator).max.bit_length - 1
        amount = Rational(match[1].to_i(36), 1 << exponent)
        return nil unless auction_wire(amount) == text
      else
        return nil
      end
      amount if amount <= state[:chips][state[:current_player]]
    end

    def auction_plan(selection, replay)
      state = replay.state
      action, preset = selection["action"].to_s, nil
      if selection["kind"] == "card" && selection["zone"] == "actions" && action == "select"
        action, preset = selection["card"].to_s.split(":", 2)
      end
      if action == "raise" && selection.key?("raise_by")
        call = auction_call(state, state[:current_player])
        return [:invalid, nil] unless selection["quoted_call"].to_s == auction_wire(call)
        increment = auction_integer(selection["raise_by"], state[:chips][state[:current_player]] / auction_unit)
        return [:invalid, nil] unless increment && increment > 0
        amount = call + increment * auction_unit
      else
        amount = auction_payment(preset || (selection.key?("amount") ? selection["amount"] : 0), state)
      end
      return [:invalid, nil] unless amount && auction_candidate(state, action, amount)
      value = "#{action}|#{auction_wire(amount)}"
      return [:invalid, nil] if value.length > GameRoomEventProtocol::MAX_VALUE_LENGTH
      [:ok, event_plan("bet", value)]
    end

    def apply_auction(state, event, actor, event_id, history)
      return false unless state[:phase] == :betting && same_user?(state[:current_player], actor)
      action, text = event["value"].to_s.split("|", 2)
      amount = auction_payment(text, state)
      return false unless amount && auction_candidate(state, action, amount)
      player, auction = state[:current_player], state[:auction]
      previous = auction[:current_bet]
      if action == "fold"
        auction[:folded][player] = true
      else
        state[:chips][player] -= amount
        auction[:contributions][player] += amount
        if auction[:contributions][player] > previous
          increase = auction[:contributions][player] - previous
          auction[:current_bet] = auction[:contributions][player]
          if increase >= auction[:min_raise]
            auction[:min_raise] = increase
            auction[:acted] = {}
          end
        end
      end
      auction[:acted][player] = true
      auction[:acted_at][player] = auction[:current_bet]
      state[:pot] = auction[:contributions].values.sum if state.key?(:pot)
      text = case action
      when "fold" then _("%{player} folds.") % {player: participant_name(player)}
      when "check" then _("%{player} checks.") % {player: participant_name(player)}
      when "call" then _("%{player} calls %{amount}.") % {player: participant_name(player), amount: auction_amount(amount)}
      when "raise" then _("%{player} raises by %{increase}, to %{amount}.") % {player: participant_name(player), increase: auction_amount(auction[:current_bet] - previous), amount: auction_amount(auction[:current_bet])}
      when "all_in" then _("%{player} is all in for %{amount}.") % {player: participant_name(player), amount: auction_amount(amount)}
      end
      add_history(history, event_id, player, :bet, text)
      if auction_complete?(state)
        complete_auction(state, event_id, history)
      else
        following = auction[:order].rotate(auction[:order].index(player) + 1)
        state[:current_player] = following.find { |person| auction_actionable(state).include?(person) }
      end
      true
    end

    def auction_complete?(state)
      return true if auction_contenders(state).size <= 1
      actionable = auction_actionable(state)
      return true if actionable.empty?
      auction = state[:auction]
      return true if actionable.one? && auction[:contributions][actionable.first] >= auction[:current_bet]
      actionable.all? { |player| auction[:acted][player] && auction[:contributions][player] == auction[:current_bet] }
    end

    def auction_label(action, state)
      amount = auction_amount(action["amount"])
      case action["action"]
      when "check" then _("Check")
      when "call" then _("Call %{amount}") % {amount: amount}
      when "fold" then _("Fold")
      when "all_in" then _("All in; %{amount}") % {amount: amount}
      when "raise"
        _("Raise by %{raise}; total payment %{amount}") % {raise: auction_amount(action["amount"] - auction_call(state, state[:current_player])), amount: amount}
      end
    end

    def auction_surface(replay, viewer)
      state = replay.state
      player = state[:players].find { |person| same_user?(person, viewer) }
      actions = auction_actions(replay, viewer).map do |action|
        value = "#{action['action']}:#{auction_wire(action['amount'])}"
        GameSurfaces::Card.new(id: value, value: value, label: auction_label(action, state))
      end
      header = _("Betting: current bet %{bet}; your contribution %{paid}; balance %{balance}.") % {
        bet: auction_amount(state[:auction][:current_bet]), paid: auction_amount(state[:auction][:contributions].fetch(player, 0)),
        balance: auction_amount(state[:chips].fetch(player, 0))}
      GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(id: "actions", header: header, cards: actions,
        empty_label: current_turn_shortcut_text(replay, viewer))])
    end

    def auction_shortcuts(replay, viewer)
      actions = auction_actions(replay, viewer)
      shortcuts = []
      {"c" => %w[check call], "f" => ["fold"], "a" => ["all_in"]}.each do |key, names|
        action = actions.find { |item| names.include?(item["action"]) }
        next unless action
        shortcuts << GameShortcut.new(key: key, label: auction_label(action, replay.state), kind: :action,
          action_kind: "command", action_name: action["action"], payload: {"amount" => auction_wire(action["amount"])})
      end
      limits = !actions.empty? && auction_raise_limits(replay.state, replay.current_player)
      if limits
        call = auction_call(replay.state, replay.current_player)
        minimum = ((limits.begin - call).to_r / auction_unit).ceil
        maximum = ((limits.end - call).to_r / auction_unit).floor
        if minimum <= maximum
          %w[r b].each do |key|
            shortcuts << GameShortcut.new(key: key, label: _("raise"), kind: :number_input, prompt: _("Raise by:"),
              action_kind: "command", action_name: "raise", value_key: "raise_by", allowed_values: minimum..maximum,
              default_value: minimum, payload: {"quoted_call" => auction_wire(call)})
          end
        end
      end
      shortcuts
    end

    def auction_pots(state)
      previous = 0
      state[:auction][:contributions].values.select(&:positive?).uniq.sort.map do |level|
        contributors = state[:auction][:order].select { |player| state[:auction][:contributions][player] >= level }
        amount = (level - previous) * contributors.size
        slice = level - previous
        previous = level
        {amount: amount, slice: slice, contributors: contributors, eligible: contributors & auction_contenders(state)}
      end
    end

    def continue_auction(state, event_id, history)
      auction = state[:auction]
      auction.merge!(acted: {}, acted_at: {}, min_raise: auction_unit)
      state.merge!(phase: :betting, current_player: auction_actionable(state).first)
      complete_auction(state, event_id, history) if auction_complete?(state)
    end
  end
end
