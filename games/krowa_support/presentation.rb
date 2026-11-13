# encoding: UTF-8

require_relative "../../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  module KrowaPresentation
    def rule_sections
      generated_rule_sections
    end

    def game_view_spec(replay, viewer)
      GameRoomLayout::ViewSpec.new(surface: surface_spec(replay, viewer),
        trailing_parts: ["commands"], restartable: replay.state[:options]["variant"] != "daily",
        restart_label: _("Start game"),
        finished_text: solo_variant?(replay.state) ? _("Game over.") : nil,
        status_commands: replay.finished? ? krowa_status_commands : [])
    end

    def surface_spec(replay, viewer)
      state = replay.state
      player = replay.players.find { |name| same_user?(name, viewer) }
      parts = []
      if state[:phase] == :active && player && !state[:results].key?(player)
        extra_commands = if user_vocabulary_allowed?(state)
          [GameSurfaces::Command.new(id: "add_word", label: _("Add noun to dictionary and check"))]
        else
          []
        end
        parts << part("answer", GameSurfaces::QuestionSpec.new(id: "krowa-answer-#{state[:round]}",
          prompt: _("Answer: %{length} letters") % {length: state[:length]}, mode: :text,
          value: "", required: true, max_length: 64, show_submit_button: false, clear_on_submit: true,
          clear_on_rejection: %w[wrong_length unknown_noun],
          extra_commands: extra_commands))
      else
        parts << part("status", information("krowa-status", _("Krowa"), status_text(replay, viewer)))
      end
      trials = state[:attempts].select { |trial| tower?(state) || !player || trial[:player] == player }
      labels = trials.map { |trial| trial_label(trial, state[:length], show_player: !solo_view?(replay, viewer)) }
      parts << part("attempts", list("krowa-attempts", _("Attempts"), labels.empty? ? [_("No attempts")] : labels))
      parts << part("results", information("krowa-results", _("Results"), result_summary(state)))
      if tower?(state)
        parts << part("turn", list("krowa-turn", _("Now playing"), [replay.current_player ? participant_name(replay.current_player) : _("Waiting for the next round")]))
      end
      commands = []
      if state[:phase] == :active && player
        if (tower?(state) && owner?(state, player)) || (!tower?(state) && !state[:results].key?(player))
          commands << GameSurfaces::Command.new(id: "surrender", label: tower?(state) ? _("Surrender Word Tower") : _("Surrender"))
        end
        if %w[random race].include?(state[:options]["variant"]) && owner?(state, player)
          label = state[:options]["variant"] == "race" ? _("Draw another word - reset the race") : _("Draw another word")
          commands << GameSurfaces::Command.new(id: "reroll", label: label, payload: {"round" => state[:round]})
        end
      end
      if state[:last_solution]
        commands << GameSurfaces::Command.new(id: "krowa_definition", label: _("Word definition"), payload: {"word" => state[:last_solution]})
      elsif player && state[:surrender_words].key?(player)
        commands << GameSurfaces::Command.new(id: "krowa_definition", label: _("Word definition"))
      end
      parts << part("commands", GameSurfaces::CommandPanelSpec.new(commands: commands)) unless commands.empty?
      GameSurfaces::CompositeSpec.new(parts: parts)
    end

    def local_action(selection, replay, _viewer)
      return nil unless selection["kind"] == "command"
      return replay.finished? ? :gallery : :gallery_unavailable if selection["action"] == "krowa_gallery"
      return :definition if selection["action"] == "krowa_definition" && selection["word"] && selection["word"] == replay.state[:last_solution]
      nil
    end

    def background_music(replay)
      return nil if replay.finished?
      {"race" => "krowa-race", "tower" => "krowa-word-tower"}.fetch(replay.state[:options]["variant"], "krowa-single")
    end

    def error_sound(status)
      {wrong_length: "krowa-length", unknown_noun: "krowa-unknown", duplicate: "krowa-duplicate"}[status]
    end

    def event_sounds(event, _before, after, viewer, repository)
      return [] unless event["action"] == "krowa_score"
      trial = after.state[:attempts].find { |item| item[:event_id] == repository.event_id(event).to_i }
      return [] unless trial && trial[:matches] == after.state[:length]
      after.state[:options]["variant"] == "race" && !same_user?(trial[:player], viewer) ? ["krowa-opponent-guessed"] : ["krowa-success"]
    end

    def history_entries_for_display(replay, viewer, surface_state: {})
      return replay.history if tower?(replay.state) || !replay.players.any? { |name| same_user?(name, viewer) }
      entries = replay.history.reject { |item| item.kind == :guess && !same_user?(item.actor, viewer) }
      return entries unless solo_view?(replay, viewer)

      trials = replay.state[:attempts].to_h { |trial| [trial[:event_id], trial] }
      entries.map do |item|
        trial = trials[item.event_id] if item.kind == :guess
        next item unless trial

        copy = item.dup
        copy.text = trial_label(trial, replay.state[:length], show_player: false) + "."
        copy
      end
    end

    def describe_event(event, repository, replay, viewer)
      history_entries_for_display(replay, viewer).select { |item| item.event_id == repository.event_id(event).to_i }.map(&:text)
    end

    def participant_status(replay, participant, connected: true)
      return super unless connected
      player = replay.players.find { |name| same_user?(name, participant) }
      result = replay.state[:results][player]
      result && (result[:solved] ? _("guessed") : result[:race_closed] ? _("not guessed") : _("surrendered"))
    end

    def result_text(replay)
      return nil unless replay.finished?
      return _("Invalid table configuration.") if replay.state[:phase] == :invalid
      return _("Word Tower ended. Completed rounds: %{count}.") % {count: replay.state[:completed].length} if tower?(replay.state)
      if solo_variant?(replay.state)
        result = replay.state[:results].values.first
        return _("The word was guessed. Attempts: %{count}.") % {count: result[:attempts]} if result && result[:solved]
        return _("Game over. The word was not guessed.")
      end
      names = replay.state[:winners]
      names.empty? ? _("Nobody guessed the word.") : _("Best result: %{players}.") % {players: names.join(", ")}
    end

    private

    def solo_view?(replay, viewer)
      replay.players.length == 1 && same_user?(replay.players.first, viewer)
    end

    def trial_label(trial, length, show_player:)
      text = _("%{word}, %{matches} of %{length}") % {
        word: trial[:word], matches: trial[:matches], length: length
      }
      show_player ? _("%{player}: %{attempt}") % {player: participant_name(trial[:player]), attempt: text} : text
    end

    def part(id, surface); GameSurfaces::SurfacePart.new(id: id, surface: surface); end
    def information(id, title, text)
      GameSurfaces::QuestionSpec.new(id: id, prompt: title, mode: :information, value: text, read_only: true)
    end
    def list(id, title, labels)
      GameSurfaces::QuestionSpec.new(id: id, prompt: title, mode: :single_choice, read_only: true,
        options: labels.each_with_index.map { |label, index| GameSurfaces::QuestionOption.new(id: index.to_s, label: label) })
    end
    def status_text(replay, viewer)
      return result_text(replay) if replay.finished?
      return _("Preparing the word.") unless replay.state[:phase] == :active
      return _("You are observing the game.") unless replay.players.any? { |name| same_user?(name, viewer) }
      _("Your game is over. Waiting for the other players.")
    end
    def result_summary(state)
      if solo_variant?(state) && state[:players].length == 1
        result = state[:results][state[:players].first]
        count = result ? result[:attempts] : state[:attempts].length
        status = result == nil ? _("Playing.") : result[:solved] ? _("Guessed.") : _("Surrendered.")
        return _("Attempts: %{count}. %{status}") % {count: count, status: status}
      end
      if tower?(state)
        lines = if [:setup, :preparing, :invalid].include?(state[:phase])
          # No current word yet; later setup phases still retain the previous
          # word's length/attempts. Neither is a limit for the next round.
          waiting = [_("Completed rounds: %{count}.") % {count: state[:completed].length}]
          waiting << _("Preparing the word.") unless state[:phase] == :invalid
          waiting
        else
          [_("Completed rounds: %{count}. Attempts this round: %{used} of %{limit}.") % {
            count: state[:completed].length, used: state[:attempts].length, limit: tower_attempt_limit(state[:length])}]
        end
        state[:completed].each_with_index do |round, index|
          lines << _("%{round}. %{word}: %{attempts} attempts") % {
            round: index + 1, word: round[:word], attempts: round[:attempts]
          }
        end
        return lines.join("\r\n")
      end
      metric = state[:options]["race_scoring"] == "time" ? :elapsed : :attempts
      state[:players].sort_by { |player| result = state[:results][player]; result && result[:solved] ? [0, result[metric]] : [1, 0] }.map do |player|
        result = state[:results][player]
        if result.nil?
          _("%{player}: %{attempts} attempts, playing") % {player: participant_name(player), attempts: attempts_for(state, player).length}
        elsif result[:race_closed]
          _("%{player}: not guessed, %{attempts} attempts") % {player: participant_name(player), attempts: result[:attempts]}
        elsif !result[:solved]
          _("%{player}: surrendered") % {player: participant_name(player)}
        else
          _("%{player}: %{attempts} attempts, %{seconds} s") % {
            player: participant_name(player), attempts: result[:attempts], seconds: format('%.3f', result[:elapsed] / 1000.0)
          }
        end
      end.join("\r\n")
    end
  end
end

require_relative '../generated/rulebooks/krowa'
