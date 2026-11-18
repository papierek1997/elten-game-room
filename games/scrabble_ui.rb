# encoding: UTF-8
require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Scrabble
    def surface_spec(replay, viewer)
      state = replay.state
      player = state[:players].find { |p| same_user?(p, viewer) }
      GameSurfaces::WordBoardSpec.new(board: state[:board], rack: state[:racks].fetch(player, []),
        tiles: tiles(state), alphabet: language(state).alphabet,
        epoch: [viewer.to_s.downcase, state[:revision]],
        editable: state[:phase] == :playing && same_user?(viewer, state[:current_player]),
        exchange: state[:bag].length >= 8, deadline: state[:turn_deadline],
        clock_offset: state[:clock_offset].to_i, frozen_at: state[:frozen_at],
        clock_epoch_offset: state[:clock_epoch_offset].to_i,
        preview: ->(placements) { preview(state, placements) }, error_message: method(:move_error))
    end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      commands = {
        "backspace" => [_("remove the draft tile here"), "remove"], "z" => [_("cancel the draft"), "cancel"],
        "f" => [_("submit the word"), "submit"], "g" => [_("exchange tiles"), "exchange"],
        "p" => [_("pass"), "pass"], "c" => [_("read your rack"), "rack"],
        "i" => [_("change rack order"), "sort"], "y" => [_("preview words and points without checking the dictionary"), "preview"]
      }
      result = commands.map { |key,(label,command)| surface_shortcut(key: key, label: label, command: "word_#{command}") }
      (1..7).each do |number|
        result << surface_shortcut(key: number.to_s, label: _("read rack position %{number}") % { number: number }, command: "word_read", payload: { "slot" => number-1 })
        result << surface_shortcut(key: number.to_s, modifiers: [:shift],
          label: _("place rack tile %{number} on the current square") % { number: number },
          command: "word_place", payload: { "slot" => number-1 })
      end
      result << announcement_shortcut(key: "e", label: _("tiles in racks and bag"), message:
        state[:players].map { |p| "#{participant_full_name(p)}, #{state[:racks][p].length}" }.join("; ") + ". " + (_("Bag: %{count} tiles.") % { count: state[:bag].length }))
      choices = state[:words].map do |w|
        direction = w[:direction] == 1 ? _("horizontal") : _("vertical")
        ShortcutChoice.new(label: "#{w[:word]}, #{Rules.field(w[:start])}, #{direction}, #{w[:score]}", value: w[:start])
      end
      choices << ShortcutChoice.new(label: _("No words have been played."), value: 0) if choices.empty?
      result << browse_shortcut(key: "l", label: _("browse played words"), prompt: _("Played words"), choices: choices)
      result
    end

    def rule_sections
      generated_rule_sections
    end
  end
end

require_relative 'generated/rulebooks/scrabble'
