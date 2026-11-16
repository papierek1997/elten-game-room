module GameSurfaces
  # Presentation only: games supply semantic keys and physical card IDs.
  # Never sort the replay hand, prepared packet or meld selection itself.
  module CardSorting
    private

    def card_sort_mode_allowed?(mode)
      return false unless %w[colour number none].include?(mode.to_s)
      allowed = @spec.respond_to?(:sort_modes) ? @spec.sort_modes : nil
      allowed == nil || allowed.include?(mode.to_s)
    end

    def reset_disallowed_card_sort
      return if @card_sort_mode.to_s.empty? || card_sort_mode_allowed?(@card_sort_mode)

      @card_sort_mode = ''
      @card_sort_direction = 'ascending'
    end

    def sorted_hand?
      mode = active_card_sort_mode
      !mode.empty? && mode != "none"
    end

    def active_card_sort_mode
      return @card_sort_mode.to_s unless @card_sort_mode.to_s.empty?

      @spec.respond_to?(:default_sort) ? @spec.default_sort.to_s : ""
    end

    def sorted_cards(cards, mode, direction = @card_sort_direction)
      return cards if mode.to_s.empty?
      sorted = cards.each_with_index.sort_by do |card, index|
        key = card_sort_keys(card)[mode.to_s]
        key == nil ? [1, index] : [0, *key.to_a, card_id(card)]
      end.map(&:first)
      direction == "descending" && mode != "none" ? sorted.reverse : sorted
    end

    def card_sort_keys(card)
      value = if card.respond_to?(:sort_keys)
        card.sort_keys
      elsif card.respond_to?(:key?)
        card["sort_keys"] || card[:sort_keys]
      end
      value.respond_to?(:key?) ? value : {}
    end
  end
end
