require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Base
    module Shortcuts
      public

      def shortcut_features
        [:turn, :material]
      end

      # Board games supply counts from the current replay, never from a cached
      # score or from the initial position. Unsupported games expose no shortcut.
      def remaining_piece_counts(_replay)
        nil
      end

      def shortcut_feature_data(feature, replay, viewer)
        case feature.to_sym
        when :turn
          message = current_turn_shortcut_text(replay, viewer)
          message.to_s.empty? ? nil : { message: message }
        when :material
          counts = remaining_piece_counts(replay)
          return nil if counts == nil

          message = replay.players.each_with_index.map do |player, index|
            _("%{player}: %{pieces}") % { player: participant_name(player), pieces: counts.fetch(index) }
          end.join("; ")
          { message: message }
        else
          nil
        end
      end

      def table_cards_browse_data(state)
        plays = state[:current_trick].to_a
        choices = if plays.empty?
          [
            ShortcutChoice.new(
              value: nil,
              label: _("No cards have been played in this trick")
            )
          ]
        else
          plays.map do |play|
            ShortcutChoice.new(
              value: play[:card],
              label: _("%{player}: %{card}") % {
                player: participant_name(play[:player]),
                card: card_label(play[:card])
              }
            )
          end
        end
        {
          kind: :browse,
          prompt: _("Cards on the table"),
          choices: choices
        }
      end

      def custom_game_shortcuts(_replay, _viewer)
        []
      end

      # Games with a real card hand may expose local navigation through the
      # currently playable physical cards. The returned hash must contain a
      # stable hand id, every distinct legal action grouped by Card#id, and the
      # subset of cards which are safe to play without any further decision.
      # Returning nil disables the feature for the current phase or variant.
      def playable_card_navigation(_replay, _viewer)
        nil
      end

      # Opt in only when this phase exposes an actual, sortable private hand.
      # Biblios' card/target pickers, boards and dice are deliberately excluded.
      def hand_sorting_available?(_replay, _viewer)
        false
      end

      # Called only for an explicitly marked hand reminder. Reuse the current
      # surface order without mutating/reducing game state or rebuilding controls.
      def displayed_hand_announcement(_replay, _viewer, cards:, hand_id:)
        return nil if cards.empty?

        _("Your hand: %{cards}.") % {cards: cards.map(&:label).join('; ')}
      end

      def hand_sort_shortcuts(replay, viewer)
        return [] unless hand_sorting_available?(replay, viewer)
        modes = declared_card_hand_order(options: replay.state&.fetch(:options, {}) || {}).sort_modes
        [["c", "colour", _("sort cards by suit"), _("Cards sorted by ascending suit."), _("Cards sorted by descending suit.")],
         ["h", "number", _("sort cards by rank"), _("Cards sorted by ascending rank."), _("Cards sorted by descending rank.")],
         ["m", "none", _("restore acquisition order"), _("Cards restored to acquisition order."), nil]].filter_map do |key, mode, label, ascending, descending|
          next unless modes.include?(mode)
          surface_shortcut(key: key, modifiers: [:shift], label: label, command: "sort_cards",
            payload: { "mode" => mode, "toggle" => mode != "none", "ascending_message" => ascending, "descending_message" => descending })
        end
      end

      def game_shortcuts(replay, viewer)
        shortcuts = GameRoomShortcuts.build(self, shortcut_features, replay, viewer)
        custom = custom_game_shortcuts(replay, viewer).to_a
        if custom.any? { |shortcut| !shortcut.is_a?(GameShortcut) }
          raise ArgumentError, "a custom game shortcut must be a GameShortcut"
        end
        result = shortcuts + custom + playable_card_shortcuts(replay, viewer)
        # Reading the active turn is shared, not an optional feature a game
        # can accidentally omit when replacing its feature list. Keep explicit
        # game-owned T commands (for example a realtime serving status).
        if (replay.current_player || replay.finished?) && result.none? { |shortcut| shortcut.key == 't' && shortcut.modifiers.empty? }
          result.unshift(*GameRoomShortcuts.build(self, [:turn], replay, viewer))
        end
        # Explicit game shortcuts (UNO colour/value/Shift+D, Rummy) retain their
        # labels and behaviour. Add only the missing shared hand commands.
        existing = result.map { |shortcut| [shortcut.key, shortcut.modifiers.to_a] }
        result += hand_sort_shortcuts(replay, viewer).reject { |shortcut| existing.include?([shortcut.key, shortcut.modifiers.to_a]) }
        result = decorate_information_shortcuts(result, replay)
        keys = result.map { |shortcut| [shortcut.key, shortcut.modifiers.to_a] }
        raise ArgumentError, "game shortcut keys must be unique" if keys.uniq.length != keys.length

        result
      end

      protected

      def card_navigation_spec(hand_id:, card_actions:, automatic_card_ids: [])
        {
          hand_id: hand_id.to_s,
          card_actions: card_actions,
          automatic_card_ids: automatic_card_ids.to_a.map(&:to_s)
        }
      end

      def playable_card_shortcuts(replay, viewer)
        specification = playable_card_navigation(replay, viewer)
        return [] if specification == nil
        raise ArgumentError, "playable card navigation must be a hash" if !specification.respond_to?(:key?)

        hand_id = option_source_value(specification, :hand_id).to_s
        raise ArgumentError, "playable card navigation requires a hand id" if hand_id.empty?
        source_actions = option_source_value(specification, :card_actions)
        raise ArgumentError, "playable card navigation requires card actions" if !source_actions.respond_to?(:each_pair)

        card_actions = {}
        source_actions.each_pair do |card_id, actions|
          id = card_id.to_s
          raise ArgumentError, "a playable card requires a physical card id" if id.empty?
          values = actions.to_a
          if values.empty? || values.any? { |action| !action.respond_to?(:key?) }
            raise ArgumentError, "a playable card requires legal action hashes"
          end
          card_actions[id] = values.map { |action| canonical_value(action) }
        end
        automatic_ids = option_source_value(specification, :automatic_card_ids).to_a.map(&:to_s).uniq
        if (automatic_ids - card_actions.keys).any?
          raise ArgumentError, "automatic playable cards must also be navigable"
        end

        auto_action = nil
        auto_card_id = nil
        if card_actions.length == 1
          card_id, actions = card_actions.first
          if automatic_ids.include?(card_id) && actions.length == 1
            auto_card_id = card_id
            auto_action = actions.first
          end
        end
        common_payload = {
          "hand_id" => hand_id,
          "card_ids" => card_actions.keys,
          "auto_card_id" => auto_card_id,
          "auto_action" => auto_action,
          "empty_message" => _("You have no playable card."),
          "focus_surface" => true
        }
        [
          surface_shortcut(
            key: "z",
            label: _("next playable card"),
            command: "navigate_playable_card",
            payload: common_payload.merge("direction" => 1, "shortcut" => "z")
          ),
          surface_shortcut(
            key: "z",
            modifiers: [:shift],
            label: _("previous playable card"),
            command: "navigate_playable_card",
            payload: common_payload.merge("direction" => -1, "shortcut" => "shift+z")
          )
        ]
      end

      def announcement_shortcut(key:, label:, message:, hand_id: nil)
        GameShortcut.new(
          key: key,
          label: label,
          kind: :announcement,
          message: message,
          payload: hand_id.to_s.empty? ? {} : {'hand_id'=>hand_id.to_s}
        )
      end

      def browse_shortcut(key:, label:, prompt:, choices:, modifiers: nil, default_value: nil, alternate_page: nil)
        GameShortcut.new(
          key: key,
          modifiers: modifiers,
          label: label,
          kind: :browse,
          prompt: prompt,
          choices: choices,
          default_value: default_value,
          alternate_page: alternate_page
        )
      end

      def number_input_shortcut(
        key:,
        label:,
        prompt:,
        action_kind:,
        action_name:,
        value_key:,
        allowed_values:,
        default_value: nil,
        invalid_message: nil
      )
        GameShortcut.new(
          key: key,
          label: label,
          kind: :number_input,
          prompt: prompt,
          action_kind: action_kind,
          action_name: action_name,
          value_key: value_key,
          allowed_values: allowed_values,
          default_value: default_value,
          invalid_message: invalid_message
        )
      end

      def surface_shortcut(key:, label:, command:, payload: {}, modifiers: nil)
        GameShortcut.new(
          key: key,
          modifiers: modifiers,
          label: label,
          kind: :surface,
          action_kind: "surface",
          action_name: command,
          payload: payload
        )
      end
    end

    include Shortcuts
  end
end
