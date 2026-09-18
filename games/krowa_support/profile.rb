require "digest"
require "json"

module GameRoomGames
  # Separate account-scoped local profile. The Game Room event stack remains
  # the only source of match state; this is just vocabulary and a solo gallery.
  class KrowaProfile
    attr_reader :data

    def initialize(program, user:)
      @program, @user = program, user.to_s
      @path = "krowa/accounts/#{Digest::SHA256.hexdigest(@user.downcase)}/profile.json"
      stored = program.read_json(@path, default: {})
      @data = {"dictionary" => [], "gallery" => {}, "daily" => []}.merge(stored.is_a?(Hash) ? stored : {})
    end

    def observe(replay)
      before = JSON.generate(@data)
      replay.history.select { |entry| entry.kind == :dictionary && entry.actor.to_s.casecmp(@user).zero? }.each do |entry|
        event = replay.accepted_events.find { |candidate| candidate["action"] == "krowa_vocab" && (candidate["__id"] || candidate["id"]).to_i == entry.event_id }
        @data["dictionary"] |= [event["value"]] if event
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
              @data["gallery"][word] = {"attempts" => result[:attempts], "at" => state[:started_ms]} if old.nil? || result[:attempts] < old["attempts"]
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
  end
end
