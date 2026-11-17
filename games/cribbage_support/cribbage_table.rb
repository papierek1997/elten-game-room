require_relative "../dealt_card_game"
require_relative "cribbage_cards"
require_relative "cribbage_private"

GameRoomServerRandom.register("cribbage", %w[deal])
GameRoomPrivateCards.register("cribbage", host: %w[private_deal], claim: %w[private_ready crib_discard crib_go crib_count],
  take: %w[initial_hand private_draw], reveal: %w[play private_show], random: %w[deal], ordered: true)

module GameRoomGames
  using GameRoomLocalization::Translations
  class CribbageTable < DealtCardGame
    CARD_HAND_ORDER = CardHandOrder.new(default_sort: 'number', sort_modes: %w[colour number], suits: PLAYROOM_SUIT_ORDER, ranks: CribbageCards::RANKS)
    include CribbagePrivate
    def id; "cribbage"; end
    def name; _('Cribbage'); end
    def score_target(_replay); 121; end
    def minimum_players; 2; end
    def maximum_players; 2; end
    def short_description; _('Score for card combinations and play to 121 points.'); end

    def rule_sections; generated_rule_sections; end

    def displayed_hand_announcement(replay, viewer, **options)
      # Counting presents public cards from either hand/the crib, not the
      # viewer's current private hand. Keep that reminder's existing meaning.
      return nil if replay.state[:phase] == :manual_count

      super
    end

    def bot_strategy
      @bot_strategy ||= GameRoomBots::HeuristicStrategy.new
    end

    def bot_action_score(replay, actor, action, context: nil)
      return 0 unless action["kind"] == "card"

      state = replay.state
      hand = hand_for(state, actor)
      seat = state[:current_player]
      key = [state[:phase], seat, hand.dup, state[:sequence].dup,
        state.fetch(:crib).fetch(seat).dup, state[:discard_slots].fetch(seat, []).dup, first_player(state),
        state[:played].values.map(&:dup), state[:scores].dup, state[:go].dup]
      cached = @cribbage_bot_choice
      preferred = cached && cached.first == key ? cached.last : cribbage_preferred_card(state, actor)
      @cribbage_bot_choice = [key, preferred]
      preferred && action["card"] == CribbageCards.encode(preferred) ? 1 : 0
    end

    def cribbage_preferred_card(state, actor)
      preferred = if state[:phase] == :discard
        hand = hand_for(state, actor).filter_map { |card| CribbageCards::DECODED[card] }
        discarded = state.fetch(:crib).fetch(state[:current_player]).filter_map { |card| CribbageCards::DECODED[card] }
        initial_hand = hand.dup
        slot = state[:discard_slots].fetch(state[:current_player], []).first
        initial_hand.insert(slot, discarded.first) if slot && discarded.one?
        key = [initial_hand.sort, !same_user?(actor, first_player(state))]
        if @cribbage_discard_key != key
          @cribbage_discards = CribbageBot.discard(initial_hand, dealer: key.last)
          @cribbage_discard_key = key
        end
        @cribbage_discards
          &.find { |card| hand.include?(card) }
      else
        cards = legal_cards(state, actor).map { |card| CribbageCards.decode(card) }
        hand = hand_for(state, actor).map { |card| CribbageCards.decode(card) }
        seen = state[:played].values.flatten.map { |card| CribbageCards.decode(card) }
        seen.concat(state[:crib].fetch(state[:current_player]).map { |card| CribbageCards.decode(card) })
        seen << CribbageCards.decode(state[:starter]) if state[:starter]
        other = state[:seats].find { |seat| !same_user?(seat, actor) }
        CribbageBot.play(cards, state[:sequence], hand: hand, seen: seen,
          opponent_count: state[:go].include?(other) ? 0 : state[:hands].fetch(other).size,
          points_needed: 121 - state[:scores].fetch(state[:current_player]),
          opponent_points_needed:121 - state[:scores].fetch(other))
      end
      preferred
    end
    private :cribbage_preferred_card

    def shortcut_features
      super - [:round_summary]
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = super
      state = replay.state
      starter = state[:starter]
      shortcuts << GameShortcut.new(key: "d", kind: :announcement, label: _('read the starter'),
        message: starter ? _('Starter: %{card}.') % {card: playing_card_label(starter)} : _('The starter has not been turned up yet.'))
      if state[:dealer]
        shortcuts << GameShortcut.new(key: "v", kind: :announcement, label: _('read who owns the crib'),
          message: crib_dealer_text(state))
      end
      return shortcuts unless state[:phase] == :manual_count && same_user?(state[:current_player], viewer)

      shortcuts << GameShortcut.new(key: "enter", label: _('Count these cards'), kind: :number_input,
        prompt: _('How many points do these cards score?'), action_kind: "command", action_name: "crib_count",
        value_key: "points", allowed_values: 0..29, payload: {"stage" => state[:count_index]})
    end

    def surface_spec(replay, viewer)
      state = replay.state
      if state[:phase] == :manual_count
        hand = count_cards(state) + [state.fetch(:starter)]
        cards = hand.map do |card|
          label = playing_card_label(card)
          label = _('Starter. %{card}') % {card: label} if card == state[:starter]
          GameSurfaces::Card.new(id: card, value: card, label: label,
            navigation_group: standard_hand_navigation_group(rank: playing_card_rank(card), suit: playing_card_suit(card)),
            sort_keys: standard_hand_sort_keys(rank: playing_card_rank(card), suit: playing_card_suit(card), position: hand.index(card)))
        end
        label = state[:count_index] == 2 ? _('Crib') : _('Cards to count')
        return GameSurfaces::CardTableSpec.new(default_sort: default_hand_sort, sort_modes: hand_sort_modes, zones: [
          GameSurfaces::CardZoneSpec.new(id: "hand", header: label, cards: cards,
            hand_order: hand, hand_epoch: [state[:round], state[:count_index]].join(":"))
        ])
      end

      if legal_actions(replay, viewer).any? { |action| action["action"] == "crib_go" }
        action = GameSurfaces::Action.new(kind: "command", name: "crib_go", payload: {}, source: "cribbage_go")
        item = GameSurfaces::PawnTrackItem.new(id: "crib_go", label: p_('Cribbage', 'Go'), action: action)
        return GameSurfaces::PawnTrackSpec.new(id: "cribbage_go",
          header: _('None of your cards fits within 31'), items: [item])
      end
      super
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      if state[:phase] == :manual_count
        return [] unless same_user?(actor, state[:current_player])

        return [{"kind" => "command", "action" => "crib_count",
          "stage" => state[:count_index], "points" => count_points(state)}]
      end
      if state[:phase] == :playing && same_user?(actor, state[:current_player]) && legal_cards(state, actor).empty?
        return [{"kind" => "command", "action" => "crib_go"}]
      end
      return super unless state[:phase] == :discard
      return [] unless same_user?(actor, state[:current_player])

      hand_for(state, actor).filter_map do |card|
        next unless CribbageCards::DECODED.key?(card)

        {"kind" => "card", "action" => "select", "zone" => "hand", "card" => card, "card_id" => card}
      end
    end

    def move_error(status)
      return _('That card would take the total above 31. Choose a lower card.') if status == :must_follow_suit

      super
    end

    def action_for(selection, replay, actor, context: nil)
      if selection["action"] == "crib_count"
        state = replay.state
        return [:invalid, nil] unless state[:phase] == :manual_count && same_user?(state[:current_player], actor)
        return [:invalid, nil] unless selection["stage"].to_s == state[:count_index].to_s
        points = selection["points"].to_s
        return [:invalid, nil] unless points.match?(/\A(?:0|[1-9][0-9]?)\z/) && points.to_i <= 29

        plan = event_plan("crib_count", "#{state[:count_index]},#{selection["points"]}")
        return private_secure_plan(plan, state, actor) if state[:private_cards]

        return [:ok, plan]
      end
      if selection["action"] == "crib_go"
        return [:invalid, nil] unless legal_actions(replay, actor).any? { |action| action.all? { |key, value| selection[key] == value } }

        plan = event_plan("crib_go", "")
        return private_secure_plan(plan, replay.state, actor) if replay.state[:private_cards]

        return [:ok, plan]
      end
      return super unless replay.state[:phase] == :discard
      return [:invalid, nil] unless legal_actions(replay, actor).any? do |action|
        %w[kind action zone card].all? { |key| selection[key] == action[key] }
      end

      slot = hand_for(replay.state, actor).index(selection["card"])
      plan = event_plan("crib_discard", slot.to_s)
      return private_secure_plan(plan, replay.state, actor) if replay.state[:private_cards]

      [:ok, plan]
    end

    protected

    def table_cards(state)
      cards = state[:phase] == :manual_count ? count_cards(state) : state.fetch(:sequence_cards, [])
      cards
    end

    def table_information_text(state)
      cards = table_cards(state)
      return _('No cards on the table.') if cards.empty?
      return cards_text(cards) unless state[:phase] == :playing
      _('Total: %{total}. Cards: %{cards}.') % {total: state[:sequence].sum { |rank| [rank, 10].min }, cards: cards_text(cards)}
    end

    def count_announcement(state)
      name = GameRoomContent.utf8(participant_name(state[:current_player]))
      if state[:count_index] == 2
        _('%{player} counts the crib. Press Enter to give the score.') % {player: name}
      else
        _('%{player} counts their hand. Press Enter to give the score.') % {player: name}
      end
    end

    def crib_dealer_text(state)
      dealer = next_player(state, first_player(state))
      _('%{player} owns the crib.') % {player: participant_name(dealer)}
    end

    def deal_round(state, seed, event, repository, history)
      add_history(history, event, repository, :crib_dealer, crib_dealer_text(state))
      seats = state.fetch(:seats)
      deck = state[:private_cards] ? Array.new(13) : shuffled_cards(CribbageCards::DECK, seed)
      state[:hands] = seats.to_h { |seat| [seat, []] }
      leader = first_player(state)
      order = [leader, next_player(state, leader)]
      12.times { |index| state[:hands].fetch(order[index % 2]) << deck[index] }
      state[:starter], state[:pending_starter] = nil, deck[12]
      state[:crib] = seats.to_h { |seat| [seat, []] }
      state[:played] = seats.to_h { |seat| [seat, []] }
      state[:discard_slots] = {}
      state[:sequence] = []
      state[:sequence_cards] = []
      state[:go] = []
      state[:play_count] = 0
      state[:phase], state[:current_player] = :discard, leader
    end

    def apply_extra_card_event(state, event, session, repository, history)
      return apply_count(state, event, session, repository, history) if event["action"] == "crib_count"
      return apply_go(state, event, session, repository, history) if event["action"] == "crib_go"
      return super unless event["action"] == "crib_discard"
      return false unless state[:phase] == :discard && event["value"].to_s.match?(/\A[0-5]\z/)

      actor = state[:current_player]
      return false unless same_user?(actor, repository.actor_of(event, session))

      hand = hand_for(state, actor)
      index = event["value"].to_i
      return false unless index < hand.size

      state[:crib].fetch(actor) << hand.delete_at(index)
      slots = (state[:discard_slots][actor] ||= [])
      slots << index
      return true unless slots.size == 2

      if state[:crib].values.sum(&:size) == 4
        state[:phase], state[:current_player] = :playing, first_player(state)
        if state[:private_cards]
          private_request_draw(state, actor: state[:current_player], count: 1, purpose: "cribbage_starter")
        elsif state[:pending_starter]
          state[:starter] = state.delete(:pending_starter)
          reveal_cribbage_starter(state, event, repository, history)
        end
      else
        state[:current_player] = next_player(state, actor)
      end
      true
    end

    def legal_cards(state, actor)
      return [] unless state[:phase] == :playing && same_user?(actor, state[:current_player])

      hand_for(state, actor).select do |card|
        decoded = CribbageCards::DECODED[card]
        decoded && CribbageScoring.pegging(state[:sequence] + [decoded.first])
      end
    end

    def play_card(state, actor, card, event, repository, history)
      seat = state[:current_player]
      state[:played].fetch(seat) << card
      state[:sequence_cards] << card
      state[:sequence] << CribbageCards.decode(card).first
      return if award_points(state, seat, CribbageScoring.pegging(state[:sequence]), event, repository, history)
      state[:last_play] = seat
      if state[:sequence].sum { |rank| [rank, 10].min } == 31
        reset_sequence(state, seat)
      elsif state[:hands].values.all?(&:empty?)
        return if award_points(state, seat, 1, event, repository, history)
        reset_sequence(state, seat)
      else
        other = next_player(state, actor)
        state[:current_player] = state[:go].include?(other) || hand_for(state, other).empty? ? seat : other
      end
    end

    def apply_go(state, event, session, repository, history)
      return false unless state[:phase] == :playing && event["value"] == ""

      seat = state[:current_player]
      return false unless same_user?(seat, repository.actor_of(event, session))
      return false if state[:sequence].empty? || !state[:last_play]
      return false unless state[:private_cards] || legal_cards(state, seat).empty?

      other = next_player(state, seat)
      if state[:go].include?(other) || hand_for(state, other).empty?
        last = state.fetch(:last_play)
        return true if award_points(state, last, 1, event, repository, history)
        reset_sequence(state, last)
      else
        state[:go] << seat
        state[:current_player] = other
      end
      true
    end

    def reset_sequence(state, last)
      state[:sequence].clear
      state[:sequence_cards].clear
      state[:go].clear
      state.delete(:last_play)
      if state[:hands].values.all?(&:empty?)
        state[:phase], state[:current_player] = :counting, nil
      else
        other = next_player(state, last)
        state[:current_player] = hand_for(state, other).empty? ? last : other
      end
    end

    def apply_replay_event(state, event, session, repository, history)
      if event['action'] == 'play'
        card = CribbageCards::DECODED[event['value']]
        return false unless state[:phase] == :playing && card && CribbageScoring.pegging(state[:sequence] + [card.first])
      end
      accepted = super
      count_round(state, event, repository, history) if accepted && !state[:private_cards] && state[:phase] == :counting
      accepted
    end

    def count_round(state, event, repository, history)
      state[:count_index] = 0
      state[:phase], state[:current_player] = :manual_count, first_player(state)
      add_history(history, event, repository, :count, count_announcement(state))
    end

    def count_cards(state)
      state[:count_index] == 2 ? state[:crib].values.flatten : state[:played].fetch(state[:current_player])
    end

    def count_points(state)
      starter = CribbageCards.decode(state.fetch(:starter))
      cards = count_cards(state).map { |card| CribbageCards.decode(card) }
      CribbageScoring.hand(cards, starter, crib: state[:count_index] == 2)
    end

    def apply_count(state, event, session, repository, history)
      return false unless state[:phase] == :manual_count

      actor = state[:current_player]
      return false unless same_user?(actor, repository.actor_of(event, session))

      actual = count_points(state)
      _stage, claim = event["value"].to_s.split(",", -1)
      return false unless claim && event["value"] == "#{state[:count_index]},#{claim}"
      return false unless claim.match?(/\A(?:0|[1-9][0-9]?)\z/)

      submitted = claim.to_i
      return false if submitted > 29
      points = [submitted, actual].min

      return true if award_points(state, actor, points, event, repository, history)

      missed = (actual - submitted).abs
      if missed.positive?
        opponent = next_player(state, actor)
        name = GameRoomContent.utf8(participant_name(opponent))
        add_history(history, event, repository, :count,
          _('Claimed: %{claimed}; correct score: %{actual}. %{player} receives the difference: %{points}.') % {
            claimed: submitted, actual: actual, player: name, points: missed})
        return true if award_points(state, opponent, missed, event, repository, history)
      end

      state[:count_index] += 1
      if state[:count_index] == 3
        state[:phase] = :round_complete
      else
        state[:current_player] = next_player(state, first_player(state))
        add_history(history, event, repository, :count, count_announcement(state))
      end
      true
    end

    def award_points(state, seat, points, event, repository, history)
      return false unless points.positive?
      state[:scores][seat] += points
      add_history(history, event, repository, :score,
        n_('%{player} received %{points} point.', '%{player} received %{points} points.', points) % {
          player: participant_name(seat), points: points}, actor: seat, value: points)
      return false if state[:scores][seat] < 121

      if state[:private_cards] && !state[:private_crib_audited]
        state[:phase], state[:current_player] = :crib_audit, nil
      else
        finish_game(state, event, repository, history)
      end
      true
    end

    def reveal_cribbage_starter(state, event, repository, history)
      add_history(history, event, repository, :starter,
        _('Starter: %{card}.') % {card: playing_card_label(state.fetch(:starter))})
      dealer = next_player(state, first_player(state))
      award_points(state, dealer, 2, event, repository, history) if CribbageCards.decode(state[:starter]).first == 11
    end
  end
end

require_relative '../generated/rulebooks/cribbage'
