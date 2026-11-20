module GameRoomGames
  class Base
    module Information
      using GameRoomLocalization::Translations

      # Standard declared point-target controls share one readout. Games with
      # a fixed or compound target override this hook, not the shortcut builder.
      def score_target(replay)
        options = replay&.state&.fetch(:options, {}) || {}
        definition = option_definitions.find do |item|
          %w[score_limit target_score].include?(item.key.to_s) && option_visible?(item, options, normalize: false)
        end
        value = GameRoomOptionValues.read(definition, options) if definition
        value.to_i if value.is_a?(Integer) || value.is_a?(String) && value.match?(/\A[0-9]+\z/)
      end

      def score_target_text(replay)
        count = score_target(replay)
        return unless count && count.positive?

        n_('Score limit: %{count} point.', 'Score limit: %{count} points.', count) % {count: count}
      end

      def duration_shortcuts?; true; end

      # History kinds are semantic, untranslated boundaries, not parsed speech.
      # A game can specialize its round lifecycle without adding UI rules.
      def round_timing_start_kinds; %i[deal round_start]; end
      def round_timing_end_kinds; %i[round_result round_end round_score hand_result]; end
      def round_timing_start_actions; []; end
      def round_timing_end_phases; [:round_complete]; end

      def round_timing_event_ids(replay, repository:)
        return replay.round_timing if replay.round_timing

        first = replay.history.reverse_each.find { |entry| round_timing_start_kinds.include?(entry.kind) }&.event_id
        action = replay.accepted_events.reverse_each.find { |event| round_timing_start_actions.include?(event['action']) }
        first = [first, action && repository.event_id(action)].compact.max
        return [nil, nil] unless first

        last = replay.history.reverse_each.find { |entry| round_timing_end_kinds.include?(entry.kind) && entry.event_id.to_i >= first.to_i }
        ended = last&.event_id
        if !ended && round_timing_end_phases.include?(replay.state&.[](:phase))
          ended = repository.event_id(replay.accepted_events.last) unless replay.accepted_events.empty?
        end
        [first, ended]
      end

      # Games that advance the round immediately at settlement start the next
      # clock at that accepted boundary, retaining the previous one at game end.
      def successive_round_timing_event_ids(replay, kinds)
        ids = replay.history.filter_map { |entry| entry.event_id if kinds.include?(entry.kind) }.uniq
        replay.finished? ? [ids[-2], ids[-1]] : [ids[-1], nil]
      end

      # Keep this framework decorator distinct from game-owned information
      # builders. Poker has long used information_shortcuts(state, viewer) for
      # its private table readout, so dynamic dispatch must not reach it here.
      def decorate_information_shortcuts(shortcuts, replay)
        tail = score_target_text(replay)
        result = shortcuts.map do |shortcut|
          next shortcut unless tail && shortcut.key == 's' && shortcut.modifiers.empty? && shortcut.kind == :announcement

          copy = shortcut.dup
          copy.message = [GameRoomContent.utf8(shortcut.message), GameRoomContent.utf8(tail)].join("\n")
          copy
        end
        return result unless duration_shortcuts?

        [[[:control], 'game', _('read how long the game has lasted')],
         [[:control, :shift], 'round', _('read how long the round has lasted')]].each do |modifiers, scope, label|
          result << GameShortcut.new(key: 't', modifiers: modifiers, label: label, kind: :announcement,
            message: _('Duration is unavailable.'), payload: {'duration_scope' => scope})
        end
        result
      end
    end

    include Information
  end
end
