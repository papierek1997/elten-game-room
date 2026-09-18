# encoding: UTF-8

require "digest"
require "json"
require_relative "../../lib/game_audio"
require_relative "../../lib/game_server_clock"
require_relative "leaderboards"
require_relative "server_store"
require_relative "sjp_definition_provider"
require_relative "profile"

module GameRoomGames
  # Local presentation/services adapter. No rooms, polling or multiplayer
  # writes: every move still goes through GameScreen and GameRepository.
  class KrowaClient
    def initialize(program, game)
      @program, @game = program, game
      @audio = GameRoomAudio.new(program, game_id: game.id)
      @definitions = GameRoomKrowa::SjpDefinitionProvider.new
      @shown_words = {}
      @daily_recorded = {}
      @publication_offered = {}
      @clock = GameRoomServerClock.new(fetch: -> {
        EltenLink::System.server_time(EltenLink::Client.new(program), timeout: 5)
      })
    end

    def start
      prepare_local_services
      EltenAPI::Tasks.run(title: _("Loading server time"), cancellable: true, show_after: 2) { @clock.synchronize }
      true
    rescue StandardError => error
      Log.warning("Krowa server clock: #{error.class}: #{error.message}") if defined?(Log)
      alert(_("Could not retrieve the server time. Please try again."))
      false
    end

    def open_gallery
      prepare_local_services
      gallery_dialog
    end

    def open_settings
      prepare_local_services
      settings_dialog
    end

    def prepare_local_services
      return true if @profile && @server_store && @leaderboards

      @profile = KrowaProfile.new(@program, user: Session.name)
      @server_store = KrowaServerStore.new(
        server_tables: @program.game_room_server_tables,
        bank: KrowaWordBank.default,
        user: Session.name
      )
      @leaderboards = KrowaLeaderboardClient.new(@program, @game, store: @server_store)
      true
    end

    def now; @clock.now; end

    def context_data
      {"dictionary" => @profile ? @profile.data["dictionary"] : []}
    end

    def before_wait(replay, viewer)
      @audio.update(@game.background_music(replay))
      @profile&.observe(replay)
      record_daily_completion(replay, viewer)
    rescue StandardError => error
      Log.warning("Krowa local profile: #{error.class}: #{error.message}") if defined?(Log)
      alert(_("Could not save the local gallery or dictionary.")) unless @profile_error_announced
      @profile_error_announced = true
    end

    def action(selection, replay, viewer)
      case @game.local_action(selection, replay, viewer)
      when :audio then settings_dialog; true
      when :definition then definition_dialog(selection["word"]); true
      when :gallery then gallery_dialog; true
      else false
      end
    end

    def error(status)
      @audio.play(@game.error_sound(status))
    end

    def automatic_error(status)
      return if @last_automatic_error == status
      @last_automatic_error = status
      alert(@game.move_error(status))
    end

    def event(event, before, after, viewer, repository)
      @game.event_sounds(event, before, after, viewer, repository).each { |asset| @audio.play(asset) }
    end

    def after_events(replay, viewer)
      record_daily_completion(replay, viewer)
      show_surrendered_solution(replay, viewer)
      # Publish the verified reveal before any modal dialog can pause the host.
      # Otherwise observers wait until the host closes their definition window.
      return if [:preparing, :revealing].include?(replay.state[:phase])
      return if replay.state[:options]["variant"] == "race" && !replay.finished?
      word = replay.state[:last_solution]
      return if !word || @shown_words[word]
      @shown_words[word] = true
      definition_dialog(word)
      offer_result_publication(replay, viewer, word)
    end

    def close; @audio.close; end

    private

    def gallery_dialog
      entries = @profile.data["gallery"]
      mode = :latest
      words = []
      list = ListBox.new([], header: _("Krowa gallery"), quiet: true, empty_label: _("No guessed words"))
      sort = lambda do
        selected = words[list.index]
        words = entries.keys.sort_by do |word|
          case mode
          when :attempts then [entries[word]["attempts"], word]
          when :length then [word.length, word]
          else [-entries[word]["at"], word]
          end
        end
        list.options = words.map do |word|
          _("%{word}: %{attempts} attempts, %{length} letters") % {
            word: word, attempts: entries[word]["attempts"], length: word.length
          }
        end
        list.index = words.index(selected) || 0
      end
      list.bind_context do |menu|
        {latest: _("Newest"), attempts: _("Number of attempts"), length: _("Number of letters")}.each do |key, label|
          menu.option(label) { mode = key; sort.call; list.focus }
        end
      end
      list.on(:select) { @leaderboards.show_word_ranking(words[list.index]) unless words.empty? }
      close = Button.new(_("Close"))
      form = GameRoomUI::Form.new([list, close], program: @program, quiet: true)
      form.cancel_button = close
      close.on(:press) { form.resume }
      sort.call
      form.wait
    end

    def settings_dialog
      values = @audio.settings
      music = CheckBox.new(_("Music"), checked: values["music"])
      music_volume = volume_list(_("Music volume"), values["music_volume"])
      effects = CheckBox.new(_("Sound effects"), checked: values["effects"])
      effects_volume = volume_list(_("Sound effects volume"), values["effects_volume"])
      dictionary = Button.new(_("My dictionary"))
      save, cancel = Button.new(_("Save")), Button.new(_("Cancel"))
      form = GameRoomUI::Form.new([music, music_volume, effects, effects_volume, dictionary, save, cancel],
        program: @program, quiet: true)
      form.cancel_button = cancel
      dictionary.on(:press) do
        dictionary_dialog
        dictionary.focus
      end
      save.on(:press) do
        @audio.save("music" => music.checked, "effects" => effects.checked,
          "music_volume" => 100 - music_volume.index, "effects_volume" => 100 - effects_volume.index)
        form.resume
      end
      cancel.on(:press) { form.resume }
      form.wait
    end

    def dictionary_dialog
      loop do
        words = @profile.data["dictionary"].to_a.sort
        if words.empty?
          alert(_("Your dictionary is empty."))
          return
        end

        selected = nil
        list = ListBox.new(words, header: _("My dictionary - select words to remove with Space"),
          quiet: true, flags: ListBox::Flags::MultiSelection)
        remove = Button.new(_("Remove selected"))
        close = Button.new(_("Close"))
        form = GameRoomUI::Form.new([list, remove, close], program: @program, quiet: true)
        form.cancel_button = close
        remove.on(:press) do
          selected = list.multiselections.filter_map { |index| words[index] }
          form.resume
        end
        close.on(:press) { form.resume }
        form.wait
        return if selected == nil
        if selected.empty?
          alert(_("Select at least one word."))
          next
        end
        next unless confirm(_("Remove the selected words from your dictionary?"))

        @profile.remove_dictionary(selected)
        alert(_("Removed words: %{words}.") % {words: selected.join(", ")})
      end
    rescue StandardError => error
      Log.warning("Krowa dictionary removal: #{error.class}: #{error.message}") if defined?(Log)
      alert(_("Could not save changes to your dictionary."))
    end

    def volume_list(title, value)
      ListBox.new(100.downto(0).map { |number| "#{number}%" }, header: title, index: 100 - value, quiet: true)
    end

    def definition_dialog(word)
      definition = begin
        EltenAPI::Tasks.run(title: _("Word definition"), cancellable: true, show_after: 2) { @definitions.definition_for(word) }
      rescue GameRoomKrowa::DefinitionNotFoundError
        _("No definition in SJP.")
      rescue StandardError
        _("Could not retrieve the definition from SJP.")
      end
      display_word = utf8_text(word)
      display_definition = utf8_text(definition || _("No definition was retrieved."))
      text = EditBox.new(_("Solution"), type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
        text: _("%{word}\r\n\r\n%{definition}\r\n\r\nSource: https://sjp.pl/") % {
          word: display_word, definition: display_definition
        }, quiet: true)
      close = Button.new(_("Close"))
      form = GameRoomUI::Form.new([text, close], program: @program, quiet: true)
      form.accept_button = close
      form.cancel_button = close
      close.on(:press) { form.resume }
      form.wait
    end

    def utf8_text(value)
      text = value.to_s.dup
      text.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::BINARY
      text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�").scrub
    end

    def record_daily_completion(replay, viewer)
      state = replay.state
      return unless state[:options]["variant"] == "daily"
      own = state[:results].find { |name, _result| @game.send(:same_user?, name, viewer) }
      return if own == nil || state[:day].to_s.empty? || @daily_recorded[state[:day]]

      result = EltenAPI::Tasks.run(title: _("Saving Daily Krowa"), cancellable: false, show_after: 2) do
        @server_store.record_daily_completion(state[:day], solved: own.last[:solved] == true)
      end
      if result
        @daily_recorded[state[:day]] = true
      else
        @daily_recorded[state[:day]] = :failed
        alert(_("Could not save Daily Krowa completion on the server. The program will try again when the game is reopened."))
      end
    rescue StandardError => error
      @daily_recorded[state[:day]] = :failed if state && state[:day]
      Log.warning("Krowa daily completion: #{error.class}: #{error.message}") if defined?(Log)
      alert(_("Could not save Daily Krowa completion on the server. The program will try again when the game is reopened."))
    end

    def show_surrendered_solution(replay, viewer)
      return unless replay.state[:options]["variant"] == "race"
      pair = replay.state[:surrender_words].find do |player, word|
        word && @game.send(:same_user?, player, viewer)
      end
      return if pair == nil || @shown_words[pair.last]

      @shown_words[pair.last] = true
      definition_dialog(pair.last)
    end

    def offer_result_publication(replay, viewer, word)
      state = replay.state
      variant = state[:options]["variant"]
      if %w[random daily].include?(variant) && replay.players.length == 1
        player, result = state[:results].find { |name, _value| @game.send(:same_user?, name, viewer) }
        return unless player && result[:solved]
        key = "word:#{word}:#{result[:attempts]}:#{state[:started_ms]}"
        return if @publication_offered[key]
        @publication_offered[key] = true
        if confirm(_("Publish the result for %{word}: %{attempts} attempts?") % {word: word, attempts: result[:attempts]})
          @leaderboards.publish_word(word, result[:attempts])
        end
        return
      end

      return unless variant == "tower" && replay.finished?
      return unless replay.players.first && @game.send(:same_user?, replay.players.first, viewer)
      rounds = tower_publication_rounds(state)
      key = "tower:#{tower_run_code(replay, rounds)}"
      return if @publication_offered[key]
      @publication_offered[key] = true
      if confirm(_("Publish the Word Tower result: %{rounds} completed rounds?") % {
        rounds: rounds.count { |round| round[:solved] }
      })
        @leaderboards.publish_tower(
          run_code: tower_run_code(replay, rounds),
          participants: replay.players,
          rounds: rounds
        )
      end
    end

    def tower_publication_rounds(state)
      rounds = state[:completed].map do |round|
        {word: round[:word], attempts: round[:attempts], solved: true}
      end
      if state[:last_solution]
        rounds << {word: state[:last_solution], attempts: state[:attempts].length, solved: false}
      end
      rounds
    end

    def tower_run_code(replay, rounds)
      source = JSON.generate([
        replay.players.map { |name| name.to_s.downcase }, replay.state[:started_ms], rounds
      ])
      [(Digest::SHA256.hexdigest(source)[0, 8].to_i(16) & 0x3fffffff), 1].max
    end
  end
end
