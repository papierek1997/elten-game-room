# encoding: UTF-8

require "json"

module GameRoomGames
  # Persistent, account-aware Krowa data. Match state still belongs exclusively
  # to Game Room events; these tables contain availability and published scores.
  class KrowaServerStore
    DAILY_TABLE = "krowa_daily_completions".freeze
    WORD_TABLE = "krowa_word_scores".freeze
    TOWER_TABLE = "krowa_tower_scores".freeze
    TOWER_ROUNDS_TABLE = "krowa_tower_rounds".freeze
    DAILY_SOLVED = 1
    DAILY_SURRENDERED = 2
    DAILY_OPENED = 3
    MAX_WORD_RESULTS = 2_000
    MAX_TOWER_RESULTS = 500

    def initialize(server_tables:, bank:, user:)
      @server_tables = server_tables
      @bank = bank
      @user = user.to_s.strip
      raise ArgumentError, "Krowa server store requires a user" if @user.empty?
    end

    def available?
      @server_tables.respond_to?(:available?) && @server_tables.available?
    end

    def synchronize_daily(date_ids)
      return false unless available?

      dates = Array(date_ids).map { |date| normalized_date(date) }.compact.uniq.last(500)
      return true if dates.empty?

      present = daily_table.select(limit: 500).to_a.each_with_object({}) do |row, result|
        result[row["day_key"].to_i] = true
      end
      missing = dates.reject { |date| present.key?(date_key(date)) }
      missing.each_slice(100) do |batch|
        inserted = daily_table.insert_many(batch.map do |date|
          {"day_key" => date_key(date), "status" => DAILY_SOLVED}
        end)
        return false unless inserted.to_a.length == batch.length
      end
      true
    end

    def daily_completed?(date_id)
      date = normalized_date(date_id)
      return false if date == nil || !available?

      !daily_table.select(where: {"day_key" => date_key(date)}, limit: 1).to_a.empty?
    end

    # Claims today's puzzle for this account before the Game Room session is
    # created. Re-reading the first row makes concurrent starts on two devices
    # deterministic: only the insertion with the earliest server id wins.
    def record_daily_open(date_id)
      date = normalized_date(date_id)
      return :unavailable if date == nil || !available?
      return :already_used if daily_completed?(date)

      inserted = daily_table.insert(
        "day_key" => date_key(date),
        "status" => DAILY_OPENED
      )
      return :unavailable if inserted == nil

      first = daily_table.select(
        where: {"day_key" => date_key(date)},
        order: [["__id", "asc"]],
        limit: 1
      ).to_a.first
      return :unavailable if first == nil

      inserted_id = (inserted["__id"] || inserted[:__id]).to_i
      first_id = (first["__id"] || first[:__id]).to_i
      same_row = inserted_id.positive? && inserted_id == first_id
      same_row ||= first.equal?(inserted) || first.to_h == inserted.to_h
      same_row ? :opened : :already_used
    end

    def record_daily_completion(date_id, solved:)
      date = normalized_date(date_id)
      return false if date == nil || !available?
      return true if daily_completed?(date)

      daily_table.insert(
        "day_key" => date_key(date),
        "status" => solved ? DAILY_SOLVED : DAILY_SURRENDERED
      ) != nil
    end

    # Returns :published, :unchanged or :unavailable.
    def publish_word(word, attempts)
      normalized = normalized_ranked_word(word)
      count = attempts.to_i
      return :unavailable if normalized == nil || count <= 0 || !available?

      own = word_table.select(
        where: {"word" => normalized, "__insertion_user" => @user},
        order: [["attempts", "asc"]], limit: 1
      ).to_a.first
      return :unchanged if own && own["attempts"].to_i <= count

      inserted = word_table.insert("word" => normalized, "attempts" => count)
      inserted == nil ? :unavailable : :published
    end

    def word_ranking(word, limit: 25)
      normalized = normalized_ranked_word(word)
      return [] if normalized == nil || !available?

      word_table.select(
        where: {"word" => normalized},
        columns: ["__insertion_user"],
        group_by: ["__insertion_user"],
        aggregates: {
          "attempts" => {"function" => "min", "column" => "attempts"},
          "first_result_at" => {"function" => "min", "column" => "__insertion_time"}
        },
        order: [["attempts", "asc"], ["__insertion_user", "asc"]],
        limit: [[limit.to_i, 1].max, 100].min
      ).to_a
    end

    # One row per ranked word. max(__insertion_time) makes both a first result
    # and a later personal best move the word to the top of this browser.
    def ranked_words(limit: MAX_WORD_RESULTS)
      return [] unless available?

      word_table.select(
        columns: ["word"],
        group_by: ["word"],
        aggregates: {
          "last_result_at" => {"function" => "max", "column" => "__insertion_time"},
          "best_attempts" => {"function" => "min", "column" => "attempts"},
          "result_count" => {"function" => "count", "column" => "__id"}
        },
        order: [["last_result_at", "desc"], ["word", "asc"]],
        limit: [[limit.to_i, 1].max, MAX_WORD_RESULTS].min
      ).to_a.select { |row| normalized_ranked_word(row["word"]) != nil }
    end

    # Details are inserted first. A ranking row therefore never points at a
    # half-written run when a bulk operation fails.
    def publish_tower(run_code:, participants:, rounds:)
      code = run_code.to_i
      return :unavailable if code <= 0 || !available?
      return :unchanged unless tower_table.select(where: {"run_code" => code}, limit: 1).to_a.empty?

      names = Array(participants).map(&:to_s).map(&:strip).reject(&:empty?).uniq
      details = Array(rounds).each_with_index.map do |round, index|
        word = normalized_ranked_word(round[:word] || round["word"])
        attempts = (round[:attempts] || round["attempts"]).to_i
        solved = round.key?(:solved) ? round[:solved] : round["solved"]
        return :unavailable if word == nil || attempts.negative?
        {"run_code" => code, "round" => index + 1, "word" => word,
          "attempts" => attempts, "solved" => solved == false ? 0 : 1}
      end
      details.each_slice(100) do |batch|
        inserted = tower_rounds_table.insert_many(batch)
        return :unavailable unless inserted.to_a.length == batch.length
      end
      completed = details.count { |round| round["solved"] == 1 }
      inserted = tower_table.insert(
        "run_code" => code,
        "rounds" => completed,
        "participants" => JSON.generate(names)
      )
      inserted == nil ? :unavailable : :published
    end

    def tower_ranking(limit: 100)
      return [] unless available?

      tower_table.select(
        order: [["rounds", "desc"], ["__insertion_time", "asc"]],
        limit: [[limit.to_i, 1].max, MAX_TOWER_RESULTS].min
      ).to_a
    end

    def tower_rounds(run_code)
      code = run_code.to_i
      return [] if code <= 0 || !available?

      tower_rounds_table.select(
        where: {"run_code" => code}, order: [["round", "asc"]], limit: 500
      ).to_a
    end

    def participants_from(row)
      value = JSON.parse(row["participants"].to_s)
      value.is_a?(Array) ? value.map(&:to_s).reject(&:empty?) : []
    rescue JSON::ParserError
      []
    end

    private

    def daily_table; @daily_table ||= @server_tables.fetch(DAILY_TABLE); end
    def word_table; @word_table ||= @server_tables.fetch(WORD_TABLE); end
    def tower_table; @tower_table ||= @server_tables.fetch(TOWER_TABLE); end
    def tower_rounds_table; @tower_rounds_table ||= @server_tables.fetch(TOWER_ROUNDS_TABLE); end

    def normalized_date(value)
      text = value.to_s
      /\A\d{4}-\d{2}-\d{2}\z/.match?(text) ? text : nil
    end

    def date_key(date)
      date.delete("-").to_i
    end

    def normalized_ranked_word(value)
      word = @bank.normalize(value)
      @bank.include?(word) ? word : nil
    end
  end
end
