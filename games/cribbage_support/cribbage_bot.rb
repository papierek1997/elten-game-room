require_relative "cribbage_scoring"
require_relative "../../lib/game_random"

module GameRoomGames
  module CribbageBot
    DECK = (1..13).to_a.product(%i[clubs diamonds hearts spades]).map(&:freeze).freeze
    module_function

    def discard(hand, dealer:)
      unseen = DECK - hand
      # Common, conditioned samples for every discard. Exclude our complete
      # six-card hand, not just the retained cards, from the hypothetical crib.
      seed = hand.sort_by { |rank, suit| [rank, suit.to_s] }.reduce(17) { |value, card| value * 53 + DECK.index(card) }
      random = Random.new(seed)
      samples = Array.new(192) do
        pool = unseen.dup
        Array.new(3) { pool.delete_at(random.rand(pool.size)) }
      end
      hand.combination(2).max_by do |cards|
        kept = hand - cards
        expected_hand = unseen.sum { |starter| CribbageScoring.hand(kept, starter) }.fdiv(unseen.size)
        expected_crib = samples.sum { |a, b, starter| CribbageScoring.hand(cards + [a, b], starter, crib: true) }.fdiv(samples.size)
        Thread.pass
        expected_hand + (dealer ? 1 : -1) * expected_crib
      end
    end

    def play(legal, sequence, hand: legal, seen: [], opponent_count: 4, points_needed: 121, opponent_points_needed: 121)
      unknown = DECK - (hand + seen).uniq
      # Common hypothetical hands for all candidate plays. An opponent chooses
      # a reply from their hand; they do not draw one uniformly random card.
      size = [opponent_count,unknown.size].min
      seed = (hand+seen).sort_by { |rank,suit|[rank,suit.to_s] }.reduce(31) { |v,c| (v*53+DECK.index(c)) % 2_147_483_647 }
      random = Random.new(seed)
      worlds = Array.new(96) { GameRoomRandom.shuffle(unknown,random:random).first(size) }
      legal.max_by do |card|
        ranks = sequence + [card.first]
        total = ranks.sum { |rank| [rank, 10].min }
        immediate = CribbageScoring.pegging(ranks)
        next [10_000 + immediate, 0, 0] if immediate >= points_needed
        # Expected replies, not the actual concealed cards. Continue with our
        # best legal answer, so creating a run/pair for ourselves has value.
        future = worlds.sum do |world|
          replies = total < 31 ? world.filter_map do |reply|
            next_ranks = ranks + [reply.first]
            loss = CribbageScoring.pegging(next_ranks)
            next unless loss
            next -1_000.0 if loss >= opponent_points_needed
            follow = (hand - [card]).filter_map { |own| CribbageScoring.pegging(next_ranks + [own.first]) }.max.to_i
            follow * 0.7 - loss
          end : []
          replies.min || 0.0
        end.fdiv(worlds.size)
        Thread.pass
        [immediate + future, total == 5 || total == 21 ? -1 : 0, -card.first]
      end
    end
  end
end
