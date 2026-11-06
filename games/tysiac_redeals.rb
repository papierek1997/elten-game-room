module GameRoomGames
  module TysiacRedeals
    using GameRoomLocalization::Translations
    REDEAL_DEFAULTS = {"redeal_four_nines"=>true, "redeal_talon_nines"=>false}.freeze

    def option_definitions
      super + [
        OptionDefinition.new(key: "redeal_four_nines", label: _("Allow a redeal with four initial nines"), kind: :boolean, default: true),
        OptionDefinition.new(key: "redeal_talon_nines", label: _("Allow a redeal with at least two nines in the talon"), kind: :boolean, default: false)
      ]
    end

    # Keep omitted defaults out of canonical storage; the definitions still
    # supply them to the editor, settings documents and rule checks.
    def normalize_options(values)
      result = super
      REDEAL_DEFAULTS.each_key do |key|
        result.delete(key) unless values.is_a?(Hash) && (values.key?(key) || values.key?(key.to_sym))
      end
      result
    end

    def table_creation_options(values = {})
      super(REDEAL_DEFAULTS.merge(values.transform_keys(&:to_s)))
    end

    def legal_actions(replay, actor, context: nil)
      actions = super
      reason = redeal_reason(replay.state, actor)
      reason ? actions + [{"kind"=>"command", "action"=>"redeal", "reason"=>reason}] : actions
    end

    def action_for(selection, replay, actor, context: nil)
      return super unless selection["kind"] == "command" && selection["action"] == "redeal"
      return [:finished, nil] if replay.finished?
      reason = redeal_reason(replay.state, actor)
      return [:cannot_redeal, nil] unless reason && selection["reason"] == reason

      [:ok, event_plan("redeal", reason)]
    end

    def automatic_action(replay, actor, context: nil)
      if replay.state[:phase] == :redeal && same_user?(actor, replay.players.first)
        return {"kind"=>"command", "action"=>"deal"}
      end
      super
    end

    def surface_spec(replay, viewer)
      surface = super
      reason = redeal_reason(replay.state, viewer)
      return surface unless reason
      cards = surface.is_a?(GameSurfaces::CardTableSpec) ? surface : surface.parts.find { |part| part.id == "cards" }&.surface
      return surface unless cards.is_a?(GameSurfaces::CardTableSpec)

      cards.zones.first.commands = [GameSurfaces::Command.new(id: "redeal", label: _("Request a redeal"),
        enabled: true, payload: {"reason"=>reason})]
      surface
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = super
      reason = redeal_reason(replay.state, viewer)
      if reason
        shortcuts << GameShortcut.new(key: "d", modifiers: [:shift], label: _("Request a redeal"),
          kind: :action, action_kind: "command", action_name: "redeal", payload: {"reason"=>reason})
      end
      shortcuts
    end

    def move_error(status)
      status == :cannot_redeal ? _("You cannot request a redeal now.") : super
    end

    private

    def redeal_reason(state, actor)
      return nil unless state && same_user?(state[:current_player], actor)
      if state[:phase] == :bidding && state[:bids][player_key(state, actor)] == nil &&
          state[:options].fetch("redeal_four_nines", true) &&
          (Tysiac::SUITS.map { |suit| "9#{suit}" } - hand_for(state, actor)).empty?
        return "four_nines"
      end
      if [:passing, :discarding].include?(state[:phase]) && same_user?(state[:taker], actor) &&
          state[:pass_index].zero? && state[:talon_visible] && state[:options].fetch("redeal_talon_nines", false) &&
          state[:talon].count { |card| card_rank(card) == "9" } >= 2
        return "talon_nines"
      end
      nil
    end

    def next_deal_coordinates(state)
      repeating = state[:phase] == :redeal
      round = state[:round].to_i + (repeating ? 0 : 1)
      dealer = state[:dealer_index]
      dealer = (dealer + 1) % state[:players].length if dealer && !repeating
      [round, dealer]
    end

    def apply_redeal(state, event, actor, repository, history)
      reason = redeal_reason(state, actor)
      return false unless reason && event["value"] == reason
      text = if reason == "four_nines"
        _("%{player} requests a redeal with four nines.")
      else
        _("%{player} requests a redeal: at least two nines in the talon.")
      end
      history << HistoryEntry.new(key: "redeal:#{repository.event_id(event)}",
        text: text % {player: participant_name(actor)}, event_id: repository.event_id(event), actor: actor, kind: :redeal, value: reason)
      state[:redeal_count] = state.fetch(:redeal_count, 0) + 1
      state[:phase], state[:current_player] = :redeal, nil
      true
    end
  end
end
