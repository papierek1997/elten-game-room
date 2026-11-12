require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Monopoly
    module Presentation
      public

      def surface_spec(replay, viewer)
        state = replay.state
        all_actions = legal_actions(replay, viewer, include_trade_offers: false)
        actions = all_actions.reject { |action| %w[build sell mortgage unmortgage trade_offer pay_jail use_jail_card bankrupt].include?(action["action"]) }
        player = player_key(state, viewer)
        if !replay.finished? && same_user?(state[:current_player], viewer) && player != nil && state[:cash][player].to_i < 0 && [:awaiting_roll, :turn_complete].include?(state[:phase])
          actions = [{ "kind" => "command", "action" => "roll" }]
        end
        items = actions.map.with_index do |action, index|
          GameSurfaces::PawnTrackItem.new(id: "monopoly_#{index}", label: action_label(action, state, viewer),
            action: GameSurfaces::Action.new(kind: action["kind"], name: action["action"],
              payload: action.reject { |key, _| %w[kind action].include?(key) }, source: "monopoly_actions"))
        end
        if items.empty?
          label = replay.finished? ? result_text(replay) : waiting_text(state)
          items << GameSurfaces::PawnTrackItem.new(id: "status", label: label)
        end
        menus = %w[build sell mortgage unmortgage].to_h do |operation|
          choices = all_actions.select { |a| a["action"] == operation }.map do |a|
            GameSurfaces::PawnTrackItem.new(id: "#{operation}:#{a['property']}", label: action_label(a, state, viewer),
              action: GameSurfaces::Action.new(kind: "command", name: operation,
                payload: { "property" => a["property"] }, source: "monopoly_actions"))
          end
          [operation, choices]
        end
        GameSurfaces::PawnTrackSpec.new(id: "monopoly_actions", header: _("Monopoly"), items: items,
          menus: menus, empty_label: _("No action is available"))
      end

      def participant_scores(replay)
        replay.state[:players].to_h { |player| [player, net_worth(replay.state, player)] }
      end

      def participant_status(replay, participant, connected: true)
        player = player_key(replay.state, participant)
        return _("bankrupt") if player != nil && replay.state[:bankrupt][player]
        super
      end

      def custom_game_shortcuts(replay, viewer)
        state = replay.state
        player = player_key(state, viewer)
        actions = legal_actions(replay, viewer, include_trade_offers: false)
        shortcuts = [
          announcement_shortcut(key: "i", label: _("read player positions"), message: positions_text(state)),
          (announcement_shortcut(key: "c", label: _("read your cash"), message: _("Your cash: %{cash}.") % { cash: state[:cash][player].to_i }) if player != nil),
          announcement_shortcut(key: "s", label: _("read finances"), message: finances_text(state)),
          (announcement_shortcut(key: "f", label: _("read the current deed"), message: deed_text(state, current_square(state, player))) if player != nil),
          browse_shortcut(key: "d", label: _("browse unowned property"), prompt: _("Unowned property"), choices: property_choices(state) { |square| state[:owners][square[:index]] == nil }),
          browse_shortcut(key: "d", modifiers: [:shift], label: _("browse the board"), prompt: _("Board"), choices: board_choices(state)),
          (browse_shortcut(key: "v", label: _("browse your holdings"), prompt: _("Your holdings"), choices: property_choices(state, group_progress: true) { |square| same_user?(state[:owners][square[:index]], player) }) if player != nil),
          browse_shortcut(key: "v", modifiers: [:shift], label: _("browse other holdings"), prompt: _("Other holdings"), choices: property_choices(state, group_progress: true) { |square| state[:owners][square[:index]] != nil && !same_user?(state[:owners][square[:index]], player) })
        ].compact
        shortcuts.concat(property_action_shortcuts(actions, state, viewer)) if player != nil
        {
          "pay_jail" => ["p", _("pay to leave jail")],
          "use_jail_card" => ["j", _("use a Get out of jail card")],
          "request_rent" => ["space", _("request the rent")],
          "bankrupt" => ["b", _("declare bankruptcy")]
        }.each do |action_name, (key, label)|
          next if !actions.any? { |action| action["action"] == action_name }

          shortcuts << GameShortcut.new(key: key, label: label, kind: :action,
            action_kind: "command", action_name: action_name)
        end
        bid = actions.find { |action| action["action"] == "auction_bid" }
        if bid != nil
          shortcuts << GameShortcut.new(key: "g", label: _("place the next auction bid"), kind: :action,
            action_kind: "command", action_name: "auction_bid", payload: { "amount" => bid["amount"] })
        end
        if state[:phase] == :auction && same_user?(state[:current_player], viewer) && player != nil
          minimum, maximum = state[:auction_bid].to_i + 1, state[:cash][player].to_i
          if maximum >= minimum
            shortcuts << GameShortcut.new(key: "b", label: _("enter your auction bid"), kind: :number_input,
              prompt: _("Your auction bid:"), default_value: bid ? bid["amount"] : minimum,
              allowed_values: minimum..maximum, value_key: "amount", action_kind: "command", action_name: "auction_bid")
          end
        end
        if same_user?(state[:current_player], viewer) && [:awaiting_roll, :turn_complete].include?(state[:phase]) && active_players(state).length > 1
          shortcuts << GameShortcut.new(
            key: "e", label: _("arrange a trade"), kind: :staged_form, prompt: _("Choose a player for the trade"),
            action_kind: "command", action_name: "trade_prepare", value_key: "target",
            choices: active_players(state).reject { |other| same_user?(other, player) }.map do |other|
              OptionChoice.new(value: player_index(state[:players], other), label: participant_name(other))
            end
          )
        end
        {
          "trade_accept" => ["a", _("accept the trade")],
          "trade_reject" => ["r", _("reject the trade")]
        }.each do |action_name, (key, label)|
          next if !actions.any? { |action| action["action"] == action_name }

          shortcuts << GameShortcut.new(key: key, label: label, kind: :action,
            action_kind: "command", action_name: action_name)
        end
        shortcuts
      end

      def staged_form_shortcut(shortcut, replay, viewer, selection)
        return nil if shortcut.action_name != "trade_prepare"

        state = replay.state
        player = player_key(state, viewer)
        target_index = Integer(selection["target"].to_s, 10)
        target = state[:players][target_index]
        return nil if player == nil || target == nil || same_user?(player, target)

        GameShortcut.new(
          key: "e", label: _("arrange a trade"), kind: :form, prompt: _("Trade proposal"),
          action_kind: "command", action_name: "trade_offer", payload: { "target" => target_index },
          fields: trade_form_fields(state, player, target)
        )
      rescue ArgumentError, TypeError
        nil
      end

      def move_error_for(status, selection: nil, replay: nil, actor: nil)
        case status
        when :empty_trade
          _("Choose at least one property or enter different cash amounts before sending the proposal.")
        when :invalid_trade
          _("This trade is no longer valid. Check the player, properties and available cash.")
        else
          super
        end
      end

      def move_error(status)
        return _("Your auction bid must exceed the current bid and fit your available cash.") if status == :invalid_auction_bid
        if status.to_s.start_with?("insolvent_")
          amount = status.to_s.delete_prefix("insolvent_").to_i
          return _("You do not have enough money. You are %{amount} short.") % { amount: amount }
        end
        super
      end

      def describe_event(event, repository, replay, viewer)
        id = repository.event_id(event).to_i
        values = replay.history.filter_map { |entry| entry.text if entry.event_id.to_i == id }
        values.empty? ? nil : values
      end

      private

      def action_label(action, state, viewer)
        index = action["property"].to_i
        property = state[:board][index]
        case action["action"]
        when "roll" then _("Roll the dice")
        when "buy" then _("Buy")
        when "decline" then _("Do not buy")
        when "build" then _("Build on %{property}; buildings: %{count}; cost: %{amount}") % {
          property: property_name_and_group(property), count: building_count_text(state, property), amount: property[:house_cost] }
        when "sell"
          if hotel_liquidation?(state, property)
            _("Sell all buildings in %{group}; receive %{amount}; no houses in the bank") % {
              group: property_group_label(property), amount: colour_group_squares(state, property[:group]).sum { |s| state[:houses][s[:index]].to_i * s[:house_cost] / 2 } }
          else
            _("Sell a building on %{property}; buildings: %{count}; receive %{amount}") % {
              property: property_name_and_group(property), count: building_count_text(state, property), amount: property[:house_cost] / 2 }
          end
        when "mortgage" then _("Mortgage %{property}; receive %{amount}") % { property: property_name_and_group(property), amount: property[:mortgage] }
        when "unmortgage" then _("Unmortgage %{property}; cost: %{amount}") % { property: property_name_and_group(property), amount: unmortgage_cost(property) }
        when "pay_jail" then _("Pay %{amount} to leave jail") % { amount: board_payment(state, 50) }
        when "use_jail_card" then _("Use a Get out of jail card")
        when "bankrupt" then _("Declare bankruptcy")
        when "auction_bid" then _("Bid %{amount}") % { amount: action["amount"] }
        when "auction_pass" then _("Pass in the auction")
        when "request_rent" then _("Request %{amount} rent from %{player}") % { amount: state[:rent_amount], player: participant_name(state[:rent_payer]) }
        when "waive_rent" then _("Do not request this rent")
        when "trade_offer" then trade_label(state, action["offer"])
        when "trade_accept" then _("Accept the proposed trade")
        when "trade_reject" then _("Reject the proposed trade")
        else action["action"]
        end
      end

      def trade_label(state, value)
        offer = parse_trade_offer(state, value)
        return _("Trade") if offer == nil
        parts = []
        offer_properties(offer, :give).each { |index| parts << _("give %{property}") % { property: property_name_and_group(state[:board][index]) } }
        parts << _("give %{amount}") % { amount: offer[:give_cash] } if offer[:give_cash] > 0
        offer_properties(offer, :receive).each { |index| parts << _("receive %{property}") % { property: property_name_and_group(state[:board][index]) } }
        parts << _("receive %{amount}") % { amount: offer[:receive_cash] } if offer[:receive_cash] > 0
        _("Trade with %{player}: %{details}") % { player: participant_name(offer[:target]), details: parts.join(", ") }
      end

      def public_trade_summary(state, offer)
        [[:give, offer[:from], offer[:target]], [:receive, offer[:target], offer[:from]]].filter_map do |side, from, target|
          assets = offer_properties(offer, side).map { |index| property_name_and_group(state[:board][index]) }
          cash = offer["#{side}_cash".to_sym].to_i
          assets << _("cash: %{amount}") % { amount: cash } if cash > 0
          next if assets.empty?
          _("%{from} to %{target}: %{assets}") % { from: participant_name(from), target: participant_name(target), assets: assets.join(", ") }
        end.join("; ")
      end

      def trade_form_fields(state, player, target)
        own = tradeable_squares(state, player).map do |square|
          OptionChoice.new(value: square[:index], label: property_name_and_group(square))
        end
        theirs = tradeable_squares(state, target).map do |square|
          OptionChoice.new(value: square[:index], label: property_name_and_group(square))
        end
        own = [OptionChoice.new(value: nil, label: _("No matching property."))] if own.empty?
        theirs = [OptionChoice.new(value: nil, label: _("No matching property."))] if theirs.empty?
        [
          OptionDefinition.new(key: "give_cash", label: _("Money you offer"), kind: :integer, default: 0),
          OptionDefinition.new(key: "receive_cash", label: _("Money you request"), kind: :integer, default: 0),
          OptionDefinition.new(key: "give_properties", label: _("Your properties in the offer"), kind: :multiple_choice, choices: own),
          OptionDefinition.new(key: "receive_properties", label: _("Requested properties from %{player}") % { player: participant_name(target) }, kind: :multiple_choice, choices: theirs)
        ]
      end

      def building_count_text(state, property)
        count = state[:houses][property[:index]].to_i
        count == 5 ? _("1 hotel") : count.to_s
      end

      def property_action_shortcuts(actions, state, viewer)
        definitions = {
          "build" => ["h", [], _("build a house"), _("Choose a property to build on")],
          "sell" => ["h", [:shift], _("sell a building"), _("Choose a property to sell a building from")],
          "mortgage" => ["k", [], _("mortgage a property"), _("Choose a property to mortgage")],
          "unmortgage" => ["k", [:shift], _("unmortgage a property"), _("Choose a property to unmortgage")]
        }
        definitions.map do |action_name, (key, modifiers, label, prompt)|
          available = actions.select { |action| action["action"] == action_name }
          if available.empty?
            message = if !same_user?(state[:current_player], viewer)
              _("It is not your turn.")
            elsif ![:awaiting_roll, :turn_complete].include?(state[:phase])
              _("Complete the current decision before managing property.")
            else
              { "build" => _("You cannot build now. You need a complete unmortgaged colour group, enough cash and an available building."),
                "sell" => _("You have no buildings available to sell now."),
                "mortgage" => _("You have no properties available to mortgage now."),
                "unmortgage" => _("You cannot unmortgage now. You need a mortgaged property and enough cash.") }.fetch(action_name)
            end
            next GameShortcut.new(key: key, modifiers: modifiers, label: label, kind: :announcement, message: message)
          end

          GameShortcut.new(
            key: key, modifiers: modifiers, label: label, kind: :surface,
            action_kind: "surface", action_name: "open_menu", payload: { "menu" => action_name, "focus_surface" => true }
          )
        end
      end

      def positions_text(state)
        state[:players].map do |player|
          square = current_square(state, player)
          _("%{player}: field %{number}, %{square}") % {
            player: participant_name(player), number: square[:index], square: square[:name]
          }
        end.join("; ")
      end

      def finances_text(state)
        worth = state[:players].to_h { |player| [player, net_worth(state, player)] }
        score_announcement_order(state[:players], worth, eliminated: state[:bankrupt]).map { |player| _("%{player}: cash %{cash}, net worth %{value}") % { player: participant_name(player), cash: state[:cash][player], value: worth[player] } }.join("; ")
      end

      def deed_text(state, square)
        return _("This square has no deed.") if ![:property, :railroad, :utility].include?(square[:type])
        owner = state[:owners][square[:index]]
        buildings = square[:type] == :property ? _("; buildings: %{buildings}") % { buildings: building_count_text(state, square) } : ""
        _("%{name}; %{group}; price %{price}; owner %{owner}%{buildings}; %{mortgage}.") % {
          name: square[:name], group: property_group_label(square), price: square[:price], owner: owner == nil ? _("none") : participant_name(owner),
          buildings: buildings, mortgage: state[:mortgaged][square[:index]] ? _("mortgaged") : _("not mortgaged")
        }
      end

      def waiting_text(state)
        template = case state[:phase]
        when :property_decision then _("Waiting for %{player} to decide whether to buy.")
        when :rent_decision then _("Waiting for %{player} to collect or waive rent.")
        when :trade_response then _("Waiting for %{player} to accept or reject the trade.")
        when :auction then _("Waiting for %{player} to bid or pass.")
        else _("Waiting for %{player} to roll.")
        end
        template % { player: participant_name(state[:current_player]) }
      end

      def property_name_and_group(square)
        _("%{property}, %{group}") % { property: square[:name], group: property_group_label(square) }
      end

      def property_group_label(square)
        return _("railroad") if square[:type] == :railroad
        return _("utility") if square[:type] == :utility

        {
          "brown" => _("brown group"),
          "light_blue" => _("light blue group"),
          "azure" => _("light blue group"),
          "pink" => _("pink group"),
          "purple" => _("purple group"),
          "orange" => _("orange group"),
          "red" => _("red group"),
          "yellow" => _("yellow group"),
          "green" => _("green group"),
          "dark_blue" => _("dark blue group"),
          "blue" => _("dark blue group"),
          "white" => _("white group"),
          "gray" => _("gray group"),
          "magenta" => _("magenta group")
        }.fetch(square[:group].to_s, square[:group].to_s)
      end

      def property_choices(state, group_progress: false)
        choices = state[:board].select { |square| [:property, :railroad, :utility].include?(square[:type]) && yield(square) }.map do |square|
          text = deed_text(state, square)
          if group_progress && square[:type] == :property
            owner = state[:owners][square[:index]]
            group = colour_group_squares(state, square[:group])
            owned = group.count { |member| same_user?(state[:owners][member[:index]], owner) }
            text = _("%{property}; group %{owned} of %{total}.") % {
              property: text.sub(/\.\z/, ""), owned: owned, total: group.length
            }
          end
          details = group_progress ? [ShortcutChoice.new(value: "rent", label: property_rent_text(state, square))] : square[:index]
          ShortcutChoice.new(value: details, label: text)
        end
        choices.empty? ? [ShortcutChoice.new(value: nil, label: _('No matching property.'))] : choices
      end

      def board_choices(state)
        state[:board].map do |square|
          name = [:property, :railroad, :utility].include?(square[:type]) ? property_name_and_group(square) : square[:name]
          ShortcutChoice.new(value: square[:index], label: _("%{number}. %{name}") % { number: square[:index], name: name })
        end
      end

      def property_rent_text(state, square)
        owner = state[:owners][square[:index]]
        return _("No rent: this property has no owner.") if owner == nil
        return _("No rent: this property is mortgaged.") if state[:mortgaged][square[:index]]
        if state[:options]["no_rent_in_jail"] && state[:jail][owner].to_i > 0
          return _("No rent: %{owner} is in jail.") % { owner: participant_name(owner) }
        end
        if square[:type] == :utility
          # Show the formula for a future visit, not the last player's roll.
          multiplier = rent_for(state.merge(last_roll: 1), square, owner)
          return _("Visitors pay %{multiplier} times their dice total to %{owner}.") % {
            multiplier: multiplier, owner: participant_name(owner)
          }
        end
        _("Visitors pay %{amount} to %{owner}.") % { amount: rent_for(state, square, owner), owner: participant_name(owner) }
      end
    end

    include Presentation
  end
end
