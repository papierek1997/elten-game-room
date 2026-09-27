# encoding: UTF-8

require_relative "../../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  module KrowaPresentation
    def rule_sections
      # Generated from docs/rulebooks/krowa.json; see tools/compile-rulebooks.rb.
      [
        rule_section(:goal, GameRoomRules.translate("Reading the clues"),
          GameRoomRules.translate("In Krowa, your task is to guess a Polish noun. At the very beginning, a word is drawn and you are told how many letters it has. You enter guesses with the same number of letters as the secret word. After each attempt, you hear how many letters occupy the same positions in both words. If the answer is kot and you enter sok, you get 1 out of 3: only the middle letter matches. K is not counted because it is the first letter in kot but the third in sok."),
          GameRoomRules.translate("By comparing successive clues, you gradually narrow down the possibilities.")),
        rule_section(:setup, GameRoomRules.translate("Play on your own or with others"),
          GameRoomRules.translate("If you are the table host, you choose the game variant."),
          GameRoomRules.translate("In solo mode, you have two options: Daily Krowa, with a new word each day that is the same for everyone, or Random word, where you can choose the word length. In the latter mode, you have one superpower. You can add words to a dictionary that stores your nouns locally. Hmmm... if you put asdfasdfasdf in there, it will be stored too, but I hope having fun matters more than racking up leaderboard scores. So, if you want to use smerfy as a guess, just press \"Add noun to dictionary and check\". You will not be able to use that word in multiplayer modes, though. Not because I dislike the Smurfs; it is simply not in the database."),
          GameRoomRules.translate("There are also two ways to play with others:"),
          GameRoomRules.translate("Race, where you compete to guess the same word. Depending on the setting, the winner is the person who uses fewer attempts or guesses faster."),
          GameRoomRules.translate("Or Word Tower, a cooperative game. Words are drawn, and everyone takes turns entering guesses while seeing what the other players have entered."),
          GameRoomRules.translate("Daily Krowa is private: nobody can join or observe it. That would make guessing it later far too easy!"),
          GameRoomRules.translate("You can observe all the other modes if the table is public or you are invited to it. If you join Krowa while someone is guessing a random word, you can check the word length and the list and number of their attempts. You can also write in chat: \"p in the fourth position! Seriously, the fourth letter is p!\" But I am not encouraging that.")),
        rule_section(:play, GameRoomRules.translate("How to play"),
          GameRoomRules.translate("Type a noun and press Enter. Each entry disappears from the edit field after submission. A wrong length, a word outside the dictionary, a repeated guess or an attempt made out of turn does not use up an attempt, but does make a funny sound."),
          GameRoomRules.translate("More about the modes:"),
          GameRoomRules.translate("Daily Krowa can draw a word between three and nine letters long. The word is determined using server time, so if you need a different one, you would have to hack into the server and change the date. You can open Daily Krowa only once. If you guess the word, give up or leave the game, it remains unavailable to your account until the next day."),
          GameRoomRules.translate("In Race, everyone guesses independently. You can set the word length or leave it to chance. Either way, you can draw another word, which resets the attempts. You can also set the winning criterion mentioned above:"),
          GameRoomRules.translate("- With time scoring, the shortest time from the start of the word to the submission of the correct answer wins, measured by a clock synchronized with the server;"),
          GameRoomRules.translate("- With attempt scoring, the fewest valid submissions wins. Equal results mean a shared victory."),
          GameRoomRules.translate("In Race, if everyone else has guessed either faster than you or in fewer attempts, the game ends and the word is revealed to you."),
          GameRoomRules.translate("In Word Tower, you take turns, and guessing the word starts another round. Words have 3 to 8 letters, and the shared attempt limit is:"),
          GameRoomRules.translate("Three-letter words: 15 attempts"),
          GameRoomRules.translate("Four-letter words: 24 attempts"),
          GameRoomRules.translate("Five-letter words: 30 attempts"),
          GameRoomRules.translate("Six-letter words: 42 attempts"),
          GameRoomRules.translate("Seven-letter words: 49 attempts"),
          GameRoomRules.translate("Eight-letter words: 64 attempts."),
          GameRoomRules.translate("The tower ends when you run out of attempts or the host gives up. Your score is the number of completed rounds. The round list in the leaderboard contains the words and attempt counts."),
          GameRoomRules.translate("Krowa's music and sound effects are off by default. Ctrl+D opens their switches and separate volume sliders. These sounds also respect the shared game-sound mute and volume settings in Game Room.")),
        rule_section(:gallery, GameRoomRules.translate("Your gallery, dictionary and rankings"),
          GameRoomRules.translate("The gallery remembers the words you have guessed on your own and your best attempt count for each one. You can open it before a game or after it ends. Its menu lets you sort by date, attempt count or word length. Select a word with Enter to open its leaderboard. After a game, you can agree to publish your result, which also opens the leaderboard for that word."),
          GameRoomRules.translate("The Rankings item in the main menu gives you access to word results and Word Tower round counts. Your gallery and custom dictionary are stored locally and separately for each account. To remove your own words, open My dictionary in Krowa settings, select them with Space and choose Delete selected.")),
        rule_section(:saving, GameRoomRules.translate("Saving your game"),
          GameRoomRules.translate("The table creator can save a Race or Word Tower while a word is being guessed, once all submitted attempts have been checked. The local save lets you resume the game with the same players at a new table. Solo games cannot be saved for later.")),
        rule_section(:controls, GameRoomRules.translate("Controls"),
          GameRoomRules.translate("Tab: move to the next field. In table settings, fields unrelated to the selected variant are hidden, so you do not need to skip them."),
          GameRoomRules.translate("Shift+Tab: move to the previous field."),
          GameRoomRules.translate("Enter in the answer field: submit the typed noun and clear the field for the next attempt."),
          GameRoomRules.translate("Ctrl+D: open Krowa settings for music, effects and your custom dictionary."))
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
        if %w[random race].include?(state[:options]["variant"]) && owner?(state, player)
          label = state[:options]["variant"] == "race" ? _("Draw another word - reset the race") : _("Draw another word")
          commands << GameSurfaces::Command.new(id: "reroll", label: label, payload: {"round" => state[:round]})
        end
      end
      commands.concat(krowa_status_commands) unless replay.finished?
      if state[:last_solution]
        commands << GameSurfaces::Command.new(id: "krowa_definition", label: _("Word definition"), payload: {"word" => state[:last_solution]})
      elsif player && state[:surrender_words].key?(player)
        commands << GameSurfaces::Command.new(id: "krowa_definition", label: _("Word definition"))
      end
      parts << part("commands", GameSurfaces::CommandPanelSpec.new(commands: commands))
      GameSurfaces::CompositeSpec.new(parts: parts)
    end

    def custom_game_shortcuts(_replay, _viewer)
      room_shortcuts
    end

    def room_shortcuts
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
