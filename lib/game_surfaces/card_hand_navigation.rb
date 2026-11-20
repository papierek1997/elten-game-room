require_relative "../game_room_localization"

module GameSurfaces
  # Local cursor movement only. The surface supplies the current, complete hand
  # or nil while that same control displays a choice/inspection instead.
  module CardHandNavigation
    using GameRoomLocalization::Translations

    ARROWS = %i[key_left key_right].freeze

    attr_writer :card_navigation_source, :card_activation_tip, :card_navigation_offset

    def update
      key = ARROWS.find do |arrow|
        key_pressed?(arrow) && GameRoomUI.modifiers_when_pressed(self, arrow, include_insert: true).empty?
      end
      groups = navigation_groups if key
      return super unless groups

      # Native ListBox treats Right as Expand, which can activate an item.
      # Mask only horizontal paths for this dispatch. Up/Down retain native
      # whole-list movement, including across suit boundaries and commands.
      @card_navigation_consumed = true
      move_in_hand(key, groups)
      super
    ensure
      @card_navigation_consumed = false
    end

    def get_tips
      inherited = defined?(super) ? super.to_a : []
      inherited = [@card_activation_tip] + inherited unless @card_activation_tip.to_s.empty?
      navigation_groups ? [_("Left/Right: jump between suits or colours. Up/Down: browse the entire hand.")] + inherited : inherited
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
        order = navigation_value(group, :order)
        # Incomplete annotations must not strand an ungrouped card. Ordinary
        # card/action lists, with no suit semantics, retain native navigation.
        return nil if id.empty? || label.empty? || !order.is_a?(Integer)

        entry = (groups[id] ||= {id: id, label: label, order: order, indices: []})
        return nil if entry[:order] != order

        entry[:indices] << index + @card_navigation_offset.to_i
      end
      values = groups.values
      return nil unless values.map { |group| group[:order] }.uniq.length == values.length

      values.sort_by { |group| group[:order] }
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
      step = key == :key_right ? 1 : -1
      group_index = group_index ? (group_index + step) % groups.length : (step == 1 ? 0 : groups.length - 1)
      group = groups[group_index]
      target = group[:indices].first
      self.index = target
      speech_stop
      # One native announcement, with card states and braille intact. Never
      # speak the whole hand caption again or modify the list to name a suit.
      clear_suppressed_focus!
      focus(nil, nil, group[:label], true)
      if target != previous
        play_sound("listbox_focus", volume: 100, pitch: 100, pan: lpos) unless @silent
        trigger(:move, target)
      end
    end
  end
end
