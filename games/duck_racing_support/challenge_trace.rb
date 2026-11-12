# frozen_string_literal: true

require_relative "challenge_engine"

module GameRoomDuckRacing
  # A local, monotonic input trace. It contains accepted edges and playback
  # acknowledgements, not an entry per UI frame. The outer client persists
  # the finished trace through HiddenSubmissions for private challenges; a
  # first-answer challenge publishes it directly for ordered verification.
  class ChallengeTrace
    attr_reader :state, :seat

    def initialize(challenge, seat:, resources: {}, compact: false)
      raise ArgumentError, "A shared challenge uses public actions" if ChallengeEngine::SHARED.include?(challenge[:kind])
      raise ArgumentError, "Participant is not in this challenge" unless challenge.fetch(:participants).include?(seat)
      @state = ChallengeEngine.start(challenge, resources: resources)
      @seat, @resources = seat, resources
      @compact, @guesses = compact, []
      @actions, @finished_at, @last_time = [], nil, 0
    end

    def submit(action, at:)
      return false if finished? || !at.is_a?(Integer) || at < @last_time
      return false unless ChallengeEngine.submit(@state, seat: @seat, action: action, now_ms: at, resources: @resources)

      input = action.to_h { |key, value| [key.to_s, value.is_a?(Symbol) ? value.to_s : value] }
      if @compact
        @guesses << input['value'].to_i if @state[:kind] == 'guess_number' && input['kind'] == 'answer'
      else
        @actions << {"at" => at, "input" => Marshal.load(Marshal.dump(input))}
      end
      @last_time = at
      @finished_at = at if ChallengeEngine.own_finished?(@state, @seat)
      true
    end

    def tick(at:)
      return false if finished? || !at.is_a?(Integer) || at < @last_time
      changed = ChallengeEngine.expire(@state, now_ms: at)
      @last_time = at
      @finished_at = at if ChallengeEngine.own_finished?(@state, @seat)
      changed
    end

    def finished?
      !@finished_at.nil?
    end

    def snapshot
      raise ArgumentError, "The private attempt is still running" unless finished?
      return CompactAttempt.answer(@state, @seat, @guesses) if @compact
      Marshal.load(Marshal.dump({"actions" => @actions, "finished_at" => @finished_at}))
    end
  end

  # Independent audio attempts are scored by the local rules, not replayed by
  # every peer. This is a transport optimisation, not an anti-cheat protocol.
  # Discrete private answers still derive their result from the shared seed.
  module CompactAttempt
    module_function

    def answer(engine, seat, guesses = [])
      result = ChallengeEngine.result_for(engine, seat)
      case engine[:kind]
      when *ChallengeEngine::LOCAL_SCORES
        score = result.fetch(:score)
        {'score' => [score.numerator, score.denominator]}
      when 'guess_number' then {'guesses' => guesses.dup}
      when 'rock_paper_scissors' then {'choice' => result[:choice]}
      when 'quiz' then {'answer' => result[:answer]}
      else raise ArgumentError, 'This challenge does not use a compact answer'
      end
    end

    def verify(challenge, answer, seat:, resources: {})
      raise TraceVerifier::InvalidTrace, 'Malformed compact answer' unless answer.is_a?(Hash)
      kind = challenge[:kind]
      if ChallengeEngine::LOCAL_SCORES.include?(kind)
        pair = answer['score']
        valid = answer.keys == ['score'] && pair.is_a?(Array) && pair.length == 2 &&
          pair.all? { |value| value.is_a?(Integer) } && pair[0].between?(0, 2**31 - 1) && pair[1].between?(1, 10_000)
        raise TraceVerifier::InvalidTrace, 'Invalid local score' unless valid
        score = Rational(*pair)
        valid = kind == 'simon' ? score.denominator == 1 : score.between?(0, 100)
        raise TraceVerifier::InvalidTrace, 'Local score outside challenge bounds' unless valid
        return {score: kind == 'simon' ? score.to_i : score}
      end
      engine = ChallengeEngine.start(challenge, resources: resources)
      values, action = case kind
      when 'guess_number'
        guesses = answer['guesses']
        raise TraceVerifier::InvalidTrace, 'Invalid guesses' unless answer.keys == ['guesses'] &&
          guesses.is_a?(Array) && guesses.length <= 10 && guesses.all? { |value| value.is_a?(Integer) && value.between?(1, 999) }
        [guesses, 'answer']
      when 'rock_paper_scissors'
        raise TraceVerifier::InvalidTrace, 'Invalid choice' unless answer.keys == ['choice'] &&
          [nil, 'rock', 'paper', 'scissors'].include?(answer['choice'])
        [answer['choice'].nil? ? [] : [answer['choice']], 'choose']
      when 'quiz'
        raise TraceVerifier::InvalidTrace, 'Invalid quiz answer' unless answer.keys == ['answer'] &&
          (answer['answer'].nil? || answer['answer'].is_a?(Integer) && answer['answer'].between?(0, 3))
        [answer['answer'].nil? ? [] : [answer['answer']], 'answer']
      else raise TraceVerifier::InvalidTrace, 'Unexpected compact challenge'
      end
      values.each_with_index do |value, index|
        accepted = ChallengeEngine.submit(engine, seat: seat,
          action: {'kind' => action, 'value' => value, 'press_id' => index + 1}, now_ms: index, resources: resources)
        raise TraceVerifier::InvalidTrace, 'Rejected compact answer' unless accepted
      end
      ChallengeEngine.expire(engine, now_ms: 120_000)
      ChallengeEngine.result_for(engine, seat)
    end

    class Verifier
      def initialize(challenge:, balances:, resources: {})
        @challenge, @balances, @resources = challenge, balances, resources
      end

      def replay(answers:, forfeits:)
        excluded = forfeits.keys
        unless (answers.keys + excluded).sort == @challenge[:participants].sort && (answers.keys & excluded).empty?
          raise TraceVerifier::InvalidTrace, 'Incomplete compact answers'
        end
        results = answers.to_h { |seat, answer| [seat, CompactAttempt.verify(@challenge, answer, seat: seat, resources: @resources)] }
        excluded.each { |seat| results[seat] = ChallengeEngine.missing_result(@challenge[:kind]) }
        target = ChallengeEngine.solution(@challenge, resources: @resources) if @challenge[:kind] == 'guess_number'
        settlement = ChallengeEngine.settlement(@challenge[:kind], balances: @balances,
          results: results, excluded: excluded, target: target)
        TraceVerifier::Resolution.new(results.freeze, settlement)
      end
    end
  end

  # One durable local result, written before publishing it. An uncertain
  # write is retried with the same value; only accepted closure removes it.
  module LocalResult
    module_function

    def prepare(state, seat:, user:, answer:, vault:)
      challenge = state.fetch(:round).fetch(:challenge)
      CompactAttempt.verify(challenge, answer, seat: seat)
      previous = recover(state, seat: seat, user: user, vault: vault)
      return previous if previous
      payload = scope(state, seat).merge('answer' => answer)
      saved = vault.prepare(session_id: state[:session_id], round_id: key(challenge[:id]), user: user, payload: payload)
      raise HiddenSubmissions::StorageError, 'Could not preserve local result' unless saved.payload == payload && vault.verify(saved)
      saved.payload.fetch('answer')
    end

    def recover(state, seat:, user:, vault:)
      challenge = state.fetch(:round).fetch(:challenge)
      envelope = vault.reveal(session_id: state[:session_id], round_id: key(challenge[:id]), user: user)
      return unless envelope
      payload = envelope.payload
      unless vault.verify(envelope) && payload.is_a?(Hash) && payload.keys.sort == %w[answer kind round seat session] &&
          payload.reject { |name, _| name == 'answer' } == scope(state, seat)
        raise HiddenSubmissions::StorageError, 'Invalid stored local result'
      end
      CompactAttempt.verify(challenge, payload['answer'], seat: seat)
      payload['answer']
    end

    def cleanup(state, user:, vault:)
      proofs = state.fetch(:result_closures, []).dup
      round = state[:round]
      proofs << {id: round[:challenge][:id], seats: round[:results].keys} if round && round[:results]
      receipts = vault.envelopes(session_id: state[:session_id], user: user, round_prefix: 'duck-score:').filter_map do |envelope|
        payload = envelope.payload
        next unless vault.verify(envelope) && payload.is_a?(Hash) && payload['session'] == state[:session_id] &&
          envelope.round_id == key(payload['round']) && proofs.any? { |proof| proof[:id] == payload['round'] && proof[:seats].include?(payload['seat']) }
        [envelope.round_id, user, envelope.commitment]
      end
      receipts.empty? || vault.discard_confirmed(session_id: state[:session_id], receipts: receipts)
    end

    def scope(state, seat)
      challenge = state.fetch(:round).fetch(:challenge)
      {'session' => state[:session_id], 'round' => challenge[:id], 'seat' => seat, 'kind' => challenge[:kind]}
    end
    def key(id); "duck-score:#{id}"; end
    private_class_method :scope, :key
  end

  # Verifies complete traces by re-running the rules. Private challenges
  # check commitments first; first-answer challenges verify at acceptance.
  # No claimed score is accepted. Player clocks are relative to that player's
  # challenge start; never subtract wall clocks from different computers.
  class TraceVerifier
    class InvalidTrace < ArgumentError; end
    Resolution = Data.define(:results, :settlement)

    def initialize(challenge:, balances:, resources: {})
      @challenge, @balances, @resources = challenge, balances, resources
      if (ChallengeEngine::SHARED + ChallengeEngine::REALTIME).include?(challenge[:kind])
        raise ArgumentError, "This challenge has its own authoritative action path"
      end
      raise ArgumentError, "Incorrect feather balances" unless balances.keys.sort == challenge[:participants].sort
    end

    def replay(traces:, forfeits:)
      forfeits = forfeits.keys if forfeits.is_a?(Hash)
      unless traces.is_a?(Hash) && forfeits.is_a?(Array) && forfeits.uniq == forfeits &&
          (traces.keys & forfeits).empty? && (traces.keys + forfeits).sort == @challenge[:participants].sort
        raise InvalidTrace, "Incomplete participant traces"
      end
      results = traces.to_h { |seat, trace| [seat, verify_trace(seat, trace)] }
      forfeits.each { |seat| results[seat] = ChallengeEngine.missing_result(@challenge[:kind]) }
      # The target comes from the challenge seed, never from a participant's
      # claimed result or trace. It is used only after private verification.
      target = ChallengeEngine.solution(@challenge, resources: @resources) if @challenge[:kind] == 'guess_number'
      settlement = ChallengeEngine.settlement(@challenge[:kind], balances: @balances,
        results: results, excluded: forfeits, target: target)
      Resolution.new(results.freeze, settlement)
    end

    def verify_attempt(seat, trace)
      raise InvalidTrace, "Not a first-answer participant" unless
        ChallengeEngine::FIRST_ANSWER.include?(@challenge[:kind]) && @challenge[:participants].include?(seat)

      verify_trace(seat, trace)
    end

    private

    def verify_trace(seat, trace)
      unless trace.is_a?(Hash) && trace.keys.sort == %w[actions finished_at] && trace["actions"].is_a?(Array) &&
          trace["finished_at"].is_a?(Integer) && trace["finished_at"] >= 0
        raise InvalidTrace, "Malformed private attempt"
      end
      state = ChallengeEngine.start(@challenge, resources: @resources)
      last = 0
      trace["actions"].each do |entry|
        unless entry.is_a?(Hash) && entry.keys.sort == %w[at input] && entry["at"].is_a?(Integer) &&
            entry["at"] >= last && entry["at"] <= trace["finished_at"] && entry["input"].is_a?(Hash)
          raise InvalidTrace, "Malformed challenge input"
        end
        ChallengeEngine.expire(state, now_ms: entry["at"])
        unless ChallengeEngine.submit(state, seat: seat, action: entry["input"], now_ms: entry["at"], resources: @resources)
          raise InvalidTrace, "Rejected challenge input in committed trace"
        end
        last = entry["at"]
      end
      ChallengeEngine.expire(state, now_ms: trace["finished_at"])
      raise InvalidTrace, "Unfinished committed attempt" unless ChallengeEngine.own_finished?(state, seat)
      ChallengeEngine.result_for(state, seat)
    end
  end
end
