module GameRoomGames
  module DicePokerPresentation
    using GameRoomLocalization::Translations

    def describe_event(event, repository, replay, viewer)
      lines = super
      return lines unless chip_rules?(replay.state[:options]) && event["action"] == "roll"

      entry = replay.history.find { |item| item.event_id.to_i == repository.event_id(event).to_i && item.kind == :roll }
      return lines unless entry && same_user?(entry.actor, viewer)

      [poker_roll_text(entry.actor, event.fetch("value").split(",").map(&:to_i), replay.state[:options]["variant"])]
    end

    private

    def poker_roll_text(player, dice, variant)
      _("%{player} rolls %{dice}: %{hand}.") % {
        player: participant_name(player), dice: dice.join(", "), hand: hand_name(dice, variant)}
    end

    def own_poker_hand_shortcut(state, viewer)
      return unless chip_rules?(state[:options])

      player = state[:players].find { |person| same_user?(person, viewer) }
      return unless player

      dice = if same_user?(state[:current_player], player) && state[:phase] == :playing && state[:rolls].positive?
        state[:dice]
      else
        state[:hands][player]
      end
      return unless dice

      announcement_shortcut(key: "h", label: _("read your poker dice hand"),
        message: _("Your dice: %{dice}. %{hand}.") % {
          dice: dice.join(", "), hand: hand_name(dice, state[:options]["variant"])})
    end

    def reveal_poker_hands(state, event_id, history)
      contenders = auction_contenders(state)
      return unless contenders.size > 1

      contenders.each do |player|
        dice = state[:hands].fetch(player)
        add_history(history, event_id, player, :showdown, _("%{player} reveals %{dice}: %{hand}.") % {
          player: participant_name(player), dice: dice.join(", "), hand: hand_name(dice, state[:options]["variant"])})
      end
    end
  end
end
