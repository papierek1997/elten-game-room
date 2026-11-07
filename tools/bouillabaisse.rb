require 'json'
require 'optparse'
require_relative '../games/bouillabaisse'
require_relative 'training/match_runner'

module GameRoomBouillabaisseBenchmark
  # Historical comparison policy; never loaded by the player runtime.
  class RankOnly
    def choose(actions:, observation:)
      trick = observation.fetch('trick')
      ranks = GameRoomGames::CardGame::CARD_RANKS
      winning = trick.empty? ? nil : trick.select { |_, card| card[1] == trick.first.last[1] }.
        max_by { |_, card| ranks.index(card[0]) }.last
      losing = actions.select do |action|
        card = action.fetch('card')
        winning && (card[1] != winning[1] || ranks.index(card[0]) < ranks.index(winning[0]))
      end
      gather = observation['round'] == 6
      candidates = gather || losing.empty? ? actions : losing
      candidates.min_by do |action|
        rank = ranks.index(action.fetch('card')[0])
        gather || !losing.empty? ? -rank : rank
      end
    end
  end

  class TacticsOnly
    def choose(actions:, observation:)
      return actions.first if actions.size <= 1

      round = BouillabaissePlanning::Round.new(observation)
      policy = BouillabaissePlanning::Policy.new(round, round.initial)
      choices = actions.to_h { |action| [BouillabaissePlanning::Round::CARD_IDS.fetch(action.fetch('card')), action] }
      choices.fetch(policy.choose(policy.candidates(choices.keys)))
    end
  end

  class Timed
    attr_reader :milliseconds

    def initialize(strategy)
      @strategy = strategy
      @milliseconds = []
    end

    def choose(actions:, observation:)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      choice = @strategy.choose(actions: actions, observation: observation)
      @milliseconds << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000 if actions.size > 1
      choice
    end
  end

  module_function

  def run(arguments)
    options = {players: [2, 3, 4], seed: 8_020_000, seeds: 4, reference: 'rank', opponents: 'rank', output: nil}
    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: ruby tools/bouillabaisse.rb [options]'
      opts.on('--players LIST', Array) { |value| options[:players] = value.map { |item| Integer(item, 10) }.uniq }
      opts.on('--seed N', Integer) { |value| options[:seed] = value }
      opts.on('--seeds N', Integer) { |value| options[:seeds] = value }
      opts.on('--reference POLICY', %w[rank tactics]) { |value| options[:reference] = value }
      opts.on('--opponents POLICY', %w[rank tactics mixed]) { |value| options[:opponents] = value }
      opts.on('--output NEW_FILE') { |value| options[:output] = value }
    end
    remaining = parser.parse(arguments)
    raise ArgumentError, 'Unexpected arguments' unless remaining.empty?
    raise ArgumentError, 'Choose 2–8 players and 1–100 seeds' unless
      !options[:players].empty? && options[:players].all? { |count| count.between?(2, 8) } && options[:seeds].between?(1, 100)
    raise ArgumentError, 'Output already exists' if options[:output] && File.exist?(options[:output])

    groups = options[:players].product([true, false]).map do |count, all_or_nothing|
      result = compare(count, all_or_nothing, options)
      warn "#{count} seats, all or nothing #{all_or_nothing}: #{result[:pairs]} pairs, margin gain #{result[:paired_margin_gain]}"
      result
    end
    report = {settings: options.except(:output), groups: groups}
    json = JSON.pretty_generate(report) + "\n"
    options[:output] ? File.write(options[:output], json, mode: 'wx') : puts(json)
  end

  def compare(count, all_or_nothing, options)
    players = Array.new(count) { |index| "Seat#{index + 1}" }
    reference = Timed.new(policy(options[:reference]))
    candidate = Timed.new(GameRoomGames::BouillabaisseStrategy.new)
    data = (options[:seed]...(options[:seed] + options[:seeds])).flat_map do |seed|
      players.map do |actor|
        opponents = (players - [actor]).each_with_index.to_h do |name, index|
          kind = options[:opponents] == 'mixed' ? (index.even? ? 'rank' : 'tactics') : options[:opponents]
          [name, policy(kind)]
        end
        before = match(players, opponents.merge(actor => reference), seed, all_or_nothing)
        after = match(players, opponents.merge(actor => candidate), seed, all_or_nothing)
        deals = ->(result) { result.events.select { |event| event['action'] == 'deal' }.map { |event| event['value'] } }
        raise 'Paired matches used different deals' unless deals.call(before) == deals.call(after) && deals.call(before).size == 6

        [measure(before, actor, all_or_nothing), measure(after, actor, all_or_nothing)]
      end
    end
    old, new = data.transpose
    {players: count, all_or_nothing: all_or_nothing, pairs: data.size,
      reference: summarize(old, reference.milliseconds), planner: summarize(new, candidate.milliseconds),
      paired_margin_gain: mean(data.map { |a, b| b[:margin] - a[:margin] }),
      paired_margin_improved: data.count { |a, b| b[:margin] > a[:margin] },
      paired_margin_unchanged: data.count { |a, b| b[:margin] == a[:margin] }}
  end

  def match(players, strategies, seed, all_or_nothing)
    game = GameRoomGames::Bouillabaisse.new
    result = GameRoomSimulation::MatchRunner.new(game: game, players: players, strategies: strategies,
      options: {'all_or_nothing'=>all_or_nothing, 'bot_delay'=>0}, max_actions: 312).run(seed: seed)
    raise "Unfinished match: #{result.reason}" unless result.finished?
    result
  end

  def measure(result, actor, all_or_nothing)
    game = GameRoomGames::Bouillabaisse.new
    repository = GameRoomSimulation::Repository.new(result.players)
    session = {'options'=>JSON.generate(game.normalize_options('all_or_nothing'=>all_or_nothing, 'bot_delay'=>0))}
    replay = game.replay(session, [], repository)
    deltas = []
    previous = 0
    result.events.each do |event|
      game.incremental_replay(replay, session, [event], repository)
      next unless [:round_complete, :finished].include?(replay.state[:phase])

      current = replay.state[:scores].fetch(actor)
      deltas << current - previous
      previous = current
    end
    scores = result.final_state.fetch(:scores)
    raise 'Scoring replay diverged' unless deltas.size == 6 && scores == replay.state[:scores]

    own = scores.fetch(actor)
    margin = (scores.reject { |name, _| name == actor }.values.min - own)
    {score: own, margin: margin, rounds: deltas}
  end

  def summarize(rows, times)
    ordered = times.sort
    percentile = ->(fraction) { ordered[[(ordered.length * fraction).ceil - 1, 0].max]&.round(3) }
    {wins: rows.count { |row| row[:margin].positive? }, ties: rows.count { |row| row[:margin].zero? },
      mean_score: mean(rows.map { |row| row[:score] }), mean_margin: mean(rows.map { |row| row[:margin] }),
      mean_round_points: rows.map { |row| row[:rounds] }.transpose.map { |points| mean(points) },
      decisions: ordered.size, p50_ms: percentile.call(0.5), p95_ms: percentile.call(0.95), max_ms: ordered.last&.round(3)}
  end

  def mean(values)
    values.sum.fdiv(values.size).round(3)
  end

  def policy(name)
    name == 'tactics' ? TacticsOnly.new : RankOnly.new
  end
end

GameRoomBouillabaisseBenchmark.run(ARGV) if $PROGRAM_NAME == __FILE__
