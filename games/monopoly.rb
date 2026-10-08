require_relative "card_game"
require_relative "../lib/game_bots"
require_relative "../content/monopoly_boards"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Monopoly < CardGame
    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      cues = []
      cues << "roll" if action == "roll"
      cues << "play2" if %w[buy build sell mortgage unmortgage trade_accept auction_bid].include?(action)
      event_history = history
      cues << "hit1" if event_history.any? { |entry| entry.key.to_s.start_with?("group_complete:") }
      return cues.first if cues.length == 1
      return cues if !cues.empty?
    end

    def notification_option_keys(_options); %w[board]; end

    def id
      "monopoly"
    end

    def save_game_error(replay)
      return _("Wait until the auction ends before saving the game.") if replay.state[:phase] == :auction

      super
    end

    def eliminated_from_game?(replay, viewer)
      replay.state.fetch(:bankrupt, {}).any? { |player, out| out && same_user?(player, viewer) }
    end

    def name
      _("Monopoly")
    end

    def short_description
      _("Buy properties, build houses and collect rent to drive your opponents into bankruptcy.")
    end

    def minimum_players
      2
    end

    def maximum_players
      8
    end

    def supports_bots?
      true
    end

    def bot_strategy
      @bot_strategy ||= GameRoomBots::HeuristicStrategy.new
    end

    def rule_sections
      generated_rule_sections
    end

    def board_profile_rules
      rule_section(:board_profiles, _("Regional board details"),
          *GameRoomContent::MonopolyBoards.choices.map do |choice|
            board = GameRoomContent::MonopolyBoards.build(choice.value)
            squares = board[:squares]
            _("%{name}: %{fields} fields; currency: %{currency}; starting cash %{cash}; Start salary %{salary}; %{groups} colour groups, %{stations} stations, %{utilities} utilities; bank: %{houses} houses and %{hotels} hotels.") % {
              name: board[:name], fields: squares.length, currency: board[:currency],
              cash: board[:starting_cash], salary: board[:salary],
              groups: squares.select { |square| square[:type] == :property }.map { |square| square[:group] }.uniq.length,
              stations: squares.count { |square| square[:type] == :railroad },
              utilities: squares.count { |square| square[:type] == :utility },
              houses: board[:bank_houses], hotels: board[:bank_hotels]
            }
          end)
    end

    def option_definitions
      [
        OptionDefinition.new(key: "board", label: _("Board to use"), kind: :choice, default: "atlantic_city", choices: GameRoomContent::MonopolyBoards.choices),
        OptionDefinition.new(key: "free_parking_jackpot", label: _("Free parking jackpot"), kind: :boolean, default: true),
        OptionDefinition.new(key: "double_salary_on_start", label: _("Double salary when landing on Start"), kind: :boolean, default: true),
        OptionDefinition.new(key: "forbid_first_round_purchase", label: _("Forbid buying properties on the first board round"), kind: :boolean, default: false),
        OptionDefinition.new(key: "no_rent_in_jail", label: _("Do not collect rent while in jail"), kind: :boolean, default: false),
        OptionDefinition.new(key: "lucky_double_one", label: _("Lucky double one"), kind: :boolean, default: false),
        OptionDefinition.new(key: "supplementary_cards", label: _("Supplementary Chance and Community Chest cards"), kind: :boolean, default: true),
        OptionDefinition.new(key: "automatic_rent", label: _("Pay rents automatically"), kind: :boolean, default: true),
        OptionDefinition.new(key: "auction_unsold", label: _("Put unsold properties up for auction"), kind: :boolean, default: false),
        OptionDefinition.new(key: "auction_decision_time", label: _("Auction decision time in seconds; 0 means no limit"), kind: :integer, default: 0,
          summary_label: _("Auction decision time"), summary_unit: :seconds, omit_zero: true,
          visible_if: { "auction_unsold" => true })
      ]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _("Auction decision time cannot be negative.") if values["auction_decision_time"].to_i < 0
      super
    end

    def rules_option_visible?(definition, options)
      return false if definition.key.to_s == "auction_decision_time" && options[definition.key.to_s].to_i.zero?
      super
    end

    def options_summary(options)
      values = normalize_options(options)
      board = GameRoomContent::MonopolyBoards.build(values["board"])
      _("%{board}; free parking jackpot: %{jackpot}; automatic rent: %{rent}") % {
        board: board[:name], jackpot: values["free_parking_jackpot"] ? _("on") : _("off"),
        rent: values["automatic_rent"] ? _("on") : _("off")
      }
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players, options_from_json(session["options"]))
      accepted = []
      history = [starting_history(players)]
      events.each do |event|
        break if state[:winner] != nil
        actor = repository.actor_of(event, session)
        groups_before = %w[buy trade_accept auction_bid auction_pass auction_timeout bankrupt bankrupt_auto].include?(event["action"].to_s) ? completed_colour_groups(state) : nil
        applied = case event["action"].to_s
        when "roll" then apply_roll(state, event, actor, repository, history)
        when "buy" then apply_buy(state, event, actor, repository, history)
        when "decline" then apply_decline(state, event, actor, repository, history)
        when "build", "sell", "mortgage", "unmortgage" then apply_property_action(state, event, actor, repository, history)
        when "pay_jail", "use_jail_card" then apply_jail_action(state, event, actor, repository, history)
        when "request_rent", "waive_rent" then apply_manual_rent(state, event, actor, repository, history)
        when "trade_prepare", "trade_offer", "trade_accept", "trade_reject" then apply_trade(state, event, actor, repository, history)
        when "bankrupt" then apply_bankruptcy(state, event, actor, repository, history)
        when "bankrupt_auto" then apply_automatic_bankruptcy(state, event, actor, repository, history)
        when "auction_bid", "auction_pass" then apply_auction(state, event, actor, repository, history)
        when "auction_timeout" then apply_auction_timeout(state, event, actor, repository, history)
        else false
        end
        if applied
          announce_completed_groups(state, groups_before, repository.event_id(event), history) if groups_before
          settle_debts(state, repository.event_id(event), history)
          advance_completed_turn(state) if event["action"].to_s != "trade_prepare"
          accepted << event
        end
      end
      GameRoomSessionClock.attach(state, session)
      Replay.new(board: state[:board], players: players, current_player: state[:current_player], winner: state[:winner],
        draw: false, accepted_events: accepted, history: history, state: state)
    end

    def active_actors(replay)
      replay.current_player == nil ? [] : [replay.current_player]
    end

    def automatic_action_allowed?(replay, actor, table_owner:)
      super || (!replay.finished? && same_user?(actor, replay.current_player) && unaffordable_purchase?(replay.state))
    end

    def automatic_actor(replay, viewer, table_owner:)
      return viewer if !replay.finished? && same_user?(viewer, replay.current_player) && unaffordable_purchase?(replay.state)
      super
    end

    def automatic_action_due?(replay, actor, context: nil)
      state = replay.state
      return false if replay.finished?
      return true if same_user?(actor, replay.current_player) && unaffordable_purchase?(state)
      return false if !same_user?(actor, replay.players.first)
      return true if unavoidable_bankruptcy?(state)
      state[:phase] == :auction &&
        state[:auction_deadline].to_i > 0 && context&.now != nil && context.now.to_i >= state[:auction_deadline].to_i
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished? || !automatic_action_due?(replay, actor, context: context)
      return { "kind" => "command", "action" => "decline" } if same_user?(actor, replay.current_player) && unaffordable_purchase?(replay.state)
      return { "kind" => "command", "action" => "bankrupt_auto" } if unavoidable_bankruptcy?(replay.state)
      { "kind" => "command", "action" => "auction_timeout" }
    end

    def legal_actions(replay, actor, context: nil, include_trade_offers: true)
      state = replay.state
      return [] if replay.finished? || !same_user?(state[:current_player], actor)
      player = player_key(state, actor)
      actions = []
      case state[:phase]
      when :awaiting_roll
        actions << { "kind" => "command", "action" => "roll" }
        actions.concat(management_actions(state, player))
        actions.concat(trade_actions(state, player)) if include_trade_offers
        actions << { "kind" => "command", "action" => "pay_jail" } if state[:jail][player].to_i > 0 && state[:cash][player] >= board_payment(state, 50)
        actions << { "kind" => "command", "action" => "use_jail_card" } if state[:jail_cards][player].to_i > 0 && state[:jail][player].to_i > 0
        actions << { "kind" => "command", "action" => "bankrupt" } if state[:cash][player] < 0
      when :property_decision
        square = current_square(state, player)
        actions << { "kind" => "command", "action" => "buy" } if state[:cash][player] >= square[:price].to_i
        actions << { "kind" => "command", "action" => "decline" }
      when :turn_complete
        actions.concat(management_actions(state, player))
        actions.concat(trade_actions(state, player)) if include_trade_offers
        actions << { "kind" => "command", "action" => "bankrupt" } if state[:cash][player] < 0
      when :auction
        amount = state[:auction_bid].to_i + auction_increment(state)
        actions << { "kind" => "command", "action" => "auction_bid", "amount" => amount } if state[:cash][player] >= amount
        actions << { "kind" => "command", "action" => "auction_pass" }
      when :rent_decision
        actions << { "kind" => "command", "action" => "request_rent" }
        actions << { "kind" => "command", "action" => "waive_rent" }
      when :trade_response
        actions << { "kind" => "command", "action" => "trade_accept" } if valid_trade_offer?(state)
        actions << { "kind" => "command", "action" => "trade_reject" }
      end
      actions
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?
      action = selection["action"].to_s
      if action == "bankrupt_auto"
        return [:invalid, nil] if !same_user?(actor, replay.players.first) || !unavoidable_bankruptcy?(state)
        return [:ok, event_plan(action, "#{player_index(state[:players], state[:current_player])}|#{state[:turn_number]}")]
      end
      if action == "auction_timeout"
        return [:invalid, nil] if state[:phase] != :auction || !automatic_action_due?(replay, actor, context: context)
        value = [state[:auction_turn], player_index(state[:players], state[:current_player]), state[:auction_deadline], context.now.to_i].join("|")
        return [:ok, event_plan("auction_timeout", value)]
      end
      return [:not_your_turn, nil] if !same_user?(state[:current_player], actor)
      if action == "auction_bid"
        amount = Integer(selection["amount"].to_s, 10)
        return [:invalid_auction_bid, nil] if state[:phase] != :auction || amount <= state[:auction_bid] || amount > state[:cash][player_key(state, actor)]
        return [:ok, event_plan(action, "#{amount}|#{auction_action_time(context, state)}")]
      end
      if action == "trade_offer"
        return [:invalid, nil] if ![:awaiting_roll, :turn_complete].include?(state[:phase])
        value = selection["offer"].to_s
        if value.empty?
          value = encode_trade_offer(
            target: Integer(selection["target"].to_s, 10),
            give_properties: selection["give_properties"],
            receive_properties: selection["receive_properties"],
            give_cash: Integer(selection["give_cash"].to_s, 10),
            receive_cash: Integer(selection["receive_cash"].to_s, 10)
          )
        end
        offer = parse_trade_offer(state, value)
        return [:invalid_trade, nil] if offer == nil
        offer[:from] = player_key(state, actor)
        return [:empty_trade, nil] if empty_trade_offer?(offer)
        return [:invalid_trade, nil] if !valid_trade_offer?(state, offer)
        return [:ok, event_plan("trade_offer", value)]
      end
      if action == "trade_prepare"
        return [:invalid_trade, nil] if ![:awaiting_roll, :turn_complete].include?(state[:phase])
        target_index = Integer(selection["target"].to_s, 10)
        target = state[:players][target_index]
        player = player_key(state, actor)
        return [:invalid_trade, nil] if target == nil || same_user?(target, player) || !active_players(state).include?(target)
        return [:ok, event_plan("trade_prepare", target_index.to_s(36))]
      end
      if action == "roll"
        deficit = -state[:cash][player_key(state, actor)].to_i
        return [("insolvent_#{deficit}").to_sym, nil] if deficit > 0
        return [:invalid, nil] if state[:phase] != :awaiting_roll || context&.random_source == nil
        dice = context.random_source.roll(count: 2, sides: 6).values.map(&:to_i)
        return [:invalid, nil] if dice.length != 2
        seed = card_seed(context.random_source)
        return [:ok, event_plan("roll", "#{dice[0]},#{dice[1]},#{seed}")]
      end
      legal = legal_actions(replay, actor, context: context)
      candidate = legal.find do |item|
        item["action"] == action && (selection["property"].to_s.empty? || item["property"].to_s == selection["property"].to_s) &&
          (action != "auction_bid" || item["amount"].to_i == selection["amount"].to_i) &&
          (action != "trade_offer" || item["offer"].to_s == selection["offer"].to_s)
      end
      return [:invalid, nil] if candidate == nil
      value = if %w[build sell mortgage unmortgage].include?(action)
        candidate["property"].to_s
      elsif action == "auction_bid"
        candidate["amount"].to_i.to_s
      elsif action == "trade_offer"
        candidate["offer"].to_s
      elsif %w[decline auction_pass].include?(action)
        auction_action_time(context, state).to_s
      else ""
      end
      [:ok, event_plan(action, value)]
    rescue ArgumentError, TypeError
      [:invalid, nil]
    end

    private

    def initial_state(players, options)
      board_data = GameRoomContent::MonopolyBoards.build(options["board"])
      { players: players, options: options, board_data: board_data, board: board_data[:squares],
        current_player: players.first, phase: :awaiting_roll, positions: players.to_h { |player| [player, 0] },
        laps: players.to_h { |player| [player, 0] }, cash: players.to_h { |player| [player, board_data[:starting_cash]] },
        owners: {}, houses: Hash.new(0), mortgaged: {}, jail: Hash.new(0), jail_cards: Hash.new(0),
        bankrupt: players.to_h { |player| [player, false] }, doubles: 0, extra_turn: false,
        last_roll: 0,
        jackpot: 0, auction_square: nil, auction_bid: 0, auction_leader: nil, auction_passed: {}, auction_deadline: 0, auction_turn: 0,
        auction_origin: nil, rent_payer: nil, rent_owner: nil, rent_amount: 0,
        rent_origin: nil, trade_offer: nil, trade_phase: nil, winner: nil,
        debts: {}, card_decks: nil, held_jail_cards: {}, rejected_trades: {},
        turn_number: 0, trade_offered_turn: {}, trade_target_turn: {} }
    end

    def apply_roll(state, event, actor, repository, history)
      return false if state[:phase] != :awaiting_roll || !same_user?(state[:current_player], actor)
      first_text, second_text, seed = event["value"].to_s.split(",", 3)
      first, second = Integer(first_text, 10), Integer(second_text, 10)
      return false if !first.between?(1, 6) || !second.between?(1, 6) || seed.to_s !~ /\A(?:[0-9a-f]{32}|[1-9]|1[0-6])\z/
      player = player_key(state, actor)
      return false if state[:cash][player] < 0
      initialize_card_decks(state, seed) if state[:card_decks] == nil
      state[:roll_seed] = seed
      id = repository.event_id(event)
      state[:extra_turn] = first == second
      state[:doubles] = first == second ? state[:doubles] + 1 : 0
      state[:last_roll] = first + second
      history << HistoryEntry.new(key: "roll:#{id}", text: _("%{player} rolled %{first} and %{second}.") % { player: participant_name(player), first: first, second: second }, event_id: id, actor: actor, kind: :roll)
      if state[:jail][player] > 0
        state[:extra_turn] = false
        state[:doubles] = 0
        if first == second
          state[:jail][player] = 0
          history << HistoryEntry.new(key: "jail_release:#{id}", text: _("%{player} rolled doubles and left jail.") % { player: participant_name(player) }, event_id: id, actor: actor, kind: :game)
        else
          state[:jail][player] -= 1
          if state[:jail][player] > 0
            state[:phase] = :turn_complete
            history << HistoryEntry.new(key: "jail_wait:#{id}", text: _("%{player} remains in jail.") % { player: participant_name(player) }, event_id: id, actor: actor, kind: :game)
            return true
          end
          text = pay_and_describe(state, player, bank_recipient(state), board_payment(state, 50), _("release from jail"))
          history << HistoryEntry.new(key: "jail_payment:#{id}", text: text, event_id: id, actor: player, kind: :game)
        end
      end
      if state[:doubles] >= 3
        send_to_jail(state, player)
        state[:phase] = :turn_complete
        history << HistoryEntry.new(key: "triple:#{id}", text: _("%{player} rolled three doubles and goes to jail.") % { player: participant_name(player) }, event_id: id, actor: actor, kind: :game)
        return true
      end
      movement_effects = []
      move_player(state, player, first + second, id, movement_effects)
      history << HistoryEntry.new(key: "move:#{id}", text: _("%{player} lands on %{square}.") % { player: participant_name(player), square: current_square(state, player)[:name] }, event_id: id, actor: player, kind: :game)
      history.concat(movement_effects)
      if first == 1 && second == 1 && state[:options]["lucky_double_one"]
        bonus = board_payment(state, 50)
        state[:cash][player] += bonus
        history << HistoryEntry.new(key: "lucky:#{id}", text: _("%{player} receives %{amount} for lucky double one.") % { player: participant_name(player), amount: bonus }, event_id: id, actor: player, kind: :game)
      end
      resolve_square(state, player, id, history)
      true
    rescue ArgumentError
      false
    end

    def advance_completed_turn(state)
      return if state[:winner] || state[:phase] == :finished
      # A new debt ends this turn, not the next player's turn. Resolution is
      # available in the debtor's next awaiting_roll phase; roll validates cash.
      if state[:phase] == :property_decision && state[:cash][state[:current_player]].to_i < 0
        state[:phase] = :turn_complete
      end
      return if state[:phase] != :turn_complete || state[:current_player] == nil

      actor = state[:current_player]
      if state[:cash][actor].to_i >= 0 && state[:extra_turn] && state[:jail][player_key(state, actor)].zero?
        state[:phase] = :awaiting_roll
        state[:extra_turn] = false
      else
        state[:turn_number] += 1
        state[:current_player] = next_active_player(state, actor)
        state[:phase] = :awaiting_roll
        state[:doubles] = 0
        state[:extra_turn] = false
      end
    end

    def current_square(state, player)
      key = player_key(state, player) || player
      state[:board][state[:positions][key].to_i]
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def active_players(state)
      state[:players].reject { |player| state[:bankrupt][player] }
    end

    def next_active_player(state, actor)
      index = player_index(state[:players], actor)
      state[:players].length.times do
        index = (index + 1) % state[:players].length
        return state[:players][index] if !state[:bankrupt][state[:players][index]]
      end
      actor
    end

    def money(state, amount)
      amount * state[:board_data].fetch(:money_factor)
    end

    def board_payment(state, amount)
      # Reference 40-square salary is 200. Use the selected board's salary
      # for unverified flat fees/prizes, rounding half up in integer units.
      (amount * state[:board_data].fetch(:salary) + 100) / 200
    end

    TRADE_OFFER_VERSION = "2".freeze
    TRADE_CASH_LIMIT = 99_999_999

  end
end

require_relative "monopoly/trading"

require_relative "monopoly/property_management"

require_relative "monopoly/debt"

require_relative "monopoly/auction"

require_relative "monopoly/board_events"

require_relative "monopoly/evaluation"

require_relative "monopoly/presentation"

require_relative 'generated/rulebooks/monopoly'
