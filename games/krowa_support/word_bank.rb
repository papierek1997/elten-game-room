require_relative "word_repository"
require_relative "daily_puzzle_provider"
require_relative "warsaw_date"

module GameRoomGames
  class KrowaWordBank
    def self.default
      @default ||= new(GameRoomKrowa::WordRepository.default)
    end

    def initialize(repository)
      @repository = repository
    end

    def normalize(word)
      GameRoomKrowa::Normalizer.call(word)
    end

    def include?(word)
      @repository.include?(word)
    end

    def index_of(word)
      @repository.index_of(word)
    end

    def word_at(index)
      @repository.word_at(index)
    end

    def choose(length:, maximum: 13, excluded: [], random:)
      lengths = length.to_i.zero? ? (3..maximum).to_a : [length.to_i]
      pools = lengths.to_h { |size| [size, @repository.words_of_length(size) - excluded] }
        .reject { |_size, pool| pool.empty? }
      raise ArgumentError, "No unused nouns of this length" if pools.empty?
      size = pools.keys.fetch(draw(random, pools.size))
      pool = pools.fetch(size)
      # GameRoomRandom's dice contract caps a die at 1000 faces. Rejection
      # sampling preserves a uniform distribution for larger noun pools.
      pool.fetch(draw(random, pool.length))
    end

    def daily(now)
      raise ArgumentError, "Server time is required" unless now && now.to_f.positive?
      date = GameRoomKrowa::WarsawDate.today_id(clock: -> { Time.at(now).utc })
      puzzle = GameRoomKrowa::DailyPuzzleProvider.new(@repository, date_provider: -> { date }).today
      [date, puzzle.solution]
    end

    def matches(word, answer)
      word.each_char.zip(answer.each_char).count { |left, right| left == right }
    end

    private

    def draw(random, size)
      return 0 if size == 1
      loop do
        values = random.roll(count: 2, sides: 1000).values
        number = (values[0] - 1) * 1000 + values[1] - 1
        limit = 1_000_000 - 1_000_000 % size
        return number % size if number < limit
      end
    end
  end
end
