# frozen_string_literal: true

require_relative "../../lib/game_random"
require_relative "dice"

module GameRoomDuckRacing
  # An authoritative model, not a payload to broadcast. The outer
  # challenge adapter supplies validated input identities and local elapsed
  # times; public_view is the only player-facing projection. No method reads
  # a clock, performs I/O or changes the race's dice/modifier objects.
  module NumericChallenges
    TYPES = {
      "rock_paper_scissors" => [2, 2, 15_000],
      "dice_duel" => [2, 8, 10_000],
      "blackjack" => [2, 8, 30_000],
      "risky_dice" => [2, 8, 30_000],
      "guess_number" => [2, 8, 120_000],
      "copy_number" => [2, 8, 15_000],
      "arithmetic" => [2, 8, 20_000],
      "race_question" => [2, 8, 20_000],
      "numbered_balls" => [2, 2, 60_000]
    }.transform_values(&:freeze).freeze
    ANSWER_TYPES = %w[copy_number arithmetic race_question].freeze
    TURN_TYPES = %w[dice_duel blackjack risky_dice numbered_balls].freeze
    ATTEMPT_TURN_TYPES = %w[blackjack risky_dice].freeze
    ACTION_KINDS = %w[choose roll hit stand save answer take].to_h { |name| [name, name.to_sym] }.freeze
    ACTION_KEYS = %w[kind value press_id repeat].freeze
    CHOICES = %w[rock paper scissors].freeze
    BALL_VALUES = [-10, -7, -3, -2, -1, 1, 2, 3, 7, 10].freeze
    DICE_SIDES = [3, 6, 10, 12].freeze
    BLACKJACK_CARDS = (0...52).to_a.freeze

    module_function

    # Blackjack has an independent standard 52-card deck per seat. Physical
    # IDs 0..51 map to ranks by id / 4 + 1. An optional prepared full deck is
    # useful for deterministic setup; it must have exactly the same cards.
    def start(type_id, seats:, seed:, now_ms:, race_snapshot: nil, dice: nil, blackjack_decks: nil)
      limits = TYPES[type_id]
      unless limits && seats.is_a?(Array) && seats.size.between?(limits[0], limits[1]) &&
          seats.uniq.size == seats.size && seats.all? { |seat| seat.is_a?(Integer) && seat >= 0 } &&
          seed.is_a?(Integer) && seed >= 0 && time?(now_ms)
        raise ArgumentError, "Invalid numeric challenge setup"
      end
      prepared_decks = copy_decks(seats, blackjack_decks) if type_id == "blackjack" && !blackjack_decks.nil?

      random = Random.new(seed)
      # Independent seat streams keep a player's dice/deck unchanged when
      # the participant order changes; no other player's draw consumes it.
      streams = seats.sort.to_h { |seat| [seat, Random.new(random.rand(1 << 63))] }
      state = {
        type: type_id, participants: seats.dup, started_at_ms: now_ms,
        deadline_ms: now_ms + limits[2], finished: false, finished_at_ms: nil,
        players: seats.to_h do |seat|
          [seat, {done: false, status: :waiting, last_press_id: 0,
            last_input_ms: now_ms, random: streams.fetch(seat)}]
        end,
        scores: {}, results: {}, outcome: nil, notices: []
      }
      case type_id
      when "rock_paper_scissors"
        state[:players].each_value { |player| player[:choice] = nil }
      when "dice_duel", "risky_dice"
        state[:dice] = copy_dice(seats, dice)
        state[:players].each_value { |player| player.merge!(rolls: [], total: 0) }
      when "blackjack"
        state[:players].each do |seat, player|
          player[:deck] = prepared_decks ? prepared_decks.fetch(seat) : GameRoomRandom.shuffle(BLACKJACK_CARDS, random: player[:random])
          player[:cards] = []
          player[:total] = 0
          2.times { draw_card!(player) }
          finish_total_if_needed!(player, 21)
        end
      when "guess_number"
        state[:answer] = random.rand(999) + 1
        state[:players].each_value { |player| player.merge!(attempts: [], best: nil) }
      when *ANSWER_TYPES
        state[:players].each_value { |player| player[:attempts] = [] }
        state[:attempt_limit] = type_id == "race_question" ? 2 : 3
        prepare_question!(state, random, race_snapshot)
      when "numbered_balls"
        state[:remaining] = Array.new(12) { BALL_VALUES.fetch(random.rand(BALL_VALUES.size)) }
        state[:turn_index] = random.rand(seats.size)
        state[:turn_started_at_ms] = now_ms
        state[:players].each_value { |player| player.merge!(balls: [], total: 0) }
      end
      if TURN_TYPES.include?(type_id) && type_id != "numbered_balls"
        eligible = seats.each_index.reject { |index| state[:players].fetch(seats[index])[:done] }
        state[:turn_index] = eligible[random.rand(eligible.length)] unless eligible.empty?
        state[:turn_started_at_ms] = now_ms
      end
      if type_id == "blackjack"
        # Deal deterministically at setup, but announce only the player whose
        # turn starts. Natural 21s need no input; reveal them when passed in
        # turn order. If everyone has 21, all hands resolve immediately.
        first = state[:turn_index]
        (first.nil? ? seats : [seats.fetch(first)]).each { |seat| announce_hand!(state, seat) }
      end
      finalize_if_done!(state, now_ms)
      state
    end

    # A new physical press has a strictly increasing press_id per seat. The
    # adapter must not assign a new identity to keyboard autorepeat or retries.
    # Syntax errors and illegal actions do not consume an attempt or RNG value.
    # A validly written but incorrect answer is an accepted attempt.
    def submit(state, seat:, action:, now_ms:)
      return false unless time?(now_ms) && !state.fetch(:finished)
      player = state.fetch(:players)[seat]
      return false unless player && !player[:done] && now_ms >= player[:last_input_ms] &&
        now_ms < state.fetch(:deadline_ms)
      if TURN_TYPES.include?(state[:type])
        return false unless state[:participants][state[:turn_index]] == seat && now_ms >= state[:turn_started_at_ms]
      end

      input = normalize_action(action)
      return false unless input && input[:press_id] > player[:last_press_id]
      return false unless permitted_action?(state, seat, player, input)

      state[:notices] = []
      player[:last_press_id] = input[:press_id]
      player[:last_input_ms] = now_ms
      case state[:type]
      when "rock_paper_scissors"
        player[:choice] = input[:value].dup
        finish_player!(player, :chosen)
      when "dice_duel"
        roll!(state, seat, 1)
        finish_player!(player, :rolled)
      when "blackjack"
        if input[:kind] == :hit
          draw_card!(player)
          state[:notices] << [:challenge_draw, seat, player[:cards].last / 4 + 1, player[:total]]
          finish_total_if_needed!(player, 21)
        else
          finish_player!(player, :stood)
          state[:notices] << [:challenge_stand, seat, player[:total]]
        end
      when "risky_dice"
        if input[:kind] == :roll
          roll!(state, seat, 2)
          finish_total_if_needed!(player, 25)
        else
          finish_player!(player, :saved)
          state[:notices] << [:challenge_stand, seat, player[:total]]
        end
      when "guess_number"
        accept_guess!(state, player, input[:value], now_ms)
      when *ANSWER_TYPES
        accept_answer!(state, player, input[:value], now_ms)
      when "numbered_balls"
        take_balls!(state, seat, input[:value], now_ms)
      end
      advance_turn!(state, now_ms) if TURN_TYPES.include?(state[:type]) && state[:type] != "numbered_balls"
      finalize_if_done!(state, now_ms)
      true
    end

    # Advance only explicit deadlines. A late poll settles the recorded
    # deadline, not its delivery time; repeated calls cannot repeat a roll.
    def expire(state, now_ms:)
      return false unless time?(now_ms) && !state.fetch(:finished) && now_ms >= state.fetch(:deadline_ms)

      state[:notices] = []
      if TURN_TYPES.include?(state[:type])
        while !state[:finished] && now_ms >= state[:deadline_ms]
          deadline = state[:deadline_ms]
          seat = state[:participants].fetch(state[:turn_index])
          player = state[:players].fetch(seat)
          case state[:type]
          when "numbered_balls"
            take_balls!(state, seat, 1, deadline)
          when "dice_duel"
            roll!(state, seat, 1)
            finish_player!(player, :automatic_roll)
          when "risky_dice"
            roll!(state, seat, 2) if player[:rolls].empty?
            finish_player!(player, player[:total] > 25 ? :busted : :timeout)
            state[:notices] << [:challenge_stand, seat, player[:total]]
          when "blackjack"
            finish_player!(player, :timeout)
            state[:notices] << [:challenge_stand, seat, player[:total]]
          end
          advance_turn!(state, deadline) unless state[:type] == "numbered_balls"
          finalize_if_done!(state, deadline)
        end
        return true
      end

      state[:players].each_value do |player|
        next if player[:done]

        finish_player!(player, :timeout)
      end
      finalize_if_done!(state, state[:deadline_ms])
      true
    end

    # Do not broadcast state, its Random objects, hidden answer or opponents'
    # unfinished input. Copies cannot mutate the authoritative model.
    def public_view(state, viewer:)
      view = {
        type: state[:type], participants: state[:participants].dup,
        started_at_ms: state[:started_at_ms], deadline_ms: state[:deadline_ms],
        finished: state[:finished], notices: duplicate(state[:notices]),
        ready: state[:players].transform_values { |player| player[:done] }
      }
      view[:question] = duplicate(state[:question]) if state.key?(:question)
      # The input announces the required width and submits on the final digit.
      # This is an agreed public hint, including in Guess the number.
      view[:answer_digits] = state[:answer].to_s.length if state.key?(:answer)
      view[:attempt_limit] = state[:attempt_limit] if state.key?(:attempt_limit)
      if TURN_TYPES.include?(state[:type])
        view[:turn_seat] = state[:finished] ? nil : state[:participants].fetch(state[:turn_index])
        view[:turn_started_at_ms] = state[:turn_started_at_ms]
      end
      if state[:type] == "numbered_balls"
        view[:remaining] = state[:remaining].dup
        view[:scores] = state[:players].transform_values { |player| player[:total] }
      end
      if ATTEMPT_TURN_TYPES.include?(state[:type])
        # Finished attempts have already been announced. A blackjack hand
        # that reached 21 on the initial deal is not public until its turn.
        view[:completed_totals] = state[:players].filter_map do |seat, player|
          [seat, player[:total]] if player[:done] &&
            (state[:type] != "blackjack" || player[:hand_announced])
        end.to_h
      end
      if state[:players].key?(viewer)
        view[:own] = player_view(state[:players].fetch(viewer))
        view[:own][:die] = state[:dice].fetch(viewer).dup if state.key?(:dice)
        if state[:type] == "guess_number" && !state[:finished]
          # Even the guessing player receives only higher/lower feedback.
          # The exact distance, or which earlier guess was nearest, would
          # disclose additional information about the unrevealed number.
          view[:own].delete(:best)
          view[:own][:attempts].each { |attempt| attempt.delete(:distance) }
        end
      end
      if state[:finished]
        view[:finished_at_ms] = state[:finished_at_ms]
        view[:scores] = duplicate(state[:scores])
        view[:results] = duplicate(state[:results])
        view[:outcome] = duplicate(state[:outcome])
        view[:answer] = state[:answer] if state.key?(:answer)
      end
      view
    end

    def time?(value)
      value.is_a?(Integer) && value >= 0
    end
    private_class_method :time?

    def normalize_action(action)
      return nil unless action.is_a?(Hash) && action.keys.all? { |key| ACTION_KEYS.include?(key.to_s) }

      input = {}
      action.each do |key, value|
        return nil unless key.is_a?(String) || key.is_a?(Symbol)
        normalized = key.to_s.to_sym
        return nil if input.key?(normalized)
        input[normalized] = value
      end
      kind = input[:kind]
      return nil unless kind.is_a?(String) || kind.is_a?(Symbol)
      input[:kind] = ACTION_KINDS[kind.to_s]
      return nil unless input[:kind] && input[:press_id].is_a?(Integer) && input[:press_id].positive?
      return nil if input.key?(:repeat) && input[:repeat] != false

      input
    end
    private_class_method :normalize_action

    def integer_answer(value)
      return value if value.is_a?(Integer) && value.abs <= 999_999_999
      return nil unless value.is_a?(String) && value.match?(/\A-?[0-9]{1,9}\z/)

      value.to_i
    end
    private_class_method :integer_answer

    def permitted_action?(state, seat, player, input)
      kind = input[:kind]
      case state[:type]
      when "rock_paper_scissors"
        kind == :choose && CHOICES.include?(input[:value])
      when "dice_duel"
        kind == :roll && !input.key?(:value)
      when "blackjack"
        !input.key?(:value) && (kind == :stand || (kind == :hit && !player[:deck].empty?))
      when "risky_dice"
        !input.key?(:value) && (kind == :roll || (kind == :save && !player[:rolls].empty?))
      when "guess_number", *ANSWER_TYPES
        return false unless kind == :answer
        value = integer_answer(input[:value])
        return false if value.nil? || (state[:type] == "guess_number" && !value.between?(1, 999))
        input[:value] = value
        true
      when "numbered_balls"
        value = integer_answer(input[:value])
        return false unless kind == :take && state[:participants][state[:turn_index]] == seat &&
          value && value.between?(1, 3) && value <= state[:remaining].length
        input[:value] = value
        true
      else
        false
      end
    end
    private_class_method :permitted_action?

    def copy_dice(seats, source)
      unless source.nil? || (source.is_a?(Hash) && source.keys.all? { |seat| seats.include?(seat) })
        raise ArgumentError, "Invalid challenge dice"
      end
      seats.to_h do |seat|
        die = source && source.key?(seat) ? source[seat] : {die_sides: 6, die_rolls: 0}
        unless die.is_a?(Hash) && DICE_SIDES.include?(die[:die_sides]) &&
            die[:die_rolls].is_a?(Integer) && die[:die_rolls] >= 0 &&
            (die[:die_sides] == 6 ? die[:die_rolls].zero? : die[:die_rolls].positive?)
          raise ArgumentError, "Invalid challenge die modifier"
        end
        [seat, {die_sides: die[:die_sides], die_rolls: die[:die_rolls]}]
      end
    end
    private_class_method :copy_dice

    def copy_decks(seats, decks)
      unless decks.is_a?(Hash) && decks.keys.sort == seats.sort && decks.values.all? do |deck|
          deck.is_a?(Array) && deck.length == 52 && deck.all? { |card| card.is_a?(Integer) } && deck.sort == BLACKJACK_CARDS
        end
        raise ArgumentError, "Invalid prepared 52-card blackjack decks"
      end

      decks.transform_values(&:dup)
    end
    private_class_method :copy_decks

    def roll!(state, seat, count)
      player = state[:players].fetch(seat)
      values = Dice.roll!(state[:dice].fetch(seat), random: player[:random], count: count, race: false)
      player[:rolls] << values
      player[:total] += values.sum
      state[:notices] << [:challenge_roll, seat, values.dup, player[:total]]
    end
    private_class_method :roll!

    def draw_card!(player)
      card = player[:deck].shift
      rank = card / 4 + 1
      total = player.fetch(:total)
      # Choose the new ace once; later draws never revalue earlier cards.
      value = rank == 1 ? (total + 11 <= 21 ? 11 : 1) : [rank, 10].min
      player[:cards] << card
      player[:total] = total + value
    end
    private_class_method :draw_card!

    def finish_player!(player, status)
      player[:done], player[:status] = true, status
    end
    private_class_method :finish_player!

    def finish_total_if_needed!(player, limit)
      return if player[:total] < limit

      finish_player!(player, player[:total] > limit ? :busted : :maximum)
    end
    private_class_method :finish_total_if_needed!

    def announce_hand!(state, seat)
      return unless state[:type] == "blackjack"

      player = state[:players].fetch(seat)
      return if player[:hand_announced]

      player[:hand_announced] = true
      state[:notices] << [:challenge_hand, seat, player[:cards].map { |card| card / 4 + 1 }, player[:total]]
    end
    private_class_method :announce_hand!

    def advance_turn!(state, now_ms)
      seats = state[:participants]
      # Drawing/rolling continues until this player's attempt ends.
      # Each accepted action still starts a fresh decision deadline.
      next_index = state[:turn_index]
      unless ATTEMPT_TURN_TYPES.include?(state[:type]) && !state[:players].fetch(seats[next_index])[:done]
        next_index = (1..seats.length).map { |offset| (state[:turn_index] + offset) % seats.length }
          .find do |index|
            announce_hand!(state, seats[index])
            !state[:players].fetch(seats[index])[:done]
          end
      end
      state[:turn_index] = next_index
      return unless next_index

      state[:turn_started_at_ms] = now_ms
      state[:deadline_ms] = now_ms + TYPES.fetch(state[:type])[2]
    end
    private_class_method :advance_turn!

    def elapsed_tenths(state, now_ms)
      (now_ms - state[:started_at_ms] + 50) / 100
    end
    private_class_method :elapsed_tenths

    def accept_guess!(state, player, value, now_ms)
      answer = state[:answer]
      attempt = {
        value: value, distance: (value - answer).abs,
        feedback: value == answer ? :correct : (value < answer ? :higher : :lower)
      }
      player[:attempts] << attempt
      player[:best] = attempt.dup if player[:best].nil? || attempt[:distance] < player[:best][:distance]
      if value == answer
        finish_player!(player, :correct)
      elsif player[:attempts].length == 10
        finish_player!(player, :attempts_exhausted)
      end
    end
    private_class_method :accept_guess!

    def accept_answer!(state, player, value, now_ms)
      correct = value == state[:answer]
      player[:attempts] << {value: value, correct: correct}
      if correct
        player[:elapsed_tenths] = elapsed_tenths(state, now_ms)
        finish_player!(player, :correct)
      elsif player[:attempts].length == state[:attempt_limit]
        finish_player!(player, :attempts_exhausted)
      end
    end
    private_class_method :accept_answer!

    def take_balls!(state, seat, count, now_ms)
      taken = state[:remaining].shift(count)
      player = state[:players].fetch(seat)
      player[:balls].concat(taken)
      player[:total] += taken.sum
      state[:notices] << [:challenge_take, seat, taken.dup]
      if state[:remaining].empty?
        state[:players].each_value { |participant| finish_player!(participant, :completed) }
      else
        state[:turn_index] = 1 - state[:turn_index]
        state[:turn_started_at_ms] = now_ms
        state[:deadline_ms] = now_ms + TYPES.fetch('numbered_balls')[2]
        state[:notices] << [:challenge_turn, state[:participants][state[:turn_index]]]
      end
    end
    private_class_method :take_balls!

    def prepare_question!(state, random, race_snapshot)
      case state[:type]
      when "copy_number"
        state[:answer] = random.rand(900) + 100
        state[:question] = {kind: :copy_number, number: state[:answer]}
      when "arithmetic"
        operation = [:add, :subtract, :multiply, :divide].fetch(random.rand(4))
        case operation
        when :add
          left = random.rand(101)
          right = random.rand(101 - left)
          answer = left + right
        when :subtract
          left = random.rand(101)
          right = random.rand(left + 1)
          answer = left - right
        when :multiply
          left, right = random.rand(11) + 2, random.rand(11) + 2
          answer = left * right
        when :divide
          right, answer = random.rand(11) + 2, random.rand(11) + 2
          left = right * answer
        end
        state[:question] = {kind: :arithmetic, operation: operation, left: left, right: right}
        state[:answer] = answer
      when "race_question"
        candidates = race_questions(race_snapshot)
        selected = candidates.fetch(random.rand(candidates.length))
        state[:question] = selected[0]
        state[:answer] = selected[1]
      end
    end
    private_class_method :prepare_question!

    # The adapter supplies a public snapshot, not live race state. No ordinal
    # ranking questions are generated, so tied racers are unambiguous.
    def race_questions(snapshot)
      unless snapshot.is_a?(Hash) && snapshot[:racers].is_a?(Hash) && !snapshot[:racers].empty? &&
          snapshot[:board_length].is_a?(Integer) && snapshot[:board_length].positive?
        raise ArgumentError, "Race question requires a public numeric snapshot"
      end
      questions = []
      snapshot[:racers].keys.sort.each do |seat|
        racer = snapshot[:racers].fetch(seat)
        unless seat.is_a?(Integer) && seat >= 0 && racer.is_a?(Hash) &&
            [:progress, :feathers, :card_count].all? { |field| racer[field].is_a?(Integer) && racer[field] >= 0 }
          raise ArgumentError, "Invalid public racer snapshot"
        end
        values = {
          square: racer[:progress] % snapshot[:board_length] + 1,
          lap: racer[:progress] / snapshot[:board_length] + 1,
          feathers: racer[:feathers], card_count: racer[:card_count]
        }
        values.each { |field, value| questions << [{kind: :race_question, seat: seat, field: field}, value] }
      end
      questions
    end
    private_class_method :race_questions

    def finalize_if_done!(state, now_ms)
      return if state[:finished] || !state[:players].values.all? { |player| player[:done] }

      state[:finished], state[:finished_at_ms] = true, now_ms
      state[:results] = state[:players].transform_values { |player| player_view(player) }
      case state[:type]
      when "rock_paper_scissors"
        finish_rps!(state)
      when "guess_number"
        finish_guesses!(state)
      when *ANSWER_TYPES
        finish_speed!(state)
      else
        state[:scores] = state[:players].transform_values { |player| player[:total] }
        ceiling = {"blackjack" => 21, "risky_dice" => 25}[state[:type]]
        eligible = state[:scores].reject { |_seat, score| ceiling && score > ceiling }
        best = highest(eligible)
        state[:outcome] = outcome(ceiling ? :ceiling : :difference, best)
        state[:outcome][:ceiling] = ceiling if ceiling
      end
    end
    private_class_method :finalize_if_done!

    def finish_rps!(state)
      choices = state[:players].transform_values { |player| player[:choice] }
      state[:scores] = choices
      if choices.values.any?(&:nil?)
        # The agreed timeout awards the duel to the sole participant who
        # actually chose. Two missing choices have neither winner nor transfer.
        state[:outcome] = outcome(:fixed, choices.compact.keys)
      else
        first, second = state[:participants]
        difference = (CHOICES.index(choices[first]) - CHOICES.index(choices[second])) % 3
        best = difference.zero? ? state[:participants] : [difference == 1 ? first : second]
        state[:outcome] = outcome(:fixed, best)
      end
      state[:outcome][:amount] = 3
    end
    private_class_method :finish_rps!

    def finish_guesses!(state)
      state[:scores] = state[:players].transform_values { |player| player[:best] && player[:best][:distance] }
      ranks = state[:scores].compact
      best = lowest(ranks)
      state[:outcome] = outcome(:guess_number, best)
    end
    private_class_method :finish_guesses!

    def finish_speed!(state)
      state[:scores] = state[:players].transform_values { |player| player[:elapsed_tenths] }
      valid = state[:scores].reject { |_seat, elapsed| elapsed.nil? }
      state[:outcome] = outcome(:speed, lowest(valid))
      # An unsuccessful participant pays as if they used the full task limit,
      # but nil remains in scores so that this fallback can never win.
      state[:outcome][:time_limit] = TYPES.fetch(state[:type])[2] / 100
    end
    private_class_method :finish_speed!

    def outcome(kind, best)
      {kind: kind, winner: best.size == 1 ? best.first : nil,
        tied: best.size > 1 ? best.dup : [], settlement_ready: true, unresolved: []}
    end
    private_class_method :outcome

    def highest(scores)
      return [] if scores.empty?

      best = scores.values.max
      scores.select { |_seat, value| value == best }.keys
    end
    private_class_method :highest

    def lowest(scores)
      return [] if scores.empty?

      best = scores.values.min
      scores.select { |_seat, value| value == best }.keys
    end
    private_class_method :lowest

    def player_view(player)
      fields = [:done, :status, :choice, :rolls, :total, :cards, :attempts,
        :best, :elapsed_tenths, :balls]
      view = player.each_with_object({}) { |(key, value), result| result[key] = duplicate(value) if fields.include?(key) }
      view[:card_ranks] = player[:cards].map { |card| card / 4 + 1 } if player.key?(:cards)
      view
    end
    private_class_method :player_view

    def duplicate(value)
      case value
      when Hash
        value.to_h { |key, entry| [key, duplicate(entry)] }
      when Array
        value.map { |entry| duplicate(entry) }
      when String
        value.dup
      else
        value
      end
    end
    private_class_method :duplicate
  end
end
