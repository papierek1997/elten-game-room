# frozen_string_literal: true

require 'json'
require 'open3'
require 'optparse'
require_relative '../games/bridge'

# Re-run a trusted local revision against the current bidder, with the same
# cards, dealer, vulnerability, opponent and card-play policy at both tables.
module BridgeBiddingBenchmark
  R = GameRoomGames::BridgeRules
  STRATEGY = GameRoomGames::BridgeStrategy
  module_function

  def baseline(ref)
    root = File.expand_path('..', __dir__)
    command = ['git', '-c', "safe.directory=#{root}"]
    commit, status = Open3.capture2e(*command, 'rev-parse', '--verify', '--end-of-options', "#{ref}^{commit}", chdir: root)
    raise "Unknown baseline: #{commit}" unless status.success?
    commit = commit.strip
    source, status = Open3.capture2e(*command, 'show', "#{commit}:games/bridge/bot.rb", chdir: root)
    raise source unless status.success?
    namespace = Module.new
    games = Module.new
    games.const_set(:BridgeRules, R)
    namespace.const_set(:GameRoomGames, games)
    # Use the old strategy in its own namespace, without its play dependency.
    body = source[/^module GameRoomGames\n.*\z/m]
    raise 'Unsupported baseline strategy source' unless body
    namespace.module_eval(body, "bridge-bot-#{commit}.rb")
    [commit, games.const_get(:BridgeStrategy).const_get(:Bidding)]
  end

  def auction(hands, dealer, vulnerability, bidders)
    calls, seat = [], dealer
    until R.auction_finished?(calls)
      view = {'seat'=>seat, 'hand'=>hands.fetch(seat), 'calls'=>calls, 'dealer'=>dealer, 'vulnerability'=>vulnerability}
      call = bidders.fetch(R.side_of(seat)).new(view).call
      raise "Illegal bid #{call.inspect} after #{calls.inspect}" unless R.legal_calls(calls, seat).include?(call)
      calls << [seat, call]
      seat = R.next_seat(seat)
    end
    R.final_contract(calls)
  end

  def tricks(hands, contract, vulnerability, planner:)
    cards = hands.map(&:dup)
    played, trick, won = [], [], [0, 0]
    dummy = R.partner_of(contract.declarer)
    seat = R.next_seat(contract.declarer)
    # The evaluator gets the contract but not the bids. Changing only the
    # auction path to the same contract cannot affect the play or the score.
    view = {'contract'=>contract.to_h.transform_keys(&:to_s), 'vulnerability'=>vulnerability, 'calls'=>[], 'played'=>played,
      'trick'=>trick, 'tricks_won'=>won}
    R::DECK.length.times do
      actor = seat == dummy ? contract.declarer : seat
      legal = R.legal_cards(cards.fetch(seat), trick)
      view.merge!('seat'=>actor, 'seat_to_play'=>seat, 'hand'=>cards.fetch(actor),
        'dummy'=>played.empty? && trick.empty? ? nil : cards.fetch(dummy))
      card = legal.first
      if legal.size > 1
        card = STRATEGY::Play.new(view).card(legal)
        card = GameRoomGames::BridgePlayPlanner.new(view).choose(legal, card) if planner
      end
      raise 'Evaluator chose an illegal card' unless legal.include?(card)
      cards.fetch(seat).delete(card)
      trick << [seat, card]
      if trick.size == 4
        seat = R.trick_winner(trick, contract.strain)
        won[R.side_of(seat)] += 1
        played.concat(trick)
        trick.clear
      else
        seat = R.next_seat(seat)
      end
    end
    won.fetch(contract.side)
  end

  def score(hands, contract, vulnerability, cache, planner:)
    return [0, 0] unless contract
    key = planner ? contract : [contract.declarer, contract.strain]
    count = cache[key] ||= tricks(hands, contract, vulnerability, planner: planner)
    points = R.duplicate_score(contract, count, vulnerable: R.vulnerable?(vulnerability, contract.side))
    [contract.side.zero? ? points : -points, count]
  end

  def count_contract(summary, contract, count, side)
    return unless contract&.side == side
    summary[:contracts] += 1
    summary[:defeated] += 1 if count < contract.tricks_needed
    summary[:undertricks] += [contract.tricks_needed - count, 0].max
    if R.trick_value(contract.strain, contract.level) >= 100
      summary[:games] += 1
      summary[:games_made] += 1 if count >= contract.tricks_needed
    end
  end

  def run(baseline, seed:, boards:, planner: false)
    old, new = Hash.new(0), Hash.new(0)
    better, worse, equal = 0, 0, 0
    points = 0
    imp_deltas = (1..boards).map do |board|
      dealer, vulnerability = R.board_dealer(board), R.board_vulnerability(board).to_s
      hands = R.deal("bidding-benchmark:#{seed}:#{board}", dealer)
      cache = {}
      reference = auction(hands, dealer, vulnerability, [baseline, baseline])
      base_score, base_tricks = score(hands, reference, vulnerability, cache, planner: planner)
      [0, 1].sum do |side|
        bidders = [baseline, baseline]
        bidders[side] = STRATEGY::Bidding
        contract = auction(hands, dealer, vulnerability, bidders)
        new_score, new_tricks = score(hands, contract, vulnerability, cache, planner: planner)
        count_contract(old, reference, base_tricks, side)
        count_contract(new, contract, new_tricks, side)
        change = (new_score - base_score) * (side.zero? ? 1 : -1)
        better += 1 if change.positive?
        worse += 1 if change.negative?
        equal += 1 if change.zero?
        points += change
        R.imps(change)
      end / 2.0
    end
    mean = imp_deltas.sum / boards
    standard_error = Math.sqrt(imp_deltas.sum { |delta| (delta - mean)**2 } / (boards * (boards - 1)))
    {seed: seed, boards: boards, play: planner ? 'planner' : 'heuristic',
      paired_comparisons: boards * 2, better: better, worse: worse, equal: equal,
      old: old, new: new, points_per_comparison: (points.fdiv(boards * 2)).round(3),
      imps_per_comparison: mean.round(3), approx_95_percent_interval: [mean - 1.96 * standard_error, mean + 1.96 * standard_error].map { |x| x.round(3) }}
  end
end

if $PROGRAM_NAME == __FILE__
  options = {seed: 263, boards: 1000}
  OptionParser.new do |parser|
    parser.banner = 'Usage: ruby tools/benchmark-bridge-bidding.rb [--seed N] [--boards N] [--planner] TRUSTED_BASELINE_REF'
    parser.on('--seed N', Integer) { |value| options[:seed] = value }
    parser.on('--boards N', Integer) { |value| options[:boards] = value }
    parser.on('--planner', 'Score with the full card-play planner (slower)') { options[:planner] = true }
  end.parse!
  abort 'Specify one trusted Git revision and at least two boards' unless ARGV.size == 1 && options[:boards] >= 2
  commit, baseline = BridgeBiddingBenchmark.baseline(ARGV.first)
  puts JSON.pretty_generate(BridgeBiddingBenchmark.run(baseline, **options).merge(baseline: commit))
end
