require 'digest'
require_relative 'hidden_card_deals'
require_relative 'game_tree_search'
require_relative 'participant_decision_events'

# Bounded common-sample continuation for trick games. Games supply their real
# legal-card, winner and point functions; this helper owns no game rules.
class GameRoomTrickForecast
  attr_reader :stats

  def self.public_plays(events, players, decoded)
    indices = players.each_with_index.to_h { |player, seat| [player.to_s.downcase, seat] }
    events.reverse.take_while { |event| !%w[deal private_deal].include?(event['action']) }.reverse.filter_map do |event|
      next unless event['action'] == 'play' && decoded.key?(event['value'])
      seat = indices[event['actor'].to_s.downcase]
      [seat, decoded.fetch(event['value'])] if seat
    end
  end

  def initialize(view, legal:, winner:, points:, policy:, voided:, evaluate: nil)
    @view, @legal, @winner, @points, @policy, @voided = view, legal, winner, points, policy, voided
    @seat, @units = view.values_at(:seat, :units)
    @evaluate = evaluate
    @budget = GameRoomBots::SearchBudget.new(limit: 4_096)
    @forecasts = {}
  end

  def choose(cards, fallback)
    # Long-deal greedy continuations are an unreliable substitute for knowing
    # an opponent's policy. Concentrate this inexpensive lookahead on the
    # constrained endgame instead of overriding sound opening heuristics.
    return fallback if @view.fetch(:hand).size > 4
    worlds = possible_hands
    return fallback if worlds.empty? || cards.size <= 1
    candidates = ([fallback] + cards).uniq
    reference = worlds.map { |hands| forecast(hands, fallback) }
    choice = candidates.max_by do |card|
      values = card == fallback ? reference : worlds.map { |hands| forecast(hands, card) }
      gains = values.zip(reference).map { |value, base| value - base }
      next [-Float::INFINITY, 0] if gains.min < -1e-9
      mean = gains.sum.fdiv(gains.size)
      error = Math.sqrt(gains.sum { |gain| (gain - mean)**2 }.fdiv([gains.size * (gains.size - 1), 1].max))
      [mean - 1.5 * error, card == fallback ? 1 : 0]
    end
    @stats = {worlds: worlds.size, candidates: candidates.size, nodes: @budget.nodes}
    choice
  end

  private

  def possible_hands
    played, own = @view.values_at(:played, :hand)
    voids = Array.new(@units.size) { [] }
    played.each_slice(@units.size) do |trick|
      lead = trick.find { |_, card| card.first != :excuse }&.last&.first
      trick.each { |seat, card| voids[seat] |= [lead] if lead && @voided.call(lead, card) }
    end
    dead = @view.fetch(:dead, [])
    pool = @view.fetch(:deck) - (played.map(&:last) + own + dead)
    players = (0...@units.size).to_a - [@seat]
    counts = players.to_h { |seat| [seat, @view[:counts].fetch(seat)] }
    if @view.fetch(:reserve, 0).positive?
      players << @units.size
      counts[@units.size] = @view[:reserve]
      voids << []
    end
    return [] unless pool.size == counts.values.sum
    seed = Digest::SHA256.hexdigest(Marshal.dump([own.sort, played, @view[:trick], @units, dead])).to_i(16)
    random = Random.new(seed)
    result = []
    48.times do
      hands = GameRoomHiddenCardDeals.assign(pool, players, counts, random) { |seat, card| !voids[seat].include?(card.first) }
      next unless hands
      result << [Array.new(@units.size) { |seat| seat == @seat ? own.dup : hands.fetch(seat) }, hands.fetch(@units.size, dead)]
      break if result.size == 12
    end
    result
  end

  def forecast(source, first)
    key = [source, first]
    return @forecasts[key] if @forecasts.key?(key)
    hands, reserve = source
    hands, trick = hands.map(&:dup), @view[:trick].map(&:dup)
    seat, card, value = @seat, first, 0.0
    completed = []
    until hands.all?(&:empty?)
      @budget.visit!
      choices = @legal.call(hands[seat], trick, seat)
      card ||= @policy.call(choices, trick, seat, hands[seat])
      hands[seat].delete(card)
      trick << [seat, card]
      card = nil
      if trick.size == @units.size
        winner = trick.fetch(@winner.call(trick.map(&:last))).first
        points = @points.call(trick.map(&:last), hands.all?(&:empty?))
        value += @units[winner] == @units[@seat] ? points : -points
        completed << [trick, winner, hands.all?(&:empty?)]
        seat = winner
        trick = []
      else
        seat = (seat + 1) % @units.size
      end
    end
    @forecasts[key] = @evaluate ? @evaluate.call(completed, reserve) : value
  end
end
