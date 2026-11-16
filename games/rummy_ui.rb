# encoding: UTF-8
require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Rummy
    def hand_sorting_available?(replay, viewer)
      !hand(replay.state, viewer).empty?
    end

    def surface_spec(replay, viewer)
      state = replay.state
      own_turn = state[:phase] == :playing && same_user?(state[:current_player], viewer)
      editable = own_turn && ready?(state)
      can_discard = editable && state[:options]["discard_mode"] != "none"
      cards = hand(state, viewer).each_with_index.map do |card, index|
        choices = editable ? additions_for(state, card).map do |item|
          meld = state[:melds].find { |m| m[:id] == item[:target] }
          action = command("add", card: card, target: item[:target], mode: item[:mode].to_s)
          label = item[:mode] == :recover ? _("Replace joker in %{meld}") : _("Lay off on %{meld}")
          GameSurfaces::CardChoice.new(id: "#{item[:target]}:#{item[:mode]}", label: label % { meld: meld_label(meld) }, value: JSON.generate(action))
        end : []
        if choices.empty? && can_discard
          choices << GameSurfaces::CardChoice.new(id: "discard", label: _("Discard"), value: JSON.generate(command("discard", card: card)))
        end
        choices << GameSurfaces::CardChoice.new(id: "cancel", label: _("Cancel"), value: "") unless choices.empty?
        GameSurfaces::Card.new(id: card, label: playing_card_label(card), value: card,
          navigation_group: standard_hand_navigation_group(rank: playing_card_rank(card), suit: playing_card_suit(card)),
          choices: choices, choice_header: _("Choose an action"), sort_keys: {
            "colour" => playing_card_sort_key(card),
            "number" => [Rules.joker?(card) ? 99 : Rules.rank(card), Rules::SUITS.index(card[1]) || 4, card],
            "none" => [index]
          })
      end
      table = state[:melds].map do |meld|
        entry = { id: meld[:id], label: meld_label(meld), details: meld_label(meld), actions: [], merges: [] }
        if own_turn && manipulation_allowed?(state)
          unless meld[:cards].any? { |c| Rules.joker?(c) }
            entry[:actions] << { label: _("Take the whole meld"), action: command("take", target: meld[:id]) }
          end
          Rules.removable(meld, identities: state[:options]["identities"]).each do |item|
            entry[:actions] << { label: _("Take %{card}") % { card: playing_card_label(item[:card]) }, action: command("take", target: meld[:id], card: item[:card]) }
          end
          state[:melds].each do |second|
            next if meld == second
            merged = Rules.validate(meld[:cards] + second[:cards], identities: state[:options]["identities"])
            next unless merged && Rules.preserves_joker?(meld, merged) && Rules.preserves_joker?(second, merged)
            entry[:merges] << { label: meld_label(second), action: command("merge", target: meld[:id], second: second[:id]) }
          end
        end
        entry
      end
      discard_choices = []
      discard_error = discard_draw_error(state, viewer)
      unless discard_error
        discard_choices = visible_discards(state).each_with_index.map do |card, index|
          { id: card, label: playing_card_label(card), action: command("draw", depth: index + 1) }
        end
      end
      GameSurfaces::MeldHandSpec.new(
        zones: [GameSurfaces::CardZoneSpec.new(id: "hand", header: _("Your hand"), cards: cards,
          empty_label: _("Your hand is empty"), hand_order: hand(state, viewer).dup, hand_epoch: "#{viewer.to_s.downcase}:#{state[:round]}")],
        turn: [state[:round], state[:turn]], editable: editable, can_discard: can_discard,
        minimum: state[:first_meld][state[:current_player]] ? 0 : state[:options]["first_meld"],
        validator: ->(groups) { meld_preview(groups, state) }, table: table, discard_choices: discard_choices,
        discard_error: discard_error, action_error: hand_action_error(state, viewer))
    end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      discards = visible_discards(state)
      discard_message = if state[:options]["discard_mode"] == "none"
        _("There is no discard pile in this variant.")
      elsif discards.empty?
        _("The discard pile is empty.")
      else
        discards.map { |card| playing_card_label(card) }.join(", ")
      end
      shortcuts = [
        GameShortcut.new(key: "space", label: _("draw a card"), kind: :action, action_kind: "command", action_name: "draw", payload: { "depth" => 0 }),
        surface_shortcut(key: "delete", label: _("discard the current card immediately"), command: "meld_discard"),
        surface_shortcut(key: "n", label: _("prepare a new meld"), command: "meld_new"),
        surface_shortcut(key: "f", label: _("submit all prepared melds"), command: "meld_submit"),
        surface_shortcut(key: "p", label: _("read prepared melds and their score"), command: "meld_read"),
        surface_shortcut(key: "p", modifiers: [:shift], label: _("edit prepared melds"), command: "meld_edit"),
        surface_shortcut(key: "c", label: _("browse melds on the table"), command: "meld_table"),
        announcement_shortcut(key: "d", label: _("read the discard pile"), message: discard_message),
        surface_shortcut(key: "d", modifiers: [:shift], label: _("take cards from the discard pile"), command: "meld_discard_pile"),
        announcement_shortcut(key: "e", label: _("card counts"), message: active_players(state).map { |p| "#{participant_name(p)}, #{state[:hands][p].length}" }.join("; ") + ". " + _("Draw pile: %{count}.") % { count: state[:stock].length }),
        announcement_shortcut(key: "s", label: _("scores"), message: score_announcement_order(state[:players], state[:scores], eliminated: state[:eliminated]).map { |p| "#{participant_name(p)}, #{state[:scores][p]}" }.join("; "))
      ]
      if state[:options]["discard_mode"] == "none"
        shortcuts << GameShortcut.new(key: "f", modifiers: [:shift], label: _("end your turn"), kind: :action, action_kind: "command", action_name: "end", payload: {})
      end
      shortcuts
    end

    def playable_card_navigation(replay, viewer)
      state = replay.state
      return nil unless state[:phase] == :playing && same_user?(state[:current_player], viewer) && ready?(state)
      cards = hand(state, viewer)
      alternatives = GameRoomRummyPlanner.candidates(cards, identities: state[:options]["identities"]).flat_map { |m| m[:cards] }
      grouped = cards.to_h do |card|
        [card, additions_for(state, card).map { |item| command("add", card: card, target: item[:target], mode: item[:mode].to_s) }]
      end.reject { |_card, actions| actions.empty? }
      automatic = grouped.select { |card, actions| actions.one? && actions.first["mode"] == "extend" && !alternatives.include?(card) }.keys
      card_navigation_spec(hand_id: "hand", card_actions: grouped, automatic_card_ids: automatic)
    end

    def rule_sections
      generated_rule_sections
    end

    protected

    # Older discards remain in state for recycling, not for inspection in the
    # single-discard variant. Reading never mutates that shared game state.
    def visible_discards(state)
      case state[:options]["discard_mode"]
      when "none" then []
      when "multiple" then state[:discard].reverse
      else state[:discard].last(1)
      end
    end

    def hand_action_error(state, viewer)
      return _("This action is not available now.") unless state[:phase] == :playing
      return _("It is not your turn.") unless same_user?(state[:current_player], viewer)
      return _("Draw a card first.") unless ready?(state)
      nil
    end

    def discard_draw_error(state, viewer)
      return _("There is no discard pile in this variant.") if state[:options]["discard_mode"] == "none"
      return _("Taking discards is disabled at this table.") if state[:options]["discard_mode"] == "discard"
      return _("This action is not available now.") unless state[:phase] == :playing
      return _("It is not your turn.") unless same_user?(state[:current_player], viewer)
      return _("You have already drawn this turn.") if state[:drawn] || state[:acted]
      return _("Make your first meld before taking discards.") unless state[:first_meld][state[:current_player]]
      return _("The discard pile is empty.") if state[:discard].empty?
      nil
    end

    def meld_label(meld)
      _("Meld %{number}: %{cards}") % { number: meld[:id], cards: meld[:cards].map { |card| playing_card_label(card) }.join(", ") }
    end
  end
end

require_relative 'generated/rulebooks/rummy'
