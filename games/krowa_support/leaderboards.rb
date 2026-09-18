# encoding: UTF-8

require_relative "server_store"

module GameRoomGames
  # Event-driven leaderboard presentation. Persistent queries live in
  # KrowaServerStore; this class only owns forms and user-facing formatting.
  class KrowaLeaderboardClient
    def initialize(program, game, store: nil)
      @program = program
      @game = game
      @store = store || KrowaServerStore.new(
        server_tables: program.game_room_server_tables,
        bank: KrowaWordBank.default,
        user: Session.name
      )
    end

    def run
      unless @store.available?
        alert(_("Krowa leaderboards are temporarily unavailable."))
        return
      end

      index = 0
      options = [
        _("Search for a word"),
        _("Word Tower leaderboard")
      ]
      loop do
        action = nil
        list = ListBox.new(options, header: _("Krowa leaderboards"), index: index, quiet: true)
        open_button = Button.new(_("Open"))
        back_button = Button.new(_("Back"))
        form = GameRoomUI::Form.new([list, open_button, back_button], program: @program, quiet: true)
        form.accept_button = open_button
        form.cancel_button = back_button
        form.hide(open_button)
        form.hide(back_button)
        open_button.on(:press) { index = list.index.to_i; action = :open; form.resume }
        back_button.on(:press) { action = :back; form.resume }
        form.wait
        return if action != :open

        case index
        when 0 then search_words
        when 1 then show_tower_ranking
        end
      end
    end

    def show_word_ranking(word)
      normalized = @game.normalize_word(word)
      results = network(_("Loading word leaderboard")) { @store.word_ranking(normalized) }
      return if results == nil

      previous_attempts = nil
      previous_rank = 0
      rows = results.each_with_index.map do |result, index|
        attempts = result["attempts"].to_i
        rank = attempts == previous_attempts ? previous_rank : index + 1
        previous_attempts = attempts
        previous_rank = rank
        [rank.to_s, result["__insertion_user"].to_s, attempts.to_s,
          score_date(result["first_result_at"])]
      end
      show_table(
        [_('Place'), _('User'), _('Attempts'), _('First result')],
        rows,
        header: _("Leaderboard: %{word}") % {word: normalized},
        empty_label: _("No published results"),
        selectable: false
      )
    end

    def publish_word(word, attempts)
      result = network(_("Publishing result")) { @store.publish_word(word, attempts) }
      case result
      when :published
        alert(_("Result published."))
        show_word_ranking(word)
        true
      when :unchanged
        alert(_("The server already has the same or a better result."))
        show_word_ranking(word)
        true
      else
        alert(_("Could not publish the result."))
        false
      end
    end

    def publish_tower(run_code:, participants:, rounds:)
      result = network(_("Publishing Word Tower result")) do
        @store.publish_tower(run_code: run_code, participants: participants, rounds: rounds)
      end
      case result
      when :published
        alert(_("Word Tower result published."))
        show_tower_ranking
        true
      when :unchanged
        alert(_("This Word Tower result has already been published."))
        show_tower_ranking
        true
      else
        alert(_("Could not publish the Word Tower result."))
        false
      end
    end

    def close; end

    private

    def search_words
      query = nil
      input = EditBox.new(_("Word or word fragment"), text: "", quiet: true, max_length: 32)
      search_button = Button.new(_("Search"))
      cancel_button = Button.new(_("Cancel"))
      form = GameRoomUI::Form.new([input, search_button, cancel_button], program: @program, quiet: true)
      form.accept_button = search_button
      form.cancel_button = cancel_button
      search_button.on(:press) { query = input.text.to_s; form.resume }
      cancel_button.on(:press) { form.resume }
      form.wait
      return if query == nil

      needle = @game.normalize_word(query)
      if needle.empty?
        alert(_("Enter a word or word fragment."))
        return
      end
      words = network(_("Searching words")) { @store.ranked_words }
      return if words == nil
      matches = words.select { |row| row["word"].to_s.include?(needle) }
      show_word_browser(matches, header: _("Search results: %{query}") % {query: needle})
    end

    def show_word_browser(words, header:)
      rows = words.map do |row|
        [row["word"].to_s, row["best_attempts"].to_i.to_s,
          row["result_count"].to_i.to_s, score_date(row["last_result_at"])]
      end
      selected = show_table(
        [_('Word'), _('Best result'), _('Results'), _('Last update')],
        rows, header: header, empty_label: _("No matching words")
      )
      show_word_ranking(words[selected]["word"]) if selected != nil
    end

    def show_tower_ranking
      results = network(_("Loading Word Tower leaderboard")) { @store.tower_ranking }
      return if results == nil

      previous_rounds = nil
      previous_rank = 0
      rows = results.each_with_index.map do |result, index|
        rounds = result["rounds"].to_i
        rank = rounds == previous_rounds ? previous_rank : index + 1
        previous_rounds = rounds
        previous_rank = rank
        names = @store.participants_from(result)
        names = [result["__insertion_user"].to_s] if names.empty?
        [rank.to_s, names.join(", "), rounds.to_s, score_date(result["__insertion_time"])]
      end
      selected = show_table(
        [_('Place'), _('Participants'), _('Rounds'), _('Date')],
        rows, header: _("Word Tower leaderboard"), empty_label: _("No results")
      )
      show_tower_details(results[selected]) if selected != nil
    end

    def show_tower_details(result)
      rounds = network(_("Loading Word Tower rounds")) do
        @store.tower_rounds(result["run_code"])
      end
      return if rounds == nil

      rows = rounds.map do |round|
        [round["round"].to_i.to_s, round["word"].to_s,
          round["attempts"].to_i.to_s, round["solved"].to_i == 1 ? _("guessed") : _("not guessed")]
      end
      participants = @store.participants_from(result)
      show_table(
        [_('Round'), _('Word'), _('Attempts'), _('Result')],
        rows,
        header: _("Word Tower: %{participants}") % {participants: participants.join(", ")},
        empty_label: _("No saved rounds"), selectable: false
      )
    end

    def show_table(columns, rows, header:, empty_label:, selectable: true)
      action = nil
      table = TableBox.new(columns, rows, header: header, quiet: true, empty_label: empty_label)
      open_button = Button.new(selectable ? _("Open") : _("Close"))
      close_button = Button.new(_("Close"))
      controls = selectable ? [table, open_button, close_button] : [table, close_button]
      form = GameRoomUI::Form.new(controls, program: @program, quiet: true)
      form.accept_button = selectable ? open_button : close_button
      form.cancel_button = close_button
      form.hide(open_button) if selectable
      form.hide(close_button)
      open_button.on(:press) do
        action = :open if !rows.empty?
        form.resume
      end if selectable
      close_button.on(:press) { form.resume }
      form.wait
      action == :open ? table.index.to_i : nil
    end

    def score_date(value)
      timestamp = value.to_i
      timestamp.positive? ? Time.at(timestamp).strftime("%Y-%m-%d %H:%M") : ""
    rescue StandardError
      ""
    end

    def network(title)
      EltenAPI::Tasks.run(title: title, cancellable: true, show_after: 2) { yield }
    rescue EltenAPI::Tasks::Cancelled
      nil
    rescue StandardError => error
      Log.warning("Krowa leaderboard: #{error.class}: #{error.message}") if defined?(Log)
      alert(_("Could not connect to the Krowa leaderboard."))
      nil
    end
  end
end
