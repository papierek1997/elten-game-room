require_relative "../dealt_card_game"
require_relative "belote_bidding"
require_relative "../../lib/private_card_round_audit"

GameRoomServerRandom.register("belote", ["deal"])
GameRoomPrivateCards.register("belote", host: %w[private_deal], claim: %w[private_ready belote_bid belote_meld belote_skip_meld],
  take: %w[initial_hand private_draw], reveal: %w[play belote_play_meld], random: %w[deal])

module GameRoomGames
  class BeloteTable < DealtCardGame
    include BeloteBidding

    def id; "belote"; end
    def name; "Belote"; end
    def short_description; "Graj w parach, wybierz atut w licytacji i zdobywaj punkty za lewy i meldunki."; end
    def private_table_required?(_options); true; end

    def rule_sections; generated_rule_sections; end
    def minimum_players; 4; end
    def maximum_players; 4; end
    def team_size(_options, player_count:); player_count == 4 ? 2 : 0; end

    def option_definitions
      [OptionDefinition.new(key: "variant", label: "Wariant", kind: :choice, default: "classic", choices: [
        OptionChoice.new(value: "classic", label: "Klasyczny"),
        OptionChoice.new(value: "coinchee", label: "Coinch\u00e9e")
      ]), OptionDefinition.new(key: "coinchee_two_stage", label: "Coinchée: rozdawanie w dwóch etapach", kind: :boolean, default: false)]
    end

    def surface_spec(replay, viewer)
      surface = super
      return surface unless surface.is_a?(GameSurfaces::CardTableSpec)

      state = replay.state
      surface.zones.each do |zone|
        zone.cards.each do |card|
          card.shift_choice = "meld" if state[:phase] == :playing
          next unless meld_available?(state, viewer, card.id)

          declaration = state[:belote_announced][viewer] ? "rebelote" : "belote"
          card.choices = [
            GameSurfaces::CardChoice.new(id: "normal", label: "Zagraj bez meldunku", value: card.id),
            GameSurfaces::CardChoice.new(id: "meld", label: "Zagraj i zg\u0142o\u015b #{declaration}", value: card.id)
          ]
          card.shift_choice = "meld"
        end
      end
      surface
    end

    def action_for(selection, replay, actor, context: nil)
      if selection["action"] == "belote_skip_meld" && replay.state[:phase] == :meld_end &&
          same_user?(replay.current_player, actor)
        plan = event_plan("belote_skip_meld", replay.state[:play_count].to_s)
        return private_secure_plan(plan, replay.state, actor) if replay.state[:private_cards]
        return [:ok, plan]
      end
      if selection["kind"] == "card" && selection["choice_id"] == "meld" &&
          legal_cards(replay.state, actor).include?(selection["card"])
        card = selection["card"]
        return [:belote_no_meld, nil] unless meld_available?(replay.state, actor, card)

        plan = event_plan("belote_play_meld", card)
        return private_secure_plan(plan, replay.state, actor) if replay.state[:private_cards]
        return [:ok, plan]
      end
      unless selection["action"] == "belote_meld"
        status, plan = super
        return [status, plan] unless status == :must_follow_suit

        state = replay.state
        trump = state[:trump]
        lead = BeloteCards.decode(table_cards(state).first).first
        if lead != trump && hand_for(state, actor).any? { |card| BeloteCards.decode(card).first == lead }
          return [status, plan]
        end

        played_trump = table_cards(state).any? { |card| BeloteCards.decode(card).first == trump }
        higher_required = played_trump && hand_for(state, actor).any? do |card|
          BeloteCards.decode(card).first == trump && !legal_cards(state, actor).include?(card)
        end
        return [higher_required ? :belote_overtrump : :belote_trump, nil]
      end
      pending = replay.state[:pending_meld]
      return [:invalid, nil] unless pending && same_user?(pending.first, actor) &&
        selection["play"].to_s == replay.state[:play_count].to_s

      plan = event_plan("belote_meld", replay.state[:play_count].to_s)
      return private_secure_plan(plan, replay.state, actor) if replay.state[:private_cards]
      [:ok, plan]
    end

    def move_error(status)
      case status
      when :belote_no_meld then "Tej karty nie mo\u017cesz zagra\u0107 z meldunkiem."
      when :belote_trump then "Musisz zagra\u0107 atut."
      when :belote_overtrump then "Musisz przebi\u0107 wy\u017cszym atutem."
      else super
      end
    end

    def shortcut_features
      super + [:led_suit]
    end

    def shortcut_feature_data(feature, replay, viewer)
      return super unless feature == :led_suit

      card = table_cards(replay.state).first
      suit = BeloteCards.decode(card).first if card
      trump = replay.state[:trump]
      trump_text = trump ? "Atut: #{BeloteBidding::LABELS.fetch(trump)}." : "Nie wybrano jeszcze atutu."
      led_text = suit ? "Kolor wyj\u015bcia: #{BeloteBidding::LABELS.fetch(suit)}." : nil
      {label: "Odczytaj atut i kolor wyj\u015bcia", message: [trump_text, led_text].compact.join(" ")}
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = super
      state = replay.state
      shortcuts << announcement_shortcut(key: "r", label: "Odczytaj kontrakt", message: round_information_text(state))
      points = state.fetch(:units).map do |unit|
        total = state.fetch(:trick_points, {}).fetch(unit, 0) + state.fetch(:bonuses, {}).fetch(unit, 0)
        "#{GameRoomContent.utf8(unit_label(state, unit))}: #{total}"
      end.join(". ")
      shortcuts << GameShortcut.new(key: "s", modifiers: [:shift], kind: :announcement,
        label: "Punkty obecnego rozdania", message: points)
      if state[:upcard]
        shortcuts << GameShortcut.new(key: "d", kind: :announcement, label: "Odczytaj odkryt\u0105 kart\u0119",
          message: "Odkryta karta: #{playing_card_label(state[:upcard])}.")
      end
      if state[:phase] == :bidding && same_user?(state[:current_player], viewer)
        choices = bid_choices(state).map { |choice| ShortcutChoice.new(value: choice.to_s, label: bid_label(choice)) }
        shortcuts << GameShortcut.new(key: "b", kind: :choice, label: "Wybierz kontrakt lub pas",
          prompt: bidding_header(state), choices: choices, action_kind: "command",
          action_name: "belote_bid", value_key: "choice")
        shortcuts << GameShortcut.new(key: "enter", kind: :choice, label: "Wybierz kontrakt lub pas",
          prompt: bidding_header(state), choices: choices, action_kind: "command",
          action_name: "belote_bid", value_key: "choice")
      end
      shortcuts
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      return "play2" if event["action"] == "belote_meld"
      return %w[play draw2 play2] if event["action"] == "belote_play_meld"

      cues = super
      return cues unless event["action"] == "play" && history.any? { |entry| entry.kind == :play }

      trump = before_replay&.state&.fetch(:trump, nil)
      card = BeloteCards::DECODED[event["value"]]
      trump && card&.first == trump ? Array(cues) + ["draw2"] : cues
    end

    def bot_strategy
      @bot_strategy ||= GameRoomBots::HeuristicStrategy.new
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      return bid_score(state, actor, action) if action["action"] == "belote_bid"
      return 0 unless action["kind"] == "card"

      legal = legal_cards(state, actor).map { |card| BeloteCards.decode(card) }
      preferred = BeloteBot.play(legal, state.fetch(:trump))
      preferred && action["card"] == BeloteCards.encode(preferred) ? 1 : 0
    end

    protected

    def deal_round(state, seed, _event, _repository, _history)
      seats = state.fetch(:seats)
      state[:passes] = 0
      state[:contract] = nil
      state[:multiplier] = 1
      state[:pending_meld] = nil
      state[:taker] = state[:trump] = state[:upcard] = nil
      state[:trick] = []
      state[:play_count] = 0
      state[:trick_points] = state[:units].to_h { |unit| [unit, 0] }
      state[:bonuses] = state[:trick_points].dup
      state[:belote_announced] = {}
      state[:phase], state[:current_player] = :bidding, first_player(state)

      unless two_stage_deal?(state)
        deck = shuffled_cards(BeloteCards::DECK, seed) unless state[:private_cards]
        state[:hands] = seats.to_h { |seat| [seat, deck ? deck.shift(8) : Array.new(8)] }
        return
      end

      if state[:private_cards]
        state[:hands] = seats.to_h { |seat| [seat, Array.new(5)] }
        state[:phase] = :awaiting_upcard
      else
        deck = shuffled_cards(BeloteCards::DECK, seed)
        order = seats.rotate((state[:dealer] + 1) % seats.size)
        state[:hands] = seats.to_h { |seat| [seat, []] }
        [3, 2].each do |count|
          order.each { |seat| state[:hands].fetch(seat).concat(deck.shift(count)) }
        end
        state[:upcard] = deck.shift
        state[:undealt] = deck
      end
    end

    def private_deal_spec(state)
      GameRoomPrivateCardRoundAudit.begin_round(state)
      {hands: state.fetch(:hands), deck: BeloteCards::DECK}
    end

    def private_dealing_applied(state, _event, _session, _repository, _history)
      return unless state[:phase] == :awaiting_upcard

      state[:phase] = :bidding
      private_request_draw(state, actor: first_player(state), count: 1, purpose: "belote_upcard")
    end

    def private_received_cards(state, purpose, cards, event, repository, history)
      return super unless purpose == "belote_upcard"

      state[:upcard] = cards.fetch(0)
    end

    def complete_belote_deal(state)
      seats = state[:seats]
      taker = state[:taker]
      state[:hands].fetch(taker) << state.fetch(:upcard)
      state[:phase], state[:current_player] = :playing, first_player(state)
      if state[:private_cards]
        counts = seats.to_h { |seat| [seat, seat == taker ? 2 : 3] }
        GameRoomPrivateCardDealing.append(state, counts)
      else
        seats.rotate(seats.index(taker)).each do |seat|
          state[:hands].fetch(seat).concat(state.fetch(:undealt).shift(seat == taker ? 2 : 3))
        end
      end
    end

    def round_information_text(state)
      taker = state[:taker]
      return "Nie wybrano jeszcze kontraktu." unless taker && state[:trump]

      name = GameRoomContent.utf8(participant_name(taker))
      pair = GameRoomContent.utf8(unit_label(state, unit_for(state, taker)))
      suit = BeloteBidding::LABELS.fetch(state[:trump])
      threshold = state[:contract] || 82
      message = "#{name} wybra\u0142 atut: #{suit}. Kontrakt gra para #{pair}. Musi zdoby\u0107 co najmniej #{threshold} punkt\u00f3w i wi\u0119cej od obrony."
      multiplier = state.fetch(:multiplier, 1)
      message += " Mno\u017cnik kontraktu: #{multiplier}." if multiplier > 1
      message
    end

    def table_cards(state)
      state.fetch(:trick, []).map(&:last)
    end

    def legal_cards(state, actor)
      return [] unless state[:phase] == :playing && same_user?(state[:current_player], actor)

      hand = hand_for(state, actor).filter_map { |card| BeloteCards::DECODED[card] }
      trick = table_cards(state).map { |card| BeloteCards.decode(card) }
      trump = state.fetch(:trump)
      partner_winning = !trick.empty? &&
        unit_for(state, state[:trick].fetch(BeloteTrick.winner(trick, trump)).first) == unit_for(state, actor)
      BeloteRound.legal(hand, trick, trump: trump, partner_winning: partner_winning).map do |card|
        BeloteCards.encode(card)
      end
    end

    def meld_available?(state, actor, card)
      return false unless legal_cards(state, actor).include?(card)

      suit, rank = BeloteCards.decode(card)
      return false unless suit == state[:trump]

      [12, 13].include?(rank) && (state[:belote_announced][actor] || hand_for(state, actor).include?(BeloteCards.encode([suit, 25 - rank])))
    end

    def private_event_card(event, state)
      return event["value"] if event["action"] == "belote_play_meld"

      super
    end

    def apply_replay_event(state, event, session, repository, history)
      return super unless event["action"] == "belote_play_meld"

      actor = repository.actor_of(event, session)
      card = event["value"]
      if state[:private_cards]
        return false unless state[:phase] == :playing && same_user?(state[:current_player], actor)
        suit, rank = BeloteCards::DECODED[card]
        return false unless suit == state[:trump] && [12, 13].include?(rank)
      else
        return false unless meld_available?(state, actor, card)
      end

      super(state, event.merge("action" => "play", "belote_declared" => true), session, repository, history)
    end

    def play_card(state, actor, card, event, repository, history)
      trick = state.fetch(:trick)
      state[:pending_meld] = nil
      suit, rank = BeloteCards.decode(card)
      if suit == state[:trump] && [12, 13].include?(rank)
        state[:pending_meld] = [actor, rank]
      end
      if event["belote_declared"]
        apply_meld(state, event.merge("value" => state[:play_count].to_s), nil, repository, history, actor: actor, resume: false)
      end
      trick << [actor, card]
      if trick.size < 4
        state[:current_player] = next_player(state, actor)

        return
      end

      cards = table_cards(state).map { |value| BeloteCards.decode(value) }
      trump = state.fetch(:trump)
      winner = trick.fetch(BeloteTrick.winner(cards, trump)).first
      last = state[:play_count] == 32
      points = BeloteTrick.points(cards, trump, last: last)
      state.fetch(:trick_points)[unit_for(state, winner)] += points
      name = GameRoomContent.utf8(participant_name(winner))
      message = "#{name} bierze lew\u0119 za #{points} pkt."
      message += " #{name} wychodzi do nast\u0119pnej lewy." unless last
      add_history(history, event, repository, :trick, message, actor: winner)
      trick.clear
      state[:current_player] = winner
      if last
        settle_belote_round(state, event, repository, history)
      end
    end

    def pause_for_meld(state, actor)
      state[:after_meld_player] = state[:current_player]
      state[:phase], state[:current_player] = :meld_end, actor
    end

    def finish_meld_decision(state, event, repository, history)
      state[:pending_meld] = nil
      state[:phase], state[:current_player] = :playing, state.delete(:after_meld_player)
      settle_belote_round(state, event, repository, history) if state[:play_count] == 32
    end

    def apply_meld(state, event, session, repository, history, actor: repository.actor_of(event, session), resume: true)
      pending = state[:pending_meld]
      return false unless pending && event["value"] == state[:play_count].to_s
      owner, rank = pending
      return false unless same_user?(owner, actor)

      state[:pending_meld] = nil
      unless state[:belote_announced][actor]
        partner_card = BeloteCards.encode([state[:trump], 25 - rank])
        return false unless state[:private_cards] || hand_for(state, actor).include?(partner_card)
        state[:belote_announced][actor] = true
        label = "belote"
      else
        state[:belote_announced].delete(actor)
        state[:bonuses][unit_for(state, actor)] += 20
        label = "rebelote, 20 punkt\u00f3w"
      end
      add_history(history, event, repository, :belote, "#{GameRoomContent.utf8(participant_name(actor))}: #{label}.", actor: actor) unless state[:private_cards]
      finish_meld_decision(state, event, repository, history) if resume && state[:phase] == :meld_end
      true
    end

    def private_after_event(state, event, session, repository, history)
      return unless %w[play belote_play_meld belote_meld belote_skip_meld].include?(event["action"])

      state.fetch(:private_round_actions) << event
      return unless state[:phase] == :private_round_end

      audit = GameRoomPrivateCardRoundAudit.initial_state(state)
      if audit
        audit.merge!(state.slice(:upcard, :taker, :trump, :passes, :contract, :multiplier))
        audit[:hands].fetch(audit[:taker]) << audit[:upcard] if two_stage_deal?(state)
        audit[:phase], audit[:current_player] = :playing, first_player(audit)
      end
      audited_history = []
      valid = audit && state.fetch(:private_round_actions).all? do |record|
        apply_replay_event(audit, record, session, repository, audited_history)
      end
      if valid
        state.merge!(audit)
        history.concat(audited_history.select { |entry| %i[belote round_result result].include?(entry.kind) })
      else
        GameRoomPrivateCardRoundAudit.reject_round(state, event, repository, history)
      end
    end

    def settle_belote_round(state, event, repository, history)
      if state[:private_cards]
        state[:phase], state[:current_player] = :private_round_end, nil
        return
      end

      units = state.fetch(:units)
      tricks = units.map { |unit| state.fetch(:trick_points).fetch(unit) }
      taker = units.index(unit_for(state, state.fetch(:taker)))
      bonuses = units.map { |unit| state.fetch(:bonuses).fetch(unit) }
      settlement = if coinchee?(state)
        compared = tricks.zip(bonuses).map(&:sum)
        success = compared[taker] >= state.fetch(:contract) && compared[taker] > compared[1 - taker]
        paid = success ? tricks.dup : [0, 0]
        paid[1 - taker] = 162 unless success
        sweep = tricks.index(162)
        paid[sweep] += 90 if sweep && paid[sweep].positive?
        {scores: paid.zip(bonuses).map { |points, bonus| (points + bonus) * state.fetch(:multiplier) }, carry: 0, winner: success ? taker : 1 - taker}
      else
        BeloteDeal.settle(tricks, taker: taker, bonuses: bonuses, carry: state.fetch(:carry, 0))
      end
      state[:carry] = settlement.fetch(:carry)
      units.zip(settlement.fetch(:scores)).each { |unit, points| state[:scores][unit] += points }
      winner = settlement.fetch(:winner)
      pair = GameRoomContent.utf8(unit_label(state, units.fetch(taker)))
      outcome = if winner.nil?
        "Remis. Para #{pair} odk\u0142ada punkty z lew do puli."
      elsif winner == taker
        "Para #{pair} wykona\u0142a kontrakt."
      else
        "Para #{pair} nie wykona\u0142a kontraktu."
      end
      add_history(history, event, repository, :round_result, outcome)
      units.each_with_index do |unit, index|
        name = GameRoomContent.utf8(unit_label(state, unit))
        collected = tricks.fetch(index) + bonuses.fetch(index)
        awarded = settlement.fetch(:scores).fetch(index)
        add_history(history, event, repository, :round_result, "#{name}. Zdobyte punkty: #{collected}. Zapisane punkty: #{awarded}.")
      end
      state[:phase], state[:current_player] = :round_complete, nil
      if state[:scores].values.max >= 1000 && winning_units(state).one?
        finish_game(state, event, repository, history)
      end
    end
  end
end

require_relative '../generated/rulebooks/belote'
