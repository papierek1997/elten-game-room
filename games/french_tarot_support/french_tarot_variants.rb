module GameRoomGames
  using GameRoomLocalization::Translations

  module FrenchTarotVariants
    HANDFUL_COUNTS = {3 => [13, 15, 18], 4 => [10, 13, 15],
      5 => [8, 10, 13], 6 => [7, 9, 11]}.freeze

    private

    def tarot_kitty_size(state)
      state[:seats].size == 5 ? 3 : 6
    end

    def tarot_call_count(state)
      state[:options].fetch("tarot_partners", true) ? [state[:seats].size - 4, 0].max : 0
    end

    def announce_tarot_kitty(state, event, repository, history)
      return unless state[:phase] == :discard && !state[:private_cards]

      kitty = hand_for(state, state[:taker]).last(tarot_kitty_size(state))
      add_history(history, event, repository, :notice, _("Kitty: %{cards}.") % {cards: cards_text(kitty)})
      add_history(history, event, repository, :notice, tarot_discard_status(state))
    end

    def tarot_call_choices(state, hand)
      second = state[:called_cards].any?
      rank = second ? 13 : 14
      ranks = second ? (1..13) : (1..14)
      cards = FrenchTarotCards::CARDS.select { |suit, value| FrenchTarotCards::SUITS.key?(suit) && ranks.cover?(value) }
      preferred = cards.select { |_, value| value == rank }
      eligible = preferred.all? { |card| hand.include?(FrenchTarotCards.encode(card)) } ? cards : preferred
      eligible.map { |card| FrenchTarotCards.encode(card) } - state[:called_cards]
    end

    def tarot_call_actions(state, actor)
      return [] unless same_user?(state[:taker], actor)

      tarot_call_choices(state, hand_for(state, actor)).map do |card|
        {"kind" => "command", "action" => "tarot_call", "choice" => card}
      end
    end

    def tarot_can_announce?(state, actor)
      state[:options]["tarot_handful"] && state[:phase] == :playing &&
        same_user?(actor, state[:current_player]) && same_user?(actor, state[:taker]) &&
        !state[:tarot_handful] && state[:play_count] < state[:seats].size
    end

    def tarot_handful_actions(state, actor)
      cards = hand_for(state, actor)
      trumps = cards.filter_map do |card|
        suit, rank = FrenchTarotCards::DECODED[card]
        rank if suit == :trump
      end.sort
      HANDFUL_COUNTS.fetch(state[:seats].size).each_with_index.filter_map do |count, index|
        next if trumps.size < count && (trumps.size != count - 1 || !cards.include?("EX"))

        chosen = trumps.size >= count ? trumps.first(count - 1) + [trumps.last] : trumps
        shown = chosen.map { |rank| "#{rank}X" }
        shown << "EX" if shown.size < count
        {"kind" => "command", "action" => "tarot_handful", "choice" => ([index + 1] + shown).join(",")}
      end
    end

    def tarot_handful_choices(state, viewer)
      tarot_handful_actions(state, viewer).map do |action|
        value = action.fetch("choice")
        level, *cards = value.split(",")
        label = _("Level %{level}. Show: %{cards}.") % {level: level, cards: cards_text(cards)}
        ShortcutChoice.new(value: value, label: label)
      end
    end

    def add_tarot_variant_shortcuts(shortcuts, state, viewer)
      return unless same_user?(state[:current_player], viewer)

      if state[:phase] == :tarot_call
        choices = tarot_call_actions(state, viewer).map do |action|
          card = action.fetch("choice")
          ShortcutChoice.new(value: card, label: playing_card_label(card))
        end
        label = state[:called_cards].empty? ? _("Call the first partner") : _("Call the second partner")
        shortcuts << GameShortcut.new(key: "b", modifiers: [:shift], kind: :choice, label: label, prompt: label,
          choices: choices, action_kind: "command", action_name: "tarot_call", value_key: "choice")
      elsif tarot_can_announce?(state, viewer)
        choices = tarot_handful_choices(state, viewer)
        unless choices.empty?
          label = _("Announce a handful")
          shortcuts << GameShortcut.new(key: "p", modifiers: [:shift], kind: :choice, label: label, prompt: label,
            choices: choices, action_kind: "command", action_name: "tarot_handful", value_key: "choice")
        end
      end
    end

    def apply_tarot_variant_event(state, event, session, repository, history)
      actor = repository.actor_of(event, session)
      return false unless same_user?(actor, state[:current_player]) && same_user?(actor, state[:taker])

      value = event["value"].to_s
      if event["action"] == "tarot_call"
        return false unless state[:phase] == :tarot_call
        card = FrenchTarotCards::DECODED[value]
        return false unless card && FrenchTarotCards::SUITS.key?(card.first) && !state[:called_cards].include?(value)
        return false if state[:called_cards].any? && card.last == 14
        if !state[:private_cards] && !tarot_call_choices(state, hand_for(state, actor)).include?(value)
          return false
        end

        state[:called_cards] << value
        add_history(history, event, repository, :notice,
          _("%{player} calls %{card}.") % {player: participant_name(actor), card: playing_card_label(value)}, actor: actor)
        if state[:called_cards].size == tarot_call_count(state)
          open_tarot_contract(state)
          announce_tarot_kitty(state, event, repository, history)
        end
      else
        return false unless tarot_can_announce?(state, actor)
        level, *cards = value.split(",")
        return false unless %w[1 2 3].include?(level)
        count = HANDFUL_COUNTS.fetch(state[:seats].size).fetch(level.to_i - 1)
        return false unless cards.size == count && cards.uniq.size == count &&
          cards.all? { |card| card == "EX" || FrenchTarotCards::DECODED[card]&.first == :trump }
        unless state[:private_cards]
          hand = hand_for(state, actor)
          trumps = hand.select { |card| FrenchTarotCards::DECODED[card]&.first == :trump }.sort_by(&:to_i)
          return false unless (cards - hand).empty? && cards.include?(trumps.first) && cards.include?(trumps.last)
          return false if cards.include?("EX") && (trumps - cards).any?
        end

        state[:tarot_handful] = level.to_i
        add_history(history, event, repository, :notice,
          _("%{player} announces a handful: %{cards}.") % {player: participant_name(actor), cards: cards_text(cards)}, actor: actor)
      end
      true
    end

    def forbidden_tarot_lead?(state, value)
      return false if state[:called_cards].empty? || state[:play_count] >= state[:seats].size
      return false if state[:trick].any? { |_, card| card != "EX" } || state[:called_cards].include?(value)

      suit = FrenchTarotCards.decode(value).first
      state[:called_cards].any? { |card| FrenchTarotCards.decode(card).first == suit }
    end

    def rebuild_tarot_piles(state)
      owners = state[:seats]
      units = owners.map { |seat| tarot_side(state, seat) }
      state[:piles] = [[], []]
      state[:excuse_debt] = [0, 0]
      state[:tarot_tricks].each_with_index do |(trick, winner), index|
        cards = trick.map { |actor, card| [owners.index(actor), FrenchTarotCards.decode(card)] }
        piles, debt = FrenchTarotTrick.distribute(cards, units: units, winner: owners.index(winner),
          last: index == state[:tarot_tricks].size - 1)
        2.times { |side| state[:piles][side].concat(piles[side]); state[:excuse_debt][side] += debt[side] }
      end
    end

    def apply_tarot_contract_scores(state, score)
      seats = state[:seats]
      taker = state[:taker]
      called = state[:called_cards].map { |value| state[:called_owners][value] }
      partners = called.compact.uniq
      defenders = seats - [taker] - partners
      unit = score
      total = defenders.size * unit
      defenders.each { |seat| state[:scores][seat] -= unit }
      partners.each do |seat|
        share = if partners.size == 2
          called.first == seat ? Rational(1, 3) : Rational(1, 6)
        elsif called.count(seat) == 2
          Rational(1, 4)
        else
          called.first == seat ? Rational(1, 3) : Rational(1, 6)
        end
        points = total * share
        state[:scores][seat] += points
        state[:scores][taker] -= points
      end
      state[:scores][taker] += total
    end

    def settle_tarot_misere(state, event, repository, history)
      seats = state[:seats]
      points = seats.to_h { |seat| [seat, 0] }
      tricks = state[:tarot_tricks]
      tricks.each_with_index do |(trick, winner), index|
        trick.each do |owner, card|
          suit_rank = FrenchTarotCards.decode(card)
          if suit_rank.first == :excuse && index < tricks.size - 1 && owner != winner
            points[owner] += 8
            points[winner] += 1
          else
            points[winner] += FrenchTarotScoring.half_points(suit_rank)
          end
        end
      end
      points[tricks.last.last] += state[:kitty].sum { |card| FrenchTarotScoring.half_points(FrenchTarotCards.decode(card)) }
      seats.each { |seat| state[:scores][seat] += 4 * (182 - seats.size * points.fetch(seat)) }
      add_history(history, event, repository, :score, _("Misère. Avoid taking card points.") + "\n" + scores_text(state))
    end
  end
end
