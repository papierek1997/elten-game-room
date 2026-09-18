# encoding: UTF-8

module GameRoomGames
  module KrowaPresentation
    def rule_sections
      # Generated from docs/rulebooks/krowa.json; see tools/compile-rulebooks.rb.
      [
        rule_section(:goal, GameRoomRules.translate("Goal"),
          GameRoomRules.translate("Guess a Polish noun. An attempt tells you how many letters are in the correct positions, for example 2 of 5. It does not identify which letters match.")),
        rule_section(:setup, GameRoomRules.translate("Setup"),
          GameRoomRules.translate("The host selects the table variant. Daily Krowa and Random word can be started alone; Race and Word Tower require at least two players. A table holds up to eight players."),
          GameRoomRules.translate("Daily Krowa is private and cannot be joined or observed. Anyone joining a Random word table becomes an observer and can follow the player's attempts without receiving an answer field. Race and Word Tower use the standard Game Room invitations and observer roles."),
          GameRoomRules.translate("The host must remain at the table: their client checks attempts while keeping the solution in local hidden storage.")),
        rule_section(:play, GameRoomRules.translate("How to play"),
          GameRoomRules.translate("Type a noun and press Enter. Every submission clears the field. A wrong length, a word outside the dictionary, a duplicate, or an out-of-turn attempt does not use an attempt."),
          GameRoomRules.translate("In a single-player Daily Krowa or Random word game, the add button stores the entered noun in the user's dictionary and immediately checks it as an attempt. The button is unavailable in multiplayer. The person adding a word is responsible for it being a noun. Solutions are drawn from the shared database."),
          GameRoomRules.translate("In Race, everyone guesses independently. With time scoring, the shortest time from the start of the word to the correct submission wins; the clock is synchronized with the server and waiting for verification does not increase the result. With attempt scoring, the fewest valid attempts wins. Equal results are a shared win."),
          GameRoomRules.translate("In Word Tower, you take turns. Words have 3 to 8 letters and the shared attempt limit is the word length multiplied by 8. Guessing the word starts another round with a different word. History and the current turn are shared.")),
        rule_section(:ending, GameRoomRules.translate("Ending the game"),
          GameRoomRules.translate("Daily Krowa and Random word end after guessing or surrendering. In a Race scored by time, the word is revealed when only one active player remains. In a Race scored by attempts, the last active player may continue up to the best solved attempt count; after a failed attempt at that count, the word is revealed. If nobody solved, it is revealed immediately. Attempts already waiting to be checked are resolved first. Observers do not block the ending. Results remain at the table."),
          GameRoomRules.translate("A person who surrenders a Race immediately learns the solution without revealing it to players who are still racing."),
          GameRoomRules.translate("Word Tower ends when the limit is exhausted or the host surrenders. Its score is the number of completed rounds; the round list contains words and attempt counts."),
          GameRoomRules.translate("After a word ends, the solution is revealed. The Word definition button opens its SJP description; a missing description also remains readable."),
          GameRoomRules.translate("Escape leaves the table. Starting Daily Krowa consumes today's puzzle for the account, so it cannot be reopened after leaving. Other variants use the standard Game Room table-leaving rules.")),
        rule_section(:variants, GameRoomRules.translate("Variants and table options"),
          GameRoomRules.translate("Daily Krowa: a common 3-to-9-letter word selected for the Warsaw date using server time. Random word: 3 to 13 letters or a random length. Race: the same lengths and a choice between time and attempt scoring. Word Tower: random lengths from 3 to 8 without a length setting."),
          GameRoomRules.translate("All options appear in one table form. Length applies to Random word and Race, while scoring applies only to Race. Daily Krowa and Word Tower ignore those fields."),
          GameRoomRules.translate("The Race host can draw a different word. The previous word is revealed and every player's attempts and time are reset. This is not a win or a completed round."),
          GameRoomRules.translate("Music and sound effects are disabled by default, have separate volume controls, and use Elten's audio output. Race and Word Tower have separate music; Daily Krowa and Random word share one track.")),
        rule_section(:controls, GameRoomRules.translate("Controls"),
          GameRoomRules.translate("Tab and Shift+Tab move through the answer, add-to-dictionary button in solo play, attempts, results, chat, history, users, and game commands. Word Tower also includes the current turn. Lists support arrow keys and letter navigation. Enter checks the typed word; Enter or Space activates buttons."),
          GameRoomRules.translate("Ctrl+D opens Krowa settings for audio and the custom dictionary. In the dictionary list, Space selects words and the shared button removes them. Up raises volume by 1% and Down lowers it. F1 reads shortcuts and Ctrl+F1 opens these rules. Invitations use the shared Game Room menu, including Ctrl+I and Ctrl+Shift+I."))
      ]
    end

    def game_view_spec(replay, viewer)
      GameRoomLayout::ViewSpec.new(surface: surface_spec(replay, viewer),
        trailing_parts: ["commands"], restartable: !solo_variant?(replay.state),
        finished_text: solo_variant?(replay.state) ? _("Game over.") : nil,
        status_commands: krowa_status_commands)
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
          extra_commands: extra_commands))
      else
        parts << part("status", information("krowa-status", _("Krowa"), status_text(replay, viewer)))
      end
      trials = state[:attempts].select { |trial| tower?(state) || !player || trial[:player] == player }
      labels = trials.map { |trial| trial_label(trial, state[:length], show_player: !solo_view?(replay, viewer)) }
      parts << part("attempts", list("krowa-attempts", _("Attempts"), labels.empty? ? [_("No attempts")] : labels))
      parts << part("results", information("krowa-results", _("Results"), result_summary(state)))
      if tower?(state)
        parts << part("turn", list("krowa-turn", _("Now playing"), [replay.current_player || _("Waiting for the next round")]))
      end
      commands = []
      if state[:phase] == :active && player
        if (tower?(state) && owner?(state, player)) || (!tower?(state) && !state[:results].key?(player))
          commands << GameSurfaces::Command.new(id: "surrender", label: tower?(state) ? _("Surrender Word Tower") : _("Surrender"))
        end
        if state[:options]["variant"] == "race" && owner?(state, player)
          commands << GameSurfaces::Command.new(id: "reroll", label: _("Draw another word - reset the race"))
        end
      end
      commands << GameSurfaces::Command.new(id: "krowa_audio", label: _("Krowa settings (Ctrl+D)"))
      if state[:last_solution]
        commands << GameSurfaces::Command.new(id: "krowa_definition", label: _("Word definition"), payload: {"word" => state[:last_solution]})
      end
      parts << part("commands", GameSurfaces::CommandPanelSpec.new(commands: commands))
      GameSurfaces::CompositeSpec.new(parts: parts)
    end

    def custom_game_shortcuts(_replay, _viewer)
      [GameShortcut.new(key: "d", modifiers: [:control], label: _("Krowa settings"),
        kind: :action, action_kind: "command", action_name: "krowa_audio")]
    end

    def local_action(selection, replay, _viewer)
      return nil unless selection["kind"] == "command"
      return :audio if selection["action"] == "krowa_audio"
      return :gallery if selection["action"] == "krowa_gallery"
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
      show_player ? _("%{player}: %{attempt}") % {player: trial[:player], attempt: text} : text
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
        lines = [_("Completed rounds: %{count}. Attempts this round: %{used} of %{limit}.") % {
          count: state[:completed].length, used: state[:attempts].length, limit: tower_attempt_limit(state[:length])}]
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
          _("%{player}: %{attempts} attempts, playing") % {player: player, attempts: attempts_for(state, player).length}
        elsif result[:race_closed]
          _("%{player}: not guessed, %{attempts} attempts") % {player: player, attempts: result[:attempts]}
        elsif !result[:solved]
          _("%{player}: surrendered") % {player: player}
        else
          _("%{player}: %{attempts} attempts, %{seconds} s") % {
            player: player, attempts: result[:attempts], seconds: format('%.3f', result[:elapsed] / 1000.0)
          }
        end
      end.join("\r\n")
    end
  end
end
