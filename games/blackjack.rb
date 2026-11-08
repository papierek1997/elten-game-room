require_relative "card_game"
require_relative "../lib/game_bots"
require_relative "../lib/blackjack_auction"
require_relative "../lib/blackjack_social"

module GameRoomGames
  using GameRoomLocalization::Translations

  class Blackjack < CardGame
    include PublicHistoryAnnouncements
    include BlackjackAuction
    include BlackjackSocial
    GameRoomServerRandom.register("blackjack", ["deal"])

    def id; "blackjack"; end
    def name; _("Blackjack"); end
    def short_description; _("Beat the automatic dealer without exceeding 21; play with virtual table chips."); end
    def minimum_players; 2; end
    def maximum_players; 6; end
    def supports_bots?; true; end
    def bot_strategy; @bot_strategy ||= GameRoomBots::HeuristicStrategy.new; end
    def rule_sections; generated_rule_sections; end
    def player_spatial_audio?; true; end

    def option_definitions
      [
        OptionDefinition.new(key: "variant", label: _("Variant"), kind: :choice, default: "simple", choices: [
          OptionChoice.new(value: "simple", label: _("Simple: hit and stand")),
          OptionChoice.new(value: "extended", label: _("Extended: double and split")),
          OptionChoice.new(value: "social", label: _("Social blackjack: rotating dealer, no house hand"))
        ]),
        OptionDefinition.new(key: "round_limit", label: _("Number of rounds"), kind: :integer, default: 10),
        OptionDefinition.new(key: "starting_chips", label: _("Starting chips"), kind: :integer, default: 100),
        OptionDefinition.new(key: "stake", label: _("Opening contribution"), kind: :integer, default: 10)
      ]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _("This blackjack betting version is not supported.") if values.key?("blackjack_betting_version") && ![1, 2].include?(values["blackjack_betting_version"])
      return _("Social blackjack requires the current betting rules.") if values['variant'] == 'social' && values['blackjack_betting_version'] != 2
      return _("Choose a supported blackjack variant.") unless %w[simple extended social].include?(values["variant"])
      return _("The number of rounds must be from 1 to 100.") unless values["round_limit"].is_a?(Integer) && values["round_limit"].between?(1, 100)
      return _("Starting chips must be from 10 to 10000.") unless values["starting_chips"].is_a?(Integer) && values["starting_chips"].between?(10, 10_000)
      return _("The stake must be positive and cannot exceed starting chips.") unless values["stake"].is_a?(Integer) && values["stake"].between?(1, values["starting_chips"])
      nil
    end

    def normalize_options(values)
      result = super
      source = values.is_a?(Hash) ? values : {}
      version = source.fetch("blackjack_betting_version") { source[:blackjack_betting_version] }
      result["blackjack_betting_version"] = GameRoomOptionValues.integer_value(version) if source.key?("blackjack_betting_version") || source.key?(:blackjack_betting_version)
      result["blackjack_betting_version"] = 2 if result["variant"] == "social" && !result.key?("blackjack_betting_version")
      result
    end

    def new_game_options(values); normalize_options(values).merge("blackjack_betting_version" => 2); end

    def notification_option_keys(_options); %w[variant round_limit starting_chips stake]; end
    # Half-chip units retain exact 3:2 payouts, even for an odd stake.
    def participant_scores(replay); replay.state[:chips].transform_values { |chips| chips / 2.0 }; end
    def eliminated_from_game?(replay, viewer)
      player = replay.players.find { |person| same_user?(person, viewer) }
      player && replay.state[:eliminated].include?(player)
    end

    def hand_total(cards)
      values = cards.map { |card| card_points(card) }
      total = values.sum
      values.count(11).times { total -= 10 if total > 21 }
      total
    end

    def natural?(hand)
      !hand[:split] && hand[:cards].size == 2 && hand_total(hand[:cards]) == 21
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished? || !same_user?(actor, replay.players.first)
      return nil if social?(replay.state) && replay.state[:phase] == :awaiting_deal
      action = {awaiting_ante: "ante", awaiting_deal: "deal", dealer: "dealer"}[replay.state[:phase]]
      {"kind" => "command", "action" => action} if action
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if replay.finished? || !same_user?(replay.current_player, actor)
      return auction_actions(replay, actor) if state[:phase] == :betting && auction_rules?(state[:options])
      return [{"kind"=>"command","action"=>"deal"}] if social?(state) && state[:phase] == :awaiting_deal
      if state[:phase] == :betting
        maximum = maximum_bet(state)
        return [1, default_bet(state), maximum / 2, maximum].select(&:positive?).uniq.sort.map do |amount|
          {"kind" => "command", "action" => "bet", "amount" => amount}
        end
      end
      return [] unless state[:phase] == :playing
      hand = current_hand(state)
      actions = %w[hit stand]
      if state[:options]["variant"] == "extended" && !hand[:split] && hand[:cards].size == 2 && state[:chips][state[:current_player]] >= hand[:bet]
        actions << "double"
        actions << "split" if playing_card_rank(hand[:cards][0]) == playing_card_rank(hand[:cards][1])
      end
      actions.map { |action| {"kind" => "command", "action" => action} }
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      state = replay.state
      action = selection["action"].to_s
      action = selection["card"].to_s if selection["kind"] == "card" && selection["zone"] == "actions" && action == "select"
      if %w[ante deal dealer].include?(action)
        if social?(state) && action == "deal"
          return [:invalid,nil] unless state[:phase] == :awaiting_deal && same_user?(actor,state[:dealing_player]) && context&.random_source
          template = "#{state[:round]+1}|{seed}"
          return [:ok,server_seed_plan("deal",template:template)] if context.server_random
          return [:ok,event_plan("deal","#{state[:round]+1}|#{card_seed(context.random_source)}")]
        end
        expected = automatic_action(replay, actor, context: context)
        return [:invalid, nil] unless expected && expected["action"] == action
        return [:ok, event_plan(action, "")] if %w[ante dealer].include?(action)
        return [:invalid, nil] unless context&.random_source
        template = "#{state[:round] + 1}|{seed}"
        return [:ok, server_seed_plan("deal", template: template)] if context.server_random
        return [:ok, event_plan("deal", "#{state[:round] + 1}|#{card_seed(context.random_source)}")]
      end
      return [:not_your_turn, nil] unless same_user?(replay.current_player, actor)
      return auction_plan(selection, replay) if state[:phase] == :betting && auction_rules?(state[:options])
      if state[:phase] == :betting
        name, preset = action.split(":", 2)
        amount = preset || selection["amount"]
        return [:invalid, nil] unless name == "bet" && valid_bet?(state, amount)
        return [:ok, event_plan("bet", amount.to_s)]
      end
      return [:invalid, nil] unless legal_actions(replay, actor).any? { |item| item["action"] == action }
      [:ok, event_plan(action, "")]
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      options = options_from_json(session["options"])
      state = {players: players, options: options, round: 0, chips: players.to_h { |person| [person, options["starting_chips"] * 2] },
        hands: {}, dealer: [], deck: [], eliminated: [], hand_index: 0, current_player: players.first,
        phase: :awaiting_deal, winner: nil, draw: false}
      prepare_betting(state) if options["blackjack_betting_version"] == 1
      prepare_auction(state) if auction_rules?(options)
      history, accepted, seen = [starting_history(players)], [], {}
      events.each do |event|
        break if state[:phase] == :finished
        event_id = repository.event_id(event)
        next if seen[event_id]
        actor = repository.actor_of(event, session)
        next unless apply_event(state, event, actor, event_id, history)
        accepted << event
        seen[event_id] = true
      end
      Replay.new(board: nil, players: players, current_player: state[:current_player], winner: state[:winner], draw: state[:draw],
        accepted_events: accepted, history: history, state: state)
    end

    def bot_observation(replay, actor)
      state = replay.state
      hand = same_user?(state[:current_player], actor) && state[:phase] == :playing ? current_hand(state) : nil
      {"cards" => hand ? hand[:cards].dup : [], "total" => hand ? hand_total(hand[:cards]) : 0,
        "dealer_upcard" => state[:dealer].first, "round" => state[:round]}
    end

    def bot_action_score(replay, actor, action, context: nil)
      return %w[check call].include?(action["action"]) ? 100 : 0 if replay.state[:phase] == :betting && auction_rules?(replay.state[:options])
      return -(action["amount"].to_i - default_bet(replay.state)).abs if replay.state[:phase] == :betting
      return 100 if social?(replay.state) && action["action"] == "deal"
      if social?(replay.state)
        return action["action"] == (hand_total(current_hand(replay.state)[:cards]) < 17 ? "hit" : "stand") ? 100 : 0
      end
      observation = bot_observation(replay, actor)
      cards, total = observation.values_at("cards", "total")
      upcard = card_points(observation["dealer_upcard"])
      preferred = if cards.size == 2 && %w[A 8].include?(playing_card_rank(cards[0])) && playing_card_rank(cards[0]) == playing_card_rank(cards[1])
        "split"
      elsif cards.size == 2 && [10, 11].include?(total) && upcard < 10
        "double"
      elsif total < 12 || (total < 17 && upcard >= 7)
        "hit"
      else
        "stand"
      end
      return 100 if action["action"] == preferred
      action["action"] == (total < 17 ? "hit" : "stand") ? 10 : 0
    end

    def playable_card_navigation(replay, viewer)
      # These cards are inspected, never played individually.
      card_navigation_spec(hand_id: "hand", card_actions: {}) if displayed_hand(replay.state, viewer)
    end

    def required_decision_key(replay, viewer)
      return nil unless replay && [:betting, :playing].include?(replay.state[:phase])
      key = super
      key && (replay.state.key?(:bets) || auction_rules?(replay.state[:options])) ? [key, replay.state[:round], replay.state[:phase]] : key
    end

    def surface_spec(replay, viewer)
      state = replay.state
      return auction_surface(replay, viewer) if state[:phase] == :betting && auction_rules?(state[:options])
      if state[:phase] == :betting
        actions = legal_actions(replay, viewer).map do |action|
          GameSurfaces::Card.new(id: "bet:#{action['amount']}", value: "bet:#{action['amount']}",
            label: _("Bet %{chips} chips") % {chips: action["amount"]})
        end
        header = _("Place your bet before the deal (maximum %{maximum})") % {maximum: maximum_bet(state)}
        return GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(id: "actions", header: header,
          cards: actions, empty_label: current_turn_shortcut_text(replay, viewer))])
      end
      hand = displayed_hand(state, viewer)
      zones = []
      if hand
        player = replay.players.find { |person| same_user?(person, viewer) }
        index = state[:hands].fetch(player).index(hand)
        header = _("Your hand %{hand} of %{count}: %{total}") % {hand: index + 1, count: state[:hands].fetch(player).size, total: hand_total(hand[:cards])}
        zones.concat(card_hand_surface(hand[:cards], header: header, hand_epoch: [state[:round], player.to_s.downcase, index]).zones)
      end
      labels = {"hit" => _("Hit"), "stand" => _("Stand"), "double" => _("Double down"), "split" => _("Split pair"), "deal"=>_("Deal cards")}
      actions = legal_actions(replay, viewer).map do |action|
        GameSurfaces::Card.new(id: action["action"], value: action["action"], label: labels.fetch(action["action"]))
      end
      public_dealer = state[:dealer_revealed] ? state[:dealer] : state[:dealer].take(1)
      dealer_text = public_dealer.map { |card| playing_card_label(card) }.join(", ")
      dealer_text += ", " + _("hidden card") if !state[:dealer_revealed] && state[:dealer].size > 1
      header = _("Dealer: %{cards}") % {cards: dealer_text}
      header = _("Dealing player: %{player}; no house hand.") % {player:participant_name(state[:dealing_player])} if social?(state)
      zones << GameSurfaces::CardZoneSpec.new(id: "actions", header: header, cards: actions,
        empty_label: result_text(replay) || current_turn_shortcut_text(replay, viewer))
      GameSurfaces::CardTableSpec.new(zones: zones)
    end

    def custom_game_shortcuts(replay, viewer)
      if social?(replay.state) && replay.state[:phase] == :awaiting_deal && same_user?(replay.current_player,viewer)
        return [GameShortcut.new(key:"d",label:_("deal the next social blackjack hand"),kind: :action,action_kind:"command",action_name:"deal")]
      end
      return auction_shortcuts(replay, viewer) if replay.state[:phase] == :betting && auction_rules?(replay.state[:options])
      return [] unless replay.state[:phase] == :betting && same_user?(replay.current_player, viewer)
      maximum = maximum_bet(replay.state)
      [GameShortcut.new(key: "b", label: _("set your bet before the deal"), kind: :number_input,
        prompt: _("Your bet (1 to %{maximum})") % {maximum: maximum}, action_kind: "command", action_name: "bet",
        value_key: "amount", allowed_values: 1..maximum, default_value: default_bet(replay.state),
        invalid_message: _("Choose a whole-chip bet within your balance."))]
    end

    def shortcut_features; super + [:scores, :hand]; end
    def shortcut_feature_data(feature, replay, viewer)
      case feature.to_sym
      when :scores
        {message: participant_scores(replay).map { |person, score| "#{participant_name(person)}: #{score}" }.join("; ")}
      when :hand
        hand = displayed_hand(replay.state, viewer)
        {message: hand ? hand[:cards].map { |card| playing_card_label(card) }.join(", ") : _("Your hand is empty")}
      else super
      end
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      cues = []
      cues << "shuffle" if event["action"] == "deal"
      cues << "draw" if %w[hit double split dealer].include?(event["action"])
      cues << "lose1" if history.any? { |entry| entry.kind == :bust && same_user?(entry.actor, viewer) }
      cues
    end

    protected

    def playing_card_rank(card); card.to_s.split(":").last.to_s[0]; end
    def playing_card_suit(card); card.to_s.split(":").last.to_s[1]; end

    private

    def auction_unit; 2; end

    def prepare_auction(state)
      state.delete(:auction)
      state.merge!(phase: :awaiting_ante, hands: {}, dealer: [], deck: [], dealer_revealed: false,
        hand_index: 0, current_player: state[:players].first)
      if social?(state)
        offset = state[:dealing_player] ? state[:players].index(state[:dealing_player]) + 1 : 0
        state[:dealing_player] = state[:players].rotate(offset).find { |p| !state[:eliminated].include?(p) }
      end
    end

    def complete_auction(state, event_id, history)
      if social?(state) && auction_contenders(state).one?
        state[:round] += 1
        social_settle(state, event_id, history, uncontested: true)
      else
        state.merge!(phase: :awaiting_deal, current_player: social?(state) ? state[:dealing_player] : state[:players].first)
      end
    end

    def card_points(card)
      rank = playing_card_rank(card)
      return 11 if rank == "A"
      %w[T J Q K].include?(rank) ? 10 : rank.to_i
    end

    def current_hand(state); state[:hands].fetch(state[:current_player])[state[:hand_index]]; end

    def displayed_hand(state, viewer)
      player = state[:players].find { |person| same_user?(person, viewer) }
      hands = state[:hands][player]
      return nil unless hands
      hands[same_user?(state[:current_player], viewer) ? state[:hand_index] : 0]
    end

    def add_history(history, event_id, actor, kind, text)
      history << HistoryEntry.new(key: "#{kind}:#{event_id}:#{history.size}", event_id: event_id, actor: actor, kind: kind, text: text)
    end

    def maximum_bet(state); state[:chips].fetch(state[:current_player]) / 2; end
    def default_bet(state); [state[:options]["stake"], maximum_bet(state)].min; end
    def valid_bet?(state, amount)
      amount.to_s.length <= maximum_bet(state).to_s.length && amount.to_s.match?(/\A[1-9][0-9]*\z/) && amount.to_i.between?(1, maximum_bet(state))
    end

    def prepare_betting(state)
      state.merge!(phase: :betting, bets: {}, hands: {}, dealer: [], deck: [], dealer_revealed: false,
        hand_index: 0, current_player: state[:players].find { |person| !state[:eliminated].include?(person) })
    end

    def apply_event(state, event, actor, event_id, history)
      action = event["action"].to_s
      if action == "ante"
        return false unless auction_rules?(state[:options]) && state[:phase] == :awaiting_ante && same_user?(actor, state[:players].first) && event["value"].to_s.empty?
        start_auction(state, state[:players] - state[:eliminated], event_id, history)
      elsif action == "bet" && auction_rules?(state[:options])
        return apply_auction(state, event, actor, event_id, history)
      elsif action == "bet"
        return false unless state[:phase] == :betting && same_user?(actor, state[:current_player]) && valid_bet?(state, event["value"])
        player = state[:current_player]
        amount = event["value"].to_i
        state[:bets][player] = amount * 2
        state[:chips][player] -= amount * 2
        add_history(history, event_id, player, :bet, _("%{player} bet %{chips} chips.") % {player: participant_name(player), chips: amount})
        following = state[:players].find { |person| !state[:eliminated].include?(person) && !state[:bets].key?(person) }
        state.merge!(phase: following ? :betting : :awaiting_deal, current_player: following || state[:players].first)
      elsif action == "deal"
        return false unless state[:phase] == :awaiting_deal && same_user?(actor, social?(state) ? state[:dealing_player] : state[:players].first)
        template = "#{state[:round] + 1}|{seed}"
        seed = GameRoomServerRandom.text_seed_value(event, template: template)
        return false unless seed
        deal(state, seed, event_id, history)
      elsif action == "dealer"
        return false unless state[:phase] == :dealer && same_user?(actor, state[:players].first) && event["value"].to_s.empty?
        settle(state, event_id, history)
      else
        return false unless state[:phase] == :playing && same_user?(actor, state[:current_player]) && event["value"].to_s.empty?
        replay = Replay.new(players: state[:players], current_player: state[:current_player], state: state, draw: false)
        return false unless legal_actions(replay, actor).any? { |item| item["action"] == action }
        play(state, action, event_id, history)
      end
      true
    end

    def deal(state, seed, event_id, history)
      return social_deal(state,seed,event_id,history) if social?(state)
      state[:round] += 1
      state[:hands] = {}
      state[:dealer] = []
      state[:dealer_revealed] = false
      deck = 6.times.flat_map { |index| standard_deck.map { |card| "#{index}:#{card}" } }
      state[:deck] = shuffled_cards(deck, seed)
      state[:players].each do |person|
        if state.key?(:auction)
          bet = state[:auction][:contributions][person]
          state[:hands][person] = [{cards: [], bet: bet, split: false, done: false}] if bet && !state[:auction][:folded][person]
        elsif state.key?(:bets)
          bet = state[:bets][person]
          state[:hands][person] = [{cards: [], bet: bet, split: false, done: false}] if bet
        elsif state[:chips][person] >= state[:options]["stake"] * 2
          bet = state[:options]["stake"] * 2
          state[:chips][person] -= bet
          state[:hands][person] = [{cards: [], bet: bet, split: false, done: false}]
        else
          state[:eliminated] << person unless state[:eliminated].include?(person)
        end
      end
      2.times do
        state[:hands].each_value { |hands| hands.first[:cards] << state[:deck].shift }
        state[:dealer] << state[:deck].shift
      end
      state[:hands].each_value { |hands| hands.first[:done] = natural?(hands.first) }
      state.merge!(phase: :playing, current_player: state[:hands].keys.first, hand_index: 0)
      add_history(history, event_id, "", :deal,
        _("Round %{round}. Dealer shows %{card}.") % {round: state[:round], card: playing_card_label(state[:dealer].first)})
      # A dealer natural ends the round before any optional extra stake.
      if hand_total(state[:dealer]) == 21
        state[:hands].each_value { |hands| hands.each { |hand| hand[:done] = true } }
      end
      advance_hand(state)
    end

    def play(state, action, event_id, history)
      actor = state[:current_player]
      hand = current_hand(state)
      case action
      when "stand" then hand[:done] = true
      when "hit", "double"
        if action == "double"
          state[:chips][actor] -= hand[:bet]
          hand[:bet] *= 2
        end
        hand[:cards] << state[:deck].shift
        hand[:done] = action == "double" || hand_total(hand[:cards]) >= 21
      when "split"
        state[:chips][actor] -= hand[:bet]
        first, second = hand[:cards]
        hands = [first, second].map do |card|
          cards = [card, state[:deck].shift]
          {cards: cards, bet: hand[:bet], split: true, done: playing_card_rank(card) == "A" || hand_total(cards) >= 21}
        end
        state[:hands][actor] = hands
        hand = hands.first
      end
      total = hand_total(hand[:cards])
      add_history(history, event_id, actor, total > 21 ? :bust : :move,
        _("%{player}: %{action}; total %{total}.") % {player: participant_name(actor), action: action_label(action), total: total})
      advance_hand(state)
    end

    def action_label(action)
      {"hit" => _("Hit"), "stand" => _("Stand"), "double" => _("Double down"), "split" => _("Split pair")}.fetch(action)
    end

    def advance_hand(state)
      state[:hands].each do |player, hands|
        index = hands.index { |hand| !hand[:done] }
        if index
          state.merge!(current_player: player, hand_index: index)
          return
        end
      end
      state.merge!(phase: :dealer, current_player: state[:players].first, hand_index: 0)
    end

    def settle(state, event_id, history)
      return social_settle(state,event_id,history) if social?(state)
      state[:dealer_revealed] = true
      live = state[:hands].values.flatten.any? { |hand| hand_total(hand[:cards]) <= 21 && !natural?(hand) }
      state[:dealer] << state[:deck].shift while live && hand_total(state[:dealer]) < 17
      dealer = hand_total(state[:dealer])
      dealer_natural = state[:dealer].size == 2 && dealer == 21
      add_history(history, event_id, "", :dealer,
        _("Dealer: %{cards}; total %{total}.") % {cards: state[:dealer].map { |card| playing_card_label(card) }.join(", "), total: dealer})
      state[:hands].each do |person, hands|
        hands.each do |hand|
          total = hand_total(hand[:cards])
          payout = if total > 21
            0
          elsif dealer_natural
            natural?(hand) ? hand[:bet] : 0
          elsif natural?(hand)
            state.key?(:auction) ? hand[:bet] * Rational(5, 2) : hand[:bet] * 5 / 2
          elsif dealer > 21 || total > dealer
            hand[:bet] * 2
          elsif total == dealer
            hand[:bet]
          else
            0
          end
          state[:chips][person] += payout
        end
        add_history(history, event_id, person, :settlement,
          _("%{player} has %{chips} chips.") % {player: participant_name(person), chips: state[:chips][person] / 2.0})
      end
      minimum = state.key?(:auction) ? 0 : state.key?(:bets) ? 2 : state[:options]["stake"] * 2
      state[:eliminated] = state[:players].select { |person| state[:chips][person].zero? || state[:chips][person] < minimum }
      if state[:round] >= state[:options]["round_limit"] || state[:eliminated].size == state[:players].size
        highest = state[:chips].values.max
        winners = state[:players].select { |person| state[:chips][person] == highest }
        state.merge!(phase: :finished, current_player: nil, winner: winners.size == 1 ? winners.first : nil, draw: winners.size != 1)
        history << result_history(event_id: event_id, winner: state[:winner], draw: state[:draw])
      else
        if state.key?(:auction)
          prepare_auction(state)
        elsif state.key?(:bets)
          prepare_betting(state)
        else
          state.merge!(phase: :awaiting_deal, current_player: state[:players].first)
        end
      end
    end
  end
end

require_relative "generated/rulebooks/blackjack"
