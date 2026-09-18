# encoding: UTF-8

require_relative "puzzle"

module GameRoomKrowa
  class DailyPuzzleProvider
    MIN_LENGTH = 3
    MAX_LENGTH = 9
    ALGORITHM_VERSION = 1
    HASH_OFFSET = 14_695_981_039_346_656_037
    HASH_PRIME = 1_099_511_628_211
    HASH_MASK = (1 << 64) - 1

    def initialize(repository, date_provider:)
      @repository = repository
      @date_provider = date_provider
      ensure_daily_pools!
    end

    def today
      puzzle_for(@date_provider.call)
    end

    def puzzle_for(date_id)
      date = date_id.to_s
      raise ArgumentError, "Invalid daily puzzle date" if !/\A\d{4}-\d{2}-\d{2}\z/.match?(date)

      seed = "krowa-daily-v#{ALGORITHM_VERSION}|#{date}"
      length = MIN_LENGTH + stable_index("#{seed}|length", MAX_LENGTH - MIN_LENGTH + 1)
      pool = @repository.words_of_length(length)
      solution = pool.fetch(stable_index("#{seed}|word", pool.length))
      Puzzle.new(
        id: "daily-v#{ALGORITHM_VERSION}-#{date}",
        solution: solution,
        mode: :daily,
        metadata: {
          "date" => date,
          "length" => length,
          "algorithm_version" => ALGORITHM_VERSION
        }.freeze
      ).freeze
    end

    private

    def ensure_daily_pools!
      missing = (MIN_LENGTH..MAX_LENGTH).reject do |length|
        !@repository.words_of_length(length).empty?
      end
      raise ArgumentError, "Missing nouns for daily lengths: #{missing.join(', ')}" if !missing.empty?
    end

    def stable_index(text, size)
      raise ArgumentError, "Daily word pool is empty" if size <= 0

      hash = HASH_OFFSET
      text.each_byte do |byte|
        hash ^= byte
        hash = (hash * HASH_PRIME) & HASH_MASK
      end
      hash % size
    end
  end
end
