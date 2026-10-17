require "digest"

module GameRoomGames
  # Pure contract bridge rules. Nothing here knows about participants, UI or
  # events: seats are 0..3 (North, East, South, West), side 0 is North-South
  # and side 1 is East-West. The game class maps players to seats.
  module BridgeRules
    SEATS = 4
    STRAINS = %w[C D H S N].freeze
    SUITS = %w[C D H S].freeze
    RANKS = %w[2 3 4 5 6 7 8 9 T J Q K A].freeze
    HONOR_POINTS = { "A" => 4, "K" => 3, "Q" => 2, "J" => 1 }.freeze
    PASS = "P".freeze
    DOUBLE = "X".freeze
    REDOUBLE = "XX".freeze
    BIDS = (1..7).flat_map { |level| STRAINS.map { |strain| "#{level}#{strain}".freeze } }.freeze
    CALLS = ([PASS, DOUBLE, REDOUBLE] + BIDS).freeze
    DECK = SUITS.flat_map { |suit| RANKS.map { |rank| "#{rank}#{suit}".freeze } }.freeze

    # Upper bounds of each IMP band from the WBF scale; 4000 or more is 24.
    IMP_BOUNDS = [10, 40, 80, 120, 160, 210, 260, 310, 360, 420, 490, 590, 740,
      890, 1090, 1290, 1490, 1740, 1990, 2240, 2490, 2990, 3490, 3990].freeze

    # Duplicate boards repeat this vulnerability pattern every 16 boards.
    BOARD_VULNERABILITY = %i[none ns ew both ns ew both none ew both none ns both none ns ew].freeze

    # Single-table reference score for the side holding more high-card points,
    # indexed by its combined HCP: [not vulnerable, vulnerable]. It estimates
    # the average result such hands earn at a duplicate table; a missing fit
    # or a distributional hand can of course score very differently.
    DATUM_BY_HCP = [
      [20, [0, 0]], [21, [50, 50]], [22, [90, 90]], [23, [110, 110]], [24, [140, 140]],
      [25, [250, 350]], [26, [400, 600]], [27, [420, 620]], [28, [430, 630]],
      [29, [440, 650]], [30, [460, 660]], [31, [700, 1000]], [32, [920, 1370]],
      [33, [980, 1430]], [34, [1000, 1450]], [35, [1100, 1600]], [36, [1250, 1850]],
      [37, [1500, 2200]]
    ].freeze

    Contract = Struct.new(:level, :strain, :doubled, :declarer, keyword_init: true) do
      def side
        declarer % 2
      end

      def tricks_needed
        6 + level
      end

      def text
        "#{level}#{strain}#{'X' * doubled}"
      end
    end

    module_function

    def side_of(seat)
      seat.to_i % 2
    end

    def partner_of(seat)
      (seat.to_i + 2) % SEATS
    end

    def next_seat(seat)
      (seat.to_i + 1) % SEATS
    end

    def card_rank(card)
      card.to_s[0]
    end

    def card_suit(card)
      card.to_s[1]
    end

    def rank_index(card)
      RANKS.index(card_rank(card)).to_i
    end

    def bid?(call)
      BIDS.include?(call.to_s)
    end

    def bid_level(call)
      call.to_s[0].to_i
    end

    def bid_strain(call)
      call.to_s[1]
    end

    def bid_index(call)
      BIDS.index(call.to_s)
    end

    def high_card_points(cards)
      cards.to_a.sum { |card| HONOR_POINTS.fetch(card_rank(card), 0) }
    end

    # The SHA256 order keeps every client's deal identical for the same seed,
    # and is independent of Ruby's (host-overridden) Array#shuffle.
    def deal(seed, dealer)
      order = DECK.sort_by { |card| Digest::SHA256.hexdigest("bridge\0#{seed}\0#{card}") }
      hands = Array.new(SEATS) { [] }
      order.each_with_index { |card, index| hands[(dealer.to_i + 1 + index) % SEATS] << card }
      hands
    end

    # Auction analysis --------------------------------------------------------

    # calls: array of [seat, call] in the order they were made.
    def last_bid(calls)
      calls.reverse_each.find { |_seat, call| bid?(call) }
    end

    def last_non_pass(calls)
      calls.reverse_each.find { |_seat, call| call != PASS }
    end

    def auction_finished?(calls)
      return false if calls.length < 4
      return calls.all? { |_seat, call| call == PASS } if last_bid(calls) == nil

      calls.last(3).all? { |_seat, call| call == PASS }
    end

    def passed_out?(calls)
      calls.length == 4 && calls.all? { |_seat, call| call == PASS }
    end

    def legal_calls(calls, seat)
      return [] if auction_finished?(calls)

      legal = [PASS]
      previous = last_non_pass(calls)
      if previous != nil && side_of(previous[0]) != side_of(seat)
        legal << DOUBLE if bid?(previous[1])
        legal << REDOUBLE if previous[1] == DOUBLE
      end
      highest = last_bid(calls)
      start = highest == nil ? 0 : bid_index(highest[1]) + 1
      legal + BIDS.drop(start)
    end

    def final_contract(calls)
      return nil if !auction_finished?(calls) || passed_out?(calls)

      bid_seat, bid = last_bid(calls)
      strain = bid_strain(bid)
      side = side_of(bid_seat)
      declarer = calls.find { |seat, call| side_of(seat) == side && bid?(call) && bid_strain(call) == strain }[0]
      after_bid = calls.drop(calls.rindex { |_seat, call| call == bid } + 1)
      doubled = after_bid.count { |_seat, call| [DOUBLE, REDOUBLE].include?(call) }
      Contract.new(level: bid_level(bid), strain: strain, doubled: [doubled, 2].min, declarer: declarer)
    end

    # Card play ----------------------------------------------------------------

    def legal_cards(hand, trick)
      return hand.to_a.dup if trick.empty?

      led = card_suit(trick.first[1])
      following = hand.select { |card| card_suit(card) == led }
      following.empty? ? hand.to_a.dup : following
    end

    # trick: array of [seat, card]. Returns the winning seat.
    def trick_winner(trick, strain)
      led = card_suit(trick.first[1])
      trumps = trick.select { |_seat, card| strain != "N" && card_suit(card) == strain }
      candidates = trumps.empty? ? trick.select { |_seat, card| card_suit(card) == led } : trumps
      candidates.max_by { |_seat, card| rank_index(card) }[0]
    end

    # Scoring ------------------------------------------------------------------

    ContractScore = Struct.new(:made, :trick_score, :overtricks, :undertricks, :insult,
      :slam, :penalty, keyword_init: true) do
      # Points other than the trick score, from the declaring side's point of view.
      def bonus_total
        overtricks + insult + slam
      end
    end

    def trick_value(strain, count)
      return 0 if count <= 0
      return 40 + 30 * (count - 1) if strain == "N"

      (["C", "D"].include?(strain) ? 20 : 30) * count
    end

    # Scores one played contract without game/partscore/rubber bonuses, which
    # depend on whether the table plays rubber or duplicate.
    def contract_score(contract, tricks, vulnerable:)
      multiplier = [1, 2, 4].fetch(contract.doubled)
      if tricks < contract.tricks_needed
        down = contract.tricks_needed - tricks
        return ContractScore.new(made: false, trick_score: 0, overtricks: 0, undertricks: down,
          insult: 0, slam: 0, penalty: undertrick_penalty(down, contract.doubled, vulnerable))
      end

      extra = tricks - contract.tricks_needed
      overtricks = if contract.doubled == 0
        trick_value(contract.strain, contract.level + extra) - trick_value(contract.strain, contract.level)
      else
        extra * (vulnerable ? 200 : 100) * contract.doubled
      end
      slam = case contract.level
      when 6 then vulnerable ? 750 : 500
      when 7 then vulnerable ? 1500 : 1000
      else 0
      end
      ContractScore.new(made: true, trick_score: trick_value(contract.strain, contract.level) * multiplier,
        overtricks: overtricks, undertricks: 0, insult: [0, 50, 100].fetch(contract.doubled), slam: slam, penalty: 0)
    end

    def undertrick_penalty(down, doubled, vulnerable)
      return down * (vulnerable ? 100 : 50) if doubled == 0

      doubled_penalty = (1..down).sum do |index|
        if vulnerable
          index == 1 ? 200 : 300
        else
          case index
          when 1 then 100
          when 2, 3 then 200
          else 300
          end
        end
      end
      doubled_penalty * (doubled == 2 ? 2 : 1)
    end

    # Duplicate score of one board for the declaring side (negative when set).
    def duplicate_score(contract, tricks, vulnerable:)
      score = contract_score(contract, tricks, vulnerable: vulnerable)
      return -score.penalty if !score.made

      game_bonus = if score.trick_score >= 100
        vulnerable ? 500 : 300
      else
        50
      end
      score.trick_score + score.bonus_total + game_bonus
    end

    def imps(difference)
      size = difference.to_i.abs
      value = IMP_BOUNDS.index { |bound| size <= bound } || IMP_BOUNDS.length
      difference.to_i < 0 ? -value : value
    end

    def board_vulnerability(board)
      BOARD_VULNERABILITY.fetch((board.to_i - 1) % 16)
    end

    def board_dealer(board)
      (board.to_i - 1) % SEATS
    end

    def vulnerable?(vulnerability, side)
      case vulnerability.to_sym
      when :both then true
      when :ns then side.to_i == 0
      when :ew then side.to_i == 1
      else false
      end
    end

    # The reference result for North-South at a single table.
    def datum(hands, vulnerability)
      ns = high_card_points(hands[0]) + high_card_points(hands[2])
      ew = 40 - ns
      return 0 if ns == ew

      side = ns > ew ? 0 : 1
      points = [ns, ew].max
      row = DATUM_BY_HCP.reverse.find { |minimum, _values| points >= minimum }
      value = row == nil ? 0 : row[1][vulnerable?(vulnerability, side) ? 1 : 0]
      side == 0 ? value : -value
    end

    def new_rubber
      { above: [0, 0], below: [0, 0], game_line: [0, 0], games: [0, 0], rubber_bonus: nil }
    end

    def rubber_vulnerable?(rubber, side)
      rubber[:games][side] >= 1
    end

    def rubber_finished?(rubber)
      rubber[:games].max >= 2
    end

    def rubber_totals(rubber)
      [0, 1].map { |side| rubber[:above][side] + rubber[:below][side] }
    end

    # Records one played contract in a rubber. Returns the entries that were
    # written as [side, :below/:above, points, reason] for announcements.
    def score_rubber_deal(rubber, contract, tricks, hands:, honors: true)
      side = contract.side
      vulnerable = rubber_vulnerable?(rubber, side)
      score = contract_score(contract, tricks, vulnerable: vulnerable)
      entries = []
      if score.made
        entries << [side, :below, score.trick_score, :contract]
        entries << [side, :above, score.overtricks, :overtricks] if score.overtricks > 0
        entries << [side, :above, score.insult, :insult] if score.insult > 0
        entries << [side, :above, score.slam, :slam] if score.slam > 0
      else
        entries << [1 - side, :above, score.penalty, :undertricks]
      end
      if honors
        held = honors(hands, contract.strain)
        entries << [held[0], :above, held[1], :honors] if held != nil
      end
      entries.each do |entry_side, line, points, _reason|
        line == :below ? rubber[:below][entry_side] += points : rubber[:above][entry_side] += points
      end
      if score.made
        rubber[:game_line][side] += score.trick_score
        if rubber[:game_line][side] >= 100
          rubber[:games][side] += 1
          rubber[:game_line] = [0, 0]
          entries << [side, :game, 0, :game]
        end
      end
      if rubber_finished?(rubber)
        winner = rubber[:games].index(2)
        bonus = rubber[:games][1 - winner] == 0 ? 700 : 500
        rubber[:above][winner] += bonus
        rubber[:rubber_bonus] = [winner, bonus]
        entries << [winner, :above, bonus, :rubber]
      end
      entries
    end

    # Rubber honours: 4 or 5 of the top trumps in one hand, or all four aces in
    # one hand at no trump. They belong to the side holding them.
    def honors(hands, strain)
      hands.each_with_index do |hand, seat|
        if strain == "N"
          return [side_of(seat), 150] if hand.count { |card| card_rank(card) == "A" } == 4
        else
          count = hand.count { |card| card_suit(card) == strain && %w[A K Q J T].include?(card_rank(card)) }
          return [side_of(seat), 150] if count == 5
          return [side_of(seat), 100] if count == 4
        end
      end
      nil
    end
  end
end
