# encoding: UTF-8

require "json"
require "date"
require_relative 'attempt_archive'

module GameRoomGames
  # Persistent, account-aware Krowa data. Match state still belongs exclusively
  # to Game Room events; these tables contain availability and published scores.
  class KrowaServerStore
    DAILY_TABLE = "krowa_daily_completions".freeze
    DAILY_SCORES_TABLE = "krowa_daily_scores".freeze
    DAILY_ASSIGNMENTS_TABLE = "krowa_daily_assignments".freeze
    WORD_TABLE = "krowa_word_scores".freeze
    TOWER_TABLE = "krowa_tower_scores".freeze
    TOWER_ROUNDS_TABLE = "krowa_tower_rounds".freeze
    DAILY_SOLVED = 1
    DAILY_SURRENDERED = 2
    DAILY_OPENED = 3
    MAX_WORD_RESULTS = 2_000
    MAX_TOWER_RESULTS = 500

    def initialize(server_tables:, bank:, user:, program: nil, schema_reader: nil)
      @server_tables = server_tables
      @bank = bank
      @user = user.to_s.strip
      raise ArgumentError, "Krowa server store requires a user" if @user.empty?
      @schema_reader = schema_reader
      if !@schema_reader && program&.respond_to?(:server_app_uuid)
        uuid = program.server_app_uuid
        @schema_reader = -> { EltenLink::Apps.schema(EltenLink::Client.new, uuid) }
      end
    end

    def available?
      @server_tables.respond_to?(:available?) && @server_tables.available?
    end

    # Read once per services instance, on its existing Tasks worker. Old
    # servers can still accept scores without optional history columns.
    def attempt_histories_available?
      return true unless @schema_reader
      return @attempt_schema_ready if defined?(@attempt_schema_ready)
      schema = @schema_reader.call
      data = schema['data']
      data = JSON.parse(data) if data.is_a?(String)
      tables = schema['tables'] || (data.is_a?(Hash) && data['tables']) || {}
      required = {
        KrowaAttemptArchive::TABLE => %w[list_key part parts nonce payload],
        WORD_TABLE => ['history_key'], DAILY_SCORES_TABLE => ['history_key'],
        TOWER_ROUNDS_TABLE => ['history_key'], TOWER_TABLE => ['histories_shared']
      }
      @attempt_schema_ready = required.all? do |name, fields|
        columns = tables.fetch(name, {}).fetch('columns', {})
        fields.all? { |field| columns.key?(field) }
      end
    end

    def synchronize_daily(date_ids)
      return false unless available?

      dates = Array(date_ids).map { |date| normalized_date(date) }.compact.uniq
      return true if dates.empty?

      present = {}
      offset = 0
      loop do
        page = daily_table.select(order: [["__id", "asc"]], limit: 500, offset: offset).to_a
        page.each { |row| present[row["day_key"].to_i] = true }
        offset += page.length
        break if page.length < 500
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

    # Daily results are separate from per-word scores: today's solution must
    # never be present in a public leaderboard record.
    def publish_daily(date_id, attempts, words: nil)
      date = normalized_date(date_id)
      count = attempts.to_i
      return :unavailable if date == nil || count <= 0 || !available? || !daily_completed?(date)
      return :history_unavailable if words && !attempt_histories_available?

      own = daily_scores_table.select(
        where: {"day_key" => date_key(date), "__insertion_user" => @user},
        order: [["attempts", "asc"]], limit: 1
      ).to_a.first
      return :unchanged if own && own["attempts"].to_i <= count

      values = {"day_key" => date_key(date), "attempts" => count}
      if words
        list = KrowaAttemptHistory.words(words, count: count)
        values['history_key'] = attempt_archive.publish("daily:#{date}", list)
        return :unavailable unless values['history_key']
      end
      insert_score(daily_scores_table, values)
    end

    def daily_ranking(date_id, limit: nil)
      date = normalized_date(date_id)
      return [] if date == nil || !available?

      rows = []
      offset = 0
      loop do
        page_limit = limit ? [500, [limit.to_i, 1].max - rows.length].min : 500
        page = daily_scores_table.select(
          where: {"day_key" => date_key(date)},
          columns: ["__insertion_user"], group_by: ["__insertion_user"],
          aggregates: {"attempts" => {"function" => "min", "column" => "attempts"}},
          order: [["attempts", "asc"], ["__insertion_user", "asc"]],
          limit: page_limit, offset: offset
        ).to_a
        rows.concat(page)
        offset += page.length
        break if page.length < page_limit || (limit && rows.length >= limit.to_i)
      end
      rows
    end

    def daily_days(limit: nil)
      return [] unless available?

      days = []
      offset = 0
      loop do
        page_limit = limit ? [500, [limit.to_i, 1].max - days.length].min : 500
        page = daily_scores_table.select(
          columns: ["day_key"], group_by: ["day_key"],
          aggregates: {"results" => {"function" => "count", "column" => "__id"}},
          order: [["day_key", "desc"]], limit: page_limit, offset: offset
        ).to_a
        days.concat(page.filter_map { |row| date_from_key(row["day_key"]) })
        offset += page.length
        break if page.length < page_limit || (limit && days.length >= limit.to_i)
      end
      days.uniq
    end

    # Every contender re-reads the first server ID after its insertion. A lost
    # acknowledgement is resolved by reading, never by blindly writing again.
    def assign_daily(date_id, now:)
      date = normalized_date(date_id)
      today = GameRoomKrowa::WarsawDate.today_id(clock: -> { Time.at(now).utc })
      return nil if date == nil || date != today || !available?
      row = daily_assignment_row(date)
      if row == nil
        assignment = @bank.new_daily_assignment(date)
        failure = nil
        begin
          daily_assignments_table.insert("day_key" => date_key(date), "assignment" => assignment)
        rescue StandardError => error
          raise if defined?(EltenAPI::Tasks::Cancelled) && error.is_a?(EltenAPI::Tasks::Cancelled)
          failure = error
        end
        row = daily_assignment_row(date)
        raise failure if row == nil && failure
      end
      return nil unless row
      @bank.assigned_daily(date, row["assignment"])
      row["assignment"]
    end

    def daily_word(date_id, today:)
      date = normalized_date(date_id)
      current = normalized_date(today)
      return nil if date == nil || current == nil || date >= current || !available?

      row = daily_assignment_row(date)
      row && GameRoomKrowa::DailyAssignment.open(date, row["assignment"])
    end

    # The date browser needs many historical answers at once. Restrict the
    # existing table query to those past days, preserving the earliest native
    # row per day even when duplicate assignments fill more than one page.
    def daily_words(date_ids, today:)
      current = normalized_date(today)
      return {} unless current && available?

      dates = Array(date_ids).filter_map { |value| normalized_date(value) }.uniq.select { |date| date < current }
      by_key = dates.to_h { |date| [date_key(date), date] }
      first_rows = {}
      by_key.keys.each_slice(100) do |keys|
        offset = 0
        loop do
          page = daily_assignments_table.select(where: {"day_key" => {"in" => keys}},
            order: [["__id", "asc"]], limit: 500, offset: offset).to_a
          page.each do |row|
            key = row["day_key"].to_i
            first_rows[key] ||= row if by_key.key?(key)
          end
          offset += page.length
          break if keys.all? { |key| first_rows.key?(key) } || page.length < 500
        end
      end
      first_rows.to_h do |key, row|
        date = by_key.fetch(key)
        [date, GameRoomKrowa::DailyAssignment.open(date, row["assignment"])]
      end
    end

    # Returns :published, :unchanged or :unavailable.
    def publish_word(word, attempts, words: nil)
      normalized = normalized_ranked_word(word)
      count = attempts.to_i
      return :unavailable if normalized == nil || count <= 0 || !available?
      return :history_unavailable if words && !attempt_histories_available?

      own = word_table.select(
        where: {"word" => normalized, "__insertion_user" => @user},
        order: [["attempts", "asc"]], limit: 1
      ).to_a.first
      return :unchanged if own && own["attempts"].to_i <= count

      values = {"word" => normalized, "attempts" => count}
      if words
        list = KrowaAttemptHistory.words(words, count: count, solution: normalized, solved: true)
        values['history_key'] = attempt_archive.publish("word:#{normalized}", list)
        return :unavailable unless values['history_key']
      end
      insert_score(word_table, values)
    end

    def word_attempt_list(word, user:, attempts:)
      normalized = normalized_ranked_word(word)
      return nil unless normalized && available?
      score_attempt_list(word_table, {'word' => normalized, '__insertion_user' => user, 'attempts' => attempts.to_i},
        "word:#{normalized}", normalized)
    end

    def daily_attempt_list(date_id, user:, attempts:, today:)
      date, current = normalized_date(date_id), normalized_date(today)
      return :hidden unless date && current && date < current
      return nil unless available?
      word = daily_word(date, today: current)
      return nil unless word
      score_attempt_list(daily_scores_table, {'day_key' => date_key(date), '__insertion_user' => user, 'attempts' => attempts.to_i},
        "daily:#{date}", word)
    end

    def tower_attempt_list(row)
      return nil unless available? && row['history_key'] && !row['history_key'].empty?
      scope = "tower:#{row.fetch('run_code')}:#{row.fetch('round')}"
      list = attempt_archive.fetch(scope, row['history_key'], user: row.fetch('__insertion_user'))
      raise IOError, 'Incomplete attempt history' unless list
      {word: row.fetch('word'), words: KrowaAttemptHistory.words(list, count: row.fetch('attempts'),
        solution: row.fetch('word'), solved: row['solved'] == 1)}
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

    # Search joins published days with their canonical saved assignments, not
    # today's dictionary order. Two paginated scans avoid a request per day.
    def search_ranked_words(query, today:)
      current = normalized_date(today)
      needle = @bank.normalize(query)
      return [] if current == nil || needle.empty? || !available?

      matches = ranked_words.select { |row| row['word'].include?(needle) }
      assignments = {}
      offset = 0
      loop do
        page = daily_assignments_table.select(order: [['__id', 'asc']], limit: 500, offset: offset).to_a
        page.each do |row|
          date = date_from_key(row['day_key'])
          next unless date && date < current && !assignments.key?(date)
          word = begin
            GameRoomKrowa::DailyAssignment.open(date, row['assignment'])
          rescue ArgumentError
            nil
          end
          assignments[date] = word
        end
        offset += page.length
        break if page.length < 500
      end
      assignments.select! { |_date, word| word && word.include?(needle) }
      return matches if assignments.empty?

      offset = 0
      loop do
        page = daily_scores_table.select(columns: ['day_key'], group_by: ['day_key'],
          aggregates: {
            'last_result_at' => {'function' => 'max', 'column' => '__insertion_time'},
            'best_attempts' => {'function' => 'min', 'column' => 'attempts'},
            'result_count' => {'function' => 'count', 'column' => '__id'}
          }, order: [['day_key', 'desc']], limit: 500, offset: offset).to_a
        page.each do |row|
          date = date_from_key(row['day_key'])
          word = assignments[date]
          matches << row.merge('word' => word, 'daily_date' => date) if word
        end
        offset += page.length
        break if page.length < 500
      end
      matches.sort_by { |row| [-row['last_result_at'].to_i, row['word'], row['daily_date'].to_s] }
    end

    # Details are inserted first. A ranking row therefore never points at a
    # half-written run when a bulk operation fails.
    def publish_tower(run_code:, participants:, rounds:)
      code = normalized_run_code(run_code)
      return :unavailable if code == nil || !available?
      sharing = Array(rounds).any? { |round| round[:words] || round['words'] }
      return :history_unavailable if sharing && !attempt_histories_available?
      identity = {"run_code" => code, "__insertion_user" => @user}
      return :unchanged unless tower_table.select(where: identity, limit: 1).to_a.empty?

      names = Array(participants).map(&:to_s).map(&:strip).reject(&:empty?).uniq
      return :unavailable unless names.length.between?(2, 8) && names.all? { |name| name.bytesize <= 64 } &&
        JSON.generate(names).bytesize <= 1024
      details = Array(rounds).each_with_index.map do |round, index|
        word = normalized_ranked_word(round[:word] || round["word"])
        attempts = (round[:attempts] || round["attempts"]).to_i
        solved = round.key?(:solved) ? round[:solved] : round["solved"]
        return :unavailable if word == nil || attempts.negative?
        values = {"run_code" => code, "round" => index + 1, "word" => word,
          "attempts" => attempts, "solved" => solved == false ? 0 : 1}
        words = round[:words] || round['words']
        if words
          list = KrowaAttemptHistory.words(words, count: attempts, solution: word, solved: solved != false)
          values['history_key'] = attempt_archive.publish("tower:#{code}:#{index + 1}", list)
          return :unavailable unless values['history_key']
        end
        values
      end
      present = tower_rounds(code, user: @user)
      return :unavailable unless present.all? do |row|
        expected = details[row["round"].to_i - 1]
        row["round"].to_i.positive? && expected && expected.all? { |key, value| row[key] == value }
      end
      missing = details.reject { |row| present.any? { |old| old["round"].to_i == row["round"] } }
      missing.each_slice(100) do |batch|
        begin
          tower_rounds_table.insert_many(batch)
        rescue StandardError
          # The server may have committed only part of the batch. Confirm
          # below; a later attempt writes only genuinely missing rounds.
        end
      end
      confirmed = tower_rounds(code, user: @user)
      return :unavailable unless details.all? { |row| confirmed.any? { |old| row.all? { |key, value| old[key] == value } } }
      completed = details.count { |round| round["solved"] == 1 }
      values = {
        "run_code" => code,
        "rounds" => completed,
        "participants" => JSON.generate(names)
      }
      values['histories_shared'] = sharing ? 1 : 0 if attempt_histories_available?
      begin
        inserted = tower_table.insert(values)
        return :published if inserted
      rescue StandardError
        # Lost acknowledgement: resolve by the same run/account identity.
      end
      tower_table.select(where: identity, limit: 1).to_a.empty? ? :unavailable : :published
    end

    def tower_ranking(limit: 100)
      return [] unless available?

      tower_table.select(
        order: [["rounds", "desc"], ["__insertion_time", "asc"]],
        limit: [[limit.to_i, 1].max, MAX_TOWER_RESULTS].min
      ).to_a.uniq { |row| [row["__insertion_user"].to_s.downcase, row["run_code"]] }
    end

    def tower_rounds(run_code, user: nil)
      code = normalized_run_code(run_code)
      return [] if code == nil || !available?
      where = {"run_code" => code}
      where["__insertion_user"] = user if user
      rows = []
      loop do
        page = tower_rounds_table.select(where: where, order: [["__id", "asc"]],
          limit: 500, offset: rows.length).to_a
        rows.concat(page)
        break if page.length < 500
      end
      rows.uniq { |row| [row["__insertion_user"].to_s.downcase, row["round"]] }.sort_by { |row| row["round"].to_i }
    end

    def participants_from(row)
      value = JSON.parse(row["participants"].to_s)
      value.is_a?(Array) ? value.map(&:to_s).reject(&:empty?) : []
    rescue JSON::ParserError
      []
    end

    def published_tower_rounds(result)
      rows = tower_rounds(result.fetch('run_code'), user: result.fetch('__insertion_user'))
      return rows if result['histories_shared'] == 1
      # A failed earlier upload may have written some optional details.
      # The final publication choice controls what the ordinary UI exposes.
      rows.map { |row| row.reject { |field, _| field == 'history_key' } }
    end

    private

    def attempt_archive; @attempt_archive ||= KrowaAttemptArchive.new(@server_tables, user: @user); end

    def score_attempt_list(table, where, scope, word)
      # The earliest row for this exact best score is authoritative; do not
      # attach attempts from a different playthrough with the same count.
      row = table.select(where: where, order: [['__id', 'asc']], limit: 1).to_a.first
      return nil unless row && !row['history_key'].to_s.empty?
      list = attempt_archive.fetch(scope, row['history_key'], user: row.fetch('__insertion_user'))
      raise IOError, 'Incomplete attempt history' unless list
      {word: word, words: KrowaAttemptHistory.words(list, count: row.fetch('attempts'), solution: word, solved: true)}
    end

    def insert_score(table, values)
      inserted = table.insert(values)
      inserted == nil ? :unavailable : :published
    rescue StandardError => error
      raise unless error.is_a?(IOError) || (defined?(EltenLink::Error) && error.is_a?(EltenLink::Error))
      # Only a read can resolve a lost acknowledgement, not a second insert.
      found = table.select(where: values.merge('__insertion_user' => @user), limit: 1).to_a.first
      found ? :published : :unavailable
    end

    def normalized_run_code(value)
      text = value.to_s
      /\A[0-9a-f]{64}\z/.match?(text) ? text : nil
    end

    def daily_table; @daily_table ||= @server_tables.fetch(DAILY_TABLE); end
    def daily_assignments_table; @daily_assignments_table ||= @server_tables.fetch(DAILY_ASSIGNMENTS_TABLE); end
    def daily_assignment_row(date)
      daily_assignments_table.select(where: {"day_key" => date_key(date)}, order: [["__id", "asc"]], limit: 1).to_a.first
    end
    def daily_scores_table; @daily_scores_table ||= @server_tables.fetch(DAILY_SCORES_TABLE); end
    def word_table; @word_table ||= @server_tables.fetch(WORD_TABLE); end
    def tower_table; @tower_table ||= @server_tables.fetch(TOWER_TABLE); end
    def tower_rounds_table; @tower_rounds_table ||= @server_tables.fetch(TOWER_ROUNDS_TABLE); end

    def normalized_date(value)
      text = value.to_s
      return nil unless /\A\d{4}-\d{2}-\d{2}\z/.match?(text)
      Date.iso8601(text).iso8601 == text ? text : nil
    rescue Date::Error
      nil
    end

    def date_from_key(value)
      key = value.to_i.to_s
      return nil unless /\A\d{8}\z/.match?(key)
      normalized_date("#{key[0, 4]}-#{key[4, 2]}-#{key[6, 2]}")
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
