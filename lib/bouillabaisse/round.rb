require 'digest'
require_relative '../../games/card_game'
require_relative '../hidden_card_deals'
require_relative 'information'

module BouillabaissePlanning
  # The hypothetical round is deliberately not a full replay or a fork of
  # the live state. Its only inputs are the fair observation and legal cards.
  class Round
    CARD_IDS = GameRoomGames::CardGame::CARD_RANKS.product(GameRoomGames::CardGame::CARD_SUITS).
      map(&:join).each_with_index.to_h.freeze
    SUIT_IDS = GameRoomGames::CardGame::CARD_SUITS.each_with_index.to_h.freeze
    State = Struct.new(:hands, :counts, :unplayed, :trick, :raw, :voids, :turn, :points_left, keyword_init: true) do
      def branch
        self.class.new(hands: hands.map(&:dup), counts: counts.dup, unplayed: unplayed.dup,
          trick: trick.dup, raw: raw.dup, voids: voids.dup, turn: turn, points_left: points_left)
      end
    end

    attr_reader :root, :initial, :number, :size, :points, :trick_points, :total, :all_or_nothing

    def initialize(observation)
      @players = observation.fetch('seats')
      @seats = @players.each_with_index.to_h
      @size = @players.size
      @root = @seats.fetch(observation.fetch('actor'))
      @number = observation.fetch('round')
      @all_or_nothing = observation.fetch('all_or_nothing') && @number != 4
      @points = Array.new(CARD_IDS.size, 0)
      observation.fetch('card_points').each { |card, value| @points[CARD_IDS.fetch(card)] = value }
      @trick_points = Scoring.trick_points(@number)
      deck = ids(observation.fetch('deck'))
      @total = deck.sum { |card| @points[card] } + deck.size / @size * @trick_points
      @scores = @players.map { |player| observation.fetch('scores').fetch(player) }
      @absence = {}
      @initial = build_state(observation, deck)
      @seed = Digest::SHA256.hexdigest(Marshal.dump([@number, @root, @initial.hands[@root].sort,
        @initial.unplayed.sort, @initial.trick, @initial.raw, @initial.voids, @points])).to_i(16)
    end

    def worlds(limit)
      opponents = (0...@size).to_a - [@root]
      counts = opponents.to_h { |player| [player, @initial.counts[player]] }
      cards = @initial.unplayed - @initial.hands[@root]
      return [] unless counts.values.sum == cards.size

      allowed = ->(player, card) { !void?(@initial, player, card % 4) }
      if opponents.size == 1
        player = opponents.first
        return [] unless cards.all? { |card| allowed.call(player, card) }
        return [world(player => cards)]
      end

      random = Random.new(@seed)
      unique = {}
      (limit * 6).times do
        assignment = GameRoomHiddenCardDeals.assign(cards, opponents, counts, random, &allowed)
        next unless assignment

        key = opponents.map { |player| assignment.fetch(player).sort }
        unique[key] ||= world(assignment)
        break if unique.size >= limit
      end
      unique.values
    end

    # Exact information only when every unseen card has a single eligible
    # seat and that assignment satisfies all public hand sizes. A sample
    # containing just one world is not itself proof.
    def forced_world
      opponents = (0...@size).select { |seat| seat != @root && @initial.counts[seat].positive? }
      assignment = opponents.to_h { |seat| [seat, []] }
      (@initial.unplayed - @initial.hands[@root]).each do |card|
        eligible = opponents.reject { |seat| void?(@initial, seat, card % 4) }
        return nil unless eligible.one?

        assignment.fetch(eligible.first) << card
      end
      return nil unless opponents.all? { |seat| assignment.fetch(seat).size == @initial.counts[seat] }

      world(assignment)
    end

    def legal(state)
      hand = state.hands[state.turn]
      return hand if state.trick.empty?

      led = state.trick.first.last % 4
      following = hand.select { |card| card % 4 == led }
      following.empty? ? hand : following
    end

    def play(state, card)
      actor = state.turn
      if !state.trick.empty? && card % 4 != state.trick.first.last % 4
        state.voids[actor] |= 1 << (state.trick.first.last % 4)
      end
      state.hands[actor].delete(card)
      state.counts[actor] -= 1
      state.unplayed.delete(card)
      state.points_left -= @points[card]
      state.trick << [actor, card]
      if state.trick.size == @size
        winner, = winning_play(state.trick)
        state.raw[winner] += @trick_points + state.trick.sum { |_, value| @points[value] }
        state.trick.clear
        state.turn = winner
      else
        state.turn = (actor + 1) % @size
      end
    end

    def finished?(state)
      state.trick.empty? && (state.unplayed.empty? || @trick_points.zero? && state.points_left.zero?)
    end

    def winning_play(trick)
      leader, high = trick.first
      led = high % 4
      trick.drop(1).each { |player, card| leader, high = player, card if card % 4 == led && card > high }
      [leader, high]
    end

    def void?(state, player, suit)
      (state.voids[player] & (1 << suit)) != 0
    end

    # Hypergeometric chance that a draw contains none of the target cards.
    # Memoization is decision-local and depends only on counts, not identities.
    def absence(population, targets, draws)
      return 1.0 if targets.zero? || draws.zero?
      return 0.0 if draws > population - targets

      key = (population * 64 + targets) * 32 + draws
      @absence[key] ||= begin
        large, small = targets >= draws ? [targets, draws] : [draws, targets]
        small.times.reduce(1.0) { |value, index| value * (1.0 - large.fdiv(population - index)) }
      end
    end

    def utilities(state, finish_priority: false)
      raw = state.raw.each_with_index.to_h { |value, player| [player, value] }
      additions = Scoring.additions(raw, round: @number, all_or_nothing: @all_or_nothing)
      scores = @scores.each_with_index.map { |score, player| score + additions.fetch(player) }
      sum = scores.sum
      scores.each_with_index.map do |score, player|
        rivals = scores.each_index.reject { |other| other == player }.map { |other| scores[other] }
        margin = (sum - score).fdiv(@size - 1) - score + 0.25 * (rivals.min - score)
        next margin unless @number == 6

        beaten = rivals.sum { |other| other > score ? 1.0 : (other == score ? 0.5 : 0.0) }
        next margin + 80 * beaten / rivals.size unless finish_priority

        # A large margin over the trailing players must not outweigh a
        # loss to the leader. On the last deal compare the actual finish
        # first, with a bounded margin to distinguish similar outcomes.
        best_rival = rivals.min
        finish = score < best_rival ? 280 : (score == best_rival ? 140 : 0)
        finish + 70 * beaten / rivals.size + 30 * margin.fdiv(100 + margin.abs)
      end
    end

    private

    def ids(cards)
      cards.map { |card| CARD_IDS.fetch(card) }
    end

    def build_state(observation, deck)
      hands = Array.new(@size) { [] }
      hands[@root] = ids(observation.fetch('hand'))
      unplayed = deck - ids(observation.fetch('played_cards'))
      voids = Information.void_suits(observation)
      State.new(hands: hands, unplayed: unplayed, turn: @root,
        counts: @players.map { |player| observation.fetch('counts').fetch(player) },
        raw: @players.map { |player| observation.fetch('captured_points').fetch(player) },
        trick: observation.fetch('trick').map { |player, card| [@seats.fetch(player), CARD_IDS.fetch(card)] },
        voids: @players.map { |player| voids.fetch(player).sum { |suit| 1 << SUIT_IDS.fetch(suit) } },
        points_left: unplayed.sum { |card| @points[card] })
    end

    def world(assignment)
      state = @initial.branch
      assignment.each { |player, cards| state.hands[player] = cards.sort }
      state
    end
  end
end
