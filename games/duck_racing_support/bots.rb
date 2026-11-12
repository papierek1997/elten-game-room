# frozen_string_literal: true

require "digest"
require_relative "challenge_bot"
require_relative "board"
require_relative "cards"
require_relative "feathers"
require_relative "session"
require_relative "../../lib/game_bots"

module GameRoomDuckRacing
  # Shared only by one game's executor/planning copies. Work is computed before
  # publication, outside this lock; the delay hook only reads immutable values.
  # At most eight current-seat plans survive, never a history of old challenges.
  class BotCache
    def initialize
      @mutex, @scope, @generation, @version, @entries = Mutex.new, nil, 0, 0, {}
    end

    def activate(scope)
      scope = immutable(scope)
      @mutex.synchronize do
        if @scope != scope
          @scope, @entries, @version = scope, {}, 0
          @generation += 1
        end
        @generation
      end
    end

    def read(scope, seat, identity)
      @mutex.synchronize do
        item = @entries[seat] if @scope == scope
        item && item[:identity] == identity ? item[:value] : nil
      end
    end

    def publish(scope, generation, seat, identity, value)
      # No caller may later change a published trace or a cached action.
      item = immutable({identity: identity, value: value})
      @mutex.synchronize do
        return nil unless @scope == scope && @generation == generation
        existing = @entries[seat]
        return existing[:value] if existing && existing[:identity] == identity
        @entries[seat] = item
        @version += 1
        item[:value]
      end
    end

    def version(scope)
      @mutex.synchronize { @scope == scope ? @version : 0 }
    end

    def size
      @mutex.synchronize { @entries.size }
    end

    private

    def immutable(value)
      case value
      when Hash then value.to_h { |key, item| [immutable(key), immutable(item)] }.freeze
      when Array then value.map { |item| immutable(item) }.freeze
      when String then value.dup.freeze
      else value.freeze
      end
    end
  end

  # Include in GameRoomGames::DuckRacing. The game constructs @bot_cache and
  # passes it to build_session_game copies, not into durable replay or saves.
  module Bots
    def active_actors(replay)
      return [] unless replay && !replay.finished? && replay.state[:race]
      race, round = replay.state.values_at(:race, :round)
      unless round
        racer = race[:racers].fetch(race[:turn])
        return [] if racer[:frozen_turns].positive? || racer[:skip_turns].positive?
        return [replay.players.fetch(race[:turn])]
      end
      return [] unless round[:phase] == :playing
      if round[:attempts] || round[:results]
        completed = round[:attempts] || round[:results]
        return round[:challenge][:participants].reject { |seat| completed.key?(seat) }
          .map { |seat| replay.players.fetch(seat) }
      end
      if (protocol = round[:private])
        return [] unless protocol[:phase] == :collecting
        return round[:challenge][:participants].reject { |seat| protocol[:commitments].key?(seat) }
          .map { |seat| replay.players.fetch(seat) }
      end
      return [] unless round[:engine]
      if round[:challenge][:kind] == 'sound_order'
        return round[:challenge][:participants].map { |seat| replay.players.fetch(seat) }
      end
      turn = ChallengeEngine.current_turn(round[:engine])
      turn.nil? ? [] : [replay.players.fetch(turn)]
    end

    def legal_actions(replay, actor, context: nil)
      return [] unless active_actors(replay).any? { |name| same_user?(name, actor) }
      seat = player_index(replay.players, actor)
      state, round = replay.state, replay.state[:round]
      unless round
        race = state.fetch(:race)
        racer = race[:racers].fetch(seat)
        actions = [{"kind" => "duck", "action" => "race", "input" => {"kind" => "roll"}}]
        return actions if race[:card_played]
        racer[:hand].each do |card|
          type = Cards::BY_ID.fetch(card.type)
          next if racer[:feathers] < type.cost
          next if type.target == :square && race[:traps].key?(Board.square(racer[:progress]))
          targets = case type.target
          when :self, :square then [nil]
          when :any then race[:racers].keys
          when :opponent then race[:racers].keys - [seat]
          end
          targets.each do |target|
            next if type.id == "challenge" && race[:racers].fetch(target)[:frozen_turns].positive?
            actions << {"kind" => "duck", "action" => "race", "input" =>
              {"kind" => "play", "card" => card.id, "target" => target}}
          end
        end
        return actions
      end
      base = {"kind" => "duck", "challenge" => round[:challenge][:id]}
      # This is a bot planning intent, not a forged finished result. Strategy
      # supplies a validated trace only once its actual elapsed time has passed.
      return [base.merge("action" => "submit_trace")] if round[:private] || round[:attempts] || round[:results]
      engine = round.fetch(:engine)
      press = engine[:last_press].fetch(seat) + 1
      view = ChallengeEngine.view(engine, seat: seat)
      if view[:type] == 'sound_order'
        return (1..8).to_a.combination(2).map do |first, second|
          base.merge('action' => 'input', 'input' => {'kind' => 'swap', 'value' => first, 'other' => second, 'press_id' => press})
        end
      end
      kinds = case view[:type]
      when "dice_duel" then ["roll"]
      when "blackjack" then ["hit", "stand"]
      when "risky_dice" then view[:own][:rolls].empty? ? ["roll"] : ["roll", "save"]
      end
      if kinds
        return kinds.map { |kind| base.merge("action" => "input", "input" => {"kind" => kind, "press_id" => press}) }
      end
      if view[:type] == "numbered_balls"
        values = (1..[3, view[:remaining].length].min).to_a
        kind = "take"
      else
        public = view.fetch(:public)
        values = ChallengeBot::MEMORY_POSITIONS - public[:removed] - public[:revealed].map { |item| item[:position] }
        kind = "reveal"
      end
      values.map { |value| base.merge("action" => "input", "input" => {"kind" => kind, "value" => value, "press_id" => press}) }
    end

    def bot_strategy
      @duck_bot_strategy ||= BotStrategy.new
    end

    def bot_move_delay(replay, actor, context: nil)
      round = replay.state[:round]
      return super unless round
      seat = player_index(replay.players, actor)
      return 0.0 unless seat && active_actors(replay).any? { |name| same_user?(name, actor) }
      scope = duck_bot_scope(replay)
      @bot_cache.activate(scope)
      entry = @bot_cache.read(scope, seat, duck_bot_identity(replay, actor, seat))
      return 0.0 unless entry
      [entry[:ready_ms] - duck_bot_now(replay, context), 0].max / 1000.0
    end

    def bot_delay_revision(replay, _revision)
      scope = duck_bot_scope(replay)
      @bot_cache.activate(scope)
      round = replay.state[:round]
      decision = round ? [round[:phase], round[:engine]&.values_at(:last_press, :last_time), duck_turn_started_ms(round)] : replay.state[:race]&.fetch(:revision)
      [duck_bot_hash([scope, decision]), @bot_cache.version(scope)]
    end

    def bot_observation(replay, actor)
      seat = player_index(replay.players, actor)
      return {} unless seat && replay.state[:race]
      state, race = replay.state, replay.state[:race]
      observation = {
        seat: seat, session_id: state[:session_id], laps: state[:laps],
        turn: race[:turn], card_played: race[:card_played],
        racers: race[:racers].transform_values do |racer|
          racer.slice(:progress, :feathers, :frozen_turns, :skip_turns, :die_sides, :die_rolls)
            .merge(card_count: racer[:hand].length)
        end,
        hand: race[:racers].fetch(seat)[:hand].map { |card| {id: card.id, type: card.type} },
        traps: race[:traps].transform_values { |trap| {owner: trap[:owner], type: trap[:card].type} }
      }
      if (round = state[:round])
        observation[:challenge] = round[:challenge].slice(:id, :kind, :participants, :trigger)
        observation[:challenge_phase] = round[:phase]
        if round[:engine]
          observation[:challenge_view] = ChallengeEngine.view(round[:engine], seat: seat)
        elsif round[:private]
          observation[:submitted] = round[:private][:commitments].keys
        elsif round[:attempts]
          observation[:submitted] = round[:attempts].keys
        elsif round[:results]
          observation[:submitted] = round[:results].keys
        end
      end
      Session.copy(observation)
    end

    # Called only by the shared bot strategy, after prepare_bot releases the
    # write lock. Never called by a surface, a timer or bot_move_delay.
    def plan_duck_bot(replay, actor, context: nil)
      seat = player_index(replay.players, actor)
      round = replay.state[:round]
      return nil unless round && seat && active_actors(replay).any? { |name| same_user?(name, actor) }
      scope = duck_bot_scope(replay)
      generation = @bot_cache.activate(scope)
      identity = duck_bot_identity(replay, actor, seat)
      cached = @bot_cache.read(scope, seat, identity)
      return cached if cached
      seed = duck_bot_hash([replay.state[:session_id], round[:challenge][:id], seat, actor.to_s.downcase])
      delay_ms = (normalize_options(replay.state[:options])["bot_delay"] * 1_000).round
      if round[:private] || round[:attempts] || round[:results]
        compact = !!(round[:results] || round.dig(:private, :compact))
        planned = ChallengeBot.plan(round[:challenge], seat: seat, seed: seed,
          resources: resources_for(replay.state[:options]), delay_ms: delay_ms, compact: compact)
        trace, elapsed = compact ? planned : [planned, planned.fetch('finished_at')]
        preparation = ChallengeEngine::SPEED_TYPES.include?(round[:challenge][:kind]) ? ChallengeEngine::PREPARATION_MS : 0
        preparation = ChallengeEngine::COUNT_DUCKS_PREPARATION_MS if round[:challenge][:kind] == 'count_ducks'
        value = {ready_ms: round[:started_at] + preparation + elapsed, trace: trace}
      else
        view = ChallengeEngine.view(round[:engine], seat: seat)
        memory = duck_memory_from_history(replay, seat)
        choice = ChallengeBot.choose_sequential(view, seat: seat, seed: seed, memory: memory,
          press_id: round[:engine][:last_press].fetch(seat) + 1, delay_ms: delay_ms)
        return nil unless choice
        last_action = if round[:challenge][:kind] == 'sound_order'
          [round[:engine][:last_time].fetch(seat), view[:started_ms].to_i].max
        else
          [round[:engine][:last_time].values.max || 0, duck_turn_started_ms(round).to_i].max
        end
        value = {ready_ms: round[:started_at] + last_action + choice[:delay_ms],
          input: choice[:action].to_h { |key, item| [key.to_s, key == :kind ? item.to_s : item] }}
      end
      @bot_cache.publish(scope, generation, seat, identity, value)
    end

    def duck_bot_ready?(entry, replay, context)
      entry && duck_bot_now(replay, context) >= entry[:ready_ms]
    end

    private

    def duck_bot_now(replay, context)
      ((context&.now || GameRoomSessionClock.for_state(replay.state)).to_f * 1000).round
    end

    def duck_bot_scope(replay)
      state, round = replay.state, replay.state[:round]
      [state[:session_id], round&.dig(:challenge, :id), round&.dig(:challenge, :kind),
        round&.dig(:challenge, :participants), replay.players.map { |name| name.to_s.downcase }, state[:bot_controller_epoch],
        state.dig(:options, 'bot_delay'),
        round && duck_bot_hash([round[:challenge], round[:started_at], state[:fingerprint]])]
    end

    def duck_bot_identity(replay, actor, seat)
      round = replay.state[:round]
      if round&.dig(:challenge, :kind) == 'sound_order'
        return [seat, actor.to_s.downcase, round.dig(:engine, :last_press, seat), round.dig(:engine, :last_time, seat)]
      end
      [seat, actor.to_s.downcase, round&.dig(:engine, :last_press), round&.dig(:engine, :last_time),
        duck_turn_started_ms(round)]
    end

    # Numeric challenges and public audio turns keep the same boundary in
    # different model-owned fields. Expiry can move it without a new input.
    def duck_turn_started_ms(round)
      round&.dig(:engine, :model, :turn_started_at_ms) ||
        round&.dig(:engine, :model, :public, :turn_started_ms)
    end

    def duck_bot_hash(value)
      Digest::SHA256.hexdigest(JSON.generate(value))[0, 16].to_i(16)
    end

    def duck_memory_from_history(replay, seat)
      round = replay.state[:round]
      return {} unless round[:challenge][:kind] == "sound_memory"
      model = ChallengeEngine.start(round[:challenge])
      memory = ChallengeBot.observe(ChallengeEngine.view(model, seat: seat))
      # The local replay projection is already authenticated and accepted. It
      # contains only this challenge's public input/expiry events, not reveals
      # of private attempts. Reconstruct every heard tone, including the first
      # of a pair which disappears from the current view after its second key.
      replay.state.fetch(:duck_challenge_events, []).each do |data|
        accepted = case data[:action]
        when "input"
          ChallengeEngine.submit(model, seat: data[:seat], action: data[:input], now_ms: data[:at], seed: data[:seed])
        when "advance" then ChallengeEngine.expire(model, now_ms: data[:at], seed: data[:seed])
        end
        memory = ChallengeBot.observe(ChallengeEngine.view(model, seat: seat), memory: memory) if accepted
      end
      ChallengeBot.observe(ChallengeEngine.view(round[:engine], seat: seat), memory: memory)
    end
  end

  class BotStrategy
    include GameRoomBots::ReplayOnlyStrategy

    def choose(actions:, observation:, actor:, game:, replay:, context:, **_unused)
      return nil if actions.empty?
      if replay.state[:round]
        entry = game.plan_duck_bot(replay, actor, context: context)
        return nil unless game.duck_bot_ready?(entry, replay, context)
        if entry[:trace]
          actions.first.merge("trace" => entry[:trace])
        else
          actions.find { |action| action["input"] == entry[:input] }
        end
      else
        evaluation = RaceEvaluation.new(observation)
        scored = actions.map { |action| [action, evaluation.score(action)] }
        # Stable ties do not consume the race generator or reveal future draws.
        scored.max_by { |action, score| [score, action.fetch("input")["card"].to_s] }.first
      end
    end
  end

  # Evaluates public board effects and expected rolls, never the saved RNG,
  # opponents' hands, secret choices or precomputed random outcomes.
  class RaceEvaluation
    def initialize(view)
      @view, @seat = view, view.fetch(:seat)
      @racers, @me = view.fetch(:racers), view.fetch(:racers).fetch(@seat)
      @goal = view.fetch(:laps) * Board::LENGTH
    end

    def score(action)
      input = action.fetch("input")
      return 0.0 if input["kind"] == "roll"
      card = @view[:hand].find { |item| item[:id] == input["card"] }
      return -Float::INFINITY unless card
      type = Cards::BY_ID.fetch(card[:type])
      target = input["target"] || @seat
      balance = @me[:feathers] + type.gain - type.cost
      value = feather_value(@seat, type.gain - type.cost)
      if type.target == :square
        # An already passed square is only encountered again after a lap. A
        # trap is most useful when a nearby opponent is approaching it now.
        square = Board.square(@me[:progress])
        chance = @racers.reject { |seat, _| seat == @seat }.sum do |seat, racer|
          distance = (square - Board.square(racer[:progress])) % Board::LENGTH
          next 0.0 unless distance.positive? && distance <= racer[:die_sides]
          [type.effects.sum { |effect| effect_value(effect, seat) }, 0].max / racer[:die_sides]
        end
        value += chance
      else
        value += type.effects.sum { |effect| effect_value(effect, target) }
      end
      # Keep a reserve, especially while leading: reaching zero freezes a
      # leader longer. A genuinely winning move still outranks this penalty.
      if balance <= 0
        last = @racers.values.map { |racer| racer[:progress] }.min
        value -= 4.0 * Feathers.freeze_turns(progress: @me[:progress], last_progress: last, board_length: Board::LENGTH)
      elsif balance < 4 && type.cost.positive?
        value -= (4 - balance) * 0.9
      end
      value - 0.15 # Save cards whose expected benefit is negligible.
    end

    private

    def threat(seat)
      return 1.0 if seat == @seat
      racer = @racers.fetch(seat)
      gap = racer[:progress] - @me[:progress]
      [[0.65 + gap / 18.0, 0.3].max, 1.6].min + (racer[:progress] >= @goal - 12 ? 0.8 : 0)
    end

    def signed(seat, value)
      seat == @seat ? value : -value * threat(seat)
    end

    def feather_value(seat, amount)
      feathers = @racers.fetch(seat)[:feathers]
      rate = feathers < 5 ? 1.8 : (feathers < 12 ? 0.8 : 0.45)
      signed(seat, amount * rate)
    end

    def effect_value(effect, target)
      kind, amount, extra = effect
      racer = @racers.fetch(target)
      case kind
      when :move then movement(target, amount)
      when :random_move
        (amount..extra).sum { |distance| movement(target, distance) + movement(target, -distance) } / (2.0 * (extra - amount + 1))
      when :feathers then feather_value(target, [amount, -racer[:feathers]].max)
      when :steal_feathers
        actual = [amount, racer[:feathers]].min
        feather_value(@seat, actual) + feather_value(target, -actual)
      when :die
        gain = (amount - 6) / 2.0 * extra - (racer[:die_sides] - 6) / 2.0 * racer[:die_rolls]
        signed(target, gain)
      when :skip then signed(target, -amount * (racer[:die_sides] + 1) / 2.0)
      when :cards then signed(target, amount * 1.1)
      when :everyone_cards then @racers.keys.sum { |seat| signed(seat, amount * 0.45) }
      when :steal_cards then racer[:card_count].zero? ? -1 : 1.8
      when :swap_hands then (racer[:card_count] - (@me[:card_count] - 1)) * 0.75
      when :pass_hands
        previous = (@seat - 1) % @racers.length
        (@racers.fetch(previous)[:card_count] - (@me[:card_count] - 1)) * 0.75
      when :quiz then 0.9
      when :duel then @me[:feathers] >= 8 && racer[:feathers] >= 5 ? 0.5 : -1.0
      when :group_challenge then @me[:feathers] >= 10 ? 0.35 : -1.0
      else 0.0
      end
    end

    def movement(seat, amount)
      racer = @racers.fetch(seat)
      destination = [racer[:progress] + amount, 0].max
      return signed(seat, 1_000_000) if destination >= @goal
      value = destination - racer[:progress]
      return 0.0 if value.zero?
      square = Board.square(destination)
      effects = Board::SQUARES.fetch(square)
      value = signed(seat, value)
      effects.each do |kind, quantity, *_rest|
        case kind
        when :feathers then value += feather_value(seat, quantity)
        when :cards then value += signed(seat, quantity * 0.8)
        when :skip then value += signed(seat, -quantity * 3.5)
        end
      end
      if (trap = @view[:traps][square]) && trap[:owner] != seat
        # A known harmful trap changes the desirability of this destination;
        # do not recursively follow an unbounded or random effect chain.
        impact = Cards::BY_ID.fetch(trap[:type]).effects.sum do |kind, quantity, _|
          case kind
          when :move then quantity
          when :skip then -3.5 * quantity
          when :steal_feathers then -quantity
          else 0.0
          end
        end
        value += signed(seat, impact)
      end
      value
    end
  end
end
