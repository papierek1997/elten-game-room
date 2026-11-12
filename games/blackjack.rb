require_relative "card_game"
require_relative "base/round_tournament"
require_relative "../lib/game_bots"
require_relative "../lib/blackjack_auction"
require_relative "../lib/blackjack_social"
require_relative "../lib/twenty_one_strategy"

module GameRoomGames
  using GameRoomLocalization::Translations

  class Blackjack < CardGame
    include PublicHistoryAnnouncements
    include BlackjackAuction
    include BlackjackSocial
    include RoundTournament
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

    def effective_option_definitions(options = {})
      betting_version_definitions(super, options)
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
      super || (player && replay.state[:eliminated].include?(player))
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
      if GameRoomTournamentMarker.present?(session) && !options.key?("blackjack_betting_version")
        options = new_game_options(options)
      end
      state = {players: players, options: options, round: 0, chips: players.to_h { |person| [person, options["starting_chips"] * 2] },
        hands: {}, dealer: [], deck: [], eliminated: [], hand_index: 0, current_player: players.first,
        phase: :awaiting_deal, winner: nil, draw: false}
      enable_round_tournament(state, session)
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
      state = replay.state
      return auction_opening_bot_score(state, action) if state[:phase] == :betting && auction_rules?(state[:options])
      return -(action["amount"].to_i - default_bet(state)).abs if state[:phase] == :betting
      return 1 if action["action"] == "deal"

      observation = bot_observation(replay, actor)
      values = observation["cards"].map { |card| bot_card_value(card) }
      hard, ace = values.sum, values.include?(1)
      plan = blackjack_bot_plan(state, observation)
      case action["action"]
      when "stand" then plan.stand(hard, ace) + 1e-9
      when "hit" then plan.draw(hard, ace)
      when "double" then 2 * plan.draw(hard, ace, stop: true)
      when "split" then 2 * plan.draw(values.first, ace, stop: ace)
      end
    end

    def playable_card_navigation(replay, viewer)
      # These cards are inspected, never played individually.
      card_navigation_spec(hand_id: "hand", card_actions: {}) if displayed_hand(replay.state, viewer)
    end

    def turn_announcement(replay, viewer)
      if replay && social?(replay.state) && replay.state[:phase] == :awaiting_deal
        return _("Deal the cards with D.") if same_user?(replay.current_player, viewer)
        return _("%{player} will deal the cards.") % {player: participant_name(replay.current_player)}
      end
      super
    end

    def current_turn_shortcut_text(replay, viewer)
      return turn_announcement(replay, viewer) if social?(replay.state) && replay.state[:phase] == :awaiting_deal

      super
    end

    def describe_event(event, repository, replay, viewer)
      return super unless event["action"] == "deal"

      event_id = repository.event_id(event).to_i
      replay.history.filter_map do |entry|
        next unless entry.event_id.to_i == event_id
        entry.text if %i[deal initial_twenty_one].include?(entry.kind) ||
          (entry.kind == :dealt_hand && same_user?(entry.actor, viewer))
      end
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
        count, total = state[:hands].fetch(player).size, hand_total(hand[:cards])
        header = if count > 1
          _("Your hand %{hand} of %{count}: %{total}") % {hand: index + 1, count: count, total: total}
        else
          _("Your hand; total %{total}.") % {total: total}
        end
        zones.concat(card_hand_surface(hand[:cards], header: header, hand_epoch: [state[:round], player.to_s.downcase, index]).zones)
      end
      labels = {"hit" => _("Draw a card"), "stand" => _("Keep your total"), "double" => _("Double down"), "split" => _("Split pair"), "deal"=>_("Deal cards")}
      actions = legal_actions(replay, viewer).map do |action|
        GameSurfaces::Card.new(id: action["action"], value: action["action"], label: labels.fetch(action["action"]))
      end
      public_dealer = state[:dealer_revealed] ? state[:dealer] : state[:dealer].take(1)
      dealer_text = public_dealer.map { |card| playing_card_label(card) }.join(", ")
      dealer_text += ", " + _("hidden card") if !state[:dealer_revealed] && state[:dealer].size > 1
      header = dealer_text.empty? ? _("Blackjack actions") : _("Dealer: %{cards}") % {cards: dealer_text}
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

    def shortcut_features; super + [:scores, :hand, :draw_card]; end
    def shortcut_feature_data(feature, replay, viewer)
      case feature.to_sym
      when :scores
        {message: replay.state[:chips].map { |person, chips| "#{participant_name(person)}: #{auction_amount(chips)}" }.join("; ")}
      when :hand
        hand = displayed_hand(replay.state, viewer)
        {message: hand ? blackjack_hand_text(hand[:cards]) : _("Your hand is empty")}
      when :draw_card
        if replay.state[:phase] == :playing && !replay.finished? && same_user?(replay.current_player, viewer)
          {kind: :action, action_kind: "command", action_name: "hit"}
        end
      else super
      end
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      cues = auction_sound_cues(event, history)
      cues << "shuffle" if event["action"] == "deal"
      cues << "draw" if %w[hit double split].include?(event["action"]) ||
        history.any? { |entry| entry.kind == :dealer_draw }
      cues << "lose1" if history.any? { |entry| entry.kind == :bust && same_user?(entry.actor, viewer) }
      cues
    end

    protected

    def playing_card_rank(card); card.to_s.split(":").last.to_s[0]; end
    def playing_card_suit(card); card.to_s.split(":").last.to_s[1]; end

    private

    def auction_unit; 2; end

    def bot_card_value(card)
      points = card_points(card)
      points == 11 ? 1 : points
    end

    def blackjack_bot_plan(state, observation)
      if social?(state)
        completed = state[:hands].filter_map do |player, hands|
          [player, hand_total(hands.first[:cards])] if hands.first[:done]
        end.to_h
        stand_value, bust_value = GameRoomTwentyOneStrategy.pot_values(auction_pots(state),
          state[:current_player], completed, GameRoomTwentyOneStrategy.card_opponent)
        return GameRoomTwentyOneStrategy::Plan.new(stand_value, bust_value: bust_value) { GameRoomTwentyOneStrategy::CARDS }
      end
      upcard = bot_card_value(observation["dealer_upcard"])
      dealer = GameRoomTwentyOneStrategy.card_dealer(upcard)
      stand_value = lambda do |sum|
        dealer.sum do |score, probability|
          score == GameRoomTwentyOneStrategy::BUST || sum > score ? probability : (sum < score ? -probability : 0)
        end
      end
      GameRoomTwentyOneStrategy::Plan.new(stand_value, bust_value: -1) { GameRoomTwentyOneStrategy::CARDS }
    end

    def prepare_auction(state, rotate_dealer: true)
      state.delete(:auction)
      state.merge!(phase: :awaiting_ante, hands: {}, dealer: [], deck: [], dealer_revealed: false,
        hand_index: 0, current_player: state[:players].first)
      if social?(state)
        offset = state[:dealing_player] ? state[:players].index(state[:dealing_player]) + (rotate_dealer ? 1 : 0) : 0
        state[:dealing_player] = (state[:players].rotate(offset) & tournament_contenders(state)).first
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
        hand_index: 0, current_player: tournament_contenders(state).first)
    end

    def apply_event(state, event, actor, event_id, history)
      action = event["action"].to_s
      if action == "tournament_elimination"
        return apply_round_tournament_elimination(state, event, event_id, history) { restart_blackjack_round(state) }
      elsif action == "ante"
        return false unless auction_rules?(state[:options]) && state[:phase] == :awaiting_ante && same_user?(actor, state[:players].first) && event["value"].to_s.empty?
        start_auction(state, tournament_contenders(state), event_id, history)
      elsif action == "bet" && auction_rules?(state[:options])
        return apply_auction(state, event, actor, event_id, history)
      elsif action == "bet"
        return false unless state[:phase] == :betting && same_user?(actor, state[:current_player]) && valid_bet?(state, event["value"])
        player = state[:current_player]
        amount = event["value"].to_i
        state[:bets][player] = amount * 2
        state[:chips][player] -= amount * 2
        add_history(history, event_id, player, :bet, _("%{player} bet %{chips} chips.") % {player: participant_name(player), chips: amount})
        following = tournament_contenders(state).find { |person| !state[:bets].key?(person) }
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
      tournament_contenders(state).each do |person|
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
      announce_dealt_hands(state, event_id, history)
      # A dealer natural ends the round before any optional extra stake.
      if hand_total(state[:dealer]) == 21
        state[:hands].each_value { |hands| hands.each { |hand| hand[:done] = true } }
      end
      advance_hand(state)
    end

    def restart_blackjack_round(state)
      auction = state[:auction]
      original_stakes = auction ? auction[:contributions] : state[:bets] || {}
      # A split or double can commit more than the original stake.
      state[:hands].each do |player, hands|
        state[:chips][player] += hands.sum { |hand| hand[:bet] } - original_stakes.fetch(player, 0)
      end
      state[:round] -= 1 if %i[playing dealer].include?(state[:phase])
      if auction_rules?(state[:options])
        refund_interrupted_auction(state)
        prepare_auction(state, rotate_dealer: false)
      elsif state.key?(:bets)
        state[:bets].each { |player, paid| state[:chips][player] += paid }
        prepare_betting(state)
      else
        state.merge!(phase: :awaiting_deal, hands: {}, dealer: [], deck: [], dealer_revealed: false,
          hand_index: 0, current_player: state[:players].first)
      end
    end

    def play(state, action, event_id, history)
      actor = state[:current_player]
      hand = current_hand(state)
      player = participant_name(actor)
      text = case action
      when "stand"
        hand[:done] = true
        _("%{player} stands at %{total}.") % {player: player, total: hand_total(hand[:cards])}
      when "hit", "double"
        if action == "double"
          state[:chips][actor] -= hand[:bet]
          hand[:bet] *= 2
        end
        card = state[:deck].shift
        hand[:cards] << card
        total = hand_total(hand[:cards])
        hand[:done] = action == "double" || total >= 21
        format = action == "double" ? _("%{player} doubles the bet and draws %{card}. Total: %{total}.") :
          _("%{player} draws %{card}. Total: %{total}.")
        format % {player: player, card: playing_card_label(card), total: total}
      when "split"
        state[:chips][actor] -= hand[:bet]
        first, second = hand[:cards]
        hands = [first, second].map do |card|
          cards = [card, state[:deck].shift]
          {cards: cards, bet: hand[:bet], split: true, done: playing_card_rank(card) == "A" || hand_total(cards) >= 21}
        end
        state[:hands][actor] = hands
        hand = hands.first
        _("%{player} splits the pair. First hand: %{first} Second hand: %{second}") % {
          player: player, first: blackjack_hand_text(hands[0][:cards]), second: blackjack_hand_text(hands[1][:cards])}
      end
      bust = hand_total(hand[:cards]) > 21
      add_history(history, event_id, actor, bust ? :bust : :move, bust ? "#{text} #{_('Over 21.')}" : text)
      index = state[:hand_index]
      advance_hand(state)
      if state[:phase] == :playing && state[:current_player] == actor && state[:hand_index] != index
        add_history(history, event_id, actor, :move,
          _("%{player} plays the second hand.") % {player: player})
      end
    end

    def blackjack_hand_text(cards)
      _("%{cards}. Total: %{total}.") % {
        cards: cards.map { |card| playing_card_label(card) }.join(", "), total: hand_total(cards)}
    end

    def announce_dealt_hands(state, event_id, history)
      state[:hands].each do |player, hands|
        cards = hands.first[:cards]
        text = if hand_total(cards) == 21
          _("%{player} is dealt 21: %{cards}.") % {
            player: participant_name(player), cards: cards.map { |card| playing_card_label(card) }.join(", ")}
        else
          _("%{player} is dealt: %{hand}") % {player: participant_name(player), hand: blackjack_hand_text(cards)}
        end
        add_history(history, event_id, player, hand_total(cards) == 21 ? :initial_twenty_one : :dealt_hand, text)
      end
    end

    def blackjack_balance_text(player, changes, balance)
      outcomes = changes.map do |change|
        if change.positive?
          _("profit %{amount}") % {amount: auction_amount(change)}
        elsif change.negative?
          _("loss %{amount}") % {amount: auction_amount(-change)}
        else
          _("gets the stake back")
        end
      end
      outcome = if outcomes.one?
        outcomes.first
      else
        outcomes.each_with_index.map { |value, index| _("hand %{hand}: %{outcome}") % {hand: index + 1, outcome: value} }.join("; ")
      end
      _("%{player}: %{outcome}. Balance: %{balance}.") % {
        player: participant_name(player), outcome: outcome, balance: auction_amount(balance)}
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
      before_count = state[:dealer].size
      state[:dealer] << state[:deck].shift while live && hand_total(state[:dealer]) < 17
      dealer = hand_total(state[:dealer])
      dealer_natural = state[:dealer].size == 2 && dealer == 21
      cards = state[:dealer].map { |card| playing_card_label(card) }.join(", ")
      text = if dealer_natural
        _("Dealer has blackjack: %{cards}.") % {cards: cards}
      elsif dealer > 21
        _("Dealer goes over 21: %{cards}. Total: %{total}.") % {cards: cards, total: dealer}
      else
        _("Dealer finishes with %{cards}. Total: %{total}.") % {cards: cards, total: dealer}
      end
      add_history(history, event_id, "", state[:dealer].size > before_count ? :dealer_draw : :dealer, text)
      state[:hands].each do |person, hands|
        changes = hands.map do |hand|
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
          payout - hand[:bet]
        end
        add_history(history, event_id, person, :settlement, blackjack_balance_text(person, changes, state[:chips][person]))
      end
      minimum = state.key?(:auction) ? 0 : state.key?(:bets) ? 2 : state[:options]["stake"] * 2
      state[:eliminated] = state[:players].select { |person| state[:chips][person].zero? || state[:chips][person] < minimum }
      complete_blackjack_round(state, event_id, history)
    end

    def tournament_round_scores(state)
      # Rational chip amounts can differ even when their Float values round
      # to the same number. The tournament only needs their exact ordering.
      rank = state[:chips].values.map(&:to_r).uniq.sort.each_with_index.to_h
      state[:chips].transform_values { |chips| rank.fetch(chips.to_r) }
    end

    def complete_blackjack_round(state, event_id, history)
      record_tournament_round(state, event_id)
      if state[:round] >= state[:options]["round_limit"] || tournament_contenders(state).size < (social?(state) ? 2 : 1)
        contenders = tournament_remaining_players(state)
        highest = contenders.map { |player| state[:chips].fetch(player) }.max
        winners = contenders.select { |person| state[:chips][person] == highest }
        record_tournament_winners(state, winners)
        state.merge!(phase: :finished, current_player: nil, winner: winners.one? ? winners.first : nil, draw: !winners.one?)
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
