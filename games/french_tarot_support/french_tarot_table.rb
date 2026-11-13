require_relative "../dealt_card_game"
require_relative "french_tarot_bidding"
require_relative "../../lib/private_card_round_audit"

GameRoomServerRandom.register("french_tarot", %w[deal])
GameRoomPrivateCards.register("french_tarot", host: %w[private_deal],
  claim: %w[private_ready tarot_bid tarot_discard], take: %w[initial_hand private_draw],
  reveal: %w[play], random: %w[deal], ordered: true)

module GameRoomGames
  class FrenchTarotTable < DealtCardGame
    include FrenchTarotBidding

    def id; "french_tarot"; end
    def name; "Francuski tarot"; end
    def rule_sections; generated_rule_sections; end

    def bot_strategy
      @bot_strategy ||= GameRoomBots::HeuristicStrategy.new
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      return tarot_bid_score(state, actor, action) if action["action"] == "tarot_bid"
      return 0 unless action["kind"] == "card"

      if state[:phase] == :discard
        hand = hand_for(state, actor).filter_map { |value| FrenchTarotCards::DECODED[value] }
        return FrenchTarotBot.discard(hand).include?(FrenchTarotCards.decode(action["card"])) ? 1 : 0
      end

      seats = state[:seats]
      legal = legal_cards(state, actor).map { |card| FrenchTarotCards.decode(card) }
      trick = table_cards(state).map { |card| FrenchTarotCards.decode(card) }
      leader = state[:trick].first&.first || actor
      card = FrenchTarotBot.play(legal, trick, taker: player_index(seats, state[:taker]),
        seat: player_index(seats, actor), leader: player_index(seats, leader))
      card && action["card"] == FrenchTarotCards.encode(card) ? 1 : 0
    end

    def shortcut_features
      super + [:led_suit]
    end

    def shortcut_feature_data(feature, replay, viewer)
      return super unless feature == :led_suit

      suit = table_cards(replay.state).map { |card| FrenchTarotCards.decode(card).first }.find { |value| value != :excuse }
      labels = {clubs: "trefl", diamonds: "karo", hearts: "kier", spades: "pik", trump: "atut"}
      {message: suit ? "Kolor wyj\u015bcia: #{labels.fetch(suit)}." : "Kolor wyj\u015bcia nie zosta\u0142 jeszcze ustalony."}
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = super
      state = replay.state
      return shortcuts unless state[:phase] == :playing

      points = state.fetch(:piles).each_with_index.map do |cards, side|
        half_points = cards.sum { |card| FrenchTarotScoring.half_points(card) }
        half_points += state[:excuse_debt][1 - side] - state[:excuse_debt][side]
        half_points.even? ? (half_points / 2).to_s : "#{half_points / 2},5"
      end
      shortcuts << GameShortcut.new(key: "s", modifiers: [:shift], kind: :announcement,
        label: "Odczytaj punkty z zako\u0144czonych lew",
        message: "Rozgrywaj\u0105cy: #{points[0]}. Obrona: #{points[1]}.")
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      cues = super
      card = FrenchTarotCards::DECODED[event["value"]]
      return cues unless event["action"] == "play" && card&.first == :trump && history.any? { |entry| entry.kind == :play }

      Array(cues) + ["draw2"]
    end

    def option_definitions
      [
        OptionDefinition.new(key: "round_limit", label: "Limit rozda\u0144 (0 = bez limitu)", kind: :integer, default: 1),
        OptionDefinition.new(key: "score_limit", label: "Pr\u00f3g punkt\u00f3w (0 = bez progu)", kind: :integer, default: 0)
      ]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      rounds, points = values.values_at("round_limit", "score_limit")
      return "Podaj nieujemne limity." unless [rounds, points].all? { |value| value.is_a?(Integer) && value >= 0 }
      return "Ustaw limit rozda\u0144 lub pr\u00f3g punkt\u00f3w." if rounds.zero? && points.zero?

      nil
    end

    def minimum_players; 4; end
    def maximum_players; 4; end
    def private_table_required?(_options); true; end

    def move_error(status)
      return _("You must follow suit or play a trump when required.") if status == :must_follow_suit

      super
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return super unless state[:phase] == :discard
      return [] unless same_user?(actor, state[:taker])

      discardable_cards(state, actor).map do |card|
        {"kind" => "card", "action" => "select", "zone" => "hand", "card" => card, "card_id" => card}
      end
    end

    def action_for(selection, replay, actor, context: nil)
      return super unless replay.state[:phase] == :discard
      return [:invalid, nil] unless legal_actions(replay, actor).any? do |action|
        %w[kind action zone card].all? { |key| action[key] == selection[key] }
      end

      index = hand_for(replay.state, actor).index(selection["card"])
      plan = event_plan("tarot_discard", index.to_s)
      return private_secure_plan(plan, replay.state, actor) if replay.state[:private_cards]

      [:ok, plan]
    end

    protected

    def round_information_text(state)
      return super unless state[:taker]

      text = "Rozgrywaj\u0105cy: #{GameRoomContent.utf8(participant_name(state[:taker]))}. Kontrakt: #{FrenchTarotBidding::LABELS.fetch(state[:contract])}."
      state[:phase] == :discard && state[:kitty].none?(&:nil?) ? "#{text} #{tarot_discard_status(state)}" : text
    end

    def tarot_discard_status(state)
      "Pozosta\u0142o kart do od\u0142o\u017cenia: #{6 - state[:kitty].size}."
    end

    def playing_card_rank(value)
      card = FrenchTarotCards::DECODED[value]
      return :excuse if card&.first == :excuse

      card&.first == :trump ? card.last : super
    end

    def standard_hand_sort_keys(rank:, suit:, position:)
      return {"colour" => [101, 0], "number" => [101, 0], "none" => [position]} if rank == :excuse
      return {"colour" => [100, rank], "number" => [100, rank], "none" => [position]} if rank.is_a?(Integer)

      suit_index = PLAYROOM_SUIT_ORDER.index(suit) || PLAYROOM_SUIT_ORDER.length
      rank_index = FrenchTarotCards::RANKS.index(rank) || FrenchTarotCards::RANKS.length
      {"colour" => [suit_index, rank_index], "number" => [rank_index, suit_index], "none" => [position]}
    end

    def hand_cards_for_display(hand)
      hand.sort_by do |value|
        keys = standard_hand_sort_keys(rank: playing_card_rank(value), suit: playing_card_suit(value), position: 0)
        keys.fetch("colour")
      end
    end

    def discardable_cards(state, actor)
      cards = hand_for(state, actor).filter_map { |card| FrenchTarotCards::DECODED[card] }
      ordinary = cards.reject { |suit, rank| %i[trump excuse].include?(suit) || rank == 14 }
      eligible = ordinary.empty? ? cards.select { |card| card.first == :trump && !FrenchTarotScoring.oudler?(card) } : ordinary
      eligible.map { |card| FrenchTarotCards.encode(card) }
    end

    def apply_extra_card_event(state, event, session, repository, history)
      return super unless event["action"] == "tarot_discard"
      actor = repository.actor_of(event, session)
      return false unless state[:phase] == :discard && same_user?(state[:taker], actor)
      return false unless event["value"].to_s.match?(/\A(?:0|[1-9][0-9]?)\z/)

      hand = hand_for(state, actor)
      index = event["value"].to_i
      return false unless index < hand.size
      return false unless state[:private_cards] || discardable_cards(state, actor).include?(hand[index])

      state[:kitty] << hand.delete_at(index)
      if state[:kitty].size == 6
        begin_tarot_play(state)
        add_history(history, event, repository, :notice, "Od\u0142o\u017cono sze\u015b\u0107 kart. Rozpoczyna si\u0119 gra.")
      else
        add_history(history, event, repository, :notice, tarot_discard_status(state))
      end
      true
    end

    def deal_round(state, seed, _event, _repository, _history)
      seats = state.fetch(:seats)
      deck = state[:private_cards] ? Array.new(78) : shuffled_cards(FrenchTarotCards::DECK, seed)
      state[:hands] = seats.zip(deck.first(72).each_slice(18)).to_h
      state[:kitty] = deck.last(6)
      state[:taker] = state[:contract] = nil
      state[:bid_count] = state[:play_count] = 0
      state[:trick] = []
      state[:piles] = [[], []]
      state[:excuse_debt] = [0, 0]
      state[:phase], state[:current_player] = :bidding, first_player(state)
    end

    def private_deal_spec(state)
      GameRoomPrivateCardRoundAudit.begin_round(state)
      {hands: state.fetch(:hands), deck: FrenchTarotCards::DECK}
    end

    def complete_tarot_bidding(state)
      taker = state[:taker]
      unless taker
        state[:phase], state[:current_player] = :round_complete, nil
        return
      end

      if %i[petite garde].include?(state[:contract])
        state[:phase], state[:current_player] = :discard, taker
        if state[:private_cards]
          private_request_draw(state, actor: taker, count: 6, purpose: "tarot_kitty")
        else
          receive_tarot_kitty(state, state.fetch(:kitty))
        end
      else
        begin_tarot_play(state)
      end
    end

    def private_received_cards(state, purpose, cards, event, repository, history)
      if purpose == "tarot_final_kitty"
        state[:kitty] = cards
        settle_tarot(state, event, repository, history)
        return
      end
      return super unless purpose == "tarot_kitty"

      receive_tarot_kitty(state, cards)
      add_history(history, event, repository, :notice, tarot_discard_status(state))
    end

    def receive_tarot_kitty(state, cards)
      state.fetch(:hands).fetch(state.fetch(:taker)).concat(cards)
      state[:kitty] = []
    end

    def playing_card_label(value)
      card = FrenchTarotCards::DECODED[value]
      return super unless card

      suit, rank = card
      return GameRoomLocalization.primary_language == "pl" ? "Wym\u00f3wka" : "Excuse" if suit == :excuse
      return "Atut #{rank}" if suit == :trump
      return super unless rank == 12

      labels = {clubs: "trefl", diamonds: "karo", hearts: "kier", spades: "pik"}
      "Rycerz #{labels.fetch(suit)}"
    end

    def table_cards(state)
      state.fetch(:trick, []).map(&:last)
    end

    def legal_cards(state, actor)
      return [] unless state[:phase] == :playing && same_user?(state[:current_player], actor)

      hand = hand_for(state, actor).filter_map { |value| FrenchTarotCards::DECODED[value] }
      trick = table_cards(state).map { |value| FrenchTarotCards.decode(value) }
      FrenchTarotTrick.legal(hand, trick).map { |card| FrenchTarotCards.encode(card) }
    end

    def play_card(state, actor, value, event, repository, history)
      trick = state.fetch(:trick)
      trick << [actor, value]
      if trick.size < 4
        state[:current_player] = next_player(state, actor)
        return
      end

      cards = trick.map { |_, card| FrenchTarotCards.decode(card) }
      winner = trick.fetch(FrenchTarotTrick.winner(cards)).first
      taking = tarot_side(state, winner)
      last = state[:play_count] == 72
      trick.zip(cards).each do |(owner, _), card|
        owner_side = tarot_side(state, owner)
        if card.first == :excuse && !last && owner_side != taking
          state[:piles][owner_side] << card
          state[:excuse_debt][owner_side] += 1
        else
          state[:piles][taking] << card
        end
      end
      trick.clear
      state[:phase], state[:current_player] = last ? [:tarot_count, nil] : [:playing, winner]
      settle_tarot(state, event, repository, history) if last && !state[:private_cards]
    end

    def private_after_event(state, event, _session, repository, history)
      return unless state[:phase] == :tarot_count
      if %i[garde_sans garde_contre].include?(state[:contract])
        private_request_draw(state, actor: state[:taker], count: 6, purpose: "tarot_final_kitty")
      else
        holder = state[:taker]
        state[:tarot_discarded] = {holder => state[:kitty]}
        return if GameRoomPrivateCardDisclosure.prepare(state, [holder], purpose: "tarot_discarded",
          zone: :tarot_discarded)

        settle_tarot(state, event, repository, history)
      end
    end

    def private_disclosure_completed(state, purpose, event, _session, repository, history)
      return unless purpose == "tarot_discarded"

      state[:kitty] = state.delete(:tarot_discarded).fetch(state[:taker])
      settle_tarot(state, event, repository, history)
    end

    def settle_tarot(state, event, repository, history)
      piles = state[:piles]
      destination = state[:contract] == :garde_contre ? 1 : 0
      piles[destination].concat(state[:kitty].map { |value| FrenchTarotCards.decode(value) })
      oudlers = piles[0].count { |card| FrenchTarotScoring.oudler?(card) }
      points = piles[0].sum { |card| FrenchTarotScoring.half_points(card) }
      points += state[:excuse_debt][1] - state[:excuse_debt][0]
      margin = points - FrenchTarotScoring::TARGET.fetch(oudlers)
      score = (50 + margin.abs) * FrenchTarotScoring::CONTRACTS.fetch(state[:contract])
      score = -score if margin.negative?
      state[:seats].each { |seat| state[:scores][seat] += tarot_side(state, seat).zero? ? 3 * score : -score }
      state[:completed_deals] = state.fetch(:completed_deals, 0) + 1
      round_limit = state[:options].fetch("round_limit", 1)
      score_limit = state[:options].fetch("score_limit", 0)
      if (round_limit.positive? && state[:completed_deals] >= round_limit) ||
          (score_limit.positive? && state[:scores].values.max >= score_limit * 2)
        finish_game(state, event, repository, history)
      else
        state[:phase], state[:current_player] = :round_complete, nil
        add_history(history, event, repository, :notice, "Koniec rozdania.\n#{scores_text(state)}")
      end
    end

    def scores_text(state)
      state[:units].sort_by { |unit| -state[:scores].fetch(unit) }.map do |unit|
        points = state[:scores].fetch(unit)
        score = points.even? ? (points / 2).to_s : "#{points.negative? ? '-' : ''}#{points.abs / 2},5"
        "#{GameRoomContent.utf8(unit_label(state, unit))}: #{score}"
      end.join("\n")
    end

    def tarot_side(state, actor)
      same_user?(actor, state[:taker]) ? 0 : 1
    end

    def begin_tarot_play(state)
      state[:phase], state[:current_player] = :playing, first_player(state)
    end
  end
end

require_relative '../generated/rulebooks/french_tarot'
