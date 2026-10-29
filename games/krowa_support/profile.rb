require "digest"
require "json"
require_relative 'attempt_history'

module GameRoomGames
  # Separate account-scoped local profile. The Game Room event stack remains
  # the only source of match state; this is just vocabulary and a solo gallery.
  class KrowaProfile
    attr_reader :data

    def initialize(program, user:)
      @program, @user = program, user.to_s
      @path = "krowa/accounts/#{Digest::SHA256.hexdigest(@user.downcase)}/profile.json"
      stored = program.read_json(@path, default: {})
      @data = {"dictionary" => [], "dictionary_events" => {}, "gallery" => {}, "daily" => []}.merge(stored.is_a?(Hash) ? stored : {})
      # Retain every processed addition, not just the most recent one per
      # noun. Reopening an older match must not undo a deliberate removal.
      markers = @data["dictionary_events"].is_a?(Hash) ? @data["dictionary_events"] : {}
      @data["dictionary_events"] = markers.to_h do |key, value|
        [value.is_a?(String) ? value : key, true]
      end
    end

    def observe(replay)
      before = JSON.generate(@data)
      dictionary_additions(replay).each do |word, identity, already_processed|
        next if @data["dictionary_events"][identity]
        @data["dictionary"] |= [word] unless already_processed
        @data["dictionary_events"][identity] = true
      end
      state = replay.state
      if %w[random daily].include?(state[:options]["variant"])
        own = state[:results].find { |name, _result| name.to_s.casecmp(@user).zero? }
        if own
          variant, result = state[:options]["variant"], own.last
          allowed = variant != "daily" || !@data["daily"].include?(state[:day])
          @data["daily"] |= [state[:day]] if variant == "daily"
          if allowed && result[:solved]
            trial = state[:attempts].find { |item| item[:player] == own.first && item[:matches] == state[:length] }
            if trial
              word = trial[:word]
              old = @data["gallery"][word]
              if old.nil? || result[:attempts] < old["attempts"] ||
                  (result[:attempts] == old['attempts'] && old['words'].nil?)
                words = state[:attempts].select { |item| item[:player] == own.first }.map { |item| item[:word] }
                @data["gallery"][word] = {"attempts" => result[:attempts], "at" => state[:started_ms],
                  "words" => KrowaAttemptHistory.words(words, count: result[:attempts], solution: word, solved: true)}
              end
            end
          end
        end
      end
      return false if JSON.generate(@data) == before
      raise "Cannot save Krowa profile" if @program.write_json(@path, @data) == false
      true
    rescue StandardError
      @data = JSON.parse(before) if before
      raise
    end

    def remove_dictionary(words)
      before = JSON.generate(@data)
      removed = words.to_a.map { |word| word.to_s.downcase }
      @data["dictionary"] = @data["dictionary"].to_a.reject do |word|
        removed.include?(word.to_s.downcase)
      end
      return false if JSON.generate(@data) == before

      raise "Cannot save Krowa profile" if @program.write_json(@path, @data) == false
      true
    rescue StandardError
      @data = JSON.parse(before) if before
      raise
    end

    private

    def dictionary_additions(replay)
      own_entries = replay.history.each_with_object({}) do |entry, ids|
        ids[entry.event_id.to_i] = true if entry.kind == :dictionary && entry.actor.to_s.casecmp(@user).zero?
      end
      events = replay.accepted_events
      # Old versions hashed the whole event with the CURRENT commitment,
      # including commitments of later rerolls. Recognize those old markers
      # without dropping them or undoing a deliberate removal during migration.
      legacy_commitments = [nil, replay.state[:commitment]] + events.filter_map do |event|
        event["value"] if event["action"] == "krowa_commit"
      end
      legacy_commitments.uniq!
      commitment = nil
      events.filter_map do |event|
        commitment = event["value"] if event["action"] == "krowa_commit"
        id = (event["__id"] || event["id"]).to_i
        next unless event["action"] == "krowa_vocab" && own_entries[id]

        # The originating round isolates sessions. Wall-clock reconciliation
        # and later rounds must not turn the same addition into a new one.
        origin = [commitment, id, event["actor"].to_s.downcase, event["action"], event["value"]]
        identity = "v2:#{Digest::SHA256.hexdigest(JSON.generate(origin))}"
        next if @data["dictionary_events"][identity]
        processed = legacy_commitments.any? do |previous|
          @data["dictionary_events"][Digest::SHA256.hexdigest(JSON.generate([previous, event]))]
        end
        [event["value"], identity, processed]
      end
    end
  end
end
