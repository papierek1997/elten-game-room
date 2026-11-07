require_relative 'game_bots'
require_relative 'bouillabaisse/round'
require_relative 'bouillabaisse/policy'

module GameRoomGames
  class BouillabaisseStrategy
    include GameRoomBots::ReplayOnlyStrategy

    WORLD_LIMIT = 6
    ROOT_LIMIT = 8
    TAIL_CARDS = 8
    TAIL_NODES = 1200

    def choose(actions:, observation:, **_extra)
      return actions.first if actions.size <= 1

      round = BouillabaissePlanning::Round.new(observation)
      by_card = actions.to_h { |action| [BouillabaissePlanning::Round::CARD_IDS.fetch(action.fetch('card')), action] }
      policy = BouillabaissePlanning::Policy.new(round, round.initial)
      if round.number == 6 && round.initial.unplayed.size <= TAIL_CARDS && (forced = round.forced_world)
        card = catch(:bouillabaisse_tail_budget) do
          by_card.keys.max_by do |choice|
            branch = forced.branch
            round.play(branch, choice)
            [solve_tail(round, branch, [TAIL_NODES], finish_priority: true).fetch(round.root), policy.score(choice)]
          end
        end
        return by_card.fetch(card) if card
      end
      cards = policy.candidates(by_card.keys)
      return by_card.fetch(cards.first) if cards.size == 1

      prior = cards.to_h { |card| [card, policy.score(card)] }
      baseline = cards.max_by { |card| [prior.fetch(card), -card] }
      worlds = round.worlds(WORLD_LIMIT)
      return by_card.fetch(baseline) if worlds.empty?

      samples = shortlist(cards, prior).to_h do |card|
        values = worlds.map do |world|
          branch = world.branch
          round.play(branch, card)
          estimate(round, branch, styles: round.size == 2 ? 2 : 1)
        end
        [card, values]
      end
      reference = samples.fetch(baseline)
      best = samples.keys.max_by do |card|
        adjustment = [(prior.fetch(card) - prior.fetch(baseline)) * 0.05, -2.0].max
        [reliable_gain(samples.fetch(card), reference) + adjustment, prior.fetch(card), -card]
      end
      by_card.fetch(best)
    end

    private

    # Compare the same worlds, not independent sample averages. A lucky
    # sweep in one possible deal is weak evidence against a sound tactic.
    def reliable_gain(values, reference)
      gains = values.zip(reference).map { |value, baseline| value - baseline }
      mean = gains.sum.fdiv(gains.size)
      return mean if gains.size <= 1

      error = Math.sqrt(gains.sum { |gain| (gain - mean)**2 }.fdiv(gains.size * (gains.size - 1)))
      mean - 0.55 * error
    end

    def shortlist(cards, prior)
      ordered = cards.sort_by { |card| [-prior.fetch(card), card] }
      return ordered if ordered.size <= ROOT_LIMIT

      (ordered.first(4) + ordered.uniq { |card| card % 4 } + ordered).uniq.first(ROOT_LIMIT)
    end

    def estimate(round, state, styles:)
      if state.unplayed.size <= TAIL_CARDS
        solved = catch(:bouillabaisse_tail_budget) { solve_tail(round, state, [TAIL_NODES]) }
        return solved.fetch(round.root) if solved
      end
      styles.times.sum do |style|
        branch = styles == 1 ? state : state.branch
        until round.finished?(branch)
          legal = round.legal(branch)
          card = legal.size == 1 ? legal.first : BouillabaissePlanning::Policy.new(round, branch, style: style).choose(legal)
          round.play(branch, card)
        end
        round.utilities(branch).fetch(round.root)
      end.fdiv(styles)
    end

    # A short search inside a *sampled* deal, not access to a real hand. Each
    # simulated seat maximizes its own final utility. If the node budget is
    # exhausted, discard the partial result and play a bounded rollout.
    def solve_tail(round, state, budget, finish_priority: false)
      budget[0] -= 1
      throw :bouillabaisse_tail_budget if budget[0].negative?
      return round.utilities(state, finish_priority: finish_priority) if round.finished?(state)

      round.legal(state).map do |card|
        branch = state.branch
        round.play(branch, card)
        solve_tail(round, branch, budget, finish_priority: finish_priority)
      end.max_by { |values| values.fetch(state.turn) }
    end
  end
end
