require_relative "../game_room_localization"

module GameSurfaces
  # Local cursor movement only. The surface supplies the current, complete hand
  # or nil while that same control displays a choice/inspection instead.
  module CardHandNavigation
    using GameRoomLocalization::Translations

    ARROWS = %i[key_up key_down key_left key_right].freeze

    attr_writer :card_navigation_source

    def update
      key = ARROWS.find do |arrow|
        key_pressed?(arrow) && GameRoomUI.modifiers_when_pressed(self, arrow, include_insert: true).empty?
      end
      groups = navigation_groups if key
      return super unless groups

      # Native ListBox also handles vertical arrows and treats Right as Expand
      # (which can activate an item). Mask those paths for this dispatch only;
      # keep its ordinary input, focus, selection and accessibility lifecycle.
      @card_navigation_consumed = true
      move_in_hand(key, groups)
      super
    ensure
      @card_navigation_consumed = false
    end

    def get_tips
      inherited = defined?(super) ? super.to_a : []
      navigation_groups ? [_("Left/Right: jump between suits or colours. Up/Down: browse cards of the current suit or colour.")] + inherited : inherited
    end

    def key_processed(key)
      if %w[left right].include?(key.to_s.sub(/\Akey_/, "")) && navigation_groups &&
          GameRoomUI.modifiers_when_pressed(self, key, include_insert: true).empty?
        return true
      end

      super
    end

    private

    def key_pressed?(key, **options)
      return false if @card_navigation_consumed && ARROWS.include?(key)

      super
    end

    def navigation_groups
      cards = @card_navigation_source&.call
      return nil if !cards || cards.empty?

      groups = {}
      cards.each_with_index do |card, index|
        group = navigation_value(card, :navigation_group)
        id, label = navigation_value(group, :id).to_s, navigation_value(group, :label).to_s
        # Incomplete annotations must not strand an ungrouped card. Ordinary
        # card/action lists, with no suit semantics, retain native navigation.
        return nil if id.empty? || label.empty?

        entry = (groups[id] ||= {id: id, label: label, indices: []})
        entry[:indices] << index
      end
      groups.values
    end

    def navigation_value(value, name)
      if value.respond_to?(name)
        value.public_send(name)
      elsif value.respond_to?(:key?)
        value[name] || value[name.to_s]
      end
    end

    def move_in_hand(key, groups)
      previous = index.to_i
      group_index = groups.index { |group| group[:indices].include?(previous) }
      @last_navigation_group = groups[group_index][:id] if group_index
      horizontal = %i[key_left key_right].include?(key)
      if horizontal
        group_index ||= groups.index { |group| group[:id] == @last_navigation_group }
        step = key == :key_right ? 1 : -1
        group_index = group_index ? (group_index + step) % groups.length : (step == 1 ? 0 : groups.length - 1)
        group = groups[group_index]
        target = group[:indices].first
        @last_navigation_group = group[:id]
      elsif group_index
        indices = groups[group_index][:indices]
        position = indices.index(previous)
        target = indices[position + 1] if key == :key_down
        target = indices[position - 1] if key == :key_up && position > 0
        # Commands appended below a hand remain reachable from any suit.
        count = groups.sum { |item| item[:indices].length }
        target ||= count if key == :key_down && count < self.options.length
      else
        count = groups.sum { |item| item[:indices].length }
        if key == :key_up && previous == count
          group = groups.find { |item| item[:id] == @last_navigation_group } || groups.last
          target = group[:indices].last
        else
          target = previous + (key == :key_down ? 1 : -1)
          target = nil unless target.between?(count, self.options.length - 1)
        end
      end

      if target && (target != previous || horizontal)
        self.index = target
        speech_stop
        # One native announcement, with card states and braille intact. Never
        # speak the whole hand caption again or modify the list to name a suit.
        clear_suppressed_focus!
        focus(nil, nil, horizontal ? group[:label] : "", true)
        if target != previous
          play_sound("listbox_focus", volume: 100, pitch: 100, pan: lpos) unless @silent
          trigger(:move, target)
        end
      else
        play_sound("border", volume: 100, pitch: 100, pan: lpos) unless @silent
        trigger(:border, previous)
      end
    end
  end
end
