require_relative '../game_content'
require_relative '../game_random'

module GameRoomCashAuction
  # A per-pack index over the existing frozen quiz rows, with no global cache.
  # The caller validates the recorded pack identity and supplies a native seed
  # obtained after awarding the auction, never the earlier wheel seed.
  class QuestionBank
    PUBLIC_FIELDS = %i[set_id pack_id pack_version pack_checksum language_id
      question_id category prompt choices].freeze
    MAX_SEED = (1 << 128) - 1

    attr_reader :categories

    def initialize(pack)
      unless pack.is_a?(GameRoomContent::Pack) && pack.supports?(game_id: 'quiz', kind: 'quiz')
        raise ArgumentError, 'Expected a quiz content pack'
      end
      questions = pack.data['questions']
      raise ArgumentError, 'Question pack is empty or invalid' unless questions.is_a?(Array) && !questions.empty?

      @by_id = {}
      questions.each do |question|
        unless valid_question?(question) && !@by_id.key?(question['id'])
          raise ArgumentError, 'Question pack has invalid or duplicate questions'
        end
        @by_id[question['id']] = question
      end
      grouped = questions.group_by { |question| question['category'] }
      @labels = grouped.keys.sort.freeze
      @groups = @labels.map { |label| grouped.fetch(label).freeze }.freeze
      @categories = (0...@groups.length).to_a.freeze
      @by_id.freeze
      @identity = {set_id: pack.set_id.dup.freeze, pack_id: pack.id.dup.freeze,
        pack_version: pack.version, pack_checksum: pack.checksum.dup.freeze,
        language_id: pack.language_id.dup.freeze}.freeze
      freeze
    end

    def category_label(category)
      category_questions(category)
      @labels.fetch(category)
    end

    # :used is the next bounded resolver ledger, not public question data.
    # Exhaustion resets only this category; the supplied ledger is immutable.
    def draw(category:, seed:, used: [])
      candidates = category_questions(category)
      raise ArgumentError, 'Invalid question seed' unless seed.is_a?(Integer) && seed.between?(0, MAX_SEED)
      unless used.is_a?(Array) && used.length <= @by_id.length &&
          used.all? { |id| id.is_a?(String) && @by_id.key?(id) } && used.uniq.length == used.length
        raise ArgumentError, 'Invalid used-question ledger'
      end
      next_used = used.map { |id| @by_id.fetch(id).fetch('id') }
      seen = next_used.to_h { |id| [id, true] }
      fresh = candidates.reject { |question| seen.key?(question['id']) }
      if fresh.empty?
        next_used.reject! { |id| @by_id.fetch(id)['category'] == @labels.fetch(category) }
        fresh = candidates
      end
      random = Random.new(seed)
      question = fresh.fetch(random.rand(fresh.length))
      answers = [question.fetch('correct'), *question.fetch('wrong')].each_with_index.to_a
      shuffled = GameRoomRandom.shuffle(answers, random: random)
      @identity.merge(question_id: question.fetch('id'), category: category,
        prompt: question.fetch('prompt'), choices: shuffled.map(&:first).freeze,
        correct_index: shuffled.index { |_text, index| index.zero? },
        used: (next_used << question.fetch('id')).freeze).freeze
    end

    # The game still decides who may receive even this answer-free view.
    def public_view(data)
      return nil if data.nil?
      raise ArgumentError, 'Invalid question view' unless data.is_a?(Hash)

      data.slice(*PUBLIC_FIELDS).to_h do |key, value|
        copied = case value
        when String then value.dup
        when Array then value.map { |item| item.is_a?(String) ? item.dup : item }
        else value
        end
        [key, copied]
      end
    end

    private

    def category_questions(category)
      unless category.is_a?(Integer) && category.between?(0, @groups.length - 1)
        raise ArgumentError, 'Unknown question category'
      end
      @groups.fetch(category)
    end

    def valid_question?(question)
      return false unless question.is_a?(Hash) && %w[id prompt category correct].all? do |key|
        question[key].is_a?(String) && !question[key].strip.empty?
      end
      return false unless question['id'].length.between?(1, 32) && question['wrong'].is_a?(Array) && question['wrong'].length == 3

      answers = [question['correct'], *question['wrong']]
      answers.all? { |answer| answer.is_a?(String) && !answer.strip.empty? } &&
        answers.map { |answer| answer.strip.downcase }.uniq.length == 4
    end
  end
end
