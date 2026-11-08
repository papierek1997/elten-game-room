require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Monopoly
    module BoardEvents
      private

      def move_player(state, player, distance, event_id, history)
        previous = state[:positions][player]
        destination = (previous + distance) % state[:board].length
        if previous + distance >= state[:board].length
          state[:laps][player] += 1
          salary = state[:board_data].fetch(:salary)
          salary *= 2 if destination.zero? && state[:options]["double_salary_on_start"]
          state[:cash][player] += salary
          text = destination.zero? && state[:options]["double_salary_on_start"] ? _("%{player} receives double salary, %{amount}, for landing on Start.") : _("%{player} collected %{amount} for passing Start.")
          # A roll and a subsequent card can both pay salary, in separate history buffers.
          history << HistoryEntry.new(key: "salary:#{event_id}:#{state[:laps][player]}", text: text % { player: participant_name(player), amount: salary }, event_id: event_id, actor: player, kind: :game)
        end
        state[:positions][player] = destination
      end

      def resolve_square(state, player, event_id, history)
        square = current_square(state, player)
        case square[:type]
        when :property, :railroad, :utility
          owner = state[:owners][square[:index]]
          if owner == nil
            if state[:options]["forbid_first_round_purchase"] && state[:laps][player].zero?
              state[:phase] = :turn_complete
            else
              state[:phase] = :property_decision
              history << HistoryEntry.new(key: "purchase_offer:#{event_id}:#{square[:index]}",
                text: _("%{player} may buy %{property}, %{group}, for %{price}.") % {
                  player: participant_name(player), property: square[:name], group: property_group_label(square), price: square[:price]
                }, event_id: event_id, actor: player, kind: :game)
            end
          elsif !same_user?(owner, player) && !state[:mortgaged][square[:index]] && !(state[:options]["no_rent_in_jail"] && state[:jail][owner] > 0)
            rent = rent_for(state, square, owner)
            rent *= state.delete(:card_rent_multiplier).to_i if state[:card_rent_multiplier]
            rent = state.delete(:card_utility_rent) if state[:card_utility_rent]
            if state[:options]["automatic_rent"]
              text = pay_and_describe(state, player, owner, rent, _("rent for %{property}") % { property: square[:name] })
              history << HistoryEntry.new(key: "rent:#{event_id}", text: text, event_id: event_id, actor: player, kind: :game)
              state[:phase] = :turn_complete
            else
              state[:rent_payer] = player
              state[:rent_owner] = owner
              state[:rent_amount] = rent
              state[:rent_origin] = square[:index]
              state[:current_player] = owner
              state[:phase] = :rent_decision
            end
          else
            state[:phase] = :turn_complete
          end
        when :tax, :tax_luxury
          amount = square.fetch(:amount)
          text = pay_and_describe(state, player, bank_recipient(state), amount, square[:name])
          history << HistoryEntry.new(key: "tax:#{event_id}",
            text: text, event_id: event_id, actor: player, kind: :game)
          state[:phase] = :turn_complete
        when :free_parking
          if state[:options]["free_parking_jackpot"] && state[:jackpot] > 0
            state[:cash][player] += state[:jackpot]
            history << HistoryEntry.new(key: "jackpot:#{event_id}", text: _("%{player} collected the Free Parking jackpot of %{amount}.") % { player: participant_name(player), amount: state[:jackpot] }, event_id: event_id, actor: player, kind: :game)
            state[:jackpot] = 0
          end
          state[:phase] = :turn_complete
        when :go_to_jail
          send_to_jail(state, player)
          history << HistoryEntry.new(key: "go_to_jail:#{event_id}", text: _("%{player} goes to jail.") % { player: participant_name(player) }, event_id: event_id, actor: player, kind: :game)
          state[:phase] = :turn_complete
        when :jail
          history << HistoryEntry.new(key: "jail_visit:#{event_id}", text: _("%{player} is only visiting jail.") % { player: participant_name(player) }, event_id: event_id, actor: player, kind: :game)
          state[:phase] = :turn_complete
        when :chance, :community
          state[:phase] = :turn_complete
          draw_event_card(state, player, square[:type], event_id, history)
        else
          state[:phase] = :turn_complete
        end
      end

      def card_definitions(state, deck)
        targets = state[:board_data].fetch(:card_destinations)
        cards = if deck == :chance
          [[:advance, targets[:most_expensive]], [:advance, targets[:start]], [:advance, targets[:middle_group]], [:advance, targets[:after_jail]],
            [:nearest, :railroad], [:nearest, :railroad], [:nearest, :utility],
            [:collect, 50], [:jail_free], [:back, 3], [:jail], [:repairs, 25, 100],
            [:pay, 15], [:advance, targets[:first_station]], [:pay_each, 50], [:collect, 150]]
        else
          [[:advance, targets[:start]], [:collect, 200], [:pay, 50], [:collect, 50], [:jail_free],
            [:jail], [:collect, 100], [:collect, 20], [:collect_each, 10],
            [:collect, 100], [:pay, 100], [:pay, 50], [:collect, 25],
            [:repairs, 40, 115], [:collect, 10], [:collect, 100]]
        end
        cards += deck == :chance ? [[:collect, 200], [:pay_each, 25]] : [[:collect_each, 25], [:pay, 75]] if state[:options]["supplementary_cards"]
        # Scale only monetary card effects, never destinations, dice or distances.
        cards.map do |card|
          if card.first == :repairs
            [card.first, *card.drop(1).map { |amount| money(state, amount) }]
          elsif [:collect, :pay, :pay_each, :collect_each].include?(card.first)
            [card.first, *card.drop(1).map { |amount| board_payment(state, amount) }]
          else
            card
          end
        end
      end

      def initialize_card_decks(state, seed)
        state[:card_decks] = [:chance, :community].to_h do |deck|
          [deck, shuffled_cards((0...card_definitions(state, deck).length).to_a, "#{seed}:#{deck}")]
        end
      end

      def draw_event_card(state, player, deck, event_id, history)
        initialize_card_decks(state, state[:roll_seed] || event_id.to_s) if !state[:card_decks]
        index = state[:card_decks][deck].shift
        return if index == nil
        kind, amount, hotel = card_definitions(state, deck).fetch(index)
        state[:card_decks][deck] << index if kind != :jail_free
        destination = nil
        movement_effects = []
        text = case kind
        when :collect
          state[:cash][player] += amount
          _("%{player} receives %{amount} from the bank.") % { player: participant_name(player), amount: amount }
        when :pay
          pay_and_describe(state, player, bank_recipient(state), amount, _("card fee"))
        when :collect_each, :pay_each
          exceptions = []
          payments = []
          active_players(state).reject { |other| same_user?(other, player) }.each do |other|
            payer, recipient = kind == :collect_each ? [other, player] : [player, other]
            short = state[:cash][payer] < amount
            payment = pay_and_describe(state, payer, recipient, amount, _("card payment"))
            payments << payment
            exceptions << payment if short
          end
          template = if exceptions.empty?
            kind == :collect_each ? _("%{player} receives %{amount} from each other player.") : _("%{player} pays %{amount} to each other player.")
          else
            nil
          end
          template ? template % { player: participant_name(player), amount: amount } : payments.join(" ")
        when :repairs
          total = owned_squares(state, player).sum do |square|
            level = state[:houses][square[:index]].to_i
            fee = level == 5 ? hotel : level * amount
            # Costlier extension buildings have proportionate repair bills.
            # The first eight colours retain the established repair schedule.
            reference_cost = money(state, 200)
            (fee * [square[:house_cost].to_i, reference_cost].max + reference_cost - 1) / reference_cost
          end
          pay_and_describe(state, player, bank_recipient(state), total, _("property repairs"))
        when :jail_free
          state[:jail_cards][player] += 1
          (state[:held_jail_cards][player] ||= []) << [deck, index]
          _("%{player} keeps a Get out of jail card.") % { player: participant_name(player) }
        when :jail
          send_to_jail(state, player)
          _("%{player} goes to jail.") % { player: participant_name(player) }
        when :advance, :back, :nearest
          previous = state[:positions][player]
          destination = if kind == :advance
            amount
          elsif kind == :back
            (previous - amount) % state[:board].length
          else
            (1..state[:board].length).map { |distance| (previous + distance) % state[:board].length }.find { |position| state[:board][position][:type] == amount }
          end
          if kind == :back
            state[:positions][player] = destination
          else
            distance = (destination - previous) % state[:board].length
            move_player(state, player, distance, event_id, movement_effects)
          end
          if kind == :nearest && amount == :railroad
            state[:card_rent_multiplier] = 2
          elsif kind == :nearest && amount == :utility
            random = Random.new(Digest::SHA256.hexdigest("#{state[:roll_seed]}:utility:#{event_id}").to_i(16))
            state[:card_utility_rent] = (random.rand(6) + random.rand(6) + 2) * money(state, 10)
          end
          _("%{player} moves to %{square}.") % { player: participant_name(player), square: state[:board][destination][:name] }
        end
        history << HistoryEntry.new(key: "card:#{event_id}:#{deck}", text: _("%{deck}: %{effect}") % {
          deck: deck == :chance ? _("Chance") : _("Community Chest"), effect: text
        }, event_id: event_id, actor: player, kind: :game)
        history.concat(movement_effects)
        if destination
          resolve_square(state, player, event_id, history)
          state.delete(:card_rent_multiplier)
          state.delete(:card_utility_rent)
        end
      end

      def send_to_jail(state, player)
        state[:positions][player] = state[:board_data].fetch(:jail_index)
        state[:jail][player] = 3
        state[:extra_turn] = false
      end

      def apply_jail_action(state, event, actor, repository, history)
        player = player_key(state, actor)
        return false if state[:phase] != :awaiting_roll || !same_user?(state[:current_player], actor) || state[:jail][player].zero?
        if event["action"] == "pay_jail"
          return false if state[:cash][player] < board_payment(state, 50)
          text = pay_and_describe(state, player, bank_recipient(state), board_payment(state, 50), _("release from jail"))
        else
          return false if state[:jail_cards][player].zero?
          state[:jail_cards][player] -= 1
          held = (state[:held_jail_cards][player] || []).shift
          state[:card_decks][held[0]] << held[1] if held && state[:card_decks]
          text = _("%{player} uses a Get out of jail card and leaves jail.") % { player: participant_name(player) }
        end
        state[:jail][player] = 0
        history << HistoryEntry.new(key: "jail:#{repository.event_id(event)}", text: text, event_id: repository.event_id(event), actor: actor, kind: :game)
        true
      end

      def apply_manual_rent(state, event, actor, repository, history)
        return false if state[:phase] != :rent_decision || !same_user?(state[:current_player], actor)
        owner = player_key(state, actor)
        return false if owner == nil || !same_user?(owner, state[:rent_owner])

        payer = state[:rent_payer]
        amount = state[:rent_amount].to_i
        id = repository.event_id(event)
        if event["action"].to_s == "request_rent"
          text = pay_and_describe(state, payer, owner, amount, _("rent for %{property}") % { property: state[:board][state[:rent_origin]][:name] })
        else
          text = _("%{owner} waived the rent from %{player}.") % {
            owner: participant_name(owner), player: participant_name(payer)
          }
        end
        history << HistoryEntry.new(key: "rent:#{id}", text: text, event_id: id, actor: actor, kind: :game)
        state[:current_player] = payer
        state[:phase] = :turn_complete
        clear_manual_rent(state)
        true
      end

      def clear_manual_rent(state)
        state[:rent_payer] = nil
        state[:rent_owner] = nil
        state[:rent_amount] = 0
        state[:rent_origin] = nil
      end
    end

    include BoardEvents
  end
end
